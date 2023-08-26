import { MockUSDC, BigBond } from "../typechain-types"
import { ethers } from "hardhat"
import { expect } from "chai"
import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("BigBond contract", function () {

  async function deployBeforeAll() {
    const [admin, operator, user1, user2] = await ethers.getSigners();
    const MockUSDC = await ethers.deployContract("MockUSDC")

    const BigBondFactory = await ethers.getContractFactory("BigBond");
    const BigBond = await BigBondFactory.deploy(MockUSDC.target, operator.address);

    await MockUSDC.transfer(operator.address, 500_000_000)
    await MockUSDC.transfer(user1.address, 30_000_000)
    await MockUSDC.transfer(user2.address, 30_000_000)

    return { BigBond, MockUSDC, admin, operator, user1, user2 }
  }


  // function signWithdrawRequest(withdrawAmount: num)


  it("should be deployed successfully", async () => {
    const { BigBond, admin, operator } = await loadFixture(deployBeforeAll)
    expect(await BigBond.getAdmin()).to.equal(admin.address)
    expect(await BigBond.getOperator()).to.equal(operator.address)
    expect(await BigBond.paused()).to.be.false
  })


  it("should allow users to deposit assets", async () => {
    const { BigBond, MockUSDC, user1 } = await loadFixture(deployBeforeAll);
    const depositAmount = 10_000_000;
    await expect(BigBond.connect(user1).depositAsset(depositAmount))
      .to.be.revertedWith("ERC20: insufficient allowance")

    await MockUSDC.connect(user1).approve(BigBond.target, depositAmount);
    await BigBond.connect(user1).depositAsset(depositAmount);

    const userAsset = await BigBond.getUserState(user1.address);
    expect(userAsset.status).to.equal(0); // AssetStatus.Normal
    expect(userAsset.pendingAmount).to.equal(0);
    expect(userAsset.requestTime).to.equal(0);

    const contractBalance = await BigBond.currentTotalBalance();
    expect(contractBalance).to.equal(depositAmount);
  });

  
  // it("should allow users to request a withdrawal", async () => {
  //   const { BigBond, operator, user1 } = await loadFixture(deployBeforeAll);

  //   const withdrawAmount = 5_000_000;
  //   const signingTime = Math.floor(Date.now() / 1000);
  //   const digest = await BigBond.calculateDigestForRequest(withdrawAmount, signingTime);
  //   const signature = await operator.signMessage(ethers.utils.arrayify(digest));

  //   await BigBond.connect(user1).requestWithdraw(withdrawAmount, signingTime, signature);

  //   const userAsset = await BigBond.getUserState(user1.address);
  //   expect(userAsset.status).to.equal(1); // AssetStatus.Pending
  //   expect(userAsset.pendingAmount).to.equal(withdrawAmount);
  //   expect(userAsset.requestTime).to.equal(signingTime);
  // });

  // it("should allow users to claim pending assets after the locking time", async () => {
  //   const { BigBond, MockUSDC, operator, user1 } = await loadFixture(deployBeforeAll);

  //   const withdrawAmount = 5_000_000;
  //   const signingTime = Math.floor(Date.now() / 1000);
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