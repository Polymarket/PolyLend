// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Offer} from "./PolyLendTestHelper.sol";

contract PolyLendOfferTest is PolyLendTestHelper {
    uint256 rate;
    uint256 requestId;

    function _setUp(uint128 _collateralAmount, uint128 _loanAmount, uint256 _rate, uint32 _minimumDuration) internal {
        vm.assume(_collateralAmount > 0);
        vm.assume(_loanAmount > 0);
        vm.assume(_minimumDuration <= 60 days);

        rate = bound(_rate, 10 ** 18 + 1, polyLend.MAX_INTEREST());

        _mintConditionalTokens(borrower, _collateralAmount, positionId0);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);
        requestId = polyLend.request(positionId0, _collateralAmount, _minimumDuration);
        vm.stopPrank();
    }

    function test_PolyLendOfferTest_offer(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(lender);
        usdc.mint(lender, _loanAmount);
        usdc.approve(address(polyLend), _loanAmount);
        vm.expectEmit();
        emit LoanOffered(requestId, lender, _loanAmount, rate);
        polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();

        Offer memory offer = _getOffer(0);

        assertEq(offer.requestId, requestId);
        assertEq(offer.lender, lender);
        assertEq(offer.loanAmount, _loanAmount);
        assertEq(offer.rate, rate);

        assertEq(polyLend.nextOfferId(), 1);
    }

    function test_revert_PolyLendOfferTest_offer_InvalidRequestId(uint128 _loanAmount) public {
        vm.startPrank(lender);
        vm.expectRevert(InvalidRequest.selector);
        polyLend.offer(0, _loanAmount, rate);
        vm.stopPrank();
    }

    function test_revert_PolyLendOfferTest_offer_InsufficientFunds(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint128 _balance
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        uint256 balance = bound(_balance, 0, _loanAmount - 1);
        vm.startPrank(lender);
        usdc.mint(lender, balance);
        vm.expectRevert(InsufficientFunds.selector);
        polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();
    }

    function test_revert_PolyLendOfferTest_offer_InsufficientAllowance(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        uint128 _allowance
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        uint256 allowance = bound(_allowance, 0, _loanAmount - 1);
        vm.startPrank(lender);
        usdc.mint(lender, _loanAmount);
        usdc.approve(address(polyLend), allowance);
        vm.expectRevert(InsufficientAllowance.selector);
        polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();
    }

    function test_revert_PolyLendOfferTest_offer_InvalidRate_tooLow(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        rate = bound(_rate, 0, 10 ** 18);
        vm.startPrank(lender);
        usdc.mint(lender, _loanAmount);
        usdc.approve(address(polyLend), _loanAmount);
        vm.expectRevert(InvalidRate.selector);
        polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();
    }

    function test_revert_PolyLendOfferTest_offer_InvalidRate_tooHigh(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_collateralAmount, _loanAmount, _rate, _minimumDuration);

        rate = bound(_rate, polyLend.MAX_INTEREST() + 1, type(uint64).max);
        vm.startPrank(lender);
        usdc.mint(lender, _loanAmount);
        usdc.approve(address(polyLend), _loanAmount);
        vm.expectRevert(InvalidRate.selector);
        polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();
    }
}
