# advisor-contracts

Main contracts for the NewFi advisor / investor portal. Implemented on top of OpenZeppelin
contracts with Truffle scaffolding.

## Getting started

- Install ganache-cli: `https://github.com/trufflesuite/ganache-cli`.
- Download Ethereum grid: `https://github.com/ethereum/grid`.
- Install project dependencies: `npm install`.

### Setup mainnet fork

- In Ethereum grid run both geth and ipfs - wait for geth node to sync.

> IPFS will be running on ip `http://127.0.0.1:8080`

Then make sure the ganache-cli is running with mainnet fork:

`ganache-cli --fork http://localhost:8545 --networkId 1` // optional --verbose for debugging

> You can also run the Ganache client GUI which helps keep track of accounts and other chain data.

Next deploy NewFi contracts to the local chain:

`npx truffle migrate`
