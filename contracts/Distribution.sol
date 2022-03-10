// contracts/GLDToken.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Distribution is AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    event Deposit(address indexed _from, address indexed _to, uint256 _value);
    event Withdraw(address indexed _from, address indexed _to, uint256 _value);
    event SetClaimableAddresses(address[] indexed _addresses, uint256[] _values);
    event Claim(address indexed _from, address indexed _to, uint256 _value);
    event Received(address sender, uint256 _value);
    event EmergencyWithdraw(address sender, uint256 _value);
    event AddClaimable(address indexed _address, uint256 _values);

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    using SafeERC20 for IERC20;
    IERC20 public token;

    mapping(address=>uint256) public users;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Distribution: caller is not admin");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "Distribution: caller is not operator");
        _;
    }

    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, _msgSender()), "Distribution: caller is not pauser");
        _;
    }
    /**
     * @dev init default params for contract
     */
    function initialize(IERC20 _token) 
        external 
        initializer 
    {
        token = _token;
        address msgSender = _msgSender();
        _setupRole(DEFAULT_ADMIN_ROLE, msgSender);
        _setupRole(OPERATOR_ROLE, msgSender);
        _setupRole(PAUSER_ROLE, msgSender);
        __Pausable_init();
    }

    receive()
        external
        payable
    {
        emit Received(_msgSender(), msg.value);
    }

    function emergencyWithdraw()
        external
        onlyAdmin
    {
        address msgSender = _msgSender();
        uint256 tokenAmount = token.balanceOf(address(this));
        if (tokenAmount > 0) {
            token.transfer(msgSender, tokenAmount);
        }
        uint256 ethAmount = address(this).balance;
        if (ethAmount > 0) {
            payable(msgSender).transfer(ethAmount);
        }
        emit EmergencyWithdraw(msgSender, tokenAmount);
    }

    function emergencyWithdraw(IERC20 _token)
        external
        onlyAdmin
    {
        address msgSender = _msgSender();
        uint256 tokenAmount = _token.balanceOf(address(this));
        if (tokenAmount > 0) {
            _token.safeTransfer(msgSender, tokenAmount);
        }
    }

    /**
     * @dev check contract balance
     */
    function contractBalance() external view returns (uint256 _amount) {
        return token.balanceOf(address(this));
    }

    function withdraw(uint256 _amount) external onlyAdmin nonReentrant whenNotPaused{
        require(_amount > 0, "Distribution: amount is invalid");
        address msgSender = _msgSender();
        uint256 tokenAmount = token.balanceOf(address(this));
        require(tokenAmount >= _amount, "Distribution: not enough balance");
        token.transfer(msgSender, _amount);
        emit Withdraw(address(this), msgSender, _amount);
    }

    function setClaimableAddresses(address[] calldata _addresses, uint256[] calldata _amounts) 
        external 
        onlyOperator 
    {
        uint256 lenA = _addresses.length;
        uint256 lenT = _amounts.length;
        require(lenA == lenT, "Distribution: claimable is invalid");
        for (uint256 i = 0; i < lenA; i++){
            users[_addresses[i]] += _amounts[i];
        }
        emit SetClaimableAddresses(_addresses, _amounts);
    }

    function removeClaimableAddresses(address[] calldata _addresses) 
        external 
        onlyOperator 
    {   
        uint256 lenA = _addresses.length;
        for (uint256 i = 0; i < lenA; i++){
            delete users[_addresses[i]];
        }
    }

    function addClaimable(address _wallet, uint256 _amount)
        external
        onlyOperator
    {
        require(_amount > 0, "Distribution: amount is invalid");
        users[_wallet] += _amount;
        emit AddClaimable(_wallet,_amount);
    }

    function getClaimableAmount(address _address) 
        external 
        view
        returns (uint256 _amount)
    {
        return users[_address];
    }

    function claim() 
        external
        nonReentrant
        whenNotPaused
    {   
        address msgSender = _msgSender();
        uint256 tokenAmount = token.balanceOf(address(this));
        uint256 amount = users[msgSender];
        require(tokenAmount >= amount, "Distribution: not enough balance");
        require(amount > 0, "Distribution: reward is zero");
        users[msgSender] = 0;
        token.transfer(msgSender, amount);
        emit Claim(address(this), msgSender, amount);
    }
    function pause() external onlyPauser {
        _pause();
    }

    function unpause() external onlyPauser {
        _unpause();
    }
}