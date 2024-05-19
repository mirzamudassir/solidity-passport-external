const web3 = require ('web3');
const { ThirdwebSDK } = require('@thirdweb-dev/sdk/evm');
const sdk = new ThirdwebSDK('mumbai');
const crypto = require('node:crypto');
const {magicCoupon} = require('./magicCoupon');


// const _nonce = process.env.MC_NONCE; // Stripe checkout confirmation code
const _claimerAddr = process.env.MC_CLAIMER_ADDR;
const _tier = process.env.MC_TIERS.split(" ")[0];
const _magicCouponAdminPrivKey = process.env.MC_ADMIN_PKEY;
const _magicCouponAdminAddr = process.env.MC_ADMIN_ADDR;
const _magicCouponRole = web3.utils.soliditySha3('MAGIC_COUPON_ADMIN_ROLE');
const _contractAddr = process.env.MC_CONTRACT_ADDR;
console.log('_magicCouponRole', _magicCouponRole);
let _nonce;
if (process.env.MC_NONCE_CODE)
    _nonce = crypto.createHash('md5').update(process.env.MC_NONCE_CODE).digest("hex");
else
    _nonce = process.env.MC_NONCES.split(" ")[0];

if (process.env.TEST) {
    const _magicCoupon = magicCoupon(_claimerAddr, _magicCouponAdminPrivKey, _tier, _nonce);
    console.log('_claimerAddr', _claimerAddr, '_magicCoupon', _magicCoupon, "_tier", _tier, '_nonce', _nonce);
} else {
    sdk.getContract(_contractAddr).then(async contract => {
        const data = await contract.call('hasRole', [_magicCouponRole, _magicCouponAdminAddr])
        if (data) {
            // const _claimerAddr = await sdk.wallet.getAddress();
            const _magicCoupon = magicCoupon(_claimerAddr, _magicCouponAdminPrivKey, _tier, _nonce);
            console.log('_claimerAddr', _claimerAddr, '_magicCoupon', _magicCoupon);
            // const price = await contract.call("calcPrice", [_magicCoupon, '0x0000000000000000000000000000000000000000', _tier]);
            // console.log(price);
        } else {
            console.warning('the specified account doesn\'t has the role required to perform this action');
        }
    });
}
// console.log(web3.eth.accounts.create())
