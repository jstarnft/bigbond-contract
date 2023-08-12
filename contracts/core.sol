// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BigBond is Ownable {
    event OwnershipRenouncedWarning(string);

    function renounceOwnership() public override onlyOwner {
        emit OwnershipRenouncedWarning("You shouldn't renounce the ownership.");
    }

    
}