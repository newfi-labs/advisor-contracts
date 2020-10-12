const { accounts, contract } = require('@openzeppelin/test-environment');

const NewfiAdvisor = contract.fromArtifact('NewfiAdvisor');

const IERC20 = contract.fromArtifact('IERC20');

const { BN } = require('@openzeppelin/test-helpers');

describe('NewfiAdvisor', async () => {
    const [ owner, advisor, investor ] = accounts;
    const unlokedAddress = 0xa5407eae9ba41422680e2e00537571bcc53efbfd;
    const usdc = await IERC20.at(0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48);
    let contract;

    beforeEach(async () => {
        contract = await NewfiAdvisor.new(
        // deployed by forking mainnet in ganache
        0xd62c837e2059ae5723ab0f084deb5cbfb4dbef3a,
        0x3d5c8955bd6aaa778018309acfd8a5b30b4e86ee,
        0xe2f2a5C287993345a840Db3B0845fbC70f5935a5,
        0xcf3f73290803fc04425bee135a4caeb2bab2c2a1,
        { from: owner });
        await usdc.transfer(advisor, new BN("10000000000000000000"), {from : unlokedAddress});
        await usdc.transfer(investor, new BN("10000000000000000000"), {from : unlokedAddress});
    });

    it('onboards a new advisor', async () => {
        await contract.onboard("Mock Advisor", { from: owner });
        const advisorInfo = await contract.advisorInfo(advisor);

        expect(advisorInfo.name).toEqual('Mock Advisor');
    });

    it('onboards a new investor with them selecting a advisor', async () => {
        await usdc.approve(contract.address, new BN("300000000000"), {from: investor})
        await contract.invest(usdc.address, new BN("200000"), advisor, 80, 20, { from: investor, value: new BN("1000") });
        const investorInfo = await contract.investorInfo(investor);

        expect(investorInfo.stablePoolLiquidity).toEqual(new BN("200000"));
    });

    it('allows the advisor to stake and invest into protocols ', async () => {
        await usdc.approve(contract.address, new BN("300000000000"), {from: advisor})
        await contract.protocolInvestment(usdc.address, new BN("200000"), [new BN("1000")], [0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7], { from: advisor });

    });
});