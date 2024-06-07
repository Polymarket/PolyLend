// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Offer} from "./PolyLendTestHelper.sol";

contract PolyLendOfferTest is PolyLendTestHelper {
    function test_PolyLend_offer(uint128 _amount, uint128 _loanAmount, uint256 _rate, uint256 _minimumDuration)
        public
    {
        vm.assume(_amount > 0);
        vm.assume(_rate > 10 ** 18);
        vm.assume(_rate <= polyLend.MAX_INTEREST());
        vm.assume(_minimumDuration <= 60 days);

        _mintConditionalTokens(borrower, _amount, positionId0);
        usdc.mint(lender, _loanAmount);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);

        uint256 requestId = polyLend.request(positionId0, _amount);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);

        vm.expectEmit();
        emit LoanOffered(requestId, lender, _loanAmount, _rate, _minimumDuration);

        polyLend.offer(requestId, _loanAmount, _rate, _minimumDuration);

        vm.stopPrank();

        Offer memory offer = _getOffer(0);

        assertEq(offer.requestId, requestId);
        assertEq(offer.lender, lender);
        assertEq(offer.loanAmount, _loanAmount);
        assertEq(offer.rate, _rate);
        assertEq(offer.minimumDuration, _minimumDuration);
    }
}
