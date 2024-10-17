// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./QpBTC.sol";


contract ConfiscatedLiquidity is Ownable {
    QpBTC qpBtc;
    mapping(address => uint256) public confiscatedAmounts;

    event FundsConfiscated(address indexed lp, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount);

    constructor(address _qpBtc) Ownable(tx.origin) {
        require(_qpBtc != address(0), "CL: QpBTC address cannot be zero");
        qpBtc = QpBTC(_qpBtc);
    }

    function receiveConfiscatedFunds(address lp, uint256 amount) external onlyOwner {
        require(lp != address(0), "CL: LP address cannot be zero");
        require(amount > 0, "CL: Confiscated amount must be greater than zero");
        confiscatedAmounts[lp] += amount;
        emit FundsConfiscated(lp, amount);
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "CL: Cannot withdraw to zero address");
        require(amount > 0, "CL: Withdraw amount must be greater than zero");

        qpBtc.transfer(to, amount);
        emit FundsWithdrawn(to, amount);
    }
}
