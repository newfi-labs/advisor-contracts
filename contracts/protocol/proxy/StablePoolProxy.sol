// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol';

contract Helper {
    // creating this due to stack too deep error
    function getUSDCVault() public pure returns (address usdcVault) {
        usdcVault = 0x597aD1e0c13Bfe8025993D9e79C69E1c0233522e;
    }
}

interface YearnController {
    function withdraw(address, uint256) external;

    function balanceOf(address) external view returns (uint256);

    function earn(address, uint256) external;
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

    function balance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function controller() external view returns (address);

    function token() external view returns (address);

    function getPricePerFullShare() external view returns (uint256);
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

contract StablePoolProxy is Initializable, OwnableUpgradeSafe, Helper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // due to stack too deep error
    uint256 constant totalProportion = 100;
    event Initialized(address indexed thisAddress);

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    /**
        Advsior deposits liquidity to mstable
        @param _mAsset address of mstable's musd.
        @param _bAsset amount of stable coin.
        @param _amount amount to be deposited.
        @param _savings address of mstable's savings contract to generate yield.
     */
    function invest(
        address _mAsset,
        address _bAsset,
        uint256 _amount,
        address _savings,
        uint256 mstableProportion,
        uint256 yearnProportion
    ) external {
        uint256 mstableAmount = _amount.mul(mstableProportion).div(100);
        uint256 yearnAmount = _amount.mul(yearnProportion).div(100);
        uint256 mAsset = MAsset(_mAsset).mint(_bAsset, mstableAmount);
        SavingsContract(_savings).depositSavings(mAsset);
        YearnVault(getUSDCVault()).deposit(yearnAmount);
    }

    /**
        Advisor redeems lquidity from the stable protocol
        @param _investor investor address
        @param _advisor advisor address
        @param _mAsset address of mstable's musd.
        @param _savings address of mstable's savings contract to generate yield.
        @param _stablecoin address of stable coin.
        @param _investorStablePoolLiquidity stable pool token balance of the investor.
        @param advisorStablePoolToken address of advisors stable pool token.
     */
    function redeemAmount(
        address _investor,
        address _advisor,
        address _mAsset,
        address _savings,
        address _stablecoin,
        uint256 _investorStablePoolLiquidity,
        address advisorStablePoolToken,
        uint256 mstableProportion
    ) external returns (uint256) {
        // uint256 advisorFee = 0;
        IERC20(advisorStablePoolToken).safeTransfer(
            address(0),
            _investorStablePoolLiquidity
        );
        uint256 mstableAmount = _investorStablePoolLiquidity
            .mul(mstableProportion)
            .div(100);
        uint256 yearnAmount = _investorStablePoolLiquidity
            .mul(totalProportion.sub(mstableProportion))
            .div(100);
        // commented stuff due to stack too deep error
        // uint256 poolValue = SavingsContract(_savings)
        //     .creditBalances(address(this))
        //     .mul(SavingsContract(_savings).exchangeRate());
        // uint256 poolTokenSupply = IERC20(advisorStablePoolToken).totalSupply();
        uint256 poolTokenPrice = SavingsContract(_savings)
            .creditBalances(address(this))
            .mul(SavingsContract(_savings).exchangeRate())
            .div(IERC20(advisorStablePoolToken).totalSupply());
        uint256 investorMStableReturns = mstableAmount.mul(poolTokenPrice);
        investorMStableReturns = SavingsContract(_savings).redeem(
            investorMStableReturns
        );

        investorMStableReturns = MAsset(_mAsset).redeem(
            _stablecoin,
            SavingsContract(_savings).redeem(investorMStableReturns)
        );

        // get the yearn stable pool proportion set by advisor and get the investors share based on it
        uint256 investorYearnReturns = yearnAmount.mul(
            (YearnVault(getUSDCVault()).balanceOf(address(this))).div(
                IERC20(advisorStablePoolToken).totalSupply()
            )
        );
        YearnVault(getUSDCVault()).withdraw(investorYearnReturns);
        // resassigning var to avoid stack too deep
        // getting principal + earnings
        investorYearnReturns = getInvestorReturnAmount(
            getUSDCVault(),
            investorYearnReturns
        );
        uint256 totalReturns = investorYearnReturns.add(investorMStableReturns);
        // 1 % per investor
        if (_investor != _advisor) {
            // advisorFee = (totalReturns.mul(1)).div(100);
            totalReturns = totalReturns.sub((totalReturns.mul(1)).div(100));
            IERC20(_stablecoin).safeTransfer(
                _advisor,
                (totalReturns.mul(1)).div(100)
            );
        }
        IERC20(_stablecoin).safeTransfer(_investor, totalReturns);
        return (totalReturns.mul(1)).div(100);
    }

    function getInvestorReturnAmount(
        address _vault,
        uint256 _investorRedeemAmount
    ) internal returns (uint256) {
        address controller = YearnVault(_vault).controller();
        address token = YearnVault(_vault).token();
        uint256 investorReturns = (
            YearnVault(_vault).balance().mul(_investorRedeemAmount)
        )
            .div(YearnVault(_vault).totalSupply());

        // Check balance
        uint256 b = IERC20(token).balanceOf(address(this));
        if (b < investorReturns) {
            uint256 _withdraw = investorReturns.sub(b);
            YearnController(controller).withdraw(address(token), _withdraw);
            uint256 _after = IERC20(token).balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                investorReturns = investorReturns.add(_diff);
            }
        }
        return investorReturns;
    }
}
