// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "./proxy/StablePoolProxy.sol";
import "./proxy/VolatilePoolProxy.sol";
import "./utils/ProxyFactory.sol";
import "./utils/AggregatorInterface.sol";

contract NewfiAdvisor is
    Initializable,
    ReentrancyGuardUpgradeSafe,
    ProxyFactory,
    Helper
{
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

    address[] public investors;

    // Since it will be fixed
    // in order to be used in the test cases
    address
        public constant massetAddress = 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;

    address
        public constant savingContract = 0xcf3F73290803Fc04425BEE135a4Caeb2BaB2C2A1;
    // usdc/eth aggregator
    address
        internal constant fiatRef = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;

    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
        // IMP NOTE => will the creation of advisor's pool tokens would be done already ? if yes then we can pass those addresses here also
        // Advisor will define their stratergy as well with the _mstableInvestmentProportion and _yearnInvestmentProportion
     */
    function initialize(
        string calldata _name,
        address _stableProxyAddress,
        address _volatileProxyAddress,
        // for volatile pool since volatile pool will be used for yearn investment
        uint256 _volatileProtocolStableCoinProportion,
        uint256 _volatileProtocolVolatileCoinProportion
    ) external payable {
        require(
            advisorInfo[msg.sender].stablePool == address(0),
            "Advisor exists"
        );
        require(
            _volatileProtocolStableCoinProportion != 0 ||
                _volatileProtocolVolatileCoinProportion != 0,
            "Both Stable Proportions are 0"
        );
        // msg.sender here would eb the advisor address
        address stablePool = createProxyPool(_stableProxyAddress, msg.sender);
        address volatilePool = createProxyPool(_volatileProxyAddress, msg.sender);

        advisorInfo[msg.sender] = Advisor(
            _name,
            stablePool,
            address(uint160(volatilePool)),
            address(0),
            address(0),
            _volatileProtocolStableCoinProportion,
            _volatileProtocolVolatileCoinProportion
        );

        advisors.push(msg.sender);
        emit AdvisorOnBoarded(
            msg.sender,
            _name,
            stablePool,
            volatilePool,
            address(0),
            address(0),
            _volatileProtocolStableCoinProportion,
            _volatileProtocolVolatileCoinProportion
        );
    }

    // IMP NOTE -> Right now these function will only give the pool value for the assets locked in mstable and yearn we can then get the total value in graph if needed we can tweak these functions to get the pool value of locked and unlocked assets direclty
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
        // whitelisted vault addresses for now
        uint256 yearnPoolInvestmentValue = YearnVault(getUSDCVault())
            .balanceOf(advisor.volatilePool)
            .mul(YearnVault(getUSDCVault()).getPricePerFullShare());
        return mstablePoolInvestmentValue.add(yearnPoolInvestmentValue);
    }

    function getVolatilePoolValue(address _advisor)
        public
        view
        returns (uint256)
    {
        Advisor storage advisor = advisorInfo[_advisor];
        // whitelisted vault addresses for now
        return
            YearnVault(getETHVault()).balanceOf(advisor.volatilePool).mul(
                YearnVault(getETHVault()).getPricePerFullShare()
            );
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

        for (uint i = 0; i < investor.advisors.length; i++) {
            if (advisors[i] == advisor) {
                exists = true;
            }
        }
        if (!exists) {
            investor.advisors.push(advisor);
        }
    }

    /**
        @param _proxy address of proxy.
     */
    function createProxyPool(address _proxy, address _advisor) internal returns (address) {
        bytes memory _payload = abi.encodeWithSignature("initialize(address)", _advisor);
        return deployMinimal(_proxy, _payload);
    }

    /**
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _totalInvest amount of stable coin.
        @param _advisor address of selected advisor.
        @param _stableProportion stable coin proportion used to invest in protocols.
        @param _volatileProportion stable coin proportion used to invest in protocols.
        // IMP NOTE => stablePoolLiquidity & volatilePoolLiquidity would be the bal of the pool tokens that the investor recieves currently just storing the deposited value
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
            "Need to invest 100% of funds"
        );
        Advisor storage advisor = advisorInfo[_advisor];
        IERC20 token = IERC20(_stablecoin);
        uint256 stableInvest = (_totalInvest * _stableProportion) / 100;
        uint256 volatileInvest = (_totalInvest * _volatileProportion) / 100;

        if (stableInvest > 0) {
            token.safeTransferFrom(
                msg.sender,
                advisor.stablePool,
                stableInvest
            );
        }
        if (volatileInvest > 0) {
            token.safeTransferFrom(
                msg.sender,
                advisor.volatilePool,
                volatileInvest
            );
        }
        if (msg.value > 0) {
            (bool success, ) = advisor.volatilePool.call{value: msg.value}("");
            require(success, "Transfer failed.");
        }
        // converting to wei 10**18
        volatileInvest = volatileInvest.mul(10**12);
        // getting the total amount in volatile pool
        uint256 volatilePoolAmount = volatileInvest.add(msg.value);

        Investor storage investor = investorInfo[msg.sender];
        if (investor.doesExist) {
            investor.stablePoolLiquidity = investor.stablePoolLiquidity.add(
                stableInvest
            );
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(
                volatilePoolAmount
            );
            addAdvisor(msg.sender, _advisor);
            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(
                stableInvest,
                volatilePoolAmount,
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
        uint256 volatileProtocolVolatileCoinInvestmentAmount = advisor
            .volatilePool
            .balance;
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
            volatileProtocolStableCoinInvestmentAmount,
            volatileProtocolVolatileCoinInvestmentAmount
        );
        uint256 totalAmount = volatileProtocolStableCoinInvestmentAmount.add(
            volatileProtocolVolatileCoinInvestmentAmount
        );
        emit ProtocolInvestment(
            msg.sender,
            stableProtocolInvestmentAmount,
            totalAmount
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
