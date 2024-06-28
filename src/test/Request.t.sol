// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {PolyLendTestHelper, Request} from "./PolyLendTestHelper.sol";

contract PolyLendRequestTest is PolyLendTestHelper {
    function test_PolyLendRequestTest_request(uint128 _amount, uint32 _minimumDuration) public {
        vm.assume(_amount > 0);
        vm.assume(_minimumDuration <= 60 days);

        _mintConditionalTokens(borrower, _amount, positionId0);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);

        vm.expectEmit();
        emit LoanRequested(0, borrower, positionId0, _amount, _minimumDuration);
        uint256 requestId = polyLend.request(positionId0, _amount, _minimumDuration);
        vm.stopPrank();

        Request memory request = _getRequest(requestId);

        assertEq(request.borrower, borrower);
        assertEq(request.positionId, positionId0);
        assertEq(request.collateralAmount, _amount);
        assertEq(request.minimumDuration, _minimumDuration);

        assertEq(polyLend.nextRequestId(), 1);
    }

    function test_revert_PolyLendRequestTest_request_CollateralAmountIsZero() public {
        vm.prank(borrower);
        vm.expectRevert(CollateralAmountIsZero.selector);
        polyLend.request(positionId0, 0, 0);
    }

    function test_revert_PolyLendRequestTest_request_InsufficientCollateralBalance() public {
        vm.prank(borrower);
        vm.expectRevert(InsufficientCollateralBalance.selector);
        polyLend.request(positionId0, 100_000_000, 0);
    }

    function test_revert_PolyLendRequestTest_request_CollateralIsNotApproved() public {
        _mintConditionalTokens(borrower, 100_000_000, positionId0);

        vm.prank(borrower);
        vm.expectRevert(CollateralIsNotApproved.selector);
        polyLend.request(positionId0, 100_000_000, 0);
    }
}
