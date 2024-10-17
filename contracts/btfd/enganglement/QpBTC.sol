// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";


contract QpBTC is ERC20Burnable, Ownable {

    constructor() Ownable(tx.origin) ERC20("Quantum Portal BTC", "QpBTC") {
        _mint(msg.sender, 10000000 ether);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
