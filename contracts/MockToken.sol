// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount, 
        uint256 initialBalance 
    ) ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function faucet() external {
        uint256 faucetAmount = 1000 * 10**decimals();
        _mint(msg.sender, faucetAmount);
    }
}