// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IQuantumPortalStake.sol";
import "./QuantumPortalAuthorityMgr.sol";
import "./Delegator.sol";
import "../../../staking/StakeOpen.sol";

import "hardhat/console.sol";

/**
 @notice The QP stake, is a special type of open staking, with two exceptions:
    1 - Unstake will move assets to a locked state, for a period.
    2 - Authorities can slash
 */
contract QuantumPortalStake is StakeOpen, Delegator, IQuantumPortalStake {
    struct WithdrawItem {
        uint64 opensAt;
        uint128 amount;
    }
    struct Pair {
        uint64 start;
        uint64 end;
    }

    uint64 constant WITHDRAW_LOCK = 30 * 3600 * 24;
    address public override STAKE_ID;
    address slashTarget;
    IQuantumPortalAuthorityMgr public auth;
    mapping(address => Pair) public withdrawItemsQueueParam;
    mapping(address => mapping (uint => WithdrawItem)) public withdrawItemsQueue;

    constructor() {
        bytes memory _data = IFerrumDeployer(msg.sender).initData();
        (address token, address authority) = abi.decode(_data, (address, address));
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        _init(token, "QP Stake", tokens);
        STAKE_ID = token;
        auth = IQuantumPortalAuthorityMgr(authority);
    }

    function delegatedStakeOf(address delegatee
    ) external override view returns (uint256) {
        require(delegatee != address(0), "QPS: delegatee required");
        address staker = reverseDelegation[delegatee];
        require(staker != address(0), "QPS: delegatee not valid");
		return state.stakes[STAKE_ID][staker];
	}

    /**
     @notice This will first, release all the available withdraw items, 
     */
    function _withdraw(
        address to,
        address id,
        address staker,
        uint256 amount
    ) internal override nonZeroAddress(staker) {
        require(id == STAKE_ID, "QPS: bad id");
        require(to == msg.sender, "QPS: only withdraw to self");
        if (amount == 0) {
            return;
        }
        // Below assumed
        // StakingBasics.StakeInfo memory info = stakings[id];
        // require(
        //     info.stakeType == Staking.StakeType.OpenEnded,
        //     "SO: Not open ended stake"
        // );
        releaseWithdrawItems(staker, staker, 0);
        _withdrawOnlyUpdateStateAndPayRewards(to, id, staker, amount);

        // Lock balance
        WithdrawItem memory wi = WithdrawItem({
            opensAt: uint64(block.timestamp) + WITHDRAW_LOCK,
            amount: uint128(amount)
        });
        pushToQueue(staker, wi);
    }

    function releaseWithdrawItems(address staker, address receiver, uint256 max
    ) public returns(uint256 total) {
        require(staker != address(0), "QPS: staker requried");
        address token = baseInfo.baseToken[STAKE_ID];
        (Pair memory pair, WithdrawItem memory wi) = peekQueue(staker);
        console.log("PEEKED", wi.opensAt, block.timestamp);
        while(wi.opensAt != 0 && wi.opensAt < block.timestamp) {
            popFromQueue(staker, pair);
            console.log("Sending tokens ", wi.amount);
            sendToken(token, receiver, wi.amount);
            total += wi.amount;
            console.log("Total is", total);
            if (max != 0 && total >= max) {
                // Shortcut if total greater than 0
                return total;
            }
            (pair, wi) = peekQueue(staker);
            console.log("PEEKED", wi.opensAt, block.timestamp);
        }
    }

    bytes32 constant SLASH_STAKE =
        keccak256("SlashStake(address user,uint256 amount)");
    function slashUser(
        address user,
        uint256 amount,
        uint64 expiry,
        bytes32 salt,
        bytes memory multiSignature
    ) external returns (uint256) {
        bytes32 message = keccak256(abi.encode(SLASH_STAKE, user, amount));
        auth.validateAuthoritySignature(IQuantumPortalAuthorityMgr.Action.SLASH, message, salt, expiry, multiSignature);
        amount = slashWithdrawItem(user, amount);
        return slashStake(user, amount);
    }

    function slashStake(
        address staker,
        uint256 amount
    ) internal returns (uint256 remaining) {
		uint stake = state.stakes[STAKE_ID][staker];
        stake = amount < stake ? amount : stake;
        remaining = amount - stake;
        _withdrawOnlyUpdateStateAndPayRewards(slashTarget, STAKE_ID, staker, stake);
        address token = baseInfo.baseToken[STAKE_ID];
        sendToken(token, slashTarget, amount);
    }

    function slashWithdrawItem(
        address staker,
        uint256 amount
    ) internal returns (uint256) {
        uint released = releaseWithdrawItems(staker, slashTarget, amount);
        return amount > released ? amount - released : 0;
    }

    function pushToQueue(address staker, WithdrawItem memory wi) private {
        uint end = withdrawItemsQueueParam[staker].end;
        withdrawItemsQueueParam[staker].end = uint64(end) + 1;
        withdrawItemsQueue[staker][end] = wi; // starts from 0, so end is empty by now
    }

    function popFromQueue(address staker, Pair memory pair) private {
        withdrawItemsQueueParam[staker].start = pair.start + 1;
        delete withdrawItemsQueue[staker][pair.start];
    }

    function peekQueue(address staker) private returns (Pair memory pair, WithdrawItem memory wi) {
        pair = withdrawItemsQueueParam[staker];
        wi = withdrawItemsQueue[staker][pair.start];
    }
}