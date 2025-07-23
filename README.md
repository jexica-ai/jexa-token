# JEXA Token Ecosystem

## High level description

JEXA is the native utility token of the Jexica AI ecosystem. It is an Omnichain Fungible Token (OFT) that can move seamlessly across LayerZero-connected chains and incorporates advanced linear vesting mechanics to distribute tokens to contributors in a flexible yet secure way.

### Token description

* **name**: Jexica AI
* **symbol**: JEXA
* **decimals**: 18
* **totalSupply**: 1 000 000 000 JEXA (minted to the deployer at genesis on mainnet)
* **extra features**:
  * Cross-chain transfers via the LayerZero OFT standard.
  * EIP-2612 `permit` support for gas-less approvals.
  * Immutable initial supply (no further minting).
  * Ownable – owner may perform privileged actions:
    * `setPeer(eid, peer)`: mark a remote OFT instance as a trusted peer on a given chain.
    * `setDelegate(address)`: designate the LayerZero endpoint delegate allowed to manage protocol-level configuration.
    * `setMsgInspector(address)`: optionally plug in a contract that can inspect/validate outbound messages before dispatch.
    * Standard OpenZeppelin `transferOwnership` and `renounceOwnership` utilities.

## Main actors, actions, flows

* **Token holders** can transfer JEXA on any supported chain and bridge it to another chain using LayerZero.
* **Project multisig / Owner** controls the initial supply and can distribute tokens or fund vesting wallets.
* **Beneficiaries** receive tokens via `JEXAVestingWallet` contracts that release tokens linearly over time.
* **Vesting wallet owners** can spawn child vesting wallets with the same or stricter vesting schedule to sub-allocate tokens (e.g., to team members or advisors).
* **`JEXAVestingWalletFactory`** deploys vesting wallets and keeps an on-chain registry of all wallets.
* **LayerZero endpoints** process omnichain messages that underpin the OFT transfers.

## Technical details

* `JEXAToken` extends LayerZero’s `OFT` and OpenZeppelin’s `ERC20Permit`.
* Cross-chain messages are routed through LayerZero `EndpointV2`; token balances are reflected on each chain (no burning).
* Deployment script mints **1 B** JEXA on mainnet (`deploy/JEXAToken.ts`), while testnets start with 0 supply for flexibility.
* **Vesting system**
  * `JEXAVestingWallet` inherits OZ `VestingWallet` and supports *spawning* child wallets with identical or harsher vesting terms.
  * Overrides `vestedAmount` and `releasable` to account for spawned amounts and prevent underflow.
  * ETH deposits and releases are disabled – the contract only manages JEXA.
* **Factory**
  * `JEXAVestingWalletFactory` deploys new wallets and stores their addresses in an `EnumerableSet` for O(1) lookups.
  * Validates that the provided token’s symbol equals **"JEXA"** before deployment.
  * Transfers tokens from the creator to the new wallet in a single transaction.
* **Testing**: The repo contains Hardhat (TypeScript) and Foundry (Solidity) test suites covering the token, vesting logic, and cross-chain flows.
* **Security**: Uses OZ patterns, immutable variables, strict parameter validation, and `SafeERC20` for transfers.

## Deployed contracts

_To be updated after production deployment_

| Contract | Network | Address | Notes |
|----------|---------|---------|-------|
| `JEXAToken` | TODO(mainnet) | TODO | Omnichain fungible token |
| `JEXAVestingWalletFactory` | TODO(mainnet) | TODO | Creates vesting wallets |
| Individual `JEXAVestingWallet` | various | created per beneficiary | Linear vesting |
