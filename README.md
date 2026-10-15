# Mortal Wound Token (MWND)

An ERC-20 with role-based minting and pausing, plus a linear vesting contract with cliffs and revocable grants. Built on OpenZeppelin v5 with Foundry.

## Contracts

| Contract | What it does |
|---|---|
| `MortalWoundToken` | ERC-20 + `ERC20Burnable` + `ERC20Pausable` + `AccessControl`. `MINTER_ROLE` mints, `PAUSER_ROLE` pauses. Pausing blocks every balance change (transfer, mint, burn) through the single `_update` hook. |
| `TokenVesting` | Linear vesting per beneficiary, with a cliff, a duration, and an optional revoke right for the owner. |

## Vesting guarantees

- **Every grant is funded.** `addGrant` reverts unless the contract holds enough unallocated tokens (`totalCommitted` tracks what is still owed). The total promised can never exceed the balance.
- **Revoking never takes earned tokens.** `revoke` pays the beneficiary everything vested so far, and returns only the unvested remainder to the owner.
- **Sane schedules.** `start <= cliff <= start + duration`.
- **Excess recovery.** `recoverUnallocated` returns only tokens not committed to any grant.
- Releases use `SafeERC20` and are reentrancy-guarded; state is updated before every transfer.

These guarantees came out of a self-review. The original version let `revoke` take vested-but-unreleased tokens, accepted unfunded grants, and accepted a cliff after the end date. Each issue has a regression test in [`test/TokenVestingSecurity.t.sol`](test/TokenVestingSecurity.t.sol), plus a fuzz test that, for any revoke time, beneficiary + owner receive exactly the grant and the beneficiary receives everything vested.

## Tests

```bash
git clone --recursive https://github.com/Arashrahmaniii/MortalWoundToken.git
cd MortalWoundToken
forge test
```

14 tests: unit tests for the token and vesting flows, 9 regression tests, and 1 fuzz test.

The tests use a fixed start timestamp. With `via_ir`, writing `uint256 start = block.timestamp` and then calling `vm.warp` can re-read the warped timestamp, which silently shifts every expected value.

## Deploy

```bash
ADMIN=<admin address> INITIAL_SUPPLY=<amount in wei> forge script script/DeployMWND.s.sol --rpc-url <rpc> --broadcast
```

The broadcasting account must be `ADMIN`, because the script mints the initial supply into the vesting contract.

## License

MIT · Arash Rahmani
