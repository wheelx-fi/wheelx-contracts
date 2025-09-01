// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IRouter} from "./libs/IRouter.sol";

contract ApprovalProxy is Ownable {
    uint256 constant SEND_GAS = 100000;

    using SafeTransferLib for address;

    event RouterUpdated(IRouter newRouter);
    error ArrayLengthsMismatch();
    error NativeTransferFailed();

    IRouter public router;

    struct TokenTransfer {
        address token;
        uint256 amount;
    }

    constructor(address _owner, IRouter _router) {
        _initializeOwner(_owner);
        router = _router;
    }

    // allow refund eth
    receive() external payable {
        // only accept eth from router
        if (msg.sender != address(router)) {
            revert NativeTransferFailed();
        }
    }

    function withdraw() external onlyOwner returns (uint256) {
        _send(msg.sender, address(this).balance);
        return address(this).balance;
    }

    function setRouter(IRouter _router) external onlyOwner {
        router = _router;

        emit RouterUpdated(_router);
    }

    function transferAndMulticall(
        TokenTransfer[] calldata transfers,
        bytes calldata calls,
        address payable refundTo,
        bytes32 request_id
    ) external payable returns (bytes memory) {
        // Transfer the tokens to the router
        for (uint256 i = 0; i < transfers.length; i++) {
            transfers[i].token.safeTransferFrom(msg.sender, address(router), transfers[i].amount);
        }

        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        return router.safeMultiCall{value: msg.value}(
            calls,
            refundTo,
            request_id
        );
    }

    function _send(address to, uint256 value) internal {
        bool success;
        assembly {
            // Save gas by avoiding copying the return data to memory.
            // Provide at most 100k gas to the internal call, which is
            // more than enough to cover common use-cases of logic for
            // receiving native tokens (eg. SCW payable fallbacks).
            success := call(SEND_GAS, to, value, 0, 0, 0, 0)
        }

        if (!success) {
            revert NativeTransferFailed();
        }
    }
}
