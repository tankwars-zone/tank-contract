// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AsteroidGame is AccessControlEnumerableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant HUNDRED_PERCENT = 10000; // 100%

    uint256 public constant ASTEROID_MOVING = 1;
    uint256 public constant ASTEROID_COLLIDED = 2;
    uint256 public constant ASTEROID_EXPLODED = 3;

    event TreasuryUpdated(address treasury);

    event RoomCreated(uint256 roomId, address token, uint256 searchFee, uint256 totalPrizes, uint256 winnerRewardPercent, uint256 ownerRewardPercent);
    event RoomUpdated(uint256 roomId, address token, uint256 searchFee, uint256 totalPrizes, uint256 winnerRewardPercent, uint256 ownerRewardPercent);
    event RoomStatusUpdated(uint256 roomId, bool status);

    event RocketUpdated(uint256 roomId, uint256 rocketId, uint256 delayTime, uint256 price);

    event AsteroidNotFound(uint256 roomId, uint256 asteroidId, address user, uint256 searchFee);
    event AsteroidFound(uint256 roomId, uint256 asteroidId, address user, uint256 searchFee);
    event AsteroidCreated(uint256 roomId, uint256 asteroidId, address user, uint256 reward);
    event AsteroidExploded(uint256 roomId, uint256 asteroidId);

    event Shoot(uint256 roomId, uint256 asteroidId, uint256 rocketId, address user, uint256 rocketPrice, uint256 delayTime);

    event RewardAdded(uint256 roomId, uint256 asteroidId, address user, uint256 amount);
    event RewardClaimed(uint256 roomId, uint256 asteroidId, address user, uint256 amount);

    struct Room {
        IERC20 token;
        uint256 currentAsteroid;
        uint256 searchFee;
        bool enable;
        uint256 totalPrizes;
        uint256 winnerRewardPercent;
        uint256 ownerRewardPercent;
    }

    struct Asteroid {
        address owner;
        uint256 reward;         // wei
        uint256 collisionAt;    // second
        uint256 status;
        uint256 totalPrizes;
        uint256 winnerRewardPercent;
        uint256 ownerRewardPercent;
        uint256 shootingWeight;
        uint256 searchingWeight;
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
    mapping(uint256 => mapping(uint256 => Rocket)) public rockets;

    // room id => asteroid id => user address => true value if is player
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public isPlayer;

    // room id => asteroid id => array of shooting information
    mapping(uint256 => mapping(uint256 => Shooting[])) private _shootings;

    // room id => asteroid id => array of user address
    mapping(uint256 => mapping(uint256 => address[])) private _winners;

    // room id => asteroid id => total players
    mapping(uint256 => mapping(uint256 => uint256)) public totalPlayers;

    // room id => asteroid id => user address => true value if reward was claimed
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public isClaimed;

    uint256 public totalRooms;

    address public treasury;

    uint256 public minLifeTime;
    uint256 public maxLifeTime;
    uint256 public minSearchingWeight;
    uint256 public maxSearchingWeight;
    uint256 public searchingRatio;
    uint256 public minShootingWeight;
    uint256 public maxShootingWeight;
    uint256 public shootingRatio;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "AsteroidGame: caller is not admin");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "AsteroidGame: caller is not operator");
        _;
    }

    modifier roomExists(uint256 roomId) {
        require(address(rooms[roomId].token) != address(0), "AsteroidGame: room does not exist");
        _;
    }

    modifier roomActive(uint256 roomId) {
        require(rooms[roomId].enable, "AsteroidGame: room was disabled");
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

        minLifeTime = 1800; // 30 minutes
        maxLifeTime = 3600; // 60 minutes

        minSearchingWeight = 2000;
        maxSearchingWeight = 4000;
        searchingRatio = 1;

        minShootingWeight = 2000;
        maxShootingWeight = 4000;
        shootingRatio = 1;
    }

    function setTreasury(address _addr)
        external
        onlyAdmin
    {
        require(_addr != address(0), "AsteroidGame: address is invalid");

        treasury = _addr;

        emit TreasuryUpdated(_addr);
    }

    function setConfig(
        uint256 _minLifeTime,
        uint256 _maxLifeTime,
        uint256 _minSearchingWeight,
        uint256 _maxSearchingWeight,
        uint256 _searchingRatio,
        uint256 _minShootingWeight,
        uint256 _maxShootingWeight,
        uint256 _shootingRatio
    )
        external
        onlyOperator
    {
        require(_minLifeTime > 0 && _minLifeTime < _maxLifeTime, "AsteroidGame: time is invalid");

        require(_minSearchingWeight < _maxSearchingWeight && _maxSearchingWeight <= HUNDRED_PERCENT, "AsteroidGame: searching weight is invalid");

        require(_minShootingWeight < _maxShootingWeight && _maxShootingWeight <= HUNDRED_PERCENT, "AsteroidGame: shooting weight is invalid");

        if (minLifeTime != _minLifeTime) {
            minLifeTime = _minLifeTime;
        }

        if (maxLifeTime != _maxLifeTime) {
            maxLifeTime = _maxLifeTime;
        }

        if (minSearchingWeight != _minSearchingWeight) {
            minSearchingWeight = _minSearchingWeight;
        }

        if (maxSearchingWeight != _maxSearchingWeight) {
            maxSearchingWeight = _maxSearchingWeight;
        }

        if (searchingRatio != _searchingRatio) {
            searchingRatio = _searchingRatio;
        }

        if (minShootingWeight != _minShootingWeight) {
            minShootingWeight = _minShootingWeight;
        }

        if (maxShootingWeight != _maxShootingWeight) {
            maxShootingWeight = _maxShootingWeight;
        }

        if (shootingRatio != _shootingRatio) {
            shootingRatio = _shootingRatio;
        }
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

    function createRoom(address _token, uint256 _searchFee, uint256 _totalPrizes, uint256 _winnerRewardPercent, uint256 _ownerRewardPercent)
        external
        onlyOperator
    {
        require(_token != address(0), "AsteroidGame: address is invalid");

        require(_searchFee > 0, "AsteroidGame: search fee is invalid");

        require(_totalPrizes > 0, "AsteroidGame: total prizes is invalid");

        require(_winnerRewardPercent + _ownerRewardPercent <= HUNDRED_PERCENT, "AsteroidGame: percent is invalid");

        uint256 roomId = ++totalRooms;

        rooms[roomId] = Room(IERC20(_token), 1, _searchFee, true, _totalPrizes, _winnerRewardPercent, _ownerRewardPercent);

        emit RoomCreated(roomId, _token, _searchFee, _totalPrizes, _winnerRewardPercent, _ownerRewardPercent);
    }

    function updateRoom(uint256 _roomId, address _token, uint256 _searchFee, uint256 _totalPrizes, uint256 _winnerRewardPercent, uint256 _ownerRewardPercent)
        external
        onlyOperator
        roomExists(_roomId)
    {
        require(_token != address(0), "AsteroidGame: address is invalid");

        require(_searchFee > 0, "AsteroidGame: search fee is invalid");

        require(_totalPrizes > 0, "AsteroidGame: total prizes is invalid");

        require(_winnerRewardPercent + _ownerRewardPercent <= HUNDRED_PERCENT, "AsteroidGame: percent is invalid");

        Room storage room = rooms[_roomId];

        if (address(room.token) != _token) {
            uint256 asteroidId = room.currentAsteroid;

            require(asteroidId == 1 && asteroids[_roomId][asteroidId].reward == 0, "AsteroidGame: can not update");

            room.token = IERC20(_token);
        }

        if (room.searchFee != _searchFee) {
            room.searchFee = _searchFee;
        }

        if (room.totalPrizes != _totalPrizes) {
            room.totalPrizes = _totalPrizes;
        }

        if (room.winnerRewardPercent != _winnerRewardPercent) {
            room.winnerRewardPercent = _winnerRewardPercent;
        }

        if (room.ownerRewardPercent != _ownerRewardPercent) {
            room.ownerRewardPercent = _ownerRewardPercent;
        }

        emit RoomUpdated(_roomId, _token, _searchFee, _totalPrizes, _winnerRewardPercent, _ownerRewardPercent);
    }

    function updateRoomStatus(uint256 _roomId, bool _status)
        external
        onlyOperator
        roomExists(_roomId)
    {
        rooms[_roomId].enable = _status;

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
            data[cnt++] = rooms[i + 1];
        }

        return data;
    }

    function setRocket(uint256 _roomId, uint256 _rocketId, uint256 _delayTime, uint256 _price)
        external
        onlyOperator
        roomExists(_roomId)
    {
        require(_delayTime > 0, "AsteroidGame: delay time is invalid");

        require(_price > 0, "AsteroidGame: price is invalid");

        Rocket storage rocket = rockets[_roomId][_rocketId];

        if (rocket.delayTime != _delayTime) {
            rocket.delayTime = _delayTime;
        }

        if (rocket.price != _price) {
            rocket.price = _price;
        }

        emit RocketUpdated(_roomId, _rocketId, _delayTime, _price);
    }

    function _random(uint256 _min, uint256 _max)
        internal
        view
        returns(uint256)
    {
        uint256 rnd = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, block.gaslimit)));

        return rnd % (_max - _min + 1) + _min;
    }

    function _updateAsteroidStatus(uint256 _roomId)
        internal
    {
        Room storage room = rooms[_roomId];

        Asteroid storage asteroid = asteroids[_roomId][room.currentAsteroid];

        if (asteroid.status == ASTEROID_MOVING && asteroid.collisionAt <= block.timestamp) {
            asteroid.status = ASTEROID_COLLIDED;
        }

        if (asteroid.status == ASTEROID_COLLIDED || asteroid.status == ASTEROID_EXPLODED) {
            room.currentAsteroid++;
        }
    }

    function createAsteroid(uint256 _roomId, uint256 _reward)
        external
        onlyOperator
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        require(_reward > 0, "AsteroidGame: reward is invalid");

        _updateAsteroidStatus(_roomId);

        Room memory room = rooms[_roomId];

        uint256 asteroidId = room.currentAsteroid;

        Asteroid storage asteroid = asteroids[_roomId][asteroidId];

        require(asteroid.status == 0, "AsteroidGame: asteroid has found");

        address msgSender = _msgSender();

        room.token.safeTransferFrom(msgSender, address(this), _reward);

        asteroid.reward += _reward;
        asteroid.owner = msgSender;
        asteroid.totalPrizes = room.totalPrizes;
        asteroid.winnerRewardPercent = room.winnerRewardPercent;
        asteroid.ownerRewardPercent = room.ownerRewardPercent;
        asteroid.collisionAt = block.timestamp + _random(minLifeTime, maxLifeTime);
        asteroid.status = ASTEROID_MOVING;

        emit AsteroidCreated(_roomId, asteroidId, msgSender, _reward);
    }

    function searchAsteroid(uint256 _roomId)
        external
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        _updateAsteroidStatus(_roomId);

        Room memory room = rooms[_roomId];

        uint256 asteroidId = room.currentAsteroid;

        Asteroid storage asteroid = asteroids[_roomId][asteroidId];

        require(asteroid.status == 0, "AsteroidGame: asteroid has found");

        address msgSender = _msgSender();

        room.token.safeTransferFrom(msgSender, address(this), room.searchFee);

        asteroid.reward += room.searchFee;

        uint256 weight = minSearchingWeight + asteroid.searchingWeight;

        // Generates number in range 1.00 to 100.00
        if (_random(100, 10000) > weight) {
            if (weight + searchingRatio <= maxSearchingWeight) {
                asteroid.searchingWeight += searchingRatio;
            }

            emit AsteroidNotFound(_roomId, asteroidId, msgSender, room.searchFee);

        } else {
            asteroid.owner = msgSender;
            asteroid.totalPrizes = room.totalPrizes;
            asteroid.winnerRewardPercent = room.winnerRewardPercent;
            asteroid.ownerRewardPercent = room.ownerRewardPercent;
            asteroid.collisionAt = block.timestamp + _random(minLifeTime, maxLifeTime);
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
            data[cnt++] = asteroids[_roomId][i + 1];
        }

        return data;
    }

    function addReward(uint256 _roomId, uint256 _reward)
        external
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        require(_reward > 0, "AsteroidGame: reward is invalid");

        Room memory room = rooms[_roomId];

        uint256 asteroidId = room.currentAsteroid;

        Asteroid storage asteroid = asteroids[_roomId][asteroidId];

        require(asteroid.status == ASTEROID_MOVING && asteroid.collisionAt > block.timestamp, "AsteroidGame: asteroid has collided, exploded or not existed");
    
        address msgSender = _msgSender();

        room.token.safeTransferFrom(msgSender, address(this), _reward);

        asteroid.reward += _reward;

        emit RewardAdded(_roomId, asteroidId, msgSender, _reward);
    }

    function shootAsteroid(uint256 _roomId, uint256 _rocketId)
        external
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        Rocket memory rocket = rockets[_roomId][_rocketId];

        require(rocket.price > 0, "AsteroidGame: rocket does not exist");

        Room memory room = rooms[_roomId];

        uint256 asteroidId = room.currentAsteroid;

        Asteroid storage asteroid = asteroids[_roomId][asteroidId];

        require(asteroid.status == ASTEROID_MOVING && asteroid.collisionAt > block.timestamp, "AsteroidGame: asteroid has collided, exploded or not existed");

        asteroid.reward += rocket.price;

        address msgSender = _msgSender();

        room.token.safeTransferFrom(msgSender, address(this), rocket.price);

        _shootings[_roomId][asteroidId].push(Shooting(msgSender, _rocketId, rocket.delayTime, rocket.price));

        emit Shoot(_roomId, asteroidId, _rocketId, msgSender, rocket.price, rocket.delayTime);

        uint256 weight = minShootingWeight + asteroid.shootingWeight;

        // Generates number in range 1.00 to 100.00
        if (_random(100, 10000) > weight) {
            if (weight + shootingRatio <= maxShootingWeight) {
                asteroid.shootingWeight += shootingRatio;
            }

            asteroid.collisionAt += rocket.delayTime;

        } else {
            asteroid.status = ASTEROID_EXPLODED;

            emit AsteroidExploded(_roomId, asteroidId);
        }

        if (!isPlayer[_roomId][asteroidId][msgSender]) {
            totalPlayers[_roomId][asteroidId]++;

            isPlayer[_roomId][asteroidId][msgSender] = true;
        }

        _sortWinners(_roomId, asteroidId, msgSender);
    }

    // Because total prizes is small, so this function will not out of gas
    function _sortWinners(uint256 _roomId, uint256 _asteroidId, address _player)
        internal
    {
        uint256 duplicated = 0;

        address[] storage winners = _winners[_roomId][_asteroidId];

        uint256 size = winners.length;

        address[] memory players = new address[](size);

        for (uint256 i = 0; i < size; i++) {
            players[i] = winners[i];

            if (players[i] == _player) {
                duplicated = i + 1;
            }
        }

        if (duplicated == 0) {
            if (asteroids[_roomId][_asteroidId].totalPrizes == size) {
                duplicated = 1;

            } else {
                winners.push(_player);
            }
        }

        if (duplicated != 0) {
            size--;

            for (uint256 i = duplicated - 1; i < size; i++) {
                winners[i] = players[i + 1];
            }

            if (winners[size] != _player) {
                winners[size] = _player;
            }
        }
    }

    function getShootings(uint256 _roomId, uint256 _asteroidId, uint256 _offset, uint256 _limit)
        external
        view
        returns(Shooting[] memory data)
    {
        uint256 max = _shootings[_roomId][_asteroidId].length;

        if (_offset >= max) {
            return data;
        }

        if (_offset + _limit < max) {
            max = _offset + _limit;
        }

        data = new Shooting[](max - _offset);

        uint256 cnt = 0;

        for (uint256 i = _offset; i < max; i++) {
            data[cnt++] = _shootings[_roomId][_asteroidId][i];
        }

        return data;
    }

    function totalShootings(uint256 _roomId, uint256 _asteroidId)
        external
        view
        returns(uint256)
    {
        return _shootings[_roomId][_asteroidId].length;
    }

    function getWinners(uint256 _roomId, uint256 _asteroidId)
        public
        view
        returns(address[] memory winners, uint256 winnerReward, uint256 ownerReward, uint256 systemFee)
    {
        Asteroid memory asteroid = asteroids[_roomId][_asteroidId];

        if (asteroid.status == 0 || asteroid.status == ASTEROID_MOVING && asteroid.collisionAt > block.timestamp) {
            return (winners, winnerReward, ownerReward, systemFee);
        }

        winners = _winners[_roomId][_asteroidId];

        uint256 numWinners = winners.length;

        if (numWinners > 0) {
            winnerReward = asteroid.reward * asteroid.winnerRewardPercent / HUNDRED_PERCENT;
            winnerReward = winnerReward - (winnerReward * asteroid.shootingWeight / HUNDRED_PERCENT);
        }

        ownerReward = asteroid.reward * asteroid.ownerRewardPercent / HUNDRED_PERCENT;
        ownerReward = ownerReward - (ownerReward * asteroid.searchingWeight / HUNDRED_PERCENT);

        systemFee = asteroid.reward - (winnerReward + ownerReward);

        if (numWinners > 0) {
            winnerReward = winnerReward / numWinners;
        }
    }

    function getBalance(uint256 _roomId, uint256 _asteroidId, address _account)
        public
        view
        returns(uint256 reward, uint256 systemFee)
    {
        if (isClaimed[_roomId][_asteroidId][_account]) {
            return (reward, systemFee);
        }

        (address[] memory winners, uint256 winnerReward, uint256 ownerReward, uint256 fee) = getWinners(_roomId, _asteroidId);

        for (uint256 i = 0; i < winners.length; i++) {
            if (winners[i] == _account) {
                reward += winnerReward;
                break;
            }
        }

        if (asteroids[_roomId][_asteroidId].owner == _account) {
            reward += ownerReward;
        }

        systemFee = fee;
    }

    function claimReward(uint256 _roomId, uint256 _asteroidId)
        external
        nonReentrant
        whenNotPaused
        roomActive(_roomId)
    {
        address msgSender = _msgSender();

        (uint256 amount, uint256 systemFee) = getBalance(_roomId, _asteroidId, msgSender);

        require(amount > 0, "AsteroidGame: amount is invalid");

        isClaimed[_roomId][_asteroidId][msgSender] = true;

        Room memory room = rooms[_roomId];

        room.token.safeTransfer(msgSender, amount);

        if (asteroids[_roomId][_asteroidId].owner == msgSender) {
            room.token.safeTransfer(treasury, systemFee);
        }

        emit RewardClaimed(_roomId, _asteroidId, msgSender, amount);
    }

}