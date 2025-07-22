const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;
const deployment = require("../deployment.json");

describe("MultiTokenVault", function () {
  let deployer, user1, user2;
  let vault, token0, token1, rewardToken;

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();
    vault = await ethers.getContractAt("MultiTokenVault", deployment.BTC0GVault);
    token0 = await ethers.getContractAt("MockERC20", deployment.BTC0GLP);
    token1 = await ethers.getContractAt("MockERC20", deployment["0G"]); // Example, adjust as needed
    rewardToken = await ethers.getContractAt("MockERC20", deployment.BTC0GReward);
  });

  describe("Token Pair Management", function () {
    it("should allow only owner to add token pair", async function () {
      await expect(
        vault.connect(user1).addTokenPair(token0.target, token1.target, "PairName", "PAIR")
      ).to.be.reverted;
      await expect(
        vault.connect(deployer).addTokenPair(token0.target, token1.target, "PairName", "PAIR")
      ).to.emit(vault, "TokenPairAdded");
    });
  });

  describe("Strategy Management", function () {
    it("should allow only owner to add strategy", async function () {
      await expect(
        vault.connect(user1).addStrategy(user2.address, "StratName", 1000)
      ).to.be.reverted;
      await expect(
        vault.connect(deployer).addStrategy(user2.address, "StratName", 1000)
      ).to.emit(vault, "StrategyAdded");
    });
  });

  describe("Liquidity Operations", function () {
    it("should allow user to add liquidity and receive shares", async function () {
      await token0.connect(deployer).mint(user1.address, ethers.parseEther("1000"));
      await token1.connect(deployer).mint(user1.address, ethers.parseEther("1000"));
      await token0.connect(user1).approve(vault.target, ethers.parseEther("1000"));
      await token1.connect(user1).approve(vault.target, ethers.parseEther("1000"));
      await expect(
        vault.connect(user1).addLiquidity(0, ethers.parseEther("100"), ethers.parseEther("100"))
      ).to.emit(vault, "LiquidityAdded");
    });
    it("should allow user to remove liquidity and burn shares", async function () {
      // Add liquidity first
      await token0.connect(deployer).mint(user1.address, ethers.parseEther("1000"));
      await token1.connect(deployer).mint(user1.address, ethers.parseEther("1000"));
      await token0.connect(user1).approve(vault.target, ethers.parseEther("1000"));
      await token1.connect(user1).approve(vault.target, ethers.parseEther("1000"));
      await vault.connect(user1).addLiquidity(0, ethers.parseEther("100"), ethers.parseEther("100"));
      // Remove liquidity
      await expect(
        vault.connect(user1).removeLiquidity(0, ethers.parseEther("100"))
      ).to.emit(vault, "LiquidityRemoved");
    });
    it("should revert on insufficient shares when removing liquidity", async function () {
      // Use user2 who has not added liquidity
      await expect(
        vault.connect(user2).removeLiquidity(0, ethers.parseEther("100"))
      ).to.be.reverted;
    });
  });

  describe("Rewards", function () {
    it("should allow only owner to harvest rewards", async function () {
      await expect(vault.connect(user1).harvestRewards()).to.be.reverted;
      await expect(vault.connect(deployer).harvestRewards()).to.emit(vault, "RewardsHarvested");
    });
    it("should allow user to claim rewards", async function () {
      // Add liquidity for user1
      await token0.connect(deployer).mint(user1.address, ethers.parseEther("1000"));
      await token1.connect(deployer).mint(user1.address, ethers.parseEther("1000"));
      await token0.connect(user1).approve(vault.target, ethers.parseEther("1000"));
      await token1.connect(user1).approve(vault.target, ethers.parseEther("1000"));
      await vault.connect(user1).addLiquidity(0, ethers.parseEther("100"), ethers.parseEther("100"));
      // Simulate time passing
      await hre.network.provider.send("evm_increaseTime", [3600]); // 1 hour
      await hre.network.provider.send("evm_mine");
      await expect(vault.connect(user1).claimRewards()).to.emit(vault, "RewardsClaimed");
    });
  });

  describe("View Functions", function () {
    it("should return user total value", async function () {
      const value = await vault.getUserTotalValue(user1.address);
      expect(value).to.be.a("bigint");
    });
    it("should return token pair info", async function () {
      const info = await vault.getTokenPair(0);
      expect(Array.isArray(info)).to.be.true;
      expect(info.length).to.equal(7);
    });
  });

  describe("ERC4626/4626-Related", function () {
    it("should return total assets", async function () {
      const assets = await vault.totalAssets();
      expect(assets).to.be.a("bigint");
    });
    // Remove or adjust the internal function test for _convertToShares/_convertToAssets
    // it("should convert to shares and assets correctly", async function () {
    //   const shares = await vault._convertToShares(ethers.parseEther("100"), 0);
    //   const assets = await vault._convertToAssets(shares, 0);
    //   expect(assets).to.be.a("bigint");
    // });
  });

  describe("Strategy Integration", function () {
    it("should allow only owner to deposit to strategy", async function () {
      await expect(
        vault.connect(user1).depositToStrategy(0, ethers.parseEther("10"))
      ).to.be.reverted;
    });
    it("should allow only owner to harvest from strategy", async function () {
      await expect(
        vault.connect(user1).harvestFromStrategy(0)
      ).to.be.reverted;
    });
  });

  describe("Access Control & Edge Cases", function () {
    it("should revert on zero address or zero amount in addTokenPair", async function () {
      await expect(
        vault.connect(deployer).addTokenPair(ethers.ZeroAddress, token1.target, "PairName", "PAIR")
      ).to.be.reverted;
      await expect(
        vault.connect(deployer).addTokenPair(token0.target, ethers.ZeroAddress, "PairName", "PAIR")
      ).to.be.reverted;
    });
    it("should revert on allocation > 10000 in addStrategy", async function () {
      await expect(
        vault.connect(deployer).addStrategy(user2.address, "StratName", 20000)
      ).to.be.reverted;
    });
    it("should revert on zero amounts in addLiquidity", async function () {
      await expect(
        vault.connect(user1).addLiquidity(0, 0, 0)
      ).to.be.reverted;
    });
  });
});

// Custom summary after all tests
let passed = 0;
let failed = 0;
let failedTests = [];
let passedTests = [];

afterEach(function () {
  if (this.currentTest.state === "passed") {
    passed++;
    passedTests.push(this.currentTest.fullTitle());
  } else if (this.currentTest.state === "failed") {
    failed++;
    failedTests.push({
      title: this.currentTest.fullTitle(),
      err: this.currentTest.err && this.currentTest.err.message
    });
  }
});

after(function () {
  console.log("\n==================== TEST SUMMARY ====================");
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  if (passedTests.length > 0) {
    console.log("\nPassed Tests:");
    passedTests.forEach((t, i) => {
      console.log(`${i + 1}) ${t}`);
    });
  }
  if (failedTests.length > 0) {
    console.log("\nFailed Tests:");
    failedTests.forEach((t, i) => {
      console.log(`${i + 1}) ${t.title}`);
      console.log(`   Error: ${t.err}`);
    });
  } else {
    console.log("All tests passed! 🎉");
  }
  console.log("======================================================\n");
}); 