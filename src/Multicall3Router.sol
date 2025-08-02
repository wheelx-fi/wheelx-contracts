// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IRouter} from "./libs/IRouter.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";

library Panic {
    function panic(uint256 code) internal pure {
        assembly ("memory-safe") {
            mstore(0x00, 0x4e487b71) // selector for `Panic(uint256)`
            mstore(0x20, code)
            revert(0x1c, 0x24)
        }
    }

    // https://docs.soliditylang.org/en/latest/control-structures.html#panic-via-assert-and-error-via-require
    uint8 internal constant GENERIC = 0x00;
    uint8 internal constant ASSERT_FAIL = 0x01;
    uint8 internal constant ARITHMETIC_OVERFLOW = 0x11;
    uint8 internal constant DIVISION_BY_ZERO = 0x12;
    uint8 internal constant ENUM_CAST = 0x21;
    uint8 internal constant CORRUPT_STORAGE_ARRAY = 0x22;
    uint8 internal constant POP_EMPTY_ARRAY = 0x31;
    uint8 internal constant ARRAY_OUT_OF_BOUNDS = 0x32;
    uint8 internal constant OUT_OF_MEMORY = 0x41;
    uint8 internal constant ZERO_FUNCTION_POINTER = 0x51;
}

library Revert {
    function _revert(bytes memory reason) internal pure {
        assembly ("memory-safe") {
            revert(add(reason, 0x20), mload(reason))
        }
    }

    function maybeRevert(bool success, bytes memory reason) internal pure {
        if (!success) {
            _revert(reason);
        }
    }
}


library SafeApproveLib {
    function safeApprove(IERC20 token, address to, uint256 amount) internal {
        assembly ("memory-safe") {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            // Storing `amount` clobbers the upper bits of the free memory pointer, but those bits
            // can never be set without running into an OOG, so it's safe. We'll restore them to
            // zero at the end.
            mstore(0x00, 0x095ea7b3000000000000000000000000) // Selector for `approve(address,uint256)`, with `to`'s padding.

            // Calldata starts at offset 16 and is 68 bytes long (2 * 32 + 4).
            // If there is returndata (optional) we copy the first 32 bytes into the first slot of memory.
            if iszero(call(gas(), token, 0x00, 0x10, 0x44, 0x00, 0x20)) {
                let ptr := and(0xffffffffffffffffffffffff, mload(0x40))
                returndatacopy(ptr, 0x00, returndatasize())
                revert(ptr, returndatasize())
            }
            // We check that the call either returned exactly 1 [true] (can't just be non-zero
            // data), or had no return data.
            if iszero(or(and(eq(mload(0x00), 0x01), lt(0x1f, returndatasize())), iszero(returndatasize()))) {
                mstore(0x00, 0x3e3f8f73) // Selector for `ApproveFailed()`
                revert(0x1c, 0x04)
            }

            mstore(0x34, 0x00) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    function safeApproveIfBelow(IERC20 token, address spender, uint256 amount) internal {
        uint256 allowance = token.allowance(address(this), spender);
        if (allowance < amount) {
            if (allowance != 0) {
                safeApprove(token, spender, 0);
            }
            safeApprove(token, spender, type(uint256).max);
        }
    }
}

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
    receive() external payable {}

    // a safer version of multicall3, which makes sure remaining eth is sent away.
    function safeMultiCall(
        bytes calldata calls,
        address refundTo,
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

            uint256 amount = address(this).balance;
            refundAddr.safeTransferETH(amount);
        }

        emit WheelxRouter(request_id);
        return returnData;
    }

    function sellToPool(address sellToken, uint256 bps, address pool, uint256 offset, bytes memory data) external {
        bool success;
        bytes memory returnData;
        uint256 value;

        if (sellToken == address(0)) {
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
            uint256 amount = (IERC20(sellToken).balanceOf(address(this)) * bps) / BASIS;
            if ((offset += 32) > data.length) {
                Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);
            }
            assembly ("memory-safe") {
                mstore(add(data, offset), amount)
            }
            if (address(sellToken) != pool) {
                IERC20(sellToken).safeApproveIfBelow(pool, amount);
            }
        }

        (success, returnData) = payable(pool).call{value: value}(data);
        success.maybeRevert(returnData);
        // forbid sending data to EOAs
        if (returnData.length == 0 && pool.code.length == 0) revert InvalidTarget();
    }

    function cleanupERC20(address token, address refundTo) external {
        // Check the router's balance for the token
        uint256 balance = IERC20(token).balanceOf(address(this));

        // Transfer the token to the refundTo address
        if (balance > 0) {
            IERC20(token).transfer(refundTo, balance);
        }
    }

    function safeApproveIfBelow(address token, address spender, uint256 amount) external {
        IERC20(token).safeApproveIfBelow(spender, amount);
    }

    function safeApprovePermit2(address token, address spender, uint256 amount) external {
        // Approve the spender to spend the specified amount of tokens through permit2
        IERC20(token).safeApproveIfBelow(address(permit2), amount);
        (uint256 allowance, uint48 expiration,) = permit2.allowance(address(this), token, spender);
        if (allowance < amount || expiration <= block.timestamp) {
            permit2.approve(token, spender, type(uint160).max, type(uint48).max);
        }
    }

    function cleanupErc20s(
        address[] calldata tokens,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) public virtual {
        // Revert if array lengths do not match
        if (
            tokens.length != amounts.length ||
            amounts.length != recipients.length
        ) {
            revert ArrayLengthsMismatch();
        }

        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            address recipient = recipients[i];

            // Get the amount to transfer
            uint256 amount = amounts[i] == 0
                ? IERC20(token).balanceOf(address(this))
                : amounts[i];

            // Transfer the token to the recipient address
            token.safeTransfer(recipient, amount);
        }
    }
}
