// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.6.8;
pragma experimental ABIEncoderV2;

interface IBEP20 {

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


/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */

library SafeMath {
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
		uint256 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
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
		return sub(a, b, "SafeMath: subtraction overflow");
	}

	/**
	 * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
	 * overflow (when the result is negative).
	 *
	 * Counterpart to Solidity's `-` operator.
	 *
	 * Requirements:
	 *
	 * - Subtraction cannot overflow.
	 */
	function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
		require(b <= a, errorMessage);
		uint256 c = a - b;

		return c;
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
		// Gas optimization: this is cheaper than requiring 'a' not being zero, but the
		// benefit is lost if 'b' is also tested.
		// See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
		if (a == 0) {
			return 0;
		}

		uint256 c = a * b;
		require(c / a == b, "SafeMath: multiplication overflow");

		return c;
	}

	/**
	 * @dev Returns the integer division of two unsigned integers. Reverts on
	 * division by zero. The result is rounded towards zero.
	 *
	 * Counterpart to Solidity's `/` operator. Note: this function uses a
	 * `revert` opcode (which leaves remaining gas untouched) while Solidity
	 * uses an invalid opcode to revert (consuming all remaining gas).
	 *
	 * Requirements:
	 *
	 * - The divisor cannot be zero.
	 */
	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		return div(a, b, "SafeMath: division by zero");
	}

	/**
	 * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
	 * division by zero. The result is rounded towards zero.
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
		require(b > 0, errorMessage);
		uint256 c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold

		return c;
	}

	/**
	 * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
	 * Reverts when dividing by zero.
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
		return mod(a, b, "SafeMath: modulo by zero");
	}

	/**
	 * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
	 * Reverts with custom message when dividing by zero.
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
		require(b != 0, errorMessage);
		return a % b;
	}
}

abstract contract Context {
	function _msgSender() internal view virtual returns (address payable) {
		return msg.sender;
	}

	function _msgData() internal view virtual returns (bytes memory) {
		this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
		return msg.data;
	}
}


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
		// According to EIP-1052, 0x0 is the value returned for not-yet created accounts
		// and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
		// for accounts without code, i.e. `keccak256('')`
		bytes32 codehash;
		bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
		// solhint-disable-next-line no-inline-assembly
		assembly { codehash := extcodehash(account) }
		return (codehash != accountHash && codehash != 0x0);
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
		return _functionCallWithValue(target, data, 0, errorMessage);
	}

	/**
	 * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
	 * but also transferring `value` wei to `target`.
	 *
	 * Requirements:
	 *
	 * - the calling contract must have an BNB balance of at least `value`.
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
		return _functionCallWithValue(target, data, value, errorMessage);
	}

	function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
		require(isContract(target), "Address: call to non-contract");

		// solhint-disable-next-line avoid-low-level-calls
		(bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
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
contract Ownable is Context {
	bool private _useMultipleCallers;
	address private _owner;
	mapping(address => bool) private _authorizedCallers;

	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
	event AuthorizedCaller(address account,bool value);
	/**
	 * @dev Initializes the contract setting the deployer as the initial owner.
	 */
	constructor () internal {
		address msgSender = _msgSender();
		_owner = msgSender;
		_authorizedCallers[msgSender] = true;
		_useMultipleCallers = true;
		emit OwnershipTransferred(address(0), msgSender);
	}

	/**
	 * @dev Returns the address of the current owner.
	 */
	function owner() public view returns (address) {
		return _owner;
	}

	function isAuthorizedCaller(address account) public view returns (bool) {
		return _authorizedCallers[account];
	}

	/**
	 * @dev Throws if called by any account other than the owner.
	 */
	modifier onlyOwner() {
		require(_owner == _msgSender() || (_useMultipleCallers && _authorizedCallers[_msgSender()] == true), "Ownable: caller is not authorized");
		_;
	}

	function setAuthorizedCallers(address account,bool value) public onlyOwner {
		require(account != address(0), "Ownable: Authorized caller is the zero address");
		_authorizedCallers[account] = value;
		emit AuthorizedCaller(account,value);
	}

	/**
	* @dev Leaves the contract without owner. It will not be possible to call
	* `onlyOwner` functions anymore except by authorized callers. 
	* Can only be called by the current owner or authorized callers.
	*
	* NOTE: Renouncing ownership will leave the contract without an owner,
	* thereby removing any functionality that is only available to the owner.
	*/
	function renounceOwnership() public virtual onlyOwner {
		emit OwnershipTransferred(_owner, address(0));
		_authorizedCallers[_owner] = false;
		_owner = address(0);
		
	}

	/**
	* @dev Leaves the contract without owner and authorized callers. It will not be possible to call
	* `onlyOwner` functions anymore. 
	* Can only be called by the current owner or authorized callers if _useMultipleCallers is true.
	*
	* NOTE: Renouncing ownership will leave the contract without an owner,
	* thereby removing any functionality that is only available to the owner.
	*/
	function fullRenounceOwnership() public virtual onlyOwner {
		emit OwnershipTransferred(_owner, address(0));
		_useMultipleCallers = false;
		_owner = address(0);
	}

	/**
	 * @dev Transfers ownership of the contract to a new account (`newOwner`).
	 * Can only be called by the current owner.
	 */
	function transferOwnership(address newOwner) public virtual onlyOwner {
		require(newOwner != address(0), "Ownable: new owner is the zero address");
		emit OwnershipTransferred(_owner, newOwner);
		_authorizedCallers[_owner] = false;
		_authorizedCallers[newOwner] = true;
		_owner = newOwner;
	}
}

interface IPancakeFactory {
	event PairCreated(address indexed token0, address indexed token1, address pair, uint);

	function feeTo() external view returns (address);
	function feeToSetter() external view returns (address);

	function getPair(address tokenA, address tokenB) external view returns (address pair);
	function allPairs(uint) external view returns (address pair);
	function allPairsLength() external view returns (uint);

	function createPair(address tokenA, address tokenB) external returns (address pair);

	function setFeeTo(address) external;
	function setFeeToSetter(address) external;
}

interface IPancakePair {
	event Approval(address indexed owner, address indexed spender, uint value);
	event Transfer(address indexed from, address indexed to, uint value);

	function name() external pure returns (string memory);
	function symbol() external pure returns (string memory);
	function decimals() external pure returns (uint8);
	function totalSupply() external view returns (uint);
	function balanceOf(address owner) external view returns (uint);
	function allowance(address owner, address spender) external view returns (uint);

	function approve(address spender, uint value) external returns (bool);
	function transfer(address to, uint value) external returns (bool);
	function transferFrom(address from, address to, uint value) external returns (bool);

	function DOMAIN_SEPARATOR() external view returns (bytes32);
	function PERMIT_TYPEHASH() external pure returns (bytes32);
	function nonces(address owner) external view returns (uint);

	function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

	event Mint(address indexed sender, uint amount0, uint amount1);
	event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
	event Swap(
		address indexed sender,
		uint amount0In,
		uint amount1In,
		uint amount0Out,
		uint amount1Out,
		address indexed to
	);
	event Sync(uint112 reserve0, uint112 reserve1);

	function MINIMUM_LIQUIDITY() external pure returns (uint);
	function factory() external view returns (address);
	function token0() external view returns (address);
	function token1() external view returns (address);
	function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
	function price0CumulativeLast() external view returns (uint);
	function price1CumulativeLast() external view returns (uint);
	function kLast() external view returns (uint);

	function mint(address to) external returns (uint liquidity);
	function burn(address to) external returns (uint amount0, uint amount1);
	function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
	function skim(address to) external;
	function sync() external;

	function initialize(address, address) external;
}

interface IPancakeRouter01 {
	function factory() external pure returns (address);
	function WETH() external pure returns (address);

	function addLiquidity(
		address tokenA,
		address tokenB,
		uint amountADesired,
		uint amountBDesired,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline
	) external returns (uint amountA, uint amountB, uint liquidity);
	function addLiquidityETH(
		address token,
		uint amountTokenDesired,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline
	) external payable returns (uint amountToken, uint amountETH, uint liquidity);
	function removeLiquidity(
		address tokenA,
		address tokenB,
		uint liquidity,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline
	) external returns (uint amountA, uint amountB);
	function removeLiquidityETH(
		address token,
		uint liquidity,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline
	) external returns (uint amountToken, uint amountETH);
	function removeLiquidityWithPermit(
		address tokenA,
		address tokenB,
		uint liquidity,
		uint amountAMin,
		uint amountBMin,
		address to,
		uint deadline,
		bool approveMax, uint8 v, bytes32 r, bytes32 s
	) external returns (uint amountA, uint amountB);
	function removeLiquidityETHWithPermit(
		address token,
		uint liquidity,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline,
		bool approveMax, uint8 v, bytes32 r, bytes32 s
	) external returns (uint amountToken, uint amountETH);
	function swapExactTokensForTokens(
		uint amountIn,
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	) external returns (uint[] memory amounts);
	function swapTokensForExactTokens(
		uint amountOut,
		uint amountInMax,
		address[] calldata path,
		address to,
		uint deadline
	) external returns (uint[] memory amounts);
	function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
	external
	payable
	returns (uint[] memory amounts);
	function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
	external
	returns (uint[] memory amounts);
	function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
	external
	returns (uint[] memory amounts);
	function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
	external
	payable
	returns (uint[] memory amounts);

	function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
	function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
	function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
	function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
	function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IPancakeRouter02 is IPancakeRouter01 {
	function removeLiquidityETHSupportingFeeOnTransferTokens(
		address token,
		uint liquidity,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline
	) external returns (uint amountETH);
	function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
		address token,
		uint liquidity,
		uint amountTokenMin,
		uint amountETHMin,
		address to,
		uint deadline,
		bool approveMax, uint8 v, bytes32 r, bytes32 s
	) external returns (uint amountETH);

	function swapExactTokensForTokensSupportingFeeOnTransferTokens(
		uint amountIn,
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	) external;
	function swapExactETHForTokensSupportingFeeOnTransferTokens(
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	) external payable;
	function swapExactTokensForETHSupportingFeeOnTransferTokens(
		uint amountIn,
		uint amountOutMin,
		address[] calldata path,
		address to,
		uint deadline
	) external;
}

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

	constructor () public {
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

	modifier isHuman() {
		require(tx.origin == msg.sender, "sorry humans only");
		_;
	}
}

library Utils {
	using SafeMath for uint256;

	function swapTokensForEth(
		address routerAddress,
		uint256 tokenAmount
	) public {
		IPancakeRouter02 pancakeRouter = IPancakeRouter02(routerAddress);

		// generate the pancake pair path of token -> weth
		address[] memory path = new address[](2);
		path[0] = address(this);
		path[1] = pancakeRouter.WETH();

		// make the swap
		pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
			tokenAmount,
			0, // accept any amount of BNB
			path,
			address(this),
			block.timestamp
		);
	}

	function swapETHForTokens(
		address routerAddress,
		address recipient,
		uint256 ethAmount
	) public {
		IPancakeRouter02 pancakeRouter = IPancakeRouter02(routerAddress);

		// generate the pancake pair path of token -> weth
		address[] memory path = new address[](2);
		path[0] = pancakeRouter.WETH();
		path[1] = address(this);

		// make the swap
		pancakeRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
			0, // accept any amount of BNB
			path,
			address(recipient),
			block.timestamp + 360
		);
	}

	function swapETHForRewardTokens(
		address routerAddress,
		address tokenAddress,
		address recipient,
		uint256 ethAmount
	) public {
		IPancakeRouter02 pancakeRouter = IPancakeRouter02(routerAddress);

		// generate the pancake pair path of token -> weth
		address[] memory path = new address[](2);
		path[0] = pancakeRouter.WETH();
		path[1] = tokenAddress;

		// make the swap
		pancakeRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
			0, // accept any amount of BNB
			path,
			address(recipient),
			block.timestamp + 360
		);
	}

	function addLiquidity(
		address routerAddress,
		address owner,
		uint256 tokenAmount,
		uint256 ethAmount
	) public {
		IPancakeRouter02 pancakeRouter = IPancakeRouter02(routerAddress);

		// add the liquidity
		pancakeRouter.addLiquidityETH{value : ethAmount}(
			address(this),
			tokenAmount,
			0, // slippage is unavoidable
			0, // slippage is unavoidable
			owner,
			block.timestamp + 360
		);
	}

	function mulScale(uint256 x, uint256 y, uint128 scale) internal pure returns (uint256) {
		uint256 a = x.div(scale);
		uint256 b = x.mod(scale);
		uint256 c = y.div(scale);
		uint256 d = y.mod(scale);
		return (a.mul(c).mul(scale)).add(a.mul(d)).add(b.mul(c)).add(b.mul(d).div(scale));
	}

}
 
contract LamboDoge is Context, IBEP20, Ownable, ReentrancyGuard {
	using SafeMath for uint256;
	using Address for address;

	string private _name = "Lambo Doge";
	string private _symbol = "LDOGE";
	uint8 private _decimals = 18;
	
	mapping(address => uint256) private _rOwned;
	mapping(address => uint256) private _tOwned;
	mapping(address => mapping(address => uint256)) private _allowances;

	mapping(address => bool) private _isExcludedFromFee;
	mapping(address => bool) private _isExcludedFromMaxTx;
	mapping(address => bool) private _applyFeeFor;
	mapping(address => bool) private _isTradingWhiteListed;
	mapping(address => bool) private _isSellWhiteListed;
    mapping(address => bool) private _isExcludedFromReward;
	mapping(address => address) private _previousHolder;
	mapping(address => address) private _nextHolder;
	mapping(address => uint256) private _nextAllowedTransferToPancake;
	mapping(address => uint256) private _nextAllowedTransferToPancakePriceImpact;
	mapping(address => uint256) private _lockAccount;
    address[] private _excluded;
    
	bool private tradingEnabled = false;
	bool private noFeeForTransfert = true;
	bool private limitSellByTimeUnit = true;

	uint256 private constant MAX = ~uint256(0);
	uint256 private _tTotal = 100 * 10**9 * 10**18;
	uint256 private _rTotal = (MAX - (MAX % _tTotal));
	uint256 private _tFeeTotal;

	// Pancakeswap pointers
	IPancakeRouter02 public immutable pancakeRouter;
	address public immutable pancakePair;
	address public immutable addressWBNB;
	address private marketingWallet;
	address private buyBackWallet;
	address private liquidityWallet;

	bool private inSwapAndLiquify = false;

	uint256 private _maxPriceImpactForSell = 20000; // 2% max price impact sell
	uint256 private _maxPriceImpactForBuy = 80000; // 8% max price impact buy
	uint256 private _maxPriceImpactForSwapAndLiquify = 20000; // 2% max price impact
	bool private swapAndLiquifyEnabled = false; // should be true
	
	uint256 private _taxFee = 2;
	uint256 private _previousTaxFee = _taxFee;

	uint256 private _liquidityFee = 2; // 2% will be added pool
	uint256 private _previousLiquidityFee = _liquidityFee;

	uint256 private _marketingFee = 2; // 2% will be converted to BNB for marketing
	uint256 private _previousMarketingFee = _marketingFee;

	uint256 private _buyBackFee = 0; // 0% will be used to buyback the reward token
	uint256 private _previousBuyBackFee = _buyBackFee;

	uint256 private _minBNBToSendToMarketingWallet = 5 * 10 ** 17;
	uint256 private _minBNBToBuyBack = 5 * 10 ** 17;
	
	uint256 private oneSellEveryX = 2 hours;

	uint256 private _totalCountBuy = 0;
	uint256 private _totalCountSell = 0;

	uint256 private _marketingBNB;
	uint256 private _buyBackBNB;

	
	modifier lockTheSwap {
		inSwapAndLiquify = true;
		_;
		inSwapAndLiquify = false;
	}
	
	event SwapAndLiquifyEnabledUpdated(bool enabled);

	event SwapAndLiquify(
		uint256 tokensSwapped,
		uint256 bnbReceived
	);

	event SwapForMarketing(
		uint256 tokensSwapped,
		uint256 bnbReceived
	);

	event SentBNBSuccessfully(
		address from,
		address to,
		uint256 bnbReceived
	);

	event SentTokensSuccessfully(
		address token,
		address from,
		address to,
		uint256 tokenReceived
	);
	
	event NewMarketingWallet(
		address oldWallet,
		address newWallet
	);
	
	event NewBuyBackWallet(
		address oldWallet,
		address newWallet
	);

	event NewLiquidityWallet(
		address oldWallet,
		address newWallet
	);

	event LockAccount(
		address account,
		uint256 time
	);
	
	event TaxFee(
		uint256 value,
		uint256 previousValue
	);

	event LiquidityFee(
		uint256 value,
		uint256 previousValue
	);

	event MarketingFee(
		uint256 value,
		uint256 previousValue
	);
	
	event BuyBackFee(
		uint256 value,
		uint256 previousValue
	);

	event TradingStatus(
		bool enabled
	);

	constructor (
		address payable routerAddress,
		address _addressWBNB
	) public {
	    // send all tokens to owner
		_rOwned[_msgSender()] = _rTotal;
		// set WBNB contract address
		addressWBNB = _addressWBNB;
		IPancakeRouter02 _pancakeRouter = IPancakeRouter02(routerAddress);
		// Create a pancake pair for this new token
		pancakePair = IPancakeFactory(_pancakeRouter.factory()).createPair(address(this), _pancakeRouter.WETH());
		// set the pancakeswap router
		pancakeRouter = _pancakeRouter;
		emit Transfer(address(0), _msgSender(), _tTotal);
	}
	
	// TOKEN INFO
	function name() public view returns (string memory) {
		return _name;
	}

	function symbol() public view returns (string memory) {
		return _symbol;
	}

	function decimals() public view returns (uint8) {
		return _decimals;
	}

	function totalSupply() public view override returns (uint256) {
		return _tTotal;
	}

	function totalFees() public view returns (uint256) {
		return _tFeeTotal;
	}

	// TOKEN INTERFACE
	function balanceOf(address account) public view override returns (uint256) {
        if (_isExcludedFromReward[account]) return _tOwned[account];
		return tokenFromReflection(_rOwned[account]);
	}

	function transfer(address recipient, uint256 amount) public override returns (bool) {
		_transfer(_msgSender(), recipient, amount);
		return true;
	}

	function allowance(address owner, address spender) public view override returns (uint256) {
		return _allowances[owner][spender];
	}

	function approve(address spender, uint256 amount) public override returns (bool) {
		_approve(_msgSender(), spender, amount);
		return true;
	}

	function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
		_transfer(sender, recipient, amount);
		_approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
		return true;
	}

	function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
		_approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
		return true;
	}

	function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
		_approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
		return true;
	}
	
	// INFO
	function addHoursToCurrentTime(uint256 _hours) public view returns (uint256){
		return block.timestamp + (_hours * 1 hours);
	}

	function addMinutesToCurrentTime(uint256 _minutes) public view returns (uint256){
		return block.timestamp + (_minutes * 1 minutes);
	}

	function isTradingWhiteListed(address account) public view returns (bool) {
		return _isTradingWhiteListed[account];
	}
	
	function isSellWhiteListed(address account) public view returns (bool) {
		return _isSellWhiteListed[account];
	}

	function canSellNow(address account) public view returns (bool) {
		return _nextAllowedTransferToPancake[account] <= block.timestamp && _nextAllowedTransferToPancakePriceImpact[account] <= _maxPriceImpactForSell;
	}
	
	function getNextAllowedTransferToPancake(address account) public view returns (uint256) {
		return _nextAllowedTransferToPancake[account];
	}

	function isExcludedFromFee(address account) public view returns (bool) {
		return _isExcludedFromFee[account];
	}
	
	function isFeeAppliedOnTransfer(address account) public view returns (bool) {
		return _applyFeeFor[account];
	}

	function isExcludedFromMaxTx(address account) public view returns (bool) {
		return _isExcludedFromMaxTx[account];
	}
	
	function getLockTime(address account) public view returns (uint256) {
		return _lockAccount[account];
	}

	function isAccountLocked(address account) public view returns (bool) {
		return _lockAccount[account] > 0 && _lockAccount[account] > block.timestamp;
	}

	function isTradingEnabled() public view returns (bool) {
		return tradingEnabled;
	}
	
	function isNoFeeForTransfert() public view returns (bool) {
		return noFeeForTransfert;
	}

	function isLimitSellByTimeUnit() public view returns (bool) {
		return limitSellByTimeUnit;
	}
	
	function getOneSellEveryX() public view returns (uint256) {
		return oneSellEveryX;
	}

	function isSwapAndLiquifyEnabled() public view returns (bool) {
		return swapAndLiquifyEnabled;
	}
	
	function getTaxFee() public view returns (uint256) {
		return _taxFee;
	}

	function getLiquidityFee() public view returns (uint256) {
		return _liquidityFee;
	}

	function getMarketingFee() public view returns (uint256) {
		return _marketingFee;
	}

	function getBuyBackFee() public view returns (uint256) {
		return _buyBackFee;
	}

	function getMaxPriceImpactForSell() public view returns (uint256) {
		return _maxPriceImpactForSell;
	}

	function getMaxPriceImpactForBuy() public view returns (uint256) {
		return _maxPriceImpactForBuy;
	}

	function getMaxPriceImpactForSwapAndLiquify() public view returns (uint256) {
		return _maxPriceImpactForSwapAndLiquify;
	}

	function getMinTokenNumberToSell() public view returns (uint256) {
		return computeAmountFromPriceImpact(_maxPriceImpactForSwapAndLiquify);
	}

	function getMinBNBToSendToMarketingWallet() public view returns (uint256) {
		return _minBNBToSendToMarketingWallet;
	}
	
	function getMinBNBToBuyBack() public view returns (uint256) {
		return _minBNBToBuyBack;
	}
	
	function getMarketingWalletAddress() public view returns (address) {
		return marketingWallet;
	}

	function getBuyBackWalletAddress() public view returns (address) {
		return buyBackWallet;
	}

	function getLiquidityWalletAddress() public view returns (address) {
		return liquidityWallet;
	}

	function getCurrentSupply() public view returns (uint256, uint256) {
		return _getCurrentSupply();
	}
	
	function getTotalCountBuy() public view returns (uint256) {
		return _totalCountBuy;
	}

	function getTotalCountSell() public view returns (uint256) {
		return _totalCountSell;
	}

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcludedFromReward[account];
    }

	// Setter
    function _excludeFromReward(address account) private {
        if (_isExcludedFromReward[account]) return;
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcludedFromReward[account] = true;
        _excluded.push(account);
    }

    function excludeFromReward(address account) public onlyOwner() {
        require(!_isExcludedFromReward[account], "Account is already excluded");
        _excludeFromReward(account);
    }

    function _includeInReward(address account) private {
        if (!_isExcludedFromReward[account]) return;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcludedFromReward[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcludedFromReward[account], "Account is already excluded");
        _includeInReward(account);
    }

	function setTradingEnabled(bool _tradingEnabled) public onlyOwner {
		tradingEnabled = _tradingEnabled;
		emit TradingStatus(tradingEnabled);
	}

	function setNoFeeForTransfert(bool _noFeeForTransfert) public onlyOwner {
		noFeeForTransfert = _noFeeForTransfert;
	}

	function setLimitSellByTimeUnit(bool _limitSellByTimeUnit,uint256 value) public onlyOwner {
		if (value == 0) {
			oneSellEveryX = 0;
			limitSellByTimeUnit = false;
		} else {
			oneSellEveryX = value;
			limitSellByTimeUnit = _limitSellByTimeUnit;
		}
	}
	
	function setExcludedFromFee(address account,bool value) public onlyOwner {
		_isExcludedFromFee[account] = value;
	}
	
	function setApplyTransferFee(address account,bool value) public onlyOwner {
		_applyFeeFor[account] = value;
	}

	function setTradingWhitelist(address account,bool value) public onlyOwner {
		_isTradingWhiteListed[account] = value;
	}

	function setSellWhitelist(address account,bool value) public onlyOwner {
		_isSellWhiteListed[account] = value;
	}

	function setMaxPriceImpactForSell(uint256 maxPriceImpact) public onlyOwner {
		_maxPriceImpactForSell = maxPriceImpact;
	}

	function setMaxPriceImpactForBuy(uint256 maxPriceImpact) public onlyOwner {
		_maxPriceImpactForBuy = maxPriceImpact;
	}

	function setMaxPriceImpactForSwapAndLiquify(uint256 maxPriceImpact) public onlyOwner {
		_maxPriceImpactForSwapAndLiquify = maxPriceImpact;
	}

	function setExcludeFromMaxTx(address _address, bool value) public onlyOwner {
		_isExcludedFromMaxTx[_address] = value;
	}
	
	function setTaxFeePercent(uint256 taxFee) public onlyOwner {
		_previousTaxFee = _taxFee;
		_taxFee = taxFee;
		emit TaxFee(_taxFee,_previousTaxFee);
	}

	function setLiquidityFeePercent(uint256 liquidityFee) public onlyOwner {
		_previousLiquidityFee = _liquidityFee;
		_liquidityFee = liquidityFee;
		emit LiquidityFee(_liquidityFee,_previousLiquidityFee);
	}

	function setMarketingFeePercent(uint256 marketingFee) public onlyOwner {
		_previousMarketingFee = _marketingFee;
		_marketingFee = marketingFee;
		emit MarketingFee(_marketingFee,_previousMarketingFee);
	}

	function setBuyBackFeePercent(uint256 buyBackFee) public onlyOwner {
		_previousBuyBackFee = _buyBackFee;
		_buyBackFee = buyBackFee;
		emit BuyBackFee(_buyBackFee,_previousBuyBackFee);
	}

	function setMinBNBToSendToMarketingWallet(uint256 value) public onlyOwner {
		_minBNBToSendToMarketingWallet = value;
	}

	function setMinBNBToBuyBack(uint256 value) public onlyOwner {
		_minBNBToBuyBack = value;
	}

	function setSwapAndLiquifyEnabled(bool _swapAndLiquifyEnabled) public onlyOwner {
		swapAndLiquifyEnabled = _swapAndLiquifyEnabled;
		emit SwapAndLiquifyEnabledUpdated(_swapAndLiquifyEnabled);
	}
	
	function lockAccountForHours(address account,uint256 _hours) public onlyOwner {
		_lockAccount[account] = block.timestamp + (_hours * 1 hours);
		emit LockAccount(account,_lockAccount[account]);
	}
	
	function lockAccountForMinutes(address account,uint256 _minutes) public onlyOwner {
		_lockAccount[account] = block.timestamp + (_minutes * 1 minutes);
		emit LockAccount(account,_lockAccount[account]);
	}

	function setNextAllowedTransferToPancake(address account,uint256 time) public onlyOwner {
		_nextAllowedTransferToPancake[account] = time;
	}
	
	function whitelistAccount(address account, bool value) public onlyOwner {
		_isSellWhiteListed[account] = value;
		_isTradingWhiteListed[account] = value;
		_isExcludedFromMaxTx[account] = value;
		_isExcludedFromFee[account] = value;
	}

	function setMarketingWallet(address wallet) public onlyOwner {
		address oldWallet = marketingWallet;
		marketingWallet = wallet;
		setAuthorizedCallers(marketingWallet,true);
		_isSellWhiteListed[marketingWallet] = true;
		_isTradingWhiteListed[marketingWallet] = true;
		_isExcludedFromMaxTx[marketingWallet] = true;
		_isExcludedFromFee[marketingWallet] = true;
		_lockAccount[marketingWallet] = 0;
		if (oldWallet != owner() && oldWallet != marketingWallet) {
			_isSellWhiteListed[oldWallet] = false;
			_isTradingWhiteListed[oldWallet] = false;
			_isExcludedFromMaxTx[oldWallet] = false;
			_isExcludedFromFee[oldWallet] = false;
			_lockAccount[oldWallet] = 0;
			setAuthorizedCallers(oldWallet,false);
		}
		emit NewMarketingWallet(oldWallet,marketingWallet);
	}

	function setBuyBackWallet(address wallet) public onlyOwner {
		address oldWallet = buyBackWallet;
		buyBackWallet = wallet;
		setAuthorizedCallers(buyBackWallet,true);
		_isSellWhiteListed[buyBackWallet] = true;
		_isTradingWhiteListed[buyBackWallet] = true;
		_isExcludedFromMaxTx[buyBackWallet] = true;
		_isExcludedFromFee[buyBackWallet] = true;
		_lockAccount[buyBackWallet] = 0;
		if (oldWallet != owner() && oldWallet != buyBackWallet) {
			_isSellWhiteListed[oldWallet] = false;
			_isTradingWhiteListed[oldWallet] = false;
			_isExcludedFromMaxTx[oldWallet] = false;
			_isExcludedFromFee[oldWallet] = false;
			_lockAccount[oldWallet] = 0;
			setAuthorizedCallers(oldWallet,false);
		}
		emit NewBuyBackWallet(oldWallet,buyBackWallet);
	}

	function setLiquidityWallet(address wallet) public onlyOwner {
		address oldWallet = liquidityWallet;
		liquidityWallet = wallet;
		_isSellWhiteListed[liquidityWallet] = true;
		_isTradingWhiteListed[liquidityWallet] = true;
		_isExcludedFromMaxTx[liquidityWallet] = true;
		_isExcludedFromFee[liquidityWallet] = true;
		_lockAccount[liquidityWallet] = 0;
		if (oldWallet != owner() && oldWallet != liquidityWallet) {
			_isSellWhiteListed[oldWallet] = false;
			_isTradingWhiteListed[oldWallet] = false;
			_isExcludedFromMaxTx[oldWallet] = false;
			_isExcludedFromFee[oldWallet] = false;
			_lockAccount[oldWallet] = 0;
		}
		emit NewLiquidityWallet(oldWallet,liquidityWallet);
	}

	// TOKEN IMPL
	function reflectionFromToken(uint256 tAmount, bool deductTransferFee) private view returns (uint256) {
		require(tAmount <= _tTotal, "Amount must be less than supply");
		if (!deductTransferFee) {
			(uint256 rAmount,,,,,,,) = _getValues(tAmount);
			return rAmount;
		} else {
			(,uint256 rTransferAmount,,,,,,) = _getValues(tAmount);
			return rTransferAmount;
		}
	}

	function tokenFromReflection(uint256 rAmount) private view returns (uint256) {
		require(rAmount <= _rTotal, "Amount must be less than total reflections");
		uint256 currentRate = _getRate();
		return rAmount.div(currentRate);
	}

	//to receive BNB from pancakeRouter when swapping
	receive() external payable {}

	function _reflectFee(uint256 rFee, uint256 tFee) private {
		_rTotal = _rTotal.sub(rFee);
		_tFeeTotal = _tFeeTotal.add(tFee);
	}
	
	struct ValueInfo {
		uint256 tTransferAmount;
		uint256 tFee;
		uint256 tLiquidity;
		uint256 tMarketing;
		uint256 tBuyBack;
	}

	function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
		ValueInfo memory info = _getTValues(tAmount);
		(uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, info.tFee,info.tLiquidity, info.tMarketing, info.tBuyBack, _getRate());
		return (rAmount, rTransferAmount, rFee, info.tTransferAmount, info.tFee, info.tLiquidity, info.tMarketing, info.tBuyBack);
	}

	function _getTValues(uint256 tAmount) private view returns (ValueInfo memory) {
		ValueInfo memory info;
		info.tFee = calculateTaxFee(tAmount);
		info.tLiquidity = calculateLiquidityFee(tAmount);
		info.tMarketing = calculateMarketingFee(tAmount);
		info.tBuyBack = calculateBuyBackFee(tAmount);
		info.tTransferAmount = tAmount.sub(info.tFee).sub(info.tLiquidity).sub(info.tMarketing).sub(info.tBuyBack);
		return info;
	}

	function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 tMarketing, uint256 tBuyBack, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
		uint256 rAmount = tAmount.mul(currentRate);
		uint256 rFee = tFee.mul(currentRate);
		uint256 rLiquidity = tLiquidity.mul(currentRate);
		uint256 rMarketing = tMarketing.mul(currentRate);
		uint256 rBuyBack = tBuyBack.mul(currentRate);
		uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity).sub(rMarketing).sub(rBuyBack);
		return (rAmount, rTransferAmount, rFee);
	}

	function _getRate() private view returns (uint256) {
		(uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
		return rSupply.div(tSupply);
	}

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
       for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

	function _takeLiquidity(uint256 tLiquidity) private {
		uint256 currentRate = _getRate();
		uint256 rLiquidity = tLiquidity.mul(currentRate);
		_rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if (_isExcludedFromReward[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
	}

	function _takeMarketing(uint256 tMarketing) private {
		uint256 currentRate = _getRate();
		uint256 rMarketing = tMarketing.mul(currentRate);
		_rOwned[address(this)] = _rOwned[address(this)].add(rMarketing);
        if (_isExcludedFromReward[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tMarketing);
	}
	
	function _takeBuyBack(uint256 tBuyBack) private {
		uint256 currentRate = _getRate();
		uint256 rBuyBack = tBuyBack.mul(currentRate);
		_rOwned[address(this)] = _rOwned[address(this)].add(rBuyBack);
        if (_isExcludedFromReward[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tBuyBack);
	}

	function calculateTaxFee(uint256 _amount) private view returns (uint256) {
		return _amount.mul(_taxFee).div(
			10 ** 2
		);
	}

	function calculateLiquidityFee(uint256 _amount) private view returns (uint256) {
		return _amount.mul(_liquidityFee).div(
			10 ** 2
		);
	}

	function calculateMarketingFee(uint256 _amount) private view returns (uint256) {
		return _amount.mul(_marketingFee).div(
			10 ** 2
		);
	}

	function calculateBuyBackFee(uint256 _amount) private view returns (uint256) {
		return _amount.mul(_buyBackFee).div(
			10 ** 2
		);
	}

	function removeAllFee() private {
		if (_taxFee == 0 && _liquidityFee == 0 && _marketingFee == 0) return;
		_previousTaxFee = _taxFee;
		_previousLiquidityFee = _liquidityFee;
		_previousMarketingFee = _marketingFee;
		_previousBuyBackFee = _buyBackFee;
		_taxFee = 0;
		_liquidityFee = 0;
		_marketingFee = 0;
		_buyBackFee = 0;
	}

	function restoreAllFee() private {
		_taxFee = _previousTaxFee;
		_liquidityFee = _previousLiquidityFee;
		_marketingFee = _previousMarketingFee;
		_buyBackFee = _previousBuyBackFee;
	}

	function _approve(address owner, address spender, uint256 amount) private {
		require(owner != address(0), "BEP20: approve from the zero address");
		require(spender != address(0), "BEP20: approve to the zero address");

		_allowances[owner][spender] = amount;
		emit Approval(owner, spender, amount);
	}

	function computePriceImpact(uint256 amount) public view returns (uint256) {
		uint256 startBnbs = IBEP20(addressWBNB).balanceOf(address(pancakePair));
		uint256 startTokens = IBEP20(address(this)).balanceOf(address(pancakePair));
		uint256 startPoolValue = startBnbs.mul(startTokens);
		uint256 endTokens = startTokens.add(amount);
		if (endTokens == 0) return 1000000;
		uint256 endBnb = startPoolValue.div(endTokens);
		uint256 deltaBnbs = startBnbs.sub(endBnb);
		if (startBnbs == 0) return 1000000;
		return Utils.mulScale(deltaBnbs,1000000,uint128(startBnbs));
	}

	function computeAmountFromPriceImpact(uint256 priceImpact) public view returns (uint256) {
		uint256 startBnbs = IBEP20(addressWBNB).balanceOf(address(pancakePair));
		if (startBnbs == 0) return 0;
		uint256 startTokens = IBEP20(address(this)).balanceOf(address(pancakePair));
		uint256 startPoolValue = startBnbs.mul(startTokens);
		uint256 deltaBnbs = priceImpact.mul(startBnbs).div(1000000);
		uint256 endBnb = startBnbs.sub(deltaBnbs);
		if (endBnb == 0) return 0;
		uint256 endTokens = startPoolValue.div(endBnb);
		return endTokens.sub(startTokens);
	}

	function _transfer(
		address from,
		address to,
		uint256 amount
	) private {
		require(amount > 0, "Transfer amount must be greater than zero");

		if (!tradingEnabled && (!(_isTradingWhiteListed[from] || _isTradingWhiteListed[to]))) {
			require(tradingEnabled, "Trading is not enabled yet");
		}
		
		// cannot transfer if account is locked
		if (_lockAccount[from] > 0) {
			require(_lockAccount[from] <= block.timestamp, "Error: transfer from this account is locked until lock time");
		}
		
		uint256 priceImpact = computePriceImpact(amount);
		bool transferring = !(_applyFeeFor[from]) && !(_applyFeeFor[to]);
		bool hasSellLimit = limitSellByTimeUnit && !_isSellWhiteListed[from] && oneSellEveryX != 0;
		if (_maxPriceImpactForSell > 0 && !_isExcludedFromMaxTx[from] && _applyFeeFor[to]) {
			require(priceImpact <= _maxPriceImpactForSell,"Price impact too high for selling !");
		}
		if (_maxPriceImpactForBuy > 0 && !_isExcludedFromMaxTx[to] && _applyFeeFor[from]) {
			require(priceImpact <= _maxPriceImpactForBuy,"Price impact too high for buying !");
		}
		if (hasSellLimit) {
			if (transferring) {
				_nextHolder[from] = to;
				_previousHolder[to] = from;
			}
			if (!(_applyFeeFor[from]) && _previousHolder[from] != address(0))  {
				// if previous holder just sold, apply limit to this current account, if limit is lower.
				if (_nextAllowedTransferToPancake[_previousHolder[from]] > _nextAllowedTransferToPancake[from]) {
					_nextAllowedTransferToPancake[from] = _nextAllowedTransferToPancake[_previousHolder[from]];
				}
				if (_nextAllowedTransferToPancakePriceImpact[_previousHolder[from]] > _nextAllowedTransferToPancakePriceImpact[from]) {
					_nextAllowedTransferToPancakePriceImpact[from] = _nextAllowedTransferToPancakePriceImpact[_previousHolder[from]];
				}
			}
			if (!(_applyFeeFor[from]) && _nextHolder[from] != address(0))  {
				// if next holder just sold, apply limit to this current account, if limit is lower.
				if (_nextAllowedTransferToPancake[_nextHolder[from]] > _nextAllowedTransferToPancake[from]) {
					_nextAllowedTransferToPancake[from] = _nextAllowedTransferToPancake[_nextHolder[from]];
				}
				if (_nextAllowedTransferToPancakePriceImpact[_nextHolder[from]] > _nextAllowedTransferToPancakePriceImpact[from]) {
					_nextAllowedTransferToPancakePriceImpact[from] = _nextAllowedTransferToPancakePriceImpact[_nextHolder[from]];
				}
			}
		}
		if (hasSellLimit && _applyFeeFor[to]) {
			if (_nextAllowedTransferToPancake[from] != 0) {
				if (_nextAllowedTransferToPancake[from] > block.timestamp) {
					require(_nextAllowedTransferToPancakePriceImpact[from].add(priceImpact) < _maxPriceImpactForSell, "Error: One sell transaction every oneSellEveryX time for max price impact");
					_nextAllowedTransferToPancakePriceImpact[from] = _nextAllowedTransferToPancakePriceImpact[from].add(priceImpact);
				} else {
					_nextAllowedTransferToPancake[from] = block.timestamp + oneSellEveryX;
					_nextAllowedTransferToPancakePriceImpact[from] = priceImpact;
				}
			} else {
				_nextAllowedTransferToPancake[from] = block.timestamp + oneSellEveryX;
				_nextAllowedTransferToPancakePriceImpact[from] = priceImpact;
			}
		}
		
		// swap and liquify
		swapAndLiquify(from, to);
		
		if (_applyFeeFor[from]) {
			_totalCountBuy = _totalCountBuy.add(1);
		}
		if (_applyFeeFor[to]) {
			_totalCountSell = _totalCountSell.add(1);
		}

		//indicates if fee should be deducted from transfer
		bool takeFee = true;

		//if any account belongs to _isExcludedFromFee account
		// or if it is a simple transfert and not from or to pancakeswap  then remove the fee
		if (_isExcludedFromFee[from] || _isExcludedFromFee[to] || (noFeeForTransfert && !_applyFeeFor[to] && !_applyFeeFor[from])) {
			takeFee = false;
		}

		//transfer amount, it will take tax, liquidity fee, marketing fee
		_tokenTransfer(from, to, amount, takeFee);
	}

	//this method is responsible for taking all fee, if takeFee is true
	function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
		if (!takeFee) {
			removeAllFee();
		}
        if (_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
		if (!takeFee) {
			restoreAllFee();
		}
	}

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
		(uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tMarketing, uint256 tBuyBack) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
		_takeMarketing(tMarketing);
		_takeBuyBack(tBuyBack);
		_reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }
	

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
		(uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tMarketing, uint256 tBuyBack) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
		_takeMarketing(tMarketing);
		_takeBuyBack(tBuyBack);
		_reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
		(uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tMarketing, uint256 tBuyBack) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
		_takeMarketing(tMarketing);
		_takeBuyBack(tBuyBack);
		_reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

	function _transferStandard(address sender, address recipient, uint256 tAmount) private {
		(uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity, uint256 tMarketing, uint256 tBuyBack) = _getValues(tAmount);
		_rOwned[sender] = _rOwned[sender].sub(rAmount);
		_rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
		_takeLiquidity(tLiquidity);
		_takeMarketing(tMarketing);
		_takeBuyBack(tBuyBack);
		_reflectFee(rFee, tFee);
		emit Transfer(sender, recipient, tTransferAmount);
	}

	// SWAP AND ADD TO LP
	function swapAndLiquify(address from, address to) private {
		// is the token balance of this contract address over the min number of
		// tokens that we need to initiate a swap + liquidity lock?
		// also, don't get caught in a circular liquidity event.
		uint256 contractTokenBalance = balanceOf(address(this));
		uint256 _maxToSell = computeAmountFromPriceImpact(_maxPriceImpactForSwapAndLiquify);
		if (_maxToSell == 0) {
			return;
		}
		bool swapPossible = swapAndLiquifyEnabled && !inSwapAndLiquify && (contractTokenBalance >= _maxToSell) && (!(from == address(this) && to == address(pancakePair)));
		bool notBuyPair = !_applyFeeFor[from];
		if (
			swapPossible &&
			notBuyPair
		) {
			// only sell for _maxToSell
			swapAndLiquify(_maxToSell);
		}
	}

	function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
		if (_liquidityFee == 0 && _marketingFee == 0 && _buyBackFee == 0) return;
		uint256 _100percent = _liquidityFee.add(_marketingFee).add(_buyBackFee);
		uint256 marketingTokens = Utils.mulScale(contractTokenBalance,_marketingFee,uint128(_100percent));
		uint256 buyBackTokens = Utils.mulScale(contractTokenBalance,_buyBackFee,uint128(_100percent));
		uint256 liquidityTokens = contractTokenBalance.sub(marketingTokens).sub(buyBackTokens);

		uint256 halfTokensForLiquidity = liquidityTokens.div(2);
		uint256 tokenAmountToBeSwapped = halfTokensForLiquidity.add(marketingTokens).add(buyBackTokens);

		uint256 initialBalance = address(this).balance;
		Utils.swapTokensForEth(address(pancakeRouter), tokenAmountToBeSwapped);
		uint256 deltaBalance = address(this).balance.sub(initialBalance);

		uint256 deltaBalanceMarketing = Utils.mulScale(deltaBalance,_marketingFee,uint128(_100percent));
		uint256 deltaBalanceBuyBack = Utils.mulScale(deltaBalance,_buyBackFee,uint128(_100percent));
		uint256 deltaBalanceLiquidity = deltaBalance.sub(deltaBalanceMarketing).sub(deltaBalanceBuyBack);
		// Add liquidity.
		Utils.addLiquidity(address(pancakeRouter), liquidityWallet, halfTokensForLiquidity, deltaBalanceLiquidity);
		emit SwapAndLiquify(halfTokensForLiquidity, deltaBalanceLiquidity);
		emit SwapForMarketing(marketingTokens, deltaBalanceMarketing);
		_marketingBNB = _marketingBNB.add(deltaBalanceMarketing);
		_buyBackBNB = _buyBackBNB.add(deltaBalanceBuyBack);
		// enough BNB ? send to marketing wallet.
		if (_marketingBNB >= _minBNBToSendToMarketingWallet) {
			_sendBNBTo(marketingWallet,_marketingBNB);
			_marketingBNB = 0;
		}
		// enough BNB ? buy back token.
		if (_buyBackBNB >= _minBNBToBuyBack) {
			_sendBNBTo(buyBackWallet,_marketingBNB);
			_buyBackBNB = 0;
		}
	}
	
	function activateContract() public onlyOwner {
		// exclude owner and this contract from fee
		_isExcludedFromFee[owner()] = true;
		_isExcludedFromFee[address(this)] = true;
		_isExcludedFromFee[address(0x000000000000000000000000000000000000dEaD)] = true;
		_isExcludedFromFee[address(0)] = true;
		// Trading whitelisted
		_isTradingWhiteListed[owner()] = true;
		_isTradingWhiteListed[address(this)] = true;
		// sell whitelist
		_isSellWhiteListed[owner()] = true;
		_isSellWhiteListed[address(this)] = true;
		// include pancake pair and pancake router in transfert fee:
		_applyFeeFor[address(pancakeRouter)] = true;
		_applyFeeFor[address(pancakePair)] = true;
		// exclude from max tx
		_isExcludedFromMaxTx[owner()] = true;
		_isExcludedFromMaxTx[address(this)] = true;
		_isExcludedFromMaxTx[address(0x000000000000000000000000000000000000dEaD)] = true;
		_isExcludedFromMaxTx[address(0)] = true;
		// exclue from reward
		_excludeFromReward(owner());
		_excludeFromReward(address(this));
		//
		setSwapAndLiquifyEnabled(false);
		setTradingEnabled(false);
		setLimitSellByTimeUnit(true, 2 hours);
		setNoFeeForTransfert(true);
		setTaxFeePercent(2);
		setLiquidityFeePercent(2);
		setMarketingFeePercent(2);
		setBuyBackFeePercent(0);
		setMaxPriceImpactForBuy(80000);
		setMaxPriceImpactForSell(20000);
		setMaxPriceImpactForSwapAndLiquify(20000);
		marketingWallet = owner();
		buyBackWallet = owner();
		liquidityWallet = address(0x000000000000000000000000000000000000dEaD);
		// approve contract
		_approve(address(this), address(pancakeRouter), 2 ** 256 - 1);
	}

	// force a swap and liquify
	function forceSwapAndLiquify() external nonReentrant onlyOwner {
		swapAndLiquify(msg.sender,msg.sender);
	}

	// RETRIEVE FUND FUNCTIONS
	/**
	 * Retrieve BNB from contract and send to marketing wallet
	 */
	function _sendBNBTo(address account,uint256 amount) private {
		uint256 toRetrieve = address(this).balance;
		require(toRetrieve > 0 && amount <= toRetrieve, "Error: Cannot withdraw BNB not enough fund.");
		if (amount == 0) {
			amount = toRetrieve;
		}
		(bool sent,) = address(account).call{value : amount}("");
		require(sent, "Error: Cannot withdraw BNB");
		emit SentBNBSuccessfully(msg.sender, account, amount);
	}

	function sendBNBTo(address account,uint256 amount) external nonReentrant onlyOwner {
		_sendBNBTo(account,amount);
		// reset counters on withdraw
		if (amount >= _marketingBNB) {
			amount = amount.sub(_marketingBNB);
			_marketingBNB = 0;
		}
		if (amount >= _buyBackBNB) {
			amount = amount.sub(_buyBackBNB);
			_buyBackBNB = 0;
		}
	}

	/**
	 * Retrieve Token located at tokenAddress from contract and send to marketing wallet
	 */
	function _sendTokensTo(address account,address tokenAddress,uint256 amount) private {
		uint256 toRetrieve = IBEP20(tokenAddress).balanceOf(address(this));
		require(toRetrieve > 0 && amount <= toRetrieve, "Error: Cannot withdraw TOKEN not enough fund.");
		if (amount == 0) {
			amount = toRetrieve;
		}
		bool sent = IBEP20(tokenAddress).transfer(account,amount);
		require(sent, "Error: Cannot withdraw TOKEN");
		emit SentTokensSuccessfully(tokenAddress,msg.sender, account, amount);
	}

	function sendTokensTo(address account,address tokenAddress,uint256 amount) external nonReentrant onlyOwner {
		_sendTokensTo(account,tokenAddress,amount);
	}
}

