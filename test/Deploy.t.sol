// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {IMD} from "../src/IMD.sol";

contract DeployTest is Test {
    Deploy private deployment;

    function setUp() public {
        deployment = new Deploy();
    }

    function test_DeployOnLocalChain() public {
        vm.chainId(31337);
        IMD token = deployment.deploy(31337);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(token.name(), "IMD");
        assertEq(token.balanceOf(address(deployment)), 0);
    }

    function test_DeployOnSepolia() public {
        vm.chainId(11155111);
        IMD token = deployment.deploy(11155111);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
    }

    function test_ZeroExpectedChainAllowsLocalSimulation() public {
        vm.chainId(31337);
        assertEq(deployment.deploy(0).totalSupply(), 1_000_000_000 * 10 ** 18);
    }

    function test_WrongExpectedChainReverts() public {
        vm.chainId(31337);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ChainMismatch.selector, 11155111, 31337));
        deployment.deploy(11155111);
    }

    function test_UnsupportedChainRevertsEvenWithZeroExpectation() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnsupportedChain.selector, 1));
        deployment.deploy(0);
    }
}
