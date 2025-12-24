// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CoOwnerManager
 * @notice Manages co-owners and distribution of ownerFee
 * Constants from Marketing:
 * - MAX_COOWNERS = 10
 * - MAX_COOWNER_PERCENT = 50 (total for all co-owners)
 */
contract CoOwnerManager is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // === Constants from Marketing ===
    uint256 public constant MAX_COOWNERS = 10;
    uint256 public constant MAX_COOWNER_PERCENT = 50; // 50% max total
    uint256 public constant PERCENT_BASE = 100;

    IERC20 public immutable usdt;
    address public treasury;

    struct CoOwner {
        address addr;
        uint256 percent; // percentage of ownerFee (out of 100)
        bool active;
    }

    // List of co-owners
    CoOwner[] public coOwners;
    
    // Mapping for quick lookup
    mapping(address => uint256) public coOwnerIndex; // address => index + 1 (0 = not exists)
    
    // Pending rewards
    mapping(address => uint256) public pendingRewards;

    // Total co-owner percentage
    uint256 public totalCoOwnerPercent;

    event CoOwnerAdded(address indexed coOwner, uint256 percent);
    event CoOwnerUpdated(address indexed coOwner, uint256 oldPercent, uint256 newPercent);
    event CoOwnerRemoved(address indexed coOwner, uint256 percent);
    event OwnerFeeDistributed(uint256 totalAmount, uint256 coOwnersAmount, uint256 treasuryAmount);
    event RewardClaimed(address indexed coOwner, uint256 amount);

    constructor(
        address admin,
        address usdtAddress,
        address treasuryAddress
    ) {
        usdt = IERC20(usdtAddress);
        treasury = treasuryAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    // --------------------------------
    // Co-Owner Management
    // --------------------------------

    /**
     * @notice Add a new co-owner
     * @param coOwner Address of co-owner
     * @param percent Percentage of ownerFee (out of 100)
     */
    function addCoOwner(
        address coOwner,
        uint256 percent
    ) external onlyRole(MANAGER_ROLE) {
        require(coOwner != address(0), "Zero address");
        require(percent > 0 && percent <= MAX_COOWNER_PERCENT, "Invalid percent");
        require(coOwnerIndex[coOwner] == 0, "Already exists");
        require(coOwners.length < MAX_COOWNERS, "Max co-owners reached");
        require(
            totalCoOwnerPercent + percent <= MAX_COOWNER_PERCENT,
            "Total percent exceeds max"
        );

        coOwners.push(CoOwner({
            addr: coOwner,
            percent: percent,
            active: true
        }));

        coOwnerIndex[coOwner] = coOwners.length; // index + 1
        totalCoOwnerPercent += percent;

        emit CoOwnerAdded(coOwner, percent);
    }

    /**
     * @notice Update co-owner percentage
     */
    function updateCoOwnerPercent(
        address coOwner,
        uint256 newPercent
    ) external onlyRole(MANAGER_ROLE) {
        uint256 idx = coOwnerIndex[coOwner];
        require(idx > 0, "Not a co-owner");
        require(newPercent > 0 && newPercent <= MAX_COOWNER_PERCENT, "Invalid percent");

        CoOwner storage co = coOwners[idx - 1];
        uint256 oldPercent = co.percent;

        uint256 newTotal = totalCoOwnerPercent - oldPercent + newPercent;
        require(newTotal <= MAX_COOWNER_PERCENT, "Total percent exceeds max");

        co.percent = newPercent;
        totalCoOwnerPercent = newTotal;

        emit CoOwnerUpdated(coOwner, oldPercent, newPercent);
    }

    /**
     * @notice Remove a co-owner
     */
    function removeCoOwner(address coOwner) external onlyRole(MANAGER_ROLE) {
        uint256 idx = coOwnerIndex[coOwner];
        require(idx > 0, "Not a co-owner");

        CoOwner storage co = coOwners[idx - 1];
        uint256 percent = co.percent;

        // Deactivate instead of removing to preserve indices
        co.active = false;
        co.percent = 0;
        totalCoOwnerPercent -= percent;
        
        delete coOwnerIndex[coOwner];

        emit CoOwnerRemoved(coOwner, percent);
    }

    // --------------------------------
    // Distribution
    // --------------------------------

    /**
     * @notice Distribute ownerFee among co-owners and treasury
     * @param amount Total ownerFee amount
     */
    function distributeOwnerFee(uint256 amount) 
        external 
        onlyRole(MANAGER_ROLE) 
        nonReentrant 
    {
        require(amount > 0, "Zero amount");

        // Transfer funds to this contract
        usdt.safeTransferFrom(msg.sender, address(this), amount);

        uint256 coOwnersTotal = 0;

        // Distribute to active co-owners
        for (uint256 i = 0; i < coOwners.length; i++) {
            CoOwner storage co = coOwners[i];
            if (!co.active || co.percent == 0) continue;

            uint256 coOwnerShare = (amount * co.percent) / PERCENT_BASE;
            if (coOwnerShare > 0) {
                pendingRewards[co.addr] += coOwnerShare;
                coOwnersTotal += coOwnerShare;
            }
        }

        // Remaining goes to treasury
        uint256 treasuryAmount = amount - coOwnersTotal;
        if (treasuryAmount > 0) {
            usdt.safeTransfer(treasury, treasuryAmount);
        }

        emit OwnerFeeDistributed(amount, coOwnersTotal, treasuryAmount);
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
    // Views
    // --------------------------------

    function getCoOwnerCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < coOwners.length; i++) {
            if (coOwners[i].active) count++;
        }
        return count;
    }

    function isCoOwner(address addr) external view returns (bool) {
        uint256 idx = coOwnerIndex[addr];
        if (idx == 0) return false;
        return coOwners[idx - 1].active;
    }

    function getCoOwnerPercent(address addr) external view returns (uint256) {
        uint256 idx = coOwnerIndex[addr];
        if (idx == 0) return 0;
        return coOwners[idx - 1].percent;
    }

    function getAllCoOwners() external view returns (CoOwner[] memory) {
        return coOwners;
    }

    function getActiveCoOwners() external view returns (CoOwner[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < coOwners.length; i++) {
            if (coOwners[i].active) activeCount++;
        }

        CoOwner[] memory active = new CoOwner[](activeCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < coOwners.length; i++) {
            if (coOwners[i].active) {
                active[idx] = coOwners[i];
                idx++;
            }
        }
        return active;
    }

    // --------------------------------
    // Admin
    // --------------------------------

    function setTreasury(address newTreasury) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newTreasury != address(0), "Zero address");
        treasury = newTreasury;
    }
}