// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {IMD} from "../src/IMD.sol";

/// @dev Complements the original suite with approval lifetime, aliasing, and
/// arithmetic boundaries. Fuzz inputs are bounded without discarded cases.
/// forge-config: default.fuzz.runs = 1000
contract IMDAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    IMD private token;

    function setUp() public {
        token = new IMD();
    }

    function test_ZeroOneAndFullSupplyRoundTrips() public {
        _roundTrip(0);
        _roundTrip(1);
        _roundTrip(SUPPLY);
    }

    function testFuzz_RoundTripHasNoFeeOrDust(uint256 amount) public {
        _roundTrip(bound(amount, 0, SUPPLY));
    }

    function test_MaxMinusOneApprovalIsFinite() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumSpendCannotOverflowOrBypassBalanceCheck() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevokingInfiniteApprovalStopsFurtherSpending() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_OneWeiAllowanceCannotBeSpentTwice() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_SelfTransferFromRequiresAndConsumesSelfAllowance() public {
        token.transfer(ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, ALICE, 1);
        vm.prank(ALICE);
        assertTrue(token.approve(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transferFrom(ALICE, ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(ALICE, ALICE), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroAddressArgumentsAreRejectedEvenForZeroAmounts() public {
        // A zero sender or receiver is invalid even when no value moves.
        // The particular validation order is not part of this property.
        vm.expectRevert();
        vm.prank(SPENDER);
        token.transferFrom(address(0), BOB, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(0), SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferCannotHideOverdraw(uint256 funded, uint256 attempted) public {
        funded = bound(funded, 0, SUPPLY);
        attempted = bound(attempted, funded + 1, type(uint256).max);
        token.transfer(ALICE, funded);
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, funded, attempted);
        vm.expectRevert(expected);
        vm.prank(ALICE);
        token.transfer(ALICE, attempted);
        vm.prank(ALICE);
        token.approve(SPENDER, attempted);
        vm.expectRevert(expected);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, attempted);
        assertEq(token.balanceOf(ALICE), funded);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.allowance(ALICE, SPENDER), attempted);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendRemainsUsableAfterRefill(uint256 funded, uint256 approved) public {
        funded = bound(funded, 1, SUPPLY);
        approved = bound(approved, 1, funded);
        token.transfer(ALICE, funded);
        vm.startPrank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        assertTrue(token.transfer(BOB, funded));
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, approved));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, SPENDER, approved);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), funded);
        assertEq(token.balanceOf(SPENDER), 0);

        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, SPENDER, approved));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), funded - approved);
        assertEq(token.balanceOf(SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIsolatedAndIdempotent(uint256 first, uint256 replacement) public {
        token.transfer(ALICE, 1);
        vm.prank(BOB);
        token.approve(SPENDER, 17);
        vm.startPrank(ALICE);
        assertTrue(token.approve(BOB, 23));
        assertTrue(token.approve(SPENDER, first));
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        vm.stopPrank();
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        assertEq(token.allowance(ALICE, BOB), 23);
        assertEq(token.allowance(BOB, SPENDER), 17);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroDelegatedTransfersPreserveAnyAllowance(uint256 approved) public {
        // The owner has no tokens, but a zero transfer remains valid for every
        // approval, including zero, max - 1, and the infinite sentinel.
        vm.prank(ALICE);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, ALICE, 0));
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersCannotExceedGrant(uint256 granted, uint256 first) public {
        granted = bound(granted, 1, SUPPLY);
        first = bound(first, 0, granted);
        token.approve(SPENDER, granted);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), granted - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, granted - first));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), SPENDER, 1);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), granted - first);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - granted);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _roundTrip(uint256 amount) private {
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
