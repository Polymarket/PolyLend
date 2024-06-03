# Lending

We will use a 1-1 lending model.

That is: borrowers and lenders are matched 1-1, with predefined terms.
Lenders can _call_ the loan _at any time_, commencing a fixed length dutch auction to sell the loan to other lenders, potentially at a higher interest rate.  If the loan is not paid off, or repurchased, the borrower is liquidated.  It is possible that the proceeds from the liquidation are less than the loan amount, in which case the lender takes a loss.  If the proceeds are greater than the loan amount, the borrower keeps the difference.
In this case, the lender may choose to _not_ call the loan if the current price is less than the loan price; in particular if they believe the price may go back up in the future.