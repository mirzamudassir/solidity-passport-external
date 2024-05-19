const web3 = require ('web3');
const crypto = require('node:crypto');
const fs = require('node:fs');
const {magicCoupon} = require('./magicCoupon');

data = []

const _claimerAddr = process.env.MC_CLAIMER_ADDR;
const _magicCouponAdminPrivKey = process.env.MC_ADMIN_PKEY;
let _nonces = [];
for (let _nonce_code of process.env.MC_NONCE_CODES.split(" ")) {
    const _nonce = crypto.createHash('md5').update(_nonce_code).digest("hex");
	// console.log('"'+ _nonce + '",');
	data.push(_nonce);
    _nonces.push(_nonce);
}
for (let _nonce of _nonces) {
	for (let _tier of process.env.MC_TIERS.split(" ")) {
		const _magicCoupon = magicCoupon(_claimerAddr, _magicCouponAdminPrivKey, _tier, _nonce);
		// console.log('_claimerAddr', _claimerAddr, '_magicCoupon', _magicCoupon, "_tier", _tier, '_nonce', _nonce);
		// console.log('"'+ _magicCoupon + '",');
		data.push(_magicCoupon);
	}
}

fs.writeFileSync('nonces_coupons.json', JSON.stringify(data, null, 4));
