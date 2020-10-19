// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';

contract Helper {
    /**
     * @dev get yearn vault address
     */
    function getETHVault() public pure returns (address ethVault) {
        ethVault = 0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7;
    }

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

contract VolatilePoolProxy is Initializable, OwnableUpgradeSafe, Helper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    /**
        Investor deposits liquidity to advisor pools
        @param stableAssetAmount stable asset amount.
     */
    function investYearn(uint256 stableAssetAmount) external {
        YearnVault(getUSDCVault()).deposit(stableAssetAmount);
    }

    /**
        Advisor redeems lquidity from the stable protocol
        @param _investor investor address
        @param _advisor advisor address
        @param _stablecoin address of stable coin.
        @param _investorVolatilePoolLiquidity volatile pool token balance of the investor.
        @param advisorVolatilePoolToken address of advisors volatile pool token.
        @param volatileProtocolStableCoinProportion stable coin proportion in volatile pool.
        @param volatileProtocolVolatileCoinProportion volatile coin proportion in volatile pool.
        // Reusing some vars due to stack too deep error
     */
    function redeemAmount(
        address _investor,
        address _advisor,
        address _stablecoin,
        uint256 _investorVolatilePoolLiquidity,
        address advisorVolatilePoolToken,
        uint256 volatileProtocolStableCoinProportion,
        uint256 volatileProtocolVolatileCoinProportion
    ) external returns (uint256) {
        uint256 stableAssetFees = 0;
        uint256 volatileAssetFees = 0;
        uint256 investorRedeemAmount = 0;
        require(
            _investorVolatilePoolLiquidity > 0,
            'No Volatile Pool Liquidity'
        );
        // had to reduce vars due to sol stack too deep error
        // investor token share * pool token price
        IERC20(advisorVolatilePoolToken).safeTransfer(
            address(0),
            _investorVolatilePoolLiquidity
        );
        investorRedeemAmount = _investorVolatilePoolLiquidity
            .mul(volatileProtocolVolatileCoinProportion)
            .div(100);
        // since yearn eth vault deposit is disable now
        // YearnVault(getETHVault()).withdrawETH(investorRedeemAmount);
        // // resassigning var to avoid stack too deep
        // _investorVolatilePoolLiquidity = getInvestorReturnAmount(
        //     getETHVault(),
        //     investorRedeemAmount
        // );
        if (_investor != _advisor) {
            // 1 % per investor
            volatileAssetFees = (investorRedeemAmount.mul(1)).div(100);
            investorRedeemAmount = investorRedeemAmount.sub(volatileAssetFees);
            (bool ethTransferCheck, ) = _advisor.call{value: volatileAssetFees}(
                ''
            );
            require(ethTransferCheck, 'Advisor Transfer failed.');
        }

        (bool ethTransferCheck, ) = _investor.call{value: investorRedeemAmount}(
            ''
        );
        require(ethTransferCheck, 'Investor Transfer failed.');
        // get the yearn stable pool proportion set by advisor and get the investors share based on it
        investorRedeemAmount = _investorVolatilePoolLiquidity
            .mul(volatileProtocolStableCoinProportion)
            .div(100)
            .mul(
            (YearnVault(getUSDCVault()).balanceOf(address(this)).mul(10**12))
                .div(IERC20(advisorVolatilePoolToken).totalSupply())
        );
        YearnVault(getUSDCVault()).withdraw(investorRedeemAmount.div(10**12));
        // resassigning var to avoid stack too deep
        // getting principal + earnings
        _investorVolatilePoolLiquidity = getInvestorReturnAmount(
            getUSDCVault(),
            investorRedeemAmount
        );
        if (_investor != _advisor) {
            // 1 % per investor
            stableAssetFees = (_investorVolatilePoolLiquidity.mul(1)).div(100);
            _investorVolatilePoolLiquidity = _investorVolatilePoolLiquidity.sub(
                stableAssetFees
            );
            IERC20(_stablecoin).safeTransfer(_advisor, stableAssetFees);
        }
        IERC20(_stablecoin).safeTransfer(
            _investor,
            _investorVolatilePoolLiquidity
        );

        return (stableAssetFees.add(volatileAssetFees));
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

    receive() external payable {}
}
