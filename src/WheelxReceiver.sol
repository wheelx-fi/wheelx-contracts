// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract WheelxReceiver {
    // --- Errors ---

    struct Call {
        address to;
        bytes data;
        uint256 value;
    }

    error CallFailed();
    error Unauthorized();
    error NativeTransferFailed();

    // --- Events ---

    event WheelxDeposit(bytes32 indexed data, uint256 amount);

    // --- Fields ---

    address private immutable SOLVER;

    // --- Constructor ---

    constructor(address solver) {
        SOLVER = solver;
    }

    // --- Public methods ---

    fallback() payable external {
        send(SOLVER, msg.value);
        emit WheelxDeposit(to_bytes32(msg.data), msg.value);
    }

    function forward(bytes calldata data) payable external {
        send(SOLVER, msg.value);
        emit WheelxDeposit(to_bytes32(data), msg.value);
    }

    function makeCalls(Call[] calldata calls) external payable {
        if (msg.sender != SOLVER) {
            revert Unauthorized();
        }

        unchecked {
            uint256 length = calls.length;
            for (uint256 i; i < length; i++) {
                Call memory c = calls[i];

                (bool success, ) = c.to.call{value: c.value}(c.data);
                if (!success) {
                    revert CallFailed();
                }
            }
        }
    }
    // --- Internal methods ---

    function to_bytes32(bytes memory data) internal pure returns (bytes32 converted) {
        assembly {
            converted := mload(add(data, 32))
        }
    }

    function send(address to, uint256 value) internal {
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
