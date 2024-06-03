// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ConditionalTokens} from "../lib/conditional-tokens-contracts/contracts/ConditionalTokens.sol";
import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";

contract PolyLend {
    struct Loan {
        address borrower;
        address lender;
        uint256 positionId;
        uint256 collateralAmount;
        uint256 loanAmount;
        uint256 rate;
        uint256 startTime;
        uint256 callTime;
    }

    struct Request {
        uint256 loanId;
        address borrower;
        uint256 positionId;
        uint256 collateralAmount;
    }

    struct Offer {
        uint256 requestId;
        address lender;
        uint256 loanAmount;
        uint256 rate;
    }

    event LoanRequested(uint256 id, address borrower, uint256 positionId, uint256 collateralAmount);
    event LoanOffered(uint256 id, uint256 loanAmount, uint256 rate);
    event LoanAccepted(uint256 id, uint256 startTime);
    event LoanCalled(uint256 id, uint256 callTime);
    event LoanRepayed(uint256 id);

    ConditionalTokens public immutable conditionalTokens;
    ERC20 public immutable usdc;

    uint256 public nextLoanId = 0;
    uint256 public nextRequestId = 0;
    uint256 public nextOfferId = 0;

    mapping(uint256 => Loan) public loans;
    mapping(uint256 => Request) public requests;
    mapping(uint256 => Offer) public offers;

    uint256 public auctionDuration = 1 days;
    uint256 public paybackBuffer = 5 minutes;

    constructor(address _conditionalTokens, address _usdc) {
        conditionalTokens = ConditionalTokens(_conditionalTokens);
        usdc = ERC20(_usdc);
    }

    function request(uint256 _positionId, uint256 _collateralAmount) {
        require(_collateralAmount > 0, "Collateral amount must be greater than 0");
        require(conditionalTokens.balanceOf(msg.sender, _positionId) >= _collateralAmount, "Insufficient collateral");
        require(conditionalTokens.isApprovedForAll(msg.sender, address(this)));

        uint256 requestId = nextRequestId;
        nextRequestId += 1;

        requests[requestId] = Request(requestId, msg.sender, _positionId, _collateralAmount);
        emit LoanRequested(requestId, msg.sender, _positionId, _collateralAmount);
    }

    function cancelRequest(uint256 _requestId) {
        require(requests[_requestId].borrower == msg.sender, "Only borrower can cancel request");
        requests[_requestId].borrower = address(0);
    }

    function offer(uint256 _requestId, uint256 _loanAmount, uint256 _rate) {
        require(request[_id].borrower != address(0), "Loan does not exist");
        require(request[_id].lender == address(0), "Loan already taken");
        require(usdc.balanceOf(msg.sender) >= _loanAmount, "Insufficient funds");
        require(usdc.allowance(msg.sender, address(this)) >= _loanAmount, "Insufficient allowance");

        uint256 offerId = nextOfferId;
        nextOfferId += 1;

        offers[offerId] = Offer(_requestId, msg.sender, _loanAmount, _rate);
        emit LoanOffered(_id, _loanAmount, _rate);
    }

    function cancelOffer(uint256 _id) {
        require(offers[_id].lender == msg.sender, "Only lender can cancel offer");
        offers[_id].lender = address(0);
    }

    function acceptLoan(uint256 _requestId, uint256 _offerId) {
        require(requests[_requestId].borrower == msg.sender, "Only borrower can accept loan");
        require(offers[_offerId].lender != address(0), "Loan offer does not exist");

        uint256 loadId = nextLoanId;
        nextLoanId += 1;

        loans[loadId] = Loan(
            requests[_requestId].borrower,
            offers[_offerId].lender,
            requests[_requestId].positionId,
            requests[_requestId].collateralAmount,
            offers[_offerId].loanAmount,
            offers[_offerId].rate,
            block.timestamp
        );

        requests[_requestId].borrower = address(0);
        requests[_requestId].lender = address(0);

        conditionalTokens.safeTransferFrom(msg.sender, address(this), loans[_id].collateralAmount);
        usdc.transferFrom(loans[_id].lender, msg.sender, loans[_id].loanAmount);

        emit LoanAccepted(_id, block.timestamp);
    }

    function callLoan(uint256 _loanId) {
        require(loans[_loanId].lender == msg.sender, "Only borrower can call loan");
        // to-do

        emit LoanCalled(_id, block.timestamp);
    }

    function paybackLoan(uint256 _loanId, uint256 _paybackTime) {
        require(loans[_loanId].borrower == msg.sender, "Only borrower can payback loan");
        require(_paybackTime + paybackBuffer > block.timestamp, "Payback time is too early");
        // to-do

        loans[_loanId].borrower = address(0);
        emit LoanRepayed(_id);
    }

    function transferLoan(uint256 _loanId, uint256 _newRate) {
        require(loans[_loanId].lender == msg.sender, "Only lender can takeover loan");
        require(loans[_loanId].callTime != 0, "Loan is not called");
        require(loans[_loanId].callTime + auctionDuration < block.timestamp, "Loan cannot be taken over yet");
        // to-do
    }
}
