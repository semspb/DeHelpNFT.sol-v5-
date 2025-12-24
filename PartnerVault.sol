// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PartnerVault
 * @notice Partner pool distribution system
 * Partners are users who have minted PARTNER_MIN_MINTS (10) or more NFTs
 */
contract PartnerVault is
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public immutable usdt;

    uint256 public constant ACC_PRECISION = 1e18;
    
    /// @dev Minimum mints to become a partner (from Marketing)
    uint256 public constant PARTNER_MIN_MINTS = 10;
    
    /// @dev Maximum levels to climb when searching for active sponsor
    uint256 public constant MAX_LEVELS_TO_CLIMB = 10;

    // --- Global state ---
    uint256 public accRewardPerShare;
    uint256 public totalShares;

    struct Partner {
        uint256 shares;
        uint256 rewardDebt;
        uint256 mintCount;  // Track number of mints
    }

    /// @dev partner address => Partner data
    mapping(address => Partner) public partners;

    /// @dev pending rewards per partner
    mapping(address => uint256) public pending;

    // --- Events ---
    event PartnerAdded(address indexed partner, uint256 shares);
    event PartnerSharesUpdated(address indexed partner, uint256 shares);
    event MintCountUpdated(address indexed partner, uint256 mintCount);
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
        onlyRole(OPERATOR_ROLE)
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
    
    /**
     * @notice Increment mint count for a partner
     * @dev Called when a user mints an NFT
     */
    function incrementMintCount(address partner)
        external
        onlyRole(OPERATOR_ROLE)
    {
        require(partner != address(0), "Zero address");
        
        Partner storage p = partners[partner];
        p.mintCount++;
        
        emit MintCountUpdated(partner, p.mintCount);
    }
    
    /**
     * @notice Check if address is a partner (has >= PARTNER_MIN_MINTS)
     */
    function isPartner(address user) external view returns (bool) {
        return partners[user].mintCount >= PARTNER_MIN_MINTS;
    }
    
    /**
     * @notice Get partner mint count
     */
    function getMintCount(address user) external view returns (uint256) {
        return partners[user].mintCount;
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