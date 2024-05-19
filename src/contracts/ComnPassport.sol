// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@thirdweb-dev/contracts/extension/LazyMintWithTier.sol";
import "@thirdweb-dev/contracts/lib/CurrencyTransferLib.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@thirdweb-dev/contracts/extension/PermissionsEnumerable.sol";
import "@thirdweb-dev/contracts/extension/PrimarySale.sol";
import "@thirdweb-dev/contracts/extension/Ownable.sol";
import "@thirdweb-dev/contracts/extension/ContractMetadata.sol";
// import "forge-std/console.sol";

function strcmp(string memory a, string memory b) pure returns (bool) {
    return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
}

function substr(string memory text, uint256 begin, uint256 end) pure returns (string memory) {
    if (end >= bytes(text).length)
        end = bytes(text).length - 1;
    bytes memory a = new bytes(end - begin + 1);
    // console.log(text, begin, end, a.length);
    for(uint i = 0; i <= end - begin; i++){
        a[i] = bytes(text)[i + begin];
        // console.log(i, string(a));
    }
    return string(a);
}

function b64decode(string memory data) pure returns (bytes memory result) {
    /// @solidity memory-safe-assembly
    assembly {
        let dataLength := mload(data)
        if dataLength {
            let decodedLength := mul(shr(2, dataLength), 3)
            for {} 1 {} {
                // If padded.
                if iszero(and(dataLength, 3)) {
                    let t := xor(mload(add(data, dataLength)), 0x3d3d)
                    // forgefmt: disable-next-item
                    decodedLength := sub(
                        decodedLength,
                        add(iszero(byte(30, t)), iszero(byte(31, t)))
                    )
                    break
                }
                // If non-padded.
                decodedLength := add(decodedLength, sub(and(dataLength, 3), 1))
                break
            }
            result := mload(0x40)
            // Write the length of the bytes.
            mstore(result, decodedLength)
            // Skip the first slot, which stores the length.
            let ptr := add(result, 0x20)
            let end := add(ptr, decodedLength)
            // Load the table into the scratch space.
            // Constants are optimized for smaller bytecode with zero gas overhead.
            // `m` also doubles as the mask of the upper 6 bits.
            let m := 0xfc000000fc00686c7074787c8084888c9094989ca0a4a8acb0b4b8bcc0c4c8cc
            mstore(0x5b, m)
            mstore(0x3b, 0x04080c1014181c2024282c3034383c4044484c5054585c6064)
            mstore(0x1a, 0xf8fcf800fcd0d4d8dce0e4e8ecf0f4)
            for {} 1 {} {
                // Read 4 bytes.
                data := add(data, 4)
                let input := mload(data)
                // Write 3 bytes.
                // forgefmt: disable-next-item
                mstore(ptr, or(
                    and(m, mload(byte(28, input))),
                    shr(6, or(
                        and(m, mload(byte(29, input))),
                        shr(6, or(
                            and(m, mload(byte(30, input))),
                            shr(6, mload(byte(31, input)))
                        ))
                    ))
                ))
                ptr := add(ptr, 3)
                if iszero(lt(ptr, end)) { break }
            }
            mstore(0x40, add(end, 0x20)) // Allocate the memory.
            mstore(end, 0) // Zeroize the slot after the bytes.
            mstore(0x60, 0) // Restore the zero slot.
        }
    }
}

struct CurrencyPrice {
    address currency;
    string tier;
    uint256 price;
}

struct PricesDiscount {
    address currency;
    uint256 price;
    uint8 discount;
}

struct Coupon {
    string id;
    uint8 discount;
    uint256 totalSupply;
    uint256 usedCount;
    uint256 expireTimestamp;
    string tier;
}

struct RangeBaseURI {
    LazyMintWithTier.TokenRange range;
    string baseURI;
    uint256[] alreadyMinted;
}

contract ComnPassport is
    MulticallUpgradeable,
    PermissionsEnumerable,
    ERC721Enumerable,
    // ContractMetadata,
    LazyMintWithTier,
    // Ownable,
    PrimarySale
{
    using StringsUpgradeable for uint256;

    // @dev The tokenId of the next token to be minted.
    uint256 internal _currentIndex;

    // @dev batchId to tier
    mapping(uint256 => string) private batchTier;

    /// @dev Mapping from tier -> the metadata ID up till which metadata IDs have been mapped to minted NFTs' tokenIds.
    mapping(string => uint256) private nextMetadataIdToMapFromTier;

    /// @dev Mapping from tier -> how many units of lazy minted metadata have not yet been mapped to minted NFTs' tokenIds.
    // mapping(string => uint256) private totalRemainingInTier;

    /// @dev Mapping from hash(tier, "minted") -> total minted in tier.
    mapping(string => uint256) private mintedInTier;

    mapping(bytes32 => address) nonces;

    /// @dev Only transfers to or from TRANSFER_ADMIN_ROLE holders are valid, when transfers are restricted.
    bytes32 private constant TRANSFER_ADMIN_ROLE = keccak256("TRANSFER_ADMIN_ROLE");
    bytes32 private constant PRICE_ADMIN_ROLE = keccak256("PRICE_ADMIN_ROLE");
    bytes32 private constant COUPON_ADMIN_ROLE = keccak256("COUPON_ADMIN_ROLE");
    bytes32 private constant MAGIC_COUPON_ADMIN_ROLE = keccak256("MAGIC_COUPON_ADMIN_ROLE");
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ADMIN_ROLE");

    event TransfersRestricted(bool isRestricted);

    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _saleRecipient
    ) ERC721(_symbol, _name)
    {
        _currentIndex = 0;

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);
        _setupRole(MAGIC_COUPON_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ADMIN_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ADMIN_ROLE, address(0));
        _setupRole(COUPON_ADMIN_ROLE, _defaultAdmin);
        _setupRole(PRICE_ADMIN_ROLE, _defaultAdmin);
        _setupPrimarySaleRecipient(_saleRecipient);
    }

    using ECDSA for bytes32;

    /// @dev Lets an account claim tokens.
    function claimWithCoupon(
        uint256 _tokenId,
        string calldata _coupon,
        address _currency,
        string calldata _tier
    ) external virtual {

        // console.log("claimWithCoupon._msgSender()", _msgSender(), _coupon);
        Coupon memory coupon = _getCoupon(_coupon);
        (uint256 discountedPrice, bytes32 sig) = _calcPrice(coupon, _currency, _tier);
        coupon.usedCount += 1;
        nonces[sig] = _msgSender();

        // If there's a price, collect price.
        if (discountedPrice > 0)
            CurrencyTransferLib.transferCurrency(
                _currency,
                _msgSender(),
                primarySaleRecipient(),
                discountedPrice
            );
        _safeMintWithTier(_tokenId, _tier, _msgSender());
    }

    function _canLazyMint() internal view override returns (bool) {
        return hasRole(MINTER_ROLE, _msgSender());
    }

    function safeMintWithTier(
        uint256 _tokenId,
        string calldata _tier,
        address _recipient
    ) public onlyRole(MINTER_ROLE) {
        _safeMintWithTier(_tokenId, _tier, _recipient);
    }

    error TokenNotInTier();
    error UnableToMint();
    error NotEnoughTokensInTier();
    error TierAlreadyOwned();

    function _safeMintWithTier(
        uint256 _tokenId,
        string calldata _tier,
        address _recipient
    ) private {

        if (!strcmp(getTierForToken(_tokenId), _tier))
            revert TokenNotInTier();

        _safeMint(_recipient, _tokenId);
    }

    function burn(uint256 _tokenId) public {
        _burn(_tokenId);
    }

    /// @dev Checks whether contract metadata can be set in the given execution context.
    // function _canSetContractURI() internal view override returns (bool) {
    //     return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    // }

    /// @dev Checks whether primary sale recipient can be set in the given execution context.
    function _canSetPrimarySaleRecipient() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    error TransferRole();
    /// @dev See {ERC721-_beforeTokenTransfer}.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, startTokenId, quantity);

        if (!hasRole(TRANSFER_ADMIN_ROLE, address(0)) && from != address(0) && to != address(0)) {
            if (!hasRole(TRANSFER_ADMIN_ROLE, from) && !hasRole(TRANSFER_ADMIN_ROLE, to)) {
                revert TransferRole();
            }
        }
    }

    /// @dev Checks whether owner can be set in the given execution context.
    // function _canSetOwner() internal view override returns (bool) {
    //     return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    // }

    /**
     * Returns the total amount of tokens minted in the contract.
     */
    function totalMinted() external view returns (uint256) {
        unchecked {
            return _currentIndex;
        }
    }

    // @dev The tokenId of the next NFT that will be minted / lazy minted.
    function nextTokenIdToMint() external view returns (uint256) {
        return nextTokenIdToLazyMint;
    }

    /*///////////////////////////////////////////////////////////////
                        ERC 165 / 721 / 2981 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) public view override returns (string memory URL) {
        URL = string(abi.encodePacked(_getBaseURI(_tokenId), _tokenId.toString()));
    }

    /*///////////////////////////////////////////////////////////////
                    Lazy minting + delayed-reveal logic
    //////////////////////////////////////////////////////////////*

    /**
     *  @dev Lets an account with `MINTER_ROLE` lazy mint 'n' NFTs.
     *       The URIs for each token is the provided `_baseURIForTokens` + `{tokenId}`.
     */
    function lazyMint(
        uint256 _amount,
        string calldata _baseURIForTokens,
        string calldata _tier,
        bytes calldata _data
    ) public override
        onlyRole(MINTER_ROLE)
        returns (uint256 batchId)
    {

        // totalRemainingInTier[_tier] += _amount;
        _currentIndex += _amount;

        uint256 startId = nextTokenIdToLazyMint;
        if (isTierEmpty(_tier) || nextMetadataIdToMapFromTier[_tier] == type(uint256).max) {
            nextMetadataIdToMapFromTier[_tier] = startId;
        }

        batchId = super.lazyMint(_amount, _baseURIForTokens, _tier, _data);
        batchTier[batchId] = _tier;
    }

    /// @dev Set baseURI for batch
    function setBatchURI(uint256 _batchId, string memory _baseURI)
        public onlyRole(MINTER_ROLE)
    {
        _setBaseURI(_batchId, _baseURI);
    }

    function  getBatchId(uint256 _tokenId) public view  returns (uint256 batchId) {
        (batchId, ) = _getBatchId(_tokenId);
    }

    /// @dev Returns the tier that the given token is associated with.
    function getTierForToken(uint256 _tokenId) public view returns (string memory mytier) {

        // Use metadata ID to return token metadata.
        (uint256 batchId, ) = _getBatchId(_tokenId);
        mytier = batchTier[batchId];
    }

    /**
     *  @notice           Restrict transfers of NFTs.
     *  @dev              Restricting transfers means revoking the TRANSFER_ADMIN_ROLE from address(0). Making
     *                    transfers unrestricted means granting the TRANSFER_ADMIN_ROLE to address(0).
     *
     *  @param _toRestrict Whether to restrict transfers or not.
     */
    function restrictTransfers(bool _toRestrict) public virtual
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (_toRestrict) {
            _revokeRole(TRANSFER_ADMIN_ROLE, address(0));
        } else {
            _setupRole(TRANSFER_ADMIN_ROLE, address(0));
        }
    }

    /// @notice Returns all metadata lazy minted for the given tier.
    function getMetadataInTier(string memory _tier)
        external view
        returns (RangeBaseURI[] memory rangeBaseURIs)
    {
        TokenRange[] memory tokens = tokensInTier[_tier];

        uint256 len = tokens.length;
        rangeBaseURIs = new RangeBaseURI[](len);

        for (uint256 i = 0; i < len; i += 1) {
            uint256 alreadyMintedLen = 0;
            uint256 rangeLen = tokens[i].endIdNonInclusive - tokens[i].startIdInclusive;
            rangeBaseURIs[i] = RangeBaseURI(tokens[i], _getBaseURI(tokens[i].startIdInclusive), new uint256[](rangeLen));
            for (uint256 j = 0; j < rangeLen; j += 1) {
                uint256 tokenId = tokens[i].startIdInclusive + j;
                if (_exists(tokenId)) {
                    rangeBaseURIs[i].alreadyMinted[alreadyMintedLen] = tokenId;
                    alreadyMintedLen += 1;
                }
            }
            uint256[] memory alreadyMinted = new uint256[](alreadyMintedLen);
            for (uint256 j = 0; j < alreadyMintedLen; j += 1) {
                alreadyMinted[j] = rangeBaseURIs[i].alreadyMinted[j];
            }
            rangeBaseURIs[i].alreadyMinted = alreadyMinted;
        }
    }

    /// @dev Coupons and discount.
    Coupon[] private coupons;

    function addCoupon(
        string calldata _couponid,
        uint8 _discount,
        uint256 _totalSupply,
        uint256 _expireTimestamp,
        string calldata _opt_tier
    )
        public virtual
        onlyRole(COUPON_ADMIN_ROLE)
    {
        uint256 i = getCouponIdx(_couponid);
        Coupon memory coupon = Coupon(_couponid, _discount, _totalSupply, 0, _expireTimestamp, _opt_tier);
        if (i == type(uint256).max)
        {
            coupons.push(coupon);
        }
        else
        {
            coupons[i] = coupon;
        }
    }

    function getCoupon(string calldata _coupon)
        public virtual view
        onlyRole(COUPON_ADMIN_ROLE)
        returns (Coupon memory)
    {
        return _getCoupon(_coupon);
    }

    function _getCoupon(string calldata _coupon)
        internal virtual view
        returns (Coupon memory)
    {
        uint256 i = getCouponIdx(_coupon);
        if (bytes(_coupon).length == 0 || i == type(uint256).max)
            return Coupon(_coupon, 0, 1, 0, 0, "INVALID");
        return coupons[i];
    }

   function getCouponIdx(string calldata _coupon)
        public view virtual returns (uint256)
    {
        for (uint256 i = 0; i < coupons.length; i++) {
            if (strcmp(coupons[i].id, _coupon)) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function getCoupons()
        public view virtual
        onlyRole(COUPON_ADMIN_ROLE)
        returns (string[] memory)
    {
        string[] memory couponIds = new string[](coupons.length);
        for (uint256 i = 0; i < coupons.length; i++) {
            couponIds[i] = coupons[i].id;
        }
        return couponIds;
    }

    /// @dev Prices and currencies.
    CurrencyPrice[] private prices;

    function addPrice(
        address _currency,
        string calldata _tier,
        uint256 _price
    )
        public
        onlyRole(PRICE_ADMIN_ROLE)
        returns (CurrencyPrice memory)
    {
        for (uint i; i < prices.length; i++) {
            if (prices[i].currency == _currency && strcmp(prices[i].tier, _tier))
            {
                prices[i].price = _price;
                return prices[i];
            }
        }
        CurrencyPrice memory price = CurrencyPrice(_currency, _tier, _price);
        prices.push(price);
        return price;
    }

    function supportsInterface(bytes4 interfaceId)
        public view virtual override returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function getPriceIdx(address _currency, string calldata _tier)
        private view
        returns (uint256 idx) {
        for (uint256 i = 0; i < prices.length; i++) {
            if (prices[i].currency == _currency && strcmp(prices[i].tier, _tier)) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function getPriceTierSize(string calldata _tier)
        public view returns (uint256 size)
    {
        for (uint256 i = 0; i < prices.length; i++) {
            if (strcmp(prices[i].tier, _tier)) {
                size += 1;
            }
        }
    }

    function calcPrices(
        string calldata _coupon,
        string calldata _tier
    ) public view returns (PricesDiscount[] memory cpd) {

        cpd = new PricesDiscount[](getPriceTierSize(_tier));

        Coupon memory coupon = _getCoupon(_coupon);
        uint j;
        for (uint256 i = 0; i < prices.length; i++) {
            if (strcmp(prices[i].tier, _tier)) {
                cpd[j].currency = prices[i].currency;
                (cpd[j].price, ) = _calcPrice(coupon, prices[i].currency, _tier);
                cpd[j].discount = coupon.discount;
                j += 1;
            }
        }
    }

    function calcPrice(
        string calldata _coupon,
        address _currency,
        string calldata _tier
    ) public view returns (uint256 discountedPrice) {
        Coupon memory coupon = _getCoupon(_coupon);
        (discountedPrice, ) = _calcPrice(coupon, _currency, _tier);
    }

    error CouponNotValidForTier();
    error CouponExpired();
    error CouponExhausted();
    error NoPriceForCurrency();
    error NoCouponFound();
    error InvalidCurrencyOrCoupon();

    function _calcPrice(
        Coupon memory _coupon,
        address _currency,
        string calldata _tier
    ) internal view returns (uint256 discountedPrice, bytes32 hash) {
        uint256 priceIdx = getPriceIdx(_currency, _tier);

        if (priceIdx > prices.length)
        {
            if (bytes(_coupon.id).length % 4 != 0 || bytes(_coupon.id).length < 64)
                revert InvalidCurrencyOrCoupon();

            // This recreates the message hash that was signed on the client.
            string memory param = string.concat(_tier, substr(_coupon.id, 0, 31));
            hash = keccak256(abi.encodePacked(_msgSender(), param)).toEthSignedMessageHash();

            // magic coupons are one time use only. This makes sure that it wasn't used before
            if (nonces[hash] != address(0))
                revert CouponExhausted();

            bytes memory signature = b64decode(substr(_coupon.id, 32, bytes(_coupon.id).length));
            address signer = hash.recover(signature);

            // Verify that the message's signer has the fiat role
            if (hasRole(MAGIC_COUPON_ADMIN_ROLE, signer))
                discountedPrice = 0;
            else
                revert InvalidCurrencyOrCoupon();
        }
        else if (_coupon.discount > 0)
        {

            uint256 basePrice = prices[priceIdx].price;
            if (bytes(_coupon.tier).length != 0 && !strcmp(_coupon.tier, _tier))
                revert CouponNotValidForTier();
            if (_coupon.expireTimestamp < block.timestamp && _coupon.expireTimestamp != 0)
                revert CouponExpired();

            if (_coupon.usedCount >= _coupon.totalSupply)
                revert CouponExhausted();

            discountedPrice = basePrice - ((basePrice * _coupon.discount)/100);
        }
        else if (bytes(_coupon.id).length > 0)
            revert NoCouponFound();
        else
        {
            discountedPrice = prices[priceIdx].price;
        }
    }
}
