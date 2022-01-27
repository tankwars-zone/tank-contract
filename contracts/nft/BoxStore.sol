// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

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
    event BoxOpened(address user, uint256 boxId, uint256 tankId);

    IMysterBox public boxContract;

    ITank public tankContract;

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

    // round id => round information
    mapping(uint256 => Round) public rounds;

    // round id => user address => number of boxes that user bought
    mapping(uint256 => mapping(address => uint256)) public numBoxesBought;

    mapping(address => bool) public isInWhitelist;

    uint256 public openBoxAt;

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
        address wallet
    ) {
        boxContract = box;
        tankContract = tank;
        adminWallet = wallet;

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

    function buyBoxInPrivateSale(uint256 roundId, uint256 quantity)
        public
        payable
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

        _buyBox(roundId, quantity, msg.value);
    }

    function buyBoxInPublicSale(uint256 roundId, uint256 quantity)
        public
        payable
        nonReentrant
    {
        Round memory round = rounds[roundId];

        require(
            round.startPublicSaleAt <= block.timestamp &&
                block.timestamp < round.endPublicSaleAt,
            "BoxStore: can not buy"
        );

        _buyBox(roundId, quantity, msg.value);
    }

    function _buyBox(
        uint256 roundId,
        uint256 quantity,
        uint256 deposit
    ) internal {
        require(quantity > 0, "BoxStore: quantity is invalid");

        Round storage round = rounds[roundId];

        require(round.boxPrice > 0, "BoxStore: round id does not exist");

        require(
            deposit == quantity * round.boxPrice,
            "BoxStore: deposit amount is invalid"
        );

        require(
            round.totalBoxesSold + quantity <= round.totalBoxes,
            "BoxStore: can not sell over limitation per round"
        );

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

        emit BoxOpened(user, boxId, tankContract.currentId());

        return this.onERC721Received.selector;
    }
}
