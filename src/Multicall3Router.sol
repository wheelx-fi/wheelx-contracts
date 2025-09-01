// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IRouter} from "./libs/IRouter.sol";
import {Panic} from "./libs/Panic.sol";
import {Revert} from "./libs/Revert.sol";
import {SafeApproveLib} from "./libs/SafeApproveLib.sol";

contract Multicall3Router is IRouter {
    using Revert for bool;
    using SafeTransferLib for address;
    using SafeApproveLib for IERC20;

    uint256 internal constant BASIS = 10_000;

    error CallFailed(bytes returnData);
    error InvalidOffset();
    error InvalidTarget();
    error ArrayLengthsMismatch();

    event WheelxRouter(bytes32 indexed request_id);

    address public immutable multicall3;
    IPermit2 public immutable permit2;

    // Set the Multicall3 address (e.g., 0xcA11bde05977b3631167028862bE2a173976CA11)
    constructor(address _multicall3, IPermit2 _permit2) {
        multicall3 = _multicall3;
        permit2 = _permit2;
    }

    // Allow ETH transfers
    receive() external payable {
        // accept ETH
    }

    // a safer version of multicall3, which makes sure remaining eth is sent away.
    function safeMultiCall(
        bytes calldata calls,
        address payable refundTo,
        bytes32 request_id
    ) external payable returns (bytes memory) {
        // perform multicall
        (bool success, bytes memory returnData) = multicall3.delegatecall(calls);
        if (!success) {
            revert CallFailed(returnData);
        }
        if (address(this).balance > 0) {
            // If refundTo is address(0), refund to msg.sender
            address refundAddr = refundTo == address(0) ? msg.sender : refundTo;
            refundAddr.safeTransferETH(address(this).balance);
        }

        emit WheelxRouter(request_id);
        return returnData;
    }

    function sellToPool(IERC20 sellToken, uint256 bps, address pool, uint256 offset, bytes memory data) external {
        bool success;
        bytes memory returnData;
        uint256 value;

        if (address(sellToken) == address(0)) {
            value = (address(this).balance * bps) / BASIS;
            if (data.length == 0) {
                if (offset != 0) revert InvalidOffset();
                (success, returnData) = payable(pool).call{value: value}("");
                success.maybeRevert(returnData);
                return;
            } else {
                if ((offset += 32) > data.length) {
                    Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
                }
                assembly ("memory-safe") {
                    mstore(add(data, offset), value)
                }
            }
        } else {
            uint256 amount = sellToken.balanceOf(address(this)) * bps / BASIS;
            if ((offset += 32) > data.length) {
                Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
            }
            assembly ("memory-safe") {
                mstore(add(data, offset), amount)
            }
            if (address(sellToken) != pool) {
                sellToken.safeApproveIfBelow(pool, amount);
            }
        }

        (success, returnData) = payable(pool).call{value: value}(data);
        success.maybeRevert(returnData);
        // forbid sending data to EOAs
        if (returnData.length == 0 && pool.code.length == 0) revert InvalidTarget();
    }

    function cleanupERC20(IERC20 token, address refundTo) external returns (uint256) {
        // Check the router's balance for the token
        uint256 balance = token.balanceOf(address(this));

        // Transfer the token to the refundTo address
        if (balance > 0) {
            address(token).safeTransfer(refundTo, balance);
        }

        return balance;
    }

    function safeApproveIfBelow(IERC20 token, address spender, uint256 amount) external {
        token.safeApproveIfBelow(spender, amount);
    }

    function safeApprovePermit2(IERC20 token, address spender, uint256 amount) external {
        // Approve the spender to spend the specified amount of tokens through permit2
        token.safeApproveIfBelow(address(permit2), amount);
        (uint256 allowance, uint48 expiration,) = permit2.allowance(address(this), address(token), spender);
        if (allowance < amount || expiration <= block.timestamp) {
            permit2.approve(address(token), spender, type(uint160).max, type(uint48).max);
        }
    }

    struct TokenTransfer {
        IERC20 token;
        address recipient;
        uint256 amount;
    }

    function cleanupErc20s(
        TokenTransfer[] calldata transfers
    ) public virtual {
        for (uint256 i; i < transfers.length; i++) {
            TokenTransfer memory t = transfers[i];

            // Get the amount to transfer
            uint256 amount = t.amount == 0
                ? t.token.balanceOf(address(this))
                : t.amount;

            // Transfer the token to the recipient address
            address(t.token).safeTransfer(t.recipient, amount);
        }
    }
}
