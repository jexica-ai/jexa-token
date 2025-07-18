// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {JEXAToken} from "../JEXAToken.sol";

// @dev WARNING: This is for testing purposes only
contract JEXATokenMock is JEXAToken {
    constructor(address _lzEndpoint, address _delegate) JEXAToken(_lzEndpoint, _delegate, 0) {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
