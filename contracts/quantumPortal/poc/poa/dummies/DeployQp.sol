// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./QpDependenciesDev.sol";
import "../QuantumPortalFeeConvertorDirect.sol";
import "../../test/QuantumPortalPocTest.sol";
import "../../QuantumPortalLedgerMgr.sol";
import "../../QuantumPortalNativeFeeRepo.sol";
import "../../QuantumPortalState.sol";
import "../../QuantumPortalGateway.sol";

contract QpFeeToken is ERC20Burnable {
        constructor() ERC20("QP Fee Test Token", "TQP") {
                _mint(msg.sender, 1000000000 * 10 ** 18);
        }
}


contract DeployQp {
    address public gateway;
    address public feeToken;

    function deployFeeToken() public {
        address _feeToken = address(new QpFeeToken{salt: bytes32(0x0)}());
        feeToken = _feeToken;
        // IERC20(feeToken).transfer(msg.sender, IERC20(feeToken).balanceOf(address(this)));
    }

    function deployWithToken(uint64 overrideChainId) external {
        deployFeeToken();
        deploy(feeToken, overrideChainId);
    }

    function deploy(address _feeToken, uint64 overrideChainId) public {
        if (overrideChainId == 0) {
            overrideChainId = uint64(block.chainid);
        }
        feeToken = _feeToken;
        QuantumPortalNativeFeeRepo nativeFee = new QuantumPortalNativeFeeRepo{salt: bytes32(0x0)}();
        QuantumPortalFeeConvertorDirect feeConvertor = new QuantumPortalFeeConvertorDirect{salt: bytes32(0x0)}();
        QuantumPortalState state = new QuantumPortalState{salt: bytes32(0x0)}();
        QuantumPortalLedgerMgr mgr = new QuantumPortalLedgerMgr{salt: bytes32(0x0)}(overrideChainId);
        QuantumPortalPocTest ledger = new QuantumPortalPocTest{salt: bytes32(0x0)}(overrideChainId);
        QuantumPortalGateway_DEV _gateway = new QuantumPortalGateway_DEV{salt: bytes32(0x0)}();
        gateway = address(_gateway);

        QpDependenciesDev deps = new QpDependenciesDev{salt: bytes32(0x0)}(_feeToken);

        nativeFee.init(address(ledger), address(feeConvertor));
        state.setMgr(address(mgr));
        state.setLedger(address(ledger));

        mgr.updateState(address(state));
        mgr.updateLedger(address(ledger));
        mgr.updateAuthorityMgr(address(deps));
        mgr.updateMinerMgr(address(deps));
        mgr.updateFeeConvertor(address(feeConvertor));

        ledger.updateFeeTarget();
        ledger.setFeeToken(_feeToken);
        ledger.setNativeFeeRepo(address(nativeFee));
        _gateway.upgrade(address(ledger), address(mgr));

        nativeFee.transferOwnership(msg.sender);
        feeConvertor.transferOwnership(msg.sender);
        state.transferOwnership(msg.sender);
        mgr.transferOwnership(msg.sender);
        ledger.transferOwnership(msg.sender);
        _gateway.transferOwnership(msg.sender);
    }

    function realChainId() external view returns (uint256) {
        return block.chainid;
    }
}