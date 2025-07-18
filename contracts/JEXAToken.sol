// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";

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
