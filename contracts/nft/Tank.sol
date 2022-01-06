// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "./../libs/Signature.sol";

contract Tank is AccessControlEnumerable, ERC721Enumerable, ERC721Burnable  {

    using Signature for bytes32;

    event BaseURIChanged(string uri);

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    string private _uri;

    uint256 private _chainId;

    mapping(uint256 => bool) public nonces;

    constructor(string memory name, string memory symbol, string memory uri, uint256 chainId) ERC721(name, symbol) {
        _uri = uri;
        _chainId = chainId;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(SIGNER_ROLE, _msgSender());
    }

    function setBaseURI(string memory uri) public virtual {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Tank: must have admin role to set");

        require(bytes(uri).length > 0, "Tank: uri is invalid");

        _uri = uri;

        emit BaseURIChanged(uri);
    }

    function mint(uint256 tokenId, address to) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "Tank: must have minter role to mint");

        _mint(to, tokenId);
    }

    function mint(uint256 tokenId, bytes memory signature) public virtual {
        require(!nonces[tokenId], "Tank: nonce was used");

        address msgSender = _msgSender();

        bytes32 message = keccak256(abi.encodePacked(tokenId, msgSender, _chainId, this)).prefixed();

        require(hasRole(SIGNER_ROLE, message.recoverSigner(signature)), "Tank: signature is invalid");

        nonces[tokenId] = true;

        _mint(msgSender, tokenId);
    }

    function mintBatch(uint256[] memory tokenIds, address[] memory accounts) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "Tank: must have minter role to mint");

        uint256 length = tokenIds.length;

        require(length > 0 && length == accounts.length, "Tank: array length is invalid");

        for (uint256 i = 0; i < length; i++) {
            _mint(accounts[i], tokenIds[i]);
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _uri;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}