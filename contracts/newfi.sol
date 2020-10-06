pragma solidity ^0.6.2;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";

contract NewFi is ReentrancyGuardUpgradeSafe {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    event AdvisorOnBoarded(string name, uint256 tradingExperience,  string twitterProfile, address pool,  uint256 stakedAmount);

    event Investment(uint256 _stablecoinAmount, address _advisor, address _poolAddress, uint256 _stableProportion, uint256 _volatileProportion);


struct Advisor {
        string name;
        uint256 tradingExperience;
        string twitterProfile;
        address pool;
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
    
    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
        @param _tradingExperience Trading exp in years for the investors in help choosing a particular advisor.
        @param _twitterProfile Twitter username of the advisor.
     */
    function onboard(string calldata _name, uint256 _tradingExperience, string calldata _twitterProfile) external {
        advisorInfo[msg.sender] = Advisor(_name, _tradingExperience, _twitterProfile, address(0), 0);
        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, _tradingExperience, _twitterProfile, address(0), 0);
    }
    
    /**
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _stablecoinAmount amount of stable coin.
        @param _advisor address os selected advisorr.
        @param _poolAddress address of advisor's pool to be created by gnosis sdk.
        @param _stableProportion stable coin proportion used to invest in protocols.
        @param _volatileProportion stable coin proportion used to invest in protocols.
        @param _advisor address os selected advisor.
     */
    function invest(address _stablecoin, uint256 _stablecoinAmount, address _advisor, address _poolAddress, uint256 _stableProportion, uint256 _volatileProportion) payable nonReentrant external {
        IERC20(_stablecoin).safeTransferFrom(address(this), _poolAddress, _stablecoinAmount);
        (bool success, ) = _poolAddress.call{value:msg.value}("");
        require(success, "Transfer failed.");

        Advisor storage advisor = advisorInfo[_advisor];
        advisor.pool = _poolAddress;
        Investor storage investor = investorInfo[msg.sender];

        if (investor.status) {
            investor.stablePoolLiquidity = investor.stablePoolLiquidity.add(_stablecoinAmount);
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(msg.value);
            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(_stablecoinAmount, msg.value, 0, _stableProportion, _volatileProportion, true);
        }
        emit Investment(_stablecoinAmount, _advisor, _poolAddress, _stableProportion, _volatileProportion);
    }
}
