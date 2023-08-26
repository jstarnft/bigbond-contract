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

    MockUSDC.transfer(operator.address, 500_000_000)
    MockUSDC.transfer(user1.address, 30_000_000)
    MockUSDC.transfer(user2.address, 30_000_000)

    return { BigBond, MockUSDC, admin, operator, user1, user2 }
  }

  it("should be deployed successfully", async () => {
    const { BigBond, admin, operator } = await loadFixture(deployBeforeAll)

    expect(await BigBond.getAdmin()).to.equal(admin.address)
    expect(await BigBond.getOperator()).to.equal(operator.address)
    expect(await BigBond.paused()).to.be.false
  })

});