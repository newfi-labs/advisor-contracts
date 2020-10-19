// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';

/**
 * @title NewfiToken
 * @dev ERC20 token that automatically mints tokens based on the
 * proportional amount of ownership in a NewFi pool.
 * F = I * P
 * P = F / I
 * F = amount of tokens in the pool
 * I = amount of wrapped tokens held by investors
 * P = Price of the Wrapped Tokens
 */
contract NewfiToken is ERC20UpgradeSafe, OwnableUpgradeSafe {
    using SafeMath for uint256;

    /**
     * @dev initialize that gives holder all of existing tokens.
     */
    function initialize(string memory name, string memory symbol)
        public
        initializer
    {
        OwnableUpgradeSafe.__Ownable_init();
        ERC20UpgradeSafe.__ERC20_init(name, symbol);
    }

    function mintOwnershipTokens(
        address holder,
        uint256 poolTokens,
        uint256 toInvest
    ) public onlyOwner {
        require(toInvest > 0, 'Investment amount cannot be 0');
        uint256 safePoolSize = poolTokens <= 0 ? 1 : poolTokens;

        _mint(holder, toInvest.div(safePoolSize));
    }
}
