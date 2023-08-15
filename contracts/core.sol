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
        uint256 lastRequestTimestamp;
    }

    uint256 constant RATIFY_TIME_LIMIT = 7 days;
    address public admin; // The root admin of this contract
    address public operator; // The RWA operator role
    uint256 public operatorDebt; // The amount of token that the operator needs to repay
    mapping(address => Asset) public userAssets;
    IERC20 public immutable tokenAddress;

    constructor(address tokenAddressInput, address operatorInput) {
        admin = _msgSender();
        tokenAddress = IERC20(tokenAddressInput);
        operator = operatorInput;
    }

    /// Events for state transitions
    event DepositEvent(address indexed user, uint256 amount);
    event RequestEvent(address indexed user, uint256 amount);
    event ClaimEvent(address indexed user, uint256 amount);
    event RatifyNormalEvent(address indexed user, uint256 amount);
    event RatifyExpiredEvent(
        address indexed user,
        uint256 amount,
        uint256 extraTime
    );
    event borrowEvent(address indexed operator, uint256 amount);
    event repayEvent(address indexed operator, uint256 amount);

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

    function currentBalance() public view returns (uint256) {
        return tokenAddress.balanceOf(address(this));
    }

    /// Functions for users
    function depositAsset(uint256 amount) public amountNotZero(amount) {
        // Transfer token
        tokenAddress.transferFrom(_msgSender(), address(this), amount);

        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        asset.depositAmount += amount;
        emit DepositEvent(_msgSender(), amount);
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
        asset.lastRequestTimestamp = block.timestamp;
        emit RequestEvent(_msgSender(), amount);
    }

    function claim() public stateIsClaimable(_msgSender()) {
        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        uint256 claimableAmount = asset.claimableAmount;
        asset.claimableAmount = 0;
        asset.status = AssetStatus.Normal;

        // Transfer token
        tokenAddress.transfer(_msgSender(), claimableAmount);
        emit ClaimEvent(_msgSender(), claimableAmount);
    }

    /// Functions for operator
    function ratifyWithin7days(address user, uint256 claimableAmount)
        public
        stateIsPending(user)
        onlyOperator
    {
        Asset storage asset = userAssets[user];
        require(
            block.timestamp <= asset.lastRequestTimestamp + RATIFY_TIME_LIMIT,
            "Ratification time expired. Please call `ratifyExpired`."
        );
        asset.claimableAmount = claimableAmount; // Need to test this.
        asset.pendingAmount = 0;
        asset.status = AssetStatus.Claimable;
        emit RatifyNormalEvent(user, claimableAmount);
    }

    function ratifyExpire(address user, uint256 claimableAmount)
        public
        stateIsPending(user)
        onlyOperator
    {
        Asset storage asset = userAssets[user];
        require(
            block.timestamp > asset.lastRequestTimestamp + RATIFY_TIME_LIMIT,
            "Ratification time isn't expired. Please call `ratifyWithin7days`."
        );
        asset.claimableAmount = claimableAmount;
        asset.pendingAmount = 0;
        asset.status = AssetStatus.Claimable;
        uint256 extraTime = block.timestamp -
            asset.lastRequestTimestamp -
            RATIFY_TIME_LIMIT;
        emit RatifyExpiredEvent(user, claimableAmount, extraTime);
    }

    function borrowAssets(uint256 borrowAmount) public onlyOperator {
        tokenAddress.transfer(operator, borrowAmount);
        operatorDebt += borrowAmount;
        emit borrowEvent(operator, borrowAmount);
    }

    function repayAssets(uint256 repayAmount) public onlyOperator {
        require(
            repayAmount <= operatorDebt,
            "The repay amount should less than the debt!"
        );
        tokenAddress.transferFrom(operator, address(this), repayAmount);
        operatorDebt -= repayAmount;
        emit repayEvent(operator, repayAmount);
    }
}
