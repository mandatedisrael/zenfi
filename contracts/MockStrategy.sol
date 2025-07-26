// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MockStrategy
 * @dev A mock strategy for testing the vault
 * 
 * Error Codes:
 * E1: Only vault can call this function
 * E2: Invalid deposit amount (must be > 0)
 * E3: Invalid withdraw amount (must be > 0)
 * E4: Insufficient balance for withdrawal
 * E5: Invalid vault address (zero address)
 * E6: Performance fee too high (max 2000 bps)
 * E7: Management fee too high (max 500 bps)
 * E8: Yield rate too high (max 5000 bps)
 */
contract MockStrategy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public want;
    IERC20 public rewardToken;
    address public vault;
    uint256 public performanceFee = 200; // 2%
    uint256 public managementFee = 50;   // 0.5%
    uint256 public yieldRate = 1000;     // 10%
    uint256 public totalDeposited;
    uint256 public lastHarvest;
    uint256 public lastYieldTime;
    uint256 public accumulatedRewards;

    // Error mapping for debugging
    mapping(string => string) public errorMessages;

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);
    event Harvested(uint256 rewards);

    constructor(address _want, address _rewardToken) Ownable(msg.sender) {
        want = IERC20(_want);
        rewardToken = IERC20(_rewardToken);
        lastHarvest = block.timestamp;
        lastYieldTime = block.timestamp;
        
        // Initialize error messages
        errorMessages["E1"] = "Only vault can call this function";
        errorMessages["E2"] = "Invalid deposit amount (must be > 0)";
        errorMessages["E3"] = "Invalid withdraw amount (must be > 0)";
        errorMessages["E4"] = "Insufficient balance for withdrawal";
        errorMessages["E5"] = "Invalid vault address (zero address)";
        errorMessages["E6"] = "Performance fee too high (max 2000 bps)";
        errorMessages["E7"] = "Management fee too high (max 500 bps)";
        errorMessages["E8"] = "Yield rate too high (max 5000 bps)";
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
        codes = new string[](8);
        messages = new string[](8);
        
        for (uint i = 1; i <= 8; i++) {
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

    modifier onlyVault() {
        require(msg.sender == vault, "E1");
        _;
    }

    /**
     * @dev Deposit funds into strategy
     */
    function deposit(uint256 _amount) external onlyVault nonReentrant {
        require(_amount > 0, "E2");
        
        want.safeTransferFrom(vault, address(this), _amount);
        totalDeposited += _amount;
        
        emit Deposited(_amount);
    }

    /**
     * @dev Withdraw funds from strategy
     */
    function withdraw(uint256 _amount) external onlyVault nonReentrant returns (uint256) {
        require(_amount > 0, "E3");
        require(_amount <= totalDeposited, "E4");
        
        want.safeTransfer(vault, _amount);
        totalDeposited -= _amount;
        
        emit Withdrawn(_amount);
        return _amount;
    }

    /**
     * @dev Harvest rewards from strategy
     */
    function harvest() external onlyVault nonReentrant returns (uint256) {
        uint256 harvested = _calculateAndMintRewards();
        
        if (harvested > 0) {
            uint256 perfFee = (harvested * performanceFee) / 10000;
            uint256 mgmtFee = (harvested * managementFee) / 10000;
            uint256 toVault = harvested - perfFee - mgmtFee;
            
            // Transfer fees to owner
            if (perfFee > 0) rewardToken.safeTransfer(owner(), perfFee);
            if (mgmtFee > 0) rewardToken.safeTransfer(owner(), mgmtFee);
            
            // Transfer rewards to vault
            if (toVault > 0) rewardToken.safeTransfer(vault, toVault);
            
            lastHarvest = block.timestamp;
            emit Harvested(harvested);
        }
        
        return harvested;
    }

    /**
     * @dev Get total value managed by strategy
     */
    function getTotalValue() external view returns (uint256) {
        return totalDeposited + getPendingRewards();
    }

    /**
     * @dev Get pending rewards
     */
    function getPendingRewards() public view returns (uint256) {
        if (totalDeposited == 0) return 0;
        
        uint256 timeElapsed = block.timestamp - lastYieldTime;
        uint256 annualYield = (totalDeposited * yieldRate) / 10000;
        
        // Calculate yield per second and multiply by elapsed time
        return (annualYield * timeElapsed) / 365 days;
    }

    /**
     * @dev Internal function to simulate reward generation
     */
    function _calculateAndMintRewards() internal returns (uint256 rewards) {
        rewards = getPendingRewards();
        
        if (rewards > 0) {
            // In a real strategy, rewards would come from external protocol
            // For mock, we simulate by checking if we have reward tokens
            uint256 available = rewardToken.balanceOf(address(this));
            
            if (available >= rewards) {
                lastYieldTime = block.timestamp;
                return rewards;
            } else {
                // If not enough reward tokens, return what we have
                lastYieldTime = block.timestamp;
                return available;
            }
        }
        
        return 0;
    }

    /**
     * @dev Emergency withdraw all funds
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = want.balanceOf(address(this));
        if (balance > 0) {
            want.safeTransfer(vault, balance);
            totalDeposited = 0;
        }
    }

    /**
     * @dev Admin functions
     */
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "E5");
        vault = _vault;
    }

    function setFees(uint256 _performanceFee, uint256 _managementFee) external onlyOwner {
        require(_performanceFee <= 2000, "E6");
        require(_managementFee <= 500, "E7");
        performanceFee = _performanceFee;
        managementFee = _managementFee;
    }

    function setYieldRate(uint256 _rate) external onlyOwner {
        require(_rate <= 5000, "E8");
        yieldRate = _rate;
    }

    /**
     * @dev Fund strategy with reward tokens (for testing)
     */
    function fundRewards(uint256 amount) external onlyOwner {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }
}