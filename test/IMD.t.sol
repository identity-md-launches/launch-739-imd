// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {IMD} from "../src/IMD.sol";

contract TokenFactory {
    function deploy() external returns (IMD) {
        return new IMD();
    }
}

contract IMDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    IMD private token;

    function setUp() public {
        token = new IMD();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "IMD");
        assertEq(token.symbol(), "IMD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsSingleMint() public {
        vm.recordLogs();
        IMD fresh = new IMD();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesEntireSupply() public {
        TokenFactory factory = new TokenFactory();
        vm.prank(ALICE);
        IMD fresh = factory.deploy();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(ALICE), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_TransferEmitsEventAndReturnsTrue() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 20 ether);
        assertTrue(token.transfer(ALICE, 20 ether));
        assertEq(token.balanceOf(ALICE), 20 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 50 ether));
        assertEq(token.allowance(address(this), SPENDER), 50 ether);
        assertTrue(token.approve(SPENDER, 7 ether));
        assertEq(token.allowance(address(this), SPENDER), 7 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromSpendsAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), ALICE, 20 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), 30 ether);
        assertEq(token.balanceOf(ALICE), 20 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
    }

    function test_TransferFromSelfConsumesAllowanceWithoutMovingBalance() public {
        token.approve(SPENDER, 5 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 5 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_MaximumAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevokePreventsFurtherSpending() public {
        token.approve(SPENDER, 10 ether);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_UnapprovedSpenderCannotUseAnotherSpendersAllowance() public {
        token.approve(SPENDER, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_InsufficientAllowanceRevertsAtomically() public {
        token.approve(SPENDER, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 3, 4));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 4);
        assertEq(token.allowance(address(this), SPENDER), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_InsufficientBalanceRestoresSpentAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 50);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 50));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 50);
        assertEq(token.allowance(ALICE, SPENDER), 50);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromToZeroRestoresAllowance() public {
        token.approve(SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_InitialDistributionAndPoolCustodyHaveNoDeductions() public {
        address distributor = address(0xD157);
        address manager = address(0x9001);
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY / 2;
        token.transfer(distributor, swarmShare);
        token.transfer(manager, poolShare);
        token.transfer(ALICE, SUPPLY - swarmShare - poolShare);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(manager), poolShare);
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(distributor);
        token.transfer(BOB, swarmShare);
        assertEq(token.balanceOf(BOB), swarmShare);
        assertEq(token.balanceOf(distributor), 0);
        vm.prank(manager);
        token.transfer(BOB, 2 ether);
        assertEq(token.balanceOf(BOB), swarmShare + 2 ether);
        vm.prank(BOB);
        token.transfer(manager, 2 ether);
        assertEq(token.balanceOf(manager), poolShare);
        assertEq(token.balanceOf(BOB), swarmShare);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintOrPrivilegedBalanceControls() public {
        token.transfer(ALICE, 100 ether);
        bytes[8] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("initialize(address)", BOB)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FiniteAllowanceCannotBeOverspent(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        uint256 remaining = approved - spent;
        assertEq(token.allowance(address(this), SPENDER), remaining);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, remaining, remaining + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, remaining + 1);
        assertEq(token.allowance(address(this), SPENDER), remaining);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutChangingSupply(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
