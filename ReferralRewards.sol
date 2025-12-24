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

contract ReferralRewards is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    // === Constants from Marketing ===
    uint256 public constant LEVEL_COUNT = 7;
    uint256 public constant BPS = 10_000; // 100% = 10000 BP
    uint256 public constant MAX_LEVELS_TO_CLIMB = 10;

    // Level percentages: [50%, 7%, 7%, 7%, 7%, 7%, 7%]
    uint256[7] public levelPercentsBP = [5000, 700, 700, 700, 700, 700, 700];

    IERC20 public immutable usdt;
    IReferralRegistry public immutable referralRegistry;
    IDeHelpNFT public immutable nft;

    // Tracking mint count for partner activation
    mapping(address => uint256) public userMintCount;
    uint256 public constant PARTNER_MIN_MINTS = 10;

    // Pending rewards per user
    mapping(address => uint256) public pendingRewards;

    // Treasury for unclaimed rewards
    address public treasury;

    event RewardsDistributed(
        uint256 indexed tokenId,
        uint256 totalAmount,
        uint256 distributedAmount,
        uint256 treasuryAmount
    );

    event LevelReward(
        uint256 indexed level,
        uint256 indexed sponsorTokenId,
        address indexed sponsor,
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
        address nftAddress,
        address treasuryAddress
    ) {
        usdt = IERC20(usdtAddress);
        referralRegistry = IReferralRegistry(referralRegistryAddress);
        nft = IDeHelpNFT(nftAddress);
        treasury = treasuryAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DISTRIBUTOR_ROLE, admin);
    }

    // --------------------------------
    // Distribution Logic
    // --------------------------------

    /**
     * @dev Distribute referral rewards for a new mint
     * @param tokenId The newly minted NFT token ID
     * @param amount Total amount to distribute (92% of baseAmount)
     */
    function distributeRewards(
        uint256 tokenId,
        uint256 amount
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        require(amount > 0, "Zero amount");

        // Transfer funds to this contract
        usdt.safeTransferFrom(msg.sender, address(this), amount);

        // Increment mint count for the buyer
        address buyer = nft.ownerOf(tokenId);
        userMintCount[buyer]++;

        uint256 distributedAmount = 0;
        uint256 currentTokenId = tokenId;

        // Distribute rewards through 7 levels
        for (uint256 level = 0; level < LEVEL_COUNT; level++) {
            // Find sponsor at this level
            currentTokenId = _findActiveSponsor(currentTokenId);
            
            if (currentTokenId == 0) {
                // No more sponsors, remaining goes to treasury
                break;
            }

            // Calculate reward for this level
            uint256 levelReward = (amount * levelPercentsBP[level]) / BPS;
            
            if (levelReward > 0) {
                address sponsorOwner = nft.ownerOf(currentTokenId);
                pendingRewards[sponsorOwner] += levelReward;
                distributedAmount += levelReward;

                emit LevelReward(level + 1, currentTokenId, sponsorOwner, levelReward);
            }
        }

        // Remaining amount goes to treasury
        uint256 treasuryAmount = amount - distributedAmount;
        if (treasuryAmount > 0) {
            usdt.safeTransfer(treasury, treasuryAmount);
        }

        emit RewardsDistributed(tokenId, amount, distributedAmount, treasuryAmount);
    }

    /**
     * @dev Find active sponsor (with at least PARTNER_MIN_MINTS)
     * Climbs up to MAX_LEVELS_TO_CLIMB levels
     */
    function _findActiveSponsor(uint256 tokenId) internal view returns (uint256) {
        uint256 current = referralRegistry.sponsorOf(tokenId);
        
        for (uint256 i = 0; i < MAX_LEVELS_TO_CLIMB && current != 0; i++) {
            address owner = nft.ownerOf(current);
            
            // Check if sponsor is active partner (10+ mints)
            if (userMintCount[owner] >= PARTNER_MIN_MINTS) {
                return current;
            }
            
            // Move to next level
            current = referralRegistry.sponsorOf(current);
        }
        
        return 0; // No active sponsor found
    }

    // --------------------------------
    // Claiming
    // --------------------------------

    function claim() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "Nothing to claim");

        pendingRewards[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, amount);

        emit RewardClaimed(msg.sender, amount);
    }

    // --------------------------------
    // View Functions
    // --------------------------------

    function isActivePartner(address user) external view returns (bool) {
        return userMintCount[user] >= PARTNER_MIN_MINTS;
    }

    function getUserMintCount(address user) external view returns (uint256) {
        return userMintCount[user];
    }

    function getPendingRewards(address user) external view returns (uint256) {
        return pendingRewards[user];
    }

    // --------------------------------
    // Admin Functions
    // --------------------------------

    function setTreasury(address newTreasury) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newTreasury != address(0), "Zero address");
        treasury = newTreasury;
    }

    /**
     * @dev Emergency: increment mint count manually (migration purposes)
     */
    function setUserMintCount(
        address user,
        uint256 count
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        userMintCount[user] = count;
    }
}