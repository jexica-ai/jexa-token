# JEXA — Utility Token for Jexica AI Platform

> **Disclaimer:** This document is a working draft. Token metrics, distribution percentages, and supported networks may change until final deployment decisions are made.

## About Jexica AI
Jexica AI is an AI-powered navigator for the crypto markets and a trading assistant, available via web interface and Telegram bot. We democratize enterprise-grade data, unique and hard-to-find metrics, and decision support—empowering retail traders with insights (with appropriate disclaimers).

## JEXA Token
The JEXA token is the native utility and community-building asset of the platform:

JEXA is deployed as a LayerZero OFT across Ethereum, Arbitrum, and Base at launch, enabling seamless cross-chain transfers and unified liquidity management. Future integrations include Solana and TON, with dedicated liquidity pools for more aggressive, community-driven trading.

- **Minimum Guaranteed Utility**: Unlock access to a personalized web dashboard and Telegram chatbot that interpret market data and assist with trading decisions in real time.
- **Future Utilities**: As the platform evolves, new features and premium services (analytics modules, signal alerts, governance access) will be added.
- **Standards**: ERC-20 with EIP-2612 permit support and LayerZero OFT v2 for seamless cross-chain transfers.
- **Total Supply**: 1,000,000,000 JEXA minted at genesis.

## Liquidity & Token Distribution
We prioritize on-chain transparency, audited locking, and sustainable market health across multiple chains:

- **60% Liquidity Lock**: Token/ETH pools on Ethereum, Arbitrum, and Base (Uniswap v4), zero-fee, low-concentration pools permanently locked and audited to guarantee minimal market depth and fair price discovery.
- **40% Platform & Community Allocation**:
  - **10%** Unlocked liquidity for operational expenses, marketing, and cross-exchange market making.
  - **5%** Linear vesting over 1 year (no cliff) — attracts live investment capital from ecosystem partners, boosting project visibility, fostering strategic integrations, and growing the community.
  - **10%** Linear vesting over 2 years (6-month cliff) — dedicated to liquidity guarantees in other networks (Arbitrum, Base, Solana, TON...) for fair price discovery and market expansion.
  - **15%** Linear vesting over 4 years (no cliff) — skin-in-the-game reserves for data partners, LLM providers, and funding early staking programs (4-year cycle aligns with a typical market cycle/Bitcoin halving).

Our flexible NFT-based vesting allows slicing and reshaping schedules without violating community unlock promises—ensuring no sudden whale dumps and maintaining trust.

Planned expansion to Solana and TON will introduce smaller, higher-concentration liquidity pools to support more aggressive trading options for the community.

## Vesting Mechanism (JEXAVestingNFT)
Every vesting position is represented by an NFT. Core operations:

1. **mintVesting(start, duration, amount)** — Lock tokens and mint a vesting NFT.
2. **release(tokenId)** — Withdraw claimable tokens; burns NFT when fully vested.
3. **splitByDates(tokenId, timestamps[])** — Segment a vesting position by custom dates.
4. **splitByAmounts(tokenId, amounts[])** — Pre-vesting split by exact amounts.
5. **splitByShares(tokenId, shares[])** — Proportional split at any time.

Full formal specifications, invariants, and audit checklists are in `AUDITABLE.md`.

## Getting Started
1. Install dependencies:
   ```bash
   pnpm install
   ```
2. Run tests:
   ```bash
   pnpm test
   ```
3. Refer to `AUDITABLE.md` for deployment, configuration, and audit details.

## Contact & Community
Explore the platform at [jexica.ai](https://jexica.ai) or chat with our trading assistant on Telegram. Contributions, issues, and feature requests are welcome on our GitHub repository.

## Audits
All completed security audits and review reports are available in the `audits/` directory of this repository.
