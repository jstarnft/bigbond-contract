require('dotenv').config()
const ethers = require('ethers');

function hexstringToUint8Array(hexstring) {
  if (hexstring.startsWith('0x')) {
    hexstring = hexstring.slice(2);
  }
  const uint8Array = new Uint8Array(hexstring.length / 2);
  for (let i = 0; i < uint8Array.length; i++) {
    uint8Array[i] = parseInt(hexstring.slice(i * 2, i * 2 + 2), 16);
  }
  return uint8Array;
}

async function signWithdrawRequest(salt, user, withdrawAmount, signingTime, signer) {
  const rawMessage = ethers.solidityPacked(
    ["address", "uint", "uint", "uint"],
    [user, withdrawAmount, signingTime, salt]
  ).slice(2)
  const message = hexstringToUint8Array(
    '000000000000000000000000' + rawMessage
  )
  const signature = await signer.signMessage(message)
  return { rawMessage, signature }
}

(async function () {
  const privateKey = process.env.TEST_PRIVATE_KEY
  const salt = process.env.SALT_SIGNATURE
  const wallet = new ethers.Wallet(privateKey);
  console.log('Operator Address:', wallet.address)

  const nowTime = parseInt(Date.now() / 1000)
  console.log('UTC Time now:', nowTime)

  const withdrawAmount = '70000000000000000'
  const user = '0xb54e978a34Af50228a3564662dB6005E9fB04f5a'

  const { rawMessage, signature } = await signWithdrawRequest(salt, user, withdrawAmount, nowTime, wallet)
  console.log('Raw message:', rawMessage)
  console.log('Signature:', signature)
})()