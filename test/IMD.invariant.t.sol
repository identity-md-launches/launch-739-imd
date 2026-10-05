// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {IMD} from "../src/IMD.sol";

/// @dev Restricts all transfers to three actors, including self-transfers, so
/// aggregate balances can be checked after arbitrary operation sequences.
/// The model starts from the requested supply and records authorized movements,
/// never copying balances or allowances back from the implementation.
contract IMDHandler is Test {
    IMD public immutable token;
    address[3] public actors = [address(0x10001), address(0x10002), address(0x10003)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMD token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(actors[ownerSeed % 3], actors[spenderSeed % 3], amount);
    }

    function approveInfinite(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % 3], actors[spenderSeed % 3], type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % 3], actors[spenderSeed % 3], 0);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        address to = actors[toSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 available = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        amount = bound(amount, 0, available < approved ? available : approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) expectedAllowance[from][spender] -= amount;
        _move(from, to, amount);
    }

    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 3];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(actors[toSeed % 3], amount);
    }

    /// @dev Always picks a funded owner so insufficient balance cannot mask the
    /// allowance failure. The preparatory approval is retained in the model.
    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 approved, uint256 amount) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % 3];
        approved = bound(approved, 0, expectedBalance[owner] - 1);
        amount = bound(amount, approved + 1, expectedBalance[owner]);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    /// @dev Approval is sufficient, but a later balance check must fail and
    /// restore the allowance spent earlier in the same transaction.
    function transferFromOverdraw(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function invalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 3]);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) private {
        // Self-transfers authorize a movement but must leave holdings unchanged.
        if (from != to) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        for (uint256 i; i < 3; ++i) {
            address actor = actors[(seed % 3 + i) % 3];
            if (expectedBalance[actor] > 0) return actor;
        }
        revert("model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDInvariantTest is Test {
    IMD private token;
    IMDHandler private handler;
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new IMD();
        handler = new IMDHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = IMDHandler.transfer.selector;
        selectors[1] = IMDHandler.approve.selector;
        selectors[2] = IMDHandler.transferFrom.selector;
        selectors[3] = IMDHandler.approveInfinite.selector;
        selectors[4] = IMDHandler.revoke.selector;
        selectors[5] = IMDHandler.overdraw.selector;
        selectors[6] = IMDHandler.overspendAllowance.selector;
        selectors[7] = IMDHandler.transferFromOverdraw.selector;
        selectors[8] = IMDHandler.invalidRecipient.selector;
        selectors[9] = IMDHandler.approveZeroSpender.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_BalancesMatchAuthorizedMovements() public view {
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder balance diverged");
        }
    }

    function invariant_AllowancesMatchGrantsAndSuccessfulSpends() public view {
        for (uint256 i; i < 3; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 3; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "allowance diverged"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
        }
    }

    /// @dev A deterministic walk proves the handler can move nonzero value,
    /// consume finite approval, retain infinite approval, reject calls, and
    /// then continue with valid calls. No random-seed-dependent hit assertions.
    function test_HandlerExercisesSuccessAndFailurePaths() public {
        handler.transfer(0, 1, 100);
        handler.approve(1, 2, 40);
        handler.transferFrom(1, 0, 2, 15);
        assertEq(token.balanceOf(handler.actors(1)), 85);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 25);
        handler.approveInfinite(1, 2);
        handler.transferFrom(1, 2, 2, 1);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
        handler.overdraw(1, 1, type(uint256).max);
        handler.overspendAllowance(1, 2, 1, 2);
        handler.transferFromOverdraw(1, 2, type(uint256).max - 1);
        handler.invalidRecipient(1, 2, 1, true);
        handler.invalidRecipient(1, 2, 0, false);
        handler.approveZeroSpender(1, type(uint256).max);
        handler.revoke(1, 2);
        handler.transfer(1, 1, 84);
        handler.transfer(1, 0, 84);
        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);
        invariant_TotalSupplyEqualsAllHolderBalances();
        invariant_BalancesMatchAuthorizedMovements();
        invariant_AllowancesMatchGrantsAndSuccessfulSpends();
    }
}
