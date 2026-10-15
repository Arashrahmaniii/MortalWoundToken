// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
import "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../src/MortalWoundToken.sol";
import "../src/TokenVesting.sol";

/// Regression tests for the issues found in the 2026-10 self-review of TokenVesting,
/// plus pause coverage for the token.
contract TokenVestingSecurityTest is Test {
    MortalWoundToken token;
    TokenVesting vest;
    address admin = address(0xA11CE);
    address alice = address(0xBEEF);
    address bob = address(0xCAFE);

    uint256 constant START = 1_000_000;

    function setUp() public {
        token = new MortalWoundToken(admin);
        vest = new TokenVesting(IERC20(address(token)));
        vest.transferOwnership(admin);
        vm.warp(START);
    }

    function _fund(uint256 amount) internal {
        vm.prank(admin);
        token.mint(address(vest), amount);
    }

    // ---------------------------------------------------------------------------------
    // Revoke must not take tokens the beneficiary already earned.
    // Before the fix, revoking at 90% vested sent all 1000 tokens to the owner.
    // ---------------------------------------------------------------------------------
    function test_revoke_paysVestedToBeneficiary() public {
        _fund(1000 ether);
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, START, START, 1000, true);

        vm.warp(START + 900); // 90% vested, nothing released yet
        vm.prank(admin);
        vest.revoke(alice);

        assertEq(token.balanceOf(alice), 900 ether, "beneficiary keeps vested tokens");
        assertEq(token.balanceOf(admin), 100 ether, "owner gets only the unvested part");
        assertEq(vest.totalCommitted(), 0);
        assertEq(token.balanceOf(address(vest)), 0);
    }

    function test_revoke_afterPartialRelease() public {
        _fund(1000 ether);
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, START, START, 1000, true);

        vm.warp(START + 300);
        vm.prank(alice);
        vest.release(); // 300

        vm.warp(START + 600);
        vm.prank(admin);
        vest.revoke(alice);

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token.balanceOf(admin), 400 ether);
    }

    function test_revoke_beforeCliffRefundsEverything() public {
        _fund(1000 ether);
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, START, START + 100, 1000, true);

        vm.warp(START + 50);
        vm.prank(admin);
        vest.revoke(alice);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(admin), 1000 ether);
    }

    function test_revoke_nonRevocableReverts() public {
        _fund(1000 ether);
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, START, START, 1000, false);
        vm.prank(admin);
        vm.expectRevert("not-revocable");
        vest.revoke(alice);
    }

    // ---------------------------------------------------------------------------------
    // Grants must be backed by tokens.
    // Before the fix, two 1000-token grants could be backed by 1000 tokens.
    // ---------------------------------------------------------------------------------
    function test_addGrant_rejectsUnfundedGrant() public {
        _fund(1000 ether);
        vm.startPrank(admin);
        vest.addGrant(alice, 1000 ether, START, START, 100, false);
        vm.expectRevert("grant-not-funded");
        vest.addGrant(bob, 1 ether, START, START, 100, false);
        vm.stopPrank();
    }

    function test_releasedTokensFreeCommitment() public {
        _fund(1000 ether);
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, START, START, 100, false);

        vm.warp(START + 100);
        vm.prank(alice);
        vest.release();
        assertEq(vest.totalCommitted(), 0);

        // a new grant needs new funding
        vm.prank(admin);
        vm.expectRevert("grant-not-funded");
        vest.addGrant(bob, 1 ether, START + 100, START + 100, 100, false);
    }

    function test_recoverUnallocated_onlyExcess() public {
        _fund(1500 ether);
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, START, START, 100, false);

        vm.prank(admin);
        vest.recoverUnallocated(admin);
        assertEq(token.balanceOf(admin), 500 ether);

        vm.prank(admin);
        vm.expectRevert("nothing-to-recover");
        vest.recoverUnallocated(admin);

        // the grant is still fully payable
        vm.warp(START + 100);
        vm.prank(alice);
        vest.release();
        assertEq(token.balanceOf(alice), 1000 ether);
    }

    // ---------------------------------------------------------------------------------
    // Schedule bounds. Before the fix, a cliff after the end was accepted.
    // ---------------------------------------------------------------------------------
    function test_addGrant_rejectsCliffAfterEnd() public {
        _fund(1000 ether);
        vm.prank(admin);
        vm.expectRevert("cliff-after-end");
        vest.addGrant(alice, 1000 ether, START, START + 101, 100, false);
    }

    // ---------------------------------------------------------------------------------
    // Fuzz: whatever the revoke time, beneficiary + owner always receive exactly the grant,
    // and the beneficiary gets at least what had vested.
    // ---------------------------------------------------------------------------------
    function testFuzz_revoke_conservesTokens(uint256 total, uint256 duration, uint256 releaseAt, uint256 revokeAt)
        public
    {
        total = bound(total, 1, 1e30);
        duration = bound(duration, 1, 10 * 365 days);
        releaseAt = bound(releaseAt, 0, 2 * duration);
        revokeAt = bound(revokeAt, releaseAt, 2 * duration);

        _fund(total);
        vm.prank(admin);
        vest.addGrant(alice, total, START, START, duration, true);

        vm.warp(START + releaseAt);
        if (vest.releasableAmount(alice) > 0) {
            vm.prank(alice);
            vest.release();
        }

        vm.warp(START + revokeAt);
        uint256 vestedAtRevoke = revokeAt >= duration ? total : (total * revokeAt) / duration;
        vm.prank(admin);
        vest.revoke(alice);

        assertEq(token.balanceOf(alice) + token.balanceOf(admin), total, "conservation");
        assertEq(token.balanceOf(alice), vestedAtRevoke, "beneficiary gets all vested");
        assertEq(vest.totalCommitted(), 0);
    }

    // ---------------------------------------------------------------------------------
    // Token pause covers transfers, mint and burn through ERC20Pausable._update.
    // ---------------------------------------------------------------------------------
    function test_pause_blocksAllBalanceChanges() public {
        vm.prank(admin);
        token.mint(alice, 10 ether);
        vm.prank(admin);
        token.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.transfer(bob, 1 ether);

        vm.prank(admin);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(bob, 1 ether);

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.burn(1 ether);

        vm.prank(admin);
        token.unpause();
        vm.prank(alice);
        token.transfer(bob, 1 ether);
        assertEq(token.balanceOf(bob), 1 ether);
    }
}
