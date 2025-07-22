// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MultiTokenVault
 * @dev handles multiple token pairs and strategies
 */
contract MultiTokenVault is ERC4626, Ownable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // Structs
    struct TokenPair {
        IERC20 token0;
        IERC20 token1;
        string name;
        string symbol;
        bool isActive;
        uint256 totalLiquidity;
        uint256 totalShares;
        uint256 lastUpdateTime;
    }

    struct Strategy {
        address strategyAddress;
        string name;
        bool isActive;
        uint256 allocation; // Percentage (basis points)
        uint256 totalValue;
        uint256 lastHarvest;
    }

    struct UserPosition {
        uint256 shares;
        uint256 lastClaimTime;
        uint256 accumulatedRewards;
    }

    // State variables
    mapping(uint256 => TokenPair) public tokenPairs;
    mapping(uint256 => Strategy) public strategies;
    mapping(address => mapping(uint256 => UserPosition)) public userPositions;
    
    uint256 public tokenPairCount;
    uint256 public strategyCount;
    uint256 public totalValueLocked;
    
    // Events
    event TokenPairAdded(uint256 indexed pairId, address token0, address token1, string name);
    event StrategyAdded(uint256 indexed strategyId, address strategyAddress, string name);
    event LiquidityAdded(uint256 indexed pairId, address user, uint256 amount0, uint256 amount1, uint256 shares);
    event LiquidityRemoved(uint256 indexed pairId, address user, uint256 shares, uint256 amount0, uint256 amount1);
    event RewardsHarvested(uint256 indexed strategyId, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(msg.sender) {}

    /**
     * @dev Add a new token pair to the vault
     */
    function addTokenPair(
        IERC20 _token0,
        IERC20 _token1,
        string memory _name,
        string memory _symbol
    ) external onlyOwner returns (uint256 pairId) {
        require(address(_token0) != address(0) && address(_token1) != address(0), "Invalid tokens");
        
        pairId = tokenPairCount++;
        tokenPairs[pairId] = TokenPair({
            token0: _token0,
            token1: _token1,
            name: _name,
            symbol: _symbol,
            isActive: true,
            totalLiquidity: 0,
            totalShares: 0,
            lastUpdateTime: block.timestamp
        });

        emit TokenPairAdded(pairId, address(_token0), address(_token1), _name);
    }

    /**
     * @dev Add a new yield strategy
     */
    function addStrategy(
        address _strategyAddress,
        string memory _name,
        uint256 _allocation
    ) external onlyOwner returns (uint256 strategyId) {
        require(_strategyAddress != address(0), "Invalid strategy address");
        require(_allocation <= 10000, "Allocation exceeds 100%");
        
        strategyId = strategyCount++;
        strategies[strategyId] = Strategy({
            strategyAddress: _strategyAddress,
            name: _name,
            isActive: true,
            allocation: _allocation,
            totalValue: 0,
            lastHarvest: block.timestamp
        });

        emit StrategyAdded(strategyId, _strategyAddress, _name);
    }

    /**
     * @dev Add liquidity to a specific token pair
     */
    function addLiquidity(
        uint256 _pairId,
        uint256 _amount0,
        uint256 _amount1
    ) external nonReentrant returns (uint256 shares) {
        TokenPair storage pair = tokenPairs[_pairId];
        require(pair.isActive, "Pair not active");
        require(_amount0 > 0 && _amount1 > 0, "Amounts must be greater than 0");

        // Calculate shares based on current ratio
        if (pair.totalShares == 0) {
            shares = _amount0; // Initial deposit
        } else {
            uint256 totalValue = pair.totalLiquidity;
            shares = (_amount0 * pair.totalShares) / totalValue;
        }

        // Transfer tokens from user
        pair.token0.safeTransferFrom(msg.sender, address(this), _amount0);
        pair.token1.safeTransferFrom(msg.sender, address(this), _amount1);

        // Update state
        pair.totalLiquidity += _amount0;
        pair.totalShares += shares;
        pair.lastUpdateTime = block.timestamp;

        // Update user position
        userPositions[msg.sender][_pairId].shares += shares;

        // Mint vault shares to user
        _mint(msg.sender, shares);

        emit LiquidityAdded(_pairId, msg.sender, _amount0, _amount1, shares);
    }

    /**
     * @dev Remove liquidity from a specific token pair
     */
    function removeLiquidity(
        uint256 _pairId,
        uint256 _shares
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        TokenPair storage pair = tokenPairs[_pairId];
        UserPosition storage position = userPositions[msg.sender][_pairId];
        
        require(pair.isActive, "Pair not active");
        require(position.shares >= _shares, "Insufficient shares");

        // Calculate amounts to return
        amount0 = (_shares * pair.totalLiquidity) / pair.totalShares;
        amount1 = (_shares * pair.totalLiquidity) / pair.totalShares; // Simplified for demo

        // Update state
        pair.totalLiquidity -= amount0;
        pair.totalShares -= _shares;
        pair.lastUpdateTime = block.timestamp;

        // Update user position
        position.shares -= _shares;

        // Transfer tokens to user
        pair.token0.safeTransfer(msg.sender, amount0);
        pair.token1.safeTransfer(msg.sender, amount1);

        // Burn vault shares
        _burn(msg.sender, _shares);

        emit LiquidityRemoved(_pairId, msg.sender, _shares, amount0, amount1);
    }

    /**
     * @dev Harvest rewards from all active strategies
     */
    function harvestRewards() external onlyOwner {
        for (uint256 i = 0; i < strategyCount; i++) {
            Strategy storage strategy = strategies[i];
            if (strategy.isActive) {
                // Call harvest function on strategy contract
                // This is a simplified version - actual implementation would call strategy.harvest()
                strategy.lastHarvest = block.timestamp;
                emit RewardsHarvested(i, 0); // Placeholder
            }
        }
    }

    /**
     * @dev Claim accumulated rewards for a user
     */
    function claimRewards() external nonReentrant {
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < tokenPairCount; i++) {
            UserPosition storage position = userPositions[msg.sender][i];
            if (position.shares > 0) {
                // Calculate rewards based on time and shares
                uint256 timeElapsed = block.timestamp - position.lastClaimTime;
                uint256 rewards = (position.shares * timeElapsed * 1e18) / 365 days; // Simplified APY calculation
                
                position.accumulatedRewards += rewards;
                position.lastClaimTime = block.timestamp;
                totalRewards += rewards;
            }
        }

        if (totalRewards > 0) {
            // Transfer rewards to user (simplified - would use actual reward token)
            emit RewardsClaimed(msg.sender, totalRewards);
        }
    }

    /**
     * @dev Get user's total value across all positions
     */
    function getUserTotalValue(address _user) external view returns (uint256 totalValue) {
        for (uint256 i = 0; i < tokenPairCount; i++) {
            UserPosition storage position = userPositions[_user][i];
            if (position.shares > 0) {
                TokenPair storage pair = tokenPairs[i];
                uint256 userValue = (position.shares * pair.totalLiquidity) / pair.totalShares;
                totalValue += userValue;
            }
        }
    }

    /**
     * @dev Get token pair information
     */
    function getTokenPair(uint256 _pairId) external view returns (
        address token0,
        address token1,
        string memory name,
        string memory symbol,
        bool isActive,
        uint256 totalLiquidity,
        uint256 totalShares
    ) {
        TokenPair storage pair = tokenPairs[_pairId];
        return (
            address(pair.token0),
            address(pair.token1),
            pair.name,
            pair.symbol,
            pair.isActive,
            pair.totalLiquidity,
            pair.totalShares
        );
    }

    // Override ERC4626 functions for compatibility
    function totalAssets() public view virtual override returns (uint256) {
        return totalValueLocked;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            shares = assets;
        } else {
            shares = assets.mulDiv(supply, totalAssets(), rounding);
        }
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            assets = shares;
        } else {
            assets = shares.mulDiv(totalAssets(), supply, rounding);
        }
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        totalValueLocked += assets;
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);
        totalValueLocked -= assets;

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Deposit assets into the strategy (for integration and testing)
     */
    function depositToStrategy(uint256 strategyId, uint256 amount) external onlyOwner {
        Strategy storage strat = strategies[strategyId];
        require(strat.isActive, "Strategy not active");
        require(strat.strategyAddress != address(0), "Invalid strategy");
        IERC20(asset()).approve(strat.strategyAddress, amount);
        (bool success, ) = strat.strategyAddress.call(abi.encodeWithSignature("deposit(uint256)", amount));
        require(success, "Strategy deposit failed");
    }

    /**
     * @dev Harvest rewards from the strategy (for integration and testing)
     */
    function harvestFromStrategy(uint256 strategyId) external onlyOwner {
        Strategy storage strat = strategies[strategyId];
        require(strat.isActive, "Strategy not active");
        require(strat.strategyAddress != address(0), "Invalid strategy");
        (bool success, ) = strat.strategyAddress.call(abi.encodeWithSignature("harvest()"));
        require(success, "Strategy harvest failed");
    }
} 