// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Request} from "./PolyLendTestHelper.sol";

contract PolyLendCancelRequestTest is PolyLendTestHelper {
    uint256 requestId;

    function _setUp(uint128 _amount, uint32 _minimumDuration) internal {
        vm.assume(_amount > 0);
        vm.assume(_minimumDuration <= 60 days);

        _mintConditionalTokens(borrower, _amount, positionId0);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);
        requestId = polyLend.request(positionId0, _amount, _minimumDuration);
        vm.stopPrank();
    }

    function test_PolyLendCancelRequestTest_cancelRequest(uint128 _amount, uint32 _minimumDuration) public {
        _setUp(_amount, _minimumDuration);

        vm.startPrank(borrower);
        polyLend.cancelRequest(requestId);
        vm.stopPrank();

        Request memory request = _getRequest(requestId);

        assertEq(request.borrower, address(0));
        assertEq(request.positionId, positionId0);
        assertEq(request.collateralAmount, _amount);
        assertEq(request.minimumDuration, _minimumDuration);
    }

    function test_revert_PolyLendCancelRequestTest_cancelOffer_OnlyBorrower(
        uint128 _amount,
        uint32 _minimumDuration,
        address _caller
    ) public {
        vm.assume(_caller != borrower);
        _setUp(_amount, _minimumDuration);

        vm.startPrank(_caller);
        vm.expectRevert(OnlyBorrower.selector);
        polyLend.cancelRequest(requestId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCancelRequestTest_offer_InvalidRequest(
        uint128 _amount,
        uint32 _minimumDuration,
        uint128 _loanAmount,
        uint256 _rate
    ) public {
        _setUp(_amount, _minimumDuration);

        vm.startPrank(borrower);
        polyLend.cancelRequest(requestId);
        vm.stopPrank();

        vm.startPrank(lender);
        vm.expectRevert(InvalidRequest.selector);
        polyLend.offer(requestId, _loanAmount, _rate);
        vm.stopPrank();
    }

    function test_revert_PolyLendCancelRequestTest_cancelRequest_alreadyCanceled(
        uint128 _amount,
        uint32 _minimumDuration
    ) public {
        _setUp(_amount, _minimumDuration);

        vm.startPrank(borrower);
        polyLend.cancelRequest(requestId);
        vm.expectRevert(OnlyBorrower.selector);
        polyLend.cancelRequest(requestId);
        vm.stopPrank();
    }

    function test_revert_PolyLendCancelRequestTest_accept_requestCanceled(
        uint128 _amount,
        uint32 _minimumDuration,
        uint128 _loanAmount,
        uint256 _rate
    ) public {
        _setUp(_amount, _minimumDuration);

        uint256 rate = bound(_rate, 10 ** 18 + 1, polyLend.MAX_INTEREST());

        vm.startPrank(lender);
        usdc.mint(lender, _loanAmount);
        usdc.approve(address(polyLend), _loanAmount);
        uint256 offerId = polyLend.offer(requestId, _loanAmount, rate);
        vm.stopPrank();

        vm.startPrank(borrower);
        polyLend.cancelRequest(requestId);
        vm.expectRevert(OnlyBorrower.selector);
        polyLend.accept(offerId);
        vm.stopPrank();
    }
}
