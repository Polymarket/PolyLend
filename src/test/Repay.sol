// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendRepayTest is PolyLendTestHelper {
    uint256 loanId;
    uint256 rate;

    function _setUp(uint128 _collateralAmount, uint128 _loanAmount, uint256 _rate, uint256 _minimumDuration) internal {
        vm.assume(_collateralAmount > 0);
        vm.assume(_minimumDuration <= 60 days);
        vm.assume(_loanAmount > 1_000_000);

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

    function test_PolyLendRepayTest_repay(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);
        uint256 duration = bound(_duration, 0, 60 days);

        uint256 paybackTime = block.timestamp + duration;
        vm.warp(paybackTime);

        uint256 amountOwed = polyLend.getAmountOwed(loanId, paybackTime);

        vm.startPrank(borrower);
        usdc.mint(borrower, amountOwed - usdc.balanceOf(borrower));
        usdc.approve(address(polyLend), amountOwed);
        vm.expectEmit();
        emit LoanRepaid(loanId);
        polyLend.repay(loanId, paybackTime);
        vm.stopPrank();

        Loan memory loan = _getLoan(loanId);

        assertEq(loan.borrower, address(0));
        assertEq(usdc.balanceOf(borrower), 0);
        assertEq(usdc.balanceOf(lender), amountOwed);
        assertEq(conditionalTokens.balanceOf(address(polyLend), positionId0), 0);
        assertEq(conditionalTokens.balanceOf(address(borrower), positionId0), _collateralAmount);
    }

    function test_PolyLendRepayTest_repay_calledLoan(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration,
        uint256 _auctionDuration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        uint256 duration = bound(_duration, _minimumDuration, 90 days);
        uint256 auctionDuration = bound(_auctionDuration, 0, polyLend.AUCTION_DURATION());

        uint256 callTime = block.timestamp + duration;
        vm.warp(callTime);

        vm.startPrank(lender);
        polyLend.call(loanId);
        vm.stopPrank();

        vm.warp(block.timestamp + auctionDuration);
        uint256 amountOwed = polyLend.getAmountOwed(loanId, callTime);

        vm.startPrank(borrower);
        usdc.mint(borrower, amountOwed - usdc.balanceOf(borrower));
        usdc.approve(address(polyLend), amountOwed);
        vm.expectEmit();
        emit LoanRepaid(loanId);
        polyLend.repay(loanId, callTime);
        vm.stopPrank();

        Loan memory loan = _getLoan(loanId);

        assertEq(loan.borrower, address(0));
        assertEq(usdc.balanceOf(borrower), 0);
        assertEq(usdc.balanceOf(lender), amountOwed);
        assertEq(conditionalTokens.balanceOf(address(polyLend), positionId0), 0);
        assertEq(conditionalTokens.balanceOf(address(borrower), positionId0), _collateralAmount);
    }

    function test_PolyLendRepayTest_repay_paybackBuffer(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration,
        uint256 _repayTimestamp
    ) public {
        vm.assume(_minimumDuration > polyLend.PAYBACK_BUFFER());
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        uint256 duration = bound(_duration, _minimumDuration, 60 days);
        vm.warp(block.timestamp + duration);

        // allowed repayTimestamps
        // note that the loan _can_ be paid for a future timestamp
        uint256 repayTimestamp = bound(_repayTimestamp, block.timestamp - polyLend.PAYBACK_BUFFER(), block.timestamp);
        uint256 amountOwed = polyLend.getAmountOwed(loanId, repayTimestamp);

        vm.startPrank(borrower);
        usdc.mint(borrower, amountOwed - usdc.balanceOf(borrower));
        usdc.approve(address(polyLend), amountOwed);
        polyLend.repay(loanId, repayTimestamp);
        vm.stopPrank();

        Loan memory loan = _getLoan(loanId);

        assertEq(loan.borrower, address(0));
        assertEq(usdc.balanceOf(borrower), 0);
        assertEq(usdc.balanceOf(lender), amountOwed);
        assertEq(conditionalTokens.balanceOf(address(polyLend), positionId0), 0);
        assertEq(conditionalTokens.balanceOf(address(borrower), positionId0), _collateralAmount);
    }

    function test_revert_PolyLendRepayTest_repay_alreadyRepaid_OnlyBorrower(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);
        uint256 duration = bound(_duration, 0, 60 days);

        uint256 paybackTime = block.timestamp + duration;
        vm.warp(paybackTime);

        uint256 amountOwed = polyLend.getAmountOwed(loanId, paybackTime);

        vm.startPrank(borrower);
        usdc.mint(borrower, amountOwed - usdc.balanceOf(borrower));
        usdc.approve(address(polyLend), amountOwed);
        polyLend.repay(loanId, paybackTime);

        usdc.mint(borrower, amountOwed - usdc.balanceOf(borrower));
        usdc.approve(address(polyLend), amountOwed);
        vm.expectRevert(OnlyBorrower.selector);
        polyLend.repay(loanId, paybackTime);
        vm.stopPrank();
    }

    function test_revert_PolyLendRepayTest_repay_OnlyBorrower(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        address _caller
    ) public {
        vm.assume(_caller != borrower);

        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(_caller);
        vm.expectRevert(OnlyBorrower.selector);
        polyLend.repay(loanId, block.timestamp);
        vm.stopPrank();
    }

    /// @dev Reverts if _repayTimestamp is too early for an uncalled loan
    function test_revert_PolyLendRepayTest_repay_timestampTooEarly_InvalidRepayTimestamp(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration,
        uint32 _repayTimestamp
    ) public {
        vm.assume(_minimumDuration > polyLend.PAYBACK_BUFFER());
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        uint256 duration = bound(_duration, _minimumDuration, 60 days);
        vm.warp(block.timestamp + duration);

        uint256 repayTimestamp = bound(_repayTimestamp, 0, block.timestamp - polyLend.PAYBACK_BUFFER() - 1);

        vm.startPrank(borrower);
        vm.expectRevert(InvalidRepayTimestamp.selector);
        polyLend.repay(loanId, repayTimestamp);
        vm.stopPrank();
    }

    /// @dev Reverts if _repayTimestamp does not equal call time for a called loan
    function test_revert_PolyLendRepayTest_repay_doesNotEqualCallTime_InvalidRepayTimestamp(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration,
        uint32 _repayTime
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        uint256 duration = bound(_duration, _minimumDuration, 60 days);
        uint256 callTime = block.timestamp + duration;

        vm.assume(_repayTime != callTime);

        vm.warp(callTime);

        vm.startPrank(lender);
        vm.expectEmit();
        emit LoanCalled(loanId, block.timestamp);
        polyLend.call(loanId);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectRevert(InvalidRepayTimestamp.selector);
        polyLend.repay(loanId, _repayTime);
        vm.stopPrank();
    }

    function test_revert_PolyLendRepayTest_repay_InsufficientAllowance(
        uint64 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration,
        uint256 _allowance
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);
        uint256 duration = bound(_duration, 0, 60 days);

        uint256 paybackTime = block.timestamp + duration;
        vm.warp(paybackTime);

        uint256 amountOwed = polyLend.getAmountOwed(loanId, paybackTime);
        uint256 allowance = bound(_allowance, 0, amountOwed - 1);

        vm.startPrank(borrower);
        usdc.mint(borrower, amountOwed);
        usdc.approve(address(polyLend), allowance);
        vm.expectRevert(InsufficientAllowance.selector);
        polyLend.repay(loanId, paybackTime);
        vm.stopPrank();
    }
}
