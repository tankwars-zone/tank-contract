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
    event RoundUpdated(uint256 roundId, uint256 boxPrice, uint256 totalBoxes, uint256 startSaleAt, uint256 endSaleAt, uint256 numBoxesPerAccount);
    event OpenBoxTimeUpdated(uint256 time);
    event BoxBought(address user, uint256 boxPrice, uint256 boxIdFrom, uint256 boxIdTo);
    event BoxOpened(address user, uint256 boxId, uint256 tankId);

    IMysterBox public boxContract;

    ITank public tankContract;

    address public adminWallet;

    struct Round {
        uint256 boxPrice;
        uint256 totalBoxes;
        uint256 totalBoxesSold;
        uint256 startSaleAt;
        uint256 endSaleAt;
        uint256 numBoxesPerAccount;
    }

    // round id => round information
    mapping(uint256 => Round) public rounds;

    // round id => user address => number of boxes that user bought
    mapping(uint256 => mapping(address => uint256)) public numBoxesBought;

    uint256 public openBoxAt;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "BoxStore: must have admin role to call");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "BoxStore: must have operator role to call");
        _;
    }

    constructor(IMysterBox box, ITank tank, address wallet) {
        boxContract = box;
        tankContract = tank;
        adminWallet = wallet;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    function setAdminWallet(address wallet)
        public
        onlyAdmin
    {
        require(wallet != address(0), "BoxStore: address is invalid");

        adminWallet = wallet;

        emit AdminWalletUpdated(wallet);
    }

    function setRound(uint256 roundId, uint256 boxPrice, uint256 totalBoxes, uint256 startSaleAt, uint256 endSaleAt, uint256 numBoxesPerAccount)
        public
        onlyOperator
    {
        Round storage round = rounds[roundId];

        if (round.boxPrice != boxPrice) {
            round.boxPrice = boxPrice;
        }

        if (round.totalBoxes != totalBoxes) {
            round.totalBoxes = totalBoxes;
        }

        if (round.startSaleAt != startSaleAt) {
            round.startSaleAt = startSaleAt;
        }

        if (round.endSaleAt != endSaleAt) {
            round.endSaleAt = endSaleAt;
        }

        if (round.numBoxesPerAccount != numBoxesPerAccount) {
            round.numBoxesPerAccount = numBoxesPerAccount;
        }

        require(round.totalBoxes >= round.totalBoxesSold, "BoxStore: total supply must be greater or equal than total sold");

        emit RoundUpdated(roundId, boxPrice, totalBoxes, startSaleAt, endSaleAt, numBoxesPerAccount);
    }

    function setOpenBoxTime(uint256 time)
        public
        onlyOperator
    {
        openBoxAt = time;

        emit OpenBoxTimeUpdated(time);
    }

    function buyBox(uint256 roundId, uint256 quantity)
        public
        payable
        nonReentrant
    {
        require(quantity > 0, "BoxStore: quantity is invalid");

        Round storage round = rounds[roundId];

        require(round.boxPrice > 0, "BoxStore: round id does not exist");

        require(msg.value == quantity * round.boxPrice, "BoxStore: deposit amount is invalid");

        require(round.totalBoxesSold + quantity <= round.totalBoxes, "BoxStore: can not sell over limitation per round");

        require(round.startSaleAt <= block.timestamp && block.timestamp < round.endSaleAt, "BoxStore: can not buy");

        address msgSender = _msgSender();

        require(numBoxesBought[roundId][msgSender] + quantity <= round.numBoxesPerAccount, "BoxStore: can not sell over limitation per account");

        address[] memory accounts = new address[](quantity);

        for (uint256 i = 0; i < quantity; i++) {
            accounts[i] = msgSender;
        }

        boxContract.mintBatch(accounts);

        round.totalBoxesSold += quantity;

        numBoxesBought[roundId][msgSender] += quantity;

        uint256 currentId = boxContract.currentId();

        emit BoxBought(msgSender, round.boxPrice, currentId - quantity + 1, currentId);
    }

    function onERC721Received(address, address user, uint256 boxId, bytes calldata)
        public
        nonReentrant
        returns (bytes4)
    {
        require(address(boxContract) == _msgSender(), "BoxStore: caller is not box contract");

        require(openBoxAt <= block.timestamp, "BoxStore: can not open");

        boxContract.burn(boxId);

        tankContract.mint(user);

        emit BoxOpened(user, boxId, tankContract.currentId());

        return this.onERC721Received.selector;
    }

}