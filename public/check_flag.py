import hashlib

txs = [
    # put the attack transactions your found here
]

'''
e.g.,
txs = [
    '0x0000000000000000000000000000000000000000000000000000000000000000',
    '0x0000000000000000000000000000000000000000000000000000000000000001',
    '0x0000000000000000000000000000000000000000000000000000000000000002',
    ...
]
'''

assert len(txs) == 22
salt = b'hint: find abnormal transactions'
m = hashlib.sha256()
for tx_hash in sorted(txs):
    assert len(tx_hash) == 66 and tx_hash[:2] == '0x'
    m.update(salt + tx_hash.encode() + m.digest())

assert m.hexdigest()[:16] == 'bf22a2d63563554c'
print('flag{' + m.hexdigest() + '}')