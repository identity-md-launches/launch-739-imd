// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMD
/// @notice Fixed-supply ERC-20: one billion IMD, with 18 decimals.
/// @dev The immediate deploying address receives the entire supply. If deployed
/// by a factory, that factory receives the tokens and handles distribution.
contract IMD is ERC20 {
    constructor() ERC20("IMD", "IMD") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
