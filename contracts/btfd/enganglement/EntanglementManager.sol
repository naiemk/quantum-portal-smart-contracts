// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IndexerRole.sol";
import "./QpBTC.sol";
import "./ConfiscatedLiquidity.sol";


contract EntanglementManager is IndexerRole {
    struct Staker {
        uint256 stake;           // Total QpBTC staked
        uint256 capacity;        // Available capacity for managing BTC
        bytes32 entangler;       // Entanglement address identifier
        bool isActive;           // Active status
    }

    mapping(address => Staker) public stakers;
    mapping(bytes32 => address) public entanglerToStaker;
    mapping(address => bytes32) public stakerToEntangler;

    address[] public activeStakers;
    uint256 public nextStakerIndex;

    QpBTC public qpBTC;

    ConfiscatedLiquidity public confiscatedWallet;

    event StakerAdded(address indexed staker, uint256 amount);
    event StakerRemoved(address indexed staker, uint256 amount);
    event DepositAssigned(address indexed staker, bytes32 entangler, uint256 amount);
    event DepositProcessed(address indexed staker, uint256 amount, address indexed user);
    event StakerPenalized(address indexed staker, uint256 penaltyAmount);
    event FundsConfiscated(address indexed staker, uint256 amount);

    constructor(address _qpBTC, address _confiscatedWallet) {
        require(_qpBTC != address(0), "EM: QpBTC address cannot be zero");
        require(_confiscatedWallet != address(0), "EM: Confiscated wallet address cannot be zero");

        qpBTC = QpBTC(_qpBTC);
        confiscatedWallet = ConfiscatedLiquidity(_confiscatedWallet);
    }

    function stakeBtc(uint256 amount) external {
        require(amount > 0, "EM: Stake amount must be greater than zero");
        Staker storage staker = stakers[msg.sender];

        // If not already active, add to activeStakers
        if (!staker.isActive) {
            staker.isActive = true;
            activeStakers.push(msg.sender);
        }

        // Update stake and capacity
        staker.stake += amount;
        staker.capacity += amount;

        // Assign entangler if not already assigned
        if (staker.entangler == bytes32(0)) {
            staker.entangler = calculateEntanglementWallet(msg.sender);
            stakerToEntangler[msg.sender] = staker.entangler;
            entanglerToStaker[staker.entangler] = msg.sender;
        }

        // Transfer QpBTC from staker to EntanglementManager
        // Assumes staker has approved EntanglementManager to transfer QpBTC
        bool success = qpBTC.transferFrom(msg.sender, address(this), amount);
        require(success, "EM: QpBTC transfer failed");

        emit StakerAdded(msg.sender, amount);
    }

    function unstakeBtc(uint256 amount) external {
        Staker storage staker = stakers[msg.sender];
        require(staker.stake >= amount, "EM: Unstake amount exceeds stake");
        require(staker.capacity >= amount, "EM: Unstake amount exceeds capacity");

        // Update stake and capacity
        staker.stake -= amount;
        staker.capacity -= amount;

        // Transfer QpBTC back to staker
        bool success = qpBTC.transfer(msg.sender, amount);
        require(success, "EM: QpBTC transfer failed");

        // If stake is zero, remove from activeStakers
        if (staker.stake == 0) {
            staker.isActive = false;
            _removeActiveStaker(msg.sender);
        }

        emit StakerRemoved(msg.sender, amount);
    }

    function getDepositAddress(uint256 depositAmount) external returns (bytes32 entangler) {
        require(depositAmount > 0, "EM: Deposit amount must be greater than zero");
        require(activeStakers.length > 0, "EM: No active stakers available");

        uint256 initialIndex = nextStakerIndex;
        bool found = false;
        address selectedStaker;

        // Iterate through activeStakers to find a staker with sufficient capacity
        for (uint256 i = 0; i < activeStakers.length; i++) {
            address stakerAddr = activeStakers[nextStakerIndex];
            Staker storage staker = stakers[stakerAddr];
            if (staker.capacity >= depositAmount) {
                selectedStaker = stakerAddr;
                found = true;
                break;
            }
            nextStakerIndex = (nextStakerIndex + 1) % activeStakers.length;
            if (nextStakerIndex == initialIndex) {
                break; // Completed a full loop
            }
        }

        require(found, "EM: No staker with sufficient capacity");

        // Assign the deposit to the selected staker
        Staker storage selectedStakerData = stakers[selectedStaker];
        selectedStakerData.capacity -= depositAmount;

        // Retrieve the entangler identifier
        entangler = selectedStakerData.entangler;

        emit DepositAssigned(selectedStaker, entangler, depositAmount);

        // Update the staker index for next assignment
        nextStakerIndex = (nextStakerIndex + 1) % activeStakers.length;
    }

    function capacityOfEntangler(bytes32 entangler) external view returns (uint256 capacity) {
        address staker = entanglerToStaker[entangler];
        if (staker != address(0)) {
            capacity = stakers[staker].capacity;
        } else {
            capacity = 0;
        }
    }

    function capacityOfStaker(address stakerAddr) external view returns (uint256 capacity) {
        Staker storage staker = stakers[stakerAddr];
        capacity = staker.capacity;
    }

    function calculateEntanglementWallet(address stakerAddr) public pure returns (bytes32 entangler) {
        entangler = keccak256(abi.encodePacked(stakerAddr));
    }

    function updateCapacity(bytes32 entangler, uint256 entangledBalance) external onlyIndexer {
        require(entangledBalance > 0, "EM: Entangled balance must be greater than zero");
        address stakerAddr = entanglerToStaker[entangler];
        require(stakerAddr != address(0), "EM: Invalid entangler identifier");
        Staker storage staker = stakers[stakerAddr];
        staker.capacity += entangledBalance;

        emit DepositProcessed(stakerAddr, entangledBalance, address(0)); // User address is not tracked here
    }

    function processDeposit(bytes32 entangler, uint256 amount, address user) external onlyIndexer {
        require(entangler != bytes32(0), "EM: Entangler identifier cannot be zero");
        require(user != address(0), "EM: User address cannot be zero");
        require(amount > 0, "EM: Deposit amount must be greater than zero");

        address stakerAddr = entanglerToStaker[entangler];
        require(stakerAddr != address(0), "EM: Invalid entangler identifier");

        Staker storage staker = stakers[stakerAddr];
        require(staker.capacity + amount <= staker.stake, "EM: Capacity exceeded after deposit");

        // Mint QpBTC to the user
        qpBTC.mint(user, amount);

        emit DepositProcessed(stakerAddr, amount, user);
    }

    function penalizeStaker(address stakerAddr, uint256 amount) external onlyOwner /** who decides penalizing? */ {
        require(stakerAddr != address(0), "EM: Staker address cannot be zero");
        require(amount > 0, "EM: Penalty amount must be greater than zero");

        Staker storage staker = stakers[stakerAddr];
        require(staker.stake >= amount, "EM: Penalty exceeds stake");
        require(staker.capacity >= amount, "EM: Penalty exceeds capacity");

        // Update stake and capacity
        staker.stake -= amount;
        staker.capacity -= amount;

        // Transfer confiscated funds to the ConfiscatedLiquidity
        confiscatedWallet.receiveConfiscatedFunds(stakerAddr, amount);

        emit StakerPenalized(stakerAddr, amount);
        emit FundsConfiscated(stakerAddr, amount);
    }

    function getStaker(address stakerAddr) external view returns (Staker memory) {
        return stakers[stakerAddr];
    }

    function _removeActiveStaker(address stakerAddr) internal {
        uint256 length = activeStakers.length;
        for (uint256 i = 0; i < length; i++) {
            if (activeStakers[i] == stakerAddr) {
                activeStakers[i] = activeStakers[length - 1];
                activeStakers.pop();
                break;
            }
        }
    }

    function getActiveStakersCount() external view returns (uint256) {
        return activeStakers.length;
    }

    function getActiveStaker(uint256 index) external view returns (address) {
        require(index < activeStakers.length, "EM: Index out of bounds");
        return activeStakers[index];
    }
}
