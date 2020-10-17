// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

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
     function initialize(string memory name, string memory symbol) public initializer {
         OwnableUpgradeSafe.__Ownable_init();
         ERC20UpgradeSafe.__ERC20_init(name, symbol);
     }

    /**
     * @dev mint new proof of ownership tokens.
     * Minted = Invest * (wrappedTokens / poolTokens)
     * At the start P = 1, therefore I = F, value = wrapped tokens
     */
    function mintOwnershipTokens(address holder, uint poolTokens, uint toInvest) public onlyOwner {
        require(poolTokens > 0);
        require(toInvest > 0);
        uint256 tokenDecimals = 10 ** uint256(decimals());
        uint256 wrappedTokens = totalSupply() == 0 ? 1 : totalSupply().div(tokenDecimals);

        _mint(holder, (toInvest.mul(wrappedTokens).div(poolTokens)).mul(tokenDecimals));
    }
}
