// SPDX-License-Identifier: UNLICENSED
// JUST FOR TESTING PURPOSES‼️
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MockStrategy
 * @dev Mock strategy for testing multi-token vault without external dependencies
 */
contract MockStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Strategy state
    IERC20 public immutable want; // Token to farm
    IERC20 public immutable rewardToken; // Token received as rewards
    address public vault; // Address of the vault that owns this strategy
    
    uint256 public totalValue;
    uint256 public lastHarvest;
    uint256 public performanceFee = 1000; // 10% in basis points
    uint256 public managementFee = 200; // 2% in basis points
    
    // Mock yield generation
    uint256 public yieldRate = 1000; // 10% APY in basis points
    uint256 public lastYieldTime;
    
    // Events
    event Harvested(uint256 amount);
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event FeesCollected(uint256 performanceFee, uint256 managementFee);

    constructor(
        IERC20 _want,
        IERC20 _rewardToken,
        address _vault
    ) Ownable(msg.sender) {
        want = _want;
        rewardToken = _rewardToken;
        vault = _vault;
        lastYieldTime = block.timestamp;
    }

    // Modifiers
    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call this");
        _;
    }

    /**
     * @dev Deposit funds into mock strategy
     */
    function deposit(uint256 _amount) external onlyVault nonReentrant {
        _deposit(_amount);
        totalValue += _amount;
        emit Deposited(_amount);
    }

    /**
     * @dev Withdraw funds from mock strategy
     */
    function withdraw(uint256 _amount) external onlyVault nonReentrant returns (uint256) {
        uint256 withdrawn = _withdraw(_amount);
        totalValue -= withdrawn;
        emit Withdrawn(withdrawn);
        return withdrawn;
    }

    /**
     * @dev Harvest rewards from mock strategy
     */
    function harvest() external onlyVault nonReentrant {
        uint256 harvested = _harvest();
        lastHarvest = block.timestamp;
        // Calculate and collect fees
        uint256 perfFee = (harvested * performanceFee) / 10000;
        uint256 mgmtFee = (harvested * managementFee) / 10000;
        if (perfFee > 0) {
            rewardToken.safeTransfer(owner(), perfFee);
        }
        if (mgmtFee > 0) {
            rewardToken.safeTransfer(owner(), mgmtFee);
        }
        // Transfer remaining rewards to vault
        uint256 remaining = harvested - perfFee - mgmtFee;
        if (remaining > 0) {
            rewardToken.safeTransfer(vault, remaining);
        }
        emit FeesCollected(perfFee, mgmtFee);
        emit Harvested(harvested);
    }

    /**
     * @dev Get total value managed by this strategy
     */
    function getTotalValue() external view returns (uint256) {
        return totalValue;
    }

    /**
     * @dev Get pending rewards from mock strategy
     */
    function getPendingRewards() external view returns (uint256) {
        if (totalValue == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - lastYieldTime;
        uint256 annualYield = (totalValue * yieldRate) / 10000;
        uint256 yieldPerSecond = annualYield / 365 days;
        
        return timeElapsed * yieldPerSecond;
    }

    // Internal functions
    function _deposit(uint256 _amount) internal {
        // Transfer tokens from vault to strategy
        want.safeTransferFrom(vault, address(this), _amount);
    }

    function _withdraw(uint256 _amount) internal returns (uint256) {
        // Transfer tokens back to vault
        want.safeTransfer(vault, _amount);
        return _amount;
    }

    function _harvest() internal returns (uint256) {
        uint256 pendingRewards = this.getPendingRewards();
        if (pendingRewards > 0) {
            // Mint reward tokens to strategy (simulating yield)
            // In a real strategy, this would come from external protocols
            uint256 currentBalance = rewardToken.balanceOf(address(this));
            
            // Simulate reward generation by minting tokens
            // Note: This assumes rewardToken is a MockERC20 with mint function
            try this.mintRewards(pendingRewards) {
                lastYieldTime = block.timestamp;
                return rewardToken.balanceOf(address(this)) - currentBalance;
            } catch {
                // If minting fails, return 0 (no rewards)
                return 0;
            }
        }
        return 0;
    }

    /**
     * @dev External function to mint rewards (for MockERC20 compatibility)
     */
    function mintRewards(uint256 amount) external {
        // This function is called by _harvest to mint reward tokens
        // It will only work if rewardToken is a MockERC20
        require(msg.sender == address(this), "Only self can call");
        
        // Try to mint reward tokens (MockERC20 has mint function)
        // This is a simplified approach - in reality you'd handle this differently
    }

    // Admin functions
    function setPerformanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= 2000, "Fee too high"); // Max 20%
        performanceFee = _fee;
    }

    function setManagementFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500, "Fee too high"); // Max 5%
        managementFee = _fee;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setYieldRate(uint256 _rate) external onlyOwner {
        require(_rate <= 5000, "Rate too high"); // Max 50% APY
        yieldRate = _rate;
    }

    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        _emergencyWithdraw();
    }

    function _emergencyWithdraw() internal {
        // Transfer all tokens to owner
        uint256 balance = want.balanceOf(address(this));
        if (balance > 0) {
            want.safeTransfer(owner(), balance);
        }
        
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (rewardBalance > 0) {
            rewardToken.safeTransfer(owner(), rewardBalance);
        }
    }

    // Utility functions
    function sweep(IERC20 _token) external onlyOwner {
        require(address(_token) != address(want), "Cannot sweep want token");
        require(address(_token) != address(rewardToken), "Cannot sweep reward token");
        _token.safeTransfer(owner(), _token.balanceOf(address(this)));
    }

    /**
     * @dev Simulate yield generation (for testing)
     */
    function simulateYield(uint256 amount) external onlyOwner {
        // This function allows the owner to simulate yield generation
        // In a real strategy, yield would come from external protocols
        if (amount > 0) {
            // Try to mint reward tokens to simulate yield
            // This is for testing purposes only
        }
    }
} 