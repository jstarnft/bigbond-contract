// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title BigBond
 */
contract BigBond is Pausable {
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

    uint256 SIGNATURE_VALID_TIME = 3 minutes;
    uint256 LOCKING_TIME = 7 days;
    address public admin; // The root admin of this contract
    address public operator; // The RWA operator role
    mapping(address => Asset) public userAssets;
    IERC20 public immutable tokenAddress;

    /**
     * @dev Initializes the contract with the token address and operator.
     * @param tokenAddressInput: The address of the ERC20 token contract.
     * @param operatorInput: The address of the RWA operator.
     */
    constructor(address tokenAddressInput, address operatorInput) {
        admin = _msgSender();
        tokenAddress = IERC20(tokenAddressInput);
        operator = operatorInput;
    }

    /* ------------- Events ------------- */
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

    /* ------------- Errors ------------- */
    error UserStateIsNotNormal();
    error UserStateIsNotPending();
    error AmountIsZero();
    error NotOperator();
    error NotAdmin();
    error InsufficientFund();
    error SignerIsNotOperator();
    error SignatureExpired();
    error ClaimTooEarly();

    /* ------------- Modifiers ------------- */
    modifier stateIsNormal(address user) {
        if (userAssets[user].status != AssetStatus.Normal) {
            revert UserStateIsNotNormal();
        }
        _;
    }

    modifier stateIsPending(address user) {
        if (userAssets[user].status != AssetStatus.Pending) {
            revert UserStateIsNotPending();
        }
        _;
    }

    modifier amountNotZero(uint256 amount) {
        if (amount == 0) {
            revert AmountIsZero();
        }
        _;
    }

    modifier onlyOperator() {
        if (_msgSender() != getOperator()) {
            revert NotOperator();
        }
        _;
    }

    modifier onlyAdmin() {
        if (_msgSender() != getAdmin()) {
            revert NotAdmin();
        }
        _;
    }

    /* ------------- View functions ------------- */
    function getSignatureValidTime() public view returns (uint256) {
        return SIGNATURE_VALID_TIME;
    }

    function getLockingTime() public view returns (uint256) {
        return LOCKING_TIME;
    }

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

    /**
     * @dev This function returns a digest. The operator from backend will sign this digest and the signature is 
            passed to the user.
     */
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

    /* ------------- Functions for users ------------- */
    /**
     * @dev Allows users to deposit assets into the contract.
     * @param depositAmount: The amount of tokens to be deposited.
     */
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

    /**
     * @dev Allows users to request a withdrawal of assets.
     * @param withdrawPrincipal: The principal amount requested for withdrawal. This param should be given by user.
     * @param withdrawPrincipalWithInterest: The principal amount with interest. This param should be given by the 
            operator from backend.
     * @param signingTime: The time when the request was signed. The user must use this signature in a certain time, 
            usually 3 minutes.
     * @param signature: The operator's signature for request validation.
     */
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
        if (asset.totalDepositAmount < withdrawPrincipal) {
            revert InsufficientFund();
        }
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
        if (expected_address != getOperator()) {
            revert SignerIsNotOperator();
        }

        // Check the signing time
        if (signingTime + SIGNATURE_VALID_TIME <= block.timestamp) {
            revert SignatureExpired();
        }
    }

    /**
     * @dev Allows users to claim their pending assets after a withdrawal request is approved. The user should call this
            function at least a certain time after requesting, usually 7 days.
     */
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
        if (asset.requestTime + LOCKING_TIME >= block.timestamp) {
            revert ClaimTooEarly();
        }
    }

    /* ------------- Functions for operator ------------- */
    /**
     * @dev Allows the operator to borrow assets from the contract.
     */
    function borrowAssets(uint256 borrowAmount)
        public
        onlyOperator
        whenNotPaused
    {
        tokenAddress.transfer(operator, borrowAmount);
        emit BorrowEvent(operator, borrowAmount);
    }

    /**
     * @dev Allows the operator to repay assets to the contract.
     */
    function repayAssets(uint256 repayAmount)
        public
        onlyOperator
        whenNotPaused
    {
        tokenAddress.transferFrom(operator, address(this), repayAmount);
        emit RepayEvent(operator, repayAmount);
    }

    /* ------------- Functions for admin ------------- */
    function setAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
        emit AdminChanged(newAdmin);
    }

    function setOperator(address newOperator) public onlyAdmin {
        operator = newOperator;
        emit OperatorChanged(newOperator);
    }

    function setSignatureValidTime(uint256 newTime) public onlyAdmin {
        SIGNATURE_VALID_TIME = newTime;
    }

    function setLockingTime(uint256 newTime) public onlyAdmin {
        LOCKING_TIME = newTime;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }
}
