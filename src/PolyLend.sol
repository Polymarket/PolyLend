// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {ERC1155TokenReceiver} from "./ERC1155TokenReceiver.sol";
import {InterestLib} from "./InterestLib.sol";

struct Loan {
    address borrower;
    address lender;
    uint256 positionId;
    uint256 collateralAmount;
    uint256 loanAmount;
    uint256 rate;
    uint256 startTime;
    uint256 minimumDuration;
    uint256 callTime;
}

struct Request {
    address borrower;
    uint256 positionId;
    uint256 collateralAmount;
    uint256 minimumDuration;
}

struct Offer {
    uint256 requestId;
    address lender;
    uint256 loanAmount;
    uint256 rate;
}

interface PolyLendEE {
    event LoanAccepted(uint256 id, uint256 startTime);
    event LoanCalled(uint256 id, uint256 callTime);
    event LoanOffered(uint256 id, address lender, uint256 loanAmount, uint256 rate);
    event LoanRepaid(uint256 id);
    event LoanRequested(
        uint256 id, address borrower, uint256 positionId, uint256 collateralAmount, uint256 minimumDuration
    );
    event LoanTransferred(uint256 oldId, uint256 newId, address newLender, uint256 newRate);

    error CollateralAmountIsZero();
    error InsufficientCollateralBalance();
    error CollateralIsNotApproved();
    error OnlyBorrower();
    error OnlyLender();
    error InvalidRequest();
    error InvalidOffer();
    error InvalidLoan();
    error InsufficientFunds();
    error InsufficientAllowance();
    error InvalidRate();
    error InvalidRepayTimestamp();
    error LoanIsNotCalled();
    error LoanIsCalled();
    error MinimumDurationHasNotPassed();
    error AuctionHasEnded();
}

/// @title PolyLend
contract PolyLend is PolyLendEE, ERC1155TokenReceiver {
    using InterestLib for uint256;

    /// @notice per second rate equal to roughly 1000% APY
    uint256 public constant MAX_INTEREST = InterestLib.ONE + InterestLib.ONE_THOUSAND_APY;
    uint256 public constant AUCTION_DURATION = 1 days;
    uint256 public constant PAYBACK_BUFFER = 1 minutes;

    IConditionalTokens public immutable conditionalTokens;
    ERC20 public immutable usdc;

    uint256 public nextLoanId = 0;
    uint256 public nextRequestId = 0;
    uint256 public nextOfferId = 0;

    mapping(uint256 => Loan) public loans;
    mapping(uint256 => Request) public requests;
    mapping(uint256 => Offer) public offers;

    constructor(address _conditionalTokens, address _usdc) {
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        usdc = ERC20(_usdc);
    }

    function getAmountOwed(uint256 _loanId, uint256 _paybackTime) public view returns (uint256) {
        uint256 loanDuration = _paybackTime - loans[_loanId].startTime;
        return _calculateAmountOwed(loans[_loanId].loanAmount, loans[_loanId].rate, loanDuration);
    }

    /// @notice Submit a request for loan offers
    function request(uint256 _positionId, uint256 _collateralAmount, uint256 _minimumDuration)
        public
        returns (uint256)
    {
        if (_collateralAmount == 0) {
            revert CollateralAmountIsZero();
        }

        if (conditionalTokens.balanceOf(msg.sender, _positionId) < _collateralAmount) {
            revert InsufficientCollateralBalance();
        }

        if (!conditionalTokens.isApprovedForAll(msg.sender, address(this))) {
            revert CollateralIsNotApproved();
        }

        uint256 requestId = nextRequestId;
        nextRequestId += 1;

        requests[requestId] = Request(msg.sender, _positionId, _collateralAmount, _minimumDuration);
        emit LoanRequested(requestId, msg.sender, _positionId, _collateralAmount, _minimumDuration);

        return requestId;
    }

    /// @notice Cancel a loan request
    function cancelRequest(uint256 _requestId) public {
        if (requests[_requestId].borrower != msg.sender) {
            revert OnlyBorrower();
        }

        requests[_requestId].borrower = address(0);
    }

    /// @notice Submit a loan offer for a request
    function offer(uint256 _requestId, uint256 _loanAmount, uint256 _rate) public returns (uint256) {
        if (requests[_requestId].borrower == address(0)) {
            revert InvalidRequest();
        }

        if (usdc.balanceOf(msg.sender) < _loanAmount) {
            revert InsufficientFunds();
        }

        if (usdc.allowance(msg.sender, address(this)) < _loanAmount) {
            revert InsufficientAllowance();
        }

        if (_rate <= InterestLib.ONE || _rate > MAX_INTEREST) {
            revert InvalidRate();
        }

        uint256 offerId = nextOfferId;
        nextOfferId += 1;

        offers[offerId] = Offer(_requestId, msg.sender, _loanAmount, _rate);

        emit LoanOffered(_requestId, msg.sender, _loanAmount, _rate);

        return offerId;
    }

    /// @notice Cancel a loan offer
    function cancelOffer(uint256 _id) public {
        if (offers[_id].lender != msg.sender) {
            revert OnlyLender();
        }

        offers[_id].lender = address(0);
    }

    /// @notice Accept a loan offer
    function accept(uint256 _requestId, uint256 _offerId) public returns (uint256) {
        if (requests[_requestId].borrower != msg.sender) {
            revert OnlyBorrower();
        }

        if (offers[_offerId].lender == address(0)) {
            revert InvalidOffer();
        }

        uint256 loanId = nextLoanId;
        nextLoanId += 1;

        // create new loan
        loans[loanId] = Loan({
            borrower: requests[_requestId].borrower,
            lender: offers[_offerId].lender,
            positionId: requests[_requestId].positionId,
            collateralAmount: requests[_requestId].collateralAmount,
            loanAmount: offers[_offerId].loanAmount,
            rate: offers[_offerId].rate,
            startTime: block.timestamp,
            minimumDuration: requests[_offerId].minimumDuration,
            callTime: 0
        });

        // invalidate the request
        requests[_requestId].borrower = address(0);

        // invalidate the offer
        offers[_requestId].lender = address(0);

        // transfer the borrowers collateral to address(this)
        conditionalTokens.safeTransferFrom(
            msg.sender, address(this), loans[_requestId].positionId, loans[_requestId].collateralAmount, ""
        );

        // transfer usdc from the lender to the borrower
        usdc.transferFrom(loans[_requestId].lender, msg.sender, loans[_requestId].loanAmount);

        emit LoanAccepted(_requestId, block.timestamp);

        return loanId;
    }

    /// @notice Call a loan
    function call(uint256 _loanId) public {
        if (loans[_loanId].borrower == address(0)) {
            revert InvalidLoan();
        }

        if (loans[_loanId].lender != msg.sender) {
            revert OnlyLender();
        }

        if (block.timestamp < loans[_loanId].startTime + loans[_loanId].minimumDuration) {
            revert MinimumDurationHasNotPassed();
        }

        if (loans[_loanId].callTime != 0) {
            revert LoanIsCalled();
        }

        loans[_loanId].callTime = block.timestamp;

        emit LoanCalled(_loanId, block.timestamp);
    }

    /// @notice Repay a loan
    /// @notice It is possible that the the block.timestamp will differ
    /// @notice from the time that the transaction is submitted to the
    /// @notice block when it is mined.
    function repay(uint256 _loanId, uint256 _repayTimestamp) public {
        if (loans[_loanId].borrower != msg.sender) {
            revert OnlyBorrower();
        }

        // if the loan has not been called,
        // _repayTimestamp can be up to PAYBACK_BUFFER seconds in the past
        if (loans[_loanId].callTime == 0) {
            if (_repayTimestamp + PAYBACK_BUFFER < block.timestamp) {
                revert InvalidRepayTimestamp();
            }
        }
        // otherwise, the payback time must be the call time
        else {
            if (loans[_loanId].callTime != _repayTimestamp) {
                revert InvalidRepayTimestamp();
            }
        }

        // compute accrued interest
        uint256 loanDuration = _repayTimestamp - loans[_loanId].startTime;
        uint256 amountOwed = _calculateAmountOwed(loans[_loanId].loanAmount, loans[_loanId].rate, loanDuration);

        // transfer usdc from the borrower to the lender
        usdc.transferFrom(msg.sender, loans[_loanId].lender, amountOwed);
        // transfer the borrowers collateral back to the borrower
        conditionalTokens.safeTransferFrom(
            address(this), msg.sender, loans[_loanId].positionId, loans[_loanId].collateralAmount, ""
        );

        // cancel loan
        loans[_loanId].borrower = address(0);

        emit LoanRepaid(_loanId);
    }

    /// @notice Transfer a called loan to a new lender
    function transfer(uint256 _loanId, uint256 _newRate) public {
        if (loans[_loanId].borrower == address(0)) {
            revert InvalidLoan();
        }

        if (loans[_loanId].callTime == 0) {
            revert LoanIsNotCalled();
        }

        if (block.timestamp > loans[_loanId].callTime + AUCTION_DURATION) {
            revert AuctionHasEnded();
        }

        uint256 currentInterestRate = (block.timestamp - loans[_loanId].callTime) * MAX_INTEREST / AUCTION_DURATION;

        // _newRate must be less than or equal to the current offered rate
        if (_newRate > currentInterestRate) {
            revert InvalidRate();
        }

        // calculate amount owed on the loan as of callTime
        uint256 amountOwed = _calculateAmountOwed(
            loans[_loanId].loanAmount, loans[_loanId].rate, loans[_loanId].callTime - loans[_loanId].startTime
        );

        uint256 loanId = nextLoanId;
        nextLoanId += 1;

        address borrower = loans[_loanId].borrower;

        // create new loan
        loans[loanId] = Loan({
            borrower: borrower,
            lender: msg.sender,
            positionId: loans[_loanId].positionId,
            collateralAmount: loans[_loanId].collateralAmount,
            loanAmount: amountOwed,
            rate: _newRate,
            startTime: block.timestamp,
            minimumDuration: 0,
            callTime: 0
        });

        // cancel the old loan
        loans[_loanId].borrower = address(0);

        // transfer usdc from the new lender to the old lender
        usdc.transferFrom(msg.sender, loans[_loanId].lender, amountOwed);

        emit LoanTransferred(_loanId, loanId, msg.sender, _newRate);
    }

    function _calculateAmountOwed(uint256 _loanAmount, uint256 _rate, uint256 _loanDuration)
        internal
        pure
        returns (uint256)
    {
        uint256 interestMultiplier = _rate.pow(_loanDuration);
        return _loanAmount * interestMultiplier / InterestLib.ONE;
    }
}
