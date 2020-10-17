// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import "./ProxyFactory.sol";

contract NewfiTokenFactory is ProxyFactory {
    address[] public tokens;

    event TokenCreated(address indexed tokenAddress);

    function createToken(address logic, string calldata name, string calldata symbol, address holder) external {
        bytes memory payload = abi.encodeWithSignature("initialize(string,string)", name, symbol, holder);

        address token = deployMinimal(logic, payload);
        emit TokenCreated(token);

        tokens.push(token);
    }
}
