// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IJEXAVestingWalletFactory} from "./interfaces/IJEXAVestingWalletFactory.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title JEXAVestingWallet
 * @author JEXA Team
 * @notice Enhanced vesting wallet with spawning capabilities for JEXA tokens
 * @dev Extends OpenZeppelin's VestingWallet with the ability to create child wallets
 *
 * Key Features:
 * - Standard linear vesting functionality from OpenZeppelin
 * - Spawn child wallets with same or worse vesting conditions
 * - Automatic token release before spawning
 * - Accurate vesting calculations with spawn tracking
 * - Factory integration for centralized wallet management
 *
 * Spawning Rules:
 * - New start time must be >= current timestamp and >= original start time
 * - New end time must be >= original end time
 * - Prevents spawning with better vesting conditions
 * - Only wallet owner can create spawns
 * - Automatic token transfer to spawned wallets
 *
 * Security Features:
 * - Validates spawning conditions to prevent privilege escalation
 * - Uses totalSpawnedAmount to prevent underflow in vesting calculations
 * - Automatic token release before spawning to maintain accuracy
 * - Only supports JEXA token to maintain focus and security
 *
 * Technical Details:
 * - Overrides vestedAmount() to handle spawned token accounting
 * - Overrides releasable() to prevent underflow issues
 * - Delegates wallet creation to factory for centralized tracking
 * - Uses SafeERC20 for secure token operations
 */
contract JEXAVestingWallet is VestingWallet {
    using SafeERC20 for IERC20;

    /// @notice The JEXA token address for vesting
    IERC20 public immutable JEXA_TOKEN;

    /// @notice The factory contract that manages wallet creation
    IJEXAVestingWalletFactory public immutable FACTORY;

    /// @notice Total amount of tokens transferred to spawned wallets
    uint256 public totalSpawnedAmount;

    /// @notice Error thrown when trying to spawn with better vesting conditions
    error InvalidVestingConditions();

    /// @notice Error thrown when trying to transfer more tokens than available
    error InsufficientBalance();

    /// @notice Error thrown when an invalid token address is provided
    error InvalidTokenAddress();

    /// @notice Error thrown when beneficiary address is zero
    error BeneficiaryIsZero();

    /// @notice Error thrown when amount is zero
    error AmountIsZero();

    /// @notice Error thrown when only JEXA token is supported
    error OnlyJEXATokenSupported();

    /// @notice Error thrown when wallet creation fails
    error WalletNotCreated();

    /// @notice Constructor sets the JEXA token address, factory address, and initializes vesting
    /// @param _JEXAToken The address of the JEXA token contract
    /// @param _beneficiary The beneficiary of the vesting wallet
    /// @param _startTimestamp The start timestamp for vesting
    /// @param _durationSeconds The duration of the vesting period
    constructor(address _JEXAToken, address _beneficiary, uint64 _startTimestamp, uint64 _durationSeconds)
        VestingWallet(_beneficiary, _startTimestamp, _durationSeconds)
    {
        require(_JEXAToken != address(0), InvalidTokenAddress());
        JEXA_TOKEN = IERC20(_JEXAToken);
        FACTORY = IJEXAVestingWalletFactory(msg.sender);
    }

    /// @notice Override receive function to disable ETH deposits
    /// @dev This contract only supports JEXA tokens, ETH deposits are not allowed
    receive() external payable virtual override {
        revert OnlyJEXATokenSupported();
    }

    /// @notice Creates a child vesting wallet with same or worse vesting conditions for JEXA tokens
    /// @dev This function redirects to the factory for wallet creation and tracking
    /// @param beneficiary The beneficiary of the new vesting wallet
    /// @param newStartTimestamp The start timestamp for the new wallet (must be >= current start)
    /// @param newDurationSeconds The duration for the new wallet (must ensure end time is >= original end time)
    /// @param amount The amount of JEXA tokens to transfer to the new wallet
    /// @return spawnedWallet The address of the newly created vesting wallet
    function spawnWallet(address beneficiary, uint64 newStartTimestamp, uint64 newDurationSeconds, uint256 amount)
        external
        onlyOwner
        returns (address spawnedWallet)
    {
        require(beneficiary != address(0), BeneficiaryIsZero());
        require(amount > 0, AmountIsZero());

        // Cache storage reads to minimize gas usage
        uint256 currentReleasable = releasable(address(JEXA_TOKEN));

        // Release any available vested tokens before spawning
        if (currentReleasable > 0) {
            release(address(JEXA_TOKEN));
        }

        // Check if we have sufficient balance
        uint256 currentBalance = JEXA_TOKEN.balanceOf(address(this));

        require(currentBalance >= amount, InsufficientBalance());

        // Cache start/duration values to avoid multiple calls
        uint64 currentStart = uint64(start());
        uint64 currentDuration = uint64(duration());
        uint64 currentEnd = currentStart + currentDuration;
        uint64 newEnd = newStartTimestamp + newDurationSeconds;

        // Validate that the new vesting conditions are same or worse
        // Prevent creating wallets that start in the past
        require(newStartTimestamp >= block.timestamp, InvalidVestingConditions());
        // Prevent creating wallets that start before the current wallet
        require(newStartTimestamp >= currentStart, InvalidVestingConditions());
        // Prevent creating wallets that end before the current wallet
        require(newEnd >= currentEnd, InvalidVestingConditions());

        // Track the spawned amount
        totalSpawnedAmount += amount;

        // Approve factory to spend the tokens for the new wallet
        JEXA_TOKEN.approve(address(FACTORY), amount);

        // Delegate wallet creation to the factory
        spawnedWallet = FACTORY.createVestingWallet(beneficiary, newStartTimestamp, newDurationSeconds, amount);

        // NOTE: The factory is trusted and will transfer the exact approved amount,
        // so no need to reset the approval to zero afterward.

        return spawnedWallet;
    }

    /// @notice Override native token release function to disable ETH processing
    /// @dev This contract only supports JEXA tokens, ETH operations are not allowed
    function release() public virtual override {
        revert OnlyJEXATokenSupported();
    }

    /// @notice Override vestedAmount to calculate vesting for this wallet only (excluding spawned amounts)
    /// @dev This prevents underflow issues when tokens are transferred out via spawning
    /// @param token The token address (must be JEXA token)
    /// @param timestamp The timestamp to calculate vesting for
    /// @return The amount of tokens vested for this specific wallet (excluding spawned amounts)
    function vestedAmount(address token, uint64 timestamp) public view virtual override returns (uint256) {
        require(token == address(JEXA_TOKEN), OnlyJEXATokenSupported());

        // Cache storage reads to minimize gas usage
        uint256 cachedTotalSpawned = totalSpawnedAmount;
        uint256 currentBalance = JEXA_TOKEN.balanceOf(address(this));
        uint256 alreadyReleased = released(token);

        // CRITICAL CALCULATION: Reconstruct original allocation
        // Formula: currentBalance + alreadyReleased + totalSpawned = originalAllocation
        // This ensures we can always calculate correct vesting even after spawning tokens
        uint256 originalAllocation = currentBalance + alreadyReleased + cachedTotalSpawned;

        // Calculate total vested amount based on original allocation and vesting schedule
        uint256 totalVested = _vestingSchedule(originalAllocation, timestamp);

        // SPAWNING ADJUSTMENT: Subtract spawned amounts from total vested
        // Why: Spawned tokens are vesting in other wallets, so they don't belong to this wallet
        // Example: If 1M original, 600k vested, 300k spawned → this wallet gets 300k vested
        if (totalVested > cachedTotalSpawned) {
            return totalVested - cachedTotalSpawned;
        } else {
            // Edge case: If total spawned exceeds vested, this wallet gets nothing
            // This can happen early in vesting when little has vested but tokens were spawned
            return 0;
        }
    }

    /// @notice Override native token vestedAmount function to disable ETH processing
    /// @dev This contract only supports JEXA tokens, ETH operations are not allowed
    /// @return Always returns 0 as ETH operations are disabled
    function vestedAmount(uint64 /* timestamp */ ) public view virtual override returns (uint256) {
        return 0; // ETH operations disabled
    }

    /// @notice Override releasable to prevent underflow using totalSpawnedAmount calculations
    /// @dev Optimized to avoid duplicate storage reads from vestedAmount call
    function releasable(address token) public view virtual override returns (uint256) {
        require(token == address(JEXA_TOKEN), OnlyJEXATokenSupported());

        // Cache storage reads to minimize gas usage
        uint256 cachedTotalSpawned = totalSpawnedAmount;
        uint256 currentBalance = JEXA_TOKEN.balanceOf(address(this));
        uint256 alreadyReleased = released(token);

        // Reconstruct original allocation (same calculation as vestedAmount)
        uint256 originalAllocation = currentBalance + alreadyReleased + cachedTotalSpawned;

        // Calculate total vested amount based on original allocation and current timestamp
        uint256 totalVested = _vestingSchedule(originalAllocation, uint64(block.timestamp));

        // Calculate vested amount for this wallet (excluding spawned amounts)
        uint256 vested = totalVested > cachedTotalSpawned ? totalVested - cachedTotalSpawned : 0;

        // Safe subtraction to prevent underflow
        return vested > alreadyReleased ? vested - alreadyReleased : 0;
    }

    /// @notice Override native token releasable function to disable ETH processing
    /// @dev This contract only supports JEXA tokens, ETH operations are not allowed
    /// @return Always returns 0 as ETH operations are disabled
    function releasable() public view virtual override returns (uint256) {
        return 0; // ETH operations disabled
    }
}
