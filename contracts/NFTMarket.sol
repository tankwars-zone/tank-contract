// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NFTMarket is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    uint256 constant public ONE_HUNDRED_PERCENT = 10000; // 100%

    event SystemFeePercentUpdated(uint256 percent);
    event AdminWalletUpdated(address wallet);

    event AskCreated(address erc20, address seller, uint256 price, uint256 tokenId);
    event BidCreated(address erc20, address bidder, uint256 price, uint256 tokenId);
    event BidRefunded(address erc20, address bidder, uint256 price, uint256 tokenId);
    event BidAccepted(address erc20, address bidder, address seller, uint256 price, uint256 tokenId);
    event BidCanceled(address erc20, address bidder, uint256 price, uint256 tokenId);
    event Payout(address erc20, uint256 tokenId, uint256 systemFeePayment, uint256 sellerPayment);
    event TokenSold(address erc20, address buyer, address seller, uint256 price, uint256 tokenId);

    IERC721 public nft;

    uint256 public systemFeePercent;

    address payable public adminWallet;

    struct Bid {
        address erc20;
        address bidder;
        uint256 price;
        uint256 systemFeePercent;
    }

    struct Ask {
        address erc20;
        address seller;
        uint256 price;
    }

    mapping(uint256 => Bid) public bids;

    mapping(uint256 => Ask) public asks;

    mapping(address => bool) public erc20Whitelist;

    modifier isWhitelist(address erc20) {
        require(erc20Whitelist[erc20], "NFTMarket: erc20 must be in whitelist");
        _;
    }

    modifier isTokenOwner(uint256 tokenId) {
        require(nft.ownerOf(tokenId) == _msgSender(), "NFTMarket: caller must be the token owner");
        _;
    }

    function initialize(IERC721 _nft, address[] memory erc20s, address payable _adminWallet)
        public
        initializer
    {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        nft = _nft;
        adminWallet = _adminWallet;

        systemFeePercent = 250; // 2.5%

        for (uint i = 0; i < erc20s.length; i++) {
            erc20Whitelist[erc20s[i]] = true;
        }
    }

    function setSystemFeePercent(uint256 percent)
        public
        onlyOwner
    {
        require(percent <= ONE_HUNDRED_PERCENT, "NFTMarket: percent is invalid");

        systemFeePercent = percent;

        emit SystemFeePercentUpdated(percent);
    }

    function setAdminWallet(address payable wallet)
        public
        onlyOwner
    {
        require(wallet != address(0), "NFTMarket: address is invalid");

        adminWallet = wallet;

        emit AdminWalletUpdated(wallet);
    }

    function setSalePrice(address erc20, uint256 tokenId, uint256 price)
        public
        isWhitelist(erc20)
        isTokenOwner(tokenId)
    {
        address msgSender = _msgSender();

        asks[tokenId] = Ask(erc20, msgSender, price);

        emit AskCreated(erc20, msgSender, price, tokenId);
    }

    function bid(address erc20, uint256 tokenId, uint256 price)
        public
        nonReentrant
        isWhitelist(erc20)
    {
        address msgSender = _msgSender();

        require(price > 0, "NFTMarket: can not bid 0");

        require(price > bids[tokenId].price, "NFTMarket: must place higher bid than existing bid");

        require(nft.ownerOf(tokenId) != msgSender, "NFTMarket: bidder can not be owner");

        IERC20(erc20).safeTransferFrom(msgSender, address(this), price + _calculateSystemFee(price, systemFeePercent));

        _refundBid(tokenId);

        bids[tokenId] = Bid(erc20, msgSender, price, systemFeePercent);

        emit BidCreated(erc20, msgSender, price, tokenId);
    }

    function cancelBid(uint256 tokenId)
        public
        nonReentrant
    {
        address msgSender = _msgSender();

        Bid memory info = bids[tokenId];

        require(info.bidder == msgSender, "NFTMarket: can not cancel a bid if sender has not made one");

        emit BidCanceled(info.erc20, msgSender, info.price, tokenId);

        _refundBid(tokenId);
    }

    function acceptBid(uint256 tokenId)
        public
        nonReentrant
    {
        address msgSender = _msgSender();

        Bid memory info = bids[tokenId];

        require(info.bidder != address(0), "NFTMarket: can not accept a bid when there is none");

        _payout(info.erc20, tokenId, msgSender, info.price, info.systemFeePercent);

        nft.transferFrom(msgSender, info.bidder, tokenId);

        emit BidAccepted(info.erc20, info.bidder, msgSender, info.price, tokenId);

        delete asks[tokenId];
        delete bids[tokenId];
    }

    function buy(uint256 tokenId)
        public
        nonReentrant
    {
        address msgSender = _msgSender();

        Ask memory info = asks[tokenId];

        require(info.price > 0, "NFTMarket: token price at 0 are not for sale");

        IERC20(info.erc20).safeTransferFrom(msgSender, address(this), info.price + _calculateSystemFee(info.price, systemFeePercent));

        _payout(info.erc20, tokenId, info.seller, info.price, systemFeePercent);

        nft.transferFrom(info.seller, msgSender, tokenId);

        if (bids[tokenId].bidder == msgSender) {
            _refundBid(tokenId);
        }

        emit TokenSold(info.erc20, msgSender, info.seller, info.price, tokenId);

        delete asks[tokenId];
    }

    function _payout(address erc20, uint256 tokenId, address seller, uint256 price, uint256 feePercent)
        internal
    {
        uint fee = _calculateSystemFee(price, feePercent);

        uint256 systemFeePayment = 2 * fee;

        if (systemFeePayment > 0) {
            IERC20(erc20).safeTransfer(adminWallet, systemFeePayment);
        }

        uint256 sellerPayment = price - fee;

        if (sellerPayment > 0) {
            IERC20(erc20).safeTransfer(seller, sellerPayment);
        }

        emit Payout(erc20, tokenId, systemFeePayment, sellerPayment);
    }

    function _refundBid(uint256 tokenId)
        internal
    {
        Bid memory info = bids[tokenId];

        if (info.bidder == address(0)) {
            return;
        }

        uint256 refund = info.price + _calculateSystemFee(info.price, info.systemFeePercent);

        IERC20(info.erc20).safeTransfer(info.bidder, refund);

        emit BidRefunded(info.erc20, info.bidder, info.price, tokenId);

        delete bids[tokenId];
    }

    function _calculateSystemFee(uint256 price, uint256 feePercent)
        internal
        pure
        returns (uint256)
    {
        return price * feePercent / ONE_HUNDRED_PERCENT;
    }

}