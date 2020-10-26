// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol';

contract MockToken is ERC20UpgradeSafe {
    function initialize(string memory name, string memory symbol)
        public
        initializer
    {
        ERC20UpgradeSafe.__ERC20_init(name, symbol);
    }

    function mintTokens(uint256 amount) public {
        _mint(msg.sender, amount * (10**uint256(decimals())));
    }
}
