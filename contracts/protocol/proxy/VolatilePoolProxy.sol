// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';

contract VolatilePoolProxy is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);

    function initialize(address _advisor) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        OwnableUpgradeSafe.transferOwnership(_advisor);
        emit Initialized(address(this));
    }

    /**
        Advisor redeems lquidity from the stable protocol
        @param _investor investor address
        @param _advisor advisor address
        @param _investorVolatilePoolLiquidity volatile pool token balance of the investor.
        @param advisorVolatilePoolToken address of advisors volatile pool token.
        // Reusing some vars due to stack too deep error
     */
    function redeemAmount(
        address _investor,
        address _advisor,
        uint256 _investorVolatilePoolLiquidity,
        address advisorVolatilePoolToken
    ) external returns (uint256) {
        uint256 volatileAssetFees = 0;
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
        // yeth vault isn't accepting deposits
        // investorRedeemAmount = _investorVolatilePoolLiquidity
        //     .mul(volatileProtocolVolatileCoinProportion)
        //     .div(100);
        // since yearn eth vault deposit is disable now
        // YearnVault(getETHVault()).withdrawETH(investorRedeemAmount);
        // // resassigning var to avoid stack too deep
        // _investorVolatilePoolLiquidity = getInvestorReturnAmount(
        //     getETHVault(),
        //     investorRedeemAmount
        // );
        if (_investor != _advisor) {
            // 1 % per investor
            volatileAssetFees = (_investorVolatilePoolLiquidity.mul(1)).div(
                100
            );
            _investorVolatilePoolLiquidity = _investorVolatilePoolLiquidity.sub(
                volatileAssetFees
            );
            (bool ethTransferCheck, ) = _advisor.call{value: volatileAssetFees}(
                ''
            );
            require(ethTransferCheck, 'Advisor Transfer failed.');
        }

        (bool ethTransferCheck, ) = _investor.call{
            value: _investorVolatilePoolLiquidity
        }('');
        require(ethTransferCheck, 'Investor Transfer failed.');

        return volatileAssetFees;
    }

    receive() external payable {}
}
