// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IndexerRole.sol";
import "./EntanglementManager.sol";


contract SettlementManager is IndexerRole {
    struct SettlementInfo {
        bytes32 settlementId;
        bytes32 btcTransactionHash;
        address settler;
        bool complete;
        address user;
        uint256 amount;
    }

    mapping(bytes32 => SettlementInfo) public settlements;
    EntanglementManager public entanglementManager;

    event SettlementRequested(bytes32 indexed settlementId, address indexed user, uint256 amount);
    event SettlementCompleted(bytes32 indexed settlementId, address indexed settler, address indexed user, uint256 amount);
    event SettlementFailed(bytes32 indexed settlementId, address indexed settler, address indexed user, uint256 amount, string reason);

    constructor(address _entanglementManager) {
        require(_entanglementManager != address(0), "SM: EntanglementManager address cannot be zero");
        entanglementManager = EntanglementManager(_entanglementManager);
    }

    function requestSettlement(bytes32 toAddress, uint256 amount) external returns (bytes32 settlementId) {
        require(amount > 0, "SM: Settlement amount must be greater than zero");
        require(entanglementManager.capacityOfStaker(msg.sender) >= amount, "SM: Insufficient capacity for settlement");

        // Generate a unique settlement ID
        settlementId = keccak256(abi.encodePacked(msg.sender, block.timestamp, amount));
        require(settlements[settlementId].settlementId == bytes32(0), "SM: Settlement ID already exists");

        // Record the settlement request
        settlements[settlementId] = SettlementInfo({
            settlementId: settlementId,
            btcTransactionHash: bytes32(0),
            settler: address(0),
            complete: false,
            user: msg.sender,
            amount: amount
        });

        emit SettlementRequested(settlementId, msg.sender, amount);
    }

    function findSettler(bytes32 settlementId, uint256 timestamp) external view returns (address settler) {
        SettlementInfo storage settlement = settlements[settlementId];
        require(settlement.settlementId != bytes32(0), "SM: Settlement does not exist");
        require(!settlement.complete, "SM: Settlement already completed");

        // Logic to find a suitable staker based on capacity
        // For simplicity, iterate through active stakers and select the first with sufficient capacity
        uint256 activeStakersCount = entanglementManager.getActiveStakersCount();
        require(activeStakersCount > 0, "SM: No active stakers available");

        for (uint256 i = 0; i < activeStakersCount; i++) {
            address staker = entanglementManager.getActiveStaker(i);
            uint256 stakerCapacity = entanglementManager.capacityOfStaker(staker);
            if (stakerCapacity >= settlement.amount) {
                settler = staker;
                break;
            }
        }

        require(settler != address(0), "SM: No staker with sufficient capacity found");
    }

    function selectSettler(
        address requestedSettler,
        bytes32 settlementId,
        uint256 timestamp
    ) external onlyOwner returns (bool success) {
        require(requestedSettler != address(0), "SM: Requested settler address cannot be zero");
        SettlementInfo storage settlement = settlements[settlementId];
        require(settlement.settlementId != bytes32(0), "SM: Settlement does not exist");
        require(!settlement.complete, "SM: Settlement already completed");

        uint256 stakerCapacity = entanglementManager.capacityOfStaker(requestedSettler);
        require(stakerCapacity >= settlement.amount, "SM: Requested settler has insufficient capacity");

        // Assign the settler
        settlement.settler = requestedSettler;
        success = true;

        return success;
    }

    function settlementStatus(bytes32 settlementId) external view returns (SettlementInfo memory settlementInfo) {
        settlementInfo = settlements[settlementId];
    }

    function registerExecution(bytes32 settlementId, bytes32 btcTransactionHash) external onlyOwner {
        SettlementInfo storage settlement = settlements[settlementId];
        require(settlement.settlementId != bytes32(0), "SM: Settlement does not exist");
        require(!settlement.complete, "SM: Settlement already completed");
        require(settlement.settler != address(0), "SM: Settler not selected");

        // Update settlement details
        settlement.btcTransactionHash = btcTransactionHash;
        settlement.complete = true;

        // Burn QpBTC from the user
        // Assuming EntanglementManager handles burning in processDeposit
        entanglementManager.processDeposit(
            entanglementManager.stakerToEntangler(settlement.settler),
            settlement.amount,
            settlement.user
        );

        emit SettlementCompleted(settlementId, settlement.settler, settlement.user, settlement.amount);
    }

    function setEntanglementManager(address _entanglementManager) external onlyOwner {
        require(_entanglementManager != address(0), "SM: EntanglementManager address cannot be zero");
        entanglementManager = EntanglementManager(_entanglementManager);
    }
}
