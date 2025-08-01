// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title JEXAVestingNFT – linear vesting positions represented by ERC-721 tokens
/// @notice Each NFT locks a fixed amount of JEXA tokens and linearly releases
///         them to the current owner during the vesting period. The contract
///         allows an owner to claim unlocked tokens (`release`), split a
///         position by future dates (`splitByDates`) or by amounts
///         (`splitByAmounts`), and to extend the vesting period (`setEndDate`).
///         Metadata for every token is served off-chain at
///         https://jexica.ai/vesting/{tokenId}/metadata.json so that wallets
///         and marketplaces can present the vesting schedule to users.
///
contract JEXAVestingNFT is ERC721, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    // Use Ethereum genesis block timestamp as a special value for the first timestamp, to encode the current time
    // as a timestamp. This is a hack to avoid having to pass the current time to the splitByDates function.
    // This value is believed not to be used by accident like 0 or 1.
    uint64 private constant _USE_CURRENT_TIMESTAMP = uint64(1438226773); // Jul-30-2015 03:26:13 PM +UTC

    /* ---------------------------------------------------------------------
                                   Storage
    --------------------------------------------------------------------- */

    struct VestingPosition {
        uint64 startTime; // Timestamp when vesting starts
        uint64 duration; // Total length of the vesting period (seconds)
        uint256 amount; // Total amount originally locked
        uint256 released; // Amount already released to owners
    }

    /// @notice Mapping of tokenId to vesting position
    mapping(uint256 tokenId => VestingPosition position) private _vesting;

    /// @notice Incrementing counter for the next tokenId
    uint256 private _nextId;

    /// @notice Address of the JEXA ERC-20 token that is being vested
    IERC20 public immutable JEXA_TOKEN;

    /// @notice Symbol check for extra safety during deployment
    string private constant _EXPECTED_TOKEN_SYMBOL = "JEXA";

    /// @notice Base URI for metadata
    string private constant _BASE_URI = "https://vesting.jexica.ai/api/nft-metadata/";

    /* ---------------------------------------------------------------------
                                     Events
    --------------------------------------------------------------------- */

    /// @notice Emitted when a new vesting NFT is minted
    /// @param creator The address that minted the vesting NFT
    /// @param tokenId The ID of the minted vesting NFT
    /// @param amount The amount of JEXA tokens that were locked
    /// @param startTime The timestamp when the vesting starts
    /// @param duration The duration of the vesting period
    event VestingNFTMinted(
        address indexed creator, uint256 indexed tokenId, uint256 amount, uint64 startTime, uint64 duration
    );

    /// @notice Emitted when tokens are released to the current owner
    /// @param tokenId The ID of the vesting NFT
    /// @param amount The amount of JEXA tokens that were released
    event TokensReleased(uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when a vesting NFT is split
    /// @param owner The address that owns the original vesting NFT
    /// @param originalId The ID of the original vesting NFT
    /// @param newTokenIds The IDs of the new vesting NFTs
    event VestingNFTSplit(address indexed owner, uint256 indexed originalId, uint256[] newTokenIds);

    /// @notice Emitted when the end date of a vesting NFT is extended
    /// @param tokenId The ID of the vesting NFT
    /// @param newEnd The new end date of the vesting NFT
    event EndDateExtended(uint256 indexed tokenId, uint64 newEnd);

    /* ---------------------------------------------------------------------
                                   Errors
    --------------------------------------------------------------------- */

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();
    /// @notice Thrown when an invalid ERC-20 token is provided
    error InvalidERC20();
    /// @notice Thrown when an invalid token symbol is provided
    error InvalidTokenSymbol();
    /// @notice Thrown when there is nothing to release
    error NothingToRelease();
    /// @notice Thrown when there is nothing to split
    error NothingToSplit();
    /// @notice Thrown when invalid timestamps are provided
    error InvalidTimestamps();
    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();
    /// @notice Thrown when an invalid duration is provided
    error InvalidDuration();
    /// @notice Thrown when invalid amounts are provided
    error InvalidAmounts();
    /// @notice Thrown when the new end date is too early
    error NewEndTooEarly();
    /// @notice Thrown when the caller is not the owner
    error OnlyOwner();

    /* ---------------------------------------------------------------------
                                  Modifier
    --------------------------------------------------------------------- */

    /// @notice Modifier to check if the caller is the owner
    /// @param tokenId The ID of the vesting NFT
    modifier onlyOwner(uint256 tokenId) {
        if (_requireOwned(tokenId) != msg.sender) revert OnlyOwner();
        _;
    }

    /* ---------------------------------------------------------------------
                                Constructor
    --------------------------------------------------------------------- */

    /// @notice Constructor to initialize the JEXAVestingNFT contract
    /// @param jexaToken The address of the JEXA ERC-20 token that is being vested
    constructor(address jexaToken) ERC721("JEXAVestingNFT", "JEXA-VEST") {
        if (jexaToken == address(0)) revert ZeroAddress();

        JEXA_TOKEN = IERC20(jexaToken);
    }

    /* ---------------------------------------------------------------------
                                 Mint logic
    --------------------------------------------------------------------- */

    /// @notice Creates a new vesting position NFT by locking `amount` JEXA.
    /// @param startTime Timestamp when linear vesting starts (could be now or the future).
    /// @param duration  Total duration in seconds – must be > 0.
    /// @param amount    Amount of JEXA to lock – must be > 0. It is transferred
    ///                  from the caller to this contract.
    /// @return tokenId The ID of the minted vesting NFT
    function mintVesting(uint64 startTime, uint64 duration, uint256 amount) external returns (uint256 tokenId) {
        // Checks
        if (duration == 0) revert InvalidDuration();
        if (amount == 0) revert InvalidAmount();

        // Effects
        unchecked {
            ++_nextId;
        }
        tokenId = _nextId;

        _vesting[tokenId] = VestingPosition({startTime: startTime, duration: duration, amount: amount, released: 0});

        // Interactions
        // 1. Pull tokens
        JEXA_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        // 2. Mint NFT (may invoke onERC721Received on receiver)
        _safeMint(msg.sender, tokenId);

        emit VestingNFTMinted(msg.sender, tokenId, amount, startTime, duration);
    }

    /* ---------------------------------------------------------------------
                                 Release
    --------------------------------------------------------------------- */

    /// @notice Releases all claimable tokens to the current owner.
    /// @param tokenId The ID of the vesting NFT
    function release(uint256 tokenId) public onlyOwner(tokenId) {
        uint256 toRelease = _release(tokenId);
        if (toRelease == 0) revert NothingToRelease();
    }

    /// @notice Internal function to release tokens from a vesting NFT
    /// @param tokenId The ID of the vesting NFT
    /// @return toRelease The amount of tokens that were released
    function _release(uint256 tokenId) internal returns (uint256 toRelease) {
        toRelease = claimable(tokenId);
        if (toRelease == 0) return 0;

        // Effects
        _vesting[tokenId].released += toRelease;
        address owner = ownerOf(tokenId);

        // burn if finished
        if (_vesting[tokenId].released == _vesting[tokenId].amount) {
            _burn(tokenId);
            delete _vesting[tokenId];
        }
        // Interaction
        JEXA_TOKEN.safeTransfer(owner, toRelease);
        emit TokensReleased(tokenId, toRelease);
    }

    /* ---------------------------------------------------------------------
                           Splitting by future dates
    --------------------------------------------------------------------- */

    /// @notice Splits a vesting NFT into new NFTs according to the supplied timeline.
    /// @dev    Rules & invariants:
    ///      • `timestamps.length >= 2` and strictly increasing.
    ///      • Special case: if `timestamps[0] == _USE_CURRENT_TIMESTAMP` (the Ethereum
    ///        genesis timestamp 1438226773) it is replaced with `block.timestamp` so
    ///        callers can signal “now” without reading the chain clock.
    ///      • `scheduleStart = max(original.startTime, block.timestamp, firstTimestamp)`.
    ///        The vesting _end_ (`original.startTime + original.duration`) never moves
    ///        earlier (no-acceleration guarantee).
    ///      • Number of resulting NFTs is `timestamps.length - 1`.
    ///      • Remaining locked amount & duration are split _iteratively_ so that any
    ///        rounding dust is spread across slices; final asserts ensure zero
    ///        leftovers.
    /// @param tokenId The ID of the vesting NFT
    /// @param timestamps The timestamps at which the vesting NFTs will be split
    /// @return newTokenIds The IDs of the new vesting NFTs
    function splitByDates(uint256 tokenId, uint64[] calldata timestamps)
        external
        nonReentrant
        onlyOwner(tokenId)
        returns (uint256[] memory newTokenIds)
    {
        // Must specify at least two timestamps to form one interval
        if (timestamps.length < 2) revert InvalidTimestamps();
        // Strictly increasing order
        for (uint256 i = 1; i < timestamps.length; ++i) {
            if (timestamps[i] <= timestamps[i - 1]) revert InvalidTimestamps();
        }

        // First, release everything vested so far.
        _release(tokenId);

        VestingPosition memory vp = _vesting[tokenId];
        if (vp.amount == 0) revert NothingToSplit(); // already empty & burned in release()

        uint64 originalStart = vp.startTime;
        uint64 originalEnd = vp.startTime + vp.duration;

        uint64 scheduleStart = timestamps[0];
        // special case: first timestamp is , use current block timestamp
        if (scheduleStart == _USE_CURRENT_TIMESTAMP) {
            scheduleStart = uint64(block.timestamp);
        }

        // First timestamp cannot be in the past relative to already vested part
        uint64 minStart = originalStart > uint64(block.timestamp) ? originalStart : uint64(block.timestamp);
        if (scheduleStart < minStart) revert InvalidTimestamps();

        // Last timestamp must not unlock faster than original schedule
        if (timestamps[timestamps.length - 1] < originalEnd) revert InvalidTimestamps();

        uint256 intervalCount = timestamps.length - 1;
        newTokenIds = new uint256[](intervalCount);

        uint256 remainingAmount = vp.amount - vp.released;
        uint256 remainingDuration = timestamps[timestamps.length - 1] - scheduleStart;

        address owner = ownerOf(tokenId);

        uint256 nextId = _nextId;
        for (uint256 i = 0; i < intervalCount; ++i) {
            uint64 intervalStart = timestamps[i];
            uint64 intervalEnd = timestamps[i + 1];
            uint64 intervalDuration = intervalEnd - intervalStart; // > 0 ensured above

            uint256 sliceAmount = (uint256(intervalDuration) * remainingAmount) / remainingDuration;
            remainingAmount -= sliceAmount;
            remainingDuration -= intervalDuration;

            unchecked {
                ++nextId;
            }
            uint256 newId = nextId;
            newTokenIds[i] = newId;

            _vesting[newId] = VestingPosition({
                startTime: intervalStart,
                duration: intervalDuration,
                amount: sliceAmount,
                released: 0
            });
            _safeMint(owner, newId);
        }

        // Sanity check
        assert(remainingAmount == 0);
        assert(remainingDuration == 0);

        _nextId = nextId;

        // Burn original token and clean storage
        _burn(tokenId);
        delete _vesting[tokenId];

        emit VestingNFTSplit(owner, tokenId, newTokenIds);
    }

    /* ---------------------------------------------------------------------
                         Splitting by shares (percentages)
    --------------------------------------------------------------------- */

    /// @notice Splits a vesting NFT into multiple ones keeping the same end date but
    ///         distributing the remaining, still-locked amount proportionally to `shares`.
    /// @dev    Example: shares = [1,1,2] ⇒ 25%,25%,50%. The vesting start for all new
    ///         NFTs is `max(original.startTime, block.timestamp)` so we never accelerate
    ///         token release. End date remains unchanged. Works even after vesting has
    ///         started.
    /// @param tokenId The ID of the vesting NFT
    /// @param shares The shares at which the vesting NFTs will be split
    /// @return newTokenIds The IDs of the new vesting NFTs
    function splitByShares(uint256 tokenId, uint32[] calldata shares)
        external
        nonReentrant
        onlyOwner(tokenId)
        returns (uint256[] memory newTokenIds)
    {
        if (shares.length < 2) revert InvalidAmounts();

        // Validate shares and compute total
        uint256 totalShares;
        unchecked {
            for (uint256 i = 0; i < shares.length; ++i) {
                if (shares[i] == 0) revert InvalidAmounts();
                totalShares += shares[i];
            }
        }

        // Release everything that has vested so far.
        _release(tokenId);

        VestingPosition memory vp = _vesting[tokenId];
        if (vp.amount == 0) revert NothingToSplit();

        uint64 newStart = vp.startTime > uint64(block.timestamp) ? vp.startTime : uint64(block.timestamp);
        uint64 newDuration = (vp.startTime + vp.duration) - newStart; // >= 0 ensured

        uint256 remainingAmount = vp.amount - vp.released;
        uint256 remainingShares = totalShares;

        newTokenIds = new uint256[](shares.length);
        address owner = ownerOf(tokenId);

        uint256 nextId = _nextId;
        for (uint256 i = 0; i < shares.length; ++i) {
            uint256 slice = (uint256(shares[i]) * remainingAmount) / remainingShares;
            remainingAmount -= slice;
            remainingShares -= shares[i];

            unchecked {
                ++nextId;
            }
            uint256 newId = nextId;
            newTokenIds[i] = newId;

            _vesting[newId] = VestingPosition({startTime: newStart, duration: newDuration, amount: slice, released: 0});
            _safeMint(owner, newId);
        }

        // Sanity: all amount assigned
        assert(remainingAmount == 0);

        _nextId = nextId;

        _burn(tokenId);
        delete _vesting[tokenId];

        emit VestingNFTSplit(owner, tokenId, newTokenIds);
    }

    /* ---------------------------------------------------------------------
                         Splitting by exact token amounts
    --------------------------------------------------------------------- */

    /// @notice Splits a vesting NFT into multiple ones keeping the same dates
    ///         but distributing the remaining amount as provided in `amounts`.
    /// @dev    `amounts.length >= 2` and their sum must equal the remaining locked
    ///         amount (after releasing vested tokens). The last amount is not
    ///         automatically adjusted – caller must pass exact values.
    /// @param tokenId The ID of the vesting NFT
    /// @param amounts The amounts at which the vesting NFTs will be split
    /// @return newTokenIds The IDs of the new vesting NFTs
    function splitByAmounts(uint256 tokenId, uint256[] calldata amounts)
        external
        nonReentrant
        onlyOwner(tokenId)
        returns (uint256[] memory newTokenIds)
    {
        if (amounts.length < 2) revert InvalidAmounts();

        // Release everything that is already vested.
        _release(tokenId);

        VestingPosition memory vp = _vesting[tokenId];
        if (vp.amount == 0) revert NothingToSplit();
        // Allow splitting by amounts only if the vesting has not started yet
        if (vp.startTime <= uint64(block.timestamp)) revert InvalidTimestamps();

        uint256 remainingAmount = vp.amount - vp.released;
        uint256 sum;
        for (uint256 i = 0; i < amounts.length; ++i) {
            sum += amounts[i];
        }
        if (sum != remainingAmount) revert InvalidAmounts();

        newTokenIds = new uint256[](amounts.length);
        address owner = ownerOf(tokenId);

        uint256 nextId = _nextId;
        for (uint256 i = 0; i < amounts.length; ++i) {
            unchecked {
                ++nextId;
            }
            uint256 newId = nextId;
            newTokenIds[i] = newId;

            _vesting[newId] =
                VestingPosition({startTime: vp.startTime, duration: vp.duration, amount: amounts[i], released: 0});

            remainingAmount -= amounts[i];

            _safeMint(owner, newId);
        }

        // Sanity check
        assert(remainingAmount == 0);

        _burn(tokenId);
        delete _vesting[tokenId];

        _nextId = nextId;
        emit VestingNFTSplit(owner, tokenId, newTokenIds);
    }

    /* ---------------------------------------------------------------------
                              Extending vesting
    --------------------------------------------------------------------- */

    /// @notice Extends the vesting end date. The new end must be at least as
    ///         far as the current end. All vested tokens are released first.
    /// @param tokenId The ID of the vesting NFT
    /// @param newEnd Timestamp of the new vesting end (>= startTime + duration).
    function setEndDate(uint256 tokenId, uint64 newEnd) external nonReentrant onlyOwner(tokenId) {
        _release(tokenId);

        VestingPosition storage vp = _vesting[tokenId];
        uint64 currentEnd = vp.startTime + vp.duration;
        if (newEnd < currentEnd) revert NewEndTooEarly();

        vp.duration = newEnd - vp.startTime;

        emit EndDateExtended(tokenId, newEnd);
    }

    /* ---------------------------------------------------------------------
                           Public view helpers
    --------------------------------------------------------------------- */

    /// @notice Returns full vesting information for a given tokenId.
    /// @param tokenId The ID of the vesting NFT
    /// @return The vesting information for the given tokenId (publicly viewable)
    function vestingInfo(uint256 tokenId) external view returns (VestingPosition memory) {
        return _vesting[tokenId];
    }

    /// @notice Amount of tokens already vested at current block timestamp.
    /// @param tokenId The ID of the vesting NFT
    /// @return The amount of tokens that have vested at the current block timestamp (publicly viewable)
    function vestedAmount(uint256 tokenId) public view returns (uint256) {
        VestingPosition memory vp = _vesting[tokenId];
        if (block.timestamp < vp.startTime) return 0;
        if (block.timestamp >= vp.startTime + vp.duration) return vp.amount;
        uint256 passed = block.timestamp - vp.startTime;
        return (vp.amount * passed) / vp.duration;
    }

    /// @notice Amount of tokens that can be released right now.
    /// @param tokenId The ID of the vesting NFT
    /// @return The amount of tokens that can be claimed at the current block timestamp
    function claimable(uint256 tokenId) public view returns (uint256) {
        VestingPosition memory vp = _vesting[tokenId];
        uint256 vested = vestedAmount(tokenId);
        return vested - vp.released;
    }

    /* ---------------------------------------------------------------------
                                ERC-721 hooks
    --------------------------------------------------------------------- */

    /// @notice Returns the base URI for the metadata
    /// @return The base URI for the metadata
    function _baseURI() internal pure override returns (string memory) {
        return _BASE_URI;
    }
}
