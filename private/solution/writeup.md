## Solution

### Step 0: Prerequisites

This challenge requires basic knowledge of the Ethereum blockchain (e.g., accounts, transactions) and smart contracts, including ERC20 tokens and the widely-used OpenZeppelin libraries. If you are not familiar with them, please refer to the following links:

- [ethereum.org - Community guides and resources](https://ethereum.org/en/learn/)
- [ethereum.org - ERC-20 TOKEN STANDARD](https://ethereum.org/en/developers/docs/standards/tokens/erc-20/)
- [OpenZeppelin/openzeppelin-contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)

### Step 1: Gathering Basic Information

According to the challenge description, our goal is to find all transactions that exploit a vulnerability in the lending market that allows unexpected or unauthorized funds to be transferred from it. To examine the transactions on the Ethereum blockchain (the Kovan testnet), I'd recommend using the [Etherscan](https://kovan.etherscan.io) blockchain explorer. Ethersacn allows you to, for example,

1. View all transactions included in a specific block
2. View all details (e.g., sender, receiver, data) of a specific transaction
3. View a contract's source code (if verified) and ABI.
4. Read public state variables or call view functions on the contract easily.

From Etherscan, we can get the source code of the `Market` and the `Oracle` contract and get a sense of how users (or attackers) interact with the `Market` contract. We may see a bunch of transactions calling, e.g., `lock`, `unlock`, `borrow`, `repay`, which gives us a hint on how the market worked. We can guess that the vulnerability is likely something that allows the attacker to gain more tokens than he should.

### Step 2: Spotting the Vulnerability

What's the vulnerability in the code? Let's see how the `Market` contract fetches a token's price:

```js
function getTokenPrice(address token) internal view returns (uint) {
    if (token == address(0) || token == WETH) return ONE;
    (uint price, ) = IOracle(oracle).getTokenPrice(token);
    return price;
}
```

And, in the `Oracle` contract, a token's price information is read directly from the contract storage mapping:

```js
function getTokenPrice(address token) public view returns (uint, uint) {
    return (priceInfo[token].priceToETH, priceInfo[token].lastUpdate);
}
```

The vulnerability is that there are no sanity checks on the returned price value neither in the `Oracle` or the `Market` contract. If the price of a token is not set in the oracle, `Oracle.getTokenPrice()` always returns `(0, 0)` (the default value in a storage slot). The `Market` contract does not ensure `lastUpdate > 0` either, but it directly uses the value returned from the oracle. Therefore, `Market.getTokenPrice()` returns `0` for any token whose price is not set yet.

By examining the transactions sent to the `Market` contract, we may notice that after the owner created the market, he initialized the allowed locked and borrowed tokens for the market. Further investigation shows that the `DAI` and `USDT` tokens were set to be the allowed borrowed tokens. However, by examining the transactions sent to the oracle, we notice that the owner never set the price of USDT. Therefore, the market thought the price of USDT was `0` and allowed the attackers to borrow any amount of USDT without providing any collateral tokens. This was the attack that stole the USDT from the market.

### Step 3: Finding Attack Transactions

To borrow USDT from the market, the attacker had to:

1. Create a position with the borrowed token being USDT (the locked token can be any token)
2. Borrow some amount of USDT from the market using the corresponding position

Any transaction that either performed the first step or the second step is considered an attack transaction, and we wanted to find all of them. There were about 172 transactions sent to the market, so it would be better to automate examining and filtering out the attack transactions. Let's use the [`Web3.py`](https://web3py.readthedocs.io) library to assist us. First, to fetch the data on the Ethereum blockchain, we need to connect to an RPC node. Here, I use the [Alchemy](https://www.alchemy.com) service as an example:

```python
def setup_web3_provider(timeout=120):
    env = 'ALCHEMY_KOVAN_API_KEY'
    end_point = f'https://eth-kovan.alchemyapi.io/v2/{os.environ[env]}'
    w3 = Web3(Web3.HTTPProvider(
        endpoint_uri=end_point,
        request_kwargs={
            'timeout': timeout
        }
    ))
    return w3
```

Next, we iterate the blocks during the attack period to get all transactions within them. Please refer to the above link for the detailed usage of `Web3.py` APIs:

```python
for block_num in range(start_block_num, end_block_num + 1):
    block = w3.eth.get_block(block_num)
    for tx_hash in block['transactions']:
        tx = w3.eth.get_transaction(tx_hash)
        if tx['to'] == market:
            print(tx['from']) # the sender of the tx
```

We may notice that only three users interacted with the market during this period. Let's call them Alice, Bob, and Cathy. We filter out all successful transactions sent from any of them and check whether they were the attack transactions:

```python
for block_num in range(start_block_num, end_block_num + 1):
    block = w3.eth.get_block(block_num)
    for tx_hash in block['transactions']:
        tx = w3.eth.get_transaction(tx_hash)
        if tx['from'] in [alice, bob, cathy] and tx['to'] == market:
            tx_receipt = w3.eth.get_transaction_receipt(tx_hash)
            if tx_receipt['status'] == 1: # success
                ... # check this is an attack or not
```

To know which function the transaction was calling, we need to get the contract ABI (available on Etherscan). Then, we create a `Contract` object representing the market:

```python
with open('abi.json', 'r') as f:
    obj = json.load(f)
abi = json.loads(obj['result'])
cont = w3.eth.contract(address=market, abi=abi)
```

With the contract object, we can decode the transaction input to get the calling function and the provided arguments, which we can use to identify transactions calling the `createPosition` and `borrow` functions. One more thing, because the newly created position's ID is logged in a smart contract event, we have to get it by processing the transaction receipt:

```python
func, args = cont.decode_function_input(tx['input'])
if func.fn_name == 'createPosition' and args['borrowedToken'] == usdt:
    print('found attack, createPosition')
    pid = cont.events.CreatePosition().processReceipt(tx_receipt)[0]['args']['pid']
    ...
```

Putting them all together, we have a script to find all attack transactions. Please see the `solution.py` file for the complete script.

```python
attack_tx_hashes, attack_pids = set(), set()
for block_num in range(start_block_num, end_block_num + 1):
    print('block # = ', block_num)
    block = w3.eth.get_block(block_num)
    for tx_hash in block['transactions']:
        tx = w3.eth.get_transaction(tx_hash)
        if tx['from'] in [alice, bob, cathy] and tx['to'] == market:
            tx_receipt = w3.eth.get_transaction_receipt(tx_hash)
            if tx_receipt['status'] == 1: # success
                func, args = cont.decode_function_input(tx['input'])
                if func.fn_name == 'createPosition' and args['borrowedToken'] == usdt:
                    print('found attack, createPosition')
                    pid = cont.events.CreatePosition().processReceipt(tx_receipt)[0]['args']['pid']
                    attack_tx_hashes.add(tx_hash)
                    attack_pids.add((tx['from'], pid))
                if func.fn_name == 'borrow' and (tx['from'], args['pid']) in attack_pids:
                    print('found attack, borrow')
                    attack_tx_hashes.add(tx_hash)
    time.sleep(0.5)
```

By pasting the found transactions in the `check_flag.py` script, we get the flag: `flag{bf22a2d63563554c2073f9480867794e17297ce17c7ec4cc3502979828e4253f}`