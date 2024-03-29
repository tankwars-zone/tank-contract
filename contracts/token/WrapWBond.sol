// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract WrapWBond is AccessControlEnumerable, ERC20Burnable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    modifier onlyMinter() {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "WrapWBond: must have minter role"
        );
        _;
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        address msgSender = _msgSender();
        _setupRole(DEFAULT_ADMIN_ROLE, msgSender);
        _setupRole(MINTER_ROLE, msgSender);
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }
}
