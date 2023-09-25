import { ethers } from "hardhat"
import { signWithdrawRequest } from "./utils";
import { time } from "@nomicfoundation/hardhat-network-helpers";
const SIGNATURE_SALT = 10001;

async function main() {
  const [deployer, operator, user] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const token = await ethers.deployContract("MockUSDC");
  console.log("Contract address:", await token.getAddress());

  const { signature, message } = await signWithdrawRequest(SIGNATURE_SALT, user.address, 10, await time.latest(), operator)
  console.log("Signing message: ", message)
  console.log("Signature: ", signature)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });