// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "remix_tests.sol"; // this import is automatically injected by Remix.
import "remix_accounts.sol"; // this import is automatically injected by Remix.
import "hardhat/console.sol";
import "../contracts/core.sol";
import "../contracts/mockTokenDeploy.sol";

contract BallotTest {

    address acc0;
    address acc1;
    address acc2;
    MockUSDC usdc = new MockUSDC();
    BigBond bigbond = new BigBond(address(usdc), acc1);

    function beforeAll () public {
        acc0 = TestsAccounts.getAccount(0); 
        acc1 = TestsAccounts.getAccount(1);
        acc2 = TestsAccounts.getAccount(2);
    }

    function logAdmin() public view {
        console.log(acc0);
    }
}