import { ethers } from "hardhat"
import { expect } from "chai"

describe("Mock USDC contract", function () {
  it("Deployment should assign the total supply of tokens to the owner", async function () {
    const [owner] = await ethers.getSigners();
    const MockUSDC = await ethers.deployContract("MockUSDC");
    const ownerBalance = await MockUSDC.balanceOf(owner.address);
    expect(await MockUSDC.totalSupply()).to.equal(ownerBalance);
  });

  it("Checks the transfer function", async function () {
    const [owner, alice, bob] = await ethers.getSigners();

    const MockUSDCFactory = await ethers.getContractFactory("MockUSDC")
    const MockUSDC = await MockUSDCFactory.deploy()
    await MockUSDC.transfer(alice.address, 150);

    await expect(MockUSDC.connect(alice).transfer(bob.address, 200)).to.be.revertedWith("ERC20: transfer amount exceeds balance")

    expect(await MockUSDC.balanceOf(alice.address)).to.equal(150);
    expect(await MockUSDC.balanceOf(bob.address)).to.equal(0);
  })

  // We don't need to write too much tests for token cause it's already checked by @OpenZeppelin.
});