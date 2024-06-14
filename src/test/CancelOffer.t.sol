// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Offer} from "./PolyLendTestHelper.sol";

contract PolyLendCancelOfferTest is PolyLendTestHelper {
    uint256 rate;
    uint256 requestId;
    uint256 offerId;

    function _setUp(uint128 _amount, uint128 _loanAmount, uint256 _rate, uint32 _minimumDuration) internal {
        vm.assume(_amount > 0);
        vm.assume(_minimumDuration <= 60 days);

        rate = bound(_rate, 10 ** 18 + 1, polyLend.MAX_INTEREST());

        _mintConditionalTokens(borrower, _amount, positionId0);
        usdc.mint(lender, _loanAmount);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);

        requestId = polyLend.request(positionId0, _amount, _minimumDuration);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);
        offerId = polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();
    }

    function test_PolyLendCancelOfferTest_cancelOffer(
        uint128 _amount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_amount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(lender);
        polyLend.cancelOffer(offerId);
        vm.stopPrank();

        Offer memory offer = _getOffer(0);

        assertEq(offer.requestId, requestId);
        assertEq(offer.lender, address(0));
        assertEq(offer.loanAmount, _loanAmount);
        assertEq(offer.rate, rate);
    }

    function test_revert_PolyLendCancelOfferTest_cancelOffer_OnlyLender(
        uint128 _amount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration,
        address _caller
    ) public {
        vm.assume(_caller != lender);
        _setUp(_amount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(_caller);
        vm.expectRevert(OnlyLender.selector);
        polyLend.cancelOffer(offerId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCancelOfferTest_accept_InvalidOffer(
        uint128 _amount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_amount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(lender);
        polyLend.cancelOffer(offerId);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectRevert(InvalidOffer.selector);
        polyLend.accept(offerId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCancelOfferTest_cancelRequest_alreadyCanceled(
        uint128 _amount,
        uint128 _loanAmount,
        uint256 _rate,
        uint32 _minimumDuration
    ) public {
        _setUp(_amount, _loanAmount, _rate, _minimumDuration);

        vm.startPrank(lender);
        polyLend.cancelOffer(offerId);
        vm.expectRevert(OnlyLender.selector);
        polyLend.cancelOffer(offerId);
        vm.stopPrank();
    }
}
