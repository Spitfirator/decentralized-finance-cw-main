//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

interface ILendingPool {
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

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

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);

    function approve(address spender, uint256 value) external;

    function transfer(address to, uint256 value) external;
}

interface IWETH is IERC20 {
    function withdraw(uint256) external;
}

interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface IUniswapV2Pair {
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

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

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

interface IQuoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

contract LiquidationOperator is IUniswapV2Callee {
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_V3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;

    uint256 constant FLASH_BORROW_USDT = 3763877732905;
    uint256 constant PRE_LIQUIDATION_USDT = 847499511221;
    uint256 constant UNI_FLASH_BORROW_BPS = 1275;
    uint256 constant DIRECT_USDC_TARGET_BPS = 1260;
    uint256 constant USDT_CONVERSION_TARGET_BPS = 6900;
    uint256 constant WBTC_WETH_V3_SPLIT_BPS = 4900;
    uint24 constant V3_FEE = 3000;

    IUniswapV2Pair immutable wethUsdtPair;
    IUniswapV2Pair immutable sushiWethUsdtPair;
    IUniswapV2Pair immutable wbtcWethPair;
    IUniswapV2Pair immutable sushiWbtcWethPair;
    IUniswapV2Pair immutable uniUsdcWethPair;
    IUniswapV2Pair immutable sushiUsdcWethPair;

    constructor() {
        address wethUsdt = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WETH_ADDR, USDT);
        address sushiWethUsdt = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WETH_ADDR, USDT);
        address uniWbtcWeth = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WBTC, WETH_ADDR);
        address sushiWbtcWeth = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WBTC, WETH_ADDR);
        address uniUsdcWeth = IUniswapV2Factory(UNISWAP_FACTORY).getPair(USDC, WETH_ADDR);
        address sushiUsdcWeth = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(USDC, WETH_ADDR);

        require(wethUsdt != address(0), "Missing WETH/USDT");
        require(sushiWethUsdt != address(0), "Missing Sushi WETH/USDT");
        require(uniWbtcWeth != address(0), "Missing Uni WBTC/WETH");
        require(sushiWbtcWeth != address(0), "Missing Sushi WBTC/WETH");
        require(uniUsdcWeth != address(0), "Missing Uni USDC/WETH");
        require(sushiUsdcWeth != address(0), "Missing Sushi USDC/WETH");

        wethUsdtPair = IUniswapV2Pair(wethUsdt);
        sushiWethUsdtPair = IUniswapV2Pair(sushiWethUsdt);
        wbtcWethPair = IUniswapV2Pair(uniWbtcWeth);
        sushiWbtcWethPair = IUniswapV2Pair(sushiWbtcWeth);
        uniUsdcWethPair = IUniswapV2Pair(uniUsdcWeth);
        sushiUsdcWethPair = IUniswapV2Pair(sushiUsdcWeth);
    }

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

    function combinedUsdtOut(
        uint256 wethIn,
        uint256 uniReserveUsdt,
        uint256 uniReserveWeth,
        uint256 sushiReserveUsdt,
        uint256 sushiReserveWeth
    ) internal pure returns (uint256 totalUsdtOut) {
        if (wethIn == 0) {
            return 0;
        }

        uint256 totalReserveWeth = uniReserveWeth + sushiReserveWeth;
        if (totalReserveWeth == 0) {
            return 0;
        }

        uint256 uniWethIn = (wethIn * uniReserveWeth) / totalReserveWeth;
        uint256 sushiWethIn = wethIn - uniWethIn;

        if (uniWethIn > 0 && uniReserveUsdt > 0 && uniReserveWeth > 0) {
            totalUsdtOut += getAmountOut(uniWethIn, uniReserveWeth, uniReserveUsdt);
        }
        if (sushiWethIn > 0 && sushiReserveUsdt > 0 && sushiReserveWeth > 0) {
            totalUsdtOut += getAmountOut(sushiWethIn, sushiReserveWeth, sushiReserveUsdt);
        }
    }

    function quoteCurveUsdcToUsdt(uint256 amountIn)
        internal
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            return 0;
        }

        return ICurvePool(CURVE_3POOL).get_dy(1, 2, amountIn);
    }

    function combinedUsdtOutViaUsdc(
        uint256 wethIn,
        uint256 uniReserveUsdc,
        uint256 uniReserveWeth,
        uint256 sushiReserveUsdc,
        uint256 sushiReserveWeth
    ) internal view returns (uint256 totalUsdtOut) {
        return
            quoteCurveUsdcToUsdt(
                combinedUsdcOut(
                    wethIn,
                    uniReserveUsdc,
                    uniReserveWeth,
                    sushiReserveUsdc,
                    sushiReserveWeth
                )
            );
    }

    function findWethInForTargetUsdtDirect(
        uint256 targetUsdtOut,
        uint256 maxWethIn,
        uint256 uniReserveUsdt,
        uint256 uniReserveWeth,
        uint256 sushiReserveUsdt,
        uint256 sushiReserveWeth
    ) internal pure returns (uint256 wethIn) {
        if (targetUsdtOut == 0) {
            return 0;
        }

        if (
            combinedUsdtOut(
                maxWethIn,
                uniReserveUsdt,
                uniReserveWeth,
                sushiReserveUsdt,
                sushiReserveWeth
            ) <= targetUsdtOut
        ) {
            return maxWethIn;
        }

        uint256 low = 0;
        uint256 high = maxWethIn;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (
                combinedUsdtOut(
                    mid,
                    uniReserveUsdt,
                    uniReserveWeth,
                    sushiReserveUsdt,
                    sushiReserveWeth
                ) >= targetUsdtOut
            ) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function findWethInForTargetUsdtViaUsdc(
        uint256 targetUsdtOut,
        uint256 maxWethIn,
        uint256 uniReserveUsdc,
        uint256 uniReserveWeth,
        uint256 sushiReserveUsdc,
        uint256 sushiReserveWeth
    ) internal view returns (uint256 wethIn) {
        if (targetUsdtOut == 0) {
            return 0;
        }

        if (
            combinedUsdtOutViaUsdc(
                maxWethIn,
                uniReserveUsdc,
                uniReserveWeth,
                sushiReserveUsdc,
                sushiReserveWeth
            ) <= targetUsdtOut
        ) {
            return maxWethIn;
        }

        uint256 low = 0;
        uint256 high = maxWethIn;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (
                combinedUsdtOutViaUsdc(
                    mid,
                    uniReserveUsdc,
                    uniReserveWeth,
                    sushiReserveUsdc,
                    sushiReserveWeth
                ) >= targetUsdtOut
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
        uint256 adjustedUsdtBalance =
            (reserveUsdt * 1000) - (borrowedUsdt * 1000) + (returnedUsdt * 997);
        uint256 minimumAdjustedWethBalance = ceilDiv(
            reserveWeth * reserveUsdt * 1000000,
            adjustedUsdtBalance
        );
        uint256 currentAdjustedWethBalance = reserveWeth * 1000;

        if (minimumAdjustedWethBalance <= currentAdjustedWethBalance) {
            return 0;
        }

        return ceilDiv(minimumAdjustedWethBalance - currentAdjustedWethBalance, 997);
    }

    function findMinimumUsdtRepayment(
        uint256 reserveWeth,
        uint256 reserveUsdt,
        uint256 borrowedUsdt,
        uint256 maxUsdtRepayment,
        uint256 availableWeth
    ) internal pure returns (uint256 usdtNeeded) {
        require(
            getMinimumWethRepayment(
                reserveWeth,
                reserveUsdt,
                borrowedUsdt,
                maxUsdtRepayment
            ) <= availableWeth,
            "Insufficient repayment assets"
        );

        uint256 low = 0;
        uint256 high = maxUsdtRepayment;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (
                getMinimumWethRepayment(
                    reserveWeth,
                    reserveUsdt,
                    borrowedUsdt,
                    mid
                ) <= availableWeth
            ) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function swapV3ExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        IERC20(tokenIn).approve(UNISWAP_V3_ROUTER, 0);
        IERC20(tokenIn).approve(UNISWAP_V3_ROUTER, amountIn);
        return
            ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: V3_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function quoteV3ExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        return
            IQuoter(UNISWAP_V3_QUOTER).quoteExactInputSingle(
                tokenIn,
                tokenOut,
                V3_FEE,
                amountIn,
                0
            );
    }

    function findWbtcInForTargetUsdcV3(
        uint256 targetUsdcOut,
        uint256 maxWbtcIn
    ) internal returns (uint256 wbtcIn) {
        if (targetUsdcOut == 0) {
            return 0;
        }

        if (quoteV3ExactInputSingle(WBTC, USDC, maxWbtcIn) <= targetUsdcOut) {
            return maxWbtcIn;
        }

        uint256 low = 0;
        uint256 high = maxWbtcIn;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (quoteV3ExactInputSingle(WBTC, USDC, mid) >= targetUsdcOut) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function swapWbtcToWethHybrid(uint256 totalWbtcIn) internal {
        if (totalWbtcIn == 0) {
            return;
        }

        uint256 v3WbtcIn = (totalWbtcIn * WBTC_WETH_V3_SPLIT_BPS) / 10000;
        uint256 v2WbtcIn = totalWbtcIn - v3WbtcIn;

        swapV3ExactInputSingle(WBTC, WETH_ADDR, v3WbtcIn);

        if (v2WbtcIn == 0) {
            return;
        }

        (uint112 uniReserveWbtc, uint112 uniReserveWeth,) = wbtcWethPair.getReserves();
        (uint112 sushiReserveWbtc, uint112 sushiReserveWeth,) = sushiWbtcWethPair.getReserves();
        uint256 totalReserveWbtc = uint256(uniReserveWbtc) + uint256(sushiReserveWbtc);
        require(totalReserveWbtc > 0, "Missing WBTC/WETH liquidity");

        uint256 uniWbtcIn = (v2WbtcIn * uint256(uniReserveWbtc)) / totalReserveWbtc;
        uint256 sushiWbtcIn = v2WbtcIn - uniWbtcIn;

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

    function swapWethToUsdtDirect(uint256 wethToSell) internal {
        if (wethToSell == 0) {
            return;
        }

        (uint112 uniReserveWeth, uint112 uniReserveUsdt,) = wethUsdtPair.getReserves();
        (uint112 sushiReserveWeth, uint112 sushiReserveUsdt,) = sushiWethUsdtPair.getReserves();
        uint256 totalReserveWeth = uint256(uniReserveWeth) + uint256(sushiReserveWeth);
        require(totalReserveWeth > 0, "Missing USDT liquidity");

        uint256 uniWethIn = (wethToSell * uint256(uniReserveWeth)) / totalReserveWeth;
        uint256 sushiWethIn = wethToSell - uniWethIn;

        swapToken0ForToken1(
            wethUsdtPair,
            WETH_ADDR,
            uniWethIn,
            uint256(uniReserveWeth),
            uint256(uniReserveUsdt)
        );
        swapToken0ForToken1(
            sushiWethUsdtPair,
            WETH_ADDR,
            sushiWethIn,
            uint256(sushiReserveWeth),
            uint256(sushiReserveUsdt)
        );
    }

    function swapWethToUsdtViaUsdc(uint256 wethToSell) internal {
        if (wethToSell == 0) {
            return;
        }

        (uint112 uniReserveUsdc, uint112 uniReserveWeth,) = uniUsdcWethPair.getReserves();
        (uint112 sushiReserveUsdc, uint112 sushiReserveWeth,) = sushiUsdcWethPair.getReserves();
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

    function coverUsdtShortfallWithBestRoute(uint256 targetUsdtOut, uint256 wethBalance) internal {
        if (targetUsdtOut == 0 || wethBalance == 0) {
            return;
        }

        (uint112 uniReserveUsdc, uint112 uniReserveWeth,) = uniUsdcWethPair.getReserves();
        (uint112 sushiReserveUsdc, uint112 sushiReserveWeth,) = sushiUsdcWethPair.getReserves();
        (uint112 uniReserveWethUsdt, uint112 uniReserveUsdt,) = wethUsdtPair.getReserves();
        (uint112 sushiReserveWethUsdt, uint112 sushiReserveUsdt,) = sushiWethUsdtPair.getReserves();

        uint256 wethToSellViaUsdc = findWethInForTargetUsdtViaUsdc(
            targetUsdtOut,
            wethBalance,
            uint256(uniReserveUsdc),
            uint256(uniReserveWeth),
            uint256(sushiReserveUsdc),
            uint256(sushiReserveWeth)
        );
        uint256 wethToSellDirect = findWethInForTargetUsdtDirect(
            targetUsdtOut,
            wethBalance,
            uint256(uniReserveUsdt),
            uint256(uniReserveWethUsdt),
            uint256(sushiReserveUsdt),
            uint256(sushiReserveWethUsdt)
        );

        if (wethToSellDirect > 0 && (wethToSellViaUsdc == 0 || wethToSellDirect < wethToSellViaUsdc)) {
            swapWethToUsdtDirect(wethToSellDirect);
            return;
        }

        swapWethToUsdtViaUsdc(wethToSellViaUsdc);
    }

    function cleanupUsdtToWeth() internal {
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (usdtBalance == 0) {
            return;
        }

        (uint112 uniReserveWeth, uint112 uniReserveUsdt,) = wethUsdtPair.getReserves();
        (uint112 sushiReserveWeth, uint112 sushiReserveUsdt,) = sushiWethUsdtPair.getReserves();
        uint256 totalReserveUsdt = uint256(uniReserveUsdt) + uint256(sushiReserveUsdt);
        require(totalReserveUsdt > 0, "Missing USDT cleanup liquidity");

        uint256 uniUsdtIn = (usdtBalance * uint256(uniReserveUsdt)) / totalReserveUsdt;
        uint256 sushiUsdtIn = usdtBalance - uniUsdtIn;

        swapToken1ForToken0(
            wethUsdtPair,
            USDT,
            uniUsdtIn,
            uint256(uniReserveUsdt),
            uint256(uniReserveWeth)
        );
        swapToken1ForToken0(
            sushiWethUsdtPair,
            USDT,
            sushiUsdtIn,
            uint256(sushiReserveUsdt),
            uint256(sushiReserveWeth)
        );
    }

    function executePreLiquidation(ILendingPool lendingPool) internal {
        (,,,,,uint256 healthFactorCurrent) = lendingPool.getUserAccountData(TARGET_USER);
        if (healthFactorCurrent >= 1e18) {
            return;
        }

        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (usdtBalance == 0) {
            return;
        }

        uint256 preLiquidationUsdt = PRE_LIQUIDATION_USDT;
        if (preLiquidationUsdt > usdtBalance) {
            preLiquidationUsdt = usdtBalance;
        }

        lendingPool.liquidationCall(
            WETH_ADDR,
            USDT,
            TARGET_USER,
            preLiquidationUsdt,
            false
        );
    }

    function executeLiquidationAndSwaps(uint256 totalUsdtRepayment) internal {
        IERC20(USDT).approve(AAVE_LENDING_POOL, 0);
        IERC20(USDT).approve(AAVE_LENDING_POOL, type(uint256).max);

        ILendingPool lendingPool = ILendingPool(AAVE_LENDING_POOL);
        executePreLiquidation(lendingPool);

        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (usdtBalance > 0) {
            lendingPool.liquidationCall(
                WBTC,
                USDT,
                TARGET_USER,
                usdtBalance,
                false
            );
        }

        uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
        uint256 targetDirectUsdcOut =
            (totalUsdtRepayment * DIRECT_USDC_TARGET_BPS) / 10000;
        uint256 wbtcToUsdc = findWbtcInForTargetUsdcV3(
            targetDirectUsdcOut,
            wbtcBalance
        );
        uint256 wbtcToWeth = wbtcBalance - wbtcToUsdc;

        swapV3ExactInputSingle(WBTC, USDC, wbtcToUsdc);
        swapWbtcToWethHybrid(wbtcToWeth);

        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        if (usdcBalance > 0) {
            IERC20(USDC).approve(CURVE_3POOL, 0);
            IERC20(USDC).approve(CURVE_3POOL, usdcBalance);
            ICurvePool(CURVE_3POOL).exchange(1, 2, usdcBalance, 0);
        }

        usdtBalance = IERC20(USDT).balanceOf(address(this));
        uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));
        if (usdtBalance < totalUsdtRepayment && wethBalance > 0) {
            uint256 usdtShortfall = totalUsdtRepayment - usdtBalance;
            uint256 targetUsdtOut =
                ((usdtShortfall * USDT_CONVERSION_TARGET_BPS) / 10000) + 1;
            coverUsdtShortfallWithBestRoute(targetUsdtOut, wethBalance);
        }
    }

    function repayFlashPair(IUniswapV2Pair pair, uint256 borrowedUsdt) internal {
        (uint112 reserveWeth, uint112 reserveUsdt,) = pair.getReserves();
        uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
        uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));

        uint256 minimumUsdtRepayment = findMinimumUsdtRepayment(
            uint256(reserveWeth),
            uint256(reserveUsdt),
            borrowedUsdt,
            usdtBalance,
            wethBalance
        );

        uint256 usdtRepayment = usdtBalance;
        if (usdtRepayment < minimumUsdtRepayment) {
            usdtRepayment = minimumUsdtRepayment;
        }

        uint256 wethRepayment = getMinimumWethRepayment(
            uint256(reserveWeth),
            uint256(reserveUsdt),
            borrowedUsdt,
            usdtRepayment
        );

        if (usdtRepayment > 0) {
            IERC20(USDT).transfer(address(pair), usdtRepayment);
        }
        if (wethRepayment > 0) {
            IERC20(WETH_ADDR).transfer(address(pair), wethRepayment);
        }
    }

    receive() external payable {}

    function operate() external {
        (,,,,,uint256 healthFactor) = ILendingPool(AAVE_LENDING_POOL).getUserAccountData(TARGET_USER);
        require(healthFactor < 1e18, "Target user is not liquidatable");

        uint256 uniBorrow = (FLASH_BORROW_USDT * UNI_FLASH_BORROW_BPS) / 10000;
        uint256 sushiBorrow = FLASH_BORROW_USDT - uniBorrow;

        if (uniBorrow <= sushiBorrow) {
            wethUsdtPair.swap(0, uniBorrow, address(this), abi.encode(sushiBorrow));
        } else {
            sushiWethUsdtPair.swap(0, sushiBorrow, address(this), abi.encode(uniBorrow));
        }

        cleanupUsdtToWeth();

        uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));
        IWETH(WETH_ADDR).withdraw(wethBalance);
        payable(msg.sender).transfer(address(this).balance);
    }

    function uniswapV2Call(
        address sender,
        uint256,
        uint256 amount1,
        bytes calldata data
    ) external override {
        require(sender == address(this), "Invalid sender");

        if (msg.sender == address(sushiWethUsdtPair)) {
            if (data.length == 32) {
                uint256 uniBorrow = abi.decode(data, (uint256));
                wethUsdtPair.swap(0, uniBorrow, address(this), bytes("inner"));
            } else {
                executeLiquidationAndSwaps(IERC20(USDT).balanceOf(address(this)));
            }
            repayFlashPair(sushiWethUsdtPair, amount1);
            return;
        }

        if (msg.sender == address(wethUsdtPair)) {
            if (data.length == 32) {
                uint256 sushiBorrow = abi.decode(data, (uint256));
                sushiWethUsdtPair.swap(0, sushiBorrow, address(this), bytes("inner"));
            } else {
                executeLiquidationAndSwaps(IERC20(USDT).balanceOf(address(this)));
            }
            repayFlashPair(wethUsdtPair, amount1);
            return;
        }

        revert("Unauthorized");
    }
}
