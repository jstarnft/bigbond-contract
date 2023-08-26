import { ethers } from "hardhat"
import { expect } from "chai"

describe("BigBond contract", function () {
  it("should be deployed successfully", async () => {
    const [owner] = await ethers.getSigners();
    const MockUSDC = await ethers.deployContract("MockUSDC")

    const BigBondFactory = await ethers.getContractFactory("BigBond");
    const BigBond = await BigBondFactory.deploy(MockUSDC.target, owner.address);
  })


  //   it("Deployment should assign the total supply of tokens to the owner", async function () {
  //     const [owner] = await ethers.getSigners();
  //     const mockUSDC = await ethers.deployContract("MockUSDC");
  //     const ownerBalance = await mockUSDC.balanceOf(owner.address);
  //     expect(await mockUSDC.totalSupply()).to.equal(ownerBalance);
  //   });

  //   it("Checks the transfer function", async function () {
  //     const [owner, alice, bob] = await ethers.getSigners();
  //     const mockUSDC = await ethers.deployContract("MockUSDC");
  //     await mockUSDC.transfer(alice.address, 150);

  //     try {
  //       await mockUSDC.connect(alice).transfer(bob.address, 200);
  //       assert.fail("Should have thrown an error");
  //     } catch (error) {
  //       expect(error.message).to.contain("ERC20: transfer amount exceeds balance");
  //     }

  //     expect(await mockUSDC.balanceOf(alice.address)).to.equal(150);
  //     expect(await mockUSDC.balanceOf(bob.address)).to.equal(0);
  //   })
});