// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendTransferTest is PolyLendTestHelper {
    address newLender;
    uint256 rate;

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
        vm.assume(_collateralAmount > 0);

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
        uint256 loanId = polyLend.accept(offerId);
        vm.stopPrank();

        vm.warp(block.timestamp + _duration);

        vm.startPrank(lender);
        polyLend.call(loanId);
        vm.stopPrank();

        return loanId;
    }

    function test_PolyLendTransferTest_transfer(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint256 _duration,
        uint256 _auctionLength,
        uint256 _newRate
    ) public {
        vm.assume(_minimumDuration <= 60 days);

        uint256 loanId;
        uint256 callTime;

        {
            uint256 duration = bound(_duration, _minimumDuration, 60 days);
            uint256 auctionLength = bound(_auctionLength, 0, polyLend.AUCTION_DURATION());
            loanId = _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration, duration);

            callTime = block.timestamp;
            vm.warp(block.timestamp + auctionLength);
        }

        uint256 newRate = bound(_newRate, 0, _getNewRate(callTime));
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

        assertEq(usdc.balanceOf(lender), amountOwed);
        assertEq(usdc.balanceOf(newLender), 0);
    }

    function test_revert_PolyLendTransferTest_transfer_InvalidLoan(uint256 _loanId, uint256 _newRate) public {
        vm.assume(_loanId != 0);

        vm.startPrank(newLender);
        vm.expectRevert(InvalidLoan.selector);
        polyLend.transfer(_loanId, _newRate);
        vm.stopPrank();
    }

    function test_revert_PolyLendTransferTest_transfer_LoanIsNotCalled(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint256 _newRate
    ) public {
        newLender = vm.createWallet("oracle").addr;

        vm.assume(_collateralAmount > 0);

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
        vm.expectEmit();
        emit LoanAccepted(requestId, block.timestamp);
        uint256 loanId = polyLend.accept(offerId);
        vm.stopPrank();

        vm.startPrank(newLender);
        vm.expectRevert(LoanIsNotCalled.selector);
        polyLend.transfer(loanId, _newRate);
        vm.stopPrank();
    }

    function test_revert_PolyLendTransferTest_transfer_AuctionHasEnded(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint256 _duration,
        uint256 _auctionLength,
        uint256 _newRate
    ) public {
        vm.assume(_minimumDuration <= 60 days);

        uint256 loanId;
        uint256 callTime;

        uint256 duration = bound(_duration, _minimumDuration, 60 days);
        uint256 auctionLength = bound(_auctionLength, polyLend.AUCTION_DURATION() + 1, type(uint32).max);
        loanId = _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration, duration);

        callTime = block.timestamp;
        vm.warp(block.timestamp + auctionLength);

        uint256 newRate = bound(_newRate, 0, _getNewRate(callTime));

        vm.startPrank(newLender);
        vm.expectRevert(AuctionHasEnded.selector);
        polyLend.transfer(loanId, newRate);
        vm.stopPrank();
    }

    function test_revert_PolyLendTransferTest_transfer_InvalidRate(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint256 _duration,
        uint256 _auctionLength,
        uint256 _newRate
    ) public {
        vm.assume(_minimumDuration <= 60 days);

        uint256 loanId;
        uint256 callTime;

        {
            uint256 duration = bound(_duration, _minimumDuration, 60 days);
            uint256 auctionLength = bound(_auctionLength, 0, polyLend.AUCTION_DURATION());
            loanId = _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration, duration);

            callTime = block.timestamp;
            vm.warp(block.timestamp + auctionLength);
        }

        uint256 newRate = bound(_newRate, _getNewRate(callTime) + 1, type(uint64).max);

        uint256 amountOwed = polyLend.getAmountOwed(loanId, callTime);
        usdc.mint(newLender, amountOwed);

        vm.startPrank(newLender);
        usdc.approve(address(polyLend), amountOwed);
        vm.expectRevert(InvalidRate.selector);
        polyLend.transfer(loanId, newRate);
        vm.stopPrank();
    }
}
