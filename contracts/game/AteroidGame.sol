// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AteroidGame is AccessControlEnumerableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant HUNDRED_PERCENT = 10000;

    uint256 public constant ASTEROID_MOVING = 1;
    uint256 public constant ASTEROID_COLLIDED = 2;
    uint256 public constant ASTEROID_EXPLODED = 3;

    event TreasuryUpdated(address treasury);

    event RoomCreated(uint256 roomId, address token, uint256 searchFee, uint256 numWinners, uint256 winnerRewardPercent, uint256 finderRewardPercent);
    event RoomUpdated(uint256 roomId, address token, uint256 searchFee, uint256 numWinners, uint256 winnerRewardPercent, uint256 finderRewardPercent);
    event RoomStatusUpdated(uint256 roomId, bool status);

    event RocketUpdated(uint256 roomId, uint256 rocketId, uint256 delayTime, uint256 price);

    event AsteroidNotFound(uint256 roomId, uint256 asteroidId, address user, uint256 searchFee);
    event AsteroidFound(uint256 roomId, uint256 asteroidId, address user, uint256 searchFee);
    event AsteroidExploded(uint256 roomId, uint256 asteroidId);

    event Shoot(uint256 roomId, uint256 asteroidId, uint256 rocketId, address user, uint256 rocketPrice, uint256 delayTime);

    struct Room {
        IERC20 token;
        uint256 currentAsteroid;
        uint256 searchFee;
        bool status;
        uint256 numWinners;
        uint256 winnerRewardPercent;
        uint256 finderRewardPercent;
    }

    struct Asteroid {
        address owner;
        uint256 reward;         // wei
        uint256 collisionAt;    // second
        uint256 status;
        uint256 numWinners;
        uint256 winnerRewardPercent;
        uint256 finderRewardPercent;
    }

    struct Rocket {
        uint256 delayTime;      // second
        uint256 price;          // wei
    }

    struct Shooting {
        address account;
        uint256 rocketId;
        uint256 delayTime;
        uint256 rocketPrice;
    }

    // room id => room information
    mapping(uint256 => Room) public rooms;

    // room id => asteroid id => asteroid information
    mapping(uint256 => mapping(uint256 => Asteroid)) public asteroids;

    // room id => rocket id => rocket information
    mapping(uint256 => mapping(uint256 => Rocket)) public  rockets;

    // room id => asteroid id => user address => status true|false
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public isPlayer;

    // room id => asteroid id => array of shooting information
    mapping(uint256 => mapping(uint256 => Shooting[])) public shootings;

    // room id => asteroid id => array of user address
    mapping(uint256 => mapping(uint256 => address[])) public players;

    uint256 public totalRooms;

    address public treasury;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "AteroidGame: caller is not admin");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "AteroidGame: caller is not operator");
        _;
    }

    modifier roomExists(uint256 roomId) {
        require(address(rooms[roomId].token) != address(0), "AteroidGame: room does not exist");
        _;
    }

    modifier roomActive(uint256 roomId) {
        require(rooms[roomId].status, "AteroidGame: room was disabled");
        _;
    }

    function initialize()
        external
        initializer
    {
        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        address msgSender = _msgSender();

        _setupRole(DEFAULT_ADMIN_ROLE, msgSender);
        _setupRole(OPERATOR_ROLE, msgSender);

        treasury = msgSender;
    }

    function setTreasury(address _addr)
        external
        onlyAdmin
    {
        require(_addr != address(0), "AteroidGame: address is invalid");

        treasury = _addr;

        emit TreasuryUpdated(_addr);
    }

    function pause()
        external
        onlyOperator
    {
        _pause();
    }

    function unpause()
        external
        onlyOperator
    {
        _unpause();
    }

    function createRoom(address _token, uint256 _searchFee, uint256 _numWinners, uint256 _winnerRewardPercent, uint256 _finderRewardPercent)
        external
        onlyOperator
    {
        require(_token != address(0), "AteroidGame: address is invalid");

        require(_searchFee > 0, "AteroidGame: search fee is invalid");

        require(_numWinners > 0, "AteroidGame: number of winners is invalid");

        require(_winnerRewardPercent + _finderRewardPercent <= HUNDRED_PERCENT, "AteroidGame: percent is invalid");

        uint256 roomId = ++totalRooms;

        rooms[roomId] = Room(IERC20(_token), 1, _searchFee, true, _numWinners, _winnerRewardPercent, _finderRewardPercent);

        emit RoomCreated(roomId, _token, _searchFee, _numWinners, _winnerRewardPercent, _finderRewardPercent);
    }

    function updateRoom(uint256 _roomId, address _token, uint256 _searchFee, uint256 _numWinners, uint256 _winnerRewardPercent, uint256 _finderRewardPercent)
        external
        onlyOperator
        roomExists(_roomId)
    {
        require(_token != address(0), "AteroidGame: address is invalid");

        require(_searchFee > 0, "AteroidGame: search fee is invalid");

        require(_numWinners > 0, "AteroidGame: number of winners is invalid");

        require(_winnerRewardPercent + _finderRewardPercent <= HUNDRED_PERCENT, "AteroidGame: percent is invalid");

        Room storage room = rooms[_roomId];

        if (address(room.token) != _token) {
            uint256 asteroidId = room.currentAsteroid;

            require(asteroidId == 1 && asteroids[_roomId][asteroidId].reward == 0, "AteroidGame: can not update");

            room.token = IERC20(_token);
        }

        if (room.searchFee != _searchFee) {
            room.searchFee = _searchFee;
        }

        if (room.numWinners != _numWinners) {
            room.numWinners = _numWinners;
        }

        if (room.winnerRewardPercent != _winnerRewardPercent) {
            room.winnerRewardPercent = _winnerRewardPercent;
        }

        if (room.finderRewardPercent != _finderRewardPercent) {
            room.finderRewardPercent = _finderRewardPercent;
        }

        emit RoomUpdated(_roomId, _token, _searchFee, _numWinners, _winnerRewardPercent, _finderRewardPercent);
    }

    function updateRoomStatus(uint256 _roomId, bool _status)
        external
        onlyOperator
        roomExists(_roomId)
    {
        rooms[_roomId].status = _status;

        emit RoomStatusUpdated(_roomId, _status);
    }

    function getRooms(uint256 _offset, uint256 _limit)
        external
        view
        returns(Room[] memory data)
    {
        uint256 max = totalRooms;

        if (_offset >= max) {
            return data;
        }

        if (_offset + _limit < max) {
            max = _offset + _limit;
        }

        data = new Room[](max - _offset);

        uint256 cnt = 0;

        for (uint256 i = _offset; i < max; i++) {
            data[cnt++] = rooms[i];
        }

        return data;
    }

    function setRocket(uint256 _roomId, uint256 _rocketId, uint256 _delayTime, uint256 _price)
        external
        onlyOperator
        roomExists(_roomId)
    {
        require(_delayTime > 0, "AteroidGame: delay time is invalid");

        require(_price > 0, "AteroidGame: price is invalid");

        Rocket storage rocket = rockets[_roomId][_rocketId];

        if (rocket.delayTime != _delayTime) {
            rocket.delayTime = _delayTime;
        }

        if (rocket.price != _price) {
            rocket.price = _price;
        }

        emit RocketUpdated(_roomId, _rocketId, _delayTime, _price);
    }

    function _random()
        internal
        view
        returns(uint256)
    {
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, block.gaslimit)));
    }

    function search(uint256 _roomId)
        external
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        Room memory room = rooms[_roomId];

        uint256 asteroidId = room.currentAsteroid;

        Asteroid storage asteroid = asteroids[_roomId][asteroidId];

        if (asteroid.status == ASTEROID_MOVING && asteroid.collisionAt <= block.timestamp) {
            asteroid.status = ASTEROID_COLLIDED;
        }

        if (asteroid.status == ASTEROID_COLLIDED || asteroid.status == ASTEROID_EXPLODED) {
            asteroidId = ++room.currentAsteroid;

            asteroid = asteroids[_roomId][asteroidId];
        }

        require(asteroid.status == 0, "AteroidGame: asteroid has found");

        address msgSender = _msgSender();

        room.token.safeTransferFrom(msgSender, address(this), room.searchFee);

        asteroid.reward += room.searchFee;

        if (_random() % 10 != 5) {
            emit AsteroidNotFound(_roomId, asteroidId, msgSender, room.searchFee);

        } else {
            asteroid.owner = msgSender;
            asteroid.numWinners = room.numWinners;
            asteroid.winnerRewardPercent = room.winnerRewardPercent;
            asteroid.finderRewardPercent = room.finderRewardPercent;
            asteroid.collisionAt = block.timestamp + 600;
            asteroid.status = ASTEROID_MOVING;

            emit AsteroidFound(_roomId, asteroidId, msgSender, room.searchFee);
        }
    }

    function getAsteroids(uint256 _roomId, uint256 _offset, uint256 _limit)
        external
        view
        returns(Asteroid[] memory data)
    {
        uint256 max = rooms[_roomId].currentAsteroid;

        if (_offset >= max) {
            return data;
        }

        if (_offset + _limit < max) {
            max = _offset + _limit;
        }

        data = new Asteroid[](max - _offset);

        uint256 cnt = 0;

        for (uint256 i = _offset; i < max; i++) {
            data[cnt++] = asteroids[_roomId][i];
        }

        return data;
    }

    function shoot(uint256 _roomId, uint256 _rocketId)
        external
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        Rocket memory rocket = rockets[_roomId][_rocketId];

        require(rocket.price > 0, "AteroidGame: rocket does not exist");

        Room memory room = rooms[_roomId];

        uint256 asteroidId = room.currentAsteroid;

        Asteroid storage asteroid = asteroids[_roomId][asteroidId];

        require(asteroid.status == ASTEROID_MOVING && asteroid.collisionAt > block.timestamp, "AteroidGame: asteroid has collided, exploded or not existed");

        asteroid.reward += rocket.price;

        address msgSender = _msgSender();

        room.token.safeTransferFrom(msgSender, address(this), rocket.price);

        shootings[_roomId][asteroidId].push(Shooting(msgSender, _rocketId, rocket.delayTime, rocket.price));

        emit Shoot(_roomId, asteroidId, _rocketId, msgSender, rocket.price, rocket.delayTime);

        if (_random() % 10 != 5) {
            asteroid.collisionAt += rocket.delayTime;

        } else {
            asteroid.status = ASTEROID_EXPLODED;

            emit AsteroidExploded(_roomId, asteroidId);
        }

        if (!isPlayer[_roomId][asteroidId][msgSender]) {
            players[_roomId][asteroidId].push(msgSender);

            isPlayer[_roomId][asteroidId][msgSender] = true;
        }
    }

    function getShootings(uint256 _roomId, uint256 _asteroidId, uint256 _offset, uint256 _limit)
        external
        view
        returns(Shooting[] memory data)
    {
        uint256 max = shootings[_roomId][_asteroidId].length;

        if (_offset >= max) {
            return data;
        }

        if (_offset + _limit < max) {
            max = _offset + _limit;
        }

        data = new Shooting[](max - _offset);

        uint256 cnt = 0;

        for (uint256 i = _offset; i < max; i++) {
            data[cnt++] = shootings[_roomId][_asteroidId][i];
        }

        return data;
    }

    function totalShootings(uint256 _roomId, uint256 _asteroidId)
        external
        view
        returns(uint256)
    {
        return shootings[_roomId][_asteroidId].length;
    }

    function totalPlayers(uint256 _roomId, uint256 _asteroidId)
        external
        view
        returns(uint256)
    {
        return players[_roomId][_asteroidId].length;
    }

    function getWinners(uint256 _roomId, uint256 _asteroidId)
        external
        view
        returns(address[] memory winners, uint256[] memory rewards)
    {
        // Asteroid memory asteroid = asteroids[_roomId][_asteroidId];
    }

}