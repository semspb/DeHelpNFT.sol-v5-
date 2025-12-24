// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DistributionController
 * @notice Controls fund distribution with correct percentages from Marketing:
 * - Referral: 92% (9200 BP) - distributed across 7 levels
 * - Partner Pool: 7% (700 BP) - PARTNER_POOL_PERCENT
 * - Reserve/Treasury: 1% (100 BP) - RESERVE_PERCENT
 */
contract DistributionController is AccessControl {

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    /// @dev basis points (10000 = 100%)
    uint256 public constant BPS = 10_000;
    
    /// @dev Partner pool percentage: 7% = 700 BP
    uint256 public constant PARTNER_POOL_PERCENT = 700;
    
    /// @dev Reserve/Treasury percentage: 1% = 100 BP
    uint256 public constant RESERVE_PERCENT = 100;
    
    /// @dev Referral percentage: 92% = 9200 BP (distributed across 7 levels)
    uint256 public constant REFERRAL_PERCENT = 9200;

    struct Distribution {
        uint256 referral;   // % to referral rewards (92% = 9200 BP)
        uint256 pool;       // % to partner pool (7% = 700 BP)
        uint256 reserve;    // % to reserve/treasury (1% = 100 BP)
    }

    Distribution public distribution;

    event DistributionUpdated(
        uint256 referral,
        uint256 pool,
        uint256 reserve
    );

    constructor(
        address admin,
        address config
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ROLE, config);
        
        // Set default distribution from Marketing specs
        distribution = Distribution({
            referral: REFERRAL_PERCENT,  // 92%
            pool: PARTNER_POOL_PERCENT,  // 7%
            reserve: RESERVE_PERCENT     // 1%
        });
    }

    // --------------------------------
    // Configuration
    // --------------------------------

    function setDistribution(
        uint256 referral,
        uint256 pool,
        uint256 reserve
    ) external onlyRole(CONFIG_ROLE) {
        require(
            referral + pool + reserve == BPS,
            "Distribution must equal 100%"
        );

        distribution = Distribution({
            referral: referral,
            pool: pool,
            reserve: reserve
        });

        emit DistributionUpdated(
            referral,
            pool,
            reserve
        );
    }

    // --------------------------------
    // View
    // --------------------------------

    function getDistribution()
        external
        view
        returns (Distribution memory)
    {
        return distribution;
    }

    /**
     * @notice Split amount according to distribution percentages
     * @param amount Total amount to split
     * @return referralAmount Amount for referral rewards (92%)
     * @return poolAmount Amount for partner pool (7%)
     * @return reserveAmount Amount for reserve/treasury (1%)
     */
    function split(
        uint256 amount
    )
        external
        view
        returns (
            uint256 referralAmount,
            uint256 poolAmount,
            uint256 reserveAmount
        )
    {
        Distribution memory d = distribution;

        referralAmount = amount * d.referral / BPS;  // 92%
        poolAmount     = amount * d.pool / BPS;      // 7%

        // Reserve gets the remainder (prevents dust)
        reserveAmount = amount - referralAmount - poolAmount;  // ~1%
    }
    
    /**
     * @notice Get current distribution percentages
     */
    function getPercentages() external view returns (
        uint256 referralPercent,
        uint256 poolPercent,
        uint256 reservePercent
    ) {
        return (
            distribution.referral,
            distribution.pool,
            distribution.reserve
        );
    }
}