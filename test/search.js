const { network, ethers } = require("hardhat");
const { BigNumber, utils } = require("ethers");

const TARGET_BLOCK = 12489619;

async function resetFork() {
  await network.provider.request({
    method: "hardhat_reset",
    params: [{
      forking: {
        jsonRpcUrl: process.env.ALCHE_API,
        blockNumber: TARGET_BLOCK,
      }
    }]
  });
}

async function runCase(params) {
  await resetFork();

  const gasPrice = 0;
  const [liquidator] = await ethers.getSigners();

  const beforeBalance = BigNumber.from(await hre.network.provider.request({
    method: "eth_getBalance",
    params: [liquidator.address],
  }));

  const Operator = await ethers.getContractFactory("SearchLiquidationOperator");
  const operator = await Operator.deploy(
    params.flashBorrowBps,
    params.liquidationSteps,
    params.uniFlashBorrowBps,
    params.conversionTargetBps,
    params.usdtRepaymentBps,
    params.directUsdcTargetBps,
    params.flashSourceMode,
    params.wbtcWethV3SplitBps,
    { gasPrice }
  );
  await operator.deployed();

  const tx = await operator.operate({ gasPrice });
  await tx.wait();

  const afterBalance = BigNumber.from(await hre.network.provider.request({
    method: "eth_getBalance",
    params: [liquidator.address],
  }));

  return afterBalance.sub(beforeBalance);
}

function profitEth(value) {
  return Number(utils.formatEther(value));
}

describe("Search", function () {
  before(function () {
    if (!process.env.RUN_SEARCH) {
      this.skip();
    }
  });

  it("finds stronger liquidation parameters", async function () {
    const stageOne = [];
    for (const flashBorrowBps of [12500, 15000, 17500, 20000]) {
      for (const liquidationSteps of [1, 2, 3, 4]) {
        const profit = await runCase({
          flashBorrowBps,
          liquidationSteps,
          uniFlashBorrowBps: 0,
          conversionTargetBps: 7500,
          usdtRepaymentBps: 10000,
          directUsdcTargetBps: 1800,
          flashSourceMode: 0,
          wbtcWethV3SplitBps: 5000,
        });
        stageOne.push({
          flashBorrowBps,
          liquidationSteps,
          uniFlashBorrowBps: 0,
          conversionTargetBps: 7500,
          usdtRepaymentBps: 10000,
          directUsdcTargetBps: 1800,
          flashSourceMode: 0,
          wbtcWethV3SplitBps: 5000,
          profit,
        });
      }
    }

    stageOne.sort((a, b) => (a.profit.gt(b.profit) ? -1 : 1));
    const bestStageOne = stageOne[0];
    console.log("Stage 1 top 5");
    for (const result of stageOne.slice(0, 5)) {
      console.log({
        ...result,
        profit: utils.formatEther(result.profit),
      });
    }

    const stageTwo = [];
    for (const uniFlashBorrowBps of [0, 1000, 2000, 3000, 4000, 5000]) {
      for (const conversionTargetBps of [6000, 6500, 6700, 7000, 7500]) {
        for (const directUsdcTargetBps of [1200, 1500, 1800, 2100, 2400]) {
          const profit = await runCase({
            flashBorrowBps: bestStageOne.flashBorrowBps,
            liquidationSteps: bestStageOne.liquidationSteps,
            uniFlashBorrowBps,
            conversionTargetBps,
            usdtRepaymentBps: 10000,
            directUsdcTargetBps,
            flashSourceMode: 0,
            wbtcWethV3SplitBps: 5000,
          });
          stageTwo.push({
            flashBorrowBps: bestStageOne.flashBorrowBps,
            liquidationSteps: bestStageOne.liquidationSteps,
            uniFlashBorrowBps,
            conversionTargetBps,
            usdtRepaymentBps: 10000,
            directUsdcTargetBps,
            flashSourceMode: 0,
            wbtcWethV3SplitBps: 5000,
            profit,
          });
        }
      }
    }

    stageTwo.sort((a, b) => (a.profit.gt(b.profit) ? -1 : 1));
    console.log("Stage 2 top 10");
    for (const result of stageTwo.slice(0, 10)) {
      console.log({
        ...result,
        profit: utils.formatEther(result.profit),
      });
    }

    const best = stageTwo[0];
    console.log("Best profit", utils.formatEther(best.profit));
    console.log("Best params", {
      flashBorrowBps: best.flashBorrowBps,
      liquidationSteps: best.liquidationSteps,
      uniFlashBorrowBps: best.uniFlashBorrowBps,
      conversionTargetBps: best.conversionTargetBps,
      usdtRepaymentBps: best.usdtRepaymentBps,
      directUsdcTargetBps: best.directUsdcTargetBps,
      flashSourceMode: best.flashSourceMode,
      wbtcWethV3SplitBps: best.wbtcWethV3SplitBps,
    });

    if (profitEth(best.profit) < 126) {
      throw new Error(`Best profit ${utils.formatEther(best.profit)} below 126 ETH`);
    }
  });
});
