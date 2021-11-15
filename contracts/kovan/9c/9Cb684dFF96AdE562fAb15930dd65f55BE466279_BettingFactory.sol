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
        return verifyCallResult(success, returndata, errorMessage);
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
        return verifyCallResult(success, returndata, errorMessage);
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
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
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

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IBettingContract.sol";

contract BettingContract is IBettingContract {
    using SafeERC20 for IERC20;

    address payable public owner;
    address payable public creator;

    address public tokenAddress;

    string public name;
    string public description;
    uint256 public lastBetPlaced; // seconds
    uint256 public priceValidationTimestamp; // timestamp

    uint256 public ticketPrice;

    uint256 public bracketsPriceDecimals;
    uint256[] public bracketsPrice;

    Status public status = Status.Lock;

    address[] private listBuyer;
    mapping(address => uint256[]) private buyers;
    mapping(uint256 => address[]) private ticketSell;

    IPriceContract private priceContract;
    bytes32 public resultId;

    constructor(address payable _owner, address payable _creator) {
        owner = _owner;
        creator = _creator;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "BETTING: Only owner");
        _;
    }

    modifier decimalsLength(uint256 decimals) {
        require(decimals <= 18, "BETTING: Required decimals <= 18");
        _;
    }

    modifier onlyOpen() {
        require(status == Status.Open, "BETTING: Required Open");
        _;
    }

    modifier onlyLock() {
        require(status == Status.Lock, "BETTING: Required NOT start");
        _;
    }

    modifier betable() {
        require(
            block.timestamp <= priceValidationTimestamp - lastBetPlaced,
            "BETTING: No betable"
        );
        _;
    }

    modifier onlyPriceClosed() {
        require(
            block.timestamp > priceValidationTimestamp,
            "BETTING: Please waiting for price close"
        );
        _;
    }

    function setName(string calldata _name)
        external
        override
        onlyOwner
        onlyLock
    {
        name = _name;
    }

    function setDescription(string calldata _description)
        external
        override
        onlyOwner
        onlyLock
    {
        description = _description;
    }

    // Setup asset
    function setPool(address _tokenAddress)
        external
        override
        onlyOwner
        onlyLock
    {
        tokenAddress = _tokenAddress;
    }

    //Unit: wei
    function setTicketPrice(uint256 price)
        external
        override
        onlyOwner
        onlyLock
    {
        ticketPrice = price;
    }

    function setBracketsPriceDecimals(uint256 decimals)
        external
        override
        onlyOwner
        decimalsLength(decimals)
        onlyLock
    {
        bracketsPriceDecimals = decimals;
    }

    //Example: [1, 2, 3, 4] ==>  1 <= bracket1 < 2, 2 <= bracket2 < 3, 3 <= bracket3 < 4
    function setBracketsPrice(uint256[] calldata _bracketsPrice)
        external
        override
        onlyOwner
        onlyLock
    {
        for (uint256 i = 1; i < _bracketsPrice.length; i++) {
            require(
                _bracketsPrice[i] >= _bracketsPrice[i - 1],
                "BETTING: bracketsPrice is wrong"
            );
        }
        bracketsPrice = _bracketsPrice;
    }

    function setPriceValidationTimestamp(uint256 unixtime)
        public
        override
        onlyOwner
        onlyLock
    {
        require(
            block.timestamp < unixtime,
            "BETTING: Required expiration > now"
        );
        priceValidationTimestamp = unixtime;
    }

    function setLastBetPlaced(uint256 _seconds)
        external
        override
        onlyOwner
        onlyLock
    {
        lastBetPlaced = _seconds;
    }

    function start(IPriceContract _priceContract)
        external
        payable
        override
        onlyOwner
        onlyLock
    {
        require(
            priceValidationTimestamp > block.timestamp,
            "BETTING: Required price validation > now"
        );
        require(
            priceValidationTimestamp - block.timestamp > lastBetPlaced,
            "BETTING: Required last bet placed > now"
        );
        require(
            bracketsPrice.length > 0,
            "BETTING: Required set brackets price"
        );
        require(
            tokenAddress != address(0x0),
            "BETTING: Required set token address"
        );
        require(
            IERC20(tokenAddress).balanceOf(address(this)) > 0,
            "BETTING: Required deposit token"
        );
        priceContract = _priceContract;
        resultId = IPriceContract(_priceContract).updatePrice{value: msg.value}(
            priceValidationTimestamp - block.timestamp,
            tokenAddress,
            creator
        );
        status = Status.Open;
        emit Ready(block.timestamp, resultId);
    }

    function close() external override onlyPriceClosed onlyOpen {
        (uint256 price, uint256 result, bool success) = _getResult();
        status = Status.End;
        if (!success) {
            _closeForce();
            return;
        }
        address[] memory winers = ticketSell[result];
        uint256 reward = 0;
        if (winers.length > 0) {
            reward = getToltalToken() / winers.length;
            for (uint256 i = winers.length - 1; i > 0; i--) {
                if (winers[i] != address(0x0)) {
                    address winner = winers[i];
                    delete winers[i];
                    IERC20(tokenAddress).safeTransfer(winner, reward);
                }
            }
            if (winers[0] != address(0x0)) {
                address winner = winers[0];
                delete winers[0];
                IERC20(tokenAddress).safeTransfer(winner, getToltalToken());
            }
        } else {
            IERC20(tokenAddress).safeTransfer(creator, getToltalToken());
        }
        creator.transfer((address(this).balance * 95) / 100);
        emit Close(block.timestamp, price, ticketSell[result], reward);
        selfdestruct(owner);
    }

    function _closeForce() private {
        if (listBuyer.length > 0) {
            uint256 reward = getToltalToken() / listBuyer.length;
            for (uint256 i = listBuyer.length - 1; i > 0; i--) {
                if (listBuyer[i] != address(0x0)) {
                    IERC20(tokenAddress).safeTransfer(listBuyer[i], reward);
                    payable(listBuyer[i]).transfer(ticketPrice);
                    delete listBuyer[i];
                }
            }
            if (listBuyer[0] != address(0x0)) {
                IERC20(tokenAddress).safeTransfer(
                    listBuyer[0],
                    getToltalToken()
                );
                payable(listBuyer[0]).transfer(ticketPrice);
                delete listBuyer[0];
            }
        } else {
            IERC20(tokenAddress).safeTransfer(owner, getToltalToken());
        }

        selfdestruct(owner);
    }

    // guess_value = real_value * 10**bracketsPriceDecimals
    function buyTicket(uint256 _bracketIndex)
        public
        payable
        override
        onlyOpen
        betable
    {
        require(msg.sender != creator, "BETTING: Creator cannot bet");
        require(
            msg.value >= ticketPrice,
            "BETTING: Required ETH >= ticketPrice"
        );
        if (_bracketIndex > bracketsPrice.length - 1) {
            _bracketIndex = bracketsPrice.length;
        }
        buyers[msg.sender].push(_bracketIndex);
        ticketSell[_bracketIndex].push(msg.sender);
        listBuyer.push(msg.sender);
        emit Ticket(msg.sender, _bracketIndex);
    }

    function getTicket() public view override returns (uint256[] memory) {
        return buyers[msg.sender];
    }

    function getToltalToken() public view override returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function _getResult()
        private
        view
        returns (
            uint256 price,
            uint256 index,
            bool success
        )
    {
        price = getTokenPrice();
        if (price == 0) {
            return (price, 0, false);
        }

        if (price < bracketsPrice[0]) {
            return (price, 0, true);
        }
        if (price >= bracketsPrice[bracketsPrice.length - 1]) {
            return (price, bracketsPrice.length, true);
        }
        for (uint256 i = 0; i < bracketsPrice.length - 1; i++) {
            if (bracketsPrice[i] <= price && price < bracketsPrice[i + 1]) {
                return (price, i + 1, true);
            }
        }

        return (price, 0, false);
    }

    // calculate price based on pair reserves
    function getTokenPrice() private view returns (uint256) {
        string memory price = IPriceContract(priceContract).getPrice(resultId);
        return stringToUint(price, bracketsPriceDecimals);
    }

    function stringToUint(string memory s, uint256 _decimals)
        private
        pure
        returns (uint256)
    {
        bytes memory b = bytes(s);
        uint256 i;
        uint256 result = 0;
        uint256 dec = 0;
        bool startDot = false;
        for (i = 0; i < b.length && dec < _decimals; i++) {
            if (startDot) {
                dec++;
            }
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            } else {
                startDot = true;
            }
        }
        result = result * 10**(_decimals - dec);
        return result;
    }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./BettingContract.sol";
import "./interface/IBettingFactory.sol";

contract BettingFactory is IBettingFactory {
    function createNewPool(address payable _owner, address payable _creator)
        public
        override
        returns (address)
    {
        BettingContract betting = new BettingContract(_owner, _creator);
        return address(betting);
    }
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;
import "./IPriceContract.sol";

interface IBettingContract {
    event Ticket(address indexed _buyer, uint256 indexed _bracketIndex);
    event Ready(uint256 _timestamp, bytes32 _resultId);
    event Close(
        uint256 _timestamp,
        uint256 _price,
        address[] _winers,
        uint256 _reward
    );

    enum Status {
        Lock,
        Open,
        End
    }

    function setLastBetPlaced(uint256 _seconds) external;

    function setName(string calldata _name) external;

    function setDescription(string calldata _description) external;

    function setPool(address _tokenAddress) external;

    function setTicketPrice(uint256 price) external;

    function setBracketsPriceDecimals(uint256 decimals) external;

    function setBracketsPrice(uint256[] calldata _bracketsPrice) external;

    function setPriceValidationTimestamp(uint256 unixtime) external;

    function start(IPriceContract _priceContract) external payable;

    function close() external;

    function buyTicket(uint256 guess_value) external payable;

    function getTicket() external view returns (uint256[] memory);

    function getToltalToken() external view returns (uint256);
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IBettingFactory {
    function createNewPool(address payable _owner, address payable _creater)
        external
        returns (address);
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPriceContract {
    function updatePrice(
        uint256 _time,
        address _tokens,
        address payable _refund
    ) external payable returns (bytes32);

    function getPrice(bytes32 _id) external view returns (string memory);

    function gasPrice() external view returns (uint256);

    function gasLimit() external view returns (uint256);
}

