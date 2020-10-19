const {accounts, contract} = require('@openzeppelin/test-environment');
const {expectEvent, constants} = require('@openzeppelin/test-helpers');
const {BN} = require('@openzeppelin/test-helpers');
const NewfiToken = contract.fromArtifact('NewfiToken');
const {ZERO_ADDRESS} = constants;

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
      const receipt = await contract.mintOwnershipTokens(user, 10, 10000, {
        from: owner,
      });

      expectEvent(receipt, 'Transfer', {
        from: ZERO_ADDRESS,
        to: user,
        value: '1000000000000000000000',
      });
    });

    it('mints a proportional amount of tokens with second investor', async () => {
      const receipt = await contract.mintOwnershipTokens(owner, 1, 10000, {
        from: owner,
      });
      const secondReceipt = await contract.mintOwnershipTokens(
        user,
        9000,
        9000,
        {from: owner}
      );

      expectEvent(receipt, 'Transfer', {
        from: ZERO_ADDRESS,
        to: owner,
        value: '10000000000000000000000',
      });
      expectEvent(secondReceipt, 'Transfer', {
        from: ZERO_ADDRESS,
        to: user,
        value: '10000000000000000000000',
      });
    });
  });
});
