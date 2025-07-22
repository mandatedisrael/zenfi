const { ethers, network } = require("hardhat");
const { parseEther, getAddress } = require("ethers");
const chalk = require('chalk');

// if (network.name !== "0g-testnet") {
//   throw new Error("This deployment script must be run with --network 0g-testnet");
// }

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(chalk.blue.bold('\n🚀 Starting Zer0Pulse Vault Deployment on 0g-testnet...\n'));
  console.log(chalk.yellow(`Deployer: ${deployer.address}`));

  // Deploy base tokens
  console.log(chalk.magenta('\n--- Deploying Base Tokens ---'));
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const btc = await MockERC20.deploy("Bitcoin", "BTC", deployer.address, parseEther("10000000"));
  await btc.waitForDeployment();
  console.log(chalk.green('✅ Deployed Bitcoin (BTC):'), btc.target);
  const weth = await MockERC20.deploy("Wrapped Ether", "WETH", deployer.address, parseEther("10000000"));
  await weth.waitForDeployment();
  console.log(chalk.green('✅ Deployed Wrapped Ether (WETH):'), weth.target);
  const dai = await MockERC20.deploy("Dai Stablecoin", "DAI", deployer.address, parseEther("10000000"));
  await dai.waitForDeployment();
  console.log(chalk.green('✅ Deployed Dai Stablecoin (DAI):'), dai.target);
  const zeroG = await MockERC20.deploy("Zero Gravity", "0G", deployer.address, parseEther("10000000"));
  await zeroG.waitForDeployment();
  console.log(chalk.green('✅ Deployed Zero Gravity (0G):'), zeroG.target);
  const bnb = await MockERC20.deploy("Binance Coin", "BNB", deployer.address, parseEther("10000000"));
  await bnb.waitForDeployment();
  console.log(chalk.green('✅ Deployed Binance Coin (BNB):'), bnb.target);

  // Deploy LP tokens
  console.log(chalk.magenta('\n--- Deploying LP Tokens ---'));
  const btc0gLP = await MockERC20.deploy("BTC-0G LP", "BTC0GLP", deployer.address, parseEther("10000000"));
  await btc0gLP.waitForDeployment();
  console.log(chalk.green('✅ Deployed BTC-0G LP:'), btc0gLP.target);
  const wethdaiLP = await MockERC20.deploy("WETH-DAI LP", "WETHDAILP", deployer.address, parseEther("10000000"));
  await wethdaiLP.waitForDeployment();
  console.log(chalk.green('✅ Deployed WETH-DAI LP:'), wethdaiLP.target);
  const zeroGbnbLP = await MockERC20.deploy("0G-BNB LP", "0GBNBLP", deployer.address, parseEther("10000000"));
  await zeroGbnbLP.waitForDeployment();
  console.log(chalk.green('✅ Deployed 0G-BNB LP:'), zeroGbnbLP.target);

  // Deploy MultiTokenVaults for each LP token
  console.log(chalk.magenta('\n--- Deploying MultiTokenVaults ---'));
  const MultiTokenVault = await ethers.getContractFactory("MultiTokenVault");
  const btc0gVault = await MultiTokenVault.deploy(getAddress(btc0gLP.target), "BTC-0G Vault", "BTC0G-VLT");
  await btc0gVault.waitForDeployment();
  console.log(chalk.green('✅ Deployed BTC-0G Vault:'), btc0gVault.target);
  const wethdaiVault = await MultiTokenVault.deploy(getAddress(wethdaiLP.target), "WETH-DAI Vault", "WETHDAI-VLT");
  await wethdaiVault.waitForDeployment();
  console.log(chalk.green('✅ Deployed WETH-DAI Vault:'), wethdaiVault.target);
  const zeroGbnbVault = await MultiTokenVault.deploy(getAddress(zeroGbnbLP.target), "0G-BNB Vault", "0GBNB-VLT");
  await zeroGbnbVault.waitForDeployment();
  console.log(chalk.green('✅ Deployed 0G-BNB Vault:'), zeroGbnbVault.target);

  // Deploy mock reward tokens
  console.log(chalk.magenta('\n--- Deploying Reward Tokens ---'));
  const btc0gReward = await MockERC20.deploy("BTC-0G Reward", "BTC0GRWD", deployer.address, parseEther("10000000"));
  await btc0gReward.waitForDeployment();
  console.log(chalk.green('✅ Deployed BTC-0G Reward:'), btc0gReward.target);
  const wethdaiReward = await MockERC20.deploy("WETH-DAI Reward", "WETHDAIRWD", deployer.address, parseEther("10000000"));
  await wethdaiReward.waitForDeployment();
  console.log(chalk.green('✅ Deployed WETH-DAI Reward:'), wethdaiReward.target);
  const zeroGbnbReward = await MockERC20.deploy("0G-BNB Reward", "0GBNBRWD", deployer.address, parseEther("10000000"));
  await zeroGbnbReward.waitForDeployment();
  console.log(chalk.green('✅ Deployed 0G-BNB Reward:'), zeroGbnbReward.target);

  // Deploy MockStrategy for each vault
  console.log(chalk.magenta('\n--- Deploying Mock Strategies ---'));
  const MockStrategy = await ethers.getContractFactory("MockStrategy");
  const btc0gStrategy = await MockStrategy.deploy(btc0gLP.target, btc0gReward.target, btc0gVault.target);
  await btc0gStrategy.waitForDeployment();
  console.log(chalk.green('✅ Deployed BTC-0G Strategy:'), btc0gStrategy.target);
  const wethdaiStrategy = await MockStrategy.deploy(wethdaiLP.target, wethdaiReward.target, wethdaiVault.target);
  await wethdaiStrategy.waitForDeployment();
  console.log(chalk.green('✅ Deployed WETH-DAI Strategy:'), wethdaiStrategy.target);
  const zeroGbnbStrategy = await MockStrategy.deploy(zeroGbnbLP.target, zeroGbnbReward.target, zeroGbnbVault.target);
  await zeroGbnbStrategy.waitForDeployment();
  console.log(chalk.green('✅ Deployed 0G-BNB Strategy:'), zeroGbnbStrategy.target);

  // Print summary
  console.log(chalk.blue.bold('\n🎉 Deployment Complete! Here are your contract addresses:'));
  console.table({
    BTC: btc.target,
    WETH: weth.target,
    DAI: dai.target,
    '0G': zeroG.target,
    BNB: bnb.target,
    'BTC-0G LP': btc0gLP.target,
    'WETH-DAI LP': wethdaiLP.target,
    '0G-BNB LP': zeroGbnbLP.target,
    'BTC-0G Vault': btc0gVault.target,
    'WETH-DAI Vault': wethdaiVault.target,
    '0G-BNB Vault': zeroGbnbVault.target,
    'BTC-0G Reward': btc0gReward.target,
    'WETH-DAI Reward': wethdaiReward.target,
    '0G-BNB Reward': zeroGbnbReward.target,
    'BTC-0G Strategy': btc0gStrategy.target,
    'WETH-DAI Strategy': wethdaiStrategy.target,
    '0G-BNB Strategy': zeroGbnbStrategy.target
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 