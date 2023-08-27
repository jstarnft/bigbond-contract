import { MockUSDC, BigBond } from "../typechain-types"
import { ethers } from "hardhat"
import { expect } from "chai"
import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { Signer, hexlify } from "ethers";

describe("BigBond contract", function () {


  function hexstringToUint8Array(hexstring: string): Uint8Array {
    if (hexstring.startsWith('0x')) {
      hexstring = hexstring.slice(2);
    }
    const uint8Array = new Uint8Array(hexstring.length / 2);
    for (let i = 0; i < uint8Array.length; i++) {
      uint8Array[i] = parseInt(hexstring.slice(i * 2, i * 2 + 2), 16);
    }
    return uint8Array;
  }


  async function signWithdrawRequest(user: string, withdrawAmount: number, signingTime: number, signer: Signer) {
    const message = hexstringToUint8Array(
      '000000000000000000000000' + ethers.solidityPacked(
        ["address", "uint", "uint"], [user, withdrawAmount, signingTime]
      ).slice(2)
    )
    const signature = await signer.signMessage(message)
    return { message, signature }
  }


  async function deployBeforeAll() {
    const [admin, operator, user1, user2] = await ethers.getSigners();
    const mockUSDC = await ethers.deployContract("MockUSDC")

    const BigBondFactory = await ethers.getContractFactory("BigBond");
    const bigbond = await BigBondFactory.deploy(mockUSDC.target, operator.address);

    await mockUSDC.transfer(operator.address, 500_000_000)
    await mockUSDC.transfer(user1.address, 30_000_000)
    await mockUSDC.transfer(user2.address, 30_000_000)

    return { bigbond, mockUSDC, admin, operator, user1, user2 }
  }


  it("should be deployed successfully", async () => {
    const { bigbond, admin, operator } = await loadFixture(deployBeforeAll)
    expect(await bigbond.getAdmin()).to.equal(admin.address)
    expect(await bigbond.getOperator()).to.equal(operator.address)
    expect(await bigbond.paused()).to.be.false
  })


  it("should allow users to deposit assets", async () => {
    const { bigbond, mockUSDC, user1 } = await loadFixture(deployBeforeAll);
    const depositAmount = 10_000_000;
    await expect(bigbond.connect(user1).depositAsset(depositAmount))
      .to.be.revertedWith("ERC20: insufficient allowance")

    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);

    const userAsset = await bigbond.getUserState(user1.address);
    expect(userAsset.status).to.equal(0); // AssetStatus.Normal
    expect(userAsset.pendingAmount).to.equal(0);
    expect(userAsset.requestTime).to.equal(0);

    const contractBalance = await bigbond.currentTotalBalance();
    expect(contractBalance).to.equal(depositAmount);
  });


  it("should sign and recover correctly", async () => {
    const { bigbond, operator, user1 } = await loadFixture(deployBeforeAll)
    const withdrawAmount = 20_000_000
    const signingTime = 1693139094

    const { message, signature } = await signWithdrawRequest(
      user1.address, withdrawAmount, signingTime, operator
    )
    const eip191_digest = await bigbond.calculateRequestDigest(
      user1.address, withdrawAmount, signingTime
    )
    const recover_address_1 = ethers.verifyMessage(message, signature)
    const recover_address_2 = ethers.recoverAddress(eip191_digest, signature)
    expect(operator.address).to.equal(recover_address_1).to.equal(recover_address_2)
  })


  it("should allow users to request a withdrawal", async () => {
    const { bigbond, mockUSDC, operator, user1 } = await loadFixture(deployBeforeAll);

    // Deposit first
    const depositAmount = 10_000_000;
    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);

    // Ask the operator to sign
    const withdrawAmount = 5_000_000;
    const signingTime = await time.latest();
    const { signature: operatorSignature } = await signWithdrawRequest(
      user1.address, withdrawAmount, signingTime, operator
    )

    // Request-withdraw: normal case
    await time.increase(60)
    await bigbond.connect(user1).requestWithdraw(withdrawAmount, signingTime, operatorSignature)

    // Assertion
    const userAsset = await bigbond.getUserState(user1.address);
    expect(userAsset.status).to.equal(1); // AssetStatus.Pending
    expect(userAsset.pendingAmount).to.equal(withdrawAmount);
  });


  it("should failed because the requesting is invalid (in 4 cases)", async () => {
    // Same as above
    const { bigbond, mockUSDC, operator, user1, user2: hacker } = await loadFixture(deployBeforeAll);
    const depositAmount = 10_000_000;
    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);
    const withdrawAmount = 5_000_000;
    const signingTime = await time.latest();
    const { signature: operatorSignature } = await signWithdrawRequest(
      user1.address, withdrawAmount, signingTime, operator
    )

    // Wrong param for the signature
    await expect(
      bigbond.connect(user1).requestWithdraw(withdrawAmount + 1, signingTime, operatorSignature)
    ).to.be.revertedWithCustomError(bigbond, "SignatureInvalid")

    // A malicious hacker wants to use the signature which is prepared for the normal user
    await expect(
      bigbond.connect(hacker).requestWithdraw(withdrawAmount, signingTime, operatorSignature)
    ).to.be.revertedWithCustomError(bigbond, "SignatureInvalid")

    // The signature is expired
    await time.increase(185)  // more than 3 minutes
    await expect(
      bigbond.connect(user1).requestWithdraw(withdrawAmount, signingTime, operatorSignature)
    ).to.be.revertedWithCustomError(bigbond, "SignatureExpired")

    // Sign again because the signautre has already expired
    const signingTimeUpdate = await time.latest();
    const { signature: operatorSignatureUpdate } = await signWithdrawRequest(
      user1.address, withdrawAmount, signingTimeUpdate, operator
    )
    await bigbond.connect(user1).requestWithdraw(
      withdrawAmount, signingTimeUpdate, operatorSignatureUpdate
    ) // should pass

    // ... The user want to use the same signature again!
    await expect(
      bigbond.connect(user1).requestWithdraw(
        withdrawAmount, signingTimeUpdate, operatorSignatureUpdate
      )
    ).to.be.revertedWithCustomError(bigbond, "UserStateIsNotNormal")
  })





  // it("should allow users to claim pending assets after the locking time", async () => {
  //   const { BigBond, MockUSDC, operator, user1 } = await loadFixture(deployBeforeAll);

  //   const withdrawAmount = 5_000_000;
  //   const signingTime = await time.latest();
  //   const digest = await BigBond.calculateDigestForRequest(withdrawAmount, signingTime);
  //   const signature = await operator.signMessage(ethers.utils.arrayify(digest));

  //   await BigBond.connect(user1).requestWithdraw(withdrawAmount, signingTime, signature);

  //   // Fast-forward time to after the locking time
  //   await time.increase(7 * 24 * 60 * 60); // 7 days

  //   await BigBond.connect(user1).claimAsset();

  //   const userAsset = await BigBond.getUserState(user1.address);
  //   expect(userAsset.status).to.equal(0); // AssetStatus.Normal
  //   expect(userAsset.pendingAmount).to.equal(0);
  //   expect(userAsset.requestTime).to.equal(0);

  //   const userBalance = await MockUSDC.balanceOf(user1.address);
  //   expect(userBalance).to.equal(withdrawAmount);
  // });

});