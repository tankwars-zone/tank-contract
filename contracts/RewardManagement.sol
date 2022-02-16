// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libs/Signature.sol";

interface ITGlod {
    function mint(address to, uint256 amount) external;
}

contract RewardManagement is AccessControlEnumerable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint32;
    using Signature for bytes32;

    event ClaimReward(address, uint256, string);

    uint256 public constant SECOND_PER_DATE = 86400;
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    ITGlod public tglod;
    uint256 private _expiredTime = 300;
    mapping(address => mapping(uint32 => uint256)) private _userQuota;
    mapping(uint32 => uint256) private _dateQuota;
    mapping(string => bool) private _claimId;
    uint256 public quotaMintPerDate;
    uint256 public quotaUserMintPerDate;
    uint256 public quotaClaim;
    bool public verifyQuota;

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "RewardManagement: Must Have Operator Role"
        );
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0), "RewardManagement: Address invalid");
        _;
    }

    constructor(
        ITGlod _tglod,
        uint256 _quotaMintPerDate,
        uint256 _quotaUserMintPerDate,
        uint256 _quotaClaim
    ) {
        tglod = _tglod;
        quotaMintPerDate = _quotaMintPerDate;
        quotaUserMintPerDate = _quotaUserMintPerDate;
        quotaClaim = _quotaClaim;
        verifyQuota = true;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(SIGNER_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    function setTgold(ITGlod _tglod)
        external
        onlyOperator
        notNull(address(_tglod))
    {
        tglod = _tglod;
    }

    function setQuotaMintPerDate(uint256 amount) external onlyOperator {
        require(amount > 0, "RewardManagement: Amount Invalid");
        quotaUserMintPerDate = amount;
    }

    function setQuotaUserMintPerDate(uint256 amount) external onlyOperator {
        require(amount > 0, "RewardManagement: Amount Invalid");
        quotaUserMintPerDate = amount;
    }

    function setQuotaClaim(uint256 amount) external onlyOperator {
        require(amount > 0, "RewardManagement: Amount Invalid");
        quotaClaim = amount;
    }

    function setExpiredTime(uint256 expiredTime) external onlyOperator {
        require(expiredTime > 0, "RewardManagement: ExpiredTime Invalid");
        _expiredTime = expiredTime;
    }

    function setVerifyQuota(bool status) external onlyOperator {
        verifyQuota = status;
    }

    function claim(
        uint256 amount,
        uint256 timestamp,
        string calldata claimId,
        bytes calldata signature
    ) external nonReentrant {
        require(
            (block.timestamp - timestamp) <= _expiredTime,
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

        uint32 date = _getCurrentDate();
        if (verifyQuota) {
            require(amount <= quotaClaim, "RewardManagement: Amount Is Exceed");

            require(
                _dateQuota[date] <= quotaMintPerDate,
                "RewardManagement: Quota Per Date Exceed"
            );

            require(
                _userQuota[_msgSender()][date] <= quotaUserMintPerDate,
                "RewardManagement: Quota User Per Date Exceed"
            );
        }

        _dateQuota[date] = _dateQuota[date].add(amount);
        _userQuota[_msgSender()][date] = _dateQuota[date].add(amount);
        _claimId[claimId] = true;
        tglod.mint(_msgSender(), amount);
        emit ClaimReward(_msgSender(), amount, claimId);
    }

    function getRemainQuota() external view returns (uint256) {
        uint32 date = _getCurrentDate();
        return quotaMintPerDate - _dateQuota[date];
    }

    function getUserRemainQuota(address _address)
        external
        view
        notNull(_address)
        returns (uint256)
    {
        uint32 date = _getCurrentDate();
        return quotaUserMintPerDate - _userQuota[_address][date];
    }

    function _getCurrentDate() internal view returns (uint32) {
        return uint32(block.timestamp / SECOND_PER_DATE);
    }
}
