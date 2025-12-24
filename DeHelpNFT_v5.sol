// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IRevenuePool {
    function onNFTTransfer(
        uint256 tokenId,
        address from,
        address to
    ) external;
}

contract DeHelpNFT is ERC721, AccessControl {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public nextTokenId;

    /// @dev immutable system contracts
    address public revenuePool;

    struct NFTData {
        uint256 mintTimestamp;
        uint256 level;
    }

    mapping(uint256 => NFTData) public nftData;

    event NFTMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 level
    );

    constructor(
        address admin,
        address _revenuePool
    ) ERC721("DeHelp NFT", "DHELP") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        revenuePool = _revenuePool;
    }

    // ------------------------
    // Mint
    // ------------------------

    function mint(
        address to,
        uint256 level
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = ++nextTokenId;

        _safeMint(to, tokenId);

        nftData[tokenId] = NFTData({
            mintTimestamp: block.timestamp,
            level: level
        });

        emit NFTMinted(to, tokenId, level);
    }

    // ------------------------
    // Transfer hook
    // ------------------------

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from != address(0) && to != address(0)) {
            IRevenuePool(revenuePool).onNFTTransfer(
                tokenId,
                from,
                to
            );
        }
    }

    // ------------------------
    // Admin
    // ------------------------

    function setRevenuePool(address newPool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revenuePool = newPool;
    }
}
