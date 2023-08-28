import { ethers } from "hardhat";
import { Signer } from "ethers";

export function hexstringToUint8Array(hexstring: string): Uint8Array {
  if (hexstring.startsWith('0x')) {
    hexstring = hexstring.slice(2);
  }
  const uint8Array = new Uint8Array(hexstring.length / 2);
  for (let i = 0; i < uint8Array.length; i++) {
    uint8Array[i] = parseInt(hexstring.slice(i * 2, i * 2 + 2), 16);
  }
  return uint8Array;
}

// This is the function for the backend operator to sign the withdraw request from user.
export async function signWithdrawRequest(user: string, withdrawAmount: number, signingTime: number, signer: Signer) {
  const message = hexstringToUint8Array(
    '000000000000000000000000' + ethers.solidityPacked(
      ["address", "uint", "uint"], [user, withdrawAmount, signingTime]
    ).slice(2)
  )
  const signature = await signer.signMessage(message)
  return { message, signature }
}
