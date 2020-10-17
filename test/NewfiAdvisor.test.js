const { accounts, contract, web3 } = require('@openzeppelin/test-environment');
const { expectEvent, ether } = require('@openzeppelin/test-helpers');

const NewfiAdvisor = contract.fromArtifact('NewfiAdvisor');
const StablePoolProxy = contract.fromArtifact('StablePoolProxy');
const VolatilePoolProxy = contract.fromArtifact('VolatilePoolProxy');
const MockToken = contract.fromArtifact('MockToken');

describe('NewfiAdvisor', () => {
    const [ mainAdvisor, secondAdvisor, investor ] = accounts;
    let contract;
    let mockToken;
    let stableProxy;
    let volatileProxy;

    beforeEach(async () => {
        // Proxy pools are initialized in the NewfiAdvisor init function.
        stableProxy = await StablePoolProxy.new({ from: mainAdvisor });
        volatileProxy = await VolatilePoolProxy.new({ from: mainAdvisor });
        contract = await NewfiAdvisor.new({ from: mainAdvisor });
        mockToken = await MockToken.new({ from: mainAdvisor });

        // Onboard a main advisor
        await contract.initialize(
            'Mock Advisor',
            stableProxy.address,
            volatileProxy.address,
            60,
            40,
          { from: mainAdvisor });

        // Onboard second advisor
        await contract.initialize(
            'Second Advisor',
            stableProxy.address,
            volatileProxy.address,
            50,
            50,
            { from: secondAdvisor }
        )
    });

    describe('advisor', () => {
        it('can get name', async () => {
            const name = await contract.advisorName(mainAdvisor);
            expect(name).toEqual('Mock Advisor');
        });
    });

    describe('investors', () => {
        beforeEach(async () => {
            await mockToken.mintTokens(10000, { from: investor });
            await mockToken.increaseAllowance(contract.address, 10000, { from: investor });
        });

        it('can add stable pool liquidity', async () => {
            const receipt = await contract.invest(
              mockToken.address,
              1000,
              mainAdvisor,
              100,
              0,
              { from: investor },
            );

            expectEvent(receipt, 'Investment', {
                _stablecoinAmount: '1000',
                _volatileAmount: '0',
                _advisor: mainAdvisor
            });
        });

        it('can add volatile pool liquidity', async () => {
            const receipt = await contract.invest(
                mockToken.address,
                1000,
                mainAdvisor,
                0,
                100,
                { from: investor },
            );

            expectEvent(receipt, 'Investment', {
                _stablecoinAmount: '0',
                _volatileAmount: '1000',
                _advisor: mainAdvisor
            });
        });

        it('can add both volatile and stable pool liquidity', async () => {
            const receipt = await contract.invest(
                mockToken.address,
                1000,
                mainAdvisor,
                60,
                40,
                { from: investor },
            );

            expectEvent(receipt, 'Investment', {
                _stablecoinAmount: '600',
                _volatileAmount: '400',
                _advisor: mainAdvisor
            });
        });

        it('can invest eth into advisor', async () => {
            const receipt = await contract.invest(
                mockToken.address,
                0,
                mainAdvisor,
                0,
                100,
                { from: investor, value: ether('25') }
            );

            const volatilePool = await contract.advisorVolatilePool(mainAdvisor);
            const balance = await web3.eth.getBalance(volatilePool);

            expect(balance / (10 ** 18)).toEqual(25);
            expectEvent(receipt, 'Investment', {
                _stablecoinAmount: '0',
                _volatileAmount: '0',
                _ethAmount: '25',
                _advisor: mainAdvisor
            });
        });

        it('can invest more into the same advisor', async () => {
            await contract.invest(
                mockToken.address,
                1000,
                mainAdvisor,
                60,
                40,
                { from: investor },
            );
            const receipt = await contract.invest(
                mockToken.address,
                1000,
                mainAdvisor,
                50,
                50,
                { from: investor },
            );
            const  stablePoolLiquidity = await contract.investorStableLiquidity(investor);
            const volatileLiquidity = await contract.investorVolatileLiquidity(investor);

            expect(stablePoolLiquidity.toString()).toEqual('1100');
            expect(volatileLiquidity.toString()).toEqual('900');

            expectEvent(receipt, 'Investment', {
                _stablecoinAmount: '500',
                _volatileAmount: '500',
                _advisor: mainAdvisor
            });
        });

        it('can invest into two different advisors', async () => {
            const firstReceipt = await contract.invest(
                mockToken.address,
                1000,
                mainAdvisor,
                60,
                40,
                { from: investor },
            );
            const secondReceipt = await contract.invest(
                mockToken.address,
                1000,
                secondAdvisor,
                50,
                50,
                { from: investor },
            );
            const  stablePoolLiquidity = await contract.investorStableLiquidity(investor);
            const volatileLiquidity = await contract.investorVolatileLiquidity(investor);
            const advisors = await contract.getAdvisors(investor);

            expect(stablePoolLiquidity.toString()).toEqual('1100');
            expect(volatileLiquidity.toString()).toEqual('900');
            expect(advisors).toEqual([mainAdvisor, secondAdvisor]);

            expectEvent(firstReceipt, 'Investment', {
                _stablecoinAmount: '600',
                _volatileAmount: '400',
                _advisor: mainAdvisor
            });
            expectEvent(secondReceipt, 'Investment', {
                _stablecoinAmount: '500',
                _volatileAmount: '500',
                _advisor: secondAdvisor
            });
        })
    });
});
