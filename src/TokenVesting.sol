// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract TokenVesting is Ownable(msg.sender), ReentrancyGuard {
    IERC20 public immutable token;

    struct Grant {
        uint256 total; // total tokens assigned
        uint256 released; // already released
        uint256 start; // vesting start timestamp
        uint256 cliff; // cliff timestamp
        uint256 duration; // duration in seconds
        bool revocable; // whether owner can revoke
        bool revoked; // whether revoked
    }

    mapping(address => Grant) public grants;

    event GrantAdded(
        address indexed beneficiary, uint256 total, uint256 start, uint256 cliff, uint256 duration, bool revocable
    );
    event Released(address indexed beneficiary, uint256 amount);
    event Revoked(address indexed beneficiary, uint256 unreleased);

    constructor(IERC20 token_) {
        require(address(token_) != address(0), "token-zero");
        token = token_;
    }

    /// @notice Add a grant for a beneficiary. Only owner (admin) can call.
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
        require(token.transfer(msg.sender, releasable), "transfer-failed");

        emit Released(msg.sender, releasable);
    }

    /// @notice Revoke a revocable grant and return unreleased tokens to owner
    function revoke(address beneficiary) external onlyOwner nonReentrant {
        Grant storage g = grants[beneficiary];
        require(g.total > 0, "no-grant");
        require(g.revocable, "not-revocable");
        require(!g.revoked, "already-revoked");

        // uint256 vested = _vestedAmount(g);
        uint256 unreleased = g.total > g.released ? g.total - g.released : 0;
        // Mark revoked before transfer to avoid reentrancy issues on custom tokens
        g.revoked = true;

        // Transfer the remaining (unreleased) tokens back to owner
        require(token.transfer(owner(), unreleased), "transfer-failed");

        emit Revoked(beneficiary, unreleased);
    }
}
