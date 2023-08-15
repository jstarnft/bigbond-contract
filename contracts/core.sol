// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract BigBond is Ownable, Pausable {
    /// Structs and state variables
    enum AssetStatus {
        Normal,
        Pending,
        Claimable
    }

    struct Asset {
        uint256 depositAmount;
        uint256 pendingAmount;
        uint256 claimableAmount;
        AssetStatus status;
        uint256 requestTimestamp;
    }

    address public admin;       // The root admin of this contract
    address public operator;    // The RWA operator role
    uint256 constant RATIFY_TIME_LIMIT = 7 days;
    mapping(address => Asset) public userAssets;
    IERC20 public immutable tokenAddress;

    constructor(address tokenAddressInput, address operatorInput) {
        admin = _msgSender();
        tokenAddress = IERC20(tokenAddressInput);
        operator = operatorInput;
    }

    /// Events for state transitions
    event DepositEvent(address indexed user, uint256 amount, uint256 timestamp);
    event RequestEvent(address indexed user, uint256 amount, uint256 timestamp);
    event ClaimEvent(address indexed user, uint256 amount, uint256 timestamp);
    event RatifyNormalEvent(address indexed user, uint256 amount, uint256 timestamp);
    event RatifyExpiredEvent(address indexed user, uint256 amount, uint256 timestamp, uint256 extraTime);

    /// Modifiers for the state machine
    modifier stateIsNormal(address user) {
        require(
            userAssets[user].status == AssetStatus.Normal,
            "The state of user needs to be 'Normal' in this function."
        );
        _;
    }

    modifier stateIsPending(address user) {
        require(
            userAssets[user].status == AssetStatus.Pending,
            "The state of user needs to be 'Pending' in this function."
        );
        _;
    }

    modifier stateIsClaimable(address user) {
        require(
            userAssets[user].status == AssetStatus.Claimable,
            "The state of user needs to be 'Claimable' in this function."
        );
        _;
    }

    modifier amountNotZero(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0!");
        _;
    }

    modifier onlyOperator() {
        require(
            _msgSender() == getOperator(),
            "Only the operator can call this function!"
        );
        _;
    }

    /// View functions
    function getOperator() public view returns (address) {
        return operator;
    }

    /// Functions for users
    function depositAsset(uint256 amount) public amountNotZero(amount) {
        // Transfer token
        tokenAddress.transferFrom(_msgSender(), address(this), amount);

        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        asset.depositAmount += amount;
        emit DepositEvent(_msgSender(), amount, block.timestamp);
    }

    function requestWithdraw(uint256 amount)
        public
        stateIsNormal(_msgSender())
        amountNotZero(amount)
    {
        Asset storage asset = userAssets[_msgSender()];
        require(asset.depositAmount >= amount, "Insufficient funds");
        asset.depositAmount -= amount;
        asset.pendingAmount += amount;
        asset.status = AssetStatus.Pending;
        asset.requestTimestamp = block.timestamp;
        emit RequestEvent(_msgSender(), amount, block.timestamp);
    }

    function claim() public stateIsClaimable(_msgSender()) {
        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        uint256 claimableAmount = asset.claimableAmount;
        asset.claimableAmount = 0;
        asset.status = AssetStatus.Normal;

        // Transfer token
        tokenAddress.transfer(_msgSender(), claimableAmount);
        emit ClaimEvent(_msgSender(), claimableAmount, block.timestamp);
    }

    /// Functions for operator
    function ratifyWithin7days(address user, uint256 claimableAmount) public stateIsPending(user) {
        Asset storage asset = userAssets[user];
        require(
            block.timestamp <= asset.requestTimestamp + RATIFY_TIME_LIMIT, 
            "Ratification time expired. Please call `ratifyExpired`."
        );
        asset.claimableAmount = claimableAmount;    // Need to test this.
        asset.pendingAmount = 0;
        asset.status = AssetStatus.Claimable;
        emit RatifyNormalEvent(user, claimableAmount, block.timestamp);
    }

    function ratifyExpire(address user, uint256 claimableAmount) public stateIsPending(user) {
        Asset storage asset = userAssets[user];
        require(
            block.timestamp > asset.requestTimestamp + RATIFY_TIME_LIMIT, 
            "Ratification time isn't expired. Please call `ratifyWithin7days`."
        );
        asset.claimableAmount = claimableAmount;
        asset.pendingAmount = 0;
        asset.status = AssetStatus.Claimable;
        uint256 extraTime = block.timestamp - asset.requestTimestamp - RATIFY_TIME_LIMIT;
        emit RatifyExpiredEvent(user, claimableAmount, block.timestamp, extraTime);
    }

}
