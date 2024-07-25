// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {ERC1155TokenReceiver} from "./ERC1155TokenReceiver.sol";
import {InterestLib} from "./InterestLib.sol";

/// @notice Loan struct
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

/// @notice Request struct
struct Request {
    address borrower;
    uint256 positionId;
    uint256 collateralAmount;
    uint256 minimumDuration;
}

/// @notice Offer struct
struct Offer {
    uint256 requestId;
    address lender;
    uint256 loanAmount;
    uint256 rate;
}

/// @title PolyLendEE
/// @notice PolyLend events and errors
interface PolyLendEE {
    event LoanAccepted(uint256 id, uint256 startTime);
    event LoanCalled(uint256 id, uint256 callTime);
    event LoanOffered(uint256 id, address lender, uint256 loanAmount, uint256 rate);
    event LoanRepaid(uint256 id);
    event LoanRequested(
        uint256 id, address borrower, uint256 positionId, uint256 collateralAmount, uint256 minimumDuration
    );
    event LoanTransferred(uint256 oldId, uint256 newId, address newLender, uint256 newRate);
    event LoanReclaimed(uint256 id);

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
    error AuctionHasNotEnded();
}

/// @title PolyLend
/// @notice A contract for lending USDC using conditional tokens as collateral
/// @author mike@polymarket.com
contract PolyLend is PolyLendEE, ERC1155TokenReceiver {
    using InterestLib for uint256;

    /// @notice per second rate equal to roughly 1000% APY
    uint256 public constant MAX_INTEREST = InterestLib.ONE + InterestLib.ONE_THOUSAND_APY;

    /// @notice duration of the auction for transferring a loan
    uint256 public constant AUCTION_DURATION = 1 days;

    /// @notice buffer for payback time
    uint256 public constant PAYBACK_BUFFER = 1 minutes;

    /// @notice The conditional tokens contract
    IConditionalTokens public immutable conditionalTokens;

    /// @notice The USDC token contract
    ERC20 public immutable usdc;

    /// @notice The next id for a loan
    uint256 public nextLoanId = 0;

    /// @notice The next id for a request
    uint256 public nextRequestId = 0;

    /// @notice The next id for an offer
    uint256 public nextOfferId = 0;

    /// @notice loans mapping
    mapping(uint256 => Loan) public loans;

    /// @notice requests mapping
    mapping(uint256 => Request) public requests;

    /// @notice offers mapping
    mapping(uint256 => Offer) public offers;

    constructor(address _conditionalTokens, address _usdc) {
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        usdc = ERC20(_usdc);
    }

    /// @notice Get the amount owed on a loan
    /// @param _loanId The id of the loan
    /// @param _paybackTime The time at which the loan will be paid back
    /// @return The amount owed on the loan
    function getAmountOwed(uint256 _loanId, uint256 _paybackTime) public view returns (uint256) {
        uint256 loanDuration = _paybackTime - loans[_loanId].startTime;
        return _calculateAmountOwed(loans[_loanId].loanAmount, loans[_loanId].rate, loanDuration);
    }

    /*//////////////////////////////////////////////////////////////
                                REQUEST
    //////////////////////////////////////////////////////////////*/

    /// @notice Submit a request for loan offers
    /// @param _positionId The conditional token position id
    /// @param _collateralAmount The amount of collateral
    /// @param _minimumDuration The minimum duration of the loan
    /// @return The request id
    function request(uint256 _positionId, uint256 _collateralAmount, uint256 _minimumDuration)
        external
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
    /// @param _requestId The request id
    function cancelRequest(uint256 _requestId) public {
        if (requests[_requestId].borrower != msg.sender) {
            revert OnlyBorrower();
        }

        requests[_requestId].borrower = address(0);
    }

    /*//////////////////////////////////////////////////////////////
                                 OFFER
    //////////////////////////////////////////////////////////////*/

    /// @notice Submit a loan offer for a request
    /// @param _requestId The request id
    /// @param _loanAmount The usdc amount of the loan
    /// @param _rate The interest rate of the loan
    /// @return The offer id
    function offer(uint256 _requestId, uint256 _loanAmount, uint256 _rate) external returns (uint256) {
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
    /// @param _id The offer id
    function cancelOffer(uint256 _id) public {
        if (offers[_id].lender != msg.sender) {
            revert OnlyLender();
        }

        offers[_id].lender = address(0);
    }

    /*//////////////////////////////////////////////////////////////
                                 ACCEPT
    //////////////////////////////////////////////////////////////*/

    /// @notice Accept a loan offer
    /// @param _offerId The offer id
    /// @return The loan id
    function accept(uint256 _offerId) external returns (uint256) {
        uint256 requestId = offers[_offerId].requestId;
        address borrower = requests[requestId].borrower;
        address lender = offers[_offerId].lender;

        if (borrower != msg.sender) {
            revert OnlyBorrower();
        }

        if (lender == address(0)) {
            revert InvalidOffer();
        }

        uint256 loanId = nextLoanId;
        nextLoanId += 1;

        uint256 positionId = requests[requestId].positionId;
        uint256 collateralAmount = requests[requestId].collateralAmount;
        uint256 loanAmount = offers[_offerId].loanAmount;

        // create new loan
        loans[loanId] = Loan({
            borrower: borrower,
            lender: lender,
            positionId: positionId,
            collateralAmount: collateralAmount,
            loanAmount: loanAmount,
            rate: offers[_offerId].rate,
            startTime: block.timestamp,
            minimumDuration: requests[_offerId].minimumDuration,
            callTime: 0
        });

        // invalidate the request
        requests[requestId].borrower = address(0);

        // invalidate the offer
        offers[requestId].lender = address(0);

        // transfer the borrowers collateral to address(this)
        conditionalTokens.safeTransferFrom(msg.sender, address(this), positionId, collateralAmount, "");

        // transfer usdc from the lender to the borrower
        usdc.transferFrom(lender, msg.sender, loanAmount);

        emit LoanAccepted(loanId, block.timestamp);

        return loanId;
    }

    /*//////////////////////////////////////////////////////////////
                                  CALL
    //////////////////////////////////////////////////////////////*/

    /// @notice Call a loan
    /// @param _loanId The id of the loan
    function call(uint256 _loanId) external {
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

    /*//////////////////////////////////////////////////////////////
                                 REPAY
    //////////////////////////////////////////////////////////////*/

    /// @notice Repay a loan
    /// @notice It is possible that the the block.timestamp will differ
    /// @notice from the time that the transaction is submitted to the
    /// @notice block when it is mined.
    /// @param _loanId The loan id
    /// @param _repayTimestamp The time at which the loan will be paid back
    function repay(uint256 _loanId, uint256 _repayTimestamp) external {
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

    /*//////////////////////////////////////////////////////////////
                                TRANSFER
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer a called loan to a new lender
    /// @notice The new lender must offer a rate less than or equal to the current rate
    /// @param _loanId The loan id
    /// @param _newRate The new interest rate
    function transfer(uint256 _loanId, uint256 _newRate) external {
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

    /*//////////////////////////////////////////////////////////////
                                RECLAIM
    //////////////////////////////////////////////////////////////*/

    /// @notice Reclaim a called loan after the auction ends
    /// @notice and the loan has not been transferred
    /// @notice The lender will receive the borrower's collateral
    /// @param _loanId The loan id
    function reclaim(uint256 _loanId) external {
        if (loans[_loanId].borrower == address(0)) {
            revert InvalidLoan();
        }

        if (loans[_loanId].lender != msg.sender) {
            revert OnlyLender();
        }

        if (loans[_loanId].callTime == 0) {
            revert LoanIsNotCalled();
        }

        if (block.timestamp <= loans[_loanId].callTime + AUCTION_DURATION) {
            revert AuctionHasNotEnded();
        }

        // cancel the loan
        loans[_loanId].borrower = address(0);

        // transfer the borrower's collateral to the lender
        conditionalTokens.safeTransferFrom(
            address(this), msg.sender, loans[_loanId].positionId, loans[_loanId].collateralAmount, ""
        );

        emit LoanReclaimed(_loanId);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate the amount owed on a loan
    /// @param _loanAmount The initial usdc amount of the loan
    /// @param _rate The interest rate of the loan
    /// @param _loanDuration The duration of the loan
    /// @return The total amount owed on the loan
    function _calculateAmountOwed(uint256 _loanAmount, uint256 _rate, uint256 _loanDuration)
        internal
        pure
        returns (uint256)
    {
        uint256 interestMultiplier = _rate.pow(_loanDuration);
        return _loanAmount * interestMultiplier / InterestLib.ONE;
    }
}
