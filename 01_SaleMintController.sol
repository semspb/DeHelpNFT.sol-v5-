// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDeHelpNFT {
    function mint(address to, uint256 level) external returns (uint256);
}

interface IReferralRegistry {
    function bindSponsor(uint256 tokenId, uint256 sponsorTokenId) external;
}

interface IDistributionController {
    function split(uint256 amount) external view returns (
        uint256 referralAmount,
        uint256 poolAmount,
        uint256 reserveAmount
    );
}

interface IRevenuePool {
    function addShares(uint256 tokenId, uint256 shares) external;
    function deposit(uint256 amount) external;
}

interface IPartnerVault {
    function addOrUpdatePartner(address partner, uint256 shares) external;
    function incrementMintCount(address partner) external;
    function deposit(uint256 amount) external;
}

interface IReferralRewards {
    function distributeRewards(uint256 tokenId, uint256 baseAmount) 
        external 
        returns (uint256 distributedAmount, uint256 undistributedAmount);
}

/**
 * @title SaleMintController
 * @notice Handles NFT minting and fund distribution
 * Distribution from Marketing specs:
 * - baseAmount: 92% referral + 7% partner pool + 1% reserve
 * - ownerFee: separate fee for co-owners/treasury
 */
contract SaleMintController is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @dev Maximum co-owners allowed
    uint256 public constant MAX_COOWNERS = 10;
    
    /// @dev Maximum total co-owner percentage (50%)
    uint256 public constant MAX_COOWNER_PERCENT = 50;

    IERC20 public usdt;
    IDeHelpNFT public nft;
    IReferralRegistry public referralRegistry;
    IDistributionController public distController;
    IRevenuePool public revenuePool;
    IPartnerVault public partnerVault;
    IReferralRewards public referralRewards;
    address public treasury;

    uint256 public basePrice;
    uint256 public ownerFee;
    uint256 public defaultSharesPerNFT = 1;

    event Minted(address indexed buyer, uint256 tokenId, uint256 level);
    event TreasuryFunded(address indexed treasury, uint256 amount);

    constructor(
        address admin,
        address usdtAddress,
        address nftAddress,
        address referralAddress,
        address distAddress,
        address revenueAddress,
        address partnerVaultAddress,
        address referralRewardsAddress,
        address treasuryAddress,
        uint256 _basePrice,
        uint256 _ownerFee
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);

        usdt = IERC20(usdtAddress);
        nft = IDeHelpNFT(nftAddress);
        referralRegistry = IReferralRegistry(referralAddress);
        distController = IDistributionController(distAddress);
        revenuePool = IRevenuePool(revenueAddress);
        partnerVault = IPartnerVault(partnerVaultAddress);
        referralRewards = IReferralRewards(referralRewardsAddress);
        treasury = treasuryAddress;

        basePrice = _basePrice;
        ownerFee = _ownerFee;
    }

    // ------------------------
    // Mint
    // ------------------------
    /**
     * @notice Mint NFT with proper fund distribution
     * @param level NFT level/tier
     * @param sponsorTokenId Referral sponsor token ID (0 if none)
     */
    function mint(
        uint256 level,
        uint256 sponsorTokenId
    ) external whenNotPaused nonReentrant {
        uint256 totalPrice = basePrice + ownerFee;

        // Transfer USDT from buyer
        usdt.safeTransferFrom(msg.sender, address(this), totalPrice);

        // 1️⃣ Mint NFT
        uint256 tokenId = nft.mint(msg.sender, level);

        // 2️⃣ Bind sponsor (if provided)
        if (sponsorTokenId != 0) {
            referralRegistry.bindSponsor(tokenId, sponsorTokenId);
        }

        // 3️⃣ Split basePrice: 92% referral, 7% pool, 1% reserve
        (uint256 referralAmt, uint256 poolAmt, uint256 reserveAmt) =
            distController.split(basePrice);

        // 4️⃣ Distribute referral rewards (92%)
        if (referralAmt > 0) {
            usdt.safeApprove(address(referralRewards), referralAmt);
            (uint256 distributed, uint256 undistributed) = 
                referralRewards.distributeRewards(tokenId, referralAmt);
            
            // Any undistributed amount goes to reserve
            reserveAmt += undistributed;
        }

        // 5️⃣ Partner pool (7%)
        if (poolAmt > 0) {
            usdt.safeApprove(address(partnerVault), poolAmt);
            partnerVault.deposit(poolAmt);
            partnerVault.incrementMintCount(msg.sender);
            partnerVault.addOrUpdatePartner(msg.sender, defaultSharesPerNFT);
        }

        // 6️⃣ Revenue pool shares for NFT holder
        revenuePool.addShares(tokenId, defaultSharesPerNFT);

        // 7️⃣ Treasury/Reserve (1% + undistributed + ownerFee)
        uint256 totalTreasury = reserveAmt + ownerFee;
        if (totalTreasury > 0) {
            usdt.safeTransfer(treasury, totalTreasury);
            emit TreasuryFunded(treasury, totalTreasury);
        }

        emit Minted(msg.sender, tokenId, level);
    }

    // ------------------------
    // Admin
    // ------------------------
    function setPrices(uint256 _basePrice, uint256 _ownerFee)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_basePrice > 0, "Invalid base price");
        basePrice = _basePrice;
        ownerFee = _ownerFee;
    }

    function setTreasury(address newTreasury)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newTreasury != address(0), "Invalid address");
        treasury = newTreasury;
    }

    function setDefaultSharesPerNFT(uint256 shares)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(shares > 0, "Shares must be > 0");
        defaultSharesPerNFT = shares;
    }
    
    function setReferralRewards(address newReferralRewards)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newReferralRewards != address(0), "Invalid address");
        referralRewards = IReferralRewards(newReferralRewards);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}