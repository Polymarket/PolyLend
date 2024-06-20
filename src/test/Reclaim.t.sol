// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Loan} from "./PolyLendTestHelper.sol";

contract PolyLendReclaimTest is PolyLendTestHelper {
    uint256 rate;

    function setUp() public override {
        super.setUp();
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

    function test_PolyLendTransferTest_reclaim(
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

        {
            uint256 duration = bound(_duration, _minimumDuration, 60 days);
            uint256 auctionLength = bound(_auctionLength, polyLend.AUCTION_DURATION() + 1, type(uint32).max);
            loanId = _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration, duration);

            callTime = block.timestamp;
            vm.warp(block.timestamp + auctionLength);
        }

        vm.startPrank(lender);
        vm.expectEmit();
        emit LoanReclaimed(loanId);
        polyLend.reclaim(loanId);
        vm.stopPrank();

        Loan memory loan = _getLoan(loanId);

        assertEq(loan.borrower, address(0));

        assertEq(conditionalTokens.balanceOf(lender, positionId0), _collateralAmount);
    }
}
