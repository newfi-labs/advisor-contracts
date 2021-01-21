pragma solidity ^0.6.0;

library InvestmentData {
    struct Advisor {
        string name;
        address stablePool;
        address payable volatilePool;
        address stablePoolToken;
        address volatilePoolToken;
        uint256 stableCoinMstableProportion;
        uint256 stableCoinYearnProportion;
    }
}
