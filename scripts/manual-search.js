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

  const output = execFileSync("npm", ["test", "--silent"], {
    cwd,
    encoding: "utf8",
    env: {
      ALCHE_API: process.env.ALCHE_API,
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
    for (const directWeightBps of [0, 2000, 5000, 10000, 20000, 40000, 80000]) {
      const config = {
        flashBorrowBps,
        liquidationSteps: 1,
        directWeightBps,
        conversionTargetBps: 7500,
        usdtRepaymentBps: 10000,
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
  for (const conversionTargetBps of [0, 2500, 5000, 7500, 10000]) {
    for (const usdtRepaymentBps of [0, 2500, 5000, 7500, 10000]) {
      const config = {
        flashBorrowBps: seed.flashBorrowBps,
        liquidationSteps: 1,
        directWeightBps: seed.directWeightBps,
        conversionTargetBps,
        usdtRepaymentBps,
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
