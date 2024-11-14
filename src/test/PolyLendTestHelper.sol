// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test, console2 as console, stdStorage, StdStorage, stdError} from "../../lib/forge-std/src/Test.sol";
import {PolyLend, PolyLendEE, Loan, Request, Offer} from "../PolyLend.sol";
import {InterestLib} from "../InterestLib.sol";
import {USDC} from "../dev/USDC.sol";
import {DeployLib} from "../dev/DeployLib.sol";
import {IConditionalTokens} from "../interfaces/IConditionalTokens.sol";

contract PolyLendTestHelper is Test, PolyLendEE {
    USDC usdc;
    IConditionalTokens conditionalTokens;
    PolyLend polyLend;

    address oracle;
    address borrower;
    address splitter;
    address lender;

    bytes32 questionId = keccak256("BIDEN-TRUMP-2024");
    bytes32 conditionId;
    uint256 positionId0;
    uint256 positionId1;

    function setUp() public virtual {
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

    function _getRequest(uint256 _requestId) internal view returns (Request memory) {
        (address borrower_, uint256 positionId_, uint256 collateralAmount_, uint256 minimumDuration_) =
            polyLend.requests(_requestId);

        return Request({
            borrower: borrower_,
            positionId: positionId_,
            collateralAmount: collateralAmount_,
            minimumDuration: minimumDuration_
        });
    }

    function _getOffer(uint256 _offerId) internal view returns (Offer memory) {
        (uint256 requestId_, address lender_, uint256 loanAmount_, uint256 rate_) = polyLend.offers(_offerId);

        return Offer({requestId: requestId_, lender: lender_, loanAmount: loanAmount_, rate: rate_});
    }

    function _getLoan(uint256 _loanId) internal view returns (Loan memory) {
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
        ) = polyLend.loans(_loanId);

        return Loan({
            borrower: borrower_,
            lender: lender_,
            positionId: positionId_,
            collateralAmount: collateralAmount_,
            loanAmount: loanAmount_,
            rate: rate_,
            startTime: startTime_,
            minimumDuration: minimumDuration_,
            callTime: callTime_
        });
    }

    function _getNewRate(uint256 _callTime) internal view returns (uint256) {
        //return (block.timestamp - _callTime) * polyLend.MAX_INTEREST() / polyLend.AUCTION_DURATION();
        return InterestLib.ONE + ((block.timestamp - _callTime) * (polyLend.MAX_INTEREST() - InterestLib.ONE) / polyLend.AUCTION_DURATION());
    }
}
