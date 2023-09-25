import { ethers } from "hardhat"
import { expect } from "chai"
import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { Signer } from "ethers";

const SIGNATURE_SALT = 10001;

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


  async function signWithdrawRequest(salt: number, user: string, withdrawAmount: number, signingTime: number, signer: Signer) {
    const message = hexstringToUint8Array(
      '000000000000000000000000' + ethers.solidityPacked(
        ["address", "uint", "uint", "uint"], [user, withdrawAmount, signingTime, salt]
      ).slice(2)
    )
    const signature = await signer.signMessage(message)
    return { message, signature }
  }


  async function deployBeforeAll() {
    const [admin, operator, withdrawSigner, user1, user2] = await ethers.getSigners();
    const mockUSDC = await ethers.deployContract("MockUSDC")

    const BigBondFactory = await ethers.getContractFactory("BigBond");
    const bigbond = await BigBondFactory.deploy(mockUSDC.target, operator.address, withdrawSigner.address, SIGNATURE_SALT);

    await mockUSDC.transfer(operator.address, 500_000_000)
    await mockUSDC.transfer(user1.address, 30_000_000)
    await mockUSDC.transfer(user2.address, 30_000_000)

    return { bigbond, mockUSDC, admin, operator, user1, user2, withdrawSigner }
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
    const { bigbond, user1, withdrawSigner } = await loadFixture(deployBeforeAll)
    const withdrawAmount = 20_000_000
    const signingTime = 1693139094

    const { message, signature } = await signWithdrawRequest(
      SIGNATURE_SALT, user1.address, withdrawAmount, signingTime, withdrawSigner
    )
    const eip191_digest = await bigbond.calculateRequestDigest(
      user1.address, withdrawAmount, signingTime
    )
    const recover_address_1 = ethers.verifyMessage(message, signature)
    const recover_address_2 = ethers.recoverAddress(eip191_digest, signature)

    expect(withdrawSigner.address).to.equal(recover_address_1).to.equal(recover_address_2)
  })


  it("should allow users to request a withdrawal", async () => {
    const { bigbond, mockUSDC, user1, withdrawSigner } = await loadFixture(deployBeforeAll);

    // Deposit first
    const depositAmount = 10_000_000;
    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);

    // Ask the operator to sign
    const withdrawAmount = 5_000_000;
    const signingTime = await time.latest();
    const { signature: operatorSignature } = await signWithdrawRequest(
      SIGNATURE_SALT, user1.address, withdrawAmount, signingTime, withdrawSigner
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
    const { bigbond, mockUSDC, user1, user2: hacker, withdrawSigner } = await loadFixture(deployBeforeAll);
    const depositAmount = 10_000_000;
    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);
    const withdrawAmount = 5_000_000;
    const signingTime = await time.latest();
    const { signature: operatorSignature } = await signWithdrawRequest(
      SIGNATURE_SALT, user1.address, withdrawAmount, signingTime, withdrawSigner
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
      SIGNATURE_SALT, user1.address, withdrawAmount, signingTimeUpdate, withdrawSigner
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


  it("should allow users to claim pending assets after the locking time", async () => {
    // Same as above
    const { bigbond, mockUSDC, user1, withdrawSigner } = await loadFixture(deployBeforeAll);
    const depositAmount = 10_000_000;
    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);
    const withdrawAmount = 5_000_000;
    const signingTime = await time.latest();
    const { signature: operatorSignature } = await signWithdrawRequest(
      SIGNATURE_SALT, user1.address, withdrawAmount, signingTime, withdrawSigner
    )

    // Request successfully
    await bigbond.connect(user1).requestWithdraw(withdrawAmount, signingTime, operatorSignature)
    const userBalanceOrigin = await mockUSDC.balanceOf(user1.address);

    // If claiming too early...
    await time.increase(6 * 24 * 60 * 60); // 6 days
    await expect(
      bigbond.connect(user1).claimAsset()
    ).to.be.revertedWithCustomError(bigbond, "ClaimTooEarly");

    // After 7 days
    await time.increase(1 * 24 * 60 * 60); // ... another 1 day
    await bigbond.connect(user1).claimAsset();

    // Assertion
    const userAsset = await bigbond.getUserState(user1.address);
    expect(userAsset.status).to.equal(0); // AssetStatus.Normal
    expect(userAsset.pendingAmount).to.equal(0);
    expect(userAsset.requestTime).to.equal(0);

    const userBalance = await mockUSDC.balanceOf(user1.address);
    expect(userBalance - userBalanceOrigin).to.equal(withdrawAmount);
  });


  it("should borrow and repay successfully by the operator", async () => {
    const { bigbond, mockUSDC, operator, user1, user2: hacker } = await loadFixture(deployBeforeAll);
    const depositAmount = 10_000_000;
    await mockUSDC.connect(user1).approve(bigbond.target, depositAmount);
    await bigbond.connect(user1).depositAsset(depositAmount);
    const operatorBalanceOrigin = await mockUSDC.balanceOf(operator.address)

    const borrowAmount = 8_000_000;
    await expect(
      bigbond.connect(hacker).borrowAssets(borrowAmount)
    ).to.be.revertedWithCustomError(bigbond, "NotOperator")

    await bigbond.connect(operator).borrowAssets(borrowAmount)
    expect(await mockUSDC.balanceOf(operator.address) - operatorBalanceOrigin)
      .to.equal(borrowAmount)

    const repayAmount = 9_000_000;
    await mockUSDC.connect(operator).approve(bigbond.target, repayAmount);
    await bigbond.connect(operator).repayAssets(repayAmount)
    expect(await mockUSDC.balanceOf(operator.address) - operatorBalanceOrigin)
      .to.equal(borrowAmount - repayAmount)
  })

});