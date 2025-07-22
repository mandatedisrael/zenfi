# Meet Zenfi: Native ERC4626 Multi-Token Vault System 

## Overview (FOR TESTING ONLY⚠️)

Welcome to **Zenfi**—your all-in-one, multi-token vault system for DeFi testing and development. It includes:
- Mock ERC20 tokens for testing (faucet/mintable)
- A vault contract supporting multiple token pairs and yield strategies
- Mock strategy contracts
- Deployment and test scripts

**Note:** This repository currently contains only smart contracts and backend scripts. The frontend is not included.

---

## Sample User Flow 🚶

Let's walk through a typical journey you might take as a user or developer testing **Zenfi**. We'll use the Hardhat console and ethers.js for hands-on interaction. No frontend needed—just you, your terminal, and some curiosity!

### 1. Mint Yourself Some Test Tokens

First, you'll want some tokens to play with. Let's mint 1000 DAI and 1000 WETH to your address using the faucet function:

```js
// In Hardhat console: npx hardhat console --network <your-network>
const [user] = await ethers.getSigners();
const MockERC20 = await ethers.getContractFactory("MockERC20");
const dai = await MockERC20.attach("<DAI_CONTRACT_ADDRESS>");
const weth = await MockERC20.attach("<WETH_CONTRACT_ADDRESS>");

// Mint tokens to yourself
await dai.connect(user).faucet();
await weth.connect(user).faucet();

console.log("DAI balance:", (await dai.balanceOf(user.address)).toString());
console.log("WETH balance:", (await weth.balanceOf(user.address)).toString());
```

### 2. Approve the Vault to Spend Your Tokens

Before you can add liquidity, you need to let the vault contract move your tokens:

```js
const vault = await ethers.getContractAt("MultiTokenVault", "<VAULT_CONTRACT_ADDRESS>");
await dai.connect(user).approve(vault.target, ethers.parseEther("1000"));
await weth.connect(user).approve(vault.target, ethers.parseEther("1000"));
```

### 3. Add Liquidity to a Token Pair

Now, let's deposit some tokens into the vault. Suppose pairId 0 is DAI/WETH:

```js
await vault.connect(user).addLiquidity(0, ethers.parseEther("100"), ethers.parseEther("100"));
console.log("Added liquidity!");
```

### 4. Check Your Position and Rewards

Curious about your vault shares or rewards? You can check your total value and claimable rewards:

```js
const value = await vault.getUserTotalValue(user.address);
console.log("Your total value in the vault:", value.toString());

// Claim rewards (if any)
await vault.connect(user).claimRewards();
console.log("Claimed rewards!");
```

### 5. Remove Liquidity

Ready to exit? Just burn your shares and get your tokens back:

```js
// Let's say you want to remove 50 shares from pairId 0
await vault.connect(user).removeLiquidity(0, ethers.parseEther("50"));
console.log("Removed liquidity!");
```

---

**That's it!** You can repeat these steps, try different token pairs, or experiment with the strategy functions if you're feeling adventurous. If you get stuck, check out the test scripts for more examples, or open an issue—help is just a click away.

---

## Contracts

### 1. MockERC20 (`MockToken.sol`)
A simple ERC20 token for testing.
- `faucet()`: Anyone can mint 1000 tokens to themselves.
- `mint(address, amount)`: Anyone can mint any amount to any address (for advanced testing).
- Standard ERC20 functions: `name()`, `symbol()`, `decimals()`, `balanceOf(address)`, etc.

### 2. MultiTokenVault (`MultiTokenVault.sol`)
A vault that supports multiple token pairs and yield strategies, based on ERC4626.
- `addTokenPair(token0, token1, name, symbol)`: Owner adds a new token pair.
- `addStrategy(strategyAddress, name, allocation)`: Owner adds a new yield strategy.
- `addLiquidity(pairId, amount0, amount1)`: Deposit two tokens into a pair, receive vault shares.
- `removeLiquidity(pairId, shares)`: Withdraw tokens by burning shares.
- `claimRewards()`: Claim accumulated rewards.
- `getUserTotalValue(address)`: View a user's total value in the vault.
- `getTokenPair(pairId)`: Get info about a specific token pair.
- `harvestRewards()`: Owner harvests rewards from all strategies.
- `depositToStrategy(strategyId, amount)`: Owner deposits assets into a strategy.
- `harvestFromStrategy(strategyId)`: Owner harvests from a specific strategy.

### 3. MockStrategy (`MockStrategy.sol`)
A mock strategy contract for simulating yield. Used for testing vault-strategy integration.
- `deposit(amount)`: Vault deposits funds.
- `withdraw(amount)`: Vault withdraws funds.
- `harvest()`: Vault harvests simulated rewards.
- `getTotalValue()`: Returns total value managed by the strategy.
- Admin and emergency functions for testing.

---

## Deployment

You can deploy all contracts and example tokens using the provided script:

```bash
npx hardhat run scripts/deploy-erc4626-lp-vaults.js --network <your-network>
```

This script will:
- Deploy base tokens (BTC, WETH, DAI, 0G, BNB)
- Deploy LP tokens (BTC-0G LP, WETH-DAI LP, 0G-BNB LP)
- Deploy MultiTokenVaults for each LP token
- Deploy mock reward tokens
- Deploy MockStrategy contracts for each vault
- Print a summary table of all deployed contract addresses

**Note:** Update the script or network as needed for your environment.

---

## Testing

Run the test suite with:

```bash
npx hardhat test
```

The tests cover:
- Token pair and strategy management (owner-only)
- Adding/removing liquidity
- Claiming and harvesting rewards
- ERC4626 compatibility
- Strategy integration and access control
- Edge cases and reverts

See `test/vault.test.js` for details and usage examples.

---

## Contract Summary Table

| Contract         | File                | Purpose/Key Functions                  |
|------------------|---------------------|----------------------------------------|
| MockERC20        | MockToken.sol       | Test ERC20, faucet/mint                |
| MultiTokenVault  | MultiTokenVault.sol | Multi-token vault, ERC4626, strategies |
| MockStrategy     | MockStrategy.sol    | Simulated yield, for testing           |

---

## Security & Testing Notes

- All contracts are for testing and development only.
- Anyone can mint tokens and interact with the vault.
- There are no real funds at risk.
- **Do not use in production.**

---

## Need More?

If you need more details, code examples, or have specific requirements, open an issue or contact the maintainer.
