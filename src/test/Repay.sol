// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendRepayTest is PolyLendTestHelper {
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
        uint256 requestId = polyLend.request(positionId0, _collateralAmount);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);
        uint256 offerId = polyLend.offer(requestId, _loanAmount, rate, _minimumDuration);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectEmit();
        emit LoanAccepted(requestId, block.timestamp);
        loanId = polyLend.accept(requestId, offerId);
        vm.stopPrank();
    }

    function test_PolyLendRepay_repay(
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
        usdc.mint(borrower, amountOwed);
        usdc.approve(address(polyLend), amountOwed);
        vm.expectEmit();
        emit LoanRepaid(loanId);
        polyLend.repay(loanId, paybackTime);
        vm.stopPrank();

        Loan memory loan = _getLoan(loanId);

        assertEq(loan.borrower, address(0));
    }

    function test_revert_PolyLendRepayTest_OnlyBorrower(
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

    function test_revert_PolyLendRepayTest_InvalidPayBackTime_1(
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
        vm.expectRevert(InvalidPaybackTime.selector);
        polyLend.repay(loanId, _repayTime);
        vm.stopPrank();
    }
}
