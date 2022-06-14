# Challenge Proposal

## Sources / Inspiration
```Inspired by the surge in adoption of Blockchain, Smart Contracts, NFTs and the likes. We have created an interesting smart contract challenge which depicts possible exploitation scenario in Smart Contracts.```
## Challenge Title
```fill in a creative challenge title```
## Challenge Category
```n.a.```
## Challenge Description / Question
```To Whom It May Concern,

We are writing to you because we need help from a elite security expert to investigate a suspicious attack on our client's decentralized lending and borrowing market. We had been helping them to both build and conduct security code reviews on the market application for months and months, and finally, we launched it on the Ethereum blockchain last week. Our customers were so excited about it, and we achieved a total value lock of one million dollars in just an hour!

However, one of our senior engineers noticed some abnormal behaviors in the market and highly suspected that some attackers were stealing the funds in the market unexpectedly. Our incident response team quickly paused the market application to prevent more funds from being stolen. They wanted to find out the attack transactions to have the engineers fix the bug. But unfortunately, no one from our company knows how the attack worked. 

So, we wanted to reach out to you and request help. We heard about you from the Cyber League leaderboard and that your expertise is in smart contract security and blockchain. Would you be able to help us with this?

P.S. You may find our market application here: https://kovan.etherscan.io/address/0x16537776395108789FE5cC5420545CAb210a7D30

Sincerely,
Cindy
CTO of DraftDown Labs Pte. Ltd.
```
## Challenge Difficulty
```Medium```
## Challenge Hints
```
1. The attack transactions exploited only one type of bug in the contracts.
2. The attack may require multiple transactions (function calls) to gain profit. For example, the attacker may need to call `functionA()` in one transaction and then `functionB()` in another transaction. In that case, both transactions are considered attack transactions. Transactions from the owner (i.e., the address that deployed the contracts) are not considered attack transactions.
3. You only have to focus on the transactions sent after the market contract was initialized and before the owner calls `pause()` on the market.
4. Once you have collected all the attack transactions, run `check_flag.py` to see if you're correct. The output is the flag.
```
## Challenge Flag
CYBERLEAGUE{```bf22a2d63563554c2073f9480867794e17297ce17c7ec4cc3502979828e4253f```}
## Challenge Resources
```Nothing```
