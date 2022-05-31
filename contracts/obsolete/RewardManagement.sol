// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libs/Signature.sol";

interface ITGlod {
    function mint(address to, uint256 amount) external;
}

interface IRenting {
    function isRenting(address erc721, uint256 tokenId)
        external
        view
        returns (bool);

    function rents(address erc721, uint256 tokenId)
        external
        view
        returns (
            address owner,
            address renter,
            uint256 percentOwner,
            uint256 percentRenter
        );
}

contract RewardManagement is
    AccessControlEnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeMath for uint256;
    using SafeMath for uint256;
    using Signature for bytes32;
    using SafeERC20 for IERC20;

    event ClaimReward(address user, uint256 amount, string claimId);

    event FixTank(
        address user,
        uint256 tankId,
        address erc20,
        uint256 ownerFee,
        uint256 renterFee,
        string claimId
    );

    uint256 public constant SECONDS_PER_DATE = 86400;
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    ITGlod public tglod;

    IERC721 public tank;

    address public adminWallet;

    uint256 public expiredTime;

    mapping(address => mapping(uint256 => uint256)) private _userQuota;

    mapping(uint256 => uint256) private _dateQuota;

    mapping(string => bool) private _claimId;

    uint256 public quotaMintPerDate;

    uint256 public quotaUserMintPerDate;

    uint256 public quotaClaim;

    mapping(address => uint256) public priceFixTank;

    bool public verifyQuota;

    IRenting public renting;

    uint256 public constant ONE_HUNDRED_PERCENT = 10000;

    mapping(string => bool) private _fixTankId;

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "RewardManagement: Must Be Operator Role"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "RewardManagement: Must Be Admin Role"
        );
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0), "RewardManagement: Address invalid");
        _;
    }

    modifier erc20Whitelist(address _erc20) {
        require(
            priceFixTank[_erc20] > 0,
            "RewardManagement: Erc20 must be in whitelist"
        );
        _;
    }

    function initialize(
        ITGlod _tglod,
        IERC721 _tank,
        address _adminWallet
    ) public initializer {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(SIGNER_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        tglod = _tglod;
        tank = _tank;
        verifyQuota = true;
        adminWallet = _adminWallet;
        expiredTime = 300;
    }

    function setTgold(ITGlod _tglod)
        external
        onlyOperator
        notNull(address(_tglod))
    {
        tglod = _tglod;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    function setAdminWallet(address _adminWallet)
        external
        onlyAdmin
        notNull(address(_adminWallet))
    {
        adminWallet = _adminWallet;
    }

    function setRenting(IRenting _renting)
        external
        onlyOperator
        notNull(address(_renting))
    {
        renting = _renting;
    }

    function setQuota(
        uint256 _quotaMintPerDate,
        uint256 _quotaUserMintPerDate,
        uint256 _quotaClaim
    ) external onlyOperator {
        if (quotaMintPerDate != _quotaMintPerDate) {
            quotaMintPerDate = _quotaMintPerDate;
        }

        if (quotaUserMintPerDate != _quotaUserMintPerDate) {
            quotaUserMintPerDate = _quotaUserMintPerDate;
        }

        if (quotaClaim != _quotaClaim) {
            quotaClaim = _quotaClaim;
        }
    }

    function setExpiredTime(uint256 _expiredTime) external onlyOperator {
        require(_expiredTime > 0, "RewardManagement: ExpiredTime Invalid");
        expiredTime = _expiredTime;
    }

    function setVerifyQuota(bool status) external onlyOperator {
        verifyQuota = status;
    }

    function setTank(IERC721 _tank) external onlyOperator {
        tank = _tank;
    }

    function setPriceFixTank(address _erc20, uint256 _price)
        external
        onlyOperator
    {
        priceFixTank[_erc20] = _price;
    }

    function claim(
        uint256 amount,
        uint256 timestamp,
        string calldata claimId,
        bytes calldata signature
    ) external nonReentrant whenNotPaused {
        require(
            (block.timestamp - timestamp) <= expiredTime,
            "RewardManagement: Transaction Expired"
        );

        require(!_claimId[claimId], "RewardManagement: Transaction Executed");

        bytes32 hashMessage = keccak256(
            abi.encodePacked(amount, timestamp, claimId)
        );
        bytes32 prefixed = hashMessage.prefixed();
        address singer = prefixed.recoverSigner(signature);
        require(
            hasRole(SIGNER_ROLE, singer),
            "RewardManagement: Signature Invalid"
        );

        uint256 date = _getCurrentDate();
        if (verifyQuota) {
            require(amount <= quotaClaim, "RewardManagement: Amount Is Exceed");

            require(
                _dateQuota[date] + amount <= quotaMintPerDate,
                "RewardManagement: Quota Per Date Exceed"
            );

            require(
                _userQuota[_msgSender()][date] + amount <= quotaUserMintPerDate,
                "RewardManagement: Quota User Per Date Exceed"
            );
        }

        _dateQuota[date] = _dateQuota[date].add(amount);
        _userQuota[_msgSender()][date] = _userQuota[_msgSender()][date].add(
            amount
        );
        _claimId[claimId] = true;
        tglod.mint(_msgSender(), amount);
        emit ClaimReward(_msgSender(), amount, claimId);
    }

    function fixTank(
        address _erc20,
        uint256 tankId,
        string calldata fixId
    ) external nonReentrant whenNotPaused erc20Whitelist(_erc20) {
        require(!_fixTankId[fixId], "RewardManagement: Transaction Executed");

        address sender = _msgSender();
        address tokenOwner = tank.ownerOf(tankId);

        if (renting.isRenting(address(tank), tankId)) {
            _payFixTankFeeForRent(tokenOwner, tankId, _erc20, fixId);
        } else {
            require(
                sender == tokenOwner,
                "RewardManagement: Must be token owner"
            );

            IERC20(_erc20).safeTransferFrom(
                sender,
                adminWallet,
                priceFixTank[_erc20]
            );
            emit FixTank(
                sender,
                tankId,
                _erc20,
                priceFixTank[_erc20],
                0,
                fixId
            );
        }

        _fixTankId[fixId] = true;
    }

    function getRemainQuota() external view returns (uint256) {
        uint256 date = _getCurrentDate();
        return quotaMintPerDate - _dateQuota[date];
    }

    function getUserRemainQuota(address _address)
        external
        view
        notNull(_address)
        returns (uint256)
    {
        uint256 date = _getCurrentDate();
        return quotaUserMintPerDate - _userQuota[_address][date];
    }

    function _payFixTankFeeForRent(
        address _tokenOwner,
        uint256 _tankId,
        address _erc20,
        string memory _fixId
    ) internal {
        address sender = _msgSender();

        (
            address owner,
            address renter,
            uint256 percentOwner,
            uint256 percentRenter
        ) = renting.rents(address(tank), _tankId);

        require(
            (sender == owner || sender == renter) && _tokenOwner == owner,
            "RewardManagement: Caller invalid"
        );

        uint256 price = priceFixTank[_erc20];
        uint256 ownerFee = _calculateFee(price, percentOwner);
        uint256 renterFee = _calculateFee(price, percentRenter);

        if (ownerFee > 0) {
            IERC20(_erc20).safeTransferFrom(owner, adminWallet, ownerFee);
        }

        if (renterFee > 0) {
            IERC20(_erc20).safeTransferFrom(renter, adminWallet, renterFee);
        }

        emit FixTank(sender, _tankId, _erc20, ownerFee, renterFee, _fixId);
    }

    function _getCurrentDate() internal view returns (uint256) {
        return (block.timestamp / SECONDS_PER_DATE);
    }

    function _calculateFee(uint256 _price, uint256 _feePercent)
        internal
        pure
        returns (uint256)
    {
        return (_price * _feePercent) / ONE_HUNDRED_PERCENT;
    }
}
