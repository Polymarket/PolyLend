// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendAcceptTest is PolyLendTestHelper {
    uint256 rate;
    uint256 offerId;

    function _setUp(uint128 _collateralAmount, uint128 _loanAmount, uint256 _rate, uint32 _minimumDuration) internal {
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
        offerId = polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();
    }

    function test_PolyLendAcceptTest_accept(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(borrower);
        vm.expectEmit();
        emit LoanAccepted(0, block.timestamp);
        polyLend.accept(offerId);
        vm.stopPrank();

        Loan memory loan = _getLoan(0);

        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
        assertEq(loan.positionId, positionId0);
        assertEq(loan.collateralAmount, _collateralAmount);
        assertEq(loan.loanAmount, _loanAmount);
        assertEq(loan.rate, rate);
        assertEq(loan.startTime, block.timestamp);
        assertEq(loan.minimumDuration, _minimumDuration);
        assertEq(loan.callTime, 0);

        assertEq(usdc.balanceOf(borrower), _loanAmount);
        assertEq(conditionalTokens.balanceOf(address(polyLend), positionId0), _collateralAmount);

        assertEq(polyLend.nextLoanId(), 1);
    }

    function test_revert_PolyLendAcceptTest_accept_OnlyBorrower(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        address _caller
    ) public {
        vm.assume(_caller != borrower);

        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(_caller);
        vm.expectRevert(OnlyBorrower.selector);
        polyLend.accept(offerId);
        vm.stopPrank();
    }

    function test_revert_PolyLendAcceptTest_accept_InvalidOffer(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint256 _offerId
    ) public {
        vm.assume(_offerId > 0);

        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(borrower);
        vm.expectRevert(InvalidOffer.selector);
        polyLend.accept(_offerId);
        vm.stopPrank();
    }
}
