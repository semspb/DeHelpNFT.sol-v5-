// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDeHelpNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract RevenuePool is
    AccessControl,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IERC20 public immutable usdt;
    IDeHelpNFT public immutable nft;

    uint256 public constant ACC_PRECISION = 1e18;

    // --- Pool state ---
    uint256 public accRewardPerShare;
    uint256 public totalShares;

    struct Position {
        uint256 shares;
        uint256 rewardDebt;
    }

    /// @dev tokenId => position
    mapping(uint256 => Position) public positions;

    /// @dev pending rewards per owner address
    mapping(address => uint256) public pending;

    // --- Events ---
    event SharesAdded(uint256 indexed tokenId, uint256 shares);
    event Deposit(uint256 amount);
    event Harvest(uint256 indexed tokenId, address indexed to, uint256 amount);
    event NFTTransferred(uint256 indexed tokenId, address from, address to);

    constructor(
        address admin,
        address operator,
        address usdtAddress,
        address nftAddress
    ) {
        usdt = IERC20(usdtAddress);
        nft = IDeHelpNFT(nftAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    // ----------------------------------------------------
    // Pool funding (from DistributionController flow)
    // ----------------------------------------------------

    /// @dev called by sale / mint logic
    function deposit(uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        require(amount > 0, "Zero deposit");
        require(totalShares > 0, "No shares");

        usdt.safeTransferFrom(msg.sender, address(this), amount);

        accRewardPerShare += (amount * ACC_PRECISION) / totalShares;

        emit Deposit(amount);
    }

    // ----------------------------------------------------
    // Shares management
    // ----------------------------------------------------

    function addShares(uint256 tokenId, uint256 shares)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        require(shares > 0, "Zero shares");

        Position storage p = positions[tokenId];

        // settle pending before change
        _harvestToPending(tokenId, nft.ownerOf(tokenId));

        totalShares += shares;
        p.shares += shares;

        p.rewardDebt = (p.shares * accRewardPerShare) / ACC_PRECISION;

        emit SharesAdded(tokenId, shares);
    }

    // ----------------------------------------------------
    // Claiming
    // ----------------------------------------------------

    function claim()
        external
        nonReentrant
    {
        uint256 amount = pending[msg.sender];
        require(amount > 0, "Nothing to claim");

        pending[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, amount);
    }

    /// @dev harvest rewards for a specific NFT
    function harvest(uint
