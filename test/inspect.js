const { network, ethers } = require("hardhat");

const DATA_PROVIDER = "0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d";
const LENDING_POOL = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";
const USER = "0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F";
const UNISWAP_FACTORY = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const SUSHISWAP_FACTORY = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac";
const CURVE_ADDRESS_PROVIDER = "0x0000000022D53366457F9d5E68Ec105046FC4383";
const UNISWAP_V3_FACTORY = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
const UNISWAP_V3_QUOTER = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";

const ASSETS = {
  USDT: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  DAI: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
  WBTC: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
  WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  UNI: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",
  AAVE: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9",
};

const PAIRS = {
  uniWethUsdt: "0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852",
  uniWbtcWeth: "0xBb2b8038a1640196FbE3e38816F3e67Cba72D940",
  sushiWbtcWeth: "0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58",
  uniWbtcUsdc: "0x004375Dff511095CC5A197A54140a24eFEF3A416",
  uniWbtcUsdt: "0x0DE0Fa91b6DbaB8c8503aAA2D1DFa91a192cB149",
  uniUsdcWeth: "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc",
  sushiUsdcWeth: "0x397FF1542f962076d0BFE58eA045FfA2d347ACa0",
  sushiWethUsdt: "0x06da0fd433C1A5d7a4faa01111c044910A184553",
};

const TOKEN_WHALES = {
  USDT: PAIRS.uniWethUsdt,
  USDC: PAIRS.sushiUsdcWeth,
  WBTC: PAIRS.sushiWbtcWeth,
};

async function resetFork() {
  await network.provider.request({
    method: "hardhat_reset",
    params: [{
      forking: {
        jsonRpcUrl: process.env.ALCHE_API,
        blockNumber: 12489619,
      }
    }]
  });
}

async function fundLiquidator(tokenAddress, whaleAddress, amount) {
  await network.provider.send("hardhat_setBalance", [
    whaleAddress,
    "0x3635C9ADC5DEA00000",
  ]);
  await network.provider.send("hardhat_impersonateAccount", [whaleAddress]);
  const whale = await ethers.getSigner(whaleAddress);
  const token = await ethers.getContractAt([
    "function transfer(address to,uint256 amount) external returns (bool)"
  ], tokenAddress);
  const [liquidator] = await ethers.getSigners();
  await token.connect(whale).transfer(liquidator.address, amount);
  await network.provider.send("hardhat_stopImpersonatingAccount", [whaleAddress]);
  return liquidator;
}

async function getHealthFactor() {
  const accountDataInterface = new ethers.utils.Interface([
    "function getUserAccountData(address user) view returns (uint256,uint256,uint256,uint256,uint256,uint256)"
  ]);
  const raw = await network.provider.send("eth_call", [{
    to: LENDING_POOL,
    data: accountDataInterface.encodeFunctionData("getUserAccountData", [USER]),
    gasPrice: "0x0",
  }, "latest"]);
  return accountDataInterface.decodeFunctionResult("getUserAccountData", raw)[5].toString();
}

async function getPairFromFactory(factoryAddress, tokenA, tokenB) {
  const factoryInterface = new ethers.utils.Interface([
    "function getPair(address tokenA,address tokenB) view returns (address)"
  ]);
  const raw = await network.provider.send("eth_call", [{
    to: factoryAddress,
    data: factoryInterface.encodeFunctionData("getPair", [tokenA, tokenB]),
    gasPrice: "0x0",
  }, "latest"]);
  return factoryInterface.decodeFunctionResult("getPair", raw)[0];
}

async function runLiquidationCase({ debtAsset, collateralAsset, fundAmount }) {
  const debtToken = await ethers.getContractAt([
    "function approve(address spender,uint256 amount) external",
    "function balanceOf(address account) view returns (uint256)"
  ], ASSETS[debtAsset]);
  const collateralToken = await ethers.getContractAt([
    "function balanceOf(address account) view returns (uint256)"
  ], ASSETS[collateralAsset]);
  const lendingPool = await ethers.getContractAt([
    "function liquidationCall(address collateralAsset,address debtAsset,address user,uint256 debtToCover,bool receiveAToken) external"
  ], LENDING_POOL);

  const liquidator = await fundLiquidator(
    ASSETS[debtAsset],
    TOKEN_WHALES[debtAsset],
    fundAmount
  );

  await debtToken.connect(liquidator).approve(LENDING_POOL, ethers.constants.MaxUint256);
  const collateralBefore = await collateralToken.balanceOf(liquidator.address);
  const debtBefore = await debtToken.balanceOf(liquidator.address);
  await lendingPool.connect(liquidator).liquidationCall(
    ASSETS[collateralAsset],
    ASSETS[debtAsset],
    USER,
    ethers.constants.MaxUint256,
    false,
    { gasPrice: 0 }
  );
  const collateralAfter = await collateralToken.balanceOf(liquidator.address);
  const debtAfter = await debtToken.balanceOf(liquidator.address);

  return {
    debtSpent: debtBefore.sub(debtAfter).toString(),
    collateralReceived: collateralAfter.sub(collateralBefore).toString(),
    healthFactor: await getHealthFactor(),
  };
}

describe("Inspect", function () {
  it("prints reserve state", async function () {
    await resetFork();

    const reserveDataInterface = new ethers.utils.Interface([
      "function getUserReserveData(address asset,address user) view returns (uint256 currentATokenBalance,uint256 currentStableDebt,uint256 currentVariableDebt,uint256 principalStableDebt,uint256 scaledVariableDebt,uint256 stableBorrowRate,uint256 liquidityRate,uint40 stableRateLastUpdated,bool usageAsCollateralEnabled)"
    ]);
    const accountDataInterface = new ethers.utils.Interface([
      "function getUserAccountData(address user) view returns (uint256,uint256,uint256,uint256,uint256,uint256)"
    ]);
    const pairInterface = new ethers.utils.Interface([
      "function getReserves() view returns (uint112,uint112,uint32)",
      "function token0() view returns (address)",
      "function token1() view returns (address)"
    ]);

    const accountDataRaw = await network.provider.send("eth_call", [{
      to: LENDING_POOL,
      data: accountDataInterface.encodeFunctionData("getUserAccountData", [USER]),
      gasPrice: "0x0",
    }, "latest"]);
    console.log(
      "accountData",
      accountDataInterface
        .decodeFunctionResult("getUserAccountData", accountDataRaw)
        .map((v) => v.toString())
    );

    for (const [name, asset] of Object.entries(ASSETS)) {
      const reserveDataRaw = await network.provider.send("eth_call", [{
        to: DATA_PROVIDER,
        data: reserveDataInterface.encodeFunctionData("getUserReserveData", [asset, USER]),
        gasPrice: "0x0",
      }, "latest"]);
      const values = reserveDataInterface.decodeFunctionResult("getUserReserveData", reserveDataRaw);
      console.log(name, values.map((v) => (typeof v === "boolean" ? v : v.toString())));
    }

    for (const [name, address] of Object.entries(PAIRS)) {
      const reservesRaw = await network.provider.send("eth_call", [{
        to: address,
        data: pairInterface.encodeFunctionData("getReserves"),
        gasPrice: "0x0",
      }, "latest"]);
      const token0Raw = await network.provider.send("eth_call", [{
        to: address,
        data: pairInterface.encodeFunctionData("token0"),
        gasPrice: "0x0",
      }, "latest"]);
      const token1Raw = await network.provider.send("eth_call", [{
        to: address,
        data: pairInterface.encodeFunctionData("token1"),
        gasPrice: "0x0",
      }, "latest"]);
      const reserves = pairInterface.decodeFunctionResult("getReserves", reservesRaw);
      console.log(name, {
        token0: pairInterface.decodeFunctionResult("token0", token0Raw)[0],
        token1: pairInterface.decodeFunctionResult("token1", token1Raw)[0],
        reserve0: reserves[0].toString(),
        reserve1: reserves[1].toString(),
      });
    }

    console.log("extraPairs", {
      uniWethUsdc: await getPairFromFactory(UNISWAP_FACTORY, ASSETS.WETH, ASSETS.USDC),
      uniWethUsdt: await getPairFromFactory(UNISWAP_FACTORY, ASSETS.WETH, ASSETS.USDT),
      uniWbtcUsdc: await getPairFromFactory(UNISWAP_FACTORY, ASSETS.WBTC, ASSETS.USDC),
      uniWbtcUsdt: await getPairFromFactory(UNISWAP_FACTORY, ASSETS.WBTC, ASSETS.USDT),
      sushiWethUsdc: await getPairFromFactory(SUSHISWAP_FACTORY, ASSETS.WETH, ASSETS.USDC),
      sushiWethUsdt: await getPairFromFactory(SUSHISWAP_FACTORY, ASSETS.WETH, ASSETS.USDT),
      sushiWbtcUsdc: await getPairFromFactory(SUSHISWAP_FACTORY, ASSETS.WBTC, ASSETS.USDC),
      sushiWbtcUsdt: await getPairFromFactory(SUSHISWAP_FACTORY, ASSETS.WBTC, ASSETS.USDT),
    });

    const addressProviderInterface = new ethers.utils.Interface([
      "function get_registry() view returns (address)"
    ]);
    const curveRegistryRaw = await network.provider.send("eth_call", [{
      to: CURVE_ADDRESS_PROVIDER,
      data: addressProviderInterface.encodeFunctionData("get_registry"),
      gasPrice: "0x0",
    }, "latest"]);
    const curveRegistry = addressProviderInterface.decodeFunctionResult("get_registry", curveRegistryRaw)[0];
    const curveRegistryInterface = new ethers.utils.Interface([
      "function find_pool_for_coins(address,address) view returns (address)"
    ]);
    async function findCurvePool(tokenA, tokenB) {
      const raw = await network.provider.send("eth_call", [{
        to: curveRegistry,
        data: curveRegistryInterface.encodeFunctionData("find_pool_for_coins", [tokenA, tokenB]),
        gasPrice: "0x0",
      }, "latest"]);
      return curveRegistryInterface.decodeFunctionResult("find_pool_for_coins", raw)[0];
    }

    console.log("curveRegistry", curveRegistry);
    console.log("curvePools", {
      wbtcUsdt: await findCurvePool(ASSETS.WBTC, ASSETS.USDT),
      wbtcUsdc: await findCurvePool(ASSETS.WBTC, ASSETS.USDC),
      wbtcWeth: await findCurvePool(ASSETS.WBTC, ASSETS.WETH),
      wethUsdt: await findCurvePool(ASSETS.WETH, ASSETS.USDT),
    });

    const providerGetAddressInterface = new ethers.utils.Interface([
      "function get_address(uint256 id) view returns (address)"
    ]);
    const registryCandidates = {};
    for (let id = 0; id <= 10; id += 1) {
      const raw = await network.provider.send("eth_call", [{
        to: CURVE_ADDRESS_PROVIDER,
        data: providerGetAddressInterface.encodeFunctionData("get_address", [id]),
        gasPrice: "0x0",
      }, "latest"]);
      const candidate = providerGetAddressInterface.decodeFunctionResult("get_address", raw)[0];
      registryCandidates[id] = candidate;
    }
    console.log("curveAddressProviderEntries", registryCandidates);

    async function tryFindCurvePool(registryAddress, tokenA, tokenB) {
      if (registryAddress === ethers.constants.AddressZero) {
        return "zero";
      }
      try {
        const raw = await network.provider.send("eth_call", [{
          to: registryAddress,
          data: curveRegistryInterface.encodeFunctionData("find_pool_for_coins", [tokenA, tokenB]),
          gasPrice: "0x0",
        }, "latest"]);
        return curveRegistryInterface.decodeFunctionResult("find_pool_for_coins", raw)[0];
      } catch (error) {
        return "revert";
      }
    }

    const curvePoolSearch = {};
    for (const [id, registryAddress] of Object.entries(registryCandidates)) {
      curvePoolSearch[id] = {
        wbtcUsdt: await tryFindCurvePool(registryAddress, ASSETS.WBTC, ASSETS.USDT),
        wbtcUsdc: await tryFindCurvePool(registryAddress, ASSETS.WBTC, ASSETS.USDC),
        wbtcWeth: await tryFindCurvePool(registryAddress, ASSETS.WBTC, ASSETS.WETH),
      };
    }
    console.log("curvePoolSearch", curvePoolSearch);

    const v3FactoryInterface = new ethers.utils.Interface([
      "function getPool(address tokenA,address tokenB,uint24 fee) view returns (address)"
    ]);
    async function getV3Pool(tokenA, tokenB, fee) {
      const raw = await network.provider.send("eth_call", [{
        to: UNISWAP_V3_FACTORY,
        data: v3FactoryInterface.encodeFunctionData("getPool", [tokenA, tokenB, fee]),
        gasPrice: "0x0",
      }, "latest"]);
      return v3FactoryInterface.decodeFunctionResult("getPool", raw)[0];
    }

    console.log("uniswapV3Pools", {
      wbtcWeth500: await getV3Pool(ASSETS.WBTC, ASSETS.WETH, 500),
      wbtcWeth3000: await getV3Pool(ASSETS.WBTC, ASSETS.WETH, 3000),
      wbtcWeth10000: await getV3Pool(ASSETS.WBTC, ASSETS.WETH, 10000),
      wbtcUsdc500: await getV3Pool(ASSETS.WBTC, ASSETS.USDC, 500),
      wbtcUsdc3000: await getV3Pool(ASSETS.WBTC, ASSETS.USDC, 3000),
      wbtcUsdc10000: await getV3Pool(ASSETS.WBTC, ASSETS.USDC, 10000),
      wbtcUsdt500: await getV3Pool(ASSETS.WBTC, ASSETS.USDT, 500),
      wbtcUsdt3000: await getV3Pool(ASSETS.WBTC, ASSETS.USDT, 3000),
      wbtcUsdt10000: await getV3Pool(ASSETS.WBTC, ASSETS.USDT, 10000),
      usdcWeth500: await getV3Pool(ASSETS.USDC, ASSETS.WETH, 500),
      usdcWeth3000: await getV3Pool(ASSETS.USDC, ASSETS.WETH, 3000),
      usdcWeth10000: await getV3Pool(ASSETS.USDC, ASSETS.WETH, 10000),
      usdtWeth500: await getV3Pool(ASSETS.USDT, ASSETS.WETH, 500),
      usdtWeth3000: await getV3Pool(ASSETS.USDT, ASSETS.WETH, 3000),
      usdtWeth10000: await getV3Pool(ASSETS.USDT, ASSETS.WETH, 10000),
    });

    const quoterInterface = new ethers.utils.Interface([
      "function quoteExactInputSingle(address tokenIn,address tokenOut,uint24 fee,uint256 amountIn,uint160 sqrtPriceLimitX96) returns (uint256 amountOut)"
    ]);
    async function quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn) {
      try {
        const raw = await network.provider.send("eth_call", [{
          to: UNISWAP_V3_QUOTER,
          data: quoterInterface.encodeFunctionData("quoteExactInputSingle", [
            tokenIn,
            tokenOut,
            fee,
            amountIn,
            0,
          ]),
          gasPrice: "0x0",
        }, "latest"]);
        return quoterInterface.decodeFunctionResult("quoteExactInputSingle", raw)[0].toString();
      } catch (error) {
        return "revert";
      }
    }

    console.log("uniswapV3Quotes", {
      wbtcToWeth500: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.WETH, 500, "9427338222"),
      wbtcToWeth3000: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.WETH, 3000, "9427338222"),
      wbtcToWeth10000: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.WETH, 10000, "9427338222"),
      wbtcToUsdc500: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.USDC, 500, "9427338222"),
      wbtcToUsdc3000: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.USDC, 3000, "9427338222"),
      wbtcToUsdc10000: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.USDC, 10000, "9427338222"),
      wbtcToUsdt500: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.USDT, 500, "9427338222"),
      wbtcToUsdt3000: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.USDT, 3000, "9427338222"),
      wbtcToUsdt10000: await quoteExactInputSingle(ASSETS.WBTC, ASSETS.USDT, 10000, "9427338222"),
      wethToUsdc500: await quoteExactInputSingle(ASSETS.WETH, ASSETS.USDC, 500, "1500000000000000000000"),
      wethToUsdc3000: await quoteExactInputSingle(ASSETS.WETH, ASSETS.USDC, 3000, "1500000000000000000000"),
      wethToUsdc10000: await quoteExactInputSingle(ASSETS.WETH, ASSETS.USDC, 10000, "1500000000000000000000"),
      wethToUsdt500: await quoteExactInputSingle(ASSETS.WETH, ASSETS.USDT, 500, "1500000000000000000000"),
      wethToUsdt3000: await quoteExactInputSingle(ASSETS.WETH, ASSETS.USDT, 3000, "1500000000000000000000"),
      wethToUsdt10000: await quoteExactInputSingle(ASSETS.WETH, ASSETS.USDT, 10000, "1500000000000000000000"),
    });
  });

  it("prints single-step liquidation opportunities", async function () {
    const cases = [
      {
        debtAsset: "USDT",
        collateralAsset: "WBTC",
        fundAmount: ethers.BigNumber.from("15000000000000"),
      },
      {
        debtAsset: "USDT",
        collateralAsset: "WETH",
        fundAmount: ethers.BigNumber.from("15000000000000"),
      },
      {
        debtAsset: "USDC",
        collateralAsset: "WBTC",
        fundAmount: ethers.BigNumber.from("5000000000000"),
      },
      {
        debtAsset: "USDC",
        collateralAsset: "WETH",
        fundAmount: ethers.BigNumber.from("5000000000000"),
      },
      {
        debtAsset: "WBTC",
        collateralAsset: "WETH",
        fundAmount: ethers.BigNumber.from("10000000000"),
      },
    ];

    for (const liquidationCase of cases) {
      await resetFork();
      const result = await runLiquidationCase(liquidationCase);
      console.log(liquidationCase, result);
    }
  });

  it("prints two-step liquidation opportunities", async function () {
    this.skip();

    const sequences = [
      [
        {
          debtAsset: "USDC",
          collateralAsset: "WETH",
          fundAmount: ethers.BigNumber.from("5000000000000"),
        },
        {
          debtAsset: "USDT",
          collateralAsset: "WBTC",
          fundAmount: ethers.BigNumber.from("15000000000000"),
        },
      ],
      [
        {
          debtAsset: "USDC",
          collateralAsset: "WBTC",
          fundAmount: ethers.BigNumber.from("5000000000000"),
        },
        {
          debtAsset: "USDT",
          collateralAsset: "WETH",
          fundAmount: ethers.BigNumber.from("15000000000000"),
        },
      ],
      [
        {
          debtAsset: "WBTC",
          collateralAsset: "WETH",
          fundAmount: ethers.BigNumber.from("10000000000"),
        },
        {
          debtAsset: "USDT",
          collateralAsset: "WBTC",
          fundAmount: ethers.BigNumber.from("15000000000000"),
        },
      ],
      [
        {
          debtAsset: "USDC",
          collateralAsset: "WETH",
          fundAmount: ethers.BigNumber.from("5000000000000"),
        },
        {
          debtAsset: "WBTC",
          collateralAsset: "WETH",
          fundAmount: ethers.BigNumber.from("10000000000"),
        },
      ],
    ];

    for (const sequence of sequences) {
      await resetFork();
      const stepResults = [];
      for (const liquidationCase of sequence) {
        stepResults.push(await runLiquidationCase(liquidationCase));
      }
      console.log(sequence, stepResults);
    }
  });
});
