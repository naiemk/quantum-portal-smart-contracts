import hre from "hardhat"
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules"
import { ZeroAddress } from "ethers";
import { loadQpDeployConfig, QpDeployConfig } from "../../scripts/utils/DeployUtils";
const DEFAULT_QP_CONFIG_FILE = 'QpDeployConfig.yaml';


const deployModule = buildModule("DeployModule", (m) => {
    const currentChainId = 31337 // hre.network.config.chainId;
    const conf: QpDeployConfig = loadQpDeployConfig(process.env.QP_CONFIG_FILE || DEFAULT_QP_CONFIG_FILE);
    const owner = m.getAccount(0)

    //--------------- Gateway ----------------//
    const gatewayImpl = m.contract("QuantumPortalGatewayUpgradeable", [conf.FRM[currentChainId!]], { id: "QPGatewayImpl"})
    let initializeCalldata: any = m.encodeFunctionCall(gatewayImpl, "initialize", [
		owner,
		owner
	]);
    const gatewayProxy = m.contract("ERC1967Proxy", [gatewayImpl, initializeCalldata], { id: "GatewayProxy"})
    const gateway = m.contractAt("QuantumPortalGatewayUpgradeable", gatewayProxy, { id: "Gateway"})

    //--------------- LedgerManager -----------//
    const ledgerMgrImpl = m.contract("QuantumPortalLedgerMgrImplUpgradeable", [], { id: "LedgerMgrImpl"})
    initializeCalldata = m.encodeFunctionCall(ledgerMgrImpl, "initialize", [
        owner,
        owner,
        conf.QuantumPortalMinStake!,
        gateway
    ]);
    const ledgerMgrProxy = m.contract("ERC1967Proxy", [ledgerMgrImpl, initializeCalldata], { id: "LedgerMgrProxy"})
    const ledgerMgr = m.contractAt("QuantumPortalLedgerMgrImplUpgradeable", ledgerMgrProxy, { id: "LedgerMgr"})

    //--------------- Poc ---------------------//
    const pocImpl = m.contract("QuantumPortalPocImplUpgradeable", [], { id: "PocImpl"})
    initializeCalldata = m.encodeFunctionCall(pocImpl, "initialize", [
        owner,
        owner,
        gateway
    ]);
    const pocProxy = m.contract("ERC1967Proxy", [pocImpl, initializeCalldata], { id: "PocProxy"})
    const poc = m.contractAt("QuantumPortalPocImplUpgradeable", pocProxy, { id: "Poc"})

    //--------------- AuthorityManager --------//
    const authMgrImpl = m.contract("QuantumPortalAuthorityMgrUpgradeable", [], { id: "AuthMgrImpl"})
    initializeCalldata = m.encodeFunctionCall(authMgrImpl, "initialize", [
        ledgerMgr,
        poc,
        owner,
        owner,
        gateway
    ]);
    const authMgrProxy = m.contract("ERC1967Proxy", [authMgrImpl, initializeCalldata], { id: "AuthMgrProxy"})
    const authMgr = m.contractAt("QuantumPortalAuthorityMgrUpgradeable", authMgrProxy, { id: "AuthMgr"})

    //--------------- Oracle ------------------//
    const oracle = m.contract("UniswapOracle", [conf.UniV2Factory[currentChainId!]], { id: "Oracle"})

    //--------------- FeeConverter ------------//
    const feeConverterImpl = m.contract("QuantumPortalFeeConverterUpgradeable", [], { id: "FeeConverterImpl"})
    initializeCalldata = m.encodeFunctionCall(feeConverterImpl, "initialize", [
        conf.WETH[currentChainId!],
        conf.FRM[currentChainId!],
        oracle,
        gateway
    ]);
    const feeConverterProxy = m.contract("ERC1967Proxy", [feeConverterImpl, initializeCalldata], { id: "FeeConverterProxy"})
    const feeConverter = m.contractAt("QuantumPortalFeeConverterUpgradeable", feeConverterProxy, { id: "FeeConverter"})

    //--------------- StakeWithDelegate -------//
    const stakingImpl = m.contract("QuantumPortalStakeWithDelegateUpgradeable", [], { id: "StakingImpl"})
    initializeCalldata = m.encodeFunctionCall(stakingImpl, "initialize(address,address,address,address)", [
        conf.FRM[currentChainId!],
        authMgr,
        ZeroAddress,
        gateway
    ]);
    const stakingProxy = m.contract("ERC1967Proxy", [stakingImpl, initializeCalldata], { id: "StakingProxy"})
    const staking = m.contractAt("QuantumPortalStakeWithDelegateUpgradeable", stakingProxy, { id: "Staking"})

    //---------------- MiningManager ----------//
    const minerMgrImpl = m.contract("QuantumPortalMinerMgrUpgradeable", [], { id: "MinerMgrImpl"})
    initializeCalldata = m.encodeFunctionCall(minerMgrImpl, "initialize", [
        staking,
        poc,
        ledgerMgr,
        gateway
    ]);
    const minerMgrProxy = m.contract("ERC1967Proxy", [minerMgrImpl, initializeCalldata], { id: "MinerMgrProxy"})
    const minerMgr = m.contractAt("QuantumPortalMinerMgrUpgradeable", minerMgrProxy, { id: "MinerMgr"})

    //----------------- Setup -----------------//
    m.call(ledgerMgr, "updateAuthorityMgr", [authMgr])
	m.call(ledgerMgr, "updateMinerMgr", [minerMgr])
	m.call(ledgerMgr, "updateFeeConvertor", [feeConverter])

    m.call(poc, "setManager", [ledgerMgr])
	m.call(poc, "setFeeToken", [conf.FRM[currentChainId!]])
    
	m.call(minerMgr, "updateBaseToken", [conf.FRM[currentChainId!]])
	m.call(ledgerMgr, "updateLedger", [poc])
    
	m.call(poc, "updateFeeTarget")
    return {
        gateway,
        ledgerMgr,
        poc,
        authMgr,
        oracle,
        feeConverter,
        staking,
        minerMgr
    }
})

export default deployModule;