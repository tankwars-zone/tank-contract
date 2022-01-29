// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IMysterBox {
    function burn(uint256 tokenId) external;

    function mintBatch(address[] memory accounts) external;

    function currentId() external view returns (uint256);
}

interface ITank {
    function mint(address account) external;

    function currentId() external view returns (uint256);
}

contract BoxStore is AccessControlEnumerable, ReentrancyGuard {
    using SafeMath for uint256;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant ONE_HUNDRED_PERCENT = 10000;

    event AdminWalletUpdated(address wallet);
    event RoundUpdated(
        uint256 roundId,
        uint256 boxPrice,
        uint256 totalBoxes,
        uint256 startPrivateSaleAt,
        uint256 endPrivateSaleAt,
        uint256 startPublicSaleAt,
        uint256 endPublicSaleAt,
        uint256 numBoxesPerAccount
    );
    event OpenBoxTimeUpdated(uint256 time);
    event WhitelistUpdated(address[] users, bool status);
    event BoxBought(
        address user,
        uint256 boxPrice,
        uint256 boxIdFrom,
        uint256 boxIdTo
    );
    event BoxOpened(
        address user,
        uint256 boxId,
        uint256 tankId,
        uint256 rarity
    );

    IMysterBox public boxContract;

    ITank public tankContract;

    IERC20 public wbondContract;

    address public adminWallet;

    struct Round {
        uint256 boxPrice;
        uint256 totalBoxes;
        uint256 totalBoxesSold;
        uint256 startPrivateSaleAt;
        uint256 endPrivateSaleAt;
        uint256 startPublicSaleAt;
        uint256 endPublicSaleAt;
        uint256 numBoxesPerAccount;
    }

    struct Rarity {
        uint256 totalSlot;
        uint256 startFrom;
        uint256 endAt;
        uint256 filled;
        uint256 rarityType;
    }

    // round id => round information
    mapping(uint256 => Round) public rounds;

    // round id => user address => number of boxes that user bought
    mapping(uint256 => mapping(address => uint256)) public numBoxesBought;

    mapping(address => bool) public isInWhitelist;

    uint256 public openBoxAt;

    uint256 private nonce;
    Rarity[] private rarities;
    uint256 private totalTank;

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "BoxStore: must have admin role to call"
        );
        _;
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "BoxStore: must have operator role to call"
        );
        _;
    }

    constructor(
        IMysterBox box,
        ITank tank,
        IERC20 wbond,
        address wallet
    ) {
        boxContract = box;
        tankContract = tank;
        adminWallet = wallet;
        wbondContract = wbond;
        nonce = 1;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    function setAdminWallet(address wallet) public onlyAdmin {
        require(wallet != address(0), "BoxStore: address is invalid");

        adminWallet = wallet;

        emit AdminWalletUpdated(wallet);
    }

    function setRound(
        uint256 roundId,
        uint256 boxPrice,
        uint256 totalBoxes,
        uint256 startPrivateSaleAt,
        uint256 endPrivateSaleAt,
        uint256 startPublicSaleAt,
        uint256 endPublicSaleAt,
        uint256 numBoxesPerAccount
    ) public onlyOperator {
        Round storage round = rounds[roundId];

        if (round.boxPrice != boxPrice) {
            round.boxPrice = boxPrice;
        }

        if (round.totalBoxes != totalBoxes) {
            round.totalBoxes = totalBoxes;
        }

        if (round.startPrivateSaleAt != startPrivateSaleAt) {
            round.startPrivateSaleAt = startPrivateSaleAt;
        }

        if (round.endPrivateSaleAt != endPrivateSaleAt) {
            round.endPrivateSaleAt = endPrivateSaleAt;
        }

        if (round.startPublicSaleAt != startPublicSaleAt) {
            round.startPublicSaleAt = startPublicSaleAt;
        }

        if (round.endPublicSaleAt != endPublicSaleAt) {
            round.endPublicSaleAt = endPublicSaleAt;
        }

        if (round.numBoxesPerAccount != numBoxesPerAccount) {
            round.numBoxesPerAccount = numBoxesPerAccount;
        }

        require(
            round.totalBoxes >= round.totalBoxesSold,
            "BoxStore: total supply must be greater or equal than total sold"
        );

        require(
            round.startPrivateSaleAt < round.endPrivateSaleAt &&
                round.startPublicSaleAt < round.endPublicSaleAt,
            "BoxStore: time is invalid"
        );

        emit RoundUpdated(
            roundId,
            boxPrice,
            totalBoxes,
            startPrivateSaleAt,
            endPrivateSaleAt,
            startPublicSaleAt,
            endPublicSaleAt,
            numBoxesPerAccount
        );
    }

    function setOpenBoxTime(uint256 time) public onlyOperator {
        openBoxAt = time;

        emit OpenBoxTimeUpdated(time);
    }

    function setWhitelist(address[] memory accounts, bool status)
        external
        onlyOperator
    {
        uint256 length = accounts.length;

        require(length > 0, "BoxStore: array length is invalid");

        for (uint256 i = 0; i < length; i++) {
            address account = accounts[i];

            isInWhitelist[account] = status;
        }

        emit WhitelistUpdated(accounts, status);
    }

    function setRarity(
        uint256 total,
        uint256[] calldata rarityType,
        uint256[] calldata percentage
    ) external onlyOperator {
        require(
            percentage.length == rarityType.length,
            "BoxStore: array invalid"
        );

        delete rarities;
        totalTank = total;

        uint256 totalPercent = 0;
        uint256 totalSlot = 0;
        uint256 index = 1;
        for (uint256 i = 0; i < percentage.length; i++) {
            uint256 slot = total.mul(percentage[i]).div(ONE_HUNDRED_PERCENT);
            totalSlot += slot;
            rarities.push(
                Rarity({
                    totalSlot: slot,
                    startFrom: index,
                    endAt: slot.add(index).sub(1),
                    filled: 0,
                    rarityType: rarityType[i]
                })
            );
            index += slot;
            totalPercent += percentage[i];
        }

        require(
            totalSlot == totalTank && totalPercent == ONE_HUNDRED_PERCENT,
            "BoxStore: parameter invalid"
        );
    }

    function getRatiry(uint256 id) external view returns (Rarity memory) {
        return rarities[id];
    }

    function buyBoxInPrivateSale(uint256 roundId, uint256 quantity)
        public
        nonReentrant
    {
        Round memory round = rounds[roundId];

        require(
            round.startPrivateSaleAt <= block.timestamp &&
                block.timestamp < round.endPrivateSaleAt,
            "BoxStore: can not buy"
        );

        require(
            isInWhitelist[_msgSender()],
            "BoxStore: caller is not in whitelist"
        );

        _buyBox(roundId, quantity);
    }

    function buyBoxInPublicSale(uint256 roundId, uint256 quantity)
        public
        nonReentrant
    {
        Round memory round = rounds[roundId];

        require(
            round.startPublicSaleAt <= block.timestamp &&
                block.timestamp < round.endPublicSaleAt,
            "BoxStore: can not buy"
        );

        _buyBox(roundId, quantity);
    }

    function _buyBox(uint256 roundId, uint256 quantity) internal {
        require(quantity > 0, "BoxStore: quantity is invalid");

        Round storage round = rounds[roundId];

        require(round.boxPrice > 0, "BoxStore: round id does not exist");

        require(
            round.totalBoxesSold + quantity <= round.totalBoxes,
            "BoxStore: can not sell over limitation per round"
        );

        uint256 amount = quantity * round.boxPrice;

        address msgSender = _msgSender();

        require(
            numBoxesBought[roundId][msgSender] + quantity <=
                round.numBoxesPerAccount,
            "BoxStore: can not sell over limitation per account"
        );

        address[] memory accounts = new address[](quantity);

        for (uint256 i = 0; i < quantity; i++) {
            accounts[i] = msgSender;
        }

        boxContract.mintBatch(accounts);

        round.totalBoxesSold += quantity;

        numBoxesBought[roundId][msgSender] += quantity;

        wbondContract.transferFrom(msg.sender, adminWallet, amount);

        uint256 currentId = boxContract.currentId();

        emit BoxBought(
            msgSender,
            round.boxPrice,
            currentId - quantity + 1,
            currentId
        );
    }

    function onERC721Received(
        address,
        address user,
        uint256 boxId,
        bytes calldata
    ) public nonReentrant returns (bytes4) {
        require(
            address(boxContract) == _msgSender(),
            "BoxStore: caller is not box contract"
        );

        require(openBoxAt <= block.timestamp, "BoxStore: can not open");

        boxContract.burn(boxId);

        tankContract.mint(user);

        uint256 rarityType = _getRatiryType();

        require(rarityType > 0, "BoxStore: Tank is exceed");

        emit BoxOpened(user, boxId, tankContract.currentId(), rarityType);

        return this.onERC721Received.selector;
    }

    function _getRatiryType() internal returns (uint256) {
        bool usingNext = false;
        uint256 rarityType = 0;
        uint8 find = 0;
        uint256 index = 0;
        while (rarityType == 0 && find < 2) {
            if (!usingNext) {
                index = _random();
            }
            for (uint256 i = 0; i < rarities.length; i++) {
                Rarity storage rarity = rarities[i];
                if (rarity.startFrom <= index && rarity.endAt >= index) {
                    if (rarity.totalSlot == rarity.filled) {
                        usingNext = true;
                        continue;
                    } else {
                        rarity.filled++;
                        rarityType = rarity.rarityType;
                        break;
                    }
                }
                if (usingNext && rarity.totalSlot > rarity.filled) {
                    rarity.filled++;
                    rarityType = rarity.rarityType;
                    break;
                }
            }
            find++;
        }
        return rarityType;
    }

    function _random() internal returns (uint256) {
        uint256 randomnumber = uint256(
            keccak256(
                abi.encodePacked(block.difficulty, block.timestamp, nonce)
            )
        ) % totalTank;
        randomnumber = randomnumber + 1;
        nonce++;
        return randomnumber;
    }
}
