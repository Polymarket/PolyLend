// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, console2 as console, stdStorage, StdStorage, stdError} from "../../lib/forge-std/src/Test.sol";
import {PolyLend} from "../PolyLend.sol";

contract PolyLendConstructorTest is Test {
    function test_PolyLendConstructorTest_constructor(address _conditionalTokens, address _usdc) public {
        PolyLend polyLend = new PolyLend(_conditionalTokens, _usdc);

        vm.assertEq(address(polyLend.usdc()), _usdc);
        vm.assertEq(address(polyLend.conditionalTokens()), _conditionalTokens);
    }
}
