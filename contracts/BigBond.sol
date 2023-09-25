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
        AssetStatus status;
        uint256 pendingAmount;
        uint256 requestTime;
    }

    uint256 SIGNATURE_VALID_TIME = 3 minutes;
    uint256 LOCKING_TIME = 7 days;
    uint256 immutable SIGNATURE_SALT;
    address public admin; // The root admin of this contract
    address public rwaOperator; // The RWA operator role
    address public withdrawSigner; // The backend signer
    mapping(address => Asset) public userAssets;
    IERC20 public immutable tokenAddress;
    bytes public constant EIP191_PREFIX = "\x19Ethereum Signed Message:\n128";

    /**
     * @dev Initializes the contract with the token address and operator.
     * @param tokenAddressInput: The address of the ERC20 token contract.
     * @param rwaOperatorInput: The address of the RWA operator.
     * @param withdrawSignerInput: The address of the backend signer, signing the withdraw
        request for users.
     * @param signatureSalt: The salt used to generate the signature. Should be different
        for each contract on each chain!
     */
    constructor(
        address tokenAddressInput,
        address rwaOperatorInput,
        address withdrawSignerInput,
        uint256 signatureSalt
    ) {
        admin = _msgSender();
        tokenAddress = IERC20(tokenAddressInput);
        rwaOperator = rwaOperatorInput;
        withdrawSigner = withdrawSignerInput;
        SIGNATURE_SALT = signatureSalt;
    }

    /* ------------- Events ------------- */
    event DepositEvent(address indexed user, uint256 depositAmount);
    event RequestEvent(address indexed user, uint256 withdrawAmount);
    event ClaimEvent(address indexed user, uint256 withdrawAmount);
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
    error NotWithdrawSigner();
    error SignatureInvalid();
    error SignatureExpired();
    error ClaimTooEarly();
    error LockingTimeLessThanSignatureValidTime();

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

    modifier onlyWithdrawSigner() {
        if (_msgSender() != getSigner()) {
            revert NotWithdrawSigner();
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
        return rwaOperator;
    }

    function getSigner() public view returns (address) {
        return withdrawSigner;
    }

    function currentTotalBalance() public view returns (uint256) {
        return tokenAddress.balanceOf(address(this));
    }

    function getUserState(address user) public view returns (Asset memory) {
        return userAssets[user];
    }

    function getProductSalt() public view returns (uint256) {
        return SIGNATURE_SALT;
    }

    /**
     * @dev This function returns a digest of `the given params with the EIP-191 prefix`.
     * The operator from backend will sign this digest if the given params is valid, and the
     * signature is passed to the user. See https://eips.ethereum.org/EIPS/eip-191 to learn
     * more about EIP-191.
     */
    function calculateRequestDigest(
        address user,
        uint256 withdrawAmount,
        uint256 signingTime
    ) public view returns (bytes32) {
        bytes memory message = abi.encode(user, withdrawAmount, signingTime, SIGNATURE_SALT);
        bytes32 digest = keccak256(bytes.concat(EIP191_PREFIX, message));
        return digest;
    }

    /* ------------- Functions for users ------------- */
    /**
     * @dev Allows users to deposit assets into the contract.
     * @param depositAmount: The amount of tokens to be deposited.
     */
    function depositAsset(
        uint256 depositAmount
    ) public amountNotZero(depositAmount) whenNotPaused {
        tokenAddress.transferFrom(_msgSender(), address(this), depositAmount);
        emit DepositEvent(_msgSender(), depositAmount);
    }

    /**
     * @dev Allows users to request a withdrawal of assets.
     * @param withdrawAmount: The amount requested to withdraw. This param should be given by
     * user from frontend, and checked by the operator from the backend.
     * @param signingTime: The time when the request was signed. The user must use this signature
     * within a certain time, usually 3 minutes.
     * @param signature: The operator's signature for request validation.
     */
    function requestWithdraw(
        uint256 withdrawAmount, // Given by user from frontend
        uint256 signingTime, // Given by operator from backend
        bytes memory signature // Signed by operator
    )
        public
        stateIsNormal(_msgSender())
        amountNotZero(withdrawAmount)
        whenNotPaused
    {
        // Change the state
        Asset storage asset = userAssets[_msgSender()];
        asset.pendingAmount = withdrawAmount;
        asset.status = AssetStatus.Pending;
        asset.requestTime = block.timestamp;
        emit RequestEvent(_msgSender(), withdrawAmount);

        // Recover signature
        bytes32 digest = calculateRequestDigest(
            _msgSender(),
            withdrawAmount,
            signingTime
        );
        address expected_address = ECDSA.recover(digest, signature);

        // Check the validity of signature
        if (expected_address != getSigner()) {
            revert SignatureInvalid();
        }
        if (signingTime + SIGNATURE_VALID_TIME <= block.timestamp) {
            revert SignatureExpired();
        }
    }

    /**
     * @dev Allows users to claim their pending assets after a withdrawal request is approved.
     * The user should call this function at least a certain time after requesting, usually
     * 7 days.
     */
    function claimAsset() public stateIsPending(_msgSender()) whenNotPaused {
        // Read the state
        Asset storage asset = userAssets[_msgSender()];

        // Check the locking time
        if (asset.requestTime + LOCKING_TIME >= block.timestamp) {
            revert ClaimTooEarly();
        }

        // Transfer token
        tokenAddress.transfer(_msgSender(), asset.pendingAmount);

        // ... and everything returns to normal
        emit ClaimEvent(_msgSender(), asset.pendingAmount);
        asset.pendingAmount = 0;
        asset.status = AssetStatus.Normal;
        asset.requestTime = 0;
    }

    /* ------------- Functions for RWA operator ------------- */
    /**
     * @dev Allows the operator to borrow assets from the contract.
     */
    function borrowAssets(
        uint256 borrowAmount
    ) public onlyOperator whenNotPaused {
        tokenAddress.transfer(rwaOperator, borrowAmount);
        emit BorrowEvent(rwaOperator, borrowAmount);
    }

    /**
     * @dev Allows the operator to repay assets to the contract.
     */
    function repayAssets(
        uint256 repayAmount
    ) public onlyOperator whenNotPaused {
        tokenAddress.transferFrom(rwaOperator, address(this), repayAmount);
        emit RepayEvent(rwaOperator, repayAmount);
    }

    /* ------------- Functions for admin ------------- */
    function setAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
        emit AdminChanged(newAdmin);
    }

    function setOperator(address newOperator) public onlyAdmin {
        rwaOperator = newOperator;
        emit OperatorChanged(newOperator);
    }

    function setSignatureValidTime(uint256 newTime) public onlyAdmin {
        SIGNATURE_VALID_TIME = newTime;
    }

    function setLockingTime(uint256 newTime) public onlyAdmin {
        if (newTime < SIGNATURE_VALID_TIME) {
            revert LockingTimeLessThanSignatureValidTime();
        }
        LOCKING_TIME = newTime;
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }
}
