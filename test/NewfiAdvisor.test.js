const { accounts, contract } = require('@openzeppelin/test-environment');
const NewfiAdvisor = contract.fromArtifact('NewfiAdvisor');

describe('NewfiAdvisor', () => {
    const [ owner ] = accounts;
    let contract;

    beforeEach(async () => {
        contract = await NewfiAdvisor.new({ from: owner });
    });

    it('onboards a new advisor', async () => {
        await contract.onboard("Mock Advisor", { from: owner });
        const advisorInfo = await contract.advisorInfo(owner);

        expect(advisorInfo.name).toEqual('Mock Advisor');
    });
});
