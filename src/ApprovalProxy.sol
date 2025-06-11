// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IRouter} from "./libs/IRouter.sol";

contract ApprovalProxy is Ownable {
    using SafeTransferLib for address;

    event RouterUpdated(address newRouter);
    error ArrayLengthsMismatch();
    error RefundToCannotBeZeroAddress();
    error NativeTransferFailed();

    address public router;

    constructor(address _owner, address _router) {
        _initializeOwner(_owner);
        router = _router;
    }

    // allow refund eth
    receive() external payable {}

    function withdraw() external onlyOwner {
        _send(msg.sender, address(this).balance);
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;

        emit RouterUpdated(_router);
    }

    function transferAndMulticall(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata calls,
        address refundTo,
        bytes32 request_id
    ) external payable returns (bytes memory) {
        // Revert if array lengths do not match
        if ((tokens.length != amounts.length)) {
            revert ArrayLengthsMismatch();
        }

        // Transfer the tokens to the router
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeTransferFrom(msg.sender, router, amounts[i]);
        }

        // Call multicall on the router
        // @dev msg.sender for the calls to targets will be the router
        return IRouter(router).safeMultiCall{value: msg.value}(
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
            success := call(100000, to, value, 0, 0, 0, 0)
        }

        if (!success) {
            revert NativeTransferFailed();
        }
    }
}
