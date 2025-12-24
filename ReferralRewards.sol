// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IReferralRegistry {
    function sponsorOf(uint256 tokenId) external view returns (uint256);
}

interface IDeHelpNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title ReferralRewards
 * @notice Распределяет реферальные награды по 7 уровням
 * Level 1: 50% (5000 BP)
 * Levels 2-7: 7% each (700 BP)
 * Total: 92% distributed
 */
contract ReferralRewards is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant BPS = 10_000;
    uint256 public constant LEVEL_COUNT = 7;
    
    // Проценты распределения по уровням в базисных пунктах
    // [5000, 700, 700, 700, 700, 700, 700] = [50%, 7%, 7%, 7%, 7%, 7%, 7%]
    uint256[7] public levelPercentsBP = [5000, 700, 700, 700, 700, 700, 700];
    
    IERC20 public immutable usdt;
    IDeHelpNFT public immutable nft;
    IReferralRegistry public immutable referralRegistry;
    
    address public treasury;
    
    // Pending rewards for each address
    mapping(address => uint256) public pendingRewards;
    
    event RewardsDistributed(
        uint256 indexed tokenId,
        uint256 totalAmount,
        uint256 distributedAmount,
        uint256 treasuryAmount
    );
    
    event RewardAssigned(
        uint256 indexed sponsorTokenId,
        address indexed sponsor,
        uint256 level,
        uint256 amount
    );
    
    event RewardsClaimed(address indexed user, uint256 amount);
    
    constructor(
        address admin,
        address operator,
        address usdtAddress,
        address nftAddress,
        address referralRegistryAddress,
        address treasuryAddress
    ) {
        usdt = IERC20(usdtAddress);
        nft = IDeHelpNFT(nftAddress);
        referralRegistry = IReferralRegistry(referralRegistryAddress);
        treasury = treasuryAddress;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }
    
    /**
     * @notice Распределяет реферальные награды по 7 уровням
     * @param tokenId ID NFT токена, для которого распределяются награды
     * @param amount Общая сумма для распределения
     */
    function distributeRewards(
        uint256 tokenId,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        require(amount > 0, "Amount must be > 0");
        
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 distributedAmount = 0;
        uint256 currentTokenId = tokenId;
        
        // Распределение по 7 уровням
        for (uint256 level = 0; level < LEVEL_COUNT; level++) {
            uint256 sponsorTokenId = referralRegistry.sponsorOf(currentTokenId);
            
            if (sponsorTokenId == 0) {
                // Нет спонсора на этом уровне
                break;
            }
            
            address sponsor = nft.ownerOf(sponsorTokenId);
            if (sponsor == address(0)) {
                // NFT не существует или сожжен
                currentTokenId = sponsorTokenId;
                continue;
            }
            
            // Рассчитываем награду для этого уровня
            uint256 levelReward = (amount * levelPercentsBP[level]) / BPS;
            
            if (levelReward > 0) {
                pendingRewards[sponsor] += levelReward;
                distributedAmount += levelReward;
                
                emit RewardAssigned(sponsorTokenId, sponsor, level + 1, levelReward);
            }
            
            currentTokenId = sponsorTokenId;
        }
        
        // Остаток (нераспределенные награды) идет в казну
        uint256 treasuryAmount = amount - distributedAmount;
        if (treasuryAmount > 0) {
            usdt.safeTransfer(treasury, treasuryAmount);
        }
        
        emit RewardsDistributed(tokenId, amount, distributedAmount, treasuryAmount);
    }
    
    /**
     * @notice Позволяет пользователю забрать свои накопленные награды
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        require(amount > 0, "No rewards to claim");
        
        pendingRewards[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, amount);
        
        emit RewardsClaimed(msg.sender, amount);
    }
    
    /**
     * @notice Получить сумму ожидающих наград для адреса
     */
    function getPendingRewards(address user) external view returns (uint256) {
        return pendingRewards[user];
    }
    
    /**
     * @notice Обновить адрес казны
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Invalid treasury address");
        treasury = newTreasury;
    }
    
    /**
     * @notice Получить проценты для конкретного уровня
     */
    function getLevelPercent(uint256 level) external view returns (uint256) {
        require(level > 0 && level <= LEVEL_COUNT, "Invalid level");
        return levelPercentsBP[level - 1];
    }
}