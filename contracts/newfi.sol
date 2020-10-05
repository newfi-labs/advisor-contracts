pragma solidity 0.6.2;

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/token/ERC20/ERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/token/ERC20/SafeERC20.sol";


contract NewFi {
    using SafeERC20 for ERC20;
    using SafeMath for uint;
    event AdvisorOnBoarded(string name, uint256 tradingExpereience,  string twiiterProfile, address stablePool, address volatilePool,   uint256 stakedAmount);
       
    
    struct Advisor {
        string naame;
        uint256 tradingExpereience;
        string twiiterProfile;
        address stablePool;
        address volatilePool;
        uint256 stakedAmount;
    }
    
    struct Investor {
        uint256 stablePoolLiquidity;
        uint256 volatilePoolLiquidity;
        uint256 poolTokenBalance;
        bool status;
    }
    
    mapping(address => Advisor) public advisorInfo;
    
    mapping(address => Investor) public investorInfo;
    
    address[] public advisors;
    
    address[] public investors;
    
    /**
        Onboards a new Advisor
        @param _name Name of the Advisor.
        @param _tradingExpereience Trading exp in years for the investors in help chossing a particular advisor.
        @param _twiiterProfile Twitter username of the advisor.
     */
    function onboard(string calldata _name, uint256 _tradingExpereience, string calldata _twiiterProfile) external {
        advisorInfo[msg.sender] = Advisor(_name, _tradingExpereience, _twiiterProfile, address(0), address(0), 0);
        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, _tradingExpereience, _twiiterProfile, address(0), address(0), 0);
    }
    
    /**
        Investor deposits liquidity to advisor pools
        @param _stablecoin address of stablecoin.
        @param _stablecoinAmount amount of stable coin.
        @param _advisor address os selected advisorr.
        @param _stablePoolAddress address of advisor's stable pool to be created by gnosis sdk.
        @param _volatilePoolAddress address of the advisor's volatile pool to be created by gnosis sdk.
     */
    function invest(address _stablecoin, uint _stablecoinAmount, address _advisor, address _stablePoolAddress, address _volatilePoolAddress) payable external {
        ERC20(_stablecoin).safeTransferFrom(address(this), _stablePoolAddress, _stablecoinAmount);
        (bool success, ) = _volatilePoolAddress.call.value(msg.value)("");
        require(success, "Transfer failed.");
        Advisor storage advisor = advisorInfo[_advisor];
        advisor.stablePool = _stablePoolAddress;
        advisor.volatilePool = _volatilePoolAddress;
        Investor storage investor = investorInfo[msg.sender];
        if (investor.status) {
            investor.stablePoolLiquidity = investor.stablePoolLiquidity.add(_stablecoinAmount);
            investor.volatilePoolLiquidity = investor.volatilePoolLiquidity.add(msg.value);
            // not including the pool token balance calculation at the moment
        } else {
            investorInfo[msg.sender] = Investor(_stablecoinAmount, msg.value, 0, true);
        }
    }
}
