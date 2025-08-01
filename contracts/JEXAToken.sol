// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;


import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/* =========== JEXA Token — Utility Token for the Jexica AI Ecosystem ==========
 *
 * JEXA powers access to the Jexica platform — a cognitive financial assistant
 * built to help humans make better decisions in an increasingly complex world.
 *
 * Jexica is not just another chatbot or dashboard. It is a conversational AI
 * agent with access to institutional-grade market data, designed to surface
 * clear, personalized insights in real time — from Telegram to web.
 *
 * The JEXA token is used to unlock features, pay for model interactions, and
 * enable smart alerting and automation within the Jexica environment. It is a
 * functional token — not speculative — and supports direct interaction between
 * users and their intelligent agent.
 * 
 * Technically, JEXA is an Omnichain Fungible Token (OFT), deployable across
 * multiple blockchains using LayerZero infrastructure. It is governed by strict
 * supply rules, transparency, and timelocked controls.
 *
 * To learn more about how Jexica works — and how to use JEXA — 
 *
 *                           visit: https://jexica.ai
 */

/**
 * @title JEXAToken
 * @dev A token contract that extends the OFT (Omnichain Fungible Token) and ERC20Permit standards.
 * This contract allows for cross-chain communication using LayerZero and provides a permit mechanism
 * for gasless token transfers.
 */
contract JEXAToken is OFT, ERC20Permit {
    /**
     * @dev Constructor to initialize the JEXA token.
     * @param _lzEndpoint The LayerZero endpoint address for cross-chain communication
     * @param _owner The owner of the token contract
     * @param _initialSupply The initial supply of the token to be minted
     */
    constructor(address _lzEndpoint, address _owner, uint256 _initialSupply)
        OFT("Jexica AI", "JEXA", _lzEndpoint, _owner)
        Ownable(_owner)
        ERC20Permit("Jexica AI")
    {
        _mint(_owner, _initialSupply);
    }
}
