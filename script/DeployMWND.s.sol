// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MortalWoundToken.sol";
import "../src/TokenVesting.sol";

contract DeployMWND is Script {
    function run() external {
        // configure these before running or pass as env vars
        address admin = vm.envAddress("0xC89CC60fA118C20a0F71e6b4d9359F89E6F734ac");
        uint256 initialSupply = vm.envUint("10000000000000000000000"); // e.g. 10000000000000000000000 (10_000 ether)

        vm.startBroadcast();

        MortalWoundToken token = new MortalWoundToken(admin);

        TokenVesting vest = new TokenVesting(IERC20(address(token)));

        // Mint initial supply directly to vesting contract
        // Only account with MINTER_ROLE (admin) can mint: we are broadcasting from your private key,
        // so ensure the private key corresponds to the admin role or that you call via admin key.
        // If you run this script while broadcasting, make sure the private key used matches admin.
        token.mint(address(vest), initialSupply);

        // Transfer owner of vesting to admin so admin can add grants
        vest.transferOwnership(admin);

        vm.stopBroadcast();
    }
}
