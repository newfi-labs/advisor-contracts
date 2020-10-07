pragma solidity ^0.6.2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "./utils/ProxyFactory.sol";
import "./utils/OwnableUpgradeSafe.sol";


contract PoolProxy is Initializable, OwnableUpgradeSafe {
    event Initialized(address indexed thisAddress);

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    // Fallback Functions for calldata and reciever for handling only ether transfer
    fallback() external payable {}

    receive() external payable {}
}

contract NewfiAdvisor is ReentrancyGuardUpgradeSafe, ProxyFactory {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event AdvisorOnBoarded(string name, address stablePool, address volatilePool, uint256 stakedAmount);

    event Investment(
        uint256 _stablecoinAmount,
        address _advisor,
        uint256 _stableProportion,
        uint256 _volatileProportion
    );

    struct Advisor {
        string name;
        address stablePool;
        address volatilePool;
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

    address public proxyBaseAddress;

    /**
        Constructor
        @param _proxy Address of the proxy contract defined above to create clones.
     */
    constructor(address _proxy) public {
      proxyBaseAddress = _proxy;
    }

    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
     */
    function onboard(string calldata _name) external {
        // TCreating two pool proxies back to back
        address stablePool = createProxy(msg.sender);
        address volatilePool = createProxy(msg.sender);
        advisorInfo[msg.sender] = Advisor(_name, stablePool, volatilePool, 0);
        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, stablePool, volatilePool, 0);
    }

    /**
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _stablecoinAmount amount of stable coin.
        @param _advisor address os selected advisor.
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
        @param _advisor Address of the Advisor.
     */
    function createProxy(address _advisor) internal returns(address) {
    bytes memory _payload = abi.encodeWithSignature(
      "initialize(address)",
      _advisor
    );
    // Deploy proxy
    // for testing the address of the proxy contract which will
    // be used to redirect interest will come here
    address _intermediate = deployMinimal(proxyBaseAddress, _payload);
    return _intermediate;

  }
}
