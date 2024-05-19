import os
from web3 import Web3, exceptions as w3exceptions
from thirdweb import ThirdwebSDK


ADMINS = os.environ['MC_ADMINS'].split()
TIERS = ['fan', 'player', 'playerx', 'producer', 'producerx', 'moon', 'planet']
ROLES = ['COUPON_ADMIN_ROLE', 'PRICE_ADMIN_ROLE', 'MAGIC_COUPON_ADMIN_ROLE',
         'MINTER_ADMIN_ROLE']
PRICES = {
    'fan': {
        'COMN': 30_000_000_000_000_000_000,
        'BTCC1': 45_000_000_000_000_000_000,
        'BTCC2': 60_000_000_000_000_000_000,
    },
    'player': {
        'COMN': 100_000_000_000_000_000_000,
        'BTCC1': 150_000_000_000_000_000_000,
        'BTCC2': 200_000_000_000_000_000_000,
    },
    'playerx': {
        'COMN': 200_000_000_000_000_000_000,
        'BTCC1': 300_000_000_000_000_000_000,
        'BTCC2': 400_000_000_000_000_000_000,
    },
    'producer': {
        'COMN': 1_000_000_000_000_000_000_000,
        'BTCC1': 1_500_000_000_000_000_000_000,
        'BTCC2': 2_000_000_000_000_000_000_000,
    },
    'producerx': {
        'COMN': 2_000_000_000_000_000_000_000,
        'BTCC1': 3_000_000_000_000_000_000_000,
        'BTCC2': 4_000_000_000_000_000_000_000,
    },
    'moon': {
        'COMN': 15_000_000_000_000_000_000_000,
        'BTCC1': 21_000_000_000_000_000_000_000,
        'BTCC2': 30_000_000_000_000_000_000_000,
    },
    'planet': {
        'COMN': 50_000_000_000_000_000_000_000,
        'BTCC1': 75_000_000_000_000_000_000_000,
        'BTCC2': 100_000_000_000_000_000_000_000,
    },
}

COUPON_DISCOUNT = {
    '': 15,
    'fan': 25,
    'player': 20,
    'playerx': 30,
    'producer': 40,
    'producerx': 50,
    'moon': 50,
    'planet': 50
}

sdk = ThirdwebSDK.from_private_key(os.environ['MC_ADMIN_PKEY'], 'mumbai')
contract = sdk.get_contract(os.environ['MC_CONTRACT_ADDR'])

for ROLE in ROLES:
    role_hash = Web3.soliditySha3(['string'], [ROLE])
    for ADMIN in ADMINS:
        if not contract.call("hasRole", role_hash, ADMIN):
            print(f'granting role {ROLE} to {ADMIN}')
            data = contract.call("grantRole", role_hash, ADMIN)


for _tier, _discount in COUPON_DISCOUNT.items():
    _coupon = f'PRESALE{_discount}{_tier.upper()}'
    data = contract.call("getCoupon", _coupon)
    if data[-1] != _tier or data[1] != _discount:
        print(f'adding coupon {_coupon} {data}')
        data = contract.call("addCoupon", _coupon, _discount, 25, 0, _tier)


for _tier, _curr_price in PRICES.items():
    for _curr, _price in _curr_price.items():
        _curr_addr = os.environ[f'MC_{_curr}_ADDR']
        try:
            data = contract.call("calcPrice", '', _curr_addr, _tier)
            if data != _price:
                raise w3exceptions.ContractLogicError
        except w3exceptions.ContractLogicError as e:
            print(f'adding price {_curr} {_tier}')
            data = contract.call("addPrice", _curr_addr, _tier, _price)
