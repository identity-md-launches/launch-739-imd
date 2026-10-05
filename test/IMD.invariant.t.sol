// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IMD} from "../src/IMD.sol";

/// @dev Restricts all transfers to three actors, including self-transfers, so
/// aggregate balances can be checked after arbitrary operation sequences.
contract IMDHandler is Test {
    IMD public immutable token;
    address[3] public actors = [address(0x10001), address(0x10002), address(0x10003)];

    constructor(IMD token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        vm.prank(actors[ownerSeed % 3]);
        assertTrue(token.approve(actors[spenderSeed % 3], amount));
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 available = token.balanceOf(from);
        uint256 approved = token.allowance(from, spender);
        amount = bound(amount, 0, available < approved ? available : approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.allowance(from, spender), approved == type(uint256).max ? approved : approved - amount);
    }
}

contract IMDInvariantTest is Test {
    IMD private token;
    IMDHandler private handler;
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new IMD();
        handler = new IMDHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IMDHandler.transfer.selector;
        selectors[1] = IMDHandler.approve.selector;
        selectors[2] = IMDHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TotalSupplyEqualsAllHolderBalances() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 3; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
