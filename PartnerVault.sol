// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PartnerVault is
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public immutable usdt;

    uint256 public constant ACC_PRECISION = 1e18;

    // --- Global state ---
    uint256 public accRewardPerShare;
    uint256 public totalShares;

    struct Partner {
        uint256 shares;
        uint256 rewardDebt;
    }

    /// @dev partner address => Partner data
    mapping(address => Partner) public partners;

    /// @dev pending rewards per partner
    mapping(address => uint256) public pending;

    // --- Events ---
    event PartnerAdded(address indexed partner, uint256 shares);
    event PartnerSharesUpdated(address indexed partner, uint256 shares);
    event Deposit(uint256 amount);
    event Harvest(address indexed partner, uint256 amount);
    event Claimed(address indexed partner, uint256 amount);

    constructor(
        address admin,
        address operator,
        address usdtAddress
    ) {
        usdt = IERC20(usdtAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    // ----------------------------------------------------
    // Partner management (admin / governance)
    // ----------------------------------------------------

    function addOrUpdatePartner(
        address partner,
        uint256 shares
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        require(partner != address(0), "Zero address");

        Partner storage p = partners[partner];

        // settle rewards before changing shares
        _harvestToPending(partner);

        totalShares = totalShares - p.shares + shares;
        p.shares = shares;

        p.rewardDebt =
            (p.shares * accRewardPerShare) / ACC_PRECISION;

        emit PartnerSharesUpdated(partner, shares);
    }

    // ----------------------------------------------------
    // Funding (from DistributionController flow)
    // ----------------------------------------------------

    function deposit(uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        require(amount > 0, "Zero deposit");
        require(totalShares > 0, "No partner shares");

        usdt.safeTransferFrom(msg.sender, address(this), amount);

        accRewardPerShare +=
            (amount * ACC_PRECISION) / totalShares;

        emit Deposit(amount);
    }

    // ----------------------------------------------------
    // Claiming
    // ----------------------------------------------------

    function harvest()
        external
        nonReentrant
    {
        _harvestToPending(msg.sender);
    }

    function claim()
        external
        nonReentrant
    {
        uint256 amount = pending[msg.sender];
        require(amount > 0, "Nothing to claim");

        pending[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    // ----------------------------------------------------
    // Internal logic
    // ----------------------------------------------------

    function _harvestToPending(address partner) internal {
        Partner storage p = partners[partner];
        if (p.shares == 0) return;

        uint256 accumulated =
            (p.shares * accRewardPerShare) / ACC_PRECISION;

        uint256 reward =
            accumulated > p.rewardDebt
                ? accumulated - p.rewardDebt
                : 0;

        if (reward > 0) {
            pending[partner] += reward;
        }

        p.rewardDebt = accumulated;

        emit Harvest(partner, reward);
    }

    // ----------------------------------------------------
    // Emergency & admin
    // ----------------------------------------------------

    function pause()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _pause();
    }

    function unpause()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _unpause();
    }
}
