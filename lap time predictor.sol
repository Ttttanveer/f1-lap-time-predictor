// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title F1 Lap Time Prediction Market - Optimized
 * @dev A streamlined prediction market for Formula 1 lap times
 */
contract F1LapTimePredictionMarket is ReentrancyGuard, Ownable, Pausable {
    
    // Structs - simplified
    struct Race {
        uint256 id;
        string name;
        string circuit;
        uint256 predictionDeadline;
        uint256 raceTime;
        uint256 fastestLap;
        string fastestDriver;
        bool finalized;
        uint256 totalStaked;
        uint256 totalPredictions;
    }
    
    struct Prediction {
        address user;
        string driver;
        uint256 lapTime;
        uint256 stake;
        bool claimed;
        uint256 accuracy;
        bool driverCorrect;
    }
    
    struct UserStats {
        uint256 totalPredictions;
        uint256 totalWinnings;
        uint256 correctPredictions;
    }
    
    // Constants
    uint256 public constant MIN_STAKE = 0.01 ether;
    uint256 public constant MAX_STAKE = 5 ether;
    uint256 public constant ACCURACY_THRESHOLD = 2000; // 2 seconds
    uint256 public constant PLATFORM_FEE = 200; // 2%
    
    // State variables
    uint256 public nextRaceId = 1;
    mapping(uint256 => Race) public races;
    mapping(uint256 => Prediction[]) public predictions;
    mapping(address => UserStats) public userStats;
    mapping(uint256 => mapping(address => bool)) public hasPredicted;
    mapping(string => bool) public validDrivers;
    
    string[] public driverList;
    
    // Events
    event RaceCreated(uint256 indexed raceId, string name);
    event PredictionMade(uint256 indexed raceId, address indexed user, string driver, uint256 lapTime);
    event RaceFinalized(uint256 indexed raceId, uint256 fastestLap, string driver);
    event RewardClaimed(uint256 indexed raceId, address indexed user, uint256 amount);
    
    constructor(address initialOwner) Ownable(initialOwner) {
        _setupDrivers();
        _createRaces();
    }
    
    function _setupDrivers() private {
        string[20] memory drivers = [
            "Max Verstappen", "Sergio Perez",
            "Lewis Hamilton", "George Russell", 
            "Charles Leclerc", "Carlos Sainz",
            "Lando Norris", "Oscar Piastri",
            "Fernando Alonso", "Lance Stroll",
            "Pierre Gasly", "Esteban Ocon",
            "Alexander Albon", "Logan Sargeant",
            "Valtteri Bottas", "Zhou Guanyu",
            "Kevin Magnussen", "Nico Hulkenberg",
            "Yuki Tsunoda", "Daniel Ricciardo"
        ];
        
        for (uint256 i = 0; i < 20; i++) {
            validDrivers[drivers[i]] = true;
            driverList.push(drivers[i]);
        }
    }
    
    function _createRaces() private {
        // Hungarian GP
        races[1] = Race({
            id: 1,
            name: "Hungarian Grand Prix",
            circuit: "Hungaroring",
            predictionDeadline: 1722672000,
            raceTime: 1722693600,
            fastestLap: 0,
            fastestDriver: "",
            finalized: false,
            totalStaked: 0,
            totalPredictions: 0
        });
        
        // Dutch GP
        races[2] = Race({
            id: 2,
            name: "Dutch Grand Prix", 
            circuit: "Circuit Zandvoort",
            predictionDeadline: 1725105600,
            raceTime: 1725127200,
            fastestLap: 0,
            fastestDriver: "",
            finalized: false,
            totalStaked: 0,
            totalPredictions: 0
        });
        
        // Italian GP
        races[3] = Race({
            id: 3,
            name: "Italian Grand Prix",
            circuit: "Autodromo Nazionale Monza", 
            predictionDeadline: 1725710400,
            raceTime: 1725732000,
            fastestLap: 0,
            fastestDriver: "",
            finalized: false,
            totalStaked: 0,
            totalPredictions: 0
        });
        
        nextRaceId = 4;
    }
    
    function createRace(
        string memory _name,
        string memory _circuit,
        uint256 _deadline,
        uint256 _raceTime
    ) external onlyOwner {
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_raceTime > _deadline, "Invalid race time");
        
        races[nextRaceId] = Race({
            id: nextRaceId,
            name: _name,
            circuit: _circuit,
            predictionDeadline: _deadline,
            raceTime: _raceTime,
            fastestLap: 0,
            fastestDriver: "",
            finalized: false,
            totalStaked: 0,
            totalPredictions: 0
        });
        
        emit RaceCreated(nextRaceId, _name);
        nextRaceId++;
    }
    
    function makePrediction(
        uint256 _raceId,
        string memory _driver,
        uint256 _lapTime
    ) external payable nonReentrant whenNotPaused {
        Race storage race = races[_raceId];
        require(race.id != 0, "Race not found");
        require(!race.finalized, "Race finalized");
        require(block.timestamp < race.predictionDeadline, "Deadline passed");
        require(!hasPredicted[_raceId][msg.sender], "Already predicted");
        require(validDrivers[_driver], "Invalid driver");
        require(msg.value >= MIN_STAKE && msg.value <= MAX_STAKE, "Invalid stake");
        require(_lapTime > 65000 && _lapTime < 95000, "Invalid lap time");
        
        predictions[_raceId].push(Prediction({
            user: msg.sender,
            driver: _driver,
            lapTime: _lapTime,
            stake: msg.value,
            claimed: false,
            accuracy: 0,
            driverCorrect: false
        }));
        
        race.totalStaked += msg.value;
        race.totalPredictions++;
        hasPredicted[_raceId][msg.sender] = true;
        userStats[msg.sender].totalPredictions++;
        
        emit PredictionMade(_raceId, msg.sender, _driver, _lapTime);
    }
    
    function finalizeRace(
        uint256 _raceId,
        uint256 _fastestLap,
        string memory _driver
    ) external onlyOwner {
        Race storage race = races[_raceId];
        require(race.id != 0, "Race not found");
        require(!race.finalized, "Already finalized");
        require(validDrivers[_driver], "Invalid driver");
        require(_fastestLap > 65000 && _fastestLap < 95000, "Invalid lap time");
        
        race.fastestLap = _fastestLap;
        race.fastestDriver = _driver;
        race.finalized = true;
        
        _calculateAccuracies(_raceId, _fastestLap, _driver);
        
        emit RaceFinalized(_raceId, _fastestLap, _driver);
    }
    
    function _calculateAccuracies(uint256 _raceId, uint256 _actualTime, string memory _actualDriver) private {
        Prediction[] storage preds = predictions[_raceId];
        
        for (uint256 i = 0; i < preds.length; i++) {
            if (preds[i].lapTime >= _actualTime) {
                preds[i].accuracy = preds[i].lapTime - _actualTime;
            } else {
                preds[i].accuracy = _actualTime - preds[i].lapTime;
            }
            
            preds[i].driverCorrect = keccak256(bytes(preds[i].driver)) == keccak256(bytes(_actualDriver));
        }
    }
    
    function claimReward(uint256 _raceId) external nonReentrant {
        Race storage race = races[_raceId];
        require(race.finalized, "Race not finalized");
        
        Prediction[] storage preds = predictions[_raceId];
        uint256 userIndex = type(uint256).max;
        
        for (uint256 i = 0; i < preds.length; i++) {
            if (preds[i].user == msg.sender) {
                userIndex = i;
                break;
            }
        }
        
        require(userIndex != type(uint256).max, "No prediction found");
        require(!preds[userIndex].claimed, "Already claimed");
        require(preds[userIndex].accuracy <= ACCURACY_THRESHOLD, "Not accurate enough");
        
        preds[userIndex].claimed = true;
        
        uint256 reward = _calculateReward(_raceId, userIndex);
        
        if (reward > 0) {
            userStats[msg.sender].totalWinnings += reward;
            userStats[msg.sender].correctPredictions++;
            payable(msg.sender).transfer(reward);
            emit RewardClaimed(_raceId, msg.sender, reward);
        }
    }
    
    function _calculateReward(uint256 _raceId, uint256 _predIndex) private view returns (uint256) {
        Race storage race = races[_raceId];
        Prediction[] storage preds = predictions[_raceId];
        
        uint256 winnerCount = 0;
        for (uint256 i = 0; i < preds.length; i++) {
            if (preds[i].accuracy <= ACCURACY_THRESHOLD) {
                winnerCount++;
            }
        }
        
        if (winnerCount == 0) return 0;
        
        uint256 platformFee = (race.totalStaked * PLATFORM_FEE) / 10000;
        uint256 rewardPool = race.totalStaked - platformFee;
        uint256 baseReward = rewardPool / winnerCount;
        
        // Bonus for driver prediction
        if (preds[_predIndex].driverCorrect) {
            baseReward += baseReward / 5; // 20% bonus
        }
        
        return baseReward;
    }
    
    function getRace(uint256 _raceId) external view returns (Race memory) {
        return races[_raceId];
    }
    
    function getRacePredictions(uint256 _raceId) external view returns (Prediction[] memory) {
        return predictions[_raceId];
    }
    
    function getUserStats(address _user) external view returns (UserStats memory) {
        return userStats[_user];
    }
    
    function getDrivers() external view returns (string[] memory) {
        return driverList;
    }
    
    function getUpcomingRaces() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i < nextRaceId; i++) {
            if (!races[i].finalized && block.timestamp < races[i].predictionDeadline) {
                count++;
            }
        }
        
        uint256[] memory upcoming = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i < nextRaceId; i++) {
            if (!races[i].finalized && block.timestamp < races[i].predictionDeadline) {
                upcoming[index] = i;
                index++;
            }
        }
        
        return upcoming;
    }
    
    function addDriver(string memory _driver) external onlyOwner {
        require(!validDrivers[_driver], "Driver exists");
        validDrivers[_driver] = true;
        driverList.push(_driver);
    }
    
    function withdrawFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}
