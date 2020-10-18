const {accounts, contract} = require('@openzeppelin/test-environment');
const {BN} = require('@openzeppelin/test-helpers');
const NewfiToken = contract.fromArtifact('NewfiToken');

describe('NewfiToken', () => {
  const [owner, user] = accounts;
  const tokenName = 'MockToken';
  const tokenSymbol = 'MTK';
  let decimals;
  let contract;
  let mockToken;

  beforeEach(async () => {
    contract = await NewfiToken.new({from: owner});
    mockToken = await contract.initialize(tokenName, tokenSymbol, {
      from: owner,
    });
    const contractDecimals = await contract.decimals();
    decimals = new BN((10 ** contractDecimals).toString());
  });

  describe('token instantiation', () => {
    it('creates a new novel token', async () => {
      const name = await contract.name();
      const symbol = await contract.symbol();

      expect(symbol).toEqual(tokenSymbol);
      expect(name).toEqual(tokenName);
    });
  });

  describe('token minting', () => {
    it('mints initial amount if pool size is negligible', async () => {
      await contract.mintOwnershipTokens(user, 10, 10000, {from: owner});
      const mintedTokens = await contract.totalSupply();
      expect(mintedTokens.div(decimals).toString()).toEqual('1000');
    });

    it('mints a proportional amount of tokens with second investor', async () => {
      await contract.mintOwnershipTokens(owner, 1, 10000, {from: owner});
      await contract.mintOwnershipTokens(user, 9000, 9000, {from: owner});
      const ownerTokens = await contract.balanceOf(user);
      const mintedTokens = await contract.balanceOf(user);

      expect(ownerTokens.div(decimals).toString());
      expect(mintedTokens.div(decimals).toString()).toEqual('10000');
    });
  });
});
