// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "remix_tests.sol"; // this import is automatically injected by Remix.
import "remix_accounts.sol"; // this import is automatically injected by Remix.
import "hardhat/console.sol";
import "../contracts/core.sol";
import "../contracts/mockTokenDeploy.sol";

contract CoreTest {
    address acc0;
    address acc1;
    address acc2;
    MockUSDC usdc = new MockUSDC();
    BigBond bigbond = new BigBond(address(usdc), acc1);

    function beforeAll() public {
        acc0 = TestsAccounts.getAccount(0); // admin
        acc1 = TestsAccounts.getAccount(1); // operator
        acc2 = TestsAccounts.getAccount(2); // user
    }

    /// #sender: account-1
    function logAdmin() public {
        console.log(acc1);
        console.log(msg.sender);
        Assert.equal(msg.sender, acc1, "Not the sender!");
    }

    /// Update owner first time
    /// This method will be called by default account(account-0) as there is no custom sender defined
    function updateOwnerOnce() public {
        // check method caller is as expected
        Assert.ok(
            msg.sender == acc0,
            "caller should be default account i.e. acc0"
        );
    }

    /// Update owner again by defining custom sender
    /// #sender: account-1 (sender is account at index '1')
    function updateOwnerOnceAgain() public {
        // check if caller is custom and is as expected
        Assert.ok(
            msg.sender == acc1,
            "caller should be custom account i.e. acc1"
        );
    }

    function testCalculateDigest() public {
        uint256 withdrawPrincipal = 50;
        uint256 withdrawPrincipalWithInterest = 50;
        uint256 signingTime = 1692279017; // 0x64de20e9
        Assert.equal(
            bigbond.calculateDigestForRequest(
                withdrawPrincipal,
                withdrawPrincipalWithInterest,
                signingTime
            ),
            bytes32(
                0xf65f161f5bd6c8dd71636b37cbf282408031e6bd3c440c71f684ea3f6f647222
                /// Hash of 0x \
                /// 0000000000000000000000000000000000000000000000000000000000000032 \
                /// 0000000000000000000000000000000000000000000000000000000000000032 \
                /// 0000000000000000000000000000000000000000000000000000000064de20e9 \
            ),
            "Hash value not correct!"
        );
    }
}
