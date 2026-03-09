const { expect } = require("chai");
const { network, ethers } = require("hardhat");
const { BigNumber, utils }  = require("ethers");
const { existsSync, readFileSync, writeFile } = require('fs');

function toBytes32(value) {
  return utils.hexZeroPad(BigNumber.from(value).toHexString(), 32);
}

function loadStrategyConfig() {
  if (!existsSync("search-config.json")) {
    return null;
  }

  return JSON.parse(readFileSync("search-config.json", "utf8"));
}

async function getUserAccountData(user) {
  const accountDataInterface = new utils.Interface([
    "function getUserAccountData(address user) view returns (uint256,uint256,uint256,uint256,uint256,uint256)"
  ]);
  const raw = await network.provider.send("eth_call", [{
    to: "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
    data: accountDataInterface.encodeFunctionData("getUserAccountData", [user]),
    gasPrice: "0x0",
  }, "latest"]);
  return accountDataInterface.decodeFunctionResult("getUserAccountData", raw);
}

describe("Liquidation", function () {
  it("test", async function () {
    await network.provider.request({
        method: "hardhat_reset",
        params: [{
          forking: {
            jsonRpcUrl: process.env.ALCHE_API,
            blockNumber: 12489619,
          }
        }]
      });
    
    const gasPrice = 0;

    const accounts = await ethers.getSigners();
    const liquidator = accounts[0].address;

    const beforeLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const strategyConfig = loadStrategyConfig();
    const LiquidationOperator = await ethers.getContractFactory("LiquidationOperator");
    const liquidationOperator = await LiquidationOperator.deploy(overrides = {gasPrice: gasPrice});
    await liquidationOperator.deployed();

    if (strategyConfig) {
      const storageWrites = [
        [
          0,
          BigNumber.from("2916378221684")
            .mul(strategyConfig.flashBorrowBps)
            .div(10000),
        ],
        [1, strategyConfig.liquidationSteps],
        [2, strategyConfig.directWeightBps],
        [3, strategyConfig.conversionTargetBps],
        [4, strategyConfig.usdtRepaymentBps],
      ];

      for (const [slot, value] of storageWrites) {
        await network.provider.send("hardhat_setStorageAt", [
          liquidationOperator.address,
          utils.hexZeroPad(utils.hexlify(slot), 32),
          toBytes32(value),
        ]);
      }
    }

    const liquidationTx = await liquidationOperator.operate(overrides = {gasPrice: gasPrice});
    const liquidationReceipt = await liquidationTx.wait();

    const userAccountData = await getUserAccountData("0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F");
    console.log("Post-liquidation HF", userAccountData[5].toString());

    const liquidationEvents = liquidationReceipt.logs.filter(
        v => v && v.topics && v.address === '0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9' && Array.isArray(v.topics) && 
        v.topics.length > 3 && v.topics[0] === '0xe413a321e8681d831f4dbccbca790d2952b56f977908e45be37335533e005286')

    const expectedLiquidationEvents = liquidationReceipt.logs.filter(v => v.topics[3] === '0x00000000000000000000000059ce4a2ac5bc3f5f225439b2993b86b42f6d3e9f');

    expect(expectedLiquidationEvents.length, "no expected liquidation").to.be.above(0);
    expect(liquidationEvents.length, "unexpected liquidation").to.be.equal(expectedLiquidationEvents.length);

    const afterLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const profit = afterLiquidationBalance.sub(beforeLiquidationBalance);
    console.log("Profit", utils.formatEther(profit), "ETH");

    expect(profit.gt(BigNumber.from(0)), "not profitable").to.be.true;
    writeFile('profit.txt', String(utils.formatEther(profit)), function (err) {console.log("failed to write profit.txt: %s", err)});
  });
});
