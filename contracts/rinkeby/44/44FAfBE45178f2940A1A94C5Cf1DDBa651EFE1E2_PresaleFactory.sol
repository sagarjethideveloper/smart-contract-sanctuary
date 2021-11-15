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
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// functions: lockTokens, unlockTokens...
contract Locker is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public tokenX;
    address public walletOwner;
    uint256 public unlockTokensAtTime;
    bool public unlockTokensRequestMade = false;
    bool public unlockTokensRequestAccepted = false;

    event UnlockedTokens(address _token, uint256 _amount);

    constructor(
        IERC20 _tokenX,
        address _walletOwner,
        uint256 _unlockTokensAtTime
    ) {
        tokenX = _tokenX;
        walletOwner = _walletOwner;
        unlockTokensAtTime = _unlockTokensAtTime;
        transferOwnership(_walletOwner);
    }

    function lockTokens(uint256 _amount) external onlyOwner {
        tokenX.transferFrom(owner(), address(this), _amount);
    }

    function makeUnlockTokensRequest() external onlyOwner {
        unlockTokensRequestMade = true;
        // make event
    }

    function acceptUnlockTokensRequest() external onlyOwner {
        unlockTokensRequestAccepted = true;
        // make event
    }

    function unlockTokens() external onlyOwner {
        require(
            unlockTokensRequestMade,
            "Please make a request to unlock tokens."
        );
        require(
            unlockTokensRequestAccepted,
            "Please wait till the approval to unlock tokens."
        );
        require(
            block.timestamp > unlockTokensAtTime,
            "Tokens will be unlocked soon."
        );
        tokenX.transfer(owner(), tokenX.balanceOf(address(this)));
    }

    function balance() public view returns (uint256) {
        return tokenX.balanceOf(address(this));
    }
}

/*

const res = await addFromWeb(1,2)
if(res === null){

}
else{
    console.log('res: ', res);
}

const someThing = newFunc();
someThing()

const p = {
    name: "ali",
    address: {
        city: "Lahore",
        street: "16",
        region: {
            time: "10"
        }
    }
}

p.name
p.address.city
console.log('time: ', p.address.region.time);

function thisContractIsMadeBy_TheHash.io() external returns(memory string) {
    return "Hi if you want to develop a smart contract you can contact on telegram @thinkmuneeb";
}

update variables by owner of tokenX and shieldNetwork
be ware of ownerships and mint to proper owners
as different factory calling will be used
natspec annotations, author Muneeb Khan
mention comments see sir written contract

*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Locker.sol";

// functions: setRate, buyTokens...
// Presale is Locker
contract Presale is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public busd; // People will give BUSD or buyingToken and get tokenX in return
    IERC20 public tokenX; // People will buy tokenX
    IERC20 public lpTokenX; // Owner of tokenX will lock lpTokenX to get their confidence
    Locker public tokenXLocker;
    Locker public lpTokenXLocker;
    uint256 public tokenXSold = 0;
    uint256 public rate; // 3 = 3 000 000 000 000 000 000, 0.3 = 3 00 000 000 000 000 000 // 0.3 busd = 1 TokenX
    uint256 public amountTokenXToBuyTokenX;
    uint256 public presaleClosedAt = type(uint256).max;
    uint8 public tier = 1;
    address public presaleEarningWallet;
    address public parentCompany;
    address public factory;

    mapping(address => bool) isWhitelisted;
    bool public onlyWhitelistedAllowed;
    bool public presaleIsRejected = false;
    bool public presaleIsApproved = false;
    bool public presaleAppliedForClosing = false;

    event RateChanged(uint256 _newRate);
    event PresaleClosed();

    constructor(
        IERC20 _tokenX,
        IERC20 _lpTokenX,
        IERC20 _busd,
        uint256 _rate,
        address _presaleEarningWallet,
        address _parentCompany,
        bool _onlyWhitelistedAllowed,
        uint256 _amountTokenXToBuyTokenX,
        uint256 _unlockAtTime,
        address[] memory _whitelistAddresses
    ) {
        tokenX = _tokenX;
        lpTokenX = _lpTokenX;
        busd = _busd;
        factory = msg.sender; // only trust those presales who address exist in factory contract // go to factory address and see presale address belong to that factory or not. use method: belongsToThisFactory
        rate = _rate;
        presaleEarningWallet = _presaleEarningWallet;
        onlyWhitelistedAllowed = _onlyWhitelistedAllowed;
        amountTokenXToBuyTokenX = _amountTokenXToBuyTokenX;
        parentCompany = _parentCompany;

        if (_onlyWhitelistedAllowed) {
            for (uint256 i = 0; i < _whitelistAddresses.length; i++) {
                isWhitelisted[_whitelistAddresses[i]] = true;
            }
        }

        tokenXLocker = new Locker(
            _tokenX,
            _presaleEarningWallet,
            _unlockAtTime
        );
        lpTokenXLocker = new Locker(
            _lpTokenX,
            _presaleEarningWallet,
            _unlockAtTime
        );
        transferOwnership(_presaleEarningWallet);
    }

    /// @notice user buys at rate of 0.3 then 33 BUSD or buyingToken will be deducted and 100 tokenX will be given
    function buyTokens(uint256 _tokens) external {
        require(
            !presaleIsRejected,
            "Presale is rejected by the parent network."
        );
        require(block.timestamp < presaleClosedAt, "Presale is closed.");
        require(
            presaleIsApproved,
            "Presale is not approved by the parent network."
        );
        require(
            tokenX.balanceOf(msg.sender) >= amountTokenXToBuyTokenX,
            "You need to hold tokens to buy them from presale."
        );

        uint256 price = (_tokens * rate) / 1e18;
        require(
            busd.balanceOf(msg.sender) >= price,
            "You have less BUSD available."
        );

        if (onlyWhitelistedAllowed) {
            require(
                isWhitelisted[msg.sender],
                "You should become whitelisted to continue."
            );
        }

        tokenXSold += _tokens;
        busd.transferFrom(msg.sender, presaleEarningWallet, price);
        tokenX.transfer(msg.sender, _tokens); // try with _msgsender on truufle test and ethgas reporter
    }

    /// @dev pass true to add to whitelist, pass false to remove from whitelist
    function ownerFunction_editWhitelist(
        address[] memory _addresses,
        bool _approve
    ) external onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            isWhitelisted[_addresses[i]] = _approve;
        }
    }

    function onlyOwnerFunction_setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
        emit RateChanged(_rate);
    }

    function onlyOwnerFunction_closePresale(uint8 _months) external onlyOwner {
        require(
            _months >= 1 && _months <= 3,
            "Presale closing period can be 1 to 3 months."
        );
        presaleAppliedForClosing = presaleAppliedForClosing;
        presaleClosedAt = block.timestamp + _months * 30 days;
        emit PresaleClosed();
    }

    function onlyParentCompanyFunction_editPresaleIsApproved(
        bool _presaleIsApproved
    ) public {
        require(
            msg.sender == parentCompany,
            "You must be parent company to edit value of presaleIsApproved."
        );
        presaleIsApproved = _presaleIsApproved;
    }

    function onlyParentCompanyFunction_editPresaleIsRejected(
        bool _presaleIsRejected
    ) public {
        require(
            msg.sender == parentCompany,
            "You must be parent company to edit value of presaleIsRejected."
        );
        presaleIsRejected = _presaleIsRejected;
    }

    function onlyParentCompanyFunction_editTier(uint8 _tier) public {
        require(
            msg.sender == parentCompany,
            "You must be parent company to edit value of tier."
        );
        tier = _tier;
    }
}

/*
notes:

first implemet core logic
// nonreentrant modifier ? I think its only need in case external calls are not at end

update variables by owner of tokenX and shieldNetwork
be ware of ownerships and mint to proper owners
as different factory calling will be used
natspec annotations, author Muneeb Khan
mention comments see sir written contract

function thisContractIsMadeBy_TheHash.io() external returns(memory string) {
    return "Hi if you want to develop a smart contract you can contact on telegram @thinkmuneeb";
}

cosmetics
function ownerFunction_unlockTokens(IERC20 _token) external onlyOwner {
    _token.transfer(owner(), _token.balanceOf(address(this)));
}
fallback send eth to owner
can send erc721 erc1155 to owner

getWhitelist addresses  method?
presaleIsApproved = false; get approval after changing rate ?


// when I do something crazy in code I feel that it will be caught in auidt. or I need to fix it. Or use some other api.
        // i.e lock token in wallet at time of its creation in single go
        
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./Presale.sol";

contract PresaleFactory is Ownable {
    mapping(uint256 => Presale) public presales;
    uint256 public lastPresaleIndex = 0;

    IERC20 public busd;

    /// @notice people can see if a presale belongs to this factory or not
    mapping(address => bool) public belongsToThisFactory;
    mapping(IERC20 => Presale) public presaleOf;

    constructor(address _parentCompany, IERC20 _busd) {
        busd = _busd;
        transferOwnership(_parentCompany);
    }

    /// @dev users can create an ICO for erc20 from this function
    function createERC20Presale(
        IERC20 _tokenX,
        IERC20 _lpTokenX,
        uint256 _rate,
        uint256 _tokenXToLock,
        uint256 _lpTokenXToLock,
        uint256 _tokenXToSell,
        uint256 _unlockAtTime,
        uint256 _amountTokenXToBuyTokenX,
        address _presaleEarningWallet,
        bool _onlyWhitelistedAllowed,
        address[] memory _whitelistAddresses
    ) external {
        // require(
        //     address(presaleOf[_tokenX]) == address(0),
        //     "Presale already exist for this token"
        // );

        Presale presale = new Presale(
            _tokenX,
            _lpTokenX,
            busd,
            _rate,
            _presaleEarningWallet,
            owner(),
            _onlyWhitelistedAllowed,
            _amountTokenXToBuyTokenX,
            _unlockAtTime,
            _whitelistAddresses
        );

        presaleOf[_tokenX] = presale;
        belongsToThisFactory[address(presale)] = true;
        presales[lastPresaleIndex++] = presale;

        _tokenX.transferFrom(
            msg.sender,
            address(presale.tokenXLocker()),
            _tokenXToLock
        );
        _lpTokenX.transferFrom(
            msg.sender,
            address(presale.lpTokenXLocker()),
            _lpTokenXToLock
        );
        _tokenX.transferFrom(msg.sender, address(presale), _tokenXToSell);
    }

    function getSelectedItems(
        Presale[] memory tempPresales,
        uint256 selectedCount
    ) private pure returns (Presale[] memory) {
        uint256 someI = 0;
        Presale[] memory selectedPresales = new Presale[](selectedCount);

        // traverse in tempPresales addresses to get only addresses that are not 0x0
        for (uint256 i = 0; i < tempPresales.length; i++) {
            if (address(tempPresales[i]) != address(0))
                selectedPresales[someI++] = tempPresales[i];
        }

        return selectedPresales;
    }

    function getPresales(uint256 _index, uint256 _amountToFetch)
        external
        view
        returns (Presale[] memory)
    {
        uint256 selectedCount = 0;
        uint256 currIndex = _index;
        Presale[] memory tempPresales = new Presale[](_amountToFetch);
        for (uint256 i = 0; i < _amountToFetch; i++) {
            if (address(presales[currIndex]) != address(0)) {
                tempPresales[i] = presales[currIndex++];
                selectedCount++;
            }
        }

        return getSelectedItems(tempPresales, selectedCount);
    }

    function getPresales(
        uint256 _index,
        uint256 _amountToFetch,
        bool _approvedValue // this method can be used to get approved and not approved presales
    ) external view returns (Presale[] memory) {
        uint256 selectedCount = 0;
        uint256 currIndex = _index;
        Presale[] memory tempPresales = new Presale[](_amountToFetch);
        for (uint256 i = 0; i < _amountToFetch; i++) {
            if (
                address(presales[currIndex]) != address(0) &&
                presales[currIndex].presaleIsApproved() == _approvedValue
            ) {
                tempPresales[i] = presales[currIndex++];
                selectedCount++;
            }
        }

        return getSelectedItems(tempPresales, selectedCount);
    }

    function getPresales(
        uint256 _index,
        uint256 _amountToFetch,
        uint256 _tier // this method can be used to get tier 1,2,3 presales
    ) external view returns (Presale[] memory) {
        uint256 selectedCount = 0;
        uint256 currIndex = _index;
        Presale[] memory tempPresales = new Presale[](_amountToFetch);
        for (uint256 i = 0; i < _amountToFetch; i++) {
            if (
                address(presales[currIndex]) != address(0) &&
                presales[currIndex].tier() == _tier
            ) {
                tempPresales[i] = presales[currIndex++];
                selectedCount++;
            }
        }

        return getSelectedItems(tempPresales, selectedCount);
    }

    function getPresalesAppliedForClosing(
        uint256 _index,
        uint256 _amountToFetch
    ) external view returns (Presale[] memory) {
        uint256 selectedCount = 0;
        uint256 currIndex = _index;
        Presale[] memory tempPresales = new Presale[](_amountToFetch);
        for (uint256 i = 0; i < _amountToFetch; i++) {
            if (
                address(presales[currIndex]) != address(0) &&
                presales[currIndex].presaleAppliedForClosing() == true
            ) {
                tempPresales[i] = presales[currIndex++];
                selectedCount++;
            }
        }

        return getSelectedItems(tempPresales, selectedCount);
    }

    function getPresales(
        uint256 _index,
        uint256 _amountToFetch,
        address _owner // this method can be used to get _owner's presales
    ) external view returns (Presale[] memory) {
        uint256 selectedCount = 0;
        uint256 currIndex = _index;
        Presale[] memory tempPresales = new Presale[](_amountToFetch);
        for (uint256 i = 0; i < _amountToFetch; i++) {
            if (
                address(presales[currIndex]) != address(0) &&
                presales[currIndex].owner() == _owner
            ) {
                tempPresales[i] = presales[currIndex++];
                selectedCount++;
            }
        }

        return getSelectedItems(tempPresales, selectedCount);
    }

    function getPresaleDetails(uint256 _index)
        external
        view
        returns (
            IERC20,
            IERC20,
            Locker,
            Locker,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            presales[_index].tokenX(), // tokenX address used in a presale
            presales[_index].lpTokenX(), // lpTokenX used in presale to lock lpTokenX
            presales[_index].tokenXLocker(),
            presales[_index].lpTokenXLocker(),
            presales[_index].tokenX().balanceOf(address(presales[_index])), // tokenX left to sell
            presales[_index].tokenXLocker().balance(), // locked X Tokens
            presales[_index].lpTokenXLocker().balance() // locked LpTokenX
            // presales[_index].tokenXSold(),
            // presales[_index].rate(), // how many BUSD = 1 TokenX
            // presales[_index].amountTokenXToBuyTokenX(),
            // presales[_index].presaleClosedAt(),
            // presales[_index].tier(), // tier can be 1,2,3. higher is better.
            // presales[_index].presaleIsRejected(),
            // presales[_index].presaleIsApproved(),
            // presales[_index].presaleAppliedForClosing()
        );
    }

    // func return all rates of 50 presales

    // see that 10 size array returns what on 3 elems in it, function getStopPoint private returns (uint256) {}
}

/*


    // uint256,
    // uint256,
    // uint256,
    // uint256,
    // uint256,
    // uint256,
    // uint8,
    // bool,
    // bool,
    // bool



notes:
getAddresIsTrustedOrNot
get approved presales
get not approved presales (for admin)
get rejected presales (for admin)
get presales of a specific person
// get presales with unlock liquidity request
disbanding projects
get presale which wan to be approved
get locked amount of a presale, (compare run time total vs save total on each transaction)
write multiple presales...
Plus more...




*/

