// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendCallTest is PolyLendTestHelper {
    uint256 loanId;
    uint256 rate;

    function _setUp(uint128 _collateralAmount, uint128 _loanAmount, uint256 _rate, uint256 _minimumDuration) internal {
        vm.assume(_collateralAmount > 0);
        vm.assume(_minimumDuration <= 60 days);

        rate = bound(_rate, 10 ** 18 + 1, polyLend.MAX_INTEREST());

        _mintConditionalTokens(borrower, _collateralAmount, positionId0);
        usdc.mint(lender, _loanAmount);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);
        uint256 requestId = polyLend.request(positionId0, _collateralAmount, _minimumDuration);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);
        uint256 offerId = polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();

        vm.startPrank(borrower);
        loanId = polyLend.accept(offerId);
        vm.stopPrank();
    }

    function test_PolyLendCallTest_call(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);
        uint256 duration = bound(_duration, _minimumDuration, type(uint128).max);

        uint256 callTime = block.timestamp + duration;
        vm.warp(callTime);

        vm.startPrank(lender);
        vm.expectEmit();
        emit LoanCalled(loanId, block.timestamp);
        polyLend.call(loanId);
        vm.stopPrank();

        Loan memory loan = _getLoan(loanId);

        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
        assertEq(loan.positionId, positionId0);
        assertEq(loan.collateralAmount, _collateralAmount);
        assertEq(loan.loanAmount, _loanAmount);
        assertEq(loan.rate, rate);
        assertEq(loan.startTime, 1);
        assertEq(loan.minimumDuration, _minimumDuration);
        assertEq(loan.callTime, block.timestamp);
    }

    function test_revert_PolyLendCallTest_call_OnlyLender(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        address _caller
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);
        vm.assume(_caller != lender);

        vm.startPrank(_caller);
        vm.expectRevert(OnlyLender.selector);
        polyLend.call(loanId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCallTest_call_MinimumDurationHasNotPassed(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration
    ) public {
        vm.assume(_minimumDuration > 0);
        uint256 duration = bound(_duration, 0, _minimumDuration - 1);

        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.warp(block.timestamp + duration);

        vm.startPrank(lender);
        vm.expectRevert(MinimumDurationHasNotPassed.selector);
        polyLend.call(loanId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCallTest_call_LoanIsCalled(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.warp(block.timestamp + _minimumDuration);

        vm.startPrank(lender);
        polyLend.call(loanId);

        vm.expectRevert(LoanIsCalled.selector);
        polyLend.call(loanId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCallTest_loanIsRepaid(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);
        uint256 duration = bound(_duration, _minimumDuration, 60 days);

        uint256 paybackTime = block.timestamp + duration;
        vm.warp(paybackTime);

        uint256 amountOwed = polyLend.getAmountOwed(loanId, paybackTime);

        vm.startPrank(borrower);
        usdc.mint(borrower, amountOwed - usdc.balanceOf(borrower));
        usdc.approve(address(polyLend), amountOwed);
        polyLend.repay(loanId, paybackTime);
        vm.stopPrank();

        vm.startPrank(lender);
        vm.expectRevert(InvalidLoan.selector);
        polyLend.call(loanId);
        vm.stopPrank();
    }
}
