// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SaleMintController.sol";

// Mock контракты для интеграции
contract MockUSDT {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockNFT {
    uint256 public nextTokenId;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint256) public levelOf;

    function mint(address to, uint256 level) external returns (uint256 tokenId) {
        tokenId = ++nextTokenId;
        ownerOf[tokenId] = to;
        levelOf[tokenId] = level;
    }
}

contract MockReferralRegistry {
    mapping(uint256 => uint256) public sponsorOf;
    function bindSponsor(uint256 tokenId, uint256 sponsorTokenId) external {
        sponsorOf[tokenId] = sponsorTokenId;
    }
}

contract MockDistributionController {
    uint256 constant BPS = 10_000;
    function split(uint256 amount) external pure returns (uint256, uint256, uint256, uint256) {
        uint256 referral = amount * 7000 / BPS;
        uint256 pool = amount * 2000 / BPS;
        uint256 partner = amount * 500 / BPS;
        uint256 treasury = amount - referral - pool - partner;
        return (referral, pool, partner, treasury);
    }
}

contract MockRevenuePool {
    mapping(uint256 => uint256) public shares;
    uint256 public totalDeposited;

    function addShares(uint256 tokenId, uint256 share) external {
        shares[tokenId] += share;
    }

    function deposit(uint256 amount) external {
        totalDeposited += amount;
    }
}

contract MockPartnerVault {
    mapping(address => uint256) public shares;
    uint256 public totalDeposited;

    function addOrUpdatePartner(address partner, uint256 share) external {
        shares[partner] += share;
    }

    function deposit(uint256 amount) external {
        totalDeposited += amount;
    }
}

contract SaleMintControllerTest is Test {
    SaleMintController public sale;
    MockUSDT public usdt;
    MockNFT public nft;
    MockReferralRegistry public referral;
    MockDistributionController public dist;
    MockRevenuePool public revenue;
    MockPartnerVault public partners;

    address admin = address(0x123);
    address user1 = address(0x456);
    address user2 = address(0x789);
    address treasury = address(0xABC);

    function setUp() public {
        usdt = new MockUSDT();
        nft = new MockNFT();
        referral = new MockReferralRegistry();
        dist = new MockDistributionController();
        revenue = new MockRevenuePool();
        partners = new MockPartnerVault();

        sale = new SaleMintController(
            admin,
            address(usdt),
            address(nft),
            address(referral),
            address(dist),
            address(revenue),
            address(partners),
            treasury,
            1000,  // basePrice
            100    // ownerFee
        );

        // mint USDT для пользователей
        usdt.mint(user1, 10_000);
        usdt.mint(user2, 10_000);
    }

    function testMintFlow() public {
        vm.prank(user1);
        usdt.approve(address(sale), 1100);

        vm.prank(user1);
        sale.mint(1, 0);  // без спонсора

        // Проверяем NFT
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.levelOf(1), 1);

        // Проверяем депозиты
        assertEq(revenue.totalDeposited(), 200); // poolAmt
        assertEq(partners.totalDeposited(), 5);  // partnerAmt

        // Проверяем treasury
        assertEq(usdt.balanceOf(treasury), 895); // остаток
    }

    function testMintWithSponsor() public {
        // user1 мент NFT
        vm.prank(user1);
        usdt.approve(address(sale), 1100);
        vm.prank(user1);
        sale.mint(1, 0);

        // user2 мент NFT с user1 в качестве спонсора
        vm.prank(user2);
        usdt.approve(address(sale), 1100);
        vm.prank(user2);
        sale.mint(1, 1);

        // Проверяем привязку спонсора
        assertEq(referral.sponsorOf(2), 1);
    }

    // ------------------------
    // Invariant test example
    // ------------------------
    function testInvariantTotalDeposited() public {
        vm.startPrank(user1);
        usdt.approve(address(sale), 1e6);
        for (uint i = 0; i < 5; i++) {
            sale.mint(1, 0);
        }
        vm.stopPrank();

        uint256 total = revenue.totalDeposited() + partners.totalDeposited() + usdt.balanceOf(treasury);
        uint256 expected = 5 * (sale.basePrice() + sale.ownerFee());
        assertEq(total, expected);
    }
}
