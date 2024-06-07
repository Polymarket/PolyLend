// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper} from "./PolyLendTestHelper.sol";

contract PolyLendRequestTest is PolyLendTestHelper {
    function test_PolyLend_accept(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration
    ) public {
        vm.assume(_collateralAmount > 0);
        vm.assume(_rate > 10 ** 18);
        vm.assume(_rate <= polyLend.MAX_INTEREST());
        vm.assume(_minimumDuration <= 60 days);

        _mintConditionalTokens(borrower, _collateralAmount, positionId0);
        usdc.mint(lender, _loanAmount);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);
        uint256 requestId = polyLend.request(positionId0, _collateralAmount);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);
        polyLend.offer(requestId, _loanAmount, _rate, _minimumDuration);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectEmit();
        emit LoanAccepted(requestId, block.timestamp);
        polyLend.accept(requestId, 0);
        vm.stopPrank();

        (
            address borrower_,
            address lender_,
            uint256 positionId_,
            uint256 collateralAmount_,
            uint256 loanAmount_,
            uint256 rate_,
            uint256 startTime_,
            uint256 minimumDuration_,
            uint256 callTime_
        ) = polyLend.loans(0);

        assertEq(borrower_, borrower);
        assertEq(lender_, lender);
        assertEq(positionId_, positionId0);
        assertEq(collateralAmount_, _collateralAmount);
        assertEq(loanAmount_, _loanAmount);
        assertEq(rate_, _rate);
        assertEq(startTime_, block.timestamp);
        assertEq(minimumDuration_, _minimumDuration);
        assertEq(callTime_, 0);

        assertEq(usdc.balanceOf(borrower), _loanAmount);
        assertEq(conditionalTokens.balanceOf(address(polyLend), positionId0), _collateralAmount);
    }
}
