// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "../src/MortalWoundToken.sol";
import "../src/TokenVesting.sol";

contract DeployMWND is Script {
    function run() external {
        // Load environment variables
        address admin = vm.envAddress("ADMIN");
        uint256 initialSupply = vm.envUint("INITIAL_SUPPLY");

        // The broadcaster must be the admin: only MINTER_ROLE can mint the initial supply.
        vm.startBroadcast(admin);

        // Deploy token
        MortalWoundToken token = new MortalWoundToken(admin);
        console2.log("MortalWoundToken deployed at", address(token));

        // Deploy vesting
        TokenVesting vest = new TokenVesting(IERC20(address(token)));
        console2.log("TokenVesting deployed at", address(vest));

        // Fund the vesting contract; grants can only be added against funded tokens
        token.mint(address(vest), initialSupply);
        console2.log("Minted to vesting contract", initialSupply);

        // Transfer vesting ownership to admin
        vest.transferOwnership(admin);
        console2.log("Vesting owner", admin);

        vm.stopBroadcast();
    }
}
