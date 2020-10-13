const { accounts, contract } = require('@openzeppelin/test-environment');
const NewfiTokenFactory = contract.fromArtifact('NewfiTokenFactory');
const NewfiToken = contract.fromArtifact('NewfiToken');

describe('NewfiTokenFactory', () => {
    const [ owner, deployer ] = accounts;
    let logic;
    let factory;

    beforeEach(async () => {
        logic = await NewfiToken.new(owner, { from: deployer });
        factory = await NewfiTokenFactory.new(owner, { from: deployer });
    });

    it('creates n+1 newfi tokens', async () => {
        await factory.createToken(logic.address, 'Token A', 'TKA', owner);
        await factory.createToken(logic.address, 'Token B', 'TKB', owner);

        const tokenA = await NewfiToken.at(await factory.tokens(0));
        const tokenB = await NewfiToken.at(await factory.tokens(1));

        expect(await tokenA.name()).toEqual('Token A');
        expect(await tokenB.symbol()).toEqual('TKB');
    })
});
