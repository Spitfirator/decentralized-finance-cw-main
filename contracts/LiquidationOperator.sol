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

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
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

library DydxAccount {
    struct Info {
        address owner;
        uint256 number;
    }
}

library DydxTypes {
    enum AssetDenomination {
        Wei,
        Par
    }

    enum AssetReference {
        Delta,
        Target
    }

    struct AssetAmount {
        bool sign;
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }
}

library DydxActions {
    enum ActionType {
        Deposit,
        Withdraw,
        Transfer,
        Buy,
        Sell,
        Trade,
        Liquidate,
        Vaporize,
        Call
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        DydxTypes.AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }
}

interface ISoloMargin {
    function operate(
        DydxAccount.Info[] calldata accounts,
        DydxActions.ActionArgs[] calldata actions
    ) external;
}

interface ICallee {
    function callFunction(
        address sender,
        DydxAccount.Info calldata accountInfo,
        bytes calldata data
    ) external;
}

// ----------------------IMPLEMENTATION------------------------------

contract BaseLiquidationOperator is IUniswapV2Callee, ICallee, IFlashLoanReceiver {
    uint8 public constant health_factor_decimals = 18;

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
    address constant DYDX_SOLO_MARGIN = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
    address constant TARGET_USER = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    uint256 constant FIRST_LIQUIDATION_USDT = 2916378221684;
    uint24 constant V3_FEE = 3000;
    uint256 constant DYDX_USDC_MARKET_ID = 2;
    uint256 constant DYDX_FLASH_FEE = 2;
    uint256 constant CURVE_USDC_BUFFER = 10000000;

    uint256 flashBorrowUsdt;
    uint256 maxLiquidationSteps;
    uint256 uniFlashBorrowBps;
    uint256 usdtConversionTargetBps;
    uint256 usdtRepaymentBps;
    uint256 directUsdcTargetBps;
    uint256 flashSourceMode;
    uint256 wbtcWethV3SplitBps;

    IUniswapV2Pair immutable wethUsdtPair;
    IUniswapV2Pair immutable sushiWethUsdtPair;
    IUniswapV2Pair immutable wbtcWethPair;
    IUniswapV2Pair immutable sushiWbtcWethPair;
    IUniswapV2Pair immutable uniWbtcUsdcPair;
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

    constructor() {
        address wethUsdt = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WETH_ADDR, USDT);
        address sushiWethUsdt = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WETH_ADDR, USDT);
        address uniWbtcWeth = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WBTC, WETH_ADDR);
        address sushiWbtcWeth = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(WBTC, WETH_ADDR);
        address uniWbtcUsdt = IUniswapV2Factory(UNISWAP_FACTORY).getPair(WBTC, USDT);
        address uniUsdcWeth = IUniswapV2Factory(UNISWAP_FACTORY).getPair(USDC, WETH_ADDR);
        address sushiUsdcWeth = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(USDC, WETH_ADDR);

        require(wethUsdt != address(0), "Missing WETH/USDT");
        require(sushiWethUsdt != address(0), "Missing Sushi WETH/USDT");
        require(uniWbtcWeth != address(0), "Missing Uni WBTC/WETH");
        require(sushiWbtcWeth != address(0), "Missing Sushi WBTC/WETH");
        require(uniWbtcUsdt != address(0), "Missing WBTC/USDT");
        require(uniUsdcWeth != address(0), "Missing Uni USDC/WETH");
        require(sushiUsdcWeth != address(0), "Missing Sushi USDC/WETH");

        wethUsdtPair = IUniswapV2Pair(wethUsdt);
        sushiWethUsdtPair = IUniswapV2Pair(sushiWethUsdt);
        wbtcWethPair = IUniswapV2Pair(uniWbtcWeth);
        sushiWbtcWethPair = IUniswapV2Pair(sushiWbtcWeth);
        uniWbtcUsdcPair = IUniswapV2Pair(uniWbtcUsdt);
        uniUsdcWethPair = IUniswapV2Pair(uniUsdcWeth);
        sushiUsdcWethPair = IUniswapV2Pair(sushiUsdcWeth);
    }

    function _setStrategy(
        uint256 flashBorrowBps,
        uint256 liquidationSteps,
        uint256 uniFlashBorrow,
        uint256 usdtConversionTarget,
        uint256 usdtRepayment,
        uint256 directUsdcTarget,
        uint256 sourceMode,
        uint256 wbtcWethV3Split
    ) internal {
        flashBorrowUsdt = (FIRST_LIQUIDATION_USDT * flashBorrowBps) / 10000;
        maxLiquidationSteps = liquidationSteps;
        uniFlashBorrowBps = uniFlashBorrow;
        usdtConversionTargetBps = usdtConversionTarget;
        usdtRepaymentBps = usdtRepayment;
        directUsdcTargetBps = directUsdcTarget;
        flashSourceMode = sourceMode;
        wbtcWethV3SplitBps = wbtcWethV3Split;
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
        amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
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

        amountOut = IQuoter(UNISWAP_V3_QUOTER).quoteExactInputSingle(
            tokenIn,
            tokenOut,
            V3_FEE,
            amountIn,
            0
        );
    }

    function findWethInForTargetUsdcV3(
        uint256 targetUsdcOut,
        uint256 maxWethIn
    ) internal returns (uint256 wethIn) {
        if (targetUsdcOut == 0) {
            return 0;
        }

        if (quoteV3ExactInputSingle(WETH_ADDR, USDC, maxWethIn) <= targetUsdcOut) {
            return maxWethIn;
        }

        uint256 low = 0;
        uint256 high = maxWethIn;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (quoteV3ExactInputSingle(WETH_ADDR, USDC, mid) >= targetUsdcOut) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
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

    function quoteCurveUsdcToUsdt(uint256 amountIn)
        internal
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            return 0;
        }

        amountOut = ICurvePool(CURVE_3POOL).get_dy(1, 2, amountIn);
    }

    function findUsdcInForTargetUsdtCurve(uint256 targetUsdtOut)
        internal
        view
        returns (uint256 usdcIn)
    {
        if (targetUsdtOut == 0) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = targetUsdtOut;
        while (quoteCurveUsdcToUsdt(high) < targetUsdtOut) {
            high *= 2;
        }

        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (quoteCurveUsdcToUsdt(mid) >= targetUsdtOut) {
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

        uint256 v3WbtcIn = (totalWbtcIn * wbtcWethV3SplitBps) / 10000;
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

    function cleanupUsdcToWeth() internal {
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        if (usdcBalance == 0) {
            return;
        }

        (uint112 uniReserveUsdc, uint112 uniReserveWeth,) = uniUsdcWethPair.getReserves();
        (uint112 sushiReserveUsdc, uint112 sushiReserveWeth,) = sushiUsdcWethPair.getReserves();
        uint256 totalReserveUsdc = uint256(uniReserveUsdc) + uint256(sushiReserveUsdc);
        require(totalReserveUsdc > 0, "Missing cleanup liquidity");

        uint256 uniUsdcIn = (usdcBalance * uint256(uniReserveUsdc)) / totalReserveUsdc;
        uint256 sushiUsdcIn = usdcBalance - uniUsdcIn;

        swapToken0ForToken1(
            uniUsdcWethPair,
            USDC,
            uniUsdcIn,
            uint256(uniReserveUsdc),
            uint256(uniReserveWeth)
        );
        swapToken0ForToken1(
            sushiUsdcWethPair,
            USDC,
            sushiUsdcIn,
            uint256(sushiReserveUsdc),
            uint256(sushiReserveWeth)
        );
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

    function executeLiquidationAndSwaps(
        uint256,
        uint256 totalUsdtRepayment
    ) internal {
        IERC20(USDT).approve(AAVE_LENDING_POOL, 0);
        IERC20(USDT).approve(AAVE_LENDING_POOL, type(uint256).max);

        ILendingPool lendingPool = ILendingPool(AAVE_LENDING_POOL);

        // Aave V2 caps each liquidation step. Keep liquidating while the position
        // remains under water and the contract still holds repayable USDT.
        for (uint256 i = 0; i < maxLiquidationSteps; i++) {
            (,,,,,uint256 healthFactorCurrent) = lendingPool.getUserAccountData(TARGET_USER);
            if (healthFactorCurrent >= 1e18) {
                break;
            }

            uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
            if (usdtBalance == 0) {
                break;
            }

            uint256 usdtBefore = usdtBalance;
            lendingPool.liquidationCall(WBTC, USDT, TARGET_USER, usdtBalance, false);
            uint256 usdtAfter = IERC20(USDT).balanceOf(address(this));
            if (usdtAfter >= usdtBefore) {
                break;
            }
        }

        // Split the liquidated WBTC across direct USDC and WETH routes on Uniswap V3.
        {
            uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
            uint256 stableRepaymentTarget = totalUsdtRepayment;
            if (flashSourceMode == 2) {
                stableRepaymentTarget = findUsdcInForTargetUsdtCurve(totalUsdtRepayment);
            }
            uint256 targetDirectUsdcOut =
                ((stableRepaymentTarget * directUsdcTargetBps) / 10000);
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
        }

        // Convert any residual shortfall through WETH -> USDC -> USDT.
        {
            uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
            uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));
            if (usdtBalance < totalUsdtRepayment && wethBalance > 0) {
                uint256 usdtShortfall = totalUsdtRepayment - usdtBalance;
                uint256 targetUsdcOut;
                if (flashSourceMode == 2) {
                    targetUsdcOut = findUsdcInForTargetUsdtCurve(usdtShortfall);
                } else {
                    targetUsdcOut =
                        ((usdtShortfall * usdtConversionTargetBps) / 10000) + 1;
                }

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
    }

    function executeLiquidationAndSwapsForUsdcRepayment(
        uint256,
        uint256 totalUsdcRepayment
    ) internal {
        IERC20(USDT).approve(AAVE_LENDING_POOL, 0);
        IERC20(USDT).approve(AAVE_LENDING_POOL, type(uint256).max);

        ILendingPool lendingPool = ILendingPool(AAVE_LENDING_POOL);

        for (uint256 i = 0; i < maxLiquidationSteps; i++) {
            (,,,,,uint256 healthFactorCurrent) = lendingPool.getUserAccountData(TARGET_USER);
            if (healthFactorCurrent >= 1e18) {
                break;
            }

            uint256 usdtBalance = IERC20(USDT).balanceOf(address(this));
            if (usdtBalance == 0) {
                break;
            }

            uint256 usdtBefore = usdtBalance;
            lendingPool.liquidationCall(WBTC, USDT, TARGET_USER, usdtBalance, false);
            uint256 usdtAfter = IERC20(USDT).balanceOf(address(this));
            if (usdtAfter >= usdtBefore) {
                break;
            }
        }

        {
            uint256 wbtcBalance = IERC20(WBTC).balanceOf(address(this));
            uint256 targetDirectUsdcOut =
                ((totalUsdcRepayment * directUsdcTargetBps) / 10000);
            uint256 wbtcToUsdc = findWbtcInForTargetUsdcV3(
                targetDirectUsdcOut,
                wbtcBalance
            );
            uint256 wbtcToWeth = wbtcBalance - wbtcToUsdc;

            swapV3ExactInputSingle(WBTC, USDC, wbtcToUsdc);
            swapWbtcToWethHybrid(wbtcToWeth);
        }

        {
            uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
            uint256 wethBalance = IERC20(WETH_ADDR).balanceOf(address(this));
            if (usdcBalance < totalUsdcRepayment && wethBalance > 0) {
                uint256 usdcShortfall = totalUsdcRepayment - usdcBalance;
                uint256 targetUsdcOut =
                    ((usdcShortfall * usdtConversionTargetBps) / 10000) + 1;

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
                }
            }
        }
    }

    function getDydxAccountInfo()
        internal
        view
        returns (DydxAccount.Info memory)
    {
        return DydxAccount.Info({owner: address(this), number: 1});
    }

    function getDydxWithdrawAction(uint256 marketId, uint256 amount)
        internal
        view
        returns (DydxActions.ActionArgs memory)
    {
        return
            DydxActions.ActionArgs({
                actionType: DydxActions.ActionType.Withdraw,
                accountId: 0,
                amount: DydxTypes.AssetAmount({
                    sign: false,
                    denomination: DydxTypes.AssetDenomination.Wei,
                    ref: DydxTypes.AssetReference.Delta,
                    value: amount
                }),
                primaryMarketId: marketId,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: bytes("")
            });
    }

    function getDydxCallAction(bytes memory data)
        internal
        view
        returns (DydxActions.ActionArgs memory)
    {
        return
            DydxActions.ActionArgs({
                actionType: DydxActions.ActionType.Call,
                accountId: 0,
                amount: DydxTypes.AssetAmount({
                    sign: false,
                    denomination: DydxTypes.AssetDenomination.Wei,
                    ref: DydxTypes.AssetReference.Delta,
                    value: 0
                }),
                primaryMarketId: 0,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: data
            });
    }

    function getDydxDepositAction(uint256 marketId, uint256 amount)
        internal
        view
        returns (DydxActions.ActionArgs memory)
    {
        return
            DydxActions.ActionArgs({
                actionType: DydxActions.ActionType.Deposit,
                accountId: 0,
                amount: DydxTypes.AssetAmount({
                    sign: true,
                    denomination: DydxTypes.AssetDenomination.Wei,
                    ref: DydxTypes.AssetReference.Delta,
                    value: amount
                }),
                primaryMarketId: marketId,
                secondaryMarketId: 0,
                otherAddress: address(this),
                otherAccountId: 0,
                data: bytes("")
            });
    }

    function executeDydxUsdcFlashLoan(uint256 liquidationUsdt) internal {
        uint256 borrowedUsdc =
            findUsdcInForTargetUsdtCurve(liquidationUsdt) + CURVE_USDC_BUFFER;
        uint256 repayUsdc = borrowedUsdc + DYDX_FLASH_FEE;

        IERC20(USDC).approve(DYDX_SOLO_MARGIN, 0);
        IERC20(USDC).approve(DYDX_SOLO_MARGIN, type(uint256).max);

        DydxAccount.Info[] memory accounts = new DydxAccount.Info[](1);
        accounts[0] = getDydxAccountInfo();

        DydxActions.ActionArgs[] memory actions = new DydxActions.ActionArgs[](3);
        actions[0] = getDydxWithdrawAction(DYDX_USDC_MARKET_ID, borrowedUsdc);
        actions[1] = getDydxCallAction(abi.encode(borrowedUsdc, liquidationUsdt, repayUsdc));
        actions[2] = getDydxDepositAction(DYDX_USDC_MARKET_ID, repayUsdc);

        ISoloMargin(DYDX_SOLO_MARGIN).operate(accounts, actions);
    }

    function executeAaveUsdtFlashLoan(uint256 liquidationUsdt) internal {
        address[] memory assets = new address[](1);
        assets[0] = USDT;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = liquidationUsdt;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        ILendingPool(AAVE_LENDING_POOL).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            bytes(""),
            0
        );
    }

    function repayFlashPair(IUniswapV2Pair pair, uint256 borrowedUsdt) internal {
        (uint112 reserveWeth, uint112 reserveUsdt,) = pair.getReserves();
        uint256 usdtBalanceForRepayment = IERC20(USDT).balanceOf(address(this));
        uint256 wethBalanceForRepayment = IERC20(WETH_ADDR).balanceOf(address(this));
        uint256 minimumUsdtRepayment = findMinimumUsdtRepayment(
            uint256(reserveWeth),
            uint256(reserveUsdt),
            borrowedUsdt,
            usdtBalanceForRepayment,
            wethBalanceForRepayment
        );
        uint256 preferredUsdtRepayment =
            (usdtBalanceForRepayment * usdtRepaymentBps) / 10000;
        uint256 usdtRepayment = preferredUsdtRepayment;
        if (usdtRepayment < minimumUsdtRepayment) {
            usdtRepayment = minimumUsdtRepayment;
        }
        if (usdtRepayment > usdtBalanceForRepayment) {
            usdtRepayment = usdtBalanceForRepayment;
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

    // required by the testing script, entry for your liquidation call
    function operate() external {
        // 1. get the target user account data & make sure it is liquidatable
        (,,,,,uint256 healthFactor) = ILendingPool(AAVE_LENDING_POOL).getUserAccountData(TARGET_USER);
        require(healthFactor < 1e18, "Target user is not liquidatable");

        if (flashSourceMode == 1) {
            executeDydxUsdcFlashLoan(flashBorrowUsdt);
            cleanupUsdcToWeth();
            cleanupUsdtToWeth();

            uint256 wethBalanceDydx = IERC20(WETH_ADDR).balanceOf(address(this));
            IWETH(WETH_ADDR).withdraw(wethBalanceDydx);
            payable(msg.sender).transfer(address(this).balance);
            return;
        }

        if (flashSourceMode == 2) {
            executeAaveUsdtFlashLoan(flashBorrowUsdt);
            cleanupUsdcToWeth();
            cleanupUsdtToWeth();

            uint256 wethBalanceAave = IERC20(WETH_ADDR).balanceOf(address(this));
            IWETH(WETH_ADDR).withdraw(wethBalanceAave);
            payable(msg.sender).transfer(address(this).balance);
            return;
        }

        // 2. split the flash borrow across Sushi and Uniswap WETH/USDT pools
        (uint112 uniReserveWeth,,) = wethUsdtPair.getReserves();
        (uint112 sushiReserveWeth,,) = sushiWethUsdtPair.getReserves();
        require(uniReserveWeth > 0 && sushiReserveWeth > 0, "Missing flash liquidity");
        uint256 uniBorrow = (flashBorrowUsdt * uniFlashBorrowBps) / 10000;
        uint256 sushiBorrow = flashBorrowUsdt - uniBorrow;

        // token0=WETH, token1=USDT; borrow USDT so amount0Out=0, amount1Out=amount
        if (sushiBorrow > 0) {
            sushiWethUsdtPair.swap(0, sushiBorrow, address(this), abi.encode(uniBorrow));
        } else {
            wethUsdtPair.swap(0, uniBorrow, address(this), bytes("inner"));
        }

        cleanupUsdcToWeth();
        cleanupUsdtToWeth();

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
        bytes calldata data
    ) external override {
        // 2.0. security checks
        require(sender == address(this), "Invalid sender");
        if (msg.sender == address(sushiWethUsdtPair)) {
            uint256 uniBorrow = abi.decode(data, (uint256));
            if (uniBorrow > 0) {
                wethUsdtPair.swap(0, uniBorrow, address(this), bytes("inner"));
            } else {
                executeLiquidationAndSwaps(amount1, amount1);
            }
            repayFlashPair(sushiWethUsdtPair, amount1);
            return;
        }

        if (msg.sender == address(wethUsdtPair)) {
            uint256 borrowedUsdt = IERC20(USDT).balanceOf(address(this));
            executeLiquidationAndSwaps(borrowedUsdt, borrowedUsdt);
            repayFlashPair(wethUsdtPair, amount1);
            return;
        }

        revert("Unauthorized");
    }

    function callFunction(
        address sender,
        DydxAccount.Info calldata,
        bytes calldata data
    ) external override {
        require(msg.sender == DYDX_SOLO_MARGIN, "Unauthorized lender");
        require(sender == address(this), "Invalid sender");

        (uint256 borrowedUsdc, uint256 liquidationUsdt, uint256 repayUsdc) = abi
            .decode(data, (uint256, uint256, uint256));

        IERC20(USDC).approve(CURVE_3POOL, 0);
        IERC20(USDC).approve(CURVE_3POOL, borrowedUsdc);
        ICurvePool(CURVE_3POOL).exchange(1, 2, borrowedUsdc, 0);
        require(
            IERC20(USDT).balanceOf(address(this)) >= liquidationUsdt,
            "Insufficient liquidation USDT"
        );

        executeLiquidationAndSwapsForUsdcRepayment(liquidationUsdt, repayUsdc);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external override returns (bool) {
        require(msg.sender == AAVE_LENDING_POOL, "Unauthorized lender");
        require(initiator == address(this), "Invalid initiator");
        require(assets.length == 1 && assets[0] == USDT, "Unexpected asset");

        uint256 repayUsdt = amounts[0] + premiums[0];
        executeLiquidationAndSwaps(amounts[0], repayUsdt);
        require(
            IERC20(USDT).balanceOf(address(this)) >= repayUsdt,
            "Insufficient Aave repayment"
        );

        IERC20(USDT).approve(AAVE_LENDING_POOL, 0);
        IERC20(USDT).approve(AAVE_LENDING_POOL, repayUsdt);
        return true;
    }
}

contract LiquidationOperator is BaseLiquidationOperator {
    constructor() {
        _setStrategy(10000, 1, 0, 6740, 10000, 1390, 0, 4950);
    }

    function configureStrategy(
        uint256 flashBorrowBps,
        uint256 liquidationSteps,
        uint256 uniFlashBorrow,
        uint256 usdtConversionTarget,
        uint256 usdtRepayment,
        uint256 directUsdcTarget,
        uint256 sourceMode,
        uint256 wbtcWethV3Split
    ) external {
        _setStrategy(
            flashBorrowBps,
            liquidationSteps,
            uniFlashBorrow,
            usdtConversionTarget,
            usdtRepayment,
            directUsdcTarget,
            sourceMode,
            wbtcWethV3Split
        );
    }
}
