// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "../src/MortalWoundToken.sol";
import "../src/TokenVesting.sol";

contract DeployMWND is Script {
    function run() external {
        // Load environment variables from .env
        address admin = vm.envAddress("ADMIN");
        uint256 initialSupply = vm.envUint("INITIAL_SUPPLY");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy token
        MortalWoundToken token = new MortalWoundToken(admin);
        emit log_named_address("MortalWoundToken deployed at", address(token));

        // Deploy vesting
        TokenVesting vest = new TokenVesting(IERC20(address(token)));
        emit log_named_address("TokenVesting deployed at", address(vest));

        // Mint initial supply to vesting contract
        token.mint(address(vest), initialSupply);
        emit log_named_uint("Minted initial supply to vesting contract", initialSupply);

        // Transfer vesting ownership to admin
        vest.transferOwnership(admin);
        emit log_named_address("Ownership of vesting transferred to admin", admin);

        vm.stopBroadcast();
    }
}
