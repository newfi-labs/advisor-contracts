// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

contract Helper {
    /**
     * @dev get yearn vault address
     */
    function getETHVault() public pure returns (address ethVault) {
        ethVault = 0xe1237aA7f535b0CC33Fd973D66cBf830354D16c7;
    }
}

interface YearnController {
    function withdraw(address, uint) external;
    function balanceOf(address) external view returns (uint);
    function earn(address, uint) external;
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

    function balance() external view returns (uint);

    function totalSupply() external view returns (uint256);

    function controller() external view returns (address);

    function token() external view returns (address);

    function getPricePerFullShare() external view returns (uint);
}

contract VolatilePoolProxy is Initializable, OwnableUpgradeSafe, Helper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Initialized(address indexed thisAddress);

    function initialize() public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        emit Initialized(address(this));
    }

    function investYearn(
        address[] memory yearnVault,
        uint256[] memory _amount
    ) external {
        require(
            yearnVault.length == _amount.length,
            "Sanity Check: Yearn Vault"
        );
        for (uint256 i = 0; i < _amount.length; i++) {
            if (yearnVault[i] == getETHVault()) {
                YearnVault(yearnVault[i]).depositETH{value: _amount[i]}();
            } else {
                // since having stable amount for yearn is not mandatory
                if (_amount[i] > 0) {
                    YearnVault(yearnVault[i]).deposit(_amount[1]);
                }
            }
        }
    }

    function redeemAmount(
        address _investor,
        address _advisor,
        address[] calldata _vault,
        address _stablecoin,
        uint256 _investorStablePoolLiquidity,
        uint256 _investorVolatilePoolLiquidity,
        address advisorStablePoolToken,
        address advisorVolatilePoolToken,
        uint256 yearnAdvisorProportion
    ) external {
        for (uint256 i = 0; i < _vault.length; i++) {
            // had to reduce vars due to sol stack too deep error
            if (_vault[i] == getETHVault()) {
                uint256 poolTokenPrice = YearnVault(_vault[i]).balanceOf(address(this)).div(IERC20(advisorVolatilePoolToken).totalSupply());
                uint256 investorRedeemAmount = _investorVolatilePoolLiquidity.mul(poolTokenPrice);
                YearnVault(_vault[i]).withdrawETH(investorRedeemAmount);
                uint256 investorReturns = getInvestorReturnAmount(_vault[i], investorRedeemAmount);
                // 1 % per investor
                uint256 advisorFee = (investorReturns.mul(1)).div(100);
                investorReturns = investorReturns.sub(advisorFee);
                (bool ethTransferCheck, ) = _advisor.call{
            value: advisorFee
            }("");
                require(ethTransferCheck, "Advisor Transfer failed.");
                (ethTransferCheck, ) = _investor.call{
            value: investorReturns
            }("");
                require(ethTransferCheck, "Investor Transfer failed.");
                // transfer eth to both
            } else {
                uint256 investorYearnLiquidity = _investorStablePoolLiquidity.mul(yearnAdvisorProportion).div(100);
                uint256 investorRedeemAmount = investorYearnLiquidity.mul(YearnVault(_vault[i]).balanceOf(address(this)).div(IERC20(advisorStablePoolToken).totalSupply()));
                YearnVault(_vault[i]).withdraw(investorRedeemAmount);
                uint256 investorReturns = getInvestorReturnAmount(_vault[i], investorRedeemAmount);
                // 1 % per investor
                uint256 advisorFee = (investorReturns.mul(1)).div(100);
                investorReturns = investorReturns.sub(advisorFee);
                IERC20(_stablecoin).safeTransfer(_advisor, advisorFee);
                IERC20(_stablecoin).safeTransfer(
                    _investor,
                    investorReturns
                );
            }
        }
    }

    function getInvestorReturnAmount(address _vault, uint256 _investorRedeemAmount) internal returns(uint256) {
        address controller = YearnVault(_vault).controller();
        address token = YearnVault(_vault).token();
        uint investorReturns = (YearnVault(_vault).balance().mul(_investorRedeemAmount)).div(YearnVault(_vault).totalSupply());

        // Check balance
        uint b = IERC20(token).balanceOf(address(this));
        if (b < investorReturns) {
            uint _withdraw = investorReturns.sub(b);
            YearnController(controller).withdraw(address(token), _withdraw);
            uint _after = IERC20(token).balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                investorReturns = investorReturns.add(_diff);
            }
        }
        return investorReturns;
    }

    receive() external payable {}
}
