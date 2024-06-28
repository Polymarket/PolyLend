// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";

contract USDC is ERC20 {
    function name() public pure override returns (string memory) {
        return "USDC";
    }

    function symbol() public pure override returns (string memory) {
        return "USDC";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
