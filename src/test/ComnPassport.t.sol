// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@thirdweb-dev/contracts/extension/LazyMintWithTier.sol";
import "@thirdweb-dev/contracts/lib/CurrencyTransferLib.sol";
import "@thirdweb-dev/contracts/lib/TWStrings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@thirdweb-dev/contracts/eip/interface/IERC721A.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


import {b64decode, substr, ComnPassport, Coupon, PricesDiscount,
        CurrencyPrice, RangeBaseURI} from "../contracts/ComnPassport.sol";

// mock class using ERC20
contract ERC20Mock is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) payable ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function transferInternal(
        address from,
        address to,
        uint256 value
    ) public {
        _transfer(from, to, value);
    }

    function approveInternal(
        address owner,
        address spender,
        uint256 value
    ) public {
        _approve(owner, spender, value);
    }
}

contract BaseSetup is Test {
    using TWStrings for uint256;
    using ECDSA for bytes32;

    ComnPassport internal passport;
    address comnAddr;
    bytes32 couponAdminRole = keccak256("COUPON_ADMIN_ROLE");
    address admin = address(0x9876);
    address primarySeller = address(0x5678);
    address claimer = address(0x1234);
    uint256 magicCouponAdminpk = 0x11234;
    address magicCouponAdmin = vm.addr(magicCouponAdminpk);
    bytes32 magicCouponAdminRole = keccak256("MAGIC_COUPON_ADMIN_ROLE");

    ERC20Mock public comn;

    function setUp() public virtual {
        vm.startPrank(admin);

        comn = new ERC20Mock("My Coin", "MYCOIN", admin, 2_000_000_000);
        comnAddr = address(comn);
        //console.log(comnAddr);


        //comn.mint(msg.sender, 1_000_000);
        //vm.deal(msg.sender, 1_000_000);

        passport = new ComnPassport(admin, "MyCCA", "MyCCA", primarySeller);

        comn.mint(claimer, 1_000_000);
        vm.stopPrank();
    }

    function test_couponAdmin() public {
   		assertEq(passport.hasRole(couponAdminRole, admin), true);
    }

   	function test_primarySaleRecipient() public {
        vm.prank(primarySeller);
        assertEq(passport.primarySaleRecipient(), primarySeller);
   	}

    function test_addCoupon() public {
        vm.prank(admin);
        assertEq(passport.getCoupons().length, 0);

        vm.startPrank(admin);
        passport.addCoupon("SALE25", 25, 10, 0, "");
        Coupon memory coupon = passport.getCoupon("SALE25");
        assertEq(passport.getCoupons().length, 1);
        vm.stopPrank();

        assertEq(coupon.id, "SALE25");
        assertEq(coupon.discount, 25);
        assertEq(coupon.totalSupply, 10);
        assertEq(coupon.expireTimestamp, 0);

        vm.startPrank(admin);
        assertEq(passport.getCoupons().length, 1);

        passport.addCoupon("SALE25", 25, 1, 8, "");

        assertEq(passport.getCoupons().length, 1);

        passport.addCoupon("SALE15", 15, 1, 8, "");

        assertEq(passport.getCoupons().length, 2);
        vm.stopPrank();
    }

    // function test_removeCoupon() public {
    //     vm.prank(admin);
    //     assertEq(passport.getCoupons().length, 0);

    //     vm.prank(admin);
    //     passport.addCoupon("SALE25", 25, 10, 0, "");

    //     vm.prank(admin);
    //     passport.addCoupon("SALE26", 26, 15, 1, "");

    //     vm.prank(admin);
    //     assertEq(passport.getCoupons().length, 2);

    //     vm.prank(admin);
    //     string[] memory coupons = passport.getCoupons();

    //     vm.prank(admin);
    //     passport.removeCoupon(coupons[0]);

    //     vm.prank(admin);
    //     assertEq(passport.getCoupons().length, 1);

    //     vm.prank(admin);
    //     vm.expectRevert(ComnPassport.NoCouponFound.selector);
    //     passport.removeCoupon("SALETHATDOESNTEXIST");
    // }


   	function test_getCoupons() public {
        vm.prank(admin);
        passport.addCoupon("SALE25", 25, 10, 0, "");

        vm.prank(admin);
        passport.addCoupon("SALE15", 15, 1, 0, "");

        vm.prank(admin);
        string[] memory coupons = passport.getCoupons();

        assertEq(bytes32(bytes(coupons[0])), bytes32(bytes("SALE25")));
        assertEq(bytes32(bytes(coupons[1])), bytes32(bytes("SALE15")));

        vm.prank(admin);
        assertEq(passport.getCoupons().length, 2);
   	}

    function test_getCoupon() public {
        vm.prank(admin);
        assertEq(passport.getCoupons().length, 0);

        vm.prank(admin);
        passport.addCoupon("SALE25", 25, 10, 0, "");

        vm.prank(admin);
        passport.addCoupon("SALE15", 15, 1, 4, "");

        vm.prank(admin);
        string[] memory coupons = passport.getCoupons();

        vm.prank(admin);
		Coupon memory coupon = passport.getCoupon(coupons[1]);
        assertEq(coupon.id, "SALE15");
        assertEq(coupon.discount, 15);
        assertEq(coupon.totalSupply, 1);
        assertEq(coupon.expireTimestamp, 4);
        assertEq(coupon.usedCount, 0);

        vm.prank(admin);
        assertEq(passport.getCoupons().length, 2);

        vm.prank(admin);
        // vm.expectRevert(ComnPassport.NoCouponFound.selector);
		assertEq(passport.getCoupon("NOSALE").discount, 0);
    }

   	function test_addPrice() public {
        vm.prank(admin);
        assertEq(passport.calcPrices("", "producer").length, 0);

        vm.prank(admin);
        passport.addPrice(comnAddr, "producer", 15);
        PricesDiscount[] memory prices = passport.calcPrices("", "producer");
        assertEq(prices[0].price, 15);

        vm.prank(admin);
        assertEq(passport.calcPrices("", "producer").length, 1);

        vm.prank(admin);
		passport.addPrice(comnAddr, "producer", 5);

        vm.prank(admin);
        assertEq(passport.calcPrices("", "producer").length, 1);
   	}

   	// function test_removePrice() public {
    //     vm.prank(admin);
    //     assertEq(passport.getPriceSize(), 0);

    //     vm.prank(admin);
    //     CurrencyPrice memory price = passport.addPrice(comnAddr, "producer", 15);
    //     assertEq(price.price, 15);

    //     vm.prank(admin);
    //     assertEq(passport.getPriceSize(), 1);

    //     vm.prank(admin);
    //     price = passport.addPrice(address(51), "producer", 15);

    //     vm.prank(admin);
    //     assertEq(passport.getPriceSize(), 2);

    //     vm.prank(admin);
    //     vm.expectRevert(ComnPassport.NoPriceForCurrency.selector);
    //     passport.removePrice(address(21), "producer");
   	// }

   	// function test_getPrice() public {
    //     address comnAddr2 = address(321);

    //     vm.prank(admin);
    //     passport.addPrice(comnAddr, "producer", 15);

    //     vm.prank(admin);
    //     passport.addPrice(comnAddr2, "producer", 25);

    //     vm.prank(admin);
    //     uint256 price = passport.getPrice(comnAddr2, "producer");
    //     assertEq(price, 25);

    //     vm.prank(admin);
    //     vm.expectRevert(ComnPassport.NoPriceForCurrency.selector);
    //     passport.getPrice(address(21), "producer");
   	// }

    function b2h(bytes memory buffer) public pure returns (string memory) {

        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);

        bytes memory _base = "0123456789abcdef";

        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }

        return string(abi.encodePacked("0x", converted));
    }

    function sign(address _claimer, uint256 _adminpk, string memory _tier, string memory nonce)
        public pure returns (string memory signature)
    {
        // address alice = vm.addr(1);
        bytes32 hash = keccak256(abi.encodePacked(_claimer, string.concat(_tier, nonce))).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_adminpk, hash);
        signature = string(bytes.concat(bytes(nonce), bytes(Base64.encode(abi.encodePacked(r, s, v)))));

        // address signer = ecrecover(hash, v, r, s);
        // assertEq(alice, signer); // [PASS]

        // bytes32 messageHash = keccak256(abi.encodePacked(claimer, "+", "producer")).toEthSignedMessageHash();

        // Verify that the message's signer has the fiat role
        // address signer = messageHash.recover(bytes(_magiccoupon.id));
        // assertEq(passport.hasRole(keccak256("FIAT_ADMIN_ROLE"), signer), true);
        // assertEq(signer, magicCouponAdmin);
    }

    function test_calcPrice() public {
        vm.warp(12345);
        assertEq(block.timestamp, 12345);

        string memory coupon = "SALE15";
        string memory fancoupon = "SALE25FAN";
        string memory producercoupon = "SALE25PRODUCER";

        vm.startPrank(admin);
        passport.addPrice(comnAddr, "producer", 5000);
        passport.addPrice(comnAddr, "fan", 300);

        passport.addCoupon(coupon, 15, 10, 0, "");
        passport.addCoupon(fancoupon, 25, 10, 0, "fan");
        passport.addCoupon(producercoupon, 50, 10, 0, "producer");
        Coupon memory _fancoupon = passport.getCoupon("SALE25FAN");
        Coupon memory _coupon = passport.getCoupon("SALE15");
        Coupon memory _producercoupon = passport.getCoupon("SALE25PRODUCER");
        Coupon memory _blankcoupon = passport.getCoupon("");
        vm.stopPrank();

        vm.expectRevert(ComnPassport.CouponNotValidForTier.selector);
        passport.calcPrice(fancoupon, comnAddr, "producer");

        uint256 price = passport.calcPrice("", comnAddr, "fan");
        assertEq(price, 300);
        assertEq(_blankcoupon.discount, 0);
        price = passport.calcPrice(fancoupon, comnAddr, "fan");
        assertEq(price, 225);
        assertEq(_fancoupon.discount, 25);

        price = passport.calcPrice(producercoupon, comnAddr, "producer");
        assertEq(price, 2500);
        assertEq(_producercoupon.discount, 50);

        price = passport.calcPrice(coupon, comnAddr, "producer");
        assertEq(price, 4250);
        assertEq(_coupon.discount, 15);

        vm.prank(admin);
        passport.grantRole(magicCouponAdminRole, magicCouponAdmin);
        assertEq(passport.hasRole(magicCouponAdminRole, magicCouponAdmin), true);

        string memory nonce = "RANDOM0123456789RANDOM0123456789";
        string memory signature = sign(claimer, magicCouponAdminpk, "producer", nonce);
        // bytes memory dsig = b64decode(signature);
        // bytes32 hash = keccak256(abi.encodePacked(claimer, "+", "producer")).toEthSignedMessageHash();
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(magicCouponAdminpk, hash);
        // console.log(b2h(abi.encodePacked(v)), b2h(abi.encodePacked(r)), b2h(abi.encodePacked(s)));
        // bytes memory s_ = abi.encodePacked(r, s, v);
        // console.log(signature, magicCouponAdminpk, b2h(s_));

        // string memory magiccoupon = string(bytes.concat(bytes(nonce), bytes(Base64.encode(bytes(signature)))));

        // string memory nonce = substr(magiccoupon, 0, 15);
        // console.log('nonce', nonce);
        // string memory _signature = substr(magiccoupon, 15, bytes(magiccoupon).length);
        // console.log(_signature, nonce);

        vm.expectRevert(ComnPassport.NoCouponFound.selector);
        price = passport.calcPrice(signature, comnAddr, "producer");

        vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        price = passport.calcPrice(signature, address(0), "producer");

        vm.prank(claimer);
        price = passport.calcPrice(signature, address(0), "producer");
        assertEq(price, 0);

        vm.prank(claimer);
        price = passport.calcPrice(COUPONS[0], address(0), "producer");
        assertEq(price, 0);

        // vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        // vm.prank(claimer);
        // price = passport.calcPrice(COUPONS[0]Tampered, address(0), "producer");
        // assertEq(price, 0);

        for (uint i; i < NONCES.length; i++)
        {
        //     nonce = i.toString() + "ANDOM0123456789RANDOM0123456789";
            for (uint j; j < TIERS.length; j++)
            {
                signature = sign(claimer, magicCouponAdminpk, TIERS[j], NONCES[i]);
                vm.prank(claimer);
                // vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
                price = passport.calcPrice(signature, address(0), TIERS[j]);
                assertEq(price, 0);
                // console.log("nonce", NONCES[i], "signature", signature);
                assertEq(signature, COUPONS[(i*TIERS.length)+j]);
            }
        }
    }

    string [] TIERS = ["producer", "fan"];

    string[] NONCES = [
        "28a9492f23a8a2b19291e46ea7ee8ae1",
        "6b9260b1e02041a665d4e4a5117cfe16",
        "c1bd877733174102f4912169070c5bef",
        "0911d1f883d425428fcfd5628ee3d68e",
        "7b064dad507c266a161ffc73c53dcdc5",
        "59b466fd93164953e56bdd1358dc0044",
        "9fefed1f10ad7c9996efe96a589b850d",
        "03c7c0ace395d80182db07ae2c30f034",
        "edaaef12693a967c47cc1beb7c2862a6",
        "47e8b9940d67c57e6b6870083f8ce025",
        "c5341e883d09ced169abfac23dc13abc",
        "72f1a850d966375fa159121c7c8b09a1",
        "fbade9e36a3f36d3d676c1b808451dd7",
        "1abe850956fa00f0cdbc3126dd4c0088",
        "b5e9d7984e7d645c40e99ac94a060e8c",
        "244ffbcf4483ae7fc354e3f00db6b454",
        "8277e0910d750195b448797616e091ad",
        "60390c7e429e38e8449519011a24f79d",
        "92a870e23eaac7b3c576e91b807f2a60",
        "7694f4a66316e53c8cdd9d9954bd611d",
        "a9d8f44a95593393194836ca1ea5a25b",
        "7d357be239953126645d91b84899ab24",
        "7b91e738dcdcd9011b3bea8c2f8c46d8",
        "be8e3e55e766fd826109b3c7e5b39803",
        "6c8349cc7260ae62e3b1396831a8398f",
        "35f4a8d465e6e1edc05f3d8ab658c551",
        "4311359ed4969e8401880e3c1836fbe1",
        "48fbab00052197bc8bd943498b89dd71",
        "fc490ca45c00b1249bbe3554a4fdf6fb",
        "f457c545a9ded88f18ecee47145a72c0",
        "51ef186e18dc00c2d31982567235c559"
    ];

    string [] COUPONS = [
        "28a9492f23a8a2b19291e46ea7ee8ae1Qn1x7l/mBz+rkCyj0RAafkCbFmp61dwT9QfTrKXPQckyI5GJC29229wdv01pILpAHw+KUauYXBnHYHH/1wZGMBs=",
        "28a9492f23a8a2b19291e46ea7ee8ae1LydXMcIVfIlH+jwMt5Dyz2Jwtuz0wsfLI6IGLe5sIT5tq/Y0emvghL8Kpu8a/Kb4ubMOd+pA7eczbQSG5fTnLxs=",
        "6b9260b1e02041a665d4e4a5117cfe16fp6xSg+if/OM9S65Kbw+iJcOA1KcRBldKIGdroPkzf9XtnhRGHh8kUJe4gK9bHrjMT91vPq6gpHVqi4L9kVTNBs=",
        "6b9260b1e02041a665d4e4a5117cfe16wleADV8UVknRvnG4ZhiLEQ9WD5Z6DqyRxApzPpV+oPpcf8PKCnYE9GtH7YuHpe7DuWloG8UOFtsRx/43H34uWRw=",
        "c1bd877733174102f4912169070c5bef40WjfmQzUtkwCAnl5ErlXkbbpPSR9eTzPGH+RMo3UPlt8czUGobSrUOmduajsbMyYHTermhjrbJmzp7RkrfLahs=",
        "c1bd877733174102f4912169070c5bef4azQnatTPl6/dmjoMbtV+Ny2FFb2l7rsEXhVwcrmIBoY8rmsp9J99VKVYh5/SmMDKRE89+ZL0Afa+N9qqfKAaBs=",
        "0911d1f883d425428fcfd5628ee3d68eJi9t+QWZFQtpij8iR9pyRUS6X3QUQwQ1p9QsmEqKTdQmObGYLGtGQSnTgnonaWXW8Bv6Fcp89KQDbAEmDzEwZRs=",
        "0911d1f883d425428fcfd5628ee3d68eyrvF8Mdc6uqOQnpcJH0Wtplm+NTE6J+8UTA6jVC2Z89HlhFUrizt9Dx8J+8uBGPFSV4sKdz4gvcfNLhn3+vIiRs=",
        "7b064dad507c266a161ffc73c53dcdc5aWYjpz5vOFS88zkzMtJ64qJyg4jJGx3pylgkF4VYxjM4OhkJuG+RqPc9F1qqAvWhew6s1QX0ENVfG/Rd4Jw53hs=",
        "7b064dad507c266a161ffc73c53dcdc5flGaiYODF5PBA7yMzW14hp+Sy9BgSYfdufs9Ya8sisNsxEz637f9sDypceWPRK0s1DNk0z4qAQMFn2nxRElbQBs=",
        "59b466fd93164953e56bdd1358dc0044l3iW5Bk7azGawvp8ljBD8nAFu4mrgjaH+pBJ25lvvYlxcMa5m67yMRvMYaSo2qNBmDkh/ztXInUftcY6sK/FJhw=",
        "59b466fd93164953e56bdd1358dc0044vxLREgLQny/Ev98I5KbBtES5KEGo/XaDnKiH0nlUAPsN72nd3NUBRD386FrRca1GhDg52Lv2kdwfjAkygPVsLhs=",
        "9fefed1f10ad7c9996efe96a589b850dCjBHm5rWFarQL1EbyoSOlF8XhxBqKu94CL7QoGA/nHIIVVWO/pynMtdrMt7/YKm5Secha9EwQsDWfcSt0U3zfRw=",
        "9fefed1f10ad7c9996efe96a589b850d1gWmLszCMxe3+gWjWExJxKbI2T8j9w8aLMNZtM/dBuUyKa1PD7ARkSWGSzUUdWKdg8GvVMd4vsWTzX+hnKwhlRw=",
        "03c7c0ace395d80182db07ae2c30f034lQT8p+rStp5GdVzJG554Cq1/xn/IkeODT1mSEHJK2o0zot0VmuJw1aNzqjbxovNbQbB/IsMa1EpkGQJAfgfYqBs=",
        "03c7c0ace395d80182db07ae2c30f034hGtlkrTWz0GTlB+l5ZbtFKg6Zs3CggeWdu2hylAidvtkijqEydV4GHzKdPwzTaRAxCrpv4P+T4hTqXH5BCRXgBs=",
        "edaaef12693a967c47cc1beb7c2862a6v5nEBO4u0qT6qg7jTsQoMwbCtlKKInLO/DonTS0bGBhfDLevuInxYgXYWykDEJgx9bYVxvOWYA8bHaBUdHV0Zhw=",
        "edaaef12693a967c47cc1beb7c2862a6y8/Hsl3Yg35LYedmYmRz9UjL6mGKu3ua/4fTifDyI4E7zzzPGs3DUqEMaZ4bxpk88xRNBd7i26Y02NBtdP4qURs=",
        "47e8b9940d67c57e6b6870083f8ce025unqhHK4KFSpr/pd2Qesyo5ZtNnRdoWl0yzrQXG9YVt1iPrmBzfL7Q4O7k1RgxrBcyzeG7hw4YyimbNqCJMQQRhs=",
        "47e8b9940d67c57e6b6870083f8ce025BeizfKQWrosoRsOju0oi3cXehn20+oI/bGuAn1r7eiRHqAj9wFIIHIZf+i2J7jT6mELJViPkFS+6pMq51iSAzRs=",
        "c5341e883d09ced169abfac23dc13abcxTjbm+bfxsUb/sYNverps9aND22bU75eYj6JbI0FCQkbMywnWJ6959HxP+5gfvZrJpCBQ4T5/esvspNCQWbk3Bw=",
        "c5341e883d09ced169abfac23dc13abc8rLLZtc4IT64s5YjEagmSaFZblNw9ZbQzrCK7xymiqFdY1QCD7UYyqhVh1eAO//fGD3wz4me+qURy7siKHCQXRw=",
        "72f1a850d966375fa159121c7c8b09a1g/VCpy9O2UnUek9p3/S1NZ10rWDCUmN+qN196rRspN9RN+nKogvKsDlEnB1Ii9F2eBkQHMYuw8xx6YX0LNLg5Bs=",
        "72f1a850d966375fa159121c7c8b09a1k8MWg9pvhSZySQ7Ofl2TYq9OzpJ+g3uLxY7oMmpvTMlVEcJvTXKU2n+Zw8wUNP2CbWpKTE3/BtwVIWeFEzGuKxs=",
        "fbade9e36a3f36d3d676c1b808451dd7qfank7WOV0PU5D9NR5085+wDA15llnrlP8uel9xD3+wtXtX0JYWw2XJ3J12aac4Vj5gWSKN7b+Y+KUT3VZLbLRw=",
        "fbade9e36a3f36d3d676c1b808451dd7BMlfhVKry2u2zp1DX3x+kYNYz3LQw2BVwdsD8hpOCM9J9GDJ00Bf27hIiyUm0BCa73Hy9rPIpB+VE1hWSD0r7xs=",
        "1abe850956fa00f0cdbc3126dd4c00887rAmQGxrgWtLlCMUmefKLuLEKz4iMrWr76+8bspeHMw9+jRf2oKH6aaFm2jEWLWaMylrZau3lKDd9m2tI7a7gRs=",
        "1abe850956fa00f0cdbc3126dd4c00886cNc8LC3o9COdWC0c2XYIGdIDw9WqMBywe7FpWlkMDlPwNCzGpstq+ercF41YP9Nvy6WV0O+h3vCQMfDwhuHKRw=",
        "b5e9d7984e7d645c40e99ac94a060e8cMOpuxTxdGHg7QCbhJozE43aFHWCOYqsU8TL9K/3nx5InXGXzuBKZjKVDcPIZX2InSY0ygMXZi2UGdGAkQFKBihw=",
        "b5e9d7984e7d645c40e99ac94a060e8c0VKqVb73SMq6AUL8i2NjYD/3KpQJDiiTQyEhZItCw5Fj0JH6oKVODNUf77YQ0fOMLrI4ZQc32rsZc98uCMf+BRw=",
        "244ffbcf4483ae7fc354e3f00db6b454Gf72cZK/BtUgZkv6sRD4nVJSgZjAm5fyu9qYGprB1DlUj232csBr7dg8aTT6YBfsLAfcFpOGaiB/huXxfrv/gBw=",
        "244ffbcf4483ae7fc354e3f00db6b454oCYHwJXkv0+fOljqmjUdTqHwr+T3ZejOb1Q+EH6g5lwZLR0wazTuSO0C0JzeWaUOncjVsSPyx8a6VPxhf/TczRw=",
        "8277e0910d750195b448797616e091adB47tS0XFuAPvfMj4K39wluRjmJJmhDR5H5uVHzhb7Gcm+OiYPD3e92SAE4vbaEV+fOl9TLJQ/YVDP8x9qS4THBs=",
        "8277e0910d750195b448797616e091adWON/e33nM8ZzFToMLQpYCzlRyjwlBYn7fXCT/OMP69kg5YpR8LRb26/EhvyzMNu4/uTzsSQWp7bUB4D3QuIvbxs=",
        "60390c7e429e38e8449519011a24f79dffNwxDojHeaBj0eJcxRC+j9iPUKgyyoohAq4QJCZcyt+YU3mUDGF+hGNTzLrQWACOblWnOPDtrj7LoCLvPvwKxw=",
        "60390c7e429e38e8449519011a24f79dyxJII0sYMoqBp3XzW4OCom/hYjCQ4JAhHMZFRmXQGoFeJgpFpvKfGMo+BdcyYWUBW2hn+f9TXjOHWJ5SEZR84Bw=",
        "92a870e23eaac7b3c576e91b807f2a60ecP3FGTJd44fIcYGvXGAm2CWJbZYq9sBJ/0x2V+5C+cgRYP612awTOAB/hriOkSpFkyh8sEmfyq+wNqV3tVnUxw=",
        "92a870e23eaac7b3c576e91b807f2a60v9d6JW63dRF/d4PRg6gzkXSC0lZOuovd6VeidK63YilLLjd0rb0wnuUQuoJ82FtM9+B0RiPHrR2ouQXk8Nmm9Rw=",
        "7694f4a66316e53c8cdd9d9954bd611dYqWTr/RoGSNMQO54rj5r5g0Uh1wXbQjOKD09QK9U2acvnro1OxA7+sUNlxaMfIZgXfRwXB/CaiDdSN412ViAcBw=",
        "7694f4a66316e53c8cdd9d9954bd611dGDEC+5gHEpuhyfVMFxAVMkvCtXePJJvgP3iONdN5ZHNvgQmW+vLDkvTcCkVmVZ7B9NLxhYH4KCFYmRjHngngDxw=",
        "a9d8f44a95593393194836ca1ea5a25bYnCI5nf6pfQWXYAB/QTFjtMpM+4gdNpmkq4p5TDJPnU6LQskAN0vOTD0WZG/AyepIxTleJ+jyBmsBksLqDX3Fhw=",
        "a9d8f44a95593393194836ca1ea5a25bsWJAlDVDQzJMZsCrU1Gaf8GjP0GfLa3Wyus6RhwKb+JSW8U+QKw4Fmo/UVj3ZjMFjnseKo9YMq/3X3yKA2Qtcxs=",
        "7d357be239953126645d91b84899ab24HjQOj5Q2E+7dUEc+nbMU/uVXsxEPar141oTCfiR+l5FYjs96tfDgwt06kTIpE4PdyR8chZNgEkOFEHMrTc5q7Rs=",
        "7d357be239953126645d91b84899ab24Th9BZ7NESnsDm2W6g2tzQPEIQdLmk+6+Lk68jCQ5G2cxaQ+GguD3AeHhtjMqUbVn4sDYjNP6hctjxSdWA1WJyRw=",
        "7b91e738dcdcd9011b3bea8c2f8c46d8OAnCDi6b7St/TKKkmiBKMfvoGtl7WQOCi3meSw6w/sJ4r3VET0BcUedZ4q5+3fcbkQMgnY6KvJfEzrhkHvA7Wxw=",
        "7b91e738dcdcd9011b3bea8c2f8c46d8yEuAUtwLqVJ4yZaw/gsft8rVRefvi+Y/rtkTIw/ZMiwwITYsG5gWh+uCVqWaNiaVzUYSeH8BZGP4CZenoIFAYhw=",
        "be8e3e55e766fd826109b3c7e5b39803pVyCVa/ojzwadvlF1jznFAGTJhX4LfvZZvuyM1YfdA11VQtKGTbsq6ihGv7fF7pP/F2sFtnu0KK6JjNqDGVF5hw=",
        "be8e3e55e766fd826109b3c7e5b398037LXCIEWtM6T3Kdo4MtH3Yxpf1iPieeLoFV1oBuxM13UBDhL/nHwACkgz+cWYya/hzpJHjRjpQMzi7se976H8/Bs=",
        "6c8349cc7260ae62e3b1396831a8398fYA4d7EMHN6UqcoqShkKI+t7qT7QbgwxLCj63r6MRdkh7RJI6yy9u2T68XT7jMjoPlS8HIhlU2PGgIAE5OZuxGRw=",
        "6c8349cc7260ae62e3b1396831a8398f0CyH/z9dexjTdxr7+xUE84aNsaNCb+ljItqBeRrCxZ8qOXI1BIOv9NQlO9xajTcVpT2sWrEN6Bxri4aoD0UjVBw=",
        "35f4a8d465e6e1edc05f3d8ab658c5516zCoIhRHMV0ixlAxAaENznH5nrFWq5dhy6O6Wy/Qz0x8qmmmnzr6rjXrNg9tlM0JtKjFYppa4w6tKevxrcj5bhw=",
        "35f4a8d465e6e1edc05f3d8ab658c551oOpW8uGtGhDdiKc5c4WhQrlk39F5A7kt/xjmXeD+/P4Ym1bF1zMLVFVqnLeLHTqShkghcY4REszVR9tSsqRQDxs=",
        "4311359ed4969e8401880e3c1836fbe1SxcZCHf4UkCjtQrmeeCN25M+zrMaIEyj/PyQPkEah+YtOTBdJg4an79FRhS8AaMP9LSVs5tKXjg49HKgfqVWRRs=",
        "4311359ed4969e8401880e3c1836fbe1Rwi3FG8Lbuzan81TOmQOZFytaQfs+dZ8G8JaMfw+cmtRUWwJIIh3nVLHn2clCWgeAwisQMKTYP2VaZ1w9MeGWRs=",
        "48fbab00052197bc8bd943498b89dd71XmRqo/B4pd+d7Lfo6yNprOUVGh+LMMKuAXLUFq+SBylGL0sN8NTI7OpmnWx/R7YElMxG9B2AHRVpSHqKYUSpXhs=",
        "48fbab00052197bc8bd943498b89dd71kMj5ya1torWTwr+LLh7KBaLuHvw+lj8QgzuBODVnnRd2GSmpWj1Z8mRd6EFKl2snnwCz8kwazSUNEkfPPJalExs=",
        "fc490ca45c00b1249bbe3554a4fdf6fbKF5I31O3mYDCF8d9Pk4vXjOnLH5tk04zciA/XD4y4ENXWj+SgTlS49m8FxNHVBFx354ms+CnUOaFtw/BZwY1hBw=",
        "fc490ca45c00b1249bbe3554a4fdf6fbp+SpHhvueczq01imN6fth2mLyYj05Vw2aPylTkUHaDhWnOGA7gPvaSU6EjfvmtmfUUnqVH6PgylM3H+YXWm4Axs=",
        "f457c545a9ded88f18ecee47145a72c0/9y8qLX2ZDCbIA18ASpEKui3lIdQQjBsq5lZWmgVilEYBJExuhKCEE4dzuekEpde6aOFHr2W3vJiFe36zpPQJBs=",
        "f457c545a9ded88f18ecee47145a72c0206MwQw6OZU40fTdkBUoQr9851T7oizKP7/IB9CTGyxb6Gy3taJsC6huauCr3NiCC2m7B/FZsM6Fcymybrk8Wxs=",
        "51ef186e18dc00c2d31982567235c559PV13ETKvEwHhpQAtRGuxDWcKKz+n8692euRbqeMizJQJFcqGS8SFwu4cTT+yMmRFs6MMOd0/Z/VBMUxlvHDCfBs=",
        "51ef186e18dc00c2d31982567235c559yWU6/q/9JIxSjEMiKhlBx7Ro3UimWCfcW7WPwNNwM9Np2OlFfMSsmvCKCVsq7SRc5HtKrlMomiYdC+Yy9qFP8Bs="
    ];

    function test_safeMintWithTier() public {
        vm.warp(12345);
        assertEq(block.timestamp, 12345);

        vm.prank(admin);
        uint256 batchid = passport.lazyMint(200, "ipfs://qqq", "producer", "");
        assertEq(passport.getBatchId(5), 200);
        assertEq(passport.tokenURI(5), "ipfs://qqq5");

        vm.prank(admin);
        passport.setBatchURI(200, "ipfs://QQQ/");
        assertEq(passport.tokenURI(8), "ipfs://QQQ/8");

        vm.expectRevert("ERC721: invalid token ID");
        assertEq(passport.ownerOf(batchid-1), address(0));

        address minter = address(0x7777);

        vm.prank(minter);
        vm.expectRevert("Permissions: account 0x0000000000000000000000000000000000007777 is missing role 0x70480ee89cb38eff00b7d23da25713d52ce19c6ed428691d22c58b2f615e3d67");
        passport.safeMintWithTier(batchid-1, "producer", claimer);

        vm.prank(admin);
        passport.grantRole(keccak256("MINTER_ADMIN_ROLE"), minter);

        vm.startPrank(minter);
        vm.expectRevert("ERC721: mint to the zero address");
        passport.safeMintWithTier(batchid-1, "producer", address(0));
        vm.expectRevert("Invalid tokenId");
        passport.safeMintWithTier(batchid, "producer", claimer);
        passport.safeMintWithTier(batchid-1, "producer", claimer);
        vm.stopPrank();

        assertEq(passport.ownerOf(batchid-1), claimer);
    }

   	function test_claimWithCoupon() public {

        vm.warp(12345);
        assertEq(block.timestamp, 12345);

        vm.prank(admin);
        passport.addPrice(comnAddr, "producer", 500);

        string memory coupon = "SALE25";
        vm.prank(admin);
        passport.addCoupon(coupon, 25, 0, 0, "");

        assertEq(passport.hasRole(keccak256("MINTER_ADMIN_ROLE"), admin), true);
        vm.startPrank(admin);
        uint256 batchid = passport.lazyMint(200, "ipfs://qqq", "producer", "");
        assertEq(batchid, 200);
        batchid = passport.lazyMint(200, "ipfs://qqq", "fan", "");
        assertEq(batchid, 400);
        vm.stopPrank();

        PricesDiscount[] memory prices = passport.calcPrices("", "producer");
        assertEq(prices[0].price, 500);
        assertEq(prices[0].discount, 0);
        vm.prank(claimer);
        comn.increaseAllowance(address(passport), prices[0].price);

        vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        vm.prank(claimer);
        passport.claimWithCoupon(0, "NOSALE", address(0), "producer");

        vm.prank(claimer);
        vm.expectRevert(ComnPassport.NoCouponFound.selector);
        passport.claimWithCoupon(0, "NOSALE", comnAddr, "producer");

        vm.expectRevert(ComnPassport.CouponExhausted.selector);
        passport.claimWithCoupon(0, coupon, comnAddr, "producer");

        vm.prank(admin);
        passport.addCoupon(coupon, 25, 1, 1, "");

        vm.expectRevert(ComnPassport.CouponExpired.selector);
        passport.claimWithCoupon(0, coupon, comnAddr, "producer");

        vm.prank(admin);
        passport.addCoupon(coupon, 25, 1, 0, "");

        vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        passport.claimWithCoupon(0, coupon, address(888), "producer");

        hoax(address(passport));
        uint256 adminbalance = comn.balanceOf(admin);
        assertEq(adminbalance, 2000000000);

        passport.calcPrices("", "producer");

        prices = passport.calcPrices(coupon, "producer");
        assertEq(prices[0].price, 375);
        assertEq(prices[0].discount, 25);

        hoax(claimer);
        uint256 claimerbalance = comn.balanceOf(claimer);
        assertEq(claimerbalance, 1000000);

        vm.prank(claimer);
        comn.increaseAllowance(address(passport), prices[0].price);

        assertEq(comn.allowance(claimer, address(passport)), 875);

        vm.prank(claimer);
        vm.expectRevert("Invalid tokenId");
        passport.claimWithCoupon(type(uint256).max, coupon, comnAddr, "producer");

        assertEq(comn.allowance(claimer, address(passport)), 875);
        vm.prank(claimer);
        passport.claimWithCoupon(9, "", comnAddr, "producer");
        assertEq(comn.allowance(claimer, address(passport)), 375);

        vm.prank(admin);
        string memory tier = passport.getTierForToken(0);
        assertEq(tier, "producer");

        vm.expectRevert("ERC721: invalid token ID");
        passport.ownerOf(0);

        comn.increaseAllowance(address(passport), prices[0].price);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        passport.claimWithCoupon(0, coupon, comnAddr, "producer");

        vm.prank(claimer);
        // vm.expectRevert(IERC721A.TransferCallerNotOwnerNorApproved.selector);
        passport.claimWithCoupon(0, coupon, comnAddr, "producer");
        assertEq(comn.allowance(claimer, address(passport)), 0);

        address owner = passport.ownerOf(0);
        assertEq(owner, claimer);
        assertEq(owner, address(0x1234));

        vm.prank(admin);
        passport.grantRole(magicCouponAdminRole, magicCouponAdmin);
        assertEq(passport.hasRole(magicCouponAdminRole, magicCouponAdmin), true);
        string memory nonce = "RANDOM0123456789RANDOM0123456789";
        string memory signature = sign(claimer, magicCouponAdminpk, "producer", nonce);

        vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        passport.claimWithCoupon(199, signature, address(0), "producer");

        vm.prank(claimer);
        passport.claimWithCoupon(199, signature, address(0), "producer");

        vm.prank(claimer);
        vm.expectRevert(ComnPassport.CouponExhausted.selector);
        passport.claimWithCoupon(199, signature, address(0), "producer");

        vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        passport.claimWithCoupon(198, COUPONS[0], address(0), "producer");

        vm.prank(claimer);
        passport.claimWithCoupon(299, COUPONS[1], address(0), "fan");

        vm.prank(claimer);
        vm.expectRevert(ComnPassport.CouponExhausted.selector);
        passport.claimWithCoupon(300, COUPONS[1], address(0), "fan");

        // vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        // passport.claimWithCoupon(198, "RANDOMSTRING1234", address(0), "producer");

        vm.prank(claimer);
        passport.claimWithCoupon(198, COUPONS[0], address(0), "producer");

        vm.prank(claimer);
        vm.expectRevert(ComnPassport.CouponExhausted.selector);
        passport.claimWithCoupon(198, COUPONS[0], address(0), "producer");

        // vm.prank(claimer);
        // vm.expectRevert(ComnPassport.InvalidCurrencyOrCoupon.selector);
        // passport.claimWithCoupon(198, COUPONS[0]Tampered, address(0), "producer");
   	}

    function test_lazyMint() public {

        vm.warp(12345);
        assertEq(block.timestamp, 12345);

        vm.prank(admin);
        passport.addPrice(comnAddr, "producer", 500);

        string memory coupon = "SALE25";
        vm.prank(admin);
        passport.addCoupon(coupon, 25, 10, 0, "");

        assertEq(passport.hasRole(keccak256("MINTER_ADMIN_ROLE"), admin), true);

        vm.startPrank(admin);
        passport.lazyMint(200, "ipfs://QQQ/", "producer", "");
        passport.lazyMint(200, "ipfs://FFF/", "fan", "");
        passport.lazyMint(200, "ipfs://PPP/", "producer", "");
        vm.stopPrank();

        assertEq(passport.getTierForToken(0), "producer");
        assertEq(passport.tokenURI(0), "ipfs://QQQ/0");
        assertEq(passport.tokenURI(220), "ipfs://FFF/220");
        assertEq(passport.tokenURI(199), "ipfs://QQQ/199");
        assertEq(passport.tokenURI(411), "ipfs://PPP/411");

        vm.expectRevert("ERC721: invalid token ID");
        passport.ownerOf(0);

        RangeBaseURI[] memory rangeBaseURIs = passport.getMetadataInTier("producer");
        assertEq(rangeBaseURIs[0].range.startIdInclusive, 0);
        assertEq(rangeBaseURIs[0].range.endIdNonInclusive, 200);
        assertEq(rangeBaseURIs[0].baseURI, "ipfs://QQQ/");
        assertEq(rangeBaseURIs[0].alreadyMinted.length, 0);
        assertEq(rangeBaseURIs[1].range.startIdInclusive, 400);
        assertEq(rangeBaseURIs[1].range.endIdNonInclusive, 600);
        assertEq(rangeBaseURIs[1].baseURI, "ipfs://PPP/");
        assertEq(rangeBaseURIs[1].alreadyMinted.length, 0);

        PricesDiscount[] memory prices = passport.calcPrices(coupon, "producer");
        assertEq(prices[0].price, 375);
        assertEq(prices[0].discount, 25);

        vm.prank(claimer);
        comn.increaseAllowance(address(passport), prices[0].price*5);

        vm.startPrank(claimer);
        passport.claimWithCoupon(0, coupon, comnAddr, "producer");
        passport.claimWithCoupon(4, coupon, comnAddr, "producer");
        passport.claimWithCoupon(13, coupon, comnAddr, "producer");
        passport.claimWithCoupon(407, coupon, comnAddr, "producer");
        passport.claimWithCoupon(539, coupon, comnAddr, "producer");
        vm.stopPrank();


        rangeBaseURIs = passport.getMetadataInTier("producer");
        assertEq(rangeBaseURIs[0].alreadyMinted.length, 3);
        assertEq(rangeBaseURIs[0].alreadyMinted[0], 0);
        assertEq(rangeBaseURIs[0].alreadyMinted[1], 4);
        assertEq(rangeBaseURIs[0].alreadyMinted[2], 13);
        assertEq(rangeBaseURIs[1].alreadyMinted.length, 2);
        assertEq(rangeBaseURIs[1].alreadyMinted[0], 407);
        assertEq(rangeBaseURIs[1].alreadyMinted[1], 539);
    }

    // function test_getCurrenciesForTier() public {
    //     vm.warp(12345);
    //     assertEq(block.timestamp, 12345);

    //     vm.startPrank(admin);
    //     passport.addPrice(comnAddr, "producer", 5000);
    //     passport.addPrice(address(1235), "producer", 7500);
    //     passport.addPrice(address(1236), "producer", 10000);
    //     passport.addPrice(comnAddr, "fan", 300);
    //     passport.addPrice(address(2235), "fan", 400);
    //     passport.addPrice(address(2236), "fan", 500);

    //     passport.addPrice(address(3236), "planet", 50000);

    //     address[] memory currs = passport.getCurrenciesForTier("producer");
    //     assertEq(currs.length, 3);
    //     assertEq(currs[0], comnAddr);
    //     assertEq(currs[1], address(1235));
    //     assertEq(currs[2], address(1236));

    //     currs = passport.getCurrenciesForTier("fan");
    //     assertEq(currs.length, 3);
    //     assertEq(currs[0], comnAddr);
    //     assertEq(currs[1], address(2235));
    //     assertEq(currs[2], address(2236));

    //     currs = passport.getCurrenciesForTier("planet");
    //     assertEq(currs.length, 1);
    //     assertEq(currs[0], address(3236));

    //     currs = passport.getCurrenciesForTier("fun");
    //     assertEq(currs.length, 0);
    // }

    function test_calcPrices() public {
        vm.warp(12345);
        assertEq(block.timestamp, 12345);

        string memory coupon = "SALE15";
        string memory fancoupon = "SALE25FAN";
        string memory producercoupon = "SALE25PRODUVER";

        vm.startPrank(admin);
        passport.addPrice(comnAddr, "producer", 5000);
        passport.addPrice(address(1235), "producer", 7500);
        passport.addPrice(address(1236), "producer", 10000);
        passport.addPrice(comnAddr, "fan", 300);
        passport.addPrice(address(1235), "fan", 400);
        passport.addPrice(address(1236), "fan", 500);

        passport.addCoupon(coupon, 15, 10, 0, "");
        passport.addCoupon(fancoupon, 25, 10, 0, "fan");
        passport.addCoupon(producercoupon, 50, 10, 0, "producer");
        Coupon memory _coupon = passport.getCoupon(fancoupon);
        vm.stopPrank();
        assertEq(_coupon.discount, 25);
        assertEq(_coupon.tier, "fan");

        vm.expectRevert(ComnPassport.CouponNotValidForTier.selector);
        passport.calcPrices(fancoupon, "producer");

        PricesDiscount[] memory prices = passport.calcPrices("", "fan");
        assertEq(prices.length, 3);
        assertEq(prices[0].currency, comnAddr);
        assertEq(prices[0].price, 300);
        assertEq(prices[0].discount, 0);
        assertEq(prices[1].currency, address(1235));
        assertEq(prices[1].price, 400);
        assertEq(prices[2].currency, address(1236));
        assertEq(prices[2].price, 500);
        prices = passport.calcPrices(fancoupon, "fan");
        assertEq(prices.length, 3);
        assertEq(prices[0].currency, comnAddr);
        assertEq(prices[0].price, 225);
        assertEq(prices[0].discount, 25);
        assertEq(prices[1].currency, address(1235));
        assertEq(prices[1].price, 300);
        assertEq(prices[2].currency, address(1236));
        assertEq(prices[2].price, 375);

        prices = passport.calcPrices(fancoupon, "fun");
        assertEq(prices.length, 0);
        prices = passport.calcPrices("", "fun");
        assertEq(prices.length, 0);
    }
}
