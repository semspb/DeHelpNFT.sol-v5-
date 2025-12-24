// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract DistributionController is AccessControl {
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");
    uint256 public constant BPS = 10_000;

    struct Distribution {
        uint256 referral;   // % to referral rewards
        uint256 pool;       // % to revenue pool
        uint256 partners;   // % to partners / co-owners
        uint256 treasury;   // % to treasury
    }

    Distribution private distribution;

    event DistributionUpdated(uint256 referral, uint256 pool, uint256 partners, uint256 treasury);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ROLE, admin);

        // Безопасный дефолт
        distribution = Distribution({
            referral: 7000,   // 70%
            pool: 2000,       // 20%
            partners: 500,    // 5%
            treasury: 500     // 5%
        });
    }

    function setDistribution(
        uint256 referral,
        uint256 pool,
        uint256 partners,
        uint256 treasury
    ) external onlyRole(CONFIG_ROLE) {
        require(referral + pool + partners + treasury == BPS, "Distribution must equal 100%");
        distribution = Distribution(referral, pool, partners, treasury);
        emit DistributionUpdated(referral, pool, partners, treasury);
    }

    function getDistribution() external view returns (Distribution memory) {
        return distribution;
    }

    function split(uint256 amount)
        external
        view
        returns (uint256 referralAmount, uint256 poolAmount, uint256 partnerAmount, uint256 treasuryAmount)
    {
        Distribution memory d = distribution;
        referralAmount = (amount * d.referral) / BPS;
        poolAmount = (amount * d.pool) / BPS;
        partnerAmount = (amount * d.partners) / BPS;
        treasuryAmount = amount - referralAmount - poolAmount - partnerAmount;
    }
}
