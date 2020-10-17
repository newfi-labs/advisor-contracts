// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

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

    function initialize() public initializer {
        OwnableUpgradeSafe.__Ownable_init();
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
