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

interface IPartnerTracker {
    function isActivePartner(address user) external view returns (bool);
    function getMintCount(address user) external view returns (uint256);
}

/**
 * @title ReferralRewards
 * @notice Distributes referral rewards across 7 levels with specified percentages
 * @dev Implements the reward distribution logic from Marketing specification
 */
contract ReferralRewards is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // ============================================
    // Constants from Marketing
    // ============================================
    
    /// @dev Number of referral levels
    uint256 public constant LEVEL_COUNT = 7;
    
    /// @dev Basis points (10000 = 100%)
    uint256 public constant BPS = 10_000;
    
    /// @dev Maximum levels to climb when searching for active sponsor
    uint256 public constant MAX_LEVELS_TO_CLIMB = 10;
    
    /// @dev Percentage distribution per level in basis points
    /// Level 1: 50% (5000 BP), Levels 2-7: 7% (700 BP) each
    /// Total: 92% (9200 BP)
    uint256[7] public levelPercentsBP = [5000, 700, 700, 700, 700, 700, 700];

    // ============================================
    // State Variables
    // ============================================
    
    IERC20 public immutable usdt;
    IReferralRegistry public immutable referralRegistry;
    IDeHelpNFT public immutable nft;
    IPartnerTracker public partnerTracker;
    
    address public treasury;

    /// @dev Accumulated rewards per user
    mapping(address => uint256) public pendingRewards;
    
    /// @dev Total rewards distributed
    uint256 public totalDistributed;
    
    /// @dev Total rewards sent to treasury (unrewarded amounts)
    uint256 public totalToTreasury;

    // ============================================
    // Events
    // ============================================
    
    event RewardsDistributed(
        uint256 indexed tokenId,
        uint256 totalAmount,
        uint256 distributedAmount,
        uint256 treasuryAmount
    );
    
    event LevelReward(
        uint256 indexed tokenId,
        uint256 indexed sponsorTokenId,
        address indexed sponsor,
        uint256 level,
        uint256 amount
    );
    
    event RewardClaimed(
        address indexed user,
        uint256 amount
    );
    
    event UnrewardedAmount(
        uint256 indexed tokenId,
        uint256 level,
        uint256 amount,
        string reason
    );

    // ============================================
    // Constructor
    // ============================================
    
    constructor(
        address admin,
        address usdtAddress,
        address nftAddress,
        address registryAddress,
        address partnerTrackerAddress,
        address treasuryAddress
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, admin);
        
        usdt = IERC20(usdtAddress);
        nft = IDeHelpNFT(nftAddress);
        referralRegistry = IReferralRegistry(registryAddress);
        partnerTracker = IPartnerTracker(partnerTrackerAddress);
        treasury = treasuryAddress;
    }

    // ============================================
    // Distribution Logic
    // ============================================
    
    /**
     * @notice Distributes referral rewards for a minted NFT
     * @param tokenId The NFT token ID that was minted
     * @param amount Total amount available for referral rewards (92% of baseAmount)
     */
    function distributeRewards(
        uint256 tokenId,
        uint256 amount
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        require(amount > 0, "Zero amount");
        
        // Transfer funds from caller
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 distributed = 0;
        uint256 treasuryAmount = 0;
        
        // Distribute rewards across 7 levels
        for (uint256 level = 0; level < LEVEL_COUNT; level++) {
            uint256 levelReward = (amount * levelPercentsBP[level]) / BPS;
            
            if (levelReward == 0) continue;
            
            // Find active sponsor at this level
            (uint256 sponsorTokenId, address sponsor) = _findActiveSponsor(
                tokenId,
                level + 1
            );
            
            if (sponsor != address(0)) {
                // Reward active sponsor
                pendingRewards[sponsor] += levelReward;
                distributed += levelReward;
                
                emit LevelReward(
                    tokenId,
                    sponsorTokenId,
                    sponsor,
                    level + 1,
                    levelReward
                );
            } else {
                // No active sponsor found - send to treasury
                treasuryAmount += levelReward;
                
                emit UnrewardedAmount(
                    tokenId,
                    level + 1,
                    levelReward,
                    "No active sponsor"
                );
            }
        }
        
        // Send unrewarded amounts to treasury
        if (treasuryAmount > 0) {
            usdt.safeTransfer(treasury, treasuryAmount);
            totalToTreasury += treasuryAmount;
        }
        
        totalDistributed += distributed;
        
        emit RewardsDistributed(
            tokenId,
            amount,
            distributed,
            treasuryAmount
        );
    }

    // ============================================
    // Claiming
    // ============================================
    
    /**
     * @notice Allows users to claim their pending rewards
     */
    function claim() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No pending rewards");
        
        pendingRewards[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, amount);
        
        emit RewardClaimed(msg.sender, amount);
    }

    // ============================================
    // Internal Functions
    // ============================================
    
    /**
     * @dev Finds an active sponsor at the specified level
     * Climbs up the referral tree up to MAX_LEVELS_TO_CLIMB to find active partner
     * @param tokenId Starting token ID
     * @param targetLevel Target level to reach (1-7)
     * @return sponsorTokenId The sponsor's token ID (0 if not found)
     * @return sponsorAddress The sponsor's address (address(0) if not found)
     */
    function _findActiveSponsor(
        uint256 tokenId,
        uint256 targetLevel
    ) internal view returns (uint256 sponsorTokenId, address sponsorAddress) {
        uint256 current = tokenId;
        
        // Navigate to target level
        for (uint256 i = 0; i < targetLevel; i++) {
            current = referralRegistry.sponsorOf(current);
            if (current == 0) return (0, address(0));
        }
        
        // Found sponsor at target level
        sponsorTokenId = current;
        
        // Try to find active partner (climb up to MAX_LEVELS_TO_CLIMB)
        for (uint256 i = 0; i < MAX_LEVELS_TO_CLIMB; i++) {
            try nft.ownerOf(sponsorTokenId) returns (address owner) {
                if (owner != address(0)) {
                    // Check if this owner is an active partner
                    if (address(partnerTracker) != address(0)) {
                        if (partnerTracker.isActivePartner(owner)) {
                            return (sponsorTokenId, owner);
                        }
                    } else {
                        // If no partner tracker, accept any valid owner
                        return (sponsorTokenId, owner);
                    }
                }
            } catch {
                // NFT doesn't exist, continue climbing
            }
            
            // Climb up one level
            uint256 nextSponsor = referralRegistry.sponsorOf(sponsorTokenId);
            if (nextSponsor == 0) break;
            sponsorTokenId = nextSponsor;
        }
        
        return (0, address(0));
    }

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Get pending rewards for a user
     */
    function getPendingRewards(address user) external view returns (uint256) {
        return pendingRewards[user];
    }
    
    /**
     * @notice Get level percentages
     */
    function getLevelPercents() external view returns (uint256[7] memory) {
        return levelPercentsBP;
    }
    
    /**
     * @notice Calculate expected rewards for each level
     */
    function calculateLevelRewards(
        uint256 amount
    ) external view returns (uint256[7] memory rewards) {
        for (uint256 i = 0; i < LEVEL_COUNT; i++) {
            rewards[i] = (amount * levelPercentsBP[i]) / BPS;
        }
    }

    // ============================================
    // Admin Functions
    // ============================================
    
    function setTreasury(address newTreasury) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newTreasury != address(0), "Zero address");
        treasury = newTreasury;
    }
    
    function setPartnerTracker(address newTracker) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        partnerTracker = IPartnerTracker(newTracker);
    }
}