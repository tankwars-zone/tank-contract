// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libs/Signature.sol";

interface WrapToken is IERC20 {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}

contract Bridge is
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeERC20 for WrapToken;
    using Signature for bytes32;

    event Deposit(
        address sender,
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 fee,
        address recipientAddress
    );

    event Withdraw(
        address sender,
        address fromToken,
        address toToken,
        uint256 amount,
        address recipientAddress,
        bytes32 depositTxid
    );

    struct Wrap {
        address toToken;
        uint256 fee;
        bool isWrap;
        bool has;
    }

    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    uint256 public constant ONE_HUNDRED_PERCENT = 10000; // 100%

    address public treasuryWallet;

    uint256 minThreshold;

    mapping(bytes32 => bool) public executed;

    mapping(address => Wrap) public tokens;

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Bridge: must be admin role"
        );
        _;
    }

    modifier onlyValidator() {
        require(
            hasRole(VALIDATOR_ROLE, _msgSender()),
            "Bridge: must be admin role"
        );
        _;
    }

    function initiallize() external initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(VALIDATOR_ROLE, _msgSender());
        minThreshold = 1;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    function setTreasuryWallet(address _treasuryWallet) external onlyAdmin {
        treasuryWallet = _treasuryWallet;
    }

    function setMinThreshold(uint256 _minThreshold) external onlyAdmin {
        minThreshold = _minThreshold;
    }

    function setToken(
        address _fromToken,
        address _toToken,
        uint256 _fee,
        bool _isWrap
    ) external onlyAdmin {
        tokens[_fromToken] = Wrap(_toToken, _fee, _isWrap, true);
    }

    function removeToken(address _fromToken) external onlyAdmin {
        delete tokens[_fromToken];
    }

    function estimate(address _fromToken, uint256 _amount)
        public
        view
        returns (uint256 amount, uint256 fee)
    {
        Wrap memory tokenWrap = tokens[_fromToken];
        require(tokenWrap.has, "Bridge: unsupport token");

        fee = _calculateFee(_amount, tokenWrap.fee);
        amount -= fee;
    }

    function deposit(
        address _fromToken,
        uint256 _amount,
        address _recipientAddress
    ) external whenNotPaused {
        address sender = _msgSender();

        Wrap memory tokenWrap = tokens[_fromToken];
        require(tokenWrap.has, "Bridge: unsupport token");
        require(
            _fromToken != address(0) && _recipientAddress != address(0),
            "Bridge: address invalid"
        );

        uint256 fee = _calculateFee(_amount, tokenWrap.fee);
        uint256 amount = _amount - fee;

        if (tokenWrap.isWrap) {
            IERC20(_fromToken).safeTransferFrom(sender, address(this), amount);
            WrapToken(_fromToken).burn(amount);
        } else {
            IERC20(_fromToken).safeTransferFrom(sender, address(this), amount);
        }

        if (fee > 0) {
            IERC20(_fromToken).safeTransferFrom(sender, treasuryWallet, fee);
        }

        emit Deposit(
            sender,
            _fromToken,
            tokenWrap.toToken,
            amount,
            fee,
            _recipientAddress
        );
    }

    function withdraw(
        address _fromToken,
        uint256 _amount,
        address _recipientAddress,
        bytes32 _depositTxid,
        bytes[] calldata _signatures
    ) external whenNotPaused nonReentrant onlyValidator {
        address sender = _msgSender();

        Wrap memory tokenWrap = tokens[_fromToken];
        require(tokenWrap.has, "Bridge: unsupport token");
        require(
            _fromToken != address(0) && _recipientAddress != address(0),
            "Bridge: address invalid"
        );

        require(
            _signatures.length >= minThreshold,
            "Bridge: require min threshold"
        );

        bytes32 key = keccak256(
            abi.encodePacked(
                _fromToken,
                _amount,
                _recipientAddress,
                _depositTxid
            )
        );

        require(!executed[key], "Bridge: transaction executed");

        for (uint256 i = 0; i < _signatures.length; i++) {
            bytes32 hashMessage = keccak256(
                abi.encodePacked(
                    sender,
                    _fromToken,
                    _amount,
                    _recipientAddress,
                    _depositTxid
                )
            );
            bytes32 prefixed = hashMessage.prefixed();
            address singer = prefixed.recoverSigner(_signatures[i]);
            require(
                hasRole(VALIDATOR_ROLE, singer),
                "Bridge: invalid validator"
            );
        }

        if (tokenWrap.isWrap) {
            WrapToken(tokenWrap.toToken).mint(_recipientAddress, _amount);
        } else {
            IERC20(tokenWrap.toToken).safeTransferFrom(
                address(this),
                _recipientAddress,
                _amount
            );
        }

        executed[key] = true;

        emit Withdraw(
            sender,
            _fromToken,
            tokenWrap.toToken,
            _amount,
            _recipientAddress,
            _depositTxid
        );
    }

    function _calculateFee(uint256 _amount, uint256 _feePercent)
        internal
        pure
        returns (uint256)
    {
        return (_amount * _feePercent) / ONE_HUNDRED_PERCENT;
    }
}
