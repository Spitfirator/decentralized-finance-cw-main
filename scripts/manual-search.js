const { execFileSync } = require("child_process");
const { writeFileSync } = require("fs");
const path = require("path");

const cwd = path.resolve(__dirname, "..");
const configPath = path.join(cwd, "search-config.json");

function writeConfig(config) {
  writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

function runCase(config) {
  writeConfig(config);

  const output = execFileSync("/bin/zsh", ["-lc", `ALCHE_API=${process.env.ALCHE_API} npm test`], {
    cwd,
    encoding: "utf8",
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      SHELL: process.env.SHELL,
      TERM: process.env.TERM,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  const match = output.match(/Profit ([0-9.]+) ETH/);
  if (!match) {
    throw new Error(`Missing profit in output for ${JSON.stringify(config)}\n${output}`);
  }

  return {
    ...config,
    profit: Number(match[1]),
  };
}

function sortResults(results) {
  return results.sort((a, b) => b.profit - a.profit);
}

function stageOne() {
  const results = [];
  for (const flashBorrowBps of [8000, 9000, 10000, 11000, 12000, 13000, 14000, 15000]) {
    for (const uniFlashBorrowBps of [0, 1000, 2000, 3000, 4000, 5000]) {
      const config = {
        flashBorrowBps,
        liquidationSteps: 1,
        uniFlashBorrowBps,
        conversionTargetBps: 7500,
        usdtRepaymentBps: 10000,
        directUsdcTargetBps: 1800,
        flashSourceMode: 0,
        wbtcWethV3SplitBps: 5000,
        liquidationCollateralMode: 0,
        preLiquidationCollateralMode: 0,
        preLiquidationUsdtBps: 0,
      };
      const result = runCase(config);
      results.push(result);
      console.log("stage1", result);
    }
  }
  return sortResults(results);
}

function stageTwo(seed) {
  const results = [];
  for (const conversionTargetBps of [6000, 6500, 6700, 7000, 7500]) {
    for (const directUsdcTargetBps of [1200, 1500, 1800, 2100, 2400]) {
      const config = {
        flashBorrowBps: seed.flashBorrowBps,
        liquidationSteps: 1,
        uniFlashBorrowBps: seed.uniFlashBorrowBps,
        conversionTargetBps,
        usdtRepaymentBps: 10000,
        directUsdcTargetBps,
        flashSourceMode: 0,
        wbtcWethV3SplitBps: 5000,
        liquidationCollateralMode: 0,
        preLiquidationCollateralMode: 0,
        preLiquidationUsdtBps: 0,
      };
      const result = runCase(config);
      results.push(result);
      console.log("stage2", result);
    }
  }
  return sortResults(results);
}

function main() {
  const stageOneResults = stageOne();
  console.log("stage1-top", stageOneResults.slice(0, 10));

  const finalists = stageOneResults.slice(0, 3);
  let best = null;

  for (const finalist of finalists) {
    const results = stageTwo(finalist);
    console.log("stage2-top", finalist, results.slice(0, 10));
    if (!best || results[0].profit > best.profit) {
      best = results[0];
    }
  }

  if (!best) {
    throw new Error("No best result");
  }

  writeConfig(best);
  console.log("best", best);
}

main();
