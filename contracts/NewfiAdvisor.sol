pragma solidity ^0.6.2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "./utils/ProxyFactory.sol";
import "./utils/OwnableUpgradeSafe.sol";

contract Helper {
    /**
     * @dev get yearn vault address
     */
    function getETHVault() public pure returns (address ethVault) {
        ethVault = 0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7;
    }
}

// NOTE - Was getting a file import issue so placed the interfaces here only for now
// Yearn Interface
interface YearnVault {
    // deposit for stable coins
    function deposit(uint256 _amount) external;

    function depositETH() external payable;

    function withdrawETH(uint256 _shares) external payable;

    function withdraw(uint256 _shares) external;
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

    function redeem(uint256 _credits) external returns (uint256 massetReturned);

    function exchangeRate() external view returns (uint256);
}

contract StablePoolProxy is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);

    struct Investment {
        uint256 amount;
        uint256 depositTime;
    }

    mapping(address => Investment) public investmentTracker;

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    function investMStable(
        address _mAsset,
        address _bAsset,
        uint256 _amount,
        address _savings,
        address _investor
    ) external {
        uint256 mAsset = MAsset(_mAsset).mint(_bAsset, _amount);
        Investment storage investments = investmentTracker[_investor];
        investments.amount = investments.amount.add(_amount);
        investments.depositTime = now;
        SavingsContract(_savings).depositSavings(mAsset);
    }

    function redeemAmount(
        address _investor,
        address _advisor,
        address _mAsset,
        address _savings,
        address _stablecoin
    ) external {
        Investment storage investments = investmentTracker[_investor];
        require(investments.amount > 0, "No Investment Amount");
        uint256 amountLockInDuration = now.sub(investments.depositTime);
        uint256 exchangeRate = SavingsContract(_savings).exchangeRate();
        uint256 investorAccuringExchangeRate = (
            exchangeRate.mul(amountLockInDuration)
        )
            .div(86400);
        uint256 investorCreditBalance = investments.amount.mul(
            investorAccuringExchangeRate
        );
        uint256 mAssetAmount = SavingsContract(_savings).redeem(
            investorCreditBalance
        );
        uint256 investorNetRedeemAmount = MAsset(_mAsset).redeem(
            _stablecoin,
            mAssetAmount
        );
        // 1 % per investor
        uint256 advisorFee = (investorNetRedeemAmount.mul(1)).div(100);
        investorNetRedeemAmount = investorNetRedeemAmount.sub(advisorFee);
        IERC20(_stablecoin).safeTransfer(_advisor, advisorFee);
        IERC20(_stablecoin).safeTransfer(_investor, investorNetRedeemAmount);
    }
}

contract VolatilePoolProxy is Initializable, OwnableUpgradeSafe, Helper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);
    // Since with yearn you can onvest in both categories
    struct Investment {
        uint256 stableAmount;
        uint256 volatileAmount;
        uint256 stableCoinDepositTime;
        uint256 volatileCoinDepositTime;
    }

    mapping(address => Investment) public investmentTracker;

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    function investYearn(
        address[] memory yearnVault,
        uint256[] memory _amount,
        address _investor
    ) external {
        require(
            yearnVault.length == _amount.length,
            "Sanity Check: Yearn Vault"
        );
        Investment storage investments = investmentTracker[_investor];
        for (uint256 i = 0; i < _amount.length; i++) {
            investments.stableAmount = investments.stableAmount.add(_amount[i]);
            if (yearnVault[i] == getETHVault()) {
                investments.volatileAmount = investments.volatileAmount.add(
                    _amount[i]
                );
                investments.stableCoinDepositTime = now;
                YearnVault(yearnVault[i]).depositETH{value: _amount[i]}();
            } else {
                // since having stable amount for yearn is not mandatory
                if (_amount[i] > 0) {
                    investments.volatileCoinDepositTime = now;
                    YearnVault(yearnVault[i]).deposit(_amount[1]);
                }
            }
        }
    }

    function redeemAmount(
        address _investor,
        address _advisor,
        uint256[] calldata _roi,
        address[] calldata _vault,
        address _stablecoin
    ) external {
        Investment storage investments = investmentTracker[_investor];
        for (uint256 i = 0; i < _vault.length; i++) {
            if (_vault[i] == getETHVault()) {
                uint256 volatileLockInDuration = now.sub(
                    investments.volatileCoinDepositTime
                );
                // 86400 * 365 = 31536000 since roi is year based
                uint256 volatileAccuredRate = _roi[i]
                    .mul(volatileLockInDuration)
                    .div(31536000);
                uint256 investorAccureAmount = investments.volatileAmount.add(
                    (
                        investments.volatileAmount.mul(volatileAccuredRate).div(
                            100
                        )
                    )
                );
                YearnVault(_vault[i]).withdrawETH(investorAccureAmount);
                // 1 % per investor
                uint256 advisorFee = (investorAccureAmount.mul(1)).div(100);
                investorAccureAmount = investorAccureAmount.sub(advisorFee);
                (bool advisorTransferCheck, ) = _advisor.call{
                    value: advisorFee
                }("");
                require(advisorTransferCheck, "Advisor Transfer failed.");
                (bool investorTransferCheck, ) = _investor.call{
                    value: investorAccureAmount
                }("");
                require(investorTransferCheck, "Investor Transfer failed.");
                // transfer eth to both
            } else {
                uint256 stableLockInDuration = now.sub(
                    investments.stableCoinDepositTime
                );
                // 86400 * 365 = 31536000 since roi is year based
                uint256 stableAccuredRate = _roi[i]
                    .mul(stableLockInDuration)
                    .div(31536000);
                uint256 investorAccureAmount = investments.stableAmount.add(
                    (investments.stableAmount.mul(stableAccuredRate).div(100))
                );
                YearnVault(_vault[i]).withdraw(investorAccureAmount);
                // 1 % per investor
                uint256 advisorFee = (investorAccureAmount.mul(1)).div(100);
                investorAccureAmount = investorAccureAmount.sub(advisorFee);
                IERC20(_stablecoin).safeTransfer(_advisor, advisorFee);
                IERC20(_stablecoin).safeTransfer(
                    _investor,
                    investorAccureAmount
                );
            }
        }
    }

    receive() external payable {}
}

contract NewfiAdvisor is ReentrancyGuardUpgradeSafe, ProxyFactory {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event AdvisorOnBoarded(
        string name,
        address stablePool,
        address volatilePool
    );

    event Investment(
        uint256 _stablecoinAmount,
        address _advisor,
        uint256 _stableProportion,
        uint256 _volatileProportion
    );

    struct Advisor {
        string name;
        address stablePool;
        address payable volatilePool;
    }

    struct Investor {
        uint256 stablePoolLiquidity;
        uint256 volatilePoolLiquidity;
        uint256 poolTokenBalance;
        uint256 stablePoolProportion;
        uint256 volatilePoolProportion;
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
     */
    function onboard(string calldata _name) external {
        // TCreating two pool proxies back to back
        address stablePool = createStableProxy(msg.sender);
        address volatilePool = createVolatileProxy(msg.sender);
        advisorInfo[msg.sender] = Advisor(
            _name,
            stablePool,
            address(uint160(volatilePool))
        );
        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, stablePool, volatilePool);
    }

    /**
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _stablecoinAmount amount of stable coin.
        @param _advisor address of selected advisor.
        @param _stableProportion stable coin proportion used to invest in protocols.
        @param _volatileProportion stable coin proportion used to invest in protocols.
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
            "Both propotions are 0"
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
                _stablecoinAmount
            );
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(
                msg.value
            );
            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(
                _stablecoinAmount,
                msg.value,
                0,
                _stableProportion,
                _volatileProportion,
                true
            );
        }
        emit Investment(
            _stablecoinAmount,
            _advisor,
            _stableProportion,
            _volatileProportion
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
        address _investor,
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
                savingContract,
                _investor
            );
        }
        VolatilePoolProxy(advisor.volatilePool).investYearn(
            _yearnVaults,
            _yearnInvestmentAmounts,
            _investor
        );
    }

    /**
        Investor Unwinding their position
        @param _advisor Address of the advisor.
        @param _vault the respective yearn vault addresses.
        @param _roi the roi of each vault to be fetched by https://yearn.tools/#/Vaults/get_vaults_apy.
        @param _stablecoin address of stablecoin to invest in mstable, will take usdc for hack.
     */
    function unwind(
        address _advisor,
        address[] calldata _vault,
        uint256[] calldata _roi,
        address _stablecoin
    ) external {
        Advisor storage advisor = advisorInfo[_advisor];
        require(_vault.length == _roi.length, "Invalid Inputs");

        StablePoolProxy(advisor.stablePool).redeemAmount(
            msg.sender,
            _advisor,
            massetAddress,
            savingContract,
            _stablecoin
        );

        VolatilePoolProxy(advisor.volatilePool).redeemAmount(
            msg.sender,
            _advisor,
            _roi,
            _vault,
            _stablecoin
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
