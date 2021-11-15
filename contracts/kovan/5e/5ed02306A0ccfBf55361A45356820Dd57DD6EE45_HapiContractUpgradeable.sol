// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HapiContractUpgradeable is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // Contract configuration `rewardERC20TokenAddress`, used for paying reporter rewards
    address private _rewardERC20TokenAddress;
    // Contract configuration `gasPrice`, used for calculating reporter rewards
    uint256 private _gasPrice;
    // Contract configuration `averageReportGas`, used for calculating reporter rewards
    uint256 private _averageReportGas;

    // Reporter type structure
    struct ReporterType {
        string name;
        uint32 rewardFactor;
        bool privileged;
    }
    // Reporter type ID tracker
    uint32 private _reporterTypeIdTracker;
    // Mapping from reporter type ID to type information
    mapping(uint32 => ReporterType) private _reporterTypes;

    // Reporter structure
    struct Reporter {
        string name;
        address account;
        uint32 rate;
        uint32 reporterTypeId;
        uint256 balance;
    }
    // Reporter ID tracker
    uint32 private _reporterIdTracker;
    // Mapping from reporter ID to reporter information
    mapping(uint32 => Reporter) private _reporters;
    // Mapping from reporter address to reporter ID
    mapping(address => uint32) private _reporterIds;

    // Case structure
    struct Case {
        string name;
        uint32 category;
        uint32 timestamp;
    }
    // Case ID tracker
    uint32 private _caseIdTracker;
    // Mapping from case ID to case information
    mapping(uint32 => Case) private _cases;

    // Address structure
    struct AddressInfo {
        uint8 rank;
        uint32 category;
        uint32 caseId;
    }
    // Mapping from address to address information
    mapping(address => AddressInfo) private _addresses;
    uint8 private constant _MAX_RANK = 10;

    /**
     * @dev Emitted when configuration `gasPrice` updated.
     */
    event UpdateGasPrice(uint256 gasPrice);
    /**
     * @dev Emitted when configuration `averageReportGas` updated.
     */
    event UpdateAverageReportGas(uint256 averageReportGas);

    /**
     * @dev Emitted when reporter type created.
     */
    event ReporterTypeCreated(uint32 reporterTypeId, string name, uint32 rewardFactor, bool privileged);
    /**
     * @dev Emitted when reporter type updated.
     */
    event ReporterTypeUpdated(uint32 reporterTypeId, string name, uint32 rewardFactor, bool privileged);

    /**
     * @dev Emitted when reporter created.
     */
    event ReporterCreated(uint32 reporterId, string name, address account, uint32 rate, uint32 reporterTypeId);
    /**
     * @dev Emitted when reporter updated.
     */
    event ReporterUpdated(uint32 reporterId, string name, address account, uint32 rate, uint32 reporterTypeId);

    /**
     * @dev Emitted when case reported.
     */
    event CaseReported(uint32 caseId, uint32 category, uint32 reporterId);
    /**
     * @dev Emitted when case updated.
     */
    event CaseUpdated(uint32 caseId, uint32 category);

    /**
     * @dev Emitted when address reported.
     */
    event AddressReported(address indexed account, uint8 rank, uint32 category, uint32 caseId, uint32 reporterId);
    /**
     * @dev Emitted when address updated.
     */
    event AddressUpdated(address indexed account, uint8 rank, uint32 category, uint32 reporterId);

    /**
     * @dev Initializes the contract by setting configuration `rewardERC20TokenAddress`, `gasPrice` and `averageReportGas`.
     *
     * Requirements:
     * - `rewardERC20TokenAddress` cannot be the zero address,
     * - `rewardERC20TokenAddress` must be ERC20 contract address.
     */
    function initialize(address rewardERC20TokenAddress_, uint256 gasPrice_, uint256 averageReportGas_) initializer public {
        __Ownable_init();

        require(rewardERC20TokenAddress_ != address(0), "HapiContract: Invalid reward erc20 token address");

        _rewardERC20TokenAddress = rewardERC20TokenAddress_;
        _gasPrice = gasPrice_;
        _averageReportGas = averageReportGas_;
    }

    /**
     * @dev Throws if called by any account other than the active reporter. Active reporter has a nonzero reporterTypeId.
     */
    modifier onlyReporter() {
        require(_reporters[_reporterIds[_msgSender()]].reporterTypeId != 0, "HapiContract: caller is not active reporter");
        _;
    }

    /**
     * @dev Returns contract configuration.
     */
    function getConfiguration()
        external
        view
        returns (
            uint256 gasPrice,
            uint256 averageReportGas,
            address rewardERC20TokenAddress,
            uint256 rewardERC20TokenBalance
        )
    {
        return (
            _gasPrice,
            _averageReportGas,
            _rewardERC20TokenAddress,
            IERC20(_rewardERC20TokenAddress).balanceOf(address(this))
        );
    }

    /**
     * @dev Returns current reporter type count.
     */
    function getReporterTypeCount() external view returns (uint32) {
        return _reporterTypeIdTracker;
    }

    /**
     * @dev Returns reporter type information for `reporterTypeId`.
     */
    function getReporterType(uint32 reporterTypeId_)
        external
        view
        returns (
            string memory name,
            uint32 rewardFactor,
            bool privileged
        )
    {
        ReporterType storage reporterType = _reporterTypes[reporterTypeId_];
        return (
            reporterType.name,
            reporterType.rewardFactor,
            reporterType.privileged
        );
    }

    /**
     * @dev Returns current reporter count.
     */
    function getReporterCount() external view returns (uint32) {
        return _reporterIdTracker;
    }

    /**
     * @dev Returns reporter ID for address `account`.
     */
    function getReporterId(address account_) external view returns (uint32) {
        return _reporterIds[account_];
    }

    /**
     * @dev Returns reporter information for `reporterId`.
     */
    function getReporter(uint32 reporterId_)
        external
        view
        returns (
            string memory name,
            address account,
            uint32 rate,
            uint32 reporterTypeId,
            uint256 balance
        )
    {
        Reporter storage reporter = _reporters[reporterId_];
        return (
            reporter.name,
            reporter.account,
            reporter.rate,
            reporter.reporterTypeId,
            reporter.balance
        );
    }

    /**
     * @dev Returns current case count.
     */
    function getCaseCount() external view returns (uint32) {
        return _caseIdTracker;
    }

    /**
     * @dev Returns case information for `caseId`.
     */
    function getCase(uint32 caseId_)
        external
        view
        returns (
            string memory name,
            uint32 category,
            uint32 timestamp
        )
    {
        Case storage _case = _cases[caseId_];
        return (
            _case.name,
            _case.category,
            _case.timestamp
        );
    }

    /**
     * @dev Returns address information for `account`.
     */
    function checkAddress(address account_)
        external
        view
        returns (
            uint8 rank,
            uint32 category,
            uint32 caseId
        )
    {
        AddressInfo storage account = _addresses[account_];
        return (
            account.rank,
            account.category,
            account.caseId
        );
    }

    /**
     * @dev Updates configuration `gasPrice`.
     *
     * Requirements:
     * - must be called by active reporter account.
     * - gasPrice must not match the current value
     */
    function updateGasPrice(uint256 gasPrice_) public onlyReporter {
        uint32 reporterTypeId = _reporters[_reporterIds[_msgSender()]].reporterTypeId;
        require(_reporterTypes[reporterTypeId].privileged, "HapiContract: Reporter has not permissions");
        require(_gasPrice != gasPrice_, "HapiContract: Invalid gasPrice");

        _gasPrice = gasPrice_;

        emit UpdateGasPrice(gasPrice_);
    }

    /**
     * @dev Updates configuration `averageReportGas`.
     *
     * Requirements:
     * - must be called by owner account.
     * - averageReportGas must not match the current value
     */
    function updateAverageReportGas(uint256 averageReportGas_) public onlyOwner {
        require(_averageReportGas != averageReportGas_, "HapiContract: Invalid averageReportGas");

        _averageReportGas = averageReportGas_;

        emit UpdateAverageReportGas(averageReportGas_);
    }

    /**
     * @dev Add new reporter type.
     *
     * Requirements:
     * - must be called by owner account,
     * - `name` must not be an empty string.
     */
    function addReporterType(string memory name_, uint32 rewardFactor_, bool privileged_) external onlyOwner {
        require(bytes(name_).length != 0, "HapiContract: Invalid name");

        _reporterTypeIdTracker += 1;
        ReporterType storage reporterType = _reporterTypes[_reporterTypeIdTracker];
        reporterType.name = name_;
        reporterType.rewardFactor = rewardFactor_;
        reporterType.privileged = privileged_;

        emit ReporterTypeCreated(_reporterTypeIdTracker, name_, rewardFactor_, privileged_);
    }

    /**
     * @dev Update reporter type for `reporterTypeId`.
     *
     * Requirements:
     * - must be called by owner account,
     * - `reporterTypeId` must exist,
     * - `name` must not be an empty string.
     */
    function updateReporterType(uint32 reporterTypeId_, string memory name_, uint32 rewardFactor_, bool privileged_) external onlyOwner {
        require(reporterTypeId_ > 0 && reporterTypeId_ <= _reporterTypeIdTracker, "HapiContract: ReporterTypeId not exist");
        require(bytes(name_).length != 0, "HapiContract: Invalid name");

        ReporterType storage reporterType = _reporterTypes[reporterTypeId_];
        require(keccak256(bytes(reporterType.name)) != keccak256(bytes(name_)) || reporterType.rewardFactor != rewardFactor_ || reporterType.privileged != privileged_, "HapiContract: Invalid params");
        reporterType.name = name_;
        reporterType.rewardFactor = rewardFactor_;
        reporterType.privileged = privileged_;

        emit ReporterTypeUpdated(reporterTypeId_, name_, rewardFactor_, privileged_);
    }

    /**
     * @dev Add new reporter.
     *
     * Requirements:
     * - must be called by owner account,
     * - `name` must not be an empty string,
     * - `account` cannot be the zero address,
     * - reporter with address `account` must not exist,
     * - `reporterTypeId` must exist.
     */
    function addReporter(string memory name_, address account_, uint32 rate_, uint32 reporterTypeId_) external onlyOwner {
        require(bytes(name_).length != 0, "HapiContract: Invalid name");
        require(account_ != address(0), "HapiContract: Invalid account");
        require(_reporterIds[account_] == 0, "HapiContract: Reporter with current account already exists");
        require(reporterTypeId_ <= _reporterTypeIdTracker, "HapiContract: ReporterTypeId not exist");

        _reporterIdTracker += 1;
        Reporter storage reporter = _reporters[_reporterIdTracker];
        reporter.name = name_;
        reporter.account = account_;
        reporter.rate = rate_;
        reporter.reporterTypeId = reporterTypeId_;
        _reporterIds[account_] = _reporterIdTracker;

        emit ReporterCreated(_reporterIdTracker, name_, account_, rate_, reporterTypeId_);
    }

    /**
     * @dev Update reporter for `reporterId`.
     *
     * Requirements:
     * - must be called by owner account,
     * - `reporterId` must exist,
     * - `name` must not be an empty string,
     * - `reporterTypeId` must exist.
     */
    function updateReporter(uint32 reporterId_, string memory name_, uint32 rate_, uint32 reporterTypeId_) external onlyOwner {
        require(reporterId_ > 0 && reporterId_ <= _reporterIdTracker, "HapiContract: ReporterId not exist");
        require(bytes(name_).length != 0, "HapiContract: Invalid name");
        require(reporterTypeId_ <= _reporterTypeIdTracker, "HapiContract: ReporterTypeId not exist");

        Reporter storage reporter = _reporters[reporterId_];
        require(keccak256(bytes(reporter.name)) != keccak256(bytes(name_)) || reporter.rate != rate_ || reporter.reporterTypeId != reporterTypeId_, "HapiContract: Invalid params");
        reporter.name = name_;
        reporter.rate = rate_;
        reporter.reporterTypeId = reporterTypeId_;

        emit ReporterUpdated(reporterId_, name_, _reporters[reporterId_].account, rate_, reporterTypeId_);
    }

    /**
     * @dev Report new case.
     *
     * Requirements:
     * - must be called by active reporter account,
     * - `name` must not be an empty string.
     */
    function reportCase(string memory name_, uint32 category_, uint32 timestamp_) external onlyReporter {
        require(bytes(name_).length != 0, "HapiContract: Invalid name");

        _caseIdTracker += 1;
        Case storage _case = _cases[_caseIdTracker];
        _case.name = name_;
        _case.category = category_;
        _case.timestamp = timestamp_;

        emit CaseReported(_caseIdTracker, category_, _reporterIds[_msgSender()]);
    }

    /**
     * @dev Update case for `caseId`.
     *
     * Requirements:
     * - must be called by owner account,
     * - `caseId` must exist,
     * - `name` must not be an empty string.
     */
    function updateCase(uint32 caseId_, string memory name_, uint32 category_) external onlyOwner {
        require(caseId_ > 0 && caseId_ <= _caseIdTracker, "HapiContract: CaseId not exist");
        require(bytes(name_).length != 0, "HapiContract: Invalid name");

        Case storage _case = _cases[caseId_];
        require(keccak256(bytes(_case.name)) != keccak256(bytes(name_)) || _case.category != category_, "HapiContract: Invalid params");
        _case.name = name_;
        _case.category = category_;

        emit CaseUpdated(caseId_, category_);
    }

    /**
     * @dev Report address (increases the balance of the reporter).
     *
     * Requirements:
     * - must be called by active reporter account,
     * - `account` cannot be the zero address,
     * - `rank` must be between 1 and MAX_RANK,
     * - `rank` for an existing `account` must be greater than the current value,
     * - `caseId` must exist.
     */
    function reportAddress(address account_, uint8 rank_, uint32 category_, uint32 caseId_) external onlyReporter nonReentrant {
        require(account_ != address(0), "HapiContract: Invalid account");
        require(rank_ > 0 && rank_ <= _MAX_RANK, "HapiContract: Invalid rank");
        require(caseId_ > 0 && caseId_ <= _caseIdTracker, "HapiContract: CaseId not exist");

        AddressInfo storage account = _addresses[account_];
        require(rank_ > account.rank, "HapiContract: Rank must be greater than the current value");

        uint256 reward = _calculateRewardForReporter(_reporterIds[_msgSender()]);
        if (reward > 0) {
            _reporters[_reporterIds[_msgSender()]].balance += reward;
        }

        account.rank = rank_;
        account.category = category_;
        account.caseId = caseId_;

        emit AddressReported(account_, rank_, category_, caseId_, _reporterIds[_msgSender()]);
    }

    /**
     * @dev Update address information. No rewards.
     *
     * Requirements:
     * - must be called by active reporter account,
     * - `account` cannot be the zero address,
     * - `account` must exist,
     * - `rank` must be between 0 and MAX_RANK,
     * - `rank` must be greater than the current value for unprivileged reporters.
     */
    function updateAddress(address account_, uint8 rank_, uint32 category_) external onlyReporter {
        require(account_ != address(0), "HapiContract: Invalid account");
        require(rank_ <= _MAX_RANK, "HapiContract: Invalid rank");

        AddressInfo storage account = _addresses[account_];
        require(account.caseId != 0, "HapiContract: Account not exist");
        require(account.rank != rank_ || account.category != category_, "HapiContract: Invalid params");

        uint32 reporterTypeId = _reporters[_reporterIds[_msgSender()]].reporterTypeId;
        require(_reporterTypes[reporterTypeId].privileged  || rank_ > account.rank, "HapiContract: Rank must be greater than the current value");

        account.rank = rank_;
        account.category = category_;

        emit AddressUpdated(account_, rank_, category_, _reporterIds[_msgSender()]);
    }

    /**
     * @dev Withdraw reward ERC20 tokens by reporter (reduces the balance of the reporter).
     *
     * Requirements:
     * - must be called by active reporter account,
     * - `account` cannot be the zero address,
     * - withdrawal `amount` must be less than or equal to the reporter's balance.
     */
    function withdrawRewardERC20Token(address account_, uint256 amount_) external onlyReporter nonReentrant {
        require(account_ != address(0), "HapiContract: Invalid account");
        require(_reporters[_reporterIds[_msgSender()]].balance >= amount_, "HapiContract: Not enough reporter balance");

        _reporters[_reporterIds[_msgSender()]].balance -= amount_;
        IERC20(_rewardERC20TokenAddress).safeTransfer(account_, amount_);
    }

    /**
     * @dev Calculate reward for reporter by `reporterId`.
     */
    function _calculateRewardForReporter(uint32 reporterId_) private view returns (uint256) {
        Reporter storage reporter = _reporters[reporterId_];
        return _gasPrice
            * _averageReportGas
            * reporter.rate
            * _reporterTypes[reporter.reporterTypeId].rewardFactor;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ReentrancyGuardUpgradeable is Initializable {
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

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
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
    uint256[49] private __gap;
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

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
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
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
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
        assembly {
            size := extcodesize(account)
        }
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

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
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
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
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
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
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
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

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
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

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

