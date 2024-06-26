// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IQuantumPortalWorkPoolClient.sol";
import "foundry-contracts/contracts/math/FullMath.sol";
import "foundry-contracts/contracts/common/SafeAmount.sol";
import "foundry-contracts/contracts/math/FixedPoint128.sol";
import "../utils/WithQp.sol";
import "../utils/WithRemotePeers.sol";
import "../utils/WithLedgerMgr.sol";

import "hardhat/console.sol";

/**
 * @notice Record amount of work done, and distribute rewards accordingly.
 */
abstract contract QuantumPortalWorkPoolClient is
    IQuantumPortalWorkPoolClient, WithQp, WithLedgerMgr, WithRemotePeers
{
    mapping(uint256 => mapping(address => uint256)) public works; // Work done on remote chain
    mapping(uint256 => uint256) public totalWork; // Total work on remote chain
    mapping(uint256 => uint256) public remoteEpoch;

    /**
     * @inheritdoc IQuantumPortalWorkPoolClient
     */
    function registerWork(
        uint256 remoteChain,
        address worker,
        uint256 work,
        uint256 _remoteEpoch
    ) external override onlyMgr {
        works[remoteChain][worker] += work;
        console.log("REGISTERING WORK", worker, work);
        totalWork[remoteChain] += work;
        remoteEpoch[remoteChain] = _remoteEpoch;
    }

    /**
     * @notice Withdraw the rewards on the remote chain. Note: in case of
     * tx failure the funds are gone. So make sure to provide enough fees to ensure the 
     * tx does not fail because of gas.
     * @param selector The selector
     * @param remoteChain The remote
     * @param to Send the rewards to
     * @param worker The worker
     * @param fee The multi-chain transaction fee
     */
    function withdraw(
        bytes4 selector,
        uint256 remoteChain,
        address to,
        address worker,
        uint fee
    ) internal {
        uint256 work = works[remoteChain][worker];
        delete works[remoteChain][worker];
        // Send the fee
        require(
            SafeAmount.safeTransferFrom(
                portal.feeToken(),
                msg.sender,
                portal.feeTarget(),
                fee
            ) != 0,
            "QPWPC: fee required"
        );
        uint256 workRatioX128 = FullMath.mulDiv(
            work,
            FixedPoint128.Q128,
            totalWork[remoteChain]
        );
        uint256 epoch = remoteEpoch[remoteChain];
        bytes memory method = abi.encodeWithSelector(
            selector,
            to,
            workRatioX128,
            epoch
        );
        address serverContract = remotePeers[remoteChain];
        console.log("ABOUT TO CALL REMOTE WITHDRAW", serverContract);
        console.log("WORKER", worker, to);
        console.log("WORKE RATIO", work, workRatioX128);
        console.log("EPOCH", epoch);
        portal.run(uint64(remoteChain), serverContract, msg.sender, method);
    }
}
