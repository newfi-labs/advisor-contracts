const {accounts, contract} = require('@openzeppelin/test-environment');
const VolatilePoolProxy = contract.fromArtifact('VolatilePoolProxy');

describe('VolatilePoolProxy', () => {
  const [owner] = accounts;
  let contract;

  beforeEach(async () => {
    contract = await VolatilePoolProxy.new({from: owner});
    await contract.initialize(owner, {from: owner});
  });

  it('does stuff', () => {
    expect(true).toEqual(true);
  });
});
