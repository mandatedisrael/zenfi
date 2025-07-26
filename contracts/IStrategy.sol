// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStrategy {
    function vault() external view returns (address);
    function want() external view returns (address);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256);
    function harvest() external returns (uint256);
    function getTotalValue() external view returns (uint256);
    function getPendingRewards() external view returns (uint256);
    function emergencyWithdraw() external;
} 