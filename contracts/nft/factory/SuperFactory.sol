// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../libs/Signature.sol";

interface ITankBox is IERC721 {
    function burn(uint256 tokenId) external;

    function mint(address account) external;

    function currentId() external returns (uint256);
}

interface ITank is IERC721 {
    function mint(address account) external;

    function currentId() external returns (uint256);
}

contract SuperFactory is
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Signature for bytes32;

    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public TIME_TO_BUILD_TANK;

    event SetPrice(uint8 cloneId, address[] erc20s, uint256[] prices);

    event CloneTank(
        address user,
        uint8 cloneId,
        uint256 tankId,
        uint256 boxId,
        uint256 timeToBuild
    );

    event SetSpeedUpFee(
        address speedupToken,
        uint256 speedupFee,
        uint256 speedupTime
    );

    event SpeedUp(uint256 boxId, uint256 timeToBuild);

    event ClaimTank(
        address user,
        uint8 cloneId,
        uint256 parentTankId,
        uint256 tankId,
        uint256 boxId
    );

    struct ClonePrice {
        address token;
        uint256 price;
    }

    struct BoxTankInfo {
        uint256 tankId;
        uint8 cloneId;
        uint256 timeBuildFinish;
        uint8 speedUpNumber;
    }

    ITank tank;

    ITankBox tankBox;

    uint8 maximunClone;

    mapping(uint256 => uint8) numberCloned;

    // cloneId ==> price
    mapping(uint8 => ClonePrice[]) clonePrices;

    // boxId ==> time to build
    mapping(uint256 => BoxTankInfo) boxTankInfo;

    address treasuryWallet;

    IERC20 speedupToken;

    uint256 speedupFee;

    uint256 speedupTime;

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Superfactory: must be admin role"
        );
        _;
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "Superfactory: must be operator role"
        );
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0), "Superfactory: Address invalid");
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
    }

    function setTreasuryWallet(address _address) external onlyAdmin {
        treasuryWallet = _address;
    }

    function setTank(ITank _address) external onlyOperator {
        tank = _address;
    }

    function setTankBox(ITankBox _address) external onlyOperator {
        tankBox = _address;
    }

    function setMaximunClone(uint8 _maximunClone) external onlyOperator {
        maximunClone = _maximunClone;
    }

    function setTimeToBuildTank(uint256 _timeToBuild) external onlyOperator {
        TIME_TO_BUILD_TANK = _timeToBuild;
    }

    function setSpeedUpFee(
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

        emit SetSpeedUpFee(address(speedupToken), speedupFee, speedupTime);
    }

    function setClonePrice(
        uint8 _cloneId,
        address[] calldata _erc20s,
        uint256[] calldata _prices
    ) external onlyOperator {
        delete clonePrices[_cloneId];
        uint256 length = _erc20s.length;
        require(
            length > 0 && length == _prices.length,
            "Superfactory: array length is invalid"
        );

        ClonePrice[] storage prices = clonePrices[_cloneId];
        for (uint256 i = 0; i < length; i++) {
            require(
                _prices[i] > 0,
                "Superfactory: Price must be greater than 0"
            );
            prices.push(ClonePrice(_erc20s[i], _prices[i]));
        }

        emit SetPrice(_cloneId, _erc20s, _prices);
    }

    function clone(uint256 _tankId, bytes calldata _signature)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        address sender = _msgSender();
        uint8 cloneId = numberCloned[_tankId] + 1;
        uint256 timeToBuild = _getTimeToBuild();
        require(
            tank.ownerOf(_tankId) == sender,
            "Superfactory: must be owner of token"
        );

        require(
            cloneId <= maximunClone,
            "Superfactory: the number of clone is exceed"
        );

        bytes32 hashMessage = keccak256(abi.encodePacked(sender, _tankId));
        bytes32 prefixed = hashMessage.prefixed();
        address singer = prefixed.recoverSigner(_signature);
        require(
            hasRole(SIGNER_ROLE, singer),
            "Superfactory: Signature Invalid"
        );

        ClonePrice[] memory prices = clonePrices[cloneId];
        uint256 priceLength = prices.length;
        require(
            priceLength > 0,
            "Superfactory: must be set price to clone tank"
        );

        for (uint256 i = 0; i < priceLength; i++) {
            ClonePrice memory price = prices[i];
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

        tankBox.mint(sender);
        numberCloned[_tankId]++;

        uint256 boxId = tankBox.currentId();
        BoxTankInfo storage boxInfo = boxTankInfo[boxId];
        boxInfo.cloneId = cloneId;
        boxInfo.tankId = _tankId;
        boxInfo.timeBuildFinish = timeToBuild;

        emit CloneTank(sender, cloneId, _tankId, boxId, timeToBuild);
    }

    function speedUp(uint256 _boxId) external whenNotPaused nonReentrant {
        address sender = _msgSender();
        require(
            tankBox.ownerOf(_boxId) == sender,
            "Superfactory: must be owner of box"
        );

        BoxTankInfo storage boxInfo = boxTankInfo[_boxId];
        require(boxInfo.tankId > 0, "Superfactory: Box is not exists");
        require(
            boxInfo.timeBuildFinish < block.timestamp,
            "Superfactory: Box finished build"
        );

        speedupToken.safeTransferFrom(sender, treasuryWallet, speedupFee);
        boxInfo.timeBuildFinish += speedupTime;
        boxInfo.speedUpNumber += 1;

        emit SpeedUp(_boxId, boxInfo.timeBuildFinish);
    }

    function onERC721Received(
        address,
        address _user,
        uint256 _boxId,
        bytes calldata
    ) public nonReentrant returns (bytes4) {
        address sender = _msgSender();

        require(
            address(tankBox) == sender,
            "Superfactory: caller is not tank box contract"
        );

        BoxTankInfo memory boxInfo = boxTankInfo[_boxId];
        require(boxInfo.tankId > 0, "Superfactory: Box is not exists");
        require(
            boxInfo.timeBuildFinish >= block.timestamp,
            "Superfactory: Cannot claim tank"
        );

        tankBox.burn(_boxId);
        tank.mint(_user);

        emit ClaimTank(
            _user,
            boxInfo.cloneId,
            boxInfo.tankId,
            tank.currentId(),
            _boxId
        );

        delete boxTankInfo[_boxId];
        return this.onERC721Received.selector;
    }

    function _getTimeToBuild() internal view returns (uint256) {
        return block.timestamp + TIME_TO_BUILD_TANK;
    }
}
