// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @title TokenVesting - linear vesting with a cliff and optionally revocable grants
/// @notice Every grant is backed by tokens held in this contract: the owner must fund the
///         contract before adding a grant, so the total promised can never exceed the balance.
///         Revoking a grant pays the beneficiary everything already vested and returns only the
///         unvested remainder to the owner.
contract TokenVesting is Ownable(msg.sender), ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    struct Grant {
        uint256 total; // total tokens assigned (reduced to the vested amount on revoke)
        uint256 released; // already released
        uint256 start; // vesting start timestamp
        uint256 cliff; // cliff timestamp
        uint256 duration; // duration in seconds
        bool revocable; // whether owner can revoke
        bool revoked; // whether revoked
    }

    mapping(address => Grant) public grants;

    /// @notice Tokens promised to beneficiaries and not yet released.
    uint256 public totalCommitted;

    event GrantAdded(
        address indexed beneficiary, uint256 total, uint256 start, uint256 cliff, uint256 duration, bool revocable
    );
    event Released(address indexed beneficiary, uint256 amount);
    event Revoked(address indexed beneficiary, uint256 vestedPaid, uint256 unvestedRefunded);
    event UnallocatedRecovered(address indexed to, uint256 amount);

    constructor(IERC20 token_) {
        require(address(token_) != address(0), "token-zero");
        token = token_;
    }

    /// @notice Add a grant for a beneficiary. Only owner (admin) can call.
    /// @dev The contract must already hold enough unallocated tokens to cover `total`.
    function addGrant(
        address beneficiary,
        uint256 total,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable
    ) external onlyOwner {
        require(beneficiary != address(0), "beneficiary-zero");
        require(total > 0, "total-zero");
        require(duration > 0, "duration-zero");
        require(grants[beneficiary].total == 0, "grant-exists");
        require(cliff >= start, "cliff-before-start");
        require(cliff <= start + duration, "cliff-after-end");
        require(token.balanceOf(address(this)) >= totalCommitted + total, "grant-not-funded");

        totalCommitted += total;
        grants[beneficiary] = Grant({
            total: total,
            released: 0,
            start: start,
            cliff: cliff,
            duration: duration,
            revocable: revocable,
            revoked: false
        });

        emit GrantAdded(beneficiary, total, start, cliff, duration, revocable);
    }

    /// @notice View how many tokens are releasable to beneficiary now
    function releasableAmount(address beneficiary) public view returns (uint256) {
        Grant storage g = grants[beneficiary];
        if (g.total == 0 || g.revoked) return 0;
        uint256 vested = _vestedAmount(g);
        return vested > g.released ? vested - g.released : 0;
    }

    /// @dev Calculates vested amount based on linear vesting
    function _vestedAmount(Grant storage g) internal view returns (uint256) {
        if (block.timestamp < g.cliff) {
            return 0;
        }
        uint256 end = g.start + g.duration;
        if (block.timestamp >= end) {
            return g.total;
        }
        uint256 elapsed = block.timestamp - g.start;
        return (g.total * elapsed) / g.duration;
    }

    /// @notice Release vested tokens for msg.sender (beneficiary)
    function release() external nonReentrant {
        Grant storage g = grants[msg.sender];
        require(g.total > 0, "no-grant");
        require(!g.revoked, "revoked");

        uint256 vested = _vestedAmount(g);
        uint256 releasable = vested > g.released ? vested - g.released : 0;
        require(releasable > 0, "no-tokens-to-release");

        g.released += releasable;
        totalCommitted -= releasable;
        token.safeTransfer(msg.sender, releasable);

        emit Released(msg.sender, releasable);
    }

    /// @notice Revoke a revocable grant. The beneficiary receives everything vested so far;
    ///         only the unvested remainder returns to the owner.
    function revoke(address beneficiary) external onlyOwner nonReentrant {
        Grant storage g = grants[beneficiary];
        require(g.total > 0, "no-grant");
        require(g.revocable, "not-revocable");
        require(!g.revoked, "already-revoked");

        uint256 vested = _vestedAmount(g);
        uint256 vestedUnreleased = vested - g.released;
        uint256 unvested = g.total - vested;

        // Effects before interactions: close the grant at the vested amount.
        g.revoked = true;
        g.total = vested;
        g.released = vested;
        totalCommitted -= vestedUnreleased + unvested;

        if (vestedUnreleased > 0) token.safeTransfer(beneficiary, vestedUnreleased);
        if (unvested > 0) token.safeTransfer(owner(), unvested);

        emit Revoked(beneficiary, vestedUnreleased, unvested);
    }

    /// @notice Return tokens that are not committed to any grant.
    function recoverUnallocated(address to) external onlyOwner nonReentrant {
        require(to != address(0), "to-zero");
        uint256 balance = token.balanceOf(address(this));
        uint256 amount = balance > totalCommitted ? balance - totalCommitted : 0;
        require(amount > 0, "nothing-to-recover");
        token.safeTransfer(to, amount);
        emit UnallocatedRecovered(to, amount);
    }
}
