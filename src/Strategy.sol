// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import { BaseStrategy, StrategyParams } from "@yearnvaults/contracts/BaseStrategy.sol";

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Market } from "../src/interfaces/Market.sol";
import { RewardsController } from "../src/interfaces/rewards.sol";
import { IVelodromeRouter } from "../src/interfaces/IVelodromeRouter.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IERC20 public constant op =
        IERC20(0x4200000000000000000000000000000000000042);

    Market public constant exactly =
        Market(0x81C9A7B55A4df39A9B7B5F781ec0e53539694873);
    RewardsController public constant rewardsController =
        RewardsController(0xBd1ba78A3976cAB420A9203E6ef14D18C2B2E031);
    IVelodromeRouter public constant router =
        IVelodromeRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);

    // solhint-disable-next-line no-empty-blocks
    constructor(address _vault) BaseStrategy(_vault) {
        maxReportDelay = 6300;
        op.approve(address(router), type(uint256).max);
        want.approve(address(exactly), type(uint256).max);
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "StrategyExactlyUSDC";
    }

    function shareToAssets() public view returns (uint256) {
        uint256 exa_bal = exactly.balanceOf(address(this));
        return exactly.convertToAssets(exa_bal);
    }

    function wantBalance() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return wantBalance().add(shareToAssets());
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    // solhint-disable-next-line no-empty-blocks
    {
        if (rewardsController.allClaimable(address(this), address(op)) > 0) {
            rewardsController.claimAll(address(this));
            _sellRewards();
        }
        uint256 stakedBal = exactly.balanceOf(address(this));
        if (_debtOutstanding > 0) {
            if (stakedBal > 0) {
                exactly.redeem(
                    Math.min(stakedBal, _debtOutstanding),
                    address(this),
                    address(this)
                );
            }
            _debtPayment = Math.min(stakedBal, _debtOutstanding);
        }
        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        if (assets > debt) {
            _profit = assets.sub(debt);
            uint256 _wantBal = wantBalance();
            if (_profit.add(_debtPayment) > _wantBal) {
                liquidateAllPositions();
            }
        } else {
            _loss = debt.sub(assets);
        }
    }

    // solhint-disable-next-line no-empty-blocks
    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _wantBal = wantBalance();
        if (_wantBal > _debtOutstanding) {
            exactly.deposit(_wantBal, address(this));
        }
    }

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 _wantBal = want.balanceOf(address(this));
        if (_amountNeeded > _wantBal) {
            uint256 _stakedBalance = shareToAssets();
            if (_stakedBalance > 0) {
                exactly.withdraw(
                    Math.min(_stakedBalance, _amountNeeded.sub(_wantBal)),
                    address(this),
                    address(this)
                );
            }
            uint256 _withdrawnBalance = wantBalance();
            _liquidatedAmount = Math.min(_amountNeeded, _withdrawnBalance);
            _loss = _amountNeeded.sub(_liquidatedAmount);
        } else {
            return (_amountNeeded, 0);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // TODO: Liquidate all positions and return the amount freed.
        uint256 _exactlyBal = exactly.balanceOf(address(this));
        if (_exactlyBal > 0) {
            exactly.redeem(_exactlyBal, address(this), address(this));
        }
        return wantBalance();
    }

    // solhint-disable-next-line no-empty-blocks
    function prepareMigration(address _newStrategy) internal override {
        uint256 _exactlyBal = exactly.balanceOf(address(this));
        if (_exactlyBal > 0) {
            exactly.redeem(_exactlyBal, address(this), address(this));
        }
        rewardsController.claimAll(address(this));
        op.safeTransfer(address(_newStrategy), op.balanceOf(address(this)));
        want.safeTransfer(
            address(_newStrategy),
            want.balanceOf(address(this))
        );
    }

    function _sellRewards() internal {
        uint op_bal = op.balanceOf(address(this));
        router.swapExactTokensForTokensSimple(
            op_bal,
            0,
            address(op),
            address(want),
            false,
            address(this),
            block.timestamp
        );
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 1800000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(
        uint256 _amtInWei
    ) public view virtual override returns (uint256) {
        // TODO create an accurate price oracle
        return _amtInWei;
    }
}
