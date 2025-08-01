# JEXA Token & Vesting Suite – Formal Specification

## 1. Scope of This Document
This README serves as **the authoritative functional specification** for the 
Jexica AI on-chain components as of commit date. It is written to be consumed by
security auditors and external contributors. Every behaviour described here is
considered an invariant; deviations should be treated as defects.

Components covered:
1. `JEXAToken`                – omnichain fungible ERC-20 (LayerZero OFT).
2. `JEXAVestingNFT`           – ERC-721 token whose every NFT represents a
   linear vesting position.

> **Testing note:** The `JEXAToken` contract is a thin composition of
>   • `OFT` (LayerZero V2 omnichain fungible token)
>   • `ERC20Permit` (OpenZeppelin)
>   • `Ownable` (OpenZeppelin)
> and adds **no custom logic** beyond its constructor. Therefore unit tests in
> this repository focus exclusively on `JEXAVestingNFT`; duplicating the
> extensive upstream test-suites for the libraries above would be redundant.

> **Coverage technique:** During coverage generation we temporarily rewrote
> `require(condition, CustomError())` guards into the explicit pattern
> `if (!condition) revert CustomError();`. Current Foundry/LCOV tooling does
> not attribute hits correctly for the `require`-with-error form, but works
> reliably with the explicit `if` pattern. After collecting coverage the
> idiomatic `require` statements were restored in a separate commit to keep
> history auditable. With this approach every function, branch and line is
> exercised — the only four lines reported as “not executed” disappear under
> `--ir-minimum` due to Solidity optimiser and can be safely ignored.

---

## 2. JEXA ERC-20 (OFT)
* **Name / Symbol / Decimals:** `Jexica AI` / `JEXA` / `18`.
* **Total Supply:** `1_000_000_000 JEXA` minted once at genesis (mainnet).
* **Immutable:** no further mint, burn or pause capabilities.
* **Cross-chain:** inherits LayerZero `OFT` v2; balances move by message rather
  than burn/mint.
* **Examples (OFT v2):** [USDT0](https://usdt0.to/) (Tether) and [USDe](https://ethena.fi) (Ethena) follow the same message-passing burn/mint pattern.
* **EIP-2612 Permit** is supported.
* **Deployment Networks**: Launched on Ethereum, Arbitrum, and Base via LayerZero OFT; future integrations planned for Solana and TON.

### 2.1 Privileged Roles (Owner)
Owner may only:
1. `setPeer(uint32 eid, address peer)`               – trust remote OFT.
2. `setDelegate(address)` for LZ config changes.
3. `setMsgInspector(address)` opt-in message filter.
4. Standard OZ `transferOwnership` / `renounceOwnership`.

_No owner function can influence vesting logic or token balances directly._

---

## 3. Vesting via `JEXAVestingNFT`
Each NFT encodes a *linear vesting schedule* for a fixed `amount` of JEXA.
The contract itself holds all the locked JEXA. The current owner of the NFT is
entitled to withdraw ("release") the portion that has already vested.

### 3.1 Storage Layout per NFT (`VestingPosition`)
| Field       | Type      | Meaning                                                  |
|-------------|-----------|----------------------------------------------------------|
| `startTime` | `uint64`  | UNIX timestamp when linear release starts.               |
| `duration`  | `uint64`  | Seconds of the vesting period. End = `start + duration`. |
| `amount`    | `uint256` | Total amount originally locked.                          |
| `released`  | `uint256` | How much has already been withdrawn.                     |

### 3.2 Global Invariants
1. **No acceleration:** For any NFT, `startTime` never moves *earlier* and
   `endTime = startTime + duration` never moves *earlier*.
2. **Conservation:** At any moment the sum of
   `released + Σ(amount of all outstanding NFTs)` equals the tokens deposited
   via `mintVesting` minus tokens withdrawn via `release`.
3. **Single-ownership:** Only `ownerOf(tokenId)` may mutate or withdraw that NFT.
4. **Re-entrancy:** All state-changing externals use `ReentrancyGuardTransient`.
5. **Token symbol guard:** constructor reverts if supplied token is not `JEXA`.

### 3.3 User Flows
#### 3.3.1 Creating a Vesting Position
```solidity
mintVesting(startTime, duration, amount)
```
* **Checks**: `duration > 0`, `amount > 0`.
* **Effects**: `_nextId++`, new `VestingPosition` stored.
* **Interactions**:
  1. `JEXA.safeTransferFrom(caller, this, amount)` – tokens locked.
  2. `_safeMint(caller, tokenId)` – NFT issued.

#### 3.3.2 Releasing Vested Tokens
```solidity
release(tokenId)
```
* Calculates `claimable = vested(now) – released` using linear formula.
* Updates `released` then transfers `claimable` to owner.
* If everything released → burns NFT (storage delete).

#### 3.3.3 Splitting by Dates (Timeline Reshaping)
```solidity
splitByDates(tokenId, uint64[] timestamps)
```
* `timestamps.length ≥ 2`, strictly increasing.
* First timestamp may be the constant `0x55D44FB5` (= Ethereum genesis) to
  denote "now" – allows front-ends to avoid `block.timestamp`.
* `scheduleStart = max(firstTimestamp, now, original.startTime)`.
* End date **unchanged**. Interval count = `len-1`.
* Remaining amount & duration are iteratively divided so that rounding dust is
  spread across slices (no special "last slice" rule).

#### 3.3.4 Splitting by Exact Amounts
```solidity
splitByAmounts(tokenId, uint256[] amounts)
```
* Only allowed **before** vesting starts (`startTime > now`).
* Σ amounts == remainingAmount (strict equality).
* All new NFTs keep original dates.

#### 3.3.5 Splitting by Shares (Percentages)
```solidity
splitByShares(tokenId, uint32[] shares)
```
* Allowed **at any time** (even mid-vesting).
* Σ shares > 0.
* New schedule: `newStart = max(original.start, now)`; `end` unchanged. Thus
  release rate never increases.
* Amount split proportionally. Iterative algorithm ensures dust spreads across
  slices; sanity `assert(remainingAmount == 0)`.

### 3.4 Security Tricks & Gas Optimisations
| Technique                      | Where                           | Purpose                                                                                                   |
|--------------------------------|---------------------------------|-----------------------------------------------------------------------------------------------------------|
| **Transient `nonReentrant`**   | All externals that mint/burn    | Gas ↘ without losing safety.                                                                              |
| **Batch `_nextId` update**     | All split functions             | 1 SSTORE instead of N.                                                                                    |
| **Iterative dust spreading**   | `splitByDates`, `splitByShares` | Prevent last slice from monopolising rounding remainder (≤1 wei per step).                                |
| **Special constant for "now"** | `splitByDates`                  | Avoid passing `block.timestamp` via ABI; chosen as Ethereum genesis timestamp to minimise collision risk. |

---

## 4. Formal Properties for Audit
Auditors should assert the following for every transaction sequence:
1. **No balance loss** – Total JEXA held by contract + total released events =
   total ever deposited via `mintVesting`.
2. **Monotone release** – For each NFT: `(vested(t₂) – released)
   ≥ (vested(t₁) – released)` when `t₂ ≥ t₁`.
3. **Invariant 1** (no acceleration): After any split/extend the new curve is
   never above the original at any time `< originalEnd`.
4. **Invariant 2** (auth) – Only owner can call mutations.
5. **Invariant 3** (nonReentrant) – Nested calls revert with
   `ReentrancyGuardReentrantCall`.
6. **Symbol Guard** – Deploying with wrong ERC-20 symbol reverts.

---

## 5. Deployment & Addresses
_To be filled after deployment._

---

## 6. Locked Liquidity (Future)
* **Audit Stage 2**: A second-stage security audit for locked liquidity will be conducted immediately after deployment to validate pool contracts and governance logic.

* **60% Locked Forever**: Permanently locked in zero-fee, low-concentration liquidity pools on Ethereum, Arbitrum, and Base (e.g., Uniswap v4) to guarantee minimum market depth and fair price discovery. Pools are fully audited and verifiable on-chain.
* **Future Chain Pools**: Dedicated smaller locked pools will be established on Solana and TON to support more aggressive trading scenarios as the community evolves.
* **Lock Mechanics**: Liquidity lock contracts require multi-signature or time-lock governance, ensuring no unlock before a specified maturity date aligning with vesting and market cycle milestones.
* **Ongoing Audits**: We commit to regular professional security audits for any significant on-chain feature or platform upgrade, with all reports published in the `audits/` directory.
---

## 7. License
All contracts are released under MIT.
