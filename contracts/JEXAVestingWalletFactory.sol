// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {JEXAVestingWallet} from "./JEXAVestingWallet.sol";
import {IJEXAVestingWalletFactory} from "./interfaces/IJEXAVestingWalletFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title JEXAVestingWalletFactory
 * @author JEXA Team
 * @notice Factory contract for creating and managing JEXA token vesting wallets
 * @dev Implements a factory pattern for deploying JEXAVestingWallet instances with centralized tracking
 *
 * Key Features:
 * - Creates new vesting wallets via direct deployment (not minimal proxies)
 * - Tracks all created wallets using OpenZeppelin's EnumerableSet
 * - Validates JEXA token contract on deployment
 * - Provides O(1) wallet validation and enumeration capabilities
 * - Emits standardized events for wallet creation tracking
 *
 * Security Features:
 * - Validates token contract has "JEXA" symbol
 * - Performs ERC20 compatibility checks
 * - Rejects zero addresses and amounts
 * - Uses SafeERC20 for secure token transfers
 *
 * Gas Considerations:
 * - Uses full contract deployment (not minimal proxies) for spawn compatibility
 * - EnumerableSet provides efficient O(1) lookups and O(n) enumeration
 * - Range queries available to avoid large array returns
 */
contract JEXAVestingWalletFactory is IJEXAVestingWalletFactory {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Expected token symbol for validation
    string private constant _EXPECTED_TOKEN_SYMBOL = "JEXA";

    /// @notice The JEXA token address
    IERC20 public immutable JEXA_TOKEN;

    /// @notice Set of all created vesting wallets
    EnumerableSet.AddressSet private _vestingWallets;

    /// @notice Emitted when a new vesting wallet is created
    /// @param wallet The address of the newly created vesting wallet
    /// @param beneficiary The beneficiary of the vesting wallet
    /// @param creator The address that created the wallet
    /// @param startTimestamp The start timestamp of the vesting
    /// @param durationSeconds The duration of the vesting
    /// @param amount The amount of JEXA tokens transferred to the wallet
    event VestingWalletCreated(
        address indexed wallet,
        address indexed beneficiary,
        address indexed creator,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint256 amount
    );

    /// @notice Error thrown when an invalid token address is provided
    error TokenAddressIsZero();

    /// @notice Error thrown when token symbol is not "JEXA"
    error InvalidTokenSymbol();

    /// @notice Error thrown when beneficiary address is zero
    error BeneficiaryIsZero();

    /// @notice Error thrown when amount is zero
    error AmountIsZero();

    /// @notice Error thrown when caller is not authorized
    error NotAuthorized();

    /// @notice Error thrown when invalid ERC20 interface
    error InvalidERC20Interface();

    /// @notice Error thrown when invalid range is provided
    error InvalidRange();

    /// @notice Constructor sets the JEXA token address with strict validation
    /// @param _JEXAToken The address of the JEXA token contract
    constructor(address _JEXAToken) {
        require(_JEXAToken != address(0), TokenAddressIsZero());

        // Validate it's a proper ERC20 token by checking the interface
        try IERC20(_JEXAToken).balanceOf(address(this)) returns (uint256) {
            // solhint-disable-previous-line no-empty-blocks
        } catch {
            revert InvalidERC20Interface();
        }

        // Validate the token symbol is exactly "JEXA"
        try IERC20Metadata(_JEXAToken).symbol() returns (string memory symbol) {
            if (keccak256(bytes(symbol)) != keccak256(bytes(_EXPECTED_TOKEN_SYMBOL))) {
                revert InvalidTokenSymbol();
            }
        } catch {
            revert InvalidERC20Interface();
        }

        JEXA_TOKEN = IERC20(_JEXAToken);
    }

    /// @notice Creates a new vesting wallet and transfers tokens to it
    /// @param beneficiary The beneficiary of the vesting wallet
    /// @param startTimestamp The start timestamp for vesting
    /// @param durationSeconds The duration of the vesting period
    /// @param amount The amount of JEXA tokens to transfer to the wallet
    /// @return wallet The address of the newly created vesting wallet
    function createVestingWallet(address beneficiary, uint64 startTimestamp, uint64 durationSeconds, uint256 amount)
        external
        override
        returns (address wallet)
    {
        require(beneficiary != address(0), BeneficiaryIsZero());
        require(amount > 0, AmountIsZero());

        // Deploy the new vesting wallet
        wallet = address(new JEXAVestingWallet(address(JEXA_TOKEN), beneficiary, startTimestamp, durationSeconds));

        // Track the new wallet
        _vestingWallets.add(wallet);

        // Transfer tokens from caller to created wallet
        JEXA_TOKEN.safeTransferFrom(msg.sender, wallet, amount);

        // Emit event for tracking
        emit VestingWalletCreated(wallet, beneficiary, msg.sender, startTimestamp, durationSeconds, amount);

        return wallet;
    }

    /// @notice Get the total number of vesting wallets created
    /// @return The total count of vesting wallets
    function getVestingWalletCount() external view returns (uint256) {
        return _vestingWallets.length();
    }

    /// @notice Check if an address is a vesting wallet created by this factory
    /// @param wallet The address to check
    /// @return True if the address is a vesting wallet, false otherwise
    function isVestingWallet(address wallet) external view returns (bool) {
        return _vestingWallets.contains(wallet);
    }

    /// @notice Get a range of vesting wallet addresses
    /// @param start The starting index
    /// @param end The ending index (exclusive)
    /// @return wallets Array of wallet addresses in the specified range
    function getVestingWallets(uint256 start, uint256 end) external view returns (address[] memory wallets) {
        require(start < end, InvalidRange());
        require(end <= _vestingWallets.length(), InvalidRange());

        wallets = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            wallets[i - start] = _vestingWallets.at(i);
        }
        return wallets;
    }

    /// @notice Get all vesting wallet addresses
    /// @return All vesting wallet addresses
    function getAllVestingWallets() external view returns (address[] memory) {
        return _vestingWallets.values();
    }
}
