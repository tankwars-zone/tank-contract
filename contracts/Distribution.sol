// contracts/GLDToken.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Distribution is AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuard {

    event Deposit(address indexed _from, address indexed _to, uint256 _value);
    event Withdraw(address indexed _from, address indexed _to, uint256 _value);
    event AddOperator(address _operator);
    event RevokeOperator(address _operator);
    event SetClaimableAddresses(address[] indexed _addresses, uint256[] _values);
    event Claim(address indexed _from, address indexed _to, uint256 _value);
    event Received(address sender, uint256 _value);
    event EmergencyWithdraw(address sender, uint256 _value);
    event AddClaimable(address indexed _address, uint256 _values);

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public token;

    mapping(address => bool) private operators;
    uint32 private countOperator;

    struct User {
        address wallet;
        uint256 reward;
    }

    User[] private users;

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
        public 
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
        public
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
        public
        onlyAdmin
    {
        address msgSender = _msgSender();
        uint256 tokenAmount = _token.balanceOf(address(this));
        if (tokenAmount > 0) {
            _token.transfer(msgSender, tokenAmount);
        }
    }

    /**
     * @dev check contract balance
     */
    function contractBalance() public view returns (uint256 _amount) {
        return token.balanceOf(address(this));
    }

    function withdraw(uint256 _amount) external onlyOperator nonReentrant whenNotPaused{
        require(_amount > 0, "Distribution: amount is invalid");
        address msgSender = _msgSender();
        uint256 tokenAmount = token.balanceOf(address(this));
        require(tokenAmount >= _amount, "Distribution: not enough balance");
        token.transfer(msgSender, _amount);
        emit Withdraw(address(this), msgSender, _amount);
    }

    function addOperator(address _operator)
        public
        onlyAdmin 
    {
        require(!operators[_operator], "Distribution: This operator is existed!");
        operators[_operator] = true;
        _setupRole(OPERATOR_ROLE, _operator);
        emit AddOperator(_operator);
    }

    function revokeOperator(address _operator)
        public
        onlyAdmin
    {
        require(operators[_operator], "Distribution: This operator is not existed!");
        revokeRole(OPERATOR_ROLE, _operator);
        operators[_operator] = false;
        emit RevokeOperator(_operator);
    }

    function checkExistOperator(address _operator)
        public
        view
        onlyAdmin
        returns
        (bool)
    {
        return operators[_operator];
    }

    function setClaimableAddresses(address[] memory _addresses, uint256[] memory _amounts) 
        public 
        onlyOperator 
    {
        uint256 lenA = _addresses.length;
        uint256 lenT = _amounts.length;
        require(lenA == lenT, "Distribution: claimable is invalid");
        delete users;
        for (uint256 i = 0; i < lenA; i++){
            users.push(User({
                wallet: _addresses[i],
                reward: _amounts[i]
            }));
        }
    }

    function addClaimable(address _wallet, uint256 _amount)
        public
        onlyOperator
    {
        require(_amount > 0, "Distribution: amount is invalid");
        uint256 length = users.length;
        bool check = false;
        for (uint256 i = 0; i < length; i++) {
            if (users[i].wallet == _wallet) {
                check = true;
                users[i].reward = users[i].reward + _amount;
                break;
            }
        }
        if (!check) {
            users.push(User({
                wallet: _wallet,
                reward: _amount
            }));
        }
        emit AddClaimable(_wallet,_amount);
    }

    function getClaimableAmount() 
        public 
        view
        returns (uint256 _amount)
    {
        address msgSender = _msgSender();
        _amount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i].wallet == msgSender) {
                _amount = users[i].reward;
                break;
            }
        }
        return _amount;
    }

    function getUsers() 
        public 
        view
        onlyOperator
        returns (User[] memory)
    {
        return users;
    }

    function claim() 
        external
        nonReentrant
        whenNotPaused
    {   
        address msgSender = _msgSender();
        uint256 tokenAmount = token.balanceOf(address(this));
        uint256 amount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i].wallet == msgSender) {
                amount = users[i].reward;
                require(tokenAmount >= amount, "Distribution: not enough balance");
                users[i].reward = 0;
                break;
            }
        }
        require(amount > 0, "Distribution: reward is zero");
        token.transfer(msgSender, amount);
        emit Claim(address(this), msgSender, amount);
    }
    function pause() public onlyPauser {
        _pause();
    }

    function unpause() public onlyPauser {
        _unpause();
    }
}
