// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libs/Signature.sol";

interface ITGlod is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface ITank is IERC721 {
    function mint(address account) external;

    function currentId() external returns (uint256);
}

contract TankBiz is
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Signature for bytes32;
    using SafeMath for uint256;
    using SafeMath for uint256;

    uint256 public constant ONE_HUNDRED_PERCENT = 10000; // 100%

    uint256 public constant SECONDS_PER_DATE = 86400;

    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public TIME_TO_BUILD_TANK;

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

    event SetPriceCloneTank(
        uint256 cloneId,
        address[] erc20s,
        uint256[] prices
    );

    event CloneTank(
        address user,
        uint256 cloneId,
        uint256 parentTankId,
        uint256 tankId,
        uint256 timeToBuild
    );

    event SetSpeedUpFeeCloneTank(
        address speedupToken,
        uint256 speedupFee,
        uint256 speedupTime
    );

    event SpeedUpCloneTank(uint256 tankId, uint256 timeToBuild);

    event ClaimTank(
        address user,
        uint256 cloneId,
        uint256 parentTankId,
        uint256 tankId
    );

    event QuotaClaimReward(
        uint256 quotaMintPerDate,
        uint256 quotaUserMintPerDate,
        uint256 quotaClaim
    );

    event ClaimReward(address user, uint256 amount, string claimId);

    event FixTank(
        address user,
        uint256 tankId,
        address erc20,
        uint256 ownerFee,
        uint256 renterFee,
        string claimId
    );

    // ------ Struct ---------------

    struct Rent {
        address owner;
        address renter;
        uint256 percentOwner;
        uint256 percentRenter;
    }

    struct CloneTankPrice {
        address token;
        uint256 price;
    }

    struct CloneTankInfo {
        uint256 parentTankId;
        uint256 cloneId;
        uint256 timeBuildFinish;
        uint256 speedUpNumber;
        bool claimed;
    }

    // ------ variable ---------------

    ITank public tank;

    ITGlod public tglod;

    // token id => sell order
    mapping(uint256 => Rent) public rents;

    uint256 public maximunClone;

    mapping(uint256 => uint256) public numberCloned;

    // tankId ==> price
    mapping(uint256 => CloneTankPrice[]) public cloneTankPrices;

    // tankId ==> time to build
    mapping(uint256 => CloneTankInfo) public cloneTankInfos;

    address public treasuryWallet;

    IERC20 public speedupToken;

    uint256 public speedupFee;

    uint256 public speedupTime;

    // Claim Reward
    uint256 public expireTransactionIn;

    mapping(address => mapping(uint256 => uint256)) private _userQuota;

    mapping(uint256 => uint256) private _dateQuota;

    mapping(string => bool) private _claimedId;

    uint256 public quotaMintPerDate;

    uint256 public quotaUserMintPerDate;

    uint256 public quotaClaim;

    mapping(address => uint256) public priceFixTank;

    mapping(string => bool) private _fixTankId;

    bool public verifyQuota;

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "TankBiz: must be admin role"
        );
        _;
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "TankBiz: must be operator role"
        );
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0), "TankBiz: Address invalid");
        _;
    }

    modifier erc20PayFixTankWhitelist(address _erc20) {
        require(
            priceFixTank[_erc20] > 0,
            "TankBiz: Erc20 must be in whitelist"
        );
        _;
    }

    function initialize() public initializer {
        __AccessControlEnumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(SIGNER_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        maximunClone = 7;
        TIME_TO_BUILD_TANK = 86400 * 7;
        speedupTime = 86400 * 7;
        treasuryWallet = _msgSender();
        expireTransactionIn = 300;
        verifyQuota = true;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    function setTreasuryWallet(address _address)
        external
        onlyAdmin
        notNull(address(_address))
    {
        treasuryWallet = _address;
    }

    function setTank(ITank _tank)
        external
        onlyOperator
        notNull(address(_tank))
    {
        tank = _tank;
    }

    function setTgold(ITGlod _tglod)
        external
        onlyOperator
        notNull(address(_tglod))
    {
        tglod = _tglod;
    }

    function setMaximunClone(uint256 _maximunClone) external onlyOperator {
        maximunClone = _maximunClone;
    }

    function setTimeToBuildTank(uint256 _timeToBuild) external onlyOperator {
        TIME_TO_BUILD_TANK = _timeToBuild;
    }

    function setSpeedUpCloneTankFee(
        IERC20 _speedupToken,
        uint256 _speedupFee,
        uint256 _speedupTime
    ) external onlyOperator {
        speedupToken = _speedupToken;

        if (speedupFee != _speedupFee) {
            speedupFee = _speedupFee;
        }

        if (speedupTime != _speedupTime) {
            speedupTime = _speedupTime;
        }

        emit SetSpeedUpFeeCloneTank(
            address(speedupToken),
            speedupFee,
            speedupTime
        );
    }

    function setCloneTankPrice(
        uint256 _cloneId,
        address[] calldata _erc20s,
        uint256[] calldata _prices
    ) external onlyOperator {
        delete cloneTankPrices[_cloneId];
        uint256 length = _erc20s.length;
        require(
            length > 0 && length == _prices.length,
            "TankBiz: array length is invalid"
        );

        CloneTankPrice[] storage prices = cloneTankPrices[_cloneId];
        for (uint256 i = 0; i < length; i++) {
            require(_prices[i] > 0, "TankBiz: Price must be greater than 0");
            prices.push(CloneTankPrice(_erc20s[i], _prices[i]));
        }

        emit SetPriceCloneTank(_cloneId, _erc20s, _prices);
    }

    function setVerifyQuotaClaimReward(bool status) external onlyOperator {
        verifyQuota = status;
    }

    function setQuotaClaimReward(
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

        emit QuotaClaimReward(
            quotaMintPerDate,
            quotaUserMintPerDate,
            quotaClaim
        );
    }

    function setExpireTransactionIn(uint256 _expiredTime)
        external
        onlyOperator
    {
        require(_expiredTime > 0, "TankBiz: ExpiredTime Invalid");
        expireTransactionIn = _expiredTime;
    }

    function setPriceFixTank(address _erc20, uint256 _price)
        external
        onlyOperator
    {
        priceFixTank[_erc20] = _price;
    }

    function removePriceFixTank(address _erc20) external onlyOperator {
        delete priceFixTank[_erc20];
    }

    function rent(
        uint256 _tokenId,
        address _renter,
        uint256 _percentOwner,
        uint256 _percentRenter
    ) public whenNotPaused nonReentrant {
        address msgSender = _msgSender();

        address nftOwner = tank.ownerOf(_tokenId);

        require(nftOwner == msgSender, "TankBiz: can not rent");

        require(
            nftOwner != _renter,
            "TankBiz: can not rent if renter is owner"
        );

        require(
            _percentOwner <= ONE_HUNDRED_PERCENT,
            "TankBiz: can not rent if owner percent over 100%"
        );

        require(
            _percentRenter <= ONE_HUNDRED_PERCENT,
            "TankBiz: can not rent if renter percent over 100%"
        );

        require(
            (_percentOwner + _percentRenter) == ONE_HUNDRED_PERCENT,
            "TankBiz: can not rent if total percent difference 100%"
        );

        Rent memory info = rents[_tokenId];

        require(
            info.owner == address(0),
            "TankBiz: can not rent if erc721 already rented"
        );

        rents[_tokenId] = Rent(
            msgSender,
            _renter,
            _percentOwner,
            _percentRenter
        );

        emit RentCreated(
            address(tank),
            _tokenId,
            msgSender,
            _renter,
            _percentOwner,
            _percentRenter
        );
    }

    function cancelRent(uint256 _tokenId) public whenNotPaused nonReentrant {
        address msgSender = _msgSender();

        Rent memory info = rents[_tokenId];

        require(
            info.owner != address(0),
            "TankBiz: can not cancel rent if erc721 not rented yet"
        );

        require(
            info.owner == msgSender,
            "TankBiz: can not cancel rent if sender has not made one"
        );

        emit RentCanceled(address(tank), _tokenId, msgSender, info.renter);

        delete rents[_tokenId];
    }

    function isRenting(address _erc721, uint256 _tokenId)
        external
        view
        returns (bool)
    {
        if (address(tank) != _erc721) {
            return false;
        }

        Rent memory info = rents[_tokenId];
        return info.owner != address(0);
    }

    function cloneTank(uint256 _tankId, bytes calldata _signature)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        address sender = _msgSender();
        uint256 cloneId = numberCloned[_tankId] + 1;
        uint256 timeToBuild = _getTimeToBuild();
        require(
            tank.ownerOf(_tankId) == sender,
            "TankBiz: must be owner of token"
        );

        require(
            cloneId <= maximunClone,
            "TankBiz: the number of clone is exceed"
        );

        bytes32 hashMessage = keccak256(
            abi.encodePacked(sender, cloneId, _tankId)
        );
        bytes32 prefixed = hashMessage.prefixed();
        address singer = prefixed.recoverSigner(_signature);
        require(hasRole(SIGNER_ROLE, singer), "TankBiz: Signature Invalid");

        CloneTankPrice[] memory prices = cloneTankPrices[cloneId];
        uint256 priceLength = prices.length;
        require(priceLength > 0, "TankBiz: must be set price to clone tank");

        for (uint256 i = 0; i < priceLength; i++) {
            CloneTankPrice memory price = prices[i];
            if (price.token == address(0)) {
                payable(treasuryWallet).transfer(price.price);
            } else {
                IERC20(price.token).safeTransferFrom(
                    sender,
                    treasuryWallet,
                    price.price
                );
            }
        }

        tank.mint(sender);
        numberCloned[_tankId]++;

        uint256 boxId = tank.currentId();
        CloneTankInfo storage cloneInfo = cloneTankInfos[boxId];
        cloneInfo.cloneId = cloneId;
        cloneInfo.parentTankId = _tankId;
        cloneInfo.timeBuildFinish = timeToBuild;

        emit CloneTank(sender, cloneId, _tankId, boxId, timeToBuild);
    }

    function speedUpCloneTank(uint256 _tankId)
        external
        whenNotPaused
        nonReentrant
    {
        address sender = _msgSender();
        require(
            tank.ownerOf(_tankId) == sender,
            "TankBiz: must be owner of tank"
        );

        CloneTankInfo storage cloneInfo = cloneTankInfos[_tankId];
        require(cloneInfo.parentTankId > 0, "TankBiz: Box is not exists");
        require(!cloneInfo.claimed, "TankBiz: Box claimed already");
        require(
            cloneInfo.timeBuildFinish > block.timestamp,
            "TankBiz: Box finished build"
        );

        speedupToken.safeTransferFrom(sender, treasuryWallet, speedupFee);
       
        if (cloneInfo.timeBuildFinish - speedupTime <= block.timestamp) {
            cloneInfo.timeBuildFinish = block.timestamp;
            emit ClaimTank(
                sender,
                cloneInfo.cloneId,
                cloneInfo.parentTankId,
                _tankId
            );
            cloneInfo.claimed = true;
        }
        else{
            cloneInfo.timeBuildFinish -= speedupTime;
        }
      
        cloneInfo.speedUpNumber += 1;

        emit SpeedUpCloneTank(_tankId, cloneInfo.timeBuildFinish);
    }

    function claimTank(uint256 _tankId) public whenNotPaused nonReentrant {
        address sender = _msgSender();
        require(
            tank.ownerOf(_tankId) == sender,
            "TankBiz: must be owner of tank"
        );

        CloneTankInfo storage cloneInfo = cloneTankInfos[_tankId];
        require(cloneInfo.parentTankId > 0, "TankBiz: Tank is not exists");
        require(!cloneInfo.claimed, "TankBiz: Tank claimed already");
        require(
            cloneInfo.timeBuildFinish <= block.timestamp,
            "TankBiz: Cannot claim tank"
        );

        cloneInfo.claimed = true;

        emit ClaimTank(
            sender,
            cloneInfo.cloneId,
            cloneInfo.parentTankId,
            _tankId
        );
    }

    function claimReward(
        uint256 _amount,
        uint256 _timestamp,
        string calldata _claimId,
        bytes calldata _signature
    ) external nonReentrant whenNotPaused {
        address sender = _msgSender();

        require(
            (block.timestamp - _timestamp) <= expireTransactionIn,
            "TankBiz: Transaction Expired"
        );

        require(!_claimedId[_claimId], "TankBiz: Transaction Executed");

        bytes32 hashMessage = keccak256(
            abi.encodePacked(_amount, _timestamp, _claimId)
        );
        bytes32 prefixed = hashMessage.prefixed();
        address singer = prefixed.recoverSigner(_signature);
        require(hasRole(SIGNER_ROLE, singer), "TankBiz: Signature Invalid");

        uint256 date = _getCurrentDate();
        if (verifyQuota) {
            require(_amount <= quotaClaim, "TankBiz: Amount Is Exceed");

            require(
                _dateQuota[date] + _amount <= quotaMintPerDate,
                "TankBiz: Quota Per Date Exceed"
            );

            require(
                _userQuota[sender][date] + _amount <= quotaUserMintPerDate,
                "TankBiz: Quota User Per Date Exceed"
            );
        }

        _dateQuota[date] = _dateQuota[date].add(_amount);
        _userQuota[sender][date] = _userQuota[sender][date].add(_amount);
        _claimedId[_claimId] = true;
        tglod.mint(sender, _amount);

        emit ClaimReward(sender, _amount, _claimId);
    }

    function fixTank(
        address _erc20,
        uint256 _tankId,
        string calldata _fixId
    ) external nonReentrant whenNotPaused erc20PayFixTankWhitelist(_erc20) {
        require(!_fixTankId[_fixId], "TankBiz: Transaction Executed");

        address sender = _msgSender();
        address tokenOwner = tank.ownerOf(_tankId);

        Rent memory info = rents[_tankId];

        if (info.owner != address(0)) {
            _payFixTankFeeForRent(tokenOwner, _tankId, _erc20, _fixId, info);
        } else {
            require(sender == tokenOwner, "TankBiz: Must be token owner");

            IERC20(_erc20).safeTransferFrom(
                sender,
                treasuryWallet,
                priceFixTank[_erc20]
            );

            emit FixTank(
                sender,
                _tankId,
                _erc20,
                priceFixTank[_erc20],
                0,
                _fixId
            );
        }

        _fixTankId[_fixId] = true;
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
        string memory _fixId,
        Rent memory _info
    ) internal {
        address sender = _msgSender();

        require(
            (sender == _info.owner || sender == _info.renter) &&
                _tokenOwner == _info.owner,
            "TankBiz: Caller invalid"
        );

        uint256 price = priceFixTank[_erc20];
        uint256 ownerFee = _calculateFee(price, _info.percentOwner);
        uint256 renterFee = _calculateFee(price, _info.percentRenter);

        if (ownerFee > 0) {
            IERC20(_erc20).safeTransferFrom(
                _info.owner,
                treasuryWallet,
                ownerFee
            );
        }

        if (renterFee > 0) {
            IERC20(_erc20).safeTransferFrom(
                _info.renter,
                treasuryWallet,
                renterFee
            );
        }

        emit FixTank(sender, _tankId, _erc20, ownerFee, renterFee, _fixId);
    }

    function _getTimeToBuild() internal view returns (uint256) {
        return block.timestamp + TIME_TO_BUILD_TANK;
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
