// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IJEXAVestingWalletFactory
 * @author JEXA Team
 * @notice Interface for the JEXAVestingWalletFactory contract
 * @dev This interface defines the factory pattern for creating JEXA token vesting wallets
 * with centralized tracking and management capabilities
 */
interface IJEXAVestingWalletFactory {
    /**
     * @notice Creates a new vesting wallet and transfers JEXA tokens to it
     * @dev This function creates a new JEXAVestingWallet instance and transfers tokens from caller
     * @param beneficiary The address that will receive the vested tokens
     * @param startTimestamp The Unix timestamp when vesting begins
     * @param durationSeconds The duration of the vesting period in seconds
     * @param amount The amount of JEXA tokens to transfer to the new wallet
     * @return wallet The address of the newly created vesting wallet
     *
     * Requirements:
     * - `beneficiary` cannot be the zero address
     * - `amount` must be greater than zero
     * - Caller must have sufficient JEXA token balance
     * - Caller must have approved the factory to spend `amount` tokens
     *
     * Emits a `VestingWalletCreated` event
     */
    function createVestingWallet(address beneficiary, uint64 startTimestamp, uint64 durationSeconds, uint256 amount)
        external
        returns (address wallet);
}
