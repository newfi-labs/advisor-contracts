// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import './proxy/StablePoolProxy.sol';
import './proxy/VolatilePoolProxy.sol';
import './utils/ProxyFactory.sol';
import './utils/AggregatorInterface.sol';
import './NewfiToken.sol';

contract NewfiAdvisor is ReentrancyGuardUpgradeSafe, ProxyFactory, Helper {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event AdvisorOnBoarded(
        address indexed advisor,
        string name,
        address indexed stablePool,
        address indexed volatilePool,
        address stablePoolToken,
        address volatilePoolToken,
        uint256 volatileProtocolStableCoinProportion,
        uint256 volatileProtocolVolatileCoinProportion
    );

    event Investment(
        address indexed investor,
        uint256 _stablecoinAmount,
        uint256 _volatileAmount,
        address indexed _advisor
    );

    event ProtocolInvestment(
        address indexed advisor,
        uint256 mstableShare,
        uint256 yearnShare
    );

    event Unwind(address indexed advisor, uint256 fess);

    struct Advisor {
        string name;
        address stablePool;
        address payable volatilePool;
        address stablePoolToken;
        address volatilePoolToken;
        // diffrentiated for stable coins
        uint256 volatileProtocolStableCoinProportion;
        uint256 volatileProtocolVolatileCoinProportion;
    }

    struct Investor {
        uint256 stablePoolLiquidity;
        uint256 volatilePoolLiquidity;
        address[] advisors;
        bool doesExist;
    }

    mapping(address => Advisor) private advisorInfo;

    mapping(address => Investor) private investorInfo;

    address[] public advisors;

    address[] public advisorTokens;

    address[] public investors;

    // Since it will be fixed
    // in order to be used in the test cases
    address
        public constant massetAddress = 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;

    address
        public constant savingContract = 0xcf3F73290803Fc04425BEE135a4Caeb2BaB2C2A1;
    // usd/eth aggregator
    address
        internal constant fiatRef = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address public stablePoolProxy;
    address public volatilePoolProxy;
    address public advisorToken;

    /**
        Constructor
        @param _stablePool Address of the proxy contract defined above to create clones.
    */
    constructor(
        address _stablePool,
        address _volatilePool,
        address _token
    ) public {
        stablePoolProxy = _stablePool;
        volatilePoolProxy = _volatilePool;
        advisorToken = _token;
    }

    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
     */
    function createAdvisor(
        string calldata _name,
        // for volatile pool since volatile pool will be used for yearn investment
        uint256 _volatileProtocolStableCoinProportion,
        uint256 _volatileProtocolVolatileCoinProportion
    ) external payable {
        require(
            advisorInfo[msg.sender].stablePool == address(0),
            'Advisor exists'
        );
        require(
            _volatileProtocolStableCoinProportion != 0 ||
                _volatileProtocolVolatileCoinProportion != 0,
            'Both Stable Proportions are 0'
        );
        // msg.sender here would eb the advisor address
        address stablePool = createProxyPool(stablePoolProxy, msg.sender);
        address volatilePool = createProxyPool(volatilePoolProxy, msg.sender);
        address stablePoolToken = createPoolToken(
            string(abi.encodePacked(_name, 'NewfiStableToken')),
            'NST',
            msg.sender
        );
        address volatilePoolToken = createPoolToken(
            string(abi.encodePacked(_name, 'NewfiVolatileToken')),
            'NVT',
            msg.sender
        );

        advisorInfo[msg.sender] = Advisor(
            _name,
            stablePool,
            address(uint160(volatilePool)),
            stablePoolToken,
            volatilePoolToken,
            _volatileProtocolStableCoinProportion,
            _volatileProtocolVolatileCoinProportion
        );

        advisors.push(msg.sender);
        emit AdvisorOnBoarded(
            msg.sender,
            _name,
            stablePoolProxy,
            volatilePoolProxy,
            stablePoolToken,
            volatilePoolToken,
            _volatileProtocolStableCoinProportion,
            _volatileProtocolVolatileCoinProportion
        );
    }

    function getStablePoolValue(address _advisor)
        public
        view
        returns (uint256)
    {
        Advisor storage advisor = advisorInfo[_advisor];
        address stablePool = advisor.stablePool;
        uint256 mstablePoolInvestmentValue = SavingsContract(savingContract)
            .creditBalances(stablePool)
            .mul(SavingsContract(savingContract).exchangeRate());
        return mstablePoolInvestmentValue;
    }

    function getVolatilePoolValue(address _advisor)
        public
        view
        returns (uint256)
    {
        Advisor storage advisor = advisorInfo[_advisor];
        uint256 yearnPoolStableCoinInvestmentValue = YearnVault(getUSDCVault())
            .balanceOf(advisor.volatilePool)
            .mul(YearnVault(getUSDCVault()).getPricePerFullShare());
        yearnPoolStableCoinInvestmentValue.mul(10**12);

        // converting int256 to uint256
        uint256 usdQuote = uint256(AggregatorInterface(fiatRef).latestAnswer());
        uint256 ethPoolValue = advisor.volatilePool.balance.mul(usdQuote);
        return yearnPoolStableCoinInvestmentValue.add(ethPoolValue);
    }

    /**
     * @dev Returns the name of the advisor.
     */
    function advisorName(address account) public view returns (string memory) {
        return advisorInfo[account].name;
    }

    /**
     * @dev Returns the address of an advisors volatile pool.
     */
    function advisorVolatilePool(address account)
        public
        view
        returns (address)
    {
        return advisorInfo[account].volatilePool;
    }

    /**
     * @dev Returns an investors stable pool liquidity.
     */
    function investorStableLiquidity(address account)
        public
        view
        returns (uint256)
    {
        return investorInfo[account].stablePoolLiquidity;
    }

    /**
     * @dev Returns an investors stable pool token balance.
     */
    function investorStablePoolTokens(address _advisor)
        public
        view
        returns (uint256)
    {
        Advisor storage advisor = advisorInfo[_advisor];
        return NewfiToken(advisor.stablePoolToken).balanceOf(msg.sender);
    }

    /**
     * @dev Returns an investors volatile pool liquidity.
     */
    function investorVolatileLiquidity(address account)
        public
        view
        returns (uint256)
    {
        return investorInfo[account].volatilePoolLiquidity;
    }

    /**
     * @dev Returns advisor data for an investor.
     */
    function getAdvisors(address account)
        public
        view
        returns (address[] memory)
    {
        return investorInfo[account].advisors;
    }

    /**
     * @dev Add unique advisors to a list.
     */
    function addAdvisor(address account, address advisor) internal {
        Investor storage investor = investorInfo[account];
        bool exists = false;

        for (uint256 i = 0; i < investor.advisors.length; i++) {
            if (advisors[i] == advisor) {
                exists = true;
            }
        }
        if (!exists) {
            investor.advisors.push(advisor);
        }
    }

    /**
        Create an advisors proxy pool
        @param _proxy address of proxy.
        @param _advisor address of advisor.
     */
    function createProxyPool(address _proxy, address _advisor)
        internal
        returns (address)
    {
        bytes memory _payload = abi.encodeWithSignature(
            'initialize(address)',
            _advisor
        );
        return deployMinimal(_proxy, _payload);
    }

    /**
        Create an advisors token
        @param _name of token.
        @param _symbol of token.
        @param _advisor address of advisor.
     */
    function createPoolToken(
        string memory _name,
        string memory _symbol,
        address _advisor
    ) internal returns (address) {
        bytes memory payload = abi.encodeWithSignature(
            'initialize(string,string)',
            _name,
            _symbol,
            _advisor
        );
        address token = deployMinimal(advisorToken, payload);
        advisorTokens.push(token);

        return token;
    }

    /**
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _totalInvest amount of stable coin.
        @param _advisor address of selected advisor.
        @param _stableProportion stable coin proportion used to invest in protocols.
        @param _volatileProportion stable coin proportion used to invest in protocols.
     */
    function invest(
        address _stablecoin,
        uint256 _totalInvest,
        address _advisor,
        uint256 _stableProportion,
        uint256 _volatileProportion
    ) external payable {
        require(
            _stableProportion + _volatileProportion == 100,
            'Need to invest 100% of funds'
        );
        Advisor storage advisor = advisorInfo[_advisor];
        IERC20 token = IERC20(_stablecoin);
        NewfiToken newfiStableToken = NewfiToken(advisor.stablePoolToken);
        NewfiToken newfiVolatileToken = NewfiToken(advisor.volatilePoolToken);

        uint256 stableInvest = (_totalInvest.mul(_stableProportion)).div(100);
        uint256 volatileInvest = (_totalInvest.mul(_volatileProportion)).div(
            100
        );
        uint256 mintedVolatilePoolToken;
        uint256 mintedStablePoolToken;
        if (stableInvest > 0) {
            uint256 stablePoolTokenPrice;
            if (getStablePoolValue(_advisor) > 0) {
                // calculating  P i.e price of the token
                stablePoolTokenPrice = getStablePoolValue(_advisor).div(
                    newfiStableToken.totalSupply()
                );
            } else {
                stablePoolTokenPrice = 0;
            }
            // converting usdc to wei since pool token is of 18 decimals
            mintedStablePoolToken = stableInvest.mul(10**12);

            newfiStableToken.mintOwnershipTokens(
                msg.sender,
                stablePoolTokenPrice,
                mintedStablePoolToken
            );
            token.safeTransferFrom(
                msg.sender,
                advisor.stablePool,
                stableInvest
            );
        }
        if (volatileInvest > 0) {
            uint256 volatilePoolTokenPrice;
            if (getVolatilePoolValue(_advisor) > 0) {
                // calculating  P i.e price of the token
                volatilePoolTokenPrice = getVolatilePoolValue(_advisor).div(
                    newfiVolatileToken.totalSupply()
                );
            } else {
                volatilePoolTokenPrice = 0;
            }
            mintedVolatilePoolToken = volatileInvest.mul(10**12);

            newfiVolatileToken.mintOwnershipTokens(
                msg.sender,
                volatilePoolTokenPrice,
                mintedVolatilePoolToken.add(msg.value)
            );
            token.safeTransferFrom(
                msg.sender,
                advisor.volatilePool,
                volatileInvest
            );
        }
        if (msg.value > 0) {
            (bool success, ) = advisor.volatilePool.call{value: msg.value}('');
            require(success, 'Transfer failed.');
        }
        // converting to wei 10**18
        volatileInvest = volatileInvest.mul(10**12);
        // getting the total amount in volatile pool
        uint256 volatilePoolAmount = volatileInvest.add(msg.value);

        Investor storage investor = investorInfo[msg.sender];
        if (investor.doesExist) {
            investor.stablePoolLiquidity = investor.stablePoolLiquidity.add(
                mintedStablePoolToken
            );
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(
                mintedVolatilePoolToken
            );
            addAdvisor(msg.sender, _advisor);

            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(
                mintedStablePoolToken,
                mintedVolatilePoolToken,
                new address[](0),
                true
            );
            addAdvisor(msg.sender, _advisor);
        }

        emit Investment(msg.sender, stableInvest, volatilePoolAmount, _advisor);
    }

    /**
        Advisor Investing a particular investors pool liquidity
        @param _stablecoin address of stablecoin to invest in mstable, will take usdc for hack.
        // IMP NOTE => _mstableInvestmentAmount & _yearnInvestmentAmountsw will be based on the advisors mstable and yearn proportions
     */
    function protocolInvestment(address _stablecoin) external {
        Advisor storage advisor = advisorInfo[msg.sender];
        IERC20 token = IERC20(_stablecoin);
        uint256 stableProtocolInvestmentAmount = token.balanceOf(
            advisor.stablePool
        );
        uint256 volatileProtocolStableCoinInvestmentAmount = token.balanceOf(
            advisor.volatilePool
        );
        // eth bal
        // uint256 volatileProtocolVolatileCoinInvestmentAmount = advisor
        //     .volatilePool
        //     .balance;
        // calling the functions in proxy contract since amount is stored there so broken them into 2 different proxies
        if (stableProtocolInvestmentAmount > 0) {
            StablePoolProxy(advisor.stablePool).investMStable(
                massetAddress,
                _stablecoin,
                stableProtocolInvestmentAmount,
                savingContract
            );
        }
        VolatilePoolProxy(advisor.volatilePool).investYearn(
            volatileProtocolStableCoinInvestmentAmount
            // volatileProtocolVolatileCoinInvestmentAmount
        );
        // uint256 totalAmount = volatileProtocolStableCoinInvestmentAmount.add(
        //     volatileProtocolVolatileCoinInvestmentAmount
        //);
        emit ProtocolInvestment(
            msg.sender,
            stableProtocolInvestmentAmount,
            volatileProtocolStableCoinInvestmentAmount
        );
    }

    /**
        Investor Unwinding their position
        @param _advisor Address of the advisor.
        @param _stablecoin address of stablecoin to invest in mstable, will take usdc for hack.
     */
    function unwind(address _advisor, address _stablecoin) external {
        Investor storage investor = investorInfo[msg.sender];
        Advisor storage advisor = advisorInfo[_advisor];

        uint256 advisorStablePoolFees = StablePoolProxy(advisor.stablePool)
            .redeemAmount(
            msg.sender,
            _advisor,
            massetAddress,
            savingContract,
            _stablecoin,
            investor.stablePoolLiquidity,
            advisor.stablePoolToken
        );

        uint256 advisorVolatilePoolFees = VolatilePoolProxy(
            advisor
                .volatilePool
        )
            .redeemAmount(
            msg.sender,
            _advisor,
            _stablecoin,
            investor.volatilePoolLiquidity,
            advisor.volatilePoolToken,
            advisor.volatileProtocolStableCoinProportion,
            advisor.volatileProtocolVolatileCoinProportion
        );
        emit Unwind(
            _advisor,
            advisorStablePoolFees.add(advisorVolatilePoolFees)
        );
    }
}
