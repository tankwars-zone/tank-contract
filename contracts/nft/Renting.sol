// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Renting is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant ONE_HUNDRED_PERCENT = 10000; // 100%

    event Erc721WhitelistUpdated(address[] erc721s, bool status);

    event RentCreated(
        address erc721,
        uint256 tokenId,
        address owner,
        address renter,
        uint256 percentOwner,
        uint256 percentRenter
    );

    event RentCanceled(
        address erc721,
        uint256 tokenId,
        address owner,
        address renter
    );

    struct Rent {
        address owner;
        address renter;
        uint256 percentOwner;
        uint256 percentRenter;
    }

    // erc721 address => status
    mapping(address => bool) public erc721Whitelist;
    
    // erc721 address => token id => sell order
    mapping(address => mapping(uint256 => Rent)) public rents;

    function initialize() public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    modifier inWhitelist(address erc721) {
        require(
            erc721Whitelist[erc721],
            "Renting: erc721 must be in whitelist"
        );
        _;
    }

    function updateErc721Whitelist(address[] memory erc721s, bool status)
        public
        onlyOwner
    {
        uint256 length = erc721s.length;

        require(length > 0, "Renting: array length is invalid");

        for (uint256 i = 0; i < length; i++) {
            erc721Whitelist[erc721s[i]] = status;
        }

        emit Erc721WhitelistUpdated(erc721s, status);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function rent(
        address erc721,
        uint256 tokenId,
        address renter,
        uint256 percentOwner,
        uint256 percentRenter
    ) public whenNotPaused nonReentrant inWhitelist(erc721) {
        address msgSender = _msgSender();

        address nftOwner = IERC721(erc721).ownerOf(tokenId);

        require(
            nftOwner == msgSender,
            "Renting: can not rent"
        );

        require(
            nftOwner != renter,
            "Renting: can not rent if renter is owner"
        );

        require(
            percentOwner <= ONE_HUNDRED_PERCENT,
            "Renting: can not rent if owner percent over 100%"
        );

        require(
            percentRenter <= ONE_HUNDRED_PERCENT,
            "Renting: can not rent if renter percent over 100%"
        );

        require(
            (percentOwner + percentRenter) == ONE_HUNDRED_PERCENT,
            "Renting: can not rent if total percent difference 100%"
        );

        Rent memory info = rents[erc721][tokenId];
        
        require(
            info.owner == address(0),
            "Renting: can not rent if erc721 already rented"
        );

        rents[erc721][tokenId] = Rent(msgSender, renter, percentOwner, percentRenter);

        emit RentCreated(erc721, tokenId, msgSender, renter, percentOwner, percentRenter);
    }

    function cancelRent(address erc721, uint256 tokenId)
        public
        whenNotPaused
        nonReentrant
    {
        address msgSender = _msgSender();

        Rent memory info = rents[erc721][tokenId];

        require(
            info.owner != address(0),
            "Renting: can not cancel rent if erc721 not rented yet"
        );

        require(
            info.owner == msgSender,
            "Renting: can not cancel rent if sender has not made one"
        );

        emit RentCanceled(erc721, tokenId, msgSender, info.renter);

        delete rents[erc721][tokenId];
    }

    function isRenting(address erc721, uint256 tokenId)
        external view
        returns(bool)
    {
        Rent memory info = rents[erc721][tokenId];
        return info.owner != address(0);
    }
}