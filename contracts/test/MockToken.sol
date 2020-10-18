// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MCK") public {
    }

    function mintTokens(uint256 amount) public {
        _mint(msg.sender, amount * (10 ** uint256(decimals())));
    }
}
