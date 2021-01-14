const {accounts, contract, web3} = require('@openzeppelin/test-environment');
const {
  expectEvent,
  ether,
  BN,
  constants,
} = require('@openzeppelin/test-helpers');
const timeMachine = require('ganache-time-traveler');

const NewfiAdvisor = contract.fromArtifact('NewfiAdvisor');
const StablePoolProxy = contract.fromArtifact('StablePoolProxy');
const VolatilePoolProxy = contract.fromArtifact('VolatilePoolProxy');
const MockToken = contract.fromArtifact('MockToken');
const NewfiToken = contract.fromArtifact('NewfiToken');
const IERC20 = contract.fromArtifact('IERC20');

describe('NewfiAdvisor', () => {
  const [mainAdvisor, secondAdvisor, investor] = accounts;
  let divisor;
  let contract;
  let mockToken;
  let advisorToken;

  beforeEach(async () => {
    const stableProxy = await StablePoolProxy.new();
    const volatileProxy = await VolatilePoolProxy.new();

    divisor = new BN((10 ** 18).toString());
    advisorToken = await NewfiToken.new();
    mockToken = await MockToken.new();

    contract = await NewfiAdvisor.new(
      stableProxy.address,
      volatileProxy.address,
      advisorToken.address
    );

    // // Onboard a main advisor
    await contract.createAdvisor('Mock Advisor', 60, 40, {from: mainAdvisor});

    // // Onboard second advisor
    // await contract.createAdvisor('Second Advisor', 50, 50, {
    //   from: secondAdvisor,
    // });
  });

  describe('advisor contract', () => {
    it('returns advisor name', async () => {
      const name = await contract.advisorName(mainAdvisor);
      expect(name).toEqual('Mock Advisor');
    });
  });

  // describe('investors', () => {
  // beforeEach(async () => {
  //   await mockToken.mintTokens(10000, {from: investor});
  //   await mockToken.increaseAllowance(contract.address, 10000, {
  //     from: investor,
  //   });
  // });
  //
  // it('can add stable pool liquidity', async () => {
  //   const receipt = await contract.invest(
  //     mockToken.address,
  //     1000,
  //     mainAdvisor,
  //     100,
  //     0,
  //     {from: investor}
  //   );
  //   const tokens = await contract.investorStablePoolTokens(mainAdvisor, {
  //     from: investor,
  //   });
  //
  //   expect(tokens.div(divisor).toString()).toEqual('1000');
  //   expectEvent(receipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '1000',
  //     _volatileAmount: '0',
  //     _advisor: mainAdvisor,
  //   });
  // });
  //
  // it('can add volatile pool liquidity', async () => {
  //   const receipt = await contract.invest(
  //     mockToken.address,
  //     1000,
  //     mainAdvisor,
  //     0,
  //     100,
  //     {from: investor}
  //   );
  //
  //   expectEvent(receipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '0',
  //     _volatileAmount: '1000000000000000',
  //     _advisor: mainAdvisor,
  //   });
  // });
  //
  // it('can add both volatile and stable pool liquidity', async () => {
  //   const receipt = await contract.invest(
  //     mockToken.address,
  //     1000,
  //     mainAdvisor,
  //     60,
  //     40,
  //     {from: investor}
  //   );
  //
  //   expectEvent(receipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '600',
  //     _volatileAmount: '400000000000000',
  //     _advisor: mainAdvisor,
  //   });
  // });
  //
  // it('can invest eth into advisor', async () => {
  //   const receipt = await contract.invest(
  //     mockToken.address,
  //     0,
  //     mainAdvisor,
  //     0,
  //     100,
  //     {from: investor, value: ether('25')}
  //   );
  //
  //   const volatilePool = await contract.advisorVolatilePool(mainAdvisor);
  //   const balance = await web3.eth.getBalance(volatilePool);
  //
  //   expect(balance / 10 ** 18).toEqual(25);
  //   expectEvent(receipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '0',
  //     _volatileAmount: ether('25'),
  //     _advisor: mainAdvisor,
  //   });
  // });
  //
  // it('can invest more into the same advisor', async () => {
  //   await contract.invest(mockToken.address, 1000, mainAdvisor, 60, 40, {
  //     from: investor,
  //   });
  //   const receipt = await contract.invest(
  //     mockToken.address,
  //     1000,
  //     mainAdvisor,
  //     50,
  //     50,
  //     {from: investor}
  //   );
  //   const stablePoolLiquidity = await contract.investorStableLiquidity(
  //     investor
  //   );
  //   const volatileLiquidity = await contract.investorVolatileLiquidity(
  //     investor
  //   );
  //
  //   expect(stablePoolLiquidity.toString()).toEqual('1100');
  //   expect(volatileLiquidity.toString()).toEqual('900000000000000');
  //
  //   expectEvent(receipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '500',
  //     _volatileAmount: '500000000000000',
  //     _advisor: mainAdvisor,
  //   });
  // });
  //
  // it('can invest into two different advisors', async () => {
  //   const firstReceipt = await contract.invest(
  //     mockToken.address,
  //     1000,
  //     mainAdvisor,
  //     60,
  //     40,
  //     {from: investor}
  //   );
  //   const secondReceipt = await contract.invest(
  //     mockToken.address,
  //     1000,
  //     secondAdvisor,
  //     50,
  //     50,
  //     {from: investor}
  //   );
  //   const stablePoolLiquidity = await contract.investorStableLiquidity(
  //     investor
  //   );
  //   const volatileLiquidity = await contract.investorVolatileLiquidity(
  //     investor
  //   );
  //   const advisors = await contract.getAdvisors(investor);
  //
  //   expect(stablePoolLiquidity.toString()).toEqual('1100');
  //   expect(volatileLiquidity.toString()).toEqual('900000000000000');
  //   expect(advisors).toEqual([mainAdvisor, secondAdvisor]);
  //
  //   expectEvent(firstReceipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '600',
  //     _volatileAmount: '400000000000000',
  //     _advisor: mainAdvisor,
  //   });
  //   expectEvent(secondReceipt, 'Investment', {
  //     investor: investor,
  //     _stablecoinAmount: '500',
  //     _volatileAmount: '500000000000000',
  //     _advisor: secondAdvisor,
  //   });
  // });

  // it('can invest the funds into protocol', async () => {
  //     await usdcInstance.approve(contract.address, 10000000, {from : unlockAddress});
  //     let receipt = await contract.invest(
  //         usdcInstance.address,
  //         1000,
  //         mainAdvisor,
  //         0,
  //         100,
  //         { from: unlockAddress },
  //     );
  //
  //     expectEvent(receipt, 'Investment', {
  //         investor: unlockAddress,
  //         _stablecoinAmount: '0',
  //         _volatileAmount: '1000',
  //         _advisor: mainAdvisor
  //     });
  //     receipt = await contract.protocolInvestment(usdcInstance.address, {from : mainAdvisor})
  //
  //     expectEvent(receipt, 'ProtocolInvestment', {
  //         advisor: mainAdvisor,
  //         mstableShare: '0',
  //         yearnShare: '1000'
  //     });
  // });

  // it('can invest the funds into protocol and unwind the position', async () => {
  //     await usdcInstance.approve(contract.address, 10000000, {from : unlockAddress});
  //     let receipt = await contract.invest(
  //         usdcInstance.address,
  //         1000,
  //         mainAdvisor,
  //         0,
  //         100,
  //         { from: unlockAddress },
  //     );
  //
  //     expectEvent(receipt, 'Investment', {
  //         investor: unlockAddress,
  //         _stablecoinAmount: '0',
  //         _volatileAmount: '1000',
  //         _advisor: mainAdvisor
  //     });
  //     receipt = await contract.protocolInvestment(usdcInstance.address, {from : mainAdvisor})
  //
  //     expectEvent(receipt, 'ProtocolInvestment', {
  //         advisor: mainAdvisor,
  //         mstableShare: '0',
  //         yearnShare: '1000'
  //     });
  //     // advancing 1 month for yield accural
  //     await timeMachine.advanceTimeAndBlock(2592000);
  //     receipt = await contract.unwind(mainAdvisor, usdcInstance.address, {from : unlockAddress})
  // });
  // });
});
