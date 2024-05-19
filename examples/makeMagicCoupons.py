import os
import json
import base64
from web3 import Web3
from eth_account import Account, messages
from hashlib import md5


js_nonces = json.loads(open('data.json').read())

count = 0
total = 0


def makeMagicCoupon(claimerAddr, adminPk, tier, nonce):
    hash = Web3.soliditySha3(['address', 'string'],
                             [claimerAddr, tier + nonce])
    if Web3.toHex(hash) not in js_nonces:
        print('hash="' + Web3.toHex(hash) + '" for nonce=' + nonce)
    message = messages.encode_defunct(hash)
    sig = Account.sign_message(message, adminPk)
    return nonce + base64.b64encode(sig.signature).decode()


_claimerAddr = os.environ['MC_CLAIMER_ADDR']
_tier = os.environ['MC_TIER']
_magicCouponAdminPrivKey = os.environ['MC_ADMIN_PKEY']
_nonces = []
for _nonce_code in os.environ['MC_NONCE_CODES'].split(" "):
    _nonce1 = md5(_nonce_code.encode()).hexdigest()
    _nonce2 = 'r' + md5(_nonce_code.encode()).hexdigest()[1:]
    if _nonce1 not in js_nonces:
        print('_nonce1="' + _nonce1 + '",', )
    if _nonce2 not in js_nonces:
        print('_nonce2="' + _nonce2 + '",')
    _nonces.extend([_nonce1, _nonce2])

for _nonce in _nonces:
    total += 1
    magicCoupon = makeMagicCoupon(_claimerAddr, _magicCouponAdminPrivKey,
                                  _tier, _nonce)
    # print('_claimerAddr', _claimerAddr, 'magicCoupon', magicCoupon, "_tier", _tier, '_nonce', _nonce)
    if magicCoupon not in js_nonces:
        count += 1
        print('magicCoupon="' + magicCoupon + '",')

print(f'failed {count} out of {total}')
