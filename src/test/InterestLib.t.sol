// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, console2 as console, stdStorage, StdStorage, stdError} from "../../lib/forge-std/src/Test.sol";
import {InterestLib} from "../InterestLib.sol";

contract InterestLibTest is Test {
    using InterestLib for uint256;

    function testPow() public pure {
        uint256 base = 2 * InterestLib.ONE;
        uint256 exponent = 3;
        uint256 result = base.pow(exponent);

        assertEq(result, 8 * InterestLib.ONE);
    }
}
