// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

interface IDeHelpNFT {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract ReferralRegistry is AccessControl {
    bytes32 public constant BINDER_ROLE = keccak256("BINDER_ROLE");
    uint256 public constant MAX_DEPTH = 11;

    IDeHelpNFT public immutable nft;

    mapping(uint256 => uint256) public sponsorOf;
    mapping(uint256 => bool) public isBound;

    event SponsorBound(uint256 indexed tokenId, uint256 indexed sponsorTokenId);

    constructor(address admin, address nftAddress) {
        nft = IDeHelpNFT(nftAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ----------------------------------------------------
    // Bind sponsor
    // ----------------------------------------------------
    function bindSponsor(uint256 tokenId, uint256 sponsorTokenId)
        external
        onlyRole(BINDER_ROLE)
    {
        require(!isBound[tokenId], "Already bound");
        require(tokenId != sponsorTokenId, "Self referral");
        require(_existsNFT(tokenId), "Token does not exist");
        require(_existsNFT(sponsorTokenId), "Sponsor does not exist");

        // Только владелец может инициировать bind
        require(nft.ownerOf(tokenId) == msg.sender, "Only owner can bind");

        // Cycle protection
        uint256 current = sponsorTokenId;
        for (uint256 i = 0; i < MAX_DEPTH; i++) {
            if (current == 0) break;
            require(current != tokenId, "Referral cycle");
            current = sponsorOf[current];
        }

        sponsorOf[tokenId] = sponsorTokenId;
        isBound[tokenId] = true;

        emit SponsorBound(tokenId, sponsorTokenId);
    }

    // ----------------------------------------------------
    // View helpers
    // ----------------------------------------------------
    function getUpline(uint256 tokenId, uint256 depth)
        external
        view
        returns (uint256 sponsorTokenId)
    {
        require(depth > 0 && depth <= MAX_DEPTH, "Invalid depth");
        sponsorTokenId = tokenId;
        for (uint256 i = 0; i < depth; i++) {
            sponsorTokenId = sponsorOf[sponsorTokenId];
            if (sponsorTokenId == 0) break;
        }
    }

    function getFullUpline(uint256 tokenId)
        external
        view
        returns (uint256[] memory upline)
    {
        upline = new uint256[](MAX_DEPTH);
        uint256 current = tokenId;
        for (uint256 i = 0; i < MAX_DEPTH; i++) {
            current = sponsorOf[current];
            if (current == 0) break;
            upline[i] = current;
        }
    }

    // ----------------------------------------------------
    // Internal
    // ----------------------------------------------------
    function _existsNFT(uint256 tokenId) internal view returns (bool) {
        try nft.ownerOf(tokenId) returns (address owner) {
            return owner != address(0);
        } catch {
            return false;
        }
    }
}
