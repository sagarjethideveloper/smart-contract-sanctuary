// SPDX-License-Identifier: BSD-3-Clause
pragma solidity >=0.7.0 <0.9.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./StringLibrary.sol";

contract HelloWorld is Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    using Address for address;
    
    address public governance;
    address public validator;
    address public beneficiary;
    address public rewardToken;
    address[] public validators;
    uint256 public chainId;
    uint256 public depositFee;
    uint256 public withdrawFee;
    uint256 public listingFee;
    uint256 public lastTokenIndex;
    uint256 private constant MAX_PLATFORM_FEE = 10000;
    uint256 private constant MAX_VALIDATOR_COUNT = 10;
    uint256 public validatorApprovalrequired;
    bool public isBridgePaused;
    mapping (address => bool) public isValidator;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
    
    struct TrustedToken {
        uint256 _index;
        address _homeERC20;
        address _foreignERC20;
        address _listedBy;
        uint256 _listedBlock;
        uint256 _suspendedBlock;
        uint8 _isActive; // 0-Suspended, 1-Active
    }
    mapping (address => TrustedToken) public trustedTokens;
    address[] TrustedTokens;
    
    struct DepositWallet {
        uint256 _index;
        uint256 _amount;
        uint256 _chainId;
        address _user;
        address _homeERC20;
        address _foreignERC20;
        uint256 _depositedBlock;
        uint256 _depositedTimeStamp;
    }
    mapping (address => DepositWallet) public depositWallets;
    address[] DepositWallets;
    
    struct WithdrawalWallet {
        uint256 _index;
        uint256 _amount;
        uint256 _chainId;
        address _user;
        address _withdrawERC20;
        address _depositedERC20;
        bytes32 _depositeTxHash;
        bool _withdrawlStatus;
    }
    WithdrawalWallet[] withdrawalWallet;
    mapping (address => WithdrawalWallet) public withdrawalWallets;
    address[] WithdrawalWallets;
    bytes32[] public DepositeTxHashs;
    
    mapping (uint256 => bool) public claimedWithdrawalsByOtherChainDepositId; // Deposit index of Foreign chain => Withdrawal in current chain
    uint256 public lastDepositIndex; // Deposit index for current chain

    event Deposited(address indexed account, uint256 amount, address homeERC20, address foreignERC20,uint256 chainId, uint256 blocknumber, uint256 timestamp, uint256 id);
    event Withdrawal(address indexed account, uint256 amount, address withdrawERC20, address depositedERC20, uint256 id, uint256 chainId);
    event TrustedTokenAdded(address indexed account, address homeERC20, address foreignERC20, address listedBy, uint256 blocknumber, uint256 blockTimestamp, uint256 tokenIndex);
    event ListingFeeUpdated(uint256 oldListingFee, uint256 newListingFee);
    event DepositFeeUpdated(uint256 oldDepositFee, uint256 newDepositFee);
    event WithdrawFeeUpdated(uint256 oldWithdrawFee, uint256 newWithdrawFee);
    event BeneficiaryUpdated(address oldBeneficiary, address newBeneficiary);
    event ValidatorAdded(address newValidator);
    event ValidatorRemoved(address removedValidator);
    event ValidatorRequirementChange(uint256 noOfValidatorRequired);
    
    constructor(address _governance, address[] memory _validators, uint _noOfValidators, address _beneficiary, uint256 _depositFee, uint256 _withdrawFee, uint256 _listingFee, address _rewardToken) {
        governance = _governance;
        setValidators(_validators, _noOfValidators);
        beneficiary = _beneficiary;
        chainId = block.chainid;
        depositFee = _depositFee;
        withdrawFee = _withdrawFee;
        listingFee = _listingFee;
        isBridgePaused = false;
        rewardToken = _rewardToken;
    }
    
    modifier validVadlidatorRequirement(uint _validatorCount, uint _approvalRequired) {
        require(_validatorCount <= MAX_VALIDATOR_COUNT
            && _approvalRequired <= _validatorCount
            && _approvalRequired != 0
            && _validatorCount != 0);
        _;
    }

    modifier validatorExists(address _validator) {
        require(isValidator[_validator]);
        _;
    }

    modifier validatorDoesNotExist(address _newValidator) {
        require(!isValidator[_newValidator]);
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0));
        _;
    }
    
    modifier noContractsAllowed() {
        require(!(address(msg.sender).isContract()) && tx.origin == msg.sender, "Access Denied:: Contracts are not allowed!");
        _;
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "Unauthorized Access");
        _;
    }
    
    function createBridgePair(address _homeERC20, address _foreignERC20) external noContractsAllowed nonReentrant payable {
        require(isBridgePaused == false, "AddTrustedToken:: Bridge Paused, Can't add new token");
        require(trustedTokens[_homeERC20]._listedBlock == 0, "AddTrustedToken:: _erc20Token already listed as TrustedToken");
        require(trustedTokens[_homeERC20]._suspendedBlock == 0, "AddTrustedToken:: _erc20Token is suspended");
        if(listingFee > 0) {
            require(msg.value == listingFee, "AddTrustedToken:: Incorrect msg.value");
            payable(beneficiary).transfer(listingFee);
        }
        lastTokenIndex = lastTokenIndex.add(1);
        updateToken(lastTokenIndex, _homeERC20, _foreignERC20);
        emit TrustedTokenAdded(msg.sender, _homeERC20, _foreignERC20, msg.sender, block.number, block.timestamp, lastTokenIndex);
    }

    function depositToBridge(address _homeERC20, uint256 _amount) external noContractsAllowed nonReentrant {
        require(isBridgePaused == false, "DepositToBridge:: Bridge Paused, Can't Deposit");
        require(trustedTokens[_homeERC20]._isActive == 1, "DepositToBridge:: _homeERC20 not listed as TrustedToken");
        require(trustedTokens[_homeERC20]._suspendedBlock == 0, "DepositToBridge:: _homeERC20 is suspended");
        require(_amount > 0, "DepositToBridge:: Tokens can't be Zero");
        require(IERC20(_homeERC20).balanceOf(msg.sender) >= _amount, "DepositToBridge:: Insufficient Balance");
        depositTokensAndPlatformFee(_homeERC20, _amount);
        lastDepositIndex = lastDepositIndex.add(1);
        updateDeposit(lastDepositIndex, _amount, chainId, _homeERC20, trustedTokens[_homeERC20]._foreignERC20, block.number, block.timestamp);
        emit Deposited(msg.sender, _amount, _homeERC20, trustedTokens[_homeERC20]._foreignERC20, chainId, block.number, block.timestamp, lastDepositIndex);
    }
    
    function withdrawfromBridge(uint256 _amount, address _withdrawERC20, address _depositedERC20, uint256 _chainId, uint256 _nonce, bytes32 _txHash, Sig[] memory signatures, address[] memory _validatedBy) external noContractsAllowed nonReentrant {
        require(isBridgePaused == false, "WithdrawfromBridge:: Bridge Paused, Can't Withdrawn");
        require(trustedTokens[_withdrawERC20]._isActive == 1, "WithdrawfromBridge:: _trustedERC20Token not listed as TrustedToken");
        require(trustedTokens[_withdrawERC20]._suspendedBlock == 0, "WithdrawfromBridge:: _trustedERC20Token is suspended");
        require(trustedTokens[_withdrawERC20]._foreignERC20 == _depositedERC20, "WithdrawfromBridge:: Incorrect Pair");
        require(_amount > 0, "WithdrawfromBridge:: Tokens can't be Zero");
        require(chainId == _chainId, "WithdrawfromBridge:: Invalid chainId!");
        require(!claimedWithdrawalsByOtherChainDepositId[_nonce], "WithdrawfromBridge:: Already Withdrawn!");
        require(_validatedBy.length == signatures.length, "WithdrawfromBridge:: Invalid Length of Validators");
        require(checkDuplicateValidators(_validatedBy) == 1, "WithdrawfromBridge:: Duplicate Validators Found");
        require(approvalCountForTrade(_amount, _withdrawERC20, _depositedERC20, _chainId, _nonce, _txHash, signatures, _validatedBy) >= validatorApprovalrequired, "WithdrawfromBridge:: Not validated by required validators ");
        withdrawTokensAndPlatformFee(_withdrawERC20, _amount);
        claimedWithdrawalsByOtherChainDepositId[_nonce] = true;
        emit Withdrawal(msg.sender, _amount, _withdrawERC20, _depositedERC20, _nonce, chainId);
    }

    function approvalCountForTrade(uint256 _amount, address _withdrawERC20, address _depositedERC20, uint256 _chainId, uint256 _nonce, bytes32 _txHash, Sig[] memory signatures, address[] memory _validatedBy) internal returns (uint256) {
        uint256 noOfApprovals = 0;
        for(uint256 i=0; i< signatures.length; i++) {
            (noOfApprovals, validator) = isValidTrade(_amount, _withdrawERC20, _depositedERC20, _chainId, _nonce, _txHash, signatures[i], _validatedBy[i]);
            noOfApprovals.add(noOfApprovals);
        }
        return noOfApprovals;
    }

    function depositTokensAndPlatformFee(address _homeERC20, uint256 _amount) internal {
        uint256 platformFee = _amount.mul(depositFee).div(MAX_PLATFORM_FEE);
        if(depositFee > 0) {
            IERC20(_homeERC20).safeTransferFrom(msg.sender, beneficiary, platformFee);
        }
        if(rewardToken != address(0) && IERC20(rewardToken).balanceOf(address(this)) >= platformFee) {
            IERC20(rewardToken).safeTransfer(msg.sender, platformFee);
        }
        IERC20(_homeERC20).safeTransferFrom(msg.sender, address(this), _amount.sub(platformFee));
    }

    function withdrawTokensAndPlatformFee(address _withdrawERC20, uint256 _amount) internal {
        uint256 platformFee = _amount.mul(withdrawFee).div(MAX_PLATFORM_FEE);
        if(withdrawFee > 0) {
            IERC20(_withdrawERC20).safeTransfer(beneficiary, platformFee);
        }
        if(rewardToken != address(0) && IERC20(rewardToken).balanceOf(address(this)) >= platformFee) {
            IERC20(rewardToken).safeTransfer(msg.sender, platformFee);
        }
        IERC20(_withdrawERC20).safeTransfer(msg.sender, _amount.sub(platformFee));
    }

    function updateToken(uint256 _index, address _homeERC20, address _foreignERC20) internal {
        trustedTokens[_homeERC20]._index = _index;
        trustedTokens[_homeERC20]._homeERC20 = _homeERC20;
        trustedTokens[_homeERC20]._foreignERC20 = _foreignERC20;
        trustedTokens[_homeERC20]._listedBy = msg.sender;
        trustedTokens[_homeERC20]._listedBlock = block.number;
        trustedTokens[_homeERC20]._suspendedBlock = 0;
        trustedTokens[_homeERC20]._isActive = 1;
        TrustedTokens.push(_homeERC20);
    }

    function updateDeposit(uint256 _index, uint256 _amount, uint256 _chainId, address _homeERC20, address _foreignERC20, uint256 _depositedBlock, uint256 _depositedTimeStamp) internal {
        depositWallets[msg.sender]._index = _index;
        depositWallets[msg.sender]._amount = _amount;
        depositWallets[msg.sender]._chainId = _chainId;
        depositWallets[msg.sender]._user = msg.sender;
        depositWallets[msg.sender]._homeERC20 = _homeERC20;
        depositWallets[msg.sender]._foreignERC20 = _foreignERC20;
        depositWallets[msg.sender]._depositedBlock = _depositedBlock;
        depositWallets[msg.sender]._depositedTimeStamp = _depositedTimeStamp;
        DepositWallets.push(msg.sender);
    }

    function updateWithdraw(uint256 _nonce, uint256 _amount, uint256 _chainId, address _withdrawERC20, address _depositedERC20, bytes32 _txHash) internal {
        withdrawalWallets[msg.sender]._index = _nonce;
        withdrawalWallets[msg.sender]._amount = _amount;
        withdrawalWallets[msg.sender]._chainId = _chainId;
        withdrawalWallets[msg.sender]._user = msg.sender;
        withdrawalWallets[msg.sender]._withdrawERC20 = _withdrawERC20;
        withdrawalWallets[msg.sender]._depositedERC20 = _depositedERC20;
        withdrawalWallets[msg.sender]._depositeTxHash = _txHash;
        withdrawalWallets[msg.sender]._withdrawlStatus = true;
        WithdrawalWallets.push(msg.sender);
        DepositeTxHashs.push(_txHash);
    }

    function checkDuplicateValidators(address[] memory signedBy) internal pure returns (uint8) {
        bool result;
        for(uint8 i = 0; i <= signedBy.length; i++) {
            for(uint8 j = 0; j <= signedBy.length; j++) {
                if(i != j) {
                    if(signedBy[i] == signedBy[j]){
                        result = true;
                    }
                }
            }
        }
        if(result == true){
            return 0;
        } else {
            return 1;
        }
    }

    function isValidTrade(uint256 _amount, address _withdraERC20, address _depositedERC20, uint256 _chainId, uint256 _nonce, bytes32 _txHash, Sig memory signature, address _validator) internal view returns (uint8, address) {
	    address validatedBy = StringLibrary.getAddress(abi.encodePacked(msg.sender, _amount, _withdraERC20, _depositedERC20, _chainId, _nonce, _txHash, address(this)), signature.v, signature.r, signature.s);
        if(isValidator[validatedBy] == true && validatedBy == _validator ) return (1, validatedBy);
        else return (0, address(0));
	}
    
    function suspendToken(address _erc20Token) external onlyGovernance {
        trustedTokens[_erc20Token]._isActive = 0;
        trustedTokens[_erc20Token]._suspendedBlock = block.number;
    }

    function activeSuspendToken(address _erc20Token) external onlyGovernance {
        trustedTokens[_erc20Token]._isActive = 1;
        trustedTokens[_erc20Token]._suspendedBlock = 0;
    }
    
    function updateListingFee(uint256 _newListingFee) external onlyGovernance {
        require(listingFee != _newListingFee, "UpdateListingFee:: New Listing Fee can not be same as Listing Fee");
        listingFee = _newListingFee;
        emit ListingFeeUpdated(listingFee, _newListingFee);
    }
    
    function updateDepositFee(uint256 _newDepositFee) external onlyGovernance {
        require(_newDepositFee <= MAX_PLATFORM_FEE, "UpdateWithdrawFee:: Invalid withdraw fee ");
        require(depositFee != _newDepositFee, "UpdateDepositFee:: New Deposit Fee can not be same as Old Deposit Fee");
        depositFee = _newDepositFee;
        emit DepositFeeUpdated(depositFee, _newDepositFee);
    }
    
    function updateWithdrawFee(uint256 _newWithdrawFee) external onlyGovernance{
        require(_newWithdrawFee <= MAX_PLATFORM_FEE, "UpdateWithdrawFee:: Invalid withdraw fee ");
        require(withdrawFee != _newWithdrawFee, "UpdateWithdrawFee:: New Withdraw Fee can not be same as Old Withdraw Fee");
        withdrawFee = _newWithdrawFee;
        emit WithdrawFeeUpdated(depositFee, _newWithdrawFee);
    }
    
    function updateBeneficiary(address _newBeneficiary) external onlyGovernance {
        require(_newBeneficiary != address(0), "UpdateBeneficiary:: New Beneficiary can not be Zero Address");
        beneficiary = _newBeneficiary;
        emit BeneficiaryUpdated(beneficiary, _newBeneficiary);
    }
    
    function updateValidator(address _newValidator) external onlyGovernance {
        require(_newValidator != address(0), "UpdateValidator:: New Validator can not be Zero Address");
        validator = _newValidator;
    }
    
    function pauseBridge() external onlyGovernance {
        require(isBridgePaused == false, "PauseBridge:: Bridge is already Paused");
        isBridgePaused = true;
    }
    
    function unPauseBridge() external onlyGovernance {
        require(isBridgePaused == true, "UnPauseBridge:: Bridge is already Unpaused");
        isBridgePaused = false;
    }

    function updateRewardToken() external onlyGovernance {
        require(rewardToken != address(0), "UpdateRewardToken:: Renounce Reward Token");
        rewardToken = address(0);
    }

    function setValidators(address[] memory _validators, uint _approvalRequired) internal validVadlidatorRequirement(_validators.length, _approvalRequired) {
        for (uint i=0; i<_validators.length; i++) {
            require(!isValidator[_validators[i]] && _validators[i] != address(0));
            isValidator[_validators[i]] = true;
        }
        validators = _validators;
        validatorApprovalrequired = _approvalRequired;
    }

    function addValidator(address _validator) external onlyGovernance validatorDoesNotExist(_validator) notNull(_validator) validVadlidatorRequirement(validators.length + 1, validatorApprovalrequired) {
        isValidator[_validator] = true;
        validators.push(_validator);
        emit ValidatorAdded(_validator);
    }

    function removeValidator(address _validator) external onlyGovernance validatorExists(_validator) {
        isValidator[_validator] = false;
        for (uint i=0; i<validators.length - 1; i++) {
            if (validators[i] == _validator) {
                delete validators[i];
                break;
            }
        }
        if (validatorApprovalrequired > validators.length) {
            changeValidatorRequirement(validators.length);
        }
        emit ValidatorRemoved(_validator);
    }

    function replaceValidator(address _oldValidator, address _newValidator) external onlyGovernance validatorExists(_oldValidator) validatorDoesNotExist(_newValidator) {
        for (uint i=0; i<validators.length; i++) {
            if (validators[i] == _oldValidator) {
                validators[i] = _newValidator;
                break;
            }
        }
        isValidator[_oldValidator] = false;
        isValidator[_newValidator] = true;
        emit ValidatorRemoved(_oldValidator);
        emit ValidatorAdded(_newValidator);
    }

    function changeValidatorRequirement(uint _validatorApprovalrequired) internal validVadlidatorRequirement(validators.length, _validatorApprovalrequired) {
        validatorApprovalrequired = _validatorApprovalrequired;
        emit ValidatorRequirementChange(_validatorApprovalrequired);
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/utils/Strings.sol";

library StringLibrary {
    using Strings for uint256;

    function append(string memory _a, string memory _b) internal pure returns (string memory) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory bab = new bytes(_ba.length + _bb.length);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) bab[k++] = _ba[i];
        for (uint i = 0; i < _bb.length; i++) bab[k++] = _bb[i];
        return string(bab);
    }

    function append(string memory _a, string memory _b, string memory _c) internal pure returns (string memory) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _bc = bytes(_c);
        bytes memory bbb = new bytes(_ba.length + _bb.length + _bc.length);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) bbb[k++] = _ba[i];
        for (uint i = 0; i < _bb.length; i++) bbb[k++] = _bb[i];
        for (uint i = 0; i < _bc.length; i++) bbb[k++] = _bc[i];
        return string(bbb);
    }

    function recover(string memory message, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes memory msgBytes = bytes(message);
        bytes memory fullMessage = concat(
            bytes("\x19Ethereum Signed Message:\n"),
            bytes(msgBytes.length.toString()),
            msgBytes,
            new bytes(0), new bytes(0), new bytes(0), new bytes(0)
        );
        return ecrecover(keccak256(fullMessage), v, r, s);
    }

    function concat(bytes memory _ba, bytes memory _bb, bytes memory _bc, bytes memory _bd, bytes memory _be, bytes memory _bf, bytes memory _bg) internal pure returns (bytes memory) {
        bytes memory resultBytes = new bytes(_ba.length + _bb.length + _bc.length + _bd.length + _be.length + _bf.length + _bg.length);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) resultBytes[k++] = _ba[i];
        for (uint i = 0; i < _bb.length; i++) resultBytes[k++] = _bb[i];
        for (uint i = 0; i < _bc.length; i++) resultBytes[k++] = _bc[i];
        for (uint i = 0; i < _bd.length; i++) resultBytes[k++] = _bd[i];
        for (uint i = 0; i < _be.length; i++) resultBytes[k++] = _be[i];
        for (uint i = 0; i < _bf.length; i++) resultBytes[k++] = _bf[i];
        for (uint i = 0; i < _bg.length; i++) resultBytes[k++] = _bg[i];
        return resultBytes;
    }

    function getAddress(bytes memory generatedBytes, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes memory msgBytes = generatedBytes;
        bytes memory fullMessage = concat(
            bytes("\x19Ethereum Signed Message:\n"),
            bytes(msgBytes.length.toString()),
            msgBytes,
            new bytes(0), new bytes(0), new bytes(0), new bytes(0)
        );
        return ecrecover(keccak256(fullMessage), v, r, s);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant alphabet = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = alphabet[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

