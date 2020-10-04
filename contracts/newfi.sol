pragma solidity 0.6.0;

contract NewFi {
    // useful for the graph
    event AdvisorOnBoarded(string name, uint256 tradingExpereience,  string twiiterProfile, address stablePool, address volatilePool,   uint256 stakedAmount);
       
    
    // we can take just the twiiter username for so the investor has much more information than just the name, maybe we can have some twitter verification function on js end
    // to just check the user's profile exists or not 
    struct Advisor {
        string naame;
        uint256 tradingExpereience;
        string twiiterProfile;
        address stablePool;
        address volatilePool;
        uint256 stakedAmount;
    }
    // keep track of all the advisors on the platform
    mapping(address => Advisor) public advisorInfo;
    
    // track the addresses of all advisors to display on the dashboard
    address[] public advisors;
    
    /**
        Creates a new instance of GoogGhosting game
        @param _name Name of the Advisor.
        @param _tradingExpereience Trading exp in years for the investors in help chossing a particular advisor.
        @param _twiiterProfile Twitter username of the advisor.
     */
    function onboard(string calldata _name, uint256 _tradingExpereience, string calldata _twiiterProfile) external {
        advisorInfo[msg.sender] = Advisor(_name, _tradingExpereience, _twiiterProfile, address(0), address(0), 0);
        advisors.push(msg.sender);
        emit AdvisorOnBoarded(_name, _tradingExpereience, _twiiterProfile, address(0), address(0), 0);
    }
}