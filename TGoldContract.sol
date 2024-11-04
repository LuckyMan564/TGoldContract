// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title Ttest Token
 * @dev ERC20 Token with adjustable transaction fees for buys and sells,
 *      with a deflationary mechanism and rewards distribution, designed for upgradeability.
 */

contract TtestToken is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 public buyFeePercentage;
    uint256 public sellFeePercentage;
    uint256 public buybackAndBurnPercentage;
    address public liquidityWallet;
    address public transactionWallet;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public isLiquidityPool;

    uint256 public rewardPerTokenStored;
    uint256 private _totalExcludedBalance;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address[] private _excludedFromRewards;

    IUniswapV2Router02 public dexRouter;
    address public lpTokenAddress; // Store the LP token address for buyback so need to set in initializer

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() public initializer {
        __ERC20_init("Ttest Token", "Ttest");
        __Ownable_init();
        __UUPSUpgradeable_init();

        _mint(msg.sender, 1_000_000 * (10**decimals()));
        buyFeePercentage = 5;
        sellFeePercentage = 10;
        buybackAndBurnPercentage = 25;
        transactionWallet = 0xA7dFf3C0144f746f8b4BfB0C9b172baAf2451032;

        _isExcludedFromFees[msg.sender] = true;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[transactionWallet] = true;

        _excludeFromRewards(msg.sender);
        _excludeFromRewards(address(this));
        _excludeFromRewards(transactionWallet);
    }

    /*** Upgrade Functionality ***/
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /*** Fee Management ***/
    function setBuyFeePercentage(uint256 fee) external onlyOwner {
        require(fee <= 30, "Fee cannot exceed 30%");
        buyFeePercentage = fee;
    }

    function setSellFeePercentage(uint256 fee) external onlyOwner {
        require(fee <= 30, "Fee cannot exceed 30%");
        sellFeePercentage = fee;
    }

    function setTransactionWallet(address wallet) external onlyOwner {
        require(wallet != address(0), "Invalid address");
        _excludeFromRewards(transactionWallet);
        transactionWallet = wallet;
        _excludeFromRewards(transactionWallet);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    /*** Liquidity Pool Management ***/
    function setLiquidityPool(address pool, bool value) external onlyOwner {
        isLiquidityPool[pool] = value;
    }

    /*** Reward Distribution ***/
    function claimRewards() external {
        _updateReward(msg.sender);

        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            _transfer(address(this), msg.sender, reward);
        }
    }

    function earned(address account) public view returns (uint256) {
        uint256 balance = balanceOf(account);
        return
            ((balance *
                (rewardPerTokenStored - userRewardPerTokenPaid[account])) /
                1e18) + rewards[account];
    }

    /*** Internal Functions ***/
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override {
        _updateReward(from);
        _updateReward(to);

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            super._transfer(from, to, value);
        } else {
            uint256 feePercentage = _getFeePercentage(from, to);
            uint256 feeAmount = (value * feePercentage) / 100;
            uint256 halfFee = feeAmount / 2;
            uint256 remainingAmount = value - feeAmount;

            uint256 liquidityAllocation = (halfFee * 50) / 100;
            uint256 holderRewards = (halfFee * 50) / 100;
            uint256 buybackAndBurn = (feeAmount * buybackAndBurnPercentage) /
                1000;

            if (liquidityAllocation > 0) {
                super._transfer(from, liquidityWallet, liquidityAllocation);
            }
            if (holderRewards > 0) {
                super._transfer(from, address(this), holderRewards);
                _distributeRewards(holderRewards);
            }
            if (buybackAndBurn > 0) {
                _buyBackAndBurn(buybackAndBurn);
            }

            super._transfer(from, to, remainingAmount);
        }
    }

    function _getFeePercentage(address sender, address recipient)
        private
        view
        returns (uint256)
    {
        if (isLiquidityPool[sender]) {
            return buyFeePercentage;
        } else if (isLiquidityPool[recipient]) {
            return sellFeePercentage;
        } else {
            return 0;
        }
    }

    function _distributeRewards(uint256 reward) private {
        uint256 circulatingSupply = totalSupply() - _totalExcludedBalance;
        if (circulatingSupply > 0) {
            rewardPerTokenStored += (reward * 1e18) / circulatingSupply;
        }
    }

    function _updateReward(address account) private {
        if (_isExcludedFromRewards(account)) return;
        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
    }

    /*** Buyback and Burn Mechanism ***/
    function _buyBackAndBurn(uint256 amount) private {
        // _burn(sender, amount);
        require(address(dexRouter) != address(0), "Router not set");
        require(lpTokenAddress != address(0), "LP token address not set");

        // Approve router to spend tokens
        _approve(address(this), address(dexRouter), amount);

        address[] memory path = new address[](2);
        path[0] = address(this); // Token address
        path[1] = dexRouter.WETH(); // Assuming WETH/ETH pair on the DEX

        // Swap tokens for ETH or LP tokens
        dexRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0, // Minimum amount out (can be set to 0 for simplicity)
            path,
            address(this),
            block.timestamp
        );

        // Burn LP tokens by transferring to the zero address
        IERC20(lpTokenAddress).transfer(address(0), amount);
    }

    /*** Reward Exclusion Management ***/
    function _excludeFromRewards(address account) private {
        if (_isExcludedFromRewards(account)) return;
        _totalExcludedBalance += balanceOf(account);
        _excludedFromRewards.push(account);
    }

    function _includeInRewards(address account) private {
        if (!_isExcludedFromRewards(account)) return;
        for (uint256 i = 0; i < _excludedFromRewards.length; i++) {
            if (_excludedFromRewards[i] == account) {
                _excludedFromRewards[i] = _excludedFromRewards[
                    _excludedFromRewards.length - 1
                ];
                _excludedFromRewards.pop();
                break;
            }
        }
        _totalExcludedBalance -= balanceOf(account);
    }

    function _isExcludedFromRewards(address account)
        private
        view
        returns (bool)
    {
        for (uint256 i = 0; i < _excludedFromRewards.length; i++) {
            if (_excludedFromRewards[i] == account) return true;
        }
        return false;
    }

    /*** Additional Functions ***/
    function setDexRouter(address router, address lpToken) external onlyOwner {
        require(router != address(0), "Invalid router address");
        dexRouter = IUniswapV2Router02(router);
        lpTokenAddress = lpToken;
    }
}