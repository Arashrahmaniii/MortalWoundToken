# Mortal Wound Token (MWND)

> A secure, pausable, and vesting-enabled ERC20 token built with Solidity and OpenZeppelin v5, powered by Foundry.

---

## Overview

**Mortal Wound (MWND)** is an ERC20 token with advanced features designed for long-term, secure token distribution.  
It includes minting, burning, pausing, and a **linear vesting system** to manage time-based token releases for team members or investors.

### 🔹 Key Features
- ERC20-compliant (OpenZeppelin v5)
-Role-based access control (`AccessControl`)
-Mintable & Burnable
-Pausable transfers for emergency stops
-Linear Vesting with cliff, duration, and revocable grants
-Reentrancy protected
-Fully tested with Foundry

---

## Project Structure


├── foundry.toml
├── src/
│ ├── MortalWoundToken.sol # Main ERC20 token contract
│ └── TokenVesting.sol # Linear vesting contract
├── test/
│ └── MortalWoundTokenAndVesting.t.sol # Unit tests for token and vesting
└── script/
└── DeployMWND.s.sol # Deployment script

---

## Installation

Make sure you have **Foundry** installed:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup

Clone this repository and install dependencies:

git clone https://github.com/Arashrahmaniii/MortalWoundToken.git
cd MortalWoundToken
forge install OpenZeppelin/openzeppelin-contracts


This project is licensed under the MIT License.
You’re free to use, modify, and distribute it with attribution


Author : Arash Rahmani