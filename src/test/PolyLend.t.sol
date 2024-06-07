// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, console2 as console, stdStorage, StdStorage, stdError} from "../../lib/forge-std/src/Test.sol";
import {PolyLend, PolyLendEE, Loan, Request, Offer} from "../PolyLend.sol";
import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";
import {DeployLib} from "../dev/DeployLib.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";

contract USDC is ERC20 {
    function name() public pure override returns (string memory) {
        return "USDC";
    }

    function symbol() public pure override returns (string memory) {
        return "USDC";
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}

contract PolyLendTest is Test, PolyLendEE {
    USDC usdc;
    IConditionalTokens conditionalTokens;
    PolyLend polyLend;

    address oracle;
    address borrower;
    address splitter;
    address lender;

    bytes32 questionId = keccak256("BIDEN TRUMP 2024");
    bytes32 conditionId;
    uint256 positionId0;
    uint256 positionId1;

    function setUp() public {
        usdc = new USDC();
        conditionalTokens = IConditionalTokens(DeployLib.deployConditionalTokens());
        polyLend = new PolyLend(address(conditionalTokens), address(usdc));

        oracle = vm.createWallet("oracle").addr;
        borrower = vm.createWallet("borrower").addr;
        splitter = vm.createWallet("splitter").addr;
        lender = vm.createWallet("lender").addr;

        conditionalTokens.prepareCondition(oracle, questionId, 2);
        conditionId = conditionalTokens.getConditionId(oracle, questionId, 2);

        bytes32 collectionId0 = conditionalTokens.getCollectionId(bytes32(0), conditionId, 1);
        positionId0 = conditionalTokens.getPositionId(address(usdc), collectionId0);

        bytes32 collectionId1 = conditionalTokens.getCollectionId(bytes32(0), conditionId, 2);
        positionId1 = conditionalTokens.getPositionId(address(usdc), collectionId1);
    }

    function _mintConditionalTokens(address _to, uint256 _amount, uint256 _positionId) internal {
        vm.startPrank(splitter);
        usdc.mint(splitter, _amount);
        usdc.approve(address(conditionalTokens), _amount);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        conditionalTokens.splitPosition(address(usdc), bytes32(0), conditionId, partition, _amount);
        conditionalTokens.safeTransferFrom(splitter, _to, _positionId, _amount, "");
        vm.stopPrank();
    }

    function test_revert_PolyLend_request_CollateralAmountIsZero() public {
        vm.prank(borrower);
        vm.expectRevert(CollateralAmountIsZero.selector);
        polyLend.request(positionId0, 0);
    }

    function test_revert_PolyLend_request_InsufficientCollateralBalance() public {
        vm.prank(borrower);
        vm.expectRevert(InsufficientCollateralBalance.selector);
        polyLend.request(positionId0, 100_000_000);
    }

    function test_revert_PolyLend_request_CollateralIsNotApproved() public {
        _mintConditionalTokens(borrower, 100_000_000, positionId0);

        vm.prank(borrower);
        vm.expectRevert(CollateralIsNotApproved.selector);
        polyLend.request(positionId0, 100_000_000);
    }

    function test_PolyLend_request(uint128 _amount) public {
        vm.assume(_amount > 0);
        _mintConditionalTokens(borrower, _amount, positionId0);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);

        vm.expectEmit();
        emit LoanRequested(0, borrower, positionId0, _amount);
        uint256 requestId = polyLend.request(positionId0, _amount);
        vm.stopPrank();

        (address borrower_, uint256 positionId_, uint256 collateralAmount_) = polyLend.requests(requestId);
        assertEq(borrower_, borrower);
        assertEq(positionId_, positionId0);
        assertEq(collateralAmount_, _amount);
    }

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

        (uint256 requestId_, address lender_, uint256 loanAmount_, uint256 rate_, uint256 minimumDuration_) =
            polyLend.offers(0);
        assertEq(requestId_, requestId);
        assertEq(lender_, lender);
        assertEq(loanAmount_, _loanAmount);
        assertEq(rate_, _rate);
        assertEq(minimumDuration_, _minimumDuration);
    }

    function test_PolyLend_acceptLoan(
        uint128 _collateralAmount,
        uint128 _loanAmount,
        uint256 _rate,
        uint256 _minimumDuration
    ) public {
        vm.assume(_collateralAmount > 0);
        vm.assume(_rate > 10 ** 18);
        vm.assume(_rate <= polyLend.MAX_INTEREST());
        vm.assume(_minimumDuration <= 60 days);

        _mintConditionalTokens(borrower, _collateralAmount, positionId0);
        usdc.mint(lender, _loanAmount);

        vm.startPrank(borrower);
        conditionalTokens.setApprovalForAll(address(polyLend), true);
        uint256 requestId = polyLend.request(positionId0, _collateralAmount);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(polyLend), _loanAmount);
        polyLend.offer(requestId, _loanAmount, _rate, _minimumDuration);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectEmit();
        emit LoanAccepted(requestId, block.timestamp);
        polyLend.acceptLoan(requestId, 0);
        vm.stopPrank();

        (
            address borrower_,
            address lender_,
            uint256 positionId_,
            uint256 collateralAmount_,
            uint256 loanAmount_,
            uint256 rate_,
            uint256 startTime_,
            uint256 minimumDuration_,
            uint256 callTime_
        ) = polyLend.loans(0);

        assertEq(borrower_, borrower);
        assertEq(lender_, lender);
        assertEq(positionId_, positionId0);
        assertEq(collateralAmount_, _collateralAmount);
        assertEq(loanAmount_, _loanAmount);
        assertEq(rate_, _rate);
        assertEq(startTime_, block.timestamp);
        assertEq(minimumDuration_, _minimumDuration);
        assertEq(callTime_, 0);

        assertEq(usdc.balanceOf(borrower), _loanAmount);
        assertEq(conditionalTokens.balanceOf(address(polyLend), positionId0), _collateralAmount);
    }
}
