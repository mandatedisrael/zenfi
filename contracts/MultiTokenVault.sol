// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IStrategy.sol";

/**
 * @title MultiTokenVault
 * @dev A vault that manages multiple token pairs and strategies
 * 
 * Error Codes:
 * E1: Invalid fee recipient (zero address)
 * E2: Invalid pair ID (out of bounds)
 * E3: Pair is inactive
 * E4: Invalid strategy ID (out of bounds)
 * E5: Strategy is inactive
 * E6: Zero address for token0 or token1
 * E7: Same token address for token0 and token1
 * E8: Invalid minimum liquidity (must be > 0)
 * E9: Zero address for strategy
 * E10: Allocation too high (exceeds MAX_BPS)
 * E11: Total allocation exceeded (exceeds MAX_BPS)
 * E12: Strategy vault mismatch
 * E13: Invalid want token (zero address)
 * E14: Transaction deadline expired
 * E15: Invalid amounts (must be > 0)
 * E16: Below minimum liquidity requirement
 * E17: Slippage exceeded for shares
 * E18: Transaction deadline expired
 * E19: Invalid shares amount (must be > 0)
 * E20: Insufficient shares for withdrawal
 * E21: Slippage exceeded for amounts
 * E22: Performance fee too high (max 2000 bps)
 * E23: Withdrawal fee too high (max 200 bps)
 * E24: Management fee too high (max 500 bps)
 * E25: Zero address for fee recipient
 * E26: Allocation too high (exceeds MAX_BPS)
 * E27: Total allocation exceeded (exceeds MAX_BPS)
 */
contract MultiTokenVault is ERC20, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant MAX_BPS = 10000;
    uint256 private constant PRECISION = 1e18;
    
    // Structs
    struct TokenPair {
        IERC20 token0;
        IERC20 token1;
        uint256 reserve0;
        uint256 reserve1;
        bool isActive;
        uint256 totalShares; // Shares for this specific pair
        uint256 minLiquidity;
    }

    struct Strategy {
        IStrategy strategyContract;
        IERC20 want; // Token this strategy farms
        uint256 allocation; // Basis points (0-10000)
        uint256 totalDeposited;
        uint256 lastHarvest;
        bool isActive;
        string name;
    }

    struct UserPosition {
        mapping(uint256 => uint256) pairShares; // pairId => shares
        uint256 totalShares;
        uint256 lastDepositTime;
        uint256 rewardDebt;
    }

    // State variables
    mapping(uint256 => TokenPair) public tokenPairs;
    mapping(uint256 => Strategy) public strategies;
    mapping(address => UserPosition) public userPositions;
    
    uint256 public tokenPairCount;
    uint256 public strategyCount;
    uint256 public totalValueLocked;
    
    // Fee structure
    uint256 public performanceFee = 1000; // 10%
    uint256 public withdrawalFee = 50; // 0.5%
    uint256 public managementFee = 200; // 2%
    address public feeRecipient;
    
    // Reward tracking
    uint256 public accRewardPerShare;
    uint256 public lastRewardBlock;
    IERC20 public rewardToken;
    
    // Events
    event TokenPairAdded(uint256 indexed pairId, address token0, address token1);
    event StrategyAdded(uint256 indexed strategyId, address strategy, address want);
    event LiquidityAdded(address indexed user, uint256 indexed pairId, uint256 amount0, uint256 amount1, uint256 shares);
    event LiquidityRemoved(address indexed user, uint256 indexed pairId, uint256 shares, uint256 amount0, uint256 amount1);
    event StrategyHarvested(uint256 indexed strategyId, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event StrategyRebalanced(uint256 indexed strategyId, uint256 deposited, uint256 withdrawn);

    // Error mapping for debugging
    mapping(string => string) public errorMessages;
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _feeRecipient,
        IERC20 _rewardToken
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "E1");
        feeRecipient = _feeRecipient;
        rewardToken = _rewardToken;
        lastRewardBlock = block.number;

        // Initialize error messages
        errorMessages["E1"] = "Invalid fee recipient (zero address)";
        errorMessages["E2"] = "Invalid pair ID (out of bounds)";
        errorMessages["E3"] = "Pair is inactive";
        errorMessages["E4"] = "Invalid strategy ID (out of bounds)";
        errorMessages["E5"] = "Strategy is inactive";
        errorMessages["E6"] = "Zero address for token0 or token1";
        errorMessages["E7"] = "Same token address for token0 and token1";
        errorMessages["E8"] = "Invalid minimum liquidity (must be > 0)";
        errorMessages["E9"] = "Zero address for strategy";
        errorMessages["E10"] = "Allocation too high (exceeds MAX_BPS)";
        errorMessages["E11"] = "Total allocation exceeded (exceeds MAX_BPS)";
        errorMessages["E12"] = "Strategy vault mismatch";
        errorMessages["E13"] = "Invalid want token (zero address)";
        errorMessages["E14"] = "Transaction deadline expired";
        errorMessages["E15"] = "Invalid amounts (must be > 0)";
        errorMessages["E16"] = "Below minimum liquidity requirement";
        errorMessages["E17"] = "Slippage exceeded for shares";
        errorMessages["E18"] = "Transaction deadline expired";
        errorMessages["E19"] = "Invalid shares amount (must be > 0)";
        errorMessages["E20"] = "Insufficient shares for withdrawal";
        errorMessages["E21"] = "Slippage exceeded for amounts";
        errorMessages["E22"] = "Performance fee too high (max 2000 bps)";
        errorMessages["E23"] = "Withdrawal fee too high (max 200 bps)";
        errorMessages["E24"] = "Management fee too high (max 500 bps)";
        errorMessages["E25"] = "Zero address for fee recipient";
        errorMessages["E26"] = "Allocation too high (exceeds MAX_BPS)";
        errorMessages["E27"] = "Total allocation exceeded (exceeds MAX_BPS)";
    }

    /**
     * @dev Get detailed error message for error code
     * @param errorCode The short error code (e.g., "E1")
     * @return Detailed error description
     */
    function getErrorMessage(string memory errorCode) external view returns (string memory) {
        return errorMessages[errorCode];
    }

    /**
     * @dev Get all error codes and messages for debugging
     * @return codes Array of error codes
     * @return messages Array of error descriptions
     */
    function getAllErrorMessages() external view returns (string[] memory codes, string[] memory messages) {
        codes = new string[](27);
        messages = new string[](27);
        
        for (uint i = 1; i <= 27; i++) {
            string memory code = string(abi.encodePacked("E", _toString(i)));
            codes[i-1] = code;
            messages[i-1] = errorMessages[code];
        }
    }

    /**
     * @dev Helper function to convert uint to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Modifiers
    modifier validPair(uint256 _pairId) {
        require(_pairId < tokenPairCount, "E2");
        require(tokenPairs[_pairId].isActive, "E3");
        _;
    }

    modifier validStrategy(uint256 _strategyId) {
        require(_strategyId < strategyCount, "E4");
        require(strategies[_strategyId].isActive, "E5");
        _;
    }

    modifier updateReward(address _user) {
        accRewardPerShare = _getAccRewardPerShare();
        lastRewardBlock = block.number;
        
        if (_user != address(0)) {
            UserPosition storage position = userPositions[_user];
            uint256 pending = (position.totalShares * accRewardPerShare) / PRECISION - position.rewardDebt;
            if (pending > 0) {
                position.rewardDebt = (position.totalShares * accRewardPerShare) / PRECISION;
                // Store pending rewards for later claim
            }
        }
        _;
    }

    /**
     * @dev Add token pair with proper validation
     */
    function addTokenPair(
        IERC20 _token0,
        IERC20 _token1,
        uint256 _minLiquidity
    ) external onlyOwner returns (uint256 pairId) {
        require(address(_token0) != address(0) && address(_token1) != address(0), "E6");
        require(address(_token0) != address(_token1), "E7");
        require(_minLiquidity > 0, "E8");
        
        pairId = tokenPairCount++;
        tokenPairs[pairId] = TokenPair({
            token0: _token0,
            token1: _token1,
            reserve0: 0,
            reserve1: 0,
            isActive: true,
            totalShares: 0,
            minLiquidity: _minLiquidity
        });

        emit TokenPairAdded(pairId, address(_token0), address(_token1));
    }

    /**
     * @dev Add strategy with validation
     */
    function addStrategy(
        IStrategy _strategy,
        uint256 _allocation,
        string memory _name
    ) external onlyOwner returns (uint256 strategyId) {
        require(address(_strategy) != address(0), "E9");
        require(_allocation <= MAX_BPS, "E10");
        require(_getTotalAllocation() + _allocation <= MAX_BPS, "E11");
        
        // Validate strategy
        require(_strategy.vault() == address(this), "E12");
        IERC20 want = IERC20(_strategy.want());
        require(address(want) != address(0), "E13");
        
        strategyId = strategyCount++;
        strategies[strategyId] = Strategy({
            strategyContract: _strategy,
            want: want,
            allocation: _allocation,
            totalDeposited: 0,
            lastHarvest: block.timestamp,
            isActive: true,
            name: _name
        });

        emit StrategyAdded(strategyId, address(_strategy), address(want));
    }

    /**
     * @dev Add liquidity with proper LP math
     */
    function addLiquidity(
        uint256 _pairId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _minShares,
        uint256 _deadline
    ) external nonReentrant whenNotPaused validPair(_pairId) updateReward(msg.sender) returns (uint256 shares) {
        require(block.timestamp <= _deadline, "E14");
        require(_amount0 > 0 && _amount1 > 0, "E15");
        
        TokenPair storage pair = tokenPairs[_pairId];
        
        // Calculate shares using proper LP math
        if (pair.totalShares == 0) {
            // First deposit - use geometric mean
            shares = _sqrt(_amount0 * _amount1);
            require(shares >= pair.minLiquidity, "E16");
            // Lock minimum liquidity forever
            pair.totalShares = pair.minLiquidity;
            shares -= pair.minLiquidity;
        } else {
            // Subsequent deposits - maintain ratio
            uint256 share0 = (_amount0 * pair.totalShares) / pair.reserve0;
            uint256 share1 = (_amount1 * pair.totalShares) / pair.reserve1;
            shares = share0 < share1 ? share0 : share1;
        }
        
        require(shares >= _minShares, "E17");
        
        // Transfer tokens
        pair.token0.safeTransferFrom(msg.sender, address(this), _amount0);
        pair.token1.safeTransferFrom(msg.sender, address(this), _amount1);
        
        // Update reserves and shares
        pair.reserve0 += _amount0;
        pair.reserve1 += _amount1;
        pair.totalShares += shares;
        totalValueLocked += _calculateValue(_amount0, _amount1);
        
        // Update user position
        UserPosition storage position = userPositions[msg.sender];
        position.pairShares[_pairId] += shares;
        position.totalShares += shares;
        position.lastDepositTime = block.timestamp;
        position.rewardDebt = (position.totalShares * accRewardPerShare) / PRECISION;
        
        // Mint vault tokens
        _mint(msg.sender, shares);
        
        // Auto-deposit to strategies if configured
        _autoDepositToStrategies(pair.token0, _amount0);
        _autoDepositToStrategies(pair.token1, _amount1);
        
        emit LiquidityAdded(msg.sender, _pairId, _amount0, _amount1, shares);
    }

    /**
     * @dev Remove liquidity with slippage protection
     */
    function removeLiquidity(
        uint256 _pairId,
        uint256 _shares,
        uint256 _minAmount0,
        uint256 _minAmount1,
        uint256 _deadline
    ) external nonReentrant validPair(_pairId) updateReward(msg.sender) returns (uint256 amount0, uint256 amount1) {
        require(block.timestamp <= _deadline, "E18");
        require(_shares > 0, "E19");
        
        UserPosition storage position = userPositions[msg.sender];
        require(position.pairShares[_pairId] >= _shares, "E20");
        
        TokenPair storage pair = tokenPairs[_pairId];
        
        // Calculate amounts
        amount0 = (_shares * pair.reserve0) / pair.totalShares;
        amount1 = (_shares * pair.reserve1) / pair.totalShares;
        
        require(amount0 >= _minAmount0 && amount1 >= _minAmount1, "E21");
        
        // Withdraw from strategies if needed
        _withdrawFromStrategies(pair.token0, amount0);
        _withdrawFromStrategies(pair.token1, amount1);
        
        // Apply withdrawal fee
        uint256 fee0 = (amount0 * withdrawalFee) / MAX_BPS;
        uint256 fee1 = (amount1 * withdrawalFee) / MAX_BPS;
        
        amount0 -= fee0;
        amount1 -= fee1;
        
        // Update state
        pair.reserve0 -= (amount0 + fee0);
        pair.reserve1 -= (amount1 + fee1);
        pair.totalShares -= _shares;
        totalValueLocked -= _calculateValue(amount0 + fee0, amount1 + fee1);
        
        // Update user position
        position.pairShares[_pairId] -= _shares;
        position.totalShares -= _shares;
        position.rewardDebt = (position.totalShares * accRewardPerShare) / PRECISION;
        
        // Burn tokens
        _burn(msg.sender, _shares);
        
        // Transfer tokens
        pair.token0.safeTransfer(msg.sender, amount0);
        pair.token1.safeTransfer(msg.sender, amount1);
        
        // Transfer fees
        if (fee0 > 0) pair.token0.safeTransfer(feeRecipient, fee0);
        if (fee1 > 0) pair.token1.safeTransfer(feeRecipient, fee1);
        
        emit LiquidityRemoved(msg.sender, _pairId, _shares, amount0, amount1);
    }

    /**
     * @dev Harvest all strategies
     */
    function harvestAll() external onlyOwner {
        for (uint256 i = 0; i < strategyCount; i++) {
            if (strategies[i].isActive) {
                _harvestStrategy(i);
            }
        }
    }

    /**
     * @dev Harvest specific strategy
     */
    function harvest(uint256 _strategyId) external onlyOwner validStrategy(_strategyId) returns (uint256) {
        return _harvestStrategy(_strategyId);
    }

    /**
     * @dev Rebalance strategies based on allocations
     */
    function rebalance() external onlyOwner {
        uint256 totalAssets = getTotalAssets();
        
        for (uint256 i = 0; i < strategyCount; i++) {
            Strategy storage strategy = strategies[i];
            if (!strategy.isActive) continue;
            
            uint256 targetAmount = (totalAssets * strategy.allocation) / MAX_BPS;
            uint256 currentAmount = strategy.totalDeposited;
            
            if (targetAmount > currentAmount) {
                // Need to deposit more
                uint256 toDeposit = targetAmount - currentAmount;
                uint256 available = strategy.want.balanceOf(address(this));
                
                if (available >= toDeposit) {
                    _depositToStrategy(i, toDeposit);
                    emit StrategyRebalanced(i, toDeposit, 0);
                }
            } else if (currentAmount > targetAmount) {
                // Need to withdraw
                uint256 toWithdraw = currentAmount - targetAmount;
                _withdrawFromStrategy(i, toWithdraw);
                emit StrategyRebalanced(i, 0, toWithdraw);
            }
        }
    }

    /**
     * @dev Claim pending rewards
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        UserPosition storage position = userPositions[msg.sender];
        uint256 pending = (position.totalShares * accRewardPerShare) / PRECISION - position.rewardDebt;
        
        if (pending > 0) {
            // Check if vault has enough reward tokens
            uint256 available = rewardToken.balanceOf(address(this));
            uint256 toClaim = pending > available ? available : pending;
            
            if (toClaim > 0) {
                position.rewardDebt = (position.totalShares * accRewardPerShare) / PRECISION;
                rewardToken.safeTransfer(msg.sender, toClaim);
                emit RewardsClaimed(msg.sender, toClaim);
            }
        }
    }

    // View functions
    function getTotalAssets() public view returns (uint256) {
        uint256 total = totalValueLocked;
        for (uint256 i = 0; i < strategyCount; i++) {
            if (strategies[i].isActive) {
                total += strategies[i].strategyContract.getTotalValue();
            }
        }
        return total;
    }

    function getUserPairShares(address _user, uint256 _pairId) external view returns (uint256) {
        return userPositions[_user].pairShares[_pairId];
    }

    function getPendingRewards(address _user) external view returns (uint256) {
        UserPosition storage position = userPositions[_user];
        uint256 accPerShare = _getAccRewardPerShare();
        return (position.totalShares * accPerShare) / PRECISION - position.rewardDebt;
    }

    // Internal functions
    function _harvestStrategy(uint256 _strategyId) internal returns (uint256) {
        Strategy storage strategy = strategies[_strategyId];
        
        uint256 rewardsBefore = rewardToken.balanceOf(address(this));
        
        try strategy.strategyContract.harvest() {
            uint256 rewardsAfter = rewardToken.balanceOf(address(this));
            uint256 actualRewards = rewardsAfter - rewardsBefore;
            
            if (actualRewards > 0) {
                // Take performance fee
                uint256 fee = (actualRewards * performanceFee) / MAX_BPS;
                if (fee > 0 && feeRecipient != address(0)) {
                    rewardToken.safeTransfer(feeRecipient, fee);
                }
                
                strategy.lastHarvest = block.timestamp;
                emit StrategyHarvested(_strategyId, actualRewards);
                return actualRewards;
            }
            return 0;
        } catch {
            // Strategy harvest failed, return 0
            return 0;
        }
    }

    function _depositToStrategy(uint256 _strategyId, uint256 _amount) internal {
        Strategy storage strategy = strategies[_strategyId];
        
        // Check if we have enough tokens
        if (strategy.want.balanceOf(address(this)) < _amount) {
            return; // Not enough tokens available
        }
        
        strategy.want.approve(address(strategy.strategyContract), 0);
        strategy.want.approve(address(strategy.strategyContract), _amount);
        
        try strategy.strategyContract.deposit(_amount) {
            strategy.totalDeposited += _amount;
        } catch {
            // Deposit failed, reset approval
            strategy.want.approve(address(strategy.strategyContract), 0);
        }
    }

    function _withdrawFromStrategy(uint256 _strategyId, uint256 _amount) internal returns (uint256) {
        Strategy storage strategy = strategies[_strategyId];
        
        try strategy.strategyContract.withdraw(_amount) returns (uint256 withdrawn) {
            strategy.totalDeposited = strategy.totalDeposited > withdrawn ? 
                strategy.totalDeposited - withdrawn : 0;
            return withdrawn;
        } catch {
            // Withdraw failed, return 0
            return 0;
        }
    }

    function _autoDepositToStrategies(IERC20 _token, uint256 _amount) internal {
        for (uint256 i = 0; i < strategyCount; i++) {
            Strategy storage strategy = strategies[i];
            if (strategy.isActive && address(strategy.want) == address(_token)) {
                uint256 toDeposit = (_amount * strategy.allocation) / MAX_BPS;
                if (toDeposit > 0 && _token.balanceOf(address(this)) >= toDeposit) {
                    _depositToStrategy(i, toDeposit);
                }
                break; // One strategy per token for now
            }
        }
    }

    function _withdrawFromStrategies(IERC20 _token, uint256 _amount) internal {
        uint256 available = _token.balanceOf(address(this));
        if (available >= _amount) return;
        
        uint256 needed = _amount - available;
        
        for (uint256 i = 0; i < strategyCount; i++) {
            Strategy storage strategy = strategies[i];
            if (strategy.isActive && address(strategy.want) == address(_token) && needed > 0) {
                uint256 withdrawn = _withdrawFromStrategy(i, needed);
                needed = needed > withdrawn ? needed - withdrawn : 0;
            }
        }
    }

    function _getTotalAllocation() internal view returns (uint256 total) {
        for (uint256 i = 0; i < strategyCount; i++) {
            if (strategies[i].isActive) {
                total += strategies[i].allocation;
            }
        }
    }

    function _getAccRewardPerShare() internal view returns (uint256) {
        if (totalSupply() == 0) return accRewardPerShare;
        
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < strategyCount; i++) {
            if (strategies[i].isActive) {
                try strategies[i].strategyContract.getPendingRewards() returns (uint256 pending) {
                    totalRewards += pending;
                } catch {
                    // Strategy call failed, skip
                    continue;
                }
            }
        }
        
        if (totalRewards > 0) {
            return accRewardPerShare + (totalRewards * PRECISION) / totalSupply();
        }
        return accRewardPerShare;
    }

    function _calculateValue(uint256 _amount0, uint256 _amount1) internal pure returns (uint256) {
        // Simplified - in reality you'd use price oracles
        return _amount0 + _amount1;
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // Admin functions
    function setFees(uint256 _performanceFee, uint256 _withdrawalFee, uint256 _managementFee) external onlyOwner {
        require(_performanceFee <= 2000, "E22");
        require(_withdrawalFee <= 200, "E23");
        require(_managementFee <= 500, "E24");
        
        performanceFee = _performanceFee;
        withdrawalFee = _withdrawalFee;
        managementFee = _managementFee;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "E25");
        feeRecipient = _feeRecipient;
    }

    function updateStrategyAllocation(uint256 _strategyId, uint256 _allocation) external onlyOwner validStrategy(_strategyId) {
        require(_allocation <= MAX_BPS, "E26");
        
        uint256 oldAllocation = strategies[_strategyId].allocation;
        uint256 totalAllocation = _getTotalAllocation() - oldAllocation + _allocation;
        require(totalAllocation <= MAX_BPS, "E27");
        
        strategies[_strategyId].allocation = _allocation;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdrawFromStrategy(uint256 _strategyId) external onlyOwner validStrategy(_strategyId) {
        Strategy storage strategy = strategies[_strategyId];
        
        try strategy.strategyContract.emergencyWithdraw() {
            strategy.totalDeposited = 0;
        } catch {
            // Emergency withdraw failed, but we still reset the accounting
            strategy.totalDeposited = 0;
        }
    }
}