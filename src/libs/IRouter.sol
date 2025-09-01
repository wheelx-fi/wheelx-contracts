// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRouter {
    function safeMultiCall(bytes calldata calls, address payable refundTo, bytes32 request_id) external payable returns (bytes memory returnData);
}
