// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract BigBond is Ownable, Pausable {
    /// Structs and state variables
    enum AssetStatus {
        Normal,
        Pending
    }

    struct Asset {
        uint256 totalDepositAmount;
        uint256 pendingAmount;
        AssetStatus status;
        uint256 requestTime;
    }

    uint256 constant SIGNATURE_VALID_TIME = 3 minutes;
    uint256 constant LOCKING_TIME = 7 days;
    address public admin; // The root admin of this contract
    address public operator; // The RWA operator role
    mapping(address => Asset) public userAssets;
    IERC20 public immutable tokenAddress;

    constructor(address tokenAddressInput, address operatorInput) {
        admin = _msgSender();
        tokenAddress = IERC20(tokenAddressInput);
        operator = operatorInput;
    }

    /// Events for state transitions
    event DepositEvent(address indexed user, uint256 depositAmount);
    event RequestEvent(
        address indexed user,
        uint256 withdrawPrincipal,
        uint256 withdrawPrincipalWithInterest
    );
    event ClaimEvent(address indexed user, uint256 pendingAmount);
    event BorrowEvent(address indexed operator, uint256 borrowAmount);
    event RepayEvent(address indexed operator, uint256 repayAmount);
    event AdminChanged(address newAdmin);
    event OperatorChanged(address newOperator);

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

    modifier onlyAdmin() {
        require(
            _msgSender() == getAdmin(),
            "Only the admin can call this function!"
        );
        _;
    }

    /// View functions
    function getAdmin() public view returns (address) {
        return admin;
    }

    function getOperator() public view returns (address) {
        return operator;
    }

    function currentBalance() public view returns (uint256) {
        return tokenAddress.balanceOf(address(this));
    }

    function getUserState(address user) public view returns (Asset memory) {
        return userAssets[user];
    }

    function calculateDigestForRequest(
        uint256 withdrawPrincipal,
        uint256 withdrawPrincipalWithInterest,
        uint256 signingTime
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    withdrawPrincipal,
                    withdrawPrincipalWithInterest,
                    signingTime
                )
            );
    }

    /// Functions for users
    function depositAsset(uint256 depositAmount)
        public
        amountNotZero(depositAmount)
        whenNotPaused
    {
        // Transfer token
        tokenAddress.transferFrom(_msgSender(), address(this), depositAmount);

        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        asset.totalDepositAmount += depositAmount;
        emit DepositEvent(_msgSender(), depositAmount);
    }

    function requestWithdraw(
        uint256 withdrawPrincipal, // Given by user from frontend
        uint256 withdrawPrincipalWithInterest, // Given by operator from backend
        uint256 signingTime, // Given by operator from backend
        bytes memory signature // Signed by operator
    )
        public
        stateIsNormal(_msgSender())
        amountNotZero(withdrawPrincipal)
        whenNotPaused
    {
        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        require(
            asset.totalDepositAmount >= withdrawPrincipal,
            "Insufficient funds"
        );
        asset.totalDepositAmount -= withdrawPrincipal;
        asset.pendingAmount += withdrawPrincipalWithInterest;
        asset.status = AssetStatus.Pending;
        asset.requestTime = block.timestamp;
        emit RequestEvent(
            _msgSender(),
            withdrawPrincipal,
            withdrawPrincipalWithInterest
        );

        // Check the signature
        bytes32 digest = calculateDigestForRequest(
            withdrawPrincipal,
            withdrawPrincipalWithInterest,
            signingTime
        );
        address expected_address = ECDSA.recover(digest, signature);
        require(
            expected_address == getOperator(),
            "The signer is not the operator!"
        );

        // Check the signing time
        require(
            signingTime + SIGNATURE_VALID_TIME > block.timestamp,
            "The signature is expired!"
        );
    }

    function claimAsset() public stateIsPending(_msgSender()) whenNotPaused {
        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        uint256 pendingAmount = asset.pendingAmount;
        asset.pendingAmount = 0;
        asset.status = AssetStatus.Normal;

        // Transfer token
        tokenAddress.transfer(_msgSender(), pendingAmount);
        emit ClaimEvent(_msgSender(), pendingAmount);

        // Check the locking time
        require(
            asset.requestTime + LOCKING_TIME < block.timestamp,
            "You can only claim the assets 7 days after request!"
        );
    }

    /// Functions for operator
    function borrowAssets(uint256 borrowAmount)
        public
        onlyOperator
        whenNotPaused
    {
        tokenAddress.transfer(operator, borrowAmount);
        emit BorrowEvent(operator, borrowAmount);
    }

    function repayAssets(uint256 repayAmount)
        public
        onlyOperator
        whenNotPaused
    {
        tokenAddress.transferFrom(operator, address(this), repayAmount);
        emit RepayEvent(operator, repayAmount);
    }

    /// Functions for Admin
    function setAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
        emit AdminChanged(newAdmin);
    }

    function setOperator(address newOperator) public onlyAdmin {
        operator = newOperator;
        emit OperatorChanged(newOperator);
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }
}
