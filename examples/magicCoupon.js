const {soliditySha3, hexToBytes} = require('web3-utils');
const {sign} = require('web3-eth-accounts');


function magicCoupon(claimerAddr, adminPk, tier, nonce)
{
    const hash = soliditySha3(claimerAddr, tier + nonce);
    const sig = sign(hash, adminPk);
    const sigc = hexToBytes(sig.signature);
    return nonce + Buffer.from(sigc).toString('base64');
}
module.exports['magicCoupon'] = magicCoupon;

