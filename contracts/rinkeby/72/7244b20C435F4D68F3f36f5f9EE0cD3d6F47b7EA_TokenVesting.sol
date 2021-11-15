// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Sablier Types
 * @author Sablier
 */
library Types {
    struct Invest {
        uint256 deposit;
        uint256 releaseCounter;
        uint256 ratePerMonth;
        uint256[] timesInMonth;
        uint256[] counterArray;
        uint256 remainingBalance;
        uint256 startTime;
        uint256 stopTime;
        address recipient;
        address sender;
        address tokenAddress;
        bool isEntity;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.12;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./contracts/Types.sol";

contract TokenVesting is Ownable {
  using SafeERC20 for IERC20;


    uint256 public nextInvestId;
    address public iagonTokenAddress;
    uint256[] intervalTime = [120, 240, 360, 480, 600, 720, 840, 960, 1080, 1200];
    //uint256[] intervalTime = [30 days, 60 days, 90 days, 120 days, 150 days, 180 days, 210 days, 240 days, 270 days, 310 days];
    uint256[] countArray = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    mapping(uint256 => Types.Invest) private invests;
  
    event CreateStream(
        uint256 indexed investId,
        address indexed sender,
        address indexed recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    );

    event WithdrawFromStream(uint256 indexed investId, address indexed recipient, uint256 amount);

    event CancelStream(
        uint256 indexed investId,
        address indexed sender,
        address indexed recipient,
        uint256 senderBalance,
        uint256 recipientBalance
    );

    modifier onlySenderOrRecipient(uint256 investId) {
        require(
            msg.sender == invests[investId].sender || msg.sender == invests[investId].recipient,
            "caller is not the sender or the recipient of the stream"
        );
        _;
    }

    modifier investExists(uint256 investId) {
        require(invests[investId].isEntity, "stream does not exist");
        _;
    }

    constructor() {
        nextInvestId = 1;
        iagonTokenAddress = 0x06f7246f009F6f0372C481AD6cf60f3CDe31DCe2;
    }

    function getInvestDetails(uint256 investId)
        external
        view
        investExists(investId)
        returns (
            address sender,
            address recipient,
            uint256 deposit,
            address tokenAddress,
            uint256 startTime,
            uint256 stopTime,
            uint256 remainingBalance,
            uint256 ratePerMonth
        ){
        sender = invests[investId].sender;
        recipient = invests[investId].recipient;
        deposit = invests[investId].deposit;
        tokenAddress = invests[investId].tokenAddress;
        startTime = invests[investId].startTime;
        stopTime = invests[investId].stopTime;
        remainingBalance = invests[investId].remainingBalance;
        ratePerMonth = invests[investId].ratePerMonth;
    }

    // function getStreamExp(uint256 investId)
    //     public
    //     view
    //     returns (
    //         address sender,
    //         address recipient,
    //         uint256 deposit,
    //         address tokenAddress,
    //         uint256 startTime,
    //         uint256 stopTime,
    //         uint256 remainingBalance,
    //         uint256 ratePerSecond,
    //         uint256 releaseCounter,
    //         uint256 ratePerMonth,
    //         uint256[] memory timesInMonth,
    //         uint256[] memory counterArray
    //     ){
    //         Types.Stream memory s = invests[investId];
    //         return(s.sender, s.recipient,s.deposit,s.tokenAddress,s.startTime,s.stopTime,s.remainingBalance,s.ratePerSecond,s.releaseCounter,s.ratePerMonth,s.timesInMonth,s.counterArray);    
    //     }

    function deltaOf(uint256 investId) public view investExists(investId) returns (uint256 delta) {
        Types.Invest memory stream = invests[investId];
        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp < stream.stopTime) return block.timestamp - stream.startTime;
        return (stream.stopTime - stream.startTime);
    }

    function investorInvestTokens(address recipient, uint256 deposit) 
        public
        returns(uint256){
            uint256 startTime = block.timestamp + 60 seconds;
            uint256 stopTime = block.timestamp + 1140 seconds;
            require(recipient != address(0x00), "stream to the zero address");
            require(recipient != address(this), "stream to the contract itself");
            require(recipient != msg.sender, "stream to the caller");
            require(deposit > 0, "deposit is zero");
            require(startTime >= block.timestamp, "start time before block.timestamp");
            require(stopTime > startTime, "stop time before the start time");
            require(deposit % 9 == 0, "deposit not multiple of time delta");

            uint256 investId = nextInvestId;
            uint256 ratePerMonth = deposit / 9;
            invests[investId] = Types.Invest({
                remainingBalance: deposit,
                deposit: deposit,
                isEntity: true,
                ratePerMonth: ratePerMonth,
                recipient: recipient,
                sender: msg.sender,
                startTime: startTime,
                stopTime: stopTime,
                tokenAddress: iagonTokenAddress,
                releaseCounter: 0,
                timesInMonth: intervalTime,
                counterArray: countArray
            });

            nextInvestId = nextInvestId + 1;
            IERC20(iagonTokenAddress).transferFrom(msg.sender, address(this), deposit);
            emit CreateStream(investId, msg.sender, recipient, deposit, iagonTokenAddress, startTime, stopTime);
            return investId;
    }
    
       function advisorInvestTokens(address recipient, uint256 deposit) 
        public
        returns(uint256){
            uint256 startTime = block.timestamp + 60 seconds;
            uint256 stopTime = block.timestamp + 1260 seconds;
            require(recipient != address(0x00), "stream to the zero address");
            require(recipient != address(this), "stream to the contract itself");
            require(recipient != msg.sender, "stream to the caller");
            require(deposit > 0, "deposit is zero");
            require(startTime >= block.timestamp, "start time before block.timestamp");
            require(stopTime > startTime, "stop time before the start time");
            require(deposit % 10 == 0, "deposit not multiple of time delta");

            uint256 investId = nextInvestId;
            uint256 ratePerMonth = deposit / 10;
            invests[investId] = Types.Invest({
                remainingBalance: deposit,
                deposit: deposit,
                isEntity: true,
                ratePerMonth: ratePerMonth,
                recipient: recipient,
                sender: msg.sender,
                startTime: startTime,
                stopTime: stopTime,
                tokenAddress: iagonTokenAddress,
                releaseCounter: 0,
                timesInMonth: intervalTime,
                counterArray: countArray
            });

            nextInvestId = nextInvestId + 1;
            IERC20(iagonTokenAddress).transferFrom(msg.sender, address(this), deposit);
            emit CreateStream(investId, msg.sender, recipient, deposit, iagonTokenAddress, startTime, stopTime);
            return investId;
    }


    function withdrawTokens(uint256 investId)
        public
        investExists(investId)
        onlySenderOrRecipient(investId)
        returns (bool){
            int256 timeDiff = int(block.timestamp - invests[investId].startTime);
            require(timeDiff > 0, "tokens are not released yet");
            uint256 percent = invests[investId].ratePerMonth;
            uint256 duration = block.timestamp - invests[investId].startTime;
            uint256 releaseAmount = 0;
            uint256 i;
            if(block.timestamp >= invests[investId].stopTime){
                releaseAmount = invests[investId].remainingBalance;
                IERC20(invests[investId].tokenAddress).safeTransfer(invests[investId].recipient, releaseAmount);
                delete invests[investId];
                emit WithdrawFromStream(investId, invests[investId].recipient, releaseAmount);
                return true;
            }
            for(i = 0; i < 10; i++){
                uint256 a = i + 1;
                if(invests[investId].timesInMonth[i] <= duration && invests[investId].timesInMonth[a] >= duration){
                    uint256 counter = invests[investId].counterArray[i];
                    counter = counter - invests[investId].releaseCounter;
                    releaseAmount = percent * counter;
                    require(releaseAmount > 0, 'amount is already withdrawn');
                    invests[investId].remainingBalance = invests[investId].remainingBalance - releaseAmount;
                    invests[investId].releaseCounter = invests[investId].releaseCounter + counter;
                    if (invests[investId].remainingBalance == 0) delete invests[investId];
                    IERC20(invests[investId].tokenAddress).safeTransfer(invests[investId].recipient, releaseAmount);
                    emit WithdrawFromStream(investId, invests[investId].recipient, releaseAmount);
                    return true;
                }
            }
            require(releaseAmount > 0, 'release Amount is zero');
            emit WithdrawFromStream(investId, invests[investId].recipient, releaseAmount);
            return false;
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
    constructor() {
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
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

