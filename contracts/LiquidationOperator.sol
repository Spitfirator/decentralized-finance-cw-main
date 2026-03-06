//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     **/
    function transfer(address to, uint256 value) external;
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     **/
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minDy
    ) external;
}

// ----------------------IMPLEMENTATION------------------------------

contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;

    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    uint256 constant FIRST_LIQUIDATION_USDT = 2916378221684;
    uint256 constant FLASH_BORROW_BPS = 15000;
    uint256 constant FLASH_BORROW_USDT = (FIRST_LIQUIDATION_USDT * FLASH_BORROW_BPS) / 10000;
    uint256 constant DIRECT_WBTC_USDT_WEIGHT_BPS = 20000;
    uint256 constant USDT_CONVERSION_TARGET_BPS = 7500;

    IUniswapV2Pair immutable wethUsdtPair;
    IUniswapV2Pair immutable wbtcWethPair;
    IUniswapV2Pair immutable sushiWbtcWethPair;
    IUniswapV2Pair immutable uniWbtcUsdtPair;
    IUniswapV2Pair immutable uniUsdcWethPair;
    IUniswapV2Pair immutable sushiUsdcWethPair;

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function ceilDiv(uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256)
    {
        return numerator == 0 ? 0 : ((numerator - 1) / denominator) + 1;
    }

    function swapToken0ForToken1(
        IUniswapV2Pair pair,
        address token0,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        IERC20(token0).transfer(address(pair), amountIn);
        pair.swap(0, amountOut, address(this), "");
    }

    function swapToken1ForToken0(
        IUniswapV2Pair pair,
        address token1,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        IERC20(token1).transfer(address(pair), amountIn);
        pair.swap(amountOut, 0, address(this), "");
    }

    function combinedUsdcOut(
        uint256 wethIn,
        uint256 uniReserveUsdc,
        uint256 uniReserveWeth,
        uint256 sushiReserveUsdc,
        uint256 sushiReserveWeth
    ) internal pure returns (uint256 totalUsdcOut) {
        if (wethIn == 0) {
            return 0;
        }

        uint256 totalReserveWeth = uniReserveWeth + sushiReserveWeth;
        if (totalReserveWeth == 0) {
            return 0;
        }

        uint256 uniWethIn = (wethIn * uniReserveWeth) / totalReserveWeth;
        uint256 sushiWethIn = wethIn - uniWethIn;

        if (uniWethIn > 0 && uniReserveUsdc > 0 && uniReserveWeth > 0) {
            totalUsdcOut += getAmountOut(uniWethIn, uniReserveWeth, uniReserveUsdc);
        }
        if (sushiWethIn > 0 && sushiReserveUsdc > 0 && sushiReserveWeth > 0) {
            totalUsdcOut += getAmountOut(sushiWethIn, sushiReserveWeth, sushiReserveUsdc);
        }
    }

    function findWethInForTargetUsdc(
        uint256 targetUsdcOut,
        uint256 maxWethIn,
        uint256 uniReserveUsdc,
        uint256 uniReserveWeth,
        uint256 sushiReserveUsdc,
        uint256 sushiReserveWeth
    ) internal pure returns (uint256 wethIn) {
        if (targetUsdcOut == 0) {
            return 0;
        }

        if (
            combinedUsdcOut(
                maxWethIn,
                uniReserveUsdc,
                uniReserveWeth,
                sushiReserveUsdc,
                sushiReserveWeth
            ) <= targetUsdcOut
        ) {
            return maxWethIn;
        }

        uint256 low = 0;
        uint256 high = maxWethIn;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (
                combinedUsdcOut(
                    mid,
                    uniReserveUsdc,
                    uniReserveWeth,
                    sushiReserveUsdc,
                    sushiReserveWeth
                ) >= targetUsdcOut
            ) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function getMinimumWethRepayment(
        uint256 reserveWeth,
        uint256 reserveUsdt,
        uint256 borrowedUsdt,
        uint256 returnedUsdt
    ) internal pure returns (uint256 wethNeeded) {
        uint256 adjustedUsdtBalance = (reserveUsdt * 1000) - (borrowedUsdt * 1000) + (returnedUsdt * 997);
        uint256 minimumAdjustedWethBalance = ceilDiv(
            reserveWeth * reserveUsdt * 1000000,
            adjustedUsdtBalance
        );
        uint256 currentAdjustedWethBalance = reserveWeth * 1000;

        if (minimumAdjustedWethBalance <= currentAdjustedWethBalance) {
            return 0;
        }

        wethNeeded = ceilDiv(
            minimumAdjustedWethBalance - currentAdjustedWethBalance,
            997
        );
    }

    constructor() {
        address wethUsdt = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WETH_ADDR, USDT);
        address uniWbtcWeth = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WBTC, WETH_ADDR);
        address sushiWbtcWeth = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WBTC, WETH_ADDR);
        address uniWbtcUsdt = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WBTC, USDT);
        address uniUsdcWeth = IUniswapV2Factory(UNISWAP_FACTORY).getPair(USDC, WETH_ADDR);
        address sushiUsdcWeth = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(USDC, WETH_ADDR);

        require(wethUsdt != address(0), "Missing WETH/USDT");
        require(uniWbtcWeth != address(0), "Missing Uni WBTC/WETH");
        require(sushiWbtcWeth != address(0), "Missing Sushi WBTC/WETH");
        require(uniWbtcUsdt != address(0), "Missing WBTC/USDT");
        require(uniUsdcWeth != address(0), "Missing Uni USDC/WETH");
        require(sushiUsdcWeth != address(0), "Missing Sushi USDC/WETH");

        wethUsdtPair = IUniswapV2Pair(wethUsdt);
        wbtcWethPair = IUniswapV2Pair(uniWbtcWeth);
        sushiWbtcWethPair = IUniswapV2Pair(sushiWbtcWeth);
        uniWbtcUsdtPair = IUniswapV2Pair(uniWbtcUsdt);
        uniUsdcWethPair = IUniswapV2Pair(uniUsdcWeth);
        sushiUsdcWethPair = IUniswapV2Pair(sushiUsdcWeth);
    }

    receive() external payable {}

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // 1. get the target user account data & make sure it is liquidatable
        (,,,,,uint256 healthFactor) = ILendingPool(AAVE_LENDING_POOL).getUserAccountData(TARGET_USER);
        require(healthFactor < 1e18, "Target user is not liquidatable");

        // 2. call flash swap to liquidate the target user
        // token0=WETH, token1=USDT; borrow USDT so amount0Out=0, amount1Out=amount
        wethUsdtPair.swap(0, FLASH_BORROW_USDT, address(this), "flash");

        // 3. Convert the profit into ETH and send back to sender
        uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));
        IWETH(WETH_ADDR).withdraw(wethBalance);
        payable(msg.sender).transfer(address(this).balance);
    }

    // required by the swap
    function uniswapV2Call(
        address sender,
        uint256,
        uint256 amount1,
        bytes calldata
    ) external override {
        // 2.0. security checks
        require(msg.sender == address(wethUsdtPair), "Unauthorized");
        require(sender == address(this), "Invalid sender");

        IERC20(USDT).approve(AAVE_LENDING_POOL, 0);
        IERC20(USDT).approve(AAVE_LENDING_POOL, type(uint256).max);

        ILendingPool lendingPool = ILendingPool(AAVE_LENDING_POOL);

        // 2.1 first liquidation, capped by Aave at 50% of the current debt
        lendingPool.liquidationCall(WBTC, USDT, TARGET_USER, type(uint256).max, false);

        // 2.2 second liquidation if the account is still underwater
        uint256 remainingUsdt = IERC20(USDT).balanceOf(address(this));
        if (remainingUsdt > 0) {
            (,,,,,uint256 healthFactorAfterFirst) = lendingPool.getUserAccountData(TARGET_USER);
            if (healthFactorAfterFirst < 1e18) {
                try lendingPool.liquidationCall(WBTC, USDT, TARGET_USER, remainingUsdt, false) {} catch {}
            }
        }

        // 2.3 sell WBTC across direct USDT and two WETH routes
        {
            uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
            (uint112 uniReserveWbtc, uint112 uniReserveWeth,) = wbtcWethPair.getReserves();
            (uint112 sushiReserveWbtc, uint112 sushiReserveWeth,) = sushiWbtcWethPair.getReserves();
            (uint112 directReserveWbtc, uint112 directReserveUsdt,) = uniWbtcUsdtPair.getReserves();
            uint256 weightedDirectReserveWbtc =
                (uint256(directReserveWbtc) * DIRECT_WBTC_USDT_WEIGHT_BPS) / 10000;

            uint256 totalWbtcLiquidity =
                uint256(uniReserveWbtc) +
                uint256(sushiReserveWbtc) +
                weightedDirectReserveWbtc;
            require(totalWbtcLiquidity > 0, "Missing WBTC liquidity");

            uint256 uniWbtcIn = (wbtcBalance * uint256(uniReserveWbtc)) / totalWbtcLiquidity;
            uint256 sushiWbtcIn = (wbtcBalance * uint256(sushiReserveWbtc)) / totalWbtcLiquidity;
            uint256 directWbtcIn = wbtcBalance - uniWbtcIn - sushiWbtcIn;

            swapToken0ForToken1(
                uniWbtcUsdtPair,
                WBTC,
                directWbtcIn,
                uint256(directReserveWbtc),
                uint256(directReserveUsdt)
            );
            swapToken0ForToken1(
                wbtcWethPair,
                WBTC,
                uniWbtcIn,
                uint256(uniReserveWbtc),
                uint256(uniReserveWeth)
            );
            swapToken0ForToken1(
                sushiWbtcWethPair,
                WBTC,
                sushiWbtcIn,
                uint256(sushiReserveWbtc),
                uint256(sushiReserveWeth)
            );
        }

        // 2.4 convert enough WETH to USDC, then 2.5 use Curve 3pool to turn it into USDT
        {
            uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
            uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));
            if (usdtBalance < amount1 && wethBalance > 0) {
                uint256 usdtShortfall = amount1 - usdtBalance;
                uint256 targetUsdcOut =
                    ((usdtShortfall * USDT_CONVERSION_TARGET_BPS) / 10000) + 1;

                (uint112 uniReserveUsdc, uint112 uniReserveWeth,) = uniUsdcWethPair.getReserves();
                (uint112 sushiReserveUsdc, uint112 sushiReserveWeth,) = sushiUsdcWethPair.getReserves();

                uint256 wethToSell = findWethInForTargetUsdc(
                    targetUsdcOut,
                    wethBalance,
                    uint256(uniReserveUsdc),
                    uint256(uniReserveWeth),
                    uint256(sushiReserveUsdc),
                    uint256(sushiReserveWeth)
                );

                if (wethToSell > 0) {
                    uint256 totalReserveWeth = uint256(uniReserveWeth) + uint256(sushiReserveWeth);
                    require(totalReserveWeth > 0, "Missing USDC liquidity");
                    uint256 uniWethIn = (wethToSell * uint256(uniReserveWeth)) / totalReserveWeth;
                    uint256 sushiWethIn = wethToSell - uniWethIn;

                    swapToken1ForToken0(
                        uniUsdcWethPair,
                        WETH_ADDR,
                        uniWethIn,
                        uint256(uniReserveWeth),
                        uint256(uniReserveUsdc)
                    );
                    swapToken1ForToken0(
                        sushiUsdcWethPair,
                        WETH_ADDR,
                        sushiWethIn,
                        uint256(sushiReserveWeth),
                        uint256(sushiReserveUsdc)
                    );

                    uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
                    if (usdcBalance > 0) {
                        IERC20(USDC).approve(CURVE_3POOL, 0);
                        IERC20(USDC).approve(CURVE_3POOL, usdcBalance);
                        ICurvePool(CURVE_3POOL).exchange(1, 2, usdcBalance, 0);
                    }
                }
            }
        }

        // 2.6 mixed repayment: return all USDT first, then top up with the minimum WETH
        (uint112 reserveWeth, uint112 reserveUsdt,) = wethUsdtPair.getReserves();
        uint256 usdtRepayment = IERC20(USDT).balanceOf(address(this));
        uint256 wethRepayment = getMinimumWethRepayment(
            uint256(reserveWeth),
            uint256(reserveUsdt),
            amount1,
            usdtRepayment
        );

        if (usdtRepayment > 0) {
            IERC20(USDT).transfer(address(wethUsdtPair), usdtRepayment);
        }
        if (wethRepayment > 0) {
            IERC20(WETH_ADDR).transfer(address(wethUsdtPair), wethRepayment);
        }
    }
}
