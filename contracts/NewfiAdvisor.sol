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

contract NewfiAdvisor is Initializable, ReentrancyGuardUpgradeSafe, ProxyFactory {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event AdvisorOnBoarded(
        string name,
        address stablePool,
        address volatilePool,
        address stablePoolToken,
        address volatilePoolToken,
        uint256 mstableInvestmentProportion,
        uint256 yearnInvestmentProportion
    );

    event Investment(
        uint256 _stablecoinAmount,
        uint256 _volatileAmount,
        uint256 _ethAmount,
        address _advisor
    );

    struct Advisor {
        string name;
        address stablePool;
        address payable volatilePool;
        address stablePoolToken;
        address volatilePoolToken;
        uint256 mstableInvestmentProportion;
        uint256 yearnInvestmentProportion;
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
    address public massetAddress;

    address public savingContract;

    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
        // IMP NOTE => will the creation of advisor's pool tokens would be done already ? if yes then we can pass those addresses here also
     */
    function initialize(
        string calldata _name,
        address _stableProxyAddress,
        address _volatileProxyAddress,
        uint256 _mstableInvestmentProportion,
        uint256 _yearnInvestmentProportion
    ) external payable {
        require(advisorInfo[msg.sender].stablePool == address(0), "Advisor exists");
        require(_mstableInvestmentProportion != 0 || _yearnInvestmentProportion != 0, "Both Stable Proportions are 0");

        address stablePool = createProxyPool(_stableProxyAddress);
        address volatilePool = createProxyPool(_volatileProxyAddress);

        advisorInfo[msg.sender] = Advisor(
            _name,
            stablePool,
            address(uint160(volatilePool)),
            address(0),
            address(0),
            _mstableInvestmentProportion,
            _yearnInvestmentProportion
        );

        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, stablePool, volatilePool,  address(0),
            address(0),
            _mstableInvestmentProportion,
            _yearnInvestmentProportion);
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
    function advisorVolatilePool(address account) public view returns (address) {
        return advisorInfo[account].volatilePool;
    }

    /**
    * @dev Returns an investors stable pool liquidity.
    */
    function investorStableLiquidity(address account) public view returns (uint256) {
        return investorInfo[account].stablePoolLiquidity;
    }

    /**
    * @dev Returns an investors volatile pool liquidity.
    */
    function investorVolatileLiquidity(address account) public view returns (uint256) {
        return investorInfo[account].volatilePoolLiquidity;
    }

    /**
    * @dev Returns advisor data for an investor.
    */
    function getAdvisors(address account) public view returns (address[] memory) {
        return investorInfo[account].advisors;
    }

    /**
    * @dev Add unique advisors to a list.
    */
    function addAdvisor(address account, address advisor) internal {
        Investor storage investor = investorInfo[account];
        bool exists = false;

        for (uint i = 0; i < investor.advisors.length; i++) {
            if(advisors[i] == advisor) {
                exists = true;
            }
        }
        if(!exists) {
            investor.advisors.push(advisor);
        }
    }

    /**
        @param _proxy address of proxy.
     */
    function createProxyPool(address _proxy) internal returns (address) {
        bytes memory _payload = abi.encodeWithSignature("initialize()");
        return deployMinimal(_proxy, _payload);
    }

    // TODO: ADD BACK IN REENTRANCY
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
        uint256 stableInvest = _totalInvest * _stableProportion / 100;
        uint256 volatileInvest = _totalInvest * _volatileProportion / 100;
        uint256 ethAmount = msg.value.div(10 ** uint256(18));

        if(stableInvest > 0) {
            token.safeTransferFrom(
                msg.sender,
                advisor.stablePool,
                stableInvest
            );
        }
        if(volatileInvest > 0) {
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

        Investor storage investor = investorInfo[msg.sender];
        if (investor.doesExist) {
            investor.stablePoolLiquidity = investor.stablePoolLiquidity.add(stableInvest);
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(volatileInvest);
            addAdvisor(msg.sender, _advisor);
            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(
                stableInvest,
                volatileInvest,
                new address[](0),
                true
            );
            addAdvisor(msg.sender, _advisor);
        }
        emit Investment(
            stableInvest,
            volatileInvest,
            ethAmount,
            _advisor
        );
    }

    /**
        Advisor Investing a particular investors pool liquidity
        @param _mstableInvestmentAsset address of stablecoin to invest in mstable, will take usdc for hack.
        @param _mstableInvestmentAmount amount of stablecoin to invest in mstable.
        @param _yearnInvestmentAmounts amount array of both types of assets to be invested in yearn.
        @param _yearnVaults vault address array of both types of assets to be invested in yearn.
     */
    function protocolInvestment(
        address _mstableInvestmentAsset,
        uint256 _mstableInvestmentAmount,
        uint256[] memory _yearnInvestmentAmounts,
        address[] memory _yearnVaults
    ) public {
        Advisor storage advisor = advisorInfo[msg.sender];
        // calling the functions in proxy contract since amount is stored there so broken them into 2 different proxies
        if (_mstableInvestmentAmount > 0) {
         StablePoolProxy(advisor.stablePool).investMStable(
                massetAddress,
                _mstableInvestmentAsset,
                _mstableInvestmentAmount,
                savingContract
            );
        }
        VolatilePoolProxy(advisor.volatilePool).investYearn(
            _yearnVaults,
            _yearnInvestmentAmounts
        );
    }

    /**
        Investor Unwinding their position
        @param _advisor Address of the advisor.
        @param _vault the respective yearn vault addresses.
        @param _stablecoin address of stablecoin to invest in mstable, will take usdc for hack.
     */
    function unwind(
        address _advisor,
        address[] calldata _vault,
        address _stablecoin
    ) external {
        Investor storage investor = investorInfo[msg.sender];
        Advisor storage advisor = advisorInfo[_advisor];

        StablePoolProxy(advisor.stablePool).redeemAmount(
            msg.sender,
            _advisor,
            massetAddress,
            savingContract,
            _stablecoin,
            investor.stablePoolLiquidity,
            advisor.stablePoolToken,
            advisor.mstableInvestmentProportion
        );

        VolatilePoolProxy(advisor.volatilePool).redeemAmount(
            msg.sender,
            _advisor,
            _vault,
            _stablecoin,
            investor.stablePoolLiquidity,
            investor.volatilePoolLiquidity,
            advisor.stablePoolToken,
            advisor.volatilePoolToken,
            advisor.yearnInvestmentProportion
        );
    }
}
