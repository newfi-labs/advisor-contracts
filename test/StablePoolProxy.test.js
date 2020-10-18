const {accounts, contract} = require('@openzeppelin/test-environment');
const StablePoolProxy = contract.fromArtifact('StablePoolProxy');

describe('StablePoolProxy', () => {
  const [owner] = accounts;
  let contract;

  beforeEach(async () => {
    contract = await StablePoolProxy.new({from: owner});
    await contract.initialize(owner, {from: owner});
  });

  it('does stuff', () => {
    expect(true).toEqual(true);
  });
});
