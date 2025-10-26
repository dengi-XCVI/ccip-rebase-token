# Cross Chain Rebase Token

1. A protocol that allows users to deposit into a vault and in return receive rebase tokens that represent their underlying balance
2. Rebase token -> balanceOf function is dynamic to show the changing balance in time
   - balance will increase linearly in time
   - mint token to our users every time they perform an action (minting, burning, transferring, or..... bridging)
3. Interest rate
   - Individually set interest rate for every user based on global interest rate of the protocol at the time of vault deposit
   - This global interest rate can only decrease to incentivise/reward early adopters