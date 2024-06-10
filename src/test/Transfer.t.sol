// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendTransferTest is PolyLendTestHelper {
    address newLender;

    function setUp() public override {
        super.setUp();
        newLender = vm.createWallet("newLender").addr;
    }

    function _setUp(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration,
        uint256 _duration
    ) internal returns (uint256) {
        newLender = vm.createWallet("oracle").addr;

        vm.assume(_collateralAmount > 0);

        _mintConditionalTokens(borrower, _collateralAmount, positionId0);
        usdc.mint(lender, _loanAmount);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);
        uint256 requestId = polyLend.request(positionId0, _collateralAmount);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);
        uint256 offerId = polyLend.offer(requestId, _loanAmount, _rate, _minimumDuration);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectEmit();
        emit LoanAccepted(requestId, block.timestamp);
        uint256 loanId = polyLend.accept(requestId, offerId);
        vm.stopPrank();

        vm.warp(block.timestamp + _duration);

        vm.startPrank(lender);
        vm.expectEmit();
        emit LoanCalled(loanId, block.timestamp);
        polyLend.call(loanId);
        vm.stopPrank();

        return loanId;
    }

    function test_PolyLend_transfer(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint256 _duration,
        uint256 _auctionLength
    ) public {
        vm.assume(_minimumDuration <= 60 days);

        uint256 loanId;
        uint256 callTime;
        uint256 rate = bound(_rate, 10 ** 18 + 1, polyLend.MAX_INTEREST());

        {
            uint256 duration = bound(_duration, _minimumDuration, 60 days);
            uint256 auctionLength = bound(_auctionLength, 0, polyLend.auctionDuration());
            loanId = _setUp(_collateralAmount, _loanAmount, rate, _minimumDuration, duration);

            callTime = block.timestamp;
            vm.warp(block.timestamp + auctionLength);
        }

        uint256 newRate = _getNewRate(callTime);
        uint256 newLoanId = loanId + 1;

        uint256 amountOwed = polyLend.getAmountOwed(loanId, callTime);
        usdc.mint(newLender, amountOwed);

        vm.startPrank(newLender);
        usdc.approve(address(polyLend), amountOwed);
        vm.expectEmit();
        emit LoanTransferred(loanId, newLoanId, newLender, newRate);
        polyLend.transfer(loanId, newRate);
        vm.stopPrank();

        Loan memory newLoan = _getLoan(newLoanId);

        assertEq(newLoan.borrower, borrower);
        assertEq(newLoan.lender, newLender);
        assertEq(newLoan.positionId, positionId0);
        assertEq(newLoan.collateralAmount, _collateralAmount);
        assertEq(newLoan.loanAmount, amountOwed);
        assertEq(newLoan.rate, newRate);
        assertEq(newLoan.startTime, block.timestamp);
        assertEq(newLoan.minimumDuration, 0);
        assertEq(newLoan.callTime, 0);
    }
}