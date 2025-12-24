// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IReferralRegistry {
    function sponsorOf(uint256 tokenId) external view returns (uint256);
}

interface IDeHelpNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title ReferralRewards
 * @notice Distributes referral rewards across 7 levels
 * Level 1: 50% (5000 BP)
 * Levels 2-7: 7% each (700 BP)
 * Total: 92% distributed, 8% returned to caller for pool/treasury
 */
contract ReferralRewards is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @dev Basis points (10000 = 100%)
    uint256 public constant BPS = 10_000;
    
    /// @dev Number of referral levels
    uint256 public constant LEVEL_COUNT = 7;
    
    /// @dev Percentage distribution per level in basis points
    /// [5000, 700, 700, 700, 700, 700, 700] = [50%, 7%, 7%, 7%, 7%, 7%, 7%]
    uint256[7] public levelPercentsBP = [5000, 700, 700, 700, 700, 700, 700];

    IERC20 public immutable usdt;
    IReferralRegistry public immutable referralRegistry;
    IDeHelpNFT public immutable nft;

    /// @dev Pending rewards per address
    mapping(address => uint256) public pendingRewards;

    event RewardDistributed(
        uint256 indexed tokenId,
        uint256 indexed sponsorTokenId,
        uint256 level,
        address indexed recipient,
        uint256 amount
    );

    event RewardClaimed(
        address indexed user,
        uint256 amount
    );

    constructor(
        address admin,
        address usdtAddress,
        address referralRegistryAddress,
        address nftAddress
    ) {
        usdt = IERC20(usdtAddress);
        referralRegistry = IReferralRegistry(referralRegistryAddress);
        nft = IDeHelpNFT(nftAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Distributes referral rewards across upline
     * @param tokenId The NFT token ID that triggered the reward
     * @param baseAmount The base amount to distribute (100% = 10000 BP)
     * @return distributedAmount Total amount distributed to referrers
     * @return undistributedAmount Amount not distributed (for pool/treasury)
     */
    function distributeRewards(
        uint256 tokenId,
        uint256 baseAmount
    )
        external
        onlyRole(DISTRIBUTOR_ROLE)
        nonReentrant
        returns (uint256 distributedAmount, uint256 undistributedAmount)
    {
        require(baseAmount > 0, "Zero amount");

        // Transfer funds to this contract first
        usdt.safeTransferFrom(msg.sender, address(this), baseAmount);

        uint256 currentTokenId = tokenId;

        // Distribute rewards across 7 levels
        for (uint256 level = 0; level < LEVEL_COUNT; level++) {
            // Get sponsor at this level
            uint256 sponsorTokenId = referralRegistry.sponsorOf(currentTokenId);
            
            // If no sponsor exists, break the loop
            if (sponsorTokenId == 0) {
                break;
            }

            // Calculate reward for this level
            uint256 levelReward = (baseAmount * levelPercentsBP[level]) / BPS;

            if (levelReward > 0) {
                // Get sponsor's owner address
                address sponsorOwner = nft.ownerOf(sponsorTokenId);
                
                // Add to pending rewards
                pendingRewards[sponsorOwner] += levelReward;
                distributedAmount += levelReward;

                emit RewardDistributed(
                    tokenId,
                    sponsorTokenId,
                    level + 1,
                    sponsorOwner,
                    levelReward
                );
            }

            // Move up the chain
            currentTokenId = sponsorTokenId;
        }

        // Calculate undistributed amount (for pool/treasury)
        undistributedAmount = baseAmount - distributedAmount;

        // Transfer undistributed amount back to caller
        if (undistributedAmount > 0) {
            usdt.safeTransfer(msg.sender, undistributedAmount);
        }
    }

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards");

        pendingRewards[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, amount);

        emit RewardClaimed(msg.sender, amount);
    }

    /**
     * @notice Get pending rewards for an address
     */
    function getPendingRewards(address user) external view returns (uint256) {
        return pendingRewards[user];
    }

    /**
     * @notice Get level percentages
     */
    function getLevelPercentages() external view returns (uint256[7] memory) {
        return levelPercentsBP;
    }

    /**
     * @notice Calculate total percentage distributed
     */
    function getTotalDistributionPercent() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < LEVEL_COUNT; i++) {
            total += levelPercentsBP[i];
        }
        return total; // Should be 9200 (92%)
    }
}