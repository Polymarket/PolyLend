# Lending

We will use a 1-1 lending model.

That is: borrowers and lenders are matched 1-1, with predefined terms.
Lenders can _call_ the loan _at any time_, commencing a fixed length dutch auction to sell the loan to other lenders, potentially at a higher interest rate.  If the loan is not paid off, or repurchased, the borrower is liquidated.  It is possible that the proceeds from the liquidation are less than the loan amount, in which case the lender takes a loss.  If the proceeds are greater than the loan amount, the borrower keeps the difference.
In this case, the lender may choose to _not_ call the loan if the current price is less than the loan price; in particular if they believe the price may go back up in the future.

```[solidity]
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
```

## Borrowers

Borrowers submit a request for a loan, simply specifying the type and amount of collateral they wish to borrow against.  A request struct is created in storage with the next available requestId.

Borrowers are free to cancel a loan request at any time before they accept a loan offer.

To cancel a request, we set the borrower to the zero address.

## Lenders

Lenders submit offers to lend against a request.  Lenders specify the amount of USDC they wish to lend, and the interest rate they wish to charge.  An offer struct is created in storage with the next available offerId.

Lenders are free to cancel an offer at any time before the offer is accepted.

## Matching

Borrowers may accept any loan offer, and the loan is created in storage with the next available loanId.
