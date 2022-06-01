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

interface ITGold is IERC20 {
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

    event RentAccepted(
        address erc721,
        uint256 tankId,
        address renter
    );

    event TakeBack(
        address erc721,
        uint256 tankId,
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
        uint256 parentTankId1,
        uint256 parentTankId2,
        uint256 cloneId1,
        uint256 cloneId2,
        uint256 tankId,
        uint256 currentStage,
        uint256 timeFinishStage
    );

    event SetCloneTankStage(
        address speedupFeeToken,
        uint256 speedupFee,
        address feeToken,
        uint256 fee,
        uint256 timeToBuild
    );

    event SpeedUpCloneTank(
        uint256 tankId,
        uint256 currentStage,
        uint256 timeFinishStage
    );

    event MorphToNextStage(
        uint256 tankId,
        uint256 currentStage,
        uint256 timeFinishStage
    );

    event ClaimTank(
        address user,
        uint256 parentTankId1,
        uint256 parentTankId2,
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
        uint256 fee,
        string fixTankId
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
        uint256 parentTankId1;
        uint256 parentTankId2;
        uint256 currentStage;
        uint256 timeBeginStage;
        uint256 timeFinishStage;
        bool claimed;
    }

    struct CloneTankStage {
        IERC20 speedupFeeToken;
        uint256 speedupFee;
        IERC20 feeToken;
        uint256 fee;
        uint256 timeToBuild;
    }

    // ------ variable ---------------

    ITank public tank;

    ITGold public tgold;

    // token id => sell order
    mapping(uint256 => Rent) public rents;

    uint256 public maximumClone;

    mapping(uint256 => uint256) public numberCloned;

    // cloneId ==> price
    mapping(uint256 => CloneTankPrice[]) public cloneTankPrices;

    // tankId ==> time to build
    mapping(uint256 => CloneTankInfo) public cloneTankInfos;

    // cloneId ==> price
    mapping(uint256 => CloneTankStage) public cloneTankStages;

    uint256 public numberCloneTankStage;

    address public treasuryWallet;

    // Claim Reward
    uint256 public expireTransactionIn;

    mapping(address => mapping(uint256 => uint256)) private _userQuota;

    mapping(uint256 => uint256) private _dateQuota;

    mapping(string => bool) private _claimeds;

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
        maximumClone = 7;
        treasuryWallet = _msgSender();
        expireTransactionIn = 300;
        verifyQuota = true;
        numberCloneTankStage = 4;
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

    function setTgold(ITGold _tgold)
        external
        onlyOperator
        notNull(address(_tgold))
    {
        tgold = _tgold;
    }

    function setNumberCloneTankStage(uint256 _numberCloneTankStage)
        external
        onlyOperator
    {
        if (numberCloneTankStage != _numberCloneTankStage) {
            numberCloneTankStage = _numberCloneTankStage;
        }
    }

    function setmaximumClone(uint256 _maximumClone) external onlyOperator {
        if (maximumClone != _maximumClone) {
            maximumClone = _maximumClone;
        }
    }

    function setCloneTankStage(
        uint256 _stage,
        IERC20 _speedupFeeToken,
        uint256 _speedupFee,
        IERC20 _feeToken,
        uint256 _fee,
        uint256 _timeToBuild
    ) external onlyOperator {
        require(_stage <= numberCloneTankStage, "TankBiz: stage invalid");

        CloneTankStage storage cloneTankStage = cloneTankStages[_stage];
        cloneTankStage.speedupFeeToken = _speedupFeeToken;
        cloneTankStage.feeToken = _feeToken;

        if (cloneTankStage.speedupFee != _speedupFee) {
            cloneTankStage.speedupFee = _speedupFee;
        }

        if (cloneTankStage.timeToBuild != _timeToBuild) {
            cloneTankStage.timeToBuild = _timeToBuild;
        }

        if (cloneTankStage.fee != _fee) {
            cloneTankStage.fee = _fee;
        }

        emit SetCloneTankStage(
            address(cloneTankStage.speedupFeeToken),
            cloneTankStage.speedupFee,
            address(cloneTankStage.feeToken),
            cloneTankStage.fee,
            cloneTankStage.timeToBuild
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

        require(!_claimeds[_claimId], "TankBiz: Transaction Executed");

        bytes32 hashMessage = keccak256(
            abi.encodePacked(sender, _amount, _timestamp, _claimId)
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
        _claimeds[_claimId] = true;
        tgold.mint(sender, _amount);

        emit ClaimReward(sender, _amount, _claimId);
    }

    function createRent(
        uint256 _tankId,
        uint256 _percentOwner,
        uint256 _percentRenter
    ) public whenNotPaused nonReentrant {
        address msgSender = _msgSender();

        address nftOwner = tank.ownerOf(_tankId);

        require(nftOwner == msgSender, "TankBiz: only owner can rent");

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

        Rent memory info = rents[_tankId];

        require(
            info.owner == address(0),
            "TankBiz: can not rent if tank already rented"
        );

        tank.transferFrom(msgSender, address(this), _tankId);

        rents[_tankId] = Rent(
            msgSender,
            address(0),
            _percentOwner,
            _percentRenter
        );

        emit RentCreated(
            address(tank),
            _tankId,
            msgSender,
            address(0),
            _percentOwner,
            _percentRenter
        );
    }

    function acceptRent(
        uint256 _tankId
    ) public whenNotPaused nonReentrant {
        address msgSender = _msgSender();
        
        Rent memory info = rents[_tankId];

        require(
            info.owner != address(0) && info.renter == address(0),
            "TankBiz: Tank not for renting or already rented"
        );

        require(info.owner != msgSender, "TankBiz: owner can not rent");

        rents[_tankId] = Rent(
            info.owner,
            msgSender,
            info.percentOwner,
            info.percentRenter
        );

        emit RentAccepted(
            address(tank),
            _tankId,
            msgSender
        );
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

    function takeBack(
        uint256 _tankId
    ) public whenNotPaused nonReentrant {
        address msgSender = _msgSender();
        
        Rent memory info = rents[_tankId];

        require(
            info.owner == msgSender,
            "TankBiz: Only owner can take back"
        );

        tank.transferFrom(address(this), msgSender, _tankId);

        emit TakeBack(
            address(tank),
            _tankId,
            msgSender,
            info.renter
        );

        delete rents[_tankId];
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

    function cloneTank(
        uint256 _tankId1,
        uint256 _tankId2,
        bytes calldata _signature
    ) external payable whenNotPaused nonReentrant {
        address sender = _msgSender();
        require(
            tank.ownerOf(_tankId1) == sender &&
                tank.ownerOf(_tankId2) == sender,
            "TankBiz: must be owner of token"
        );

        uint256 cloneId1 = numberCloned[_tankId1] + 1;
        uint256 cloneId2 = numberCloned[_tankId2] + 1;

        require(
            cloneId1 <= maximumClone && cloneId2 <= maximumClone,
            "TankBiz: the number of clone is exceed"
        );

        _checkSignature(
            keccak256(abi.encodePacked(sender, _tankId1, _tankId2)),
            _signature
        );

        CloneTankPrice[] memory priceTank1 = cloneTankPrices[cloneId1];
        CloneTankPrice[] memory priceTank2 = cloneTankPrices[cloneId2];
        uint256 priceTank1Length = priceTank1.length;
        uint256 priceTank2Length = priceTank2.length;
        require(
            priceTank1Length > 0 && priceTank2Length > 0,
            "TankBiz: must be set price to clone tank"
        );

        for (uint256 i = 0; i < priceTank1Length; i++) {
            CloneTankPrice memory price = priceTank1[i];
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

        for (uint256 i = 0; i < priceTank2Length; i++) {
            CloneTankPrice memory price = priceTank2[i];
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
        numberCloned[_tankId1]++;
        numberCloned[_tankId2]++;

        uint256 boxId = tank.currentId();
        CloneTankInfo storage cloneInfo = cloneTankInfos[boxId];
        cloneInfo.parentTankId1 = _tankId1;
        cloneInfo.parentTankId2 = _tankId2;
        cloneInfo.timeBeginStage = block.timestamp;
        cloneInfo.currentStage = 1;

        if (numberCloneTankStage > 1) {
            CloneTankStage memory stage = cloneTankStages[2];
            cloneInfo.timeFinishStage = block.timestamp + stage.timeToBuild;
        } else {
            cloneInfo.timeFinishStage = block.timestamp;
        }

        emit CloneTank(
            sender,
            _tankId1,
            _tankId2,
            cloneId1,
            cloneId2,
            boxId,
            1,
            cloneInfo.timeFinishStage
        );
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
        require(cloneInfo.timeFinishStage > 0, "TankBiz: Box is not exists");
        require(!cloneInfo.claimed, "TankBiz: Box claimed already");

        uint256 nextStageId = cloneInfo.currentStage + 1;
        require(nextStageId <= numberCloneTankStage, "TankBiz: Stage invalid");

        require(
            cloneInfo.timeFinishStage > block.timestamp,
            "TankBiz: Stage time is finished"
        );

        CloneTankStage memory stage = cloneTankStages[nextStageId];

        if (
            address(stage.speedupFeeToken) != address(0) && stage.speedupFee > 0
        ) {
            stage.speedupFeeToken.safeTransferFrom(
                sender,
                treasuryWallet,
                stage.speedupFee
            );
        }

        if (cloneInfo.timeFinishStage - stage.timeToBuild < block.timestamp) {
            cloneInfo.timeFinishStage = block.timestamp;
        } else {
            cloneInfo.timeFinishStage -= stage.timeToBuild;
        }

        emit SpeedUpCloneTank(
            _tankId,
            cloneInfo.currentStage,
            cloneInfo.timeFinishStage
        );
    }

    function morphToNextStage(uint256 _tankId)
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
        require(cloneInfo.timeFinishStage > 0, "TankBiz: Tank is not exists");
        require(!cloneInfo.claimed, "TankBiz: Tank claimed already");

        require(
            cloneInfo.timeFinishStage <= block.timestamp,
            "TankBiz: build not finish"
        );

        uint256 nextStageId = cloneInfo.currentStage + 1;
        CloneTankStage memory stage = cloneTankStages[nextStageId];
        if (address(stage.feeToken) != address(0) && stage.fee > 0) {
            stage.feeToken.safeTransferFrom(sender, treasuryWallet, stage.fee);
        }

        cloneInfo.currentStage = nextStageId;
        cloneInfo.timeBeginStage = block.timestamp;
        if (nextStageId == numberCloneTankStage) {
            cloneInfo.claimed = true;
            cloneInfo.timeFinishStage = block.timestamp;
            emit MorphToNextStage(
                _tankId,
                cloneInfo.currentStage,
                cloneInfo.timeFinishStage
            );

            emit ClaimTank(
                sender,
                cloneInfo.parentTankId1,
                cloneInfo.parentTankId2,
                _tankId
            );
        } else {
            CloneTankStage memory stageNext = cloneTankStages[nextStageId + 1];
            cloneInfo.timeFinishStage = block.timestamp + stageNext.timeToBuild;
            emit MorphToNextStage(
                _tankId,
                cloneInfo.currentStage,
                cloneInfo.timeFinishStage
            );
        }
    }

    function cloneTankPriceNumber(uint256 _cloneId)
        external
        view
        returns (uint256)
    {
        return cloneTankPrices[_cloneId].length;
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
            require(
                sender == info.owner || sender == info.renter,
                "TankBiz: Caller invalid"
            );
        } else {
            require(sender == tokenOwner, "TankBiz: Must be token owner");
        }

        IERC20(_erc20).safeTransferFrom(
            sender,
            treasuryWallet,
            priceFixTank[_erc20]
        );

        emit FixTank(sender, _tankId, _erc20, priceFixTank[_erc20], _fixId);

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

    function _checkSignature(bytes32 _hashMessage, bytes memory _signature)
        internal
        view
    {
        bytes32 prefixed = _hashMessage.prefixed();
        address singer = prefixed.recoverSigner(_signature);
        require(hasRole(SIGNER_ROLE, singer), "TankBiz: Signature Invalid");
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
