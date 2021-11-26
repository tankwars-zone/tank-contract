// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

interface IBPContract {

    function protect(address sender, address receiver, uint256 amount) external;

}

contract WBond is Ownable, ERC20Burnable {

    IBPContract public bpContract;

    bool public bpEnabled;
    bool public bpDisabledForever;

    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
    {
        _mint(_msgSender(), initialSupply);
    }

    function setBPContract(address addr)
        public
        onlyOwner
    {
        require(address(bpContract) == address(0), "WBond: can only be initialized once");

        bpContract = IBPContract(addr);
    }

    function setBPEnabled(bool enabled)
        public
        onlyOwner
    {
        bpEnabled = enabled;
    }

    function setBPDisableForever()
        public
        onlyOwner
    {
        require(!bpDisabledForever, "WBond: bot protection disabled");

        bpDisabledForever = true;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
    {
        if (bpEnabled && !bpDisabledForever) {
            bpContract.protect(from, to, amount);
        }
    }

}