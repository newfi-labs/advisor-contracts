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
    function deposit(uint256 _amount) external returns (uint256 creditIssued);

    function withdraw(uint256 _amount) external;
}

contract StablePoolProxy is Initializable, OwnableUpgradeSafe {
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
        SavingsContract(_savings).deposit(mAsset);
    }
}

contract VolatilePoolProxy is Initializable, OwnableUpgradeSafe, Helper {
    event Initialized(address indexed thisAddress);

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    function investYearn(address[] memory yearnVault, uint256[] memory _amount)
        external
    {
        require(
            yearnVault.length == _amount.length,
            "Sanity Check: Yearn Vault"
        );
        for (uint256 i = 0; i < _amount.length; i++) {
            if (yearnVault[i] == getETHVault()) {
                YearnVault(yearnVault[i]).depositETH{value: _amount[0]}();
            } else {
                // since having stable amount for yearn is not mandatory
                if (_amount[i] > 0) {
                    YearnVault(yearnVault[i]).deposit(_amount[1]);
                }
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
        address volatilePool,
        uint256 stakedAmount
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
        uint256 stakedAmount;
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
            address(uint160(volatilePool)),
            0
        );
        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, stablePool, volatilePool, 0);
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
        // This function assumes that based on the investors proption  and liquidity in both pools stored in the struct visible on ui, the advisors selects the amount to invest in yearn, mstable we can have that logic here as well
        // need to refactor stake calculation for assumptiom taken it to be 50 %
     */
    function protocolInvestment(
        address _mstableInvestmentAsset,
        uint256 _mstableInvestmentAmount,
        uint256[] memory _yearnInvestmentAmounts,
        address[] memory _yearnVaults
    ) public {
        uint256 _totalAmount = 0;
        // Max size will be 2 only
        for (uint256 i = 0; i < _yearnInvestmentAmounts.length; i++) {
            _totalAmount = _totalAmount.add(_yearnInvestmentAmounts[i]);
        }
        _totalAmount = _totalAmount.add(_mstableInvestmentAmount);

        // Just taking 50 % stake now this will change
        uint256 advisorStake = _totalAmount.div(2);
        Advisor storage advisor = advisorInfo[msg.sender];
        advisor.stakedAmount = advisorStake;

        // Currently staking only in stable pool since volatile pool is only for eth, but we can change this and do 50%
        IERC20(_mstableInvestmentAsset).safeTransferFrom(
            address(this),
            advisor.stablePool,
            advisorStake
        );
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
