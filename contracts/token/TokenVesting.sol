// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenVesting is Ownable {

    using SafeERC20 for IERC20;

    event PoolAdded(uint256 poolId, uint256 startTime, uint256 cliffDuration, uint256 duration);
    event PoolRemoved(uint256 poolId);
    event TokenLocked(uint256 poolId, address account, uint256 amount);
    event TokenReleased(uint256 poolId, address account, uint256 amount);

    IERC20 private _token;

    struct Pool {
        uint256 startTime;      // second
        uint256 cliffDuration;  // second
        uint256 duration;       // second
        uint256 balance;
    }

    mapping(uint256 => Pool) private _pools;

    struct Account {
        uint256 balance;
        uint256 released;
    }

    mapping(uint256 => mapping(address => Account)) private _accounts;

    modifier poolExist(uint256 poolId) {
        require(_pools[poolId].duration > 0, "TokenVesting: pool does not exist");
        _;
    }

    constructor(IERC20 token)
    {
        _token = token;
    }

    function getContractInfo()
        public
        view
        returns (address, uint256)
    {
        return (
            address(_token),
            _token.balanceOf(address(this))
        );
    }

    function addPool(uint256 poolId, uint256 startTime, uint256 cliffDuration, uint256 duration)
        public
        onlyOwner
    {
        require(_pools[poolId].duration == 0, "TokenVesting: pool existed");

        require(cliffDuration > 0 && cliffDuration <= duration, "TokenVesting: cliff duration is longer than duration");

        require(startTime + duration > block.timestamp, "TokenVesting: final time is before current time");

        _pools[poolId] = Pool(startTime, cliffDuration, duration, 0);

        emit PoolAdded(poolId, startTime, cliffDuration, duration);
    }

    function removePool(uint256 poolId)
        public
        onlyOwner
        poolExist(poolId)
    {
        require(_pools[poolId].balance == 0, "TokenVesting: pool is containing token");

        delete _pools[poolId];

        emit PoolRemoved(poolId);
    }

    function getPoolInfo(uint256 poolId)
        public
        view
        returns (Pool memory)
    {
        return _pools[poolId];
    }

    function lockToken(uint256 poolId, address[] memory accounts, uint256[] memory amounts)
        public
        onlyOwner
        poolExist(poolId)
    {
        uint256 length = accounts.length;

        require(length > 0 && length == amounts.length, "LockToken: array length is invalid"); 

        uint256 total = 0;

        for (uint256 i = 0; i < length; i++) {
            address account = accounts[i];
            uint256 amount = amounts[i];

            require(account != address(0), "TokenVesting: address is invalid");

            require(amount > 0, "TokenVesting: amount is invalid");

            total += amount;

            _pools[poolId].balance += amount;

            _accounts[poolId][account].balance += amount;

            emit TokenLocked(poolId, account, amount);
        }

        if (total > 0) {
            _token.safeTransferFrom(_msgSender(), address(this), total);
        }
    }

    function releaseToken(uint256 poolId)
        public
        poolExist(poolId)
    {
        address msgSender = _msgSender();

        uint256 amount = getVestedTokenAmount(poolId, msgSender);

        require(amount > 0, "TokenVesting: no tokens are due");

        Account storage accountInfo = _accounts[poolId][msgSender];

        accountInfo.balance -= amount;
        accountInfo.released += amount;

        _pools[poolId].balance -= amount;

        _token.safeTransfer(msgSender, amount);

        emit TokenReleased(poolId, msgSender, amount);
    }

    function getVestedTokenAmount(uint256 poolId, address account)
        public
        view
        returns (uint256)
    {
        Pool memory poolInfo = _pools[poolId];

        Account memory accountInfo = _accounts[poolId][account];

        if (block.timestamp < poolInfo.startTime + poolInfo.cliffDuration) {
            return 0;

        } else if (block.timestamp >= poolInfo.startTime + poolInfo.duration) {
            return accountInfo.balance;

        } else {
            uint256 totalBalance = accountInfo.balance + accountInfo.released;

            uint256 numCliff = (block.timestamp - poolInfo.startTime) / poolInfo.cliffDuration;

            uint256 amount = poolInfo.cliffDuration * numCliff * totalBalance / poolInfo.duration;

            return amount > accountInfo.released ? amount - accountInfo.released : 0;
        }
    }

    function getAccountInfo(uint256 poolId, address account)
        public
        view
        returns (Account memory)
    {
        return _accounts[poolId][account];
    }

}