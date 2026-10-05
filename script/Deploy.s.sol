// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IMD} from "../src/IMD.sol";

/// @notice Standalone deployment helper. Network factory launches use IMD's
/// creation bytecode directly so the factory receives the constructor mint.
contract Deploy is Script {
    error UnsupportedChain(uint256 actual);
    error ChainMismatch(uint256 expected, uint256 actual);

    function run() external returns (IMD token) {
        return deploy(vm.envOr("EXPECTED_CHAIN_ID", uint256(0)));
    }

    /// @param expectedChainId Zero skips equality checking, but still restricts
    /// deployment to local development (31337) or Sepolia (11155111).
    function deploy(uint256 expectedChainId) public returns (IMD token) {
        if (block.chainid != 31337 && block.chainid != 11155111) {
            revert UnsupportedChain(block.chainid);
        }
        if (expectedChainId != 0 && block.chainid != expectedChainId) {
            revert ChainMismatch(expectedChainId, block.chainid);
        }

        vm.startBroadcast();
        token = new IMD();
        vm.stopBroadcast();
    }
}
