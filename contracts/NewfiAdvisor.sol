pragma solidity ^0.6.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "./utils/ProxyFactory.sol";

contract Helper {
    /**
     * @dev get yearn vault address
     */
    function getETHVault() public pure returns (address ethVault) {
        ethVault = 0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7;
    }
}

interface YearnController {
    function withdraw(address, uint) external;
    function balanceOf(address) external view returns (uint);
    function earn(address, uint) external;
}

// NOTE - Was getting a file import issue so placed the interfaces here only for now
// Yearn Interface
interface YearnVault {
    // deposit for stable coins
    function deposit(uint256 _amount) external;

    function depositETH() external payable;

    function withdrawETH(uint256 _shares) external payable;

    function withdraw(uint256 _shares) external;

    function balanceOf(address account) external view returns (uint256);

    function balance() external view returns (uint);

    function totalSupply() external view returns (uint256);

    function controller() external view returns (address);

    function token() external view returns (address);

    function getPricePerFullShare() external view returns (uint);
}

// would be a 2 step although all in 1 tx
// for generating yield
// 1. deposit usdc to Masset Contract
// 2. deposit received musd to saving contract
// for unwinding
// 1. withdraw from savings contract
// 2. withdraw the recieved musd from masset contract
interface MAsset {
    function mint(address _bAsset, uint256 _bAssetQuanity)
        external
        returns (uint256 massetMinted);

    function redeem(address _bAsset, uint256 _bAssetQuanity)
        external
        returns (uint256 massetRedeemed);
}

interface SavingsContract {
    function depositSavings(uint256 _amount)
        external
        returns (uint256 creditsIssued);
    function creditBalances(address _user) external view returns (uint256);

    function redeem(uint256 _credits) external returns (uint256 massetReturned);

    function exchangeRate() external view returns (uint256);
}

contract StablePoolProxy is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);


    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    function investMStable(
        address _mAsset,
        address _bAsset,
        uint256 _amount,
        address _savings
        ) external {
        uint256 mAsset = MAsset(_mAsset).mint(_bAsset, _amount);
        SavingsContract(_savings).depositSavings(mAsset);
    }

    function redeemAmount(
        address _investor,
        address _advisor,
        address _mAsset,
        address _savings,
        address _stablecoin,
        uint256 _investorStablePoolLiquidity,
        address advisorStablePoolToken,
        uint256 mstableAdvisorProportion
    ) external {
        uint256 poolValue = SavingsContract(_savings).creditBalances(address(this)).mul(SavingsContract(_savings).exchangeRate());
        uint256 poolTokenSupply = IERC20(advisorStablePoolToken).totalSupply();
        uint256 poolTokenPrice = poolValue.div(poolTokenSupply);
        uint256 investorMstableLiquidity = _investorStablePoolLiquidity.mul(mstableAdvisorProportion).div(100);
        uint256 investorTotalReturns = investorMstableLiquidity.mul(poolTokenPrice);
        uint256 mAssetAmount = SavingsContract(_savings).redeem(
            investorTotalReturns
        );
        investorTotalReturns = MAsset(_mAsset).redeem(
            _stablecoin,
            mAssetAmount
        );
        // 1 % per investor
        uint256 advisorFee = (investorTotalReturns.mul(1)).div(100);
        investorTotalReturns = investorTotalReturns.sub(advisorFee);
        IERC20(_stablecoin).safeTransfer(_advisor, advisorFee);
        IERC20(_stablecoin).safeTransfer(_investor, investorTotalReturns);
    }
}

contract VolatilePoolProxy is Initializable, OwnableUpgradeSafe, Helper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    function investYearn(
        address[] memory yearnVault,
        uint256[] memory _amount
        ) external {
        require(
            yearnVault.length == _amount.length,
            "Sanity Check: Yearn Vault"
        );
        for (uint256 i = 0; i < _amount.length; i++) {
            if (yearnVault[i] == getETHVault()) {
                YearnVault(yearnVault[i]).depositETH{value: _amount[i]}();
            } else {
                // since having stable amount for yearn is not mandatory
                if (_amount[i] > 0) {
                    YearnVault(yearnVault[i]).deposit(_amount[1]);
                }
            }
        }
    }

    function redeemAmount(
        address _investor,
        address _advisor,
        address[] calldata _vault,
        address _stablecoin,
        uint256 _investorStablePoolLiquidity,
        uint256 _investorVolatilePoolLiquidity,
        address advisorStablePoolToken,
        address advisorVolatilePoolToken,
        uint256 yearnAdvisorProportion
    ) external {
        for (uint256 i = 0; i < _vault.length; i++) {
            // had to reduce vars due to sol stack too deep error
            if (_vault[i] == getETHVault()) {
                uint256 poolTokenPrice = YearnVault(_vault[i]).balanceOf(address(this)).div(IERC20(advisorVolatilePoolToken).totalSupply());
                uint256 investorRedeemAmount = _investorVolatilePoolLiquidity.mul(poolTokenPrice);
                YearnVault(_vault[i]).withdrawETH(investorRedeemAmount);
                uint256 investorReturns = getInvestorReturnAmount(_vault[i], investorRedeemAmount);
                // 1 % per investor
                uint256 advisorFee = (investorReturns.mul(1)).div(100);
                investorReturns = investorReturns.sub(advisorFee);
                (bool ethTransferCheck, ) = _advisor.call{
                    value: advisorFee
                }("");
                require(ethTransferCheck, "Advisor Transfer failed.");
                (ethTransferCheck, ) = _investor.call{
                    value: investorReturns
                }("");
                require(ethTransferCheck, "Investor Transfer failed.");
                // transfer eth to both
            } else {
                uint256 investorYearnLiquidity = _investorStablePoolLiquidity.mul(yearnAdvisorProportion).div(100);
                uint256 investorRedeemAmount = investorYearnLiquidity.mul(YearnVault(_vault[i]).balanceOf(address(this)).div(IERC20(advisorStablePoolToken).totalSupply()));
                YearnVault(_vault[i]).withdraw(investorRedeemAmount);
                uint256 investorReturns = getInvestorReturnAmount(_vault[i], investorRedeemAmount);
                // 1 % per investor
                uint256 advisorFee = (investorReturns.mul(1)).div(100);
                investorReturns = investorReturns.sub(advisorFee);
                IERC20(_stablecoin).safeTransfer(_advisor, advisorFee);
                IERC20(_stablecoin).safeTransfer(
                    _investor,
                    investorReturns
                );
            }
        }
    }

    function getInvestorReturnAmount(address _vault, uint256 _investorRedeemAmount) internal returns(uint256) {
 address controller = YearnVault(_vault).controller();
                address token = YearnVault(_vault).token();
                uint investorReturns = (YearnVault(_vault).balance().mul(_investorRedeemAmount)).div(YearnVault(_vault).totalSupply());

        // Check balance
        uint b = IERC20(token).balanceOf(address(this));
        if (b < investorReturns) {
            uint _withdraw = investorReturns.sub(b);
            YearnController(controller).withdraw(address(token), _withdraw);
            uint _after = IERC20(token).balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                investorReturns = investorReturns.add(_diff);
            }
        }
        return investorReturns;
    }

    receive() external payable {}
}

contract NewfiAdvisor is ReentrancyGuardUpgradeSafe, ProxyFactory {
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
        address advisor;
        bool status;
    }

    mapping(address => Advisor) public advisorInfo;

    mapping(address => Investor) public investorInfo;

    address[] public advisors;

    address[] public investors;

    address public stableProxyBaseAddress;

    address payable public volatileProxyBaseAddress;
    // Since it will be fixed
    address public massetAddress;

    address public savingContract;

    /**
        Constructor
        @param _stableproxy address of stable proxy contract.
        @param _volatileproxy address of volatile proxy contract.
        @param _massetAddress address of the masset.
        @param _savingsContract address of the saving contract.
     */
    constructor(
        address _stableproxy,
        address payable _volatileproxy,
        address _massetAddress,
        address _savingsContract
    ) public {
        stableProxyBaseAddress = _stableproxy;
        volatileProxyBaseAddress = _volatileproxy;
        massetAddress = _massetAddress;
        savingContract = _savingsContract;
    }

    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
        // IMP NOTE => will the creation of advisor's pool tokens would be done already ? if yes then we can pass those addresses here also
     */
    function onboard(string calldata _name, uint256 _stableCoinAmount, address _stablecoin, uint256 _mstableInvestmentProportion, uint256 _yearnInvestmentProportion) external payable {
        // Creating two pool proxies back to back
        require(advisorInfo[msg.sender].stablePool == address(0), "Advsior exists");
        require(_mstableInvestmentProportion != 0 || _yearnInvestmentProportion != 0, "Both Stable Proportions are 0");
        address stablePool = createStableProxy(msg.sender);
        address volatilePool = createVolatileProxy(msg.sender);
        if (_stableCoinAmount > 0) {
            IERC20(_stablecoin).safeTransferFrom(
            address(this),
            stablePool,
            _stableCoinAmount
        );
        }
        if (msg.value > 0) {
        (bool success, ) = volatilePool.call{value: msg.value}("");
        require(success, "Transfer failed.");
        }
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
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _stablecoinAmount amount of stable coin.
        @param _advisor address of selected advisor.
        @param _stableProportion stable coin proportion used to invest in protocols.
        @param _volatileProportion stable coin proportion used to invest in protocols.
        // IMP NOTE => stablePoolLiquidity & volatilePoolLiquidity would be the bal of the pool tokens that the investor recieves currently just storing the deposited value
     */
    function invest(
        address _stablecoin,
        uint256 _stablecoinAmount,
        address _advisor,
        uint256 _stableProportion,
        uint256 _volatileProportion
    ) external payable nonReentrant {
        require(
            _stableProportion != 0 || _volatileProportion != 0,
            "Both proportions are 0"
        );
        Advisor storage advisor = advisorInfo[_advisor];
        IERC20(_stablecoin).safeTransferFrom(
            address(this),
            advisor.stablePool,
            _stablecoinAmount
        );
        // assuming usdc and eth for hack
        (bool success, ) = advisor.volatilePool.call{value: msg.value}("");
        require(success, "Transfer failed.");
        Investor storage investor = investorInfo[msg.sender];

        if (investor.status) {
            investor.stablePoolLiquidity = investor.stablePoolLiquidity.add(
                investor.stablePoolLiquidity
            );
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(
                msg.value
            );
            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(
                _stablecoinAmount,
                msg.value,
                _advisor,
                true
            );
        }
        emit Investment(
            _stablecoinAmount,
            msg.value,
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

    /**
        @param _advisor Address of the Advisor.
     */
    function createStableProxy(address _advisor) internal returns (address) {
        bytes memory _payload = abi.encodeWithSignature(
            "initialize(address)",
            _advisor
        );
        // Deploy proxy
        // for testing the address of the proxy contract which will
        // be used to redirect interest will come here
        address _intermediate = deployMinimal(stableProxyBaseAddress, _payload);
        return _intermediate;
    }

    /**
        @param _advisor Address of the Advisor.
     */
    function createVolatileProxy(address _advisor) internal returns (address) {
        bytes memory _payload = abi.encodeWithSignature(
            "initialize(address)",
            _advisor
        );
        // Deploy proxy
        // for testing the address of the proxy contract which will
        // be used to redirect interest will come here
        address _intermediate = deployMinimal(
            volatileProxyBaseAddress,
            _payload
        );
        return _intermediate;
    }
}
