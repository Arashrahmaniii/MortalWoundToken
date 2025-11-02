// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
import "../src/MortalWoundToken.sol";
import "../src/TokenVesting.sol";

contract MortalWoundFullTest is Test {
    MortalWoundToken token;
    TokenVesting vest;
    address admin = address(0xA11CE); // admin / deployer
    address alice = address(0xBEEF);
    address bob = address(0xCAFE);

    uint256 constant INITIAL_SUPPLY = 10_000 ether; // initial supply to mint to vesting

    function setUp() public {
        // Deploy token with admin as the role holder
        token = new MortalWoundToken(admin);

        // Deploy vesting contract (owner will be the test contract temporarily)
        vest = new TokenVesting(IERC20(address(token)));

        // Mint initial supply to vesting contract using admin role
        vm.prank(admin);
        token.mint(address(vest), INITIAL_SUPPLY);

        // Transfer ownership of vesting contract to admin so admin manages grants
        // Note: TokenVesting is Ownable and owner is initially this test contract.
        // Use vm.prank to simulate admin calling transferOwnership.
        vm.prank(address(this));
        vest.transferOwnership(admin);
    }

    function testTokenBasics() public {
        // name / symbol
        assertEq(token.name(), "Mortal Wound");
        assertEq(token.symbol(), "MWND");

        // burn: mint some to bob then burn
        vm.prank(admin);
        token.mint(bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);

        vm.prank(bob);
        token.burn(50 ether);
        assertEq(token.balanceOf(bob), 50 ether);
    }

    function testAddGrantAndReleasable() public {
        // admin will add a grant for alice
        uint256 start = block.timestamp;
        uint256 cliff = start + 100;
        uint256 duration = 1000;
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, start, cliff, duration, true);

        // before cliff, nothing releasable
        vm.warp(start + 50);
        assertEq(vest.releasableAmount(alice), 0);

        // after cliff and halfway
        vm.warp(start + 500);
        uint256 expected = (1000 ether * (550)) / duration; // linear
        assertEq(vest.releasableAmount(alice), expected);
    }

    function testReleaseFlow() public {
        // prepare grant
        uint256 start = block.timestamp;
        uint256 cliff = start;
        uint256 duration = 1000;
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, start, cliff, duration, true);

        // warp to halfway and release
        vm.warp(start + 500);
        vm.prank(alice);
        vest.release();

        // alice should have received 500
        assertEq(token.balanceOf(alice), 500 ether);

        // warp to end and release remaining
        vm.warp(start + 1000);
        vm.prank(alice);
        vest.release();
        assertEq(token.balanceOf(alice), 1000 ether);
    }

    function testRevokeGrantReturnsUnreleasedToAdmin() public {
        // add a revocable grant
        uint256 start = block.timestamp;
        uint256 cliff = start;
        uint256 duration = 1000;
        vm.prank(admin);
        vest.addGrant(alice, 1000 ether, start, cliff, duration, true);

        // warp half, then revoke
        vm.warp(start + 500);

        // compute unreleased (should be 500)
        (uint256 total, uint256 released,,,,,) = vest.grants(alice);
        uint256 unreleased = total - released;
        assertEq(unreleased, 1000 ether - 0);

        vm.prank(admin);
        vest.revoke(alice);

        // after revoke, alice can't release
        vm.prank(alice);
        vm.expectRevert("revoked");
        vest.release();

        // admin should receive remaining tokens (note: admin didn't have initial supply)
        // Balance of admin increased by unreleased (1000 ether) since alice had released nothing
        assertEq(token.balanceOf(admin), unreleased);
    }
}
