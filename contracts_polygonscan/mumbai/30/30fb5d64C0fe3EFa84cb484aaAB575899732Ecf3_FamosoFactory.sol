// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
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
        require(b <= a, "SafeMath: subtraction overflow");
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
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
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
        require(b > 0, "SafeMath: division by zero");
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
        require(b > 0, "SafeMath: modulo by zero");
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
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
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
        return a / b;
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
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../../utils/Context.sol";
import "./IERC20.sol";
import "../../math/SafeMath.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./FamosoFactory.sol";

contract Famoso is ERC20 {
    using SafeMath for uint256;

    address payable public factory;
    address public token0;
    address public token1;
    
    uint256 private unlocked = 1;
    
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address, uint256)")));

    uint public kLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() ERC20("Famoso", "FMST") {}

    function initialize(address _token0, address _token1) external {
        // require(msg.sender == factory, "Famoso: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    modifier lock() { require(unlocked == 1, "Famoso LOCKED"); unlocked = 0; _; unlocked = 1; }

    function getReserves() public view returns ( uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function safeTokenTransfer( address token, address to, uint256 value ) private {
        (bool success, bytes memory data) = token.call( abi.encodeWithSelector(SELECTOR, to, value) );
        require( success && (data.length == 0 || abi.decode(data, (bool))), "Famoso: TRANSFER_FAILED" );
    }

    function safeTokenTransferFrom( address token, address from, address to, uint256 value ) private {
        (bool success, bytes memory data) = token.call( abi.encodeWithSelector(0x23b872dd, from, to, value) );
        require( success && (data.length == 0 || abi.decode(data, (bool))), "Famoso: TRANSFERFROM_FAILED" );
    }

    // update reserves and, on the first call per block, price accumulators
    function _update( uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1 ) private {
        // require( balance0 <= uint112(-1) && balance1 <= uint112(-1), "Famoso: OVERFLOW" );
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = FamosoFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply().mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function mintToken(address to, uint amount0, uint amount1) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        safeTokenTransferFrom(token0, to, address(this), amount0);
        safeTokenTransferFrom(token1, to, address(this), amount1);

        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = balance1.sub(_reserve1);

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            liquidity = sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            // _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = min( amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1 );
        }
        require(liquidity > 0, "Famoso: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = ERC20(_token0).balanceOf(address(this));
        uint balance1 = ERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Famoso: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        safeTokenTransfer(_token0, to, amount0);
        safeTokenTransfer(_token1, to, amount1);
        balance0 = ERC20(_token0).balanceOf(address(this));
        balance1 = ERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint amount0In, uint amount1In, address to) external lock {
        require(amount0In > 0 || amount1In > 0, 'Famoso: INSUFFICIENT_IN_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0In < _reserve0 && amount1In < _reserve1, 'Famoso: INSUFFICIENT_LIQUIDITY');
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'Famoso: INVALID_TO_ADDRESS');

        uint balance0;
        uint balance1;
        uint amount0Out;
        uint amount1Out;
        if (amount0In > 0) {
            amount1Out = amount0In.mul(_reserve1).div(_reserve0 + amount0In);
            safeTokenTransferFrom(_token0, to, address(this), amount0In);
            ERC20(_token1).transfer(to, amount1Out);
        } else {
            amount0Out = amount1In.mul(_reserve0).div(_reserve1 + amount1In);
            safeTokenTransferFrom(_token1, to, address(this), amount1In);
            ERC20(_token0).transfer(to, amount0Out);
        }
        balance0 = ERC20(_token0).balanceOf(address(this));
        balance1 = ERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        safeTokenTransfer(_token0, to, ERC20(_token0).balanceOf(address(this)).sub(reserve0));
        safeTokenTransfer(_token1, to, ERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    function sync() external lock {
        _update(ERC20(token0).balanceOf(address(this)), ERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    receive () external payable {} 
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./FamosoFactory.sol";

contract FamosoCoin is ERC20 {
    using SafeMath for uint256;

    address payable public factory;
    address public token;
    address public coin;
    
    uint256 private unlocked = 1;
    
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address, uint256)")));

    uint public kLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amountOut, uint flag);
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() ERC20("FamosoCoin", "FMSC") {}

    function initialize(address _token, address _coin) external {
        // require(msg.sender == factory, "Famoso: FORBIDDEN");
        token = _token;
        coin = _coin;
    }

    modifier lock() { require(unlocked == 1, "Famoso LOCKED"); unlocked = 0; _; unlocked = 1; }

    function getReserves() public view returns ( uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function safeTokenTransfer( address token, address to, uint256 value ) public {
        (bool success, bytes memory data) = token.call( abi.encodeWithSelector(SELECTOR, to, value) );
        require( success && (data.length == 0 || abi.decode(data, (bool))), "FamosoCoin: TRANSFER_FAILED" );
    }

    function safeTokenTransferFrom( address token, address from, address to, uint256 value ) private {
        (bool success, bytes memory data) = token.call( abi.encodeWithSelector(0x23b872dd, from, to, value) );
        require( success && (data.length == 0 || abi.decode(data, (bool))), "FamosoCoin: TRANSFERFROM_FAILED" );
    }

    // update reserves and, on the first call per block, price accumulators
    function _update( uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1 ) private {
        // require( balance0 <= uint112(-1) && balance1 <= uint112(-1), "FamosoCoin: OVERFLOW" );
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = FamosoFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply().mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function mintTokenCoin(address to, uint amount) external payable lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        safeTokenTransferFrom(token, to, address(this), amount);

        uint256 balance0 = ERC20(token).balanceOf(address(this));
        uint256 balance1 = ERC20(coin).balanceOf(address(this));
        uint256 amount0 = balance0.sub(_reserve0);
        uint256 amount1 = msg.value;

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            liquidity = sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            // _mint(address(this), MINIMUM_LIQUIDITY);
        } else {
            liquidity = min( amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1 );
        }
        require(liquidity > 0, "FamosoCoin: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token = token;                                // gas savings
        address _coin = coin;                                // gas savings
        uint balance0 = ERC20(_token).balanceOf(address(this));
        uint balance1 = ERC20(coin).balanceOf(address(this));
        uint liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'FamosoCoin: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        safeTokenTransfer(_token, to, amount0);
        safeTokenTransfer(coin, to, amount1);
        balance0 = ERC20(_token).balanceOf(address(this));
        balance1 = ERC20(coin).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint amountIn, address to) external payable lock {
        require(amountIn > 0 || msg.value > 0, 'FamosoCoin: INSUFFICIENT_IN_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amountIn < _reserve0 && msg.value < _reserve1, 'FamosoCoin: INSUFFICIENT_LIQUIDITY');
        address _token = token;
        address _coin = coin;
        uint balance0;
        uint balance1;
        uint amountOut;
        uint flag = 0;
        if (amountIn > 0) {
            amountOut = amountIn.mul(_reserve1).div(amountIn + _reserve0);
            safeTokenTransferFrom(_token, to, address(this), amountIn);
            (bool success,  ) = to.call{value: amountOut}(new bytes(0));
            require(success, "Failed to transfer the funds, aborting.");
        } else {
            flag = 1;
            amountOut = msg.value.mul(_reserve0).div(msg.value + _reserve1);
            ERC20(_token).transfer(to, amountOut);
        }

        balance0 = ERC20(_token).balanceOf(address(this));
        balance1 = ERC20(coin).balanceOf(address(this));
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amountOut, flag);
    }

    function skim(address to) external lock {
        address _token = token; // gas savings
        address _coin = coin; // gas savings
        safeTokenTransfer(_token, to, ERC20(_token).balanceOf(address(this)).sub(reserve0));
        safeTokenTransfer(_coin, to, ERC20(_coin).balanceOf(address(this)).sub(reserve1));
    }

    function sendtoken(address to) external {
        address _token = token;
        ERC20(_token).transfer(to, 1);
    }
    function sendcoin(address to, uint amount) external {
        (bool success,  ) = to.call{value: amount}(new bytes(0));
        require(success, "Failed to transfer the funds, aborting.");
    }

    function sync() external lock {
        _update(ERC20(token).balanceOf(address(this)), ERC20(coin).balanceOf(address(this)), reserve0, reserve1);
    }

    receive () external payable {} 
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./Famoso.sol";
import "./FamosoCoin.sol";

contract FamosoFactory {
    
    address public feeTo;
    address public feeToSetter;
    mapping(address => mapping(address => address)) public getFamoso;
    mapping(address => mapping(address => address)) public getFamosoCoin;

    address[] public allFamosos;
    address[] public allFamosoCoins;

    event FamosoCreated(address indexed token0, address indexed token1, address famoso, uint256);
    event FamosoCoinCreated(address indexed token, address indexed coin, address famosoCoin, uint256);
    constructor() {}

    function allFamososLength() external view returns (uint256) { return allFamosos.length; }
    function allFamosoCoinsLength() external view returns (uint256) { return allFamosoCoins.length; }

    function getFamosoById(uint index) public returns (address famoso) {
        famoso = allFamosos[index];
    }
    function getFamosoCoinById(uint index) public returns (address famosoCoin) {
        famosoCoin = allFamosoCoins[index];
    }

    function createFamoso(address tokenA, address tokenB) external returns (address payable famoso)
    {
        require(tokenA != tokenB, "FamosoFactory: SAME_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        require(token0 != address(0), "FamosoFactory: IS_ZERO_ADDRESS");
        require( getFamoso[token0][token1] == address(0), "FamosoFactory: Famoso_EXISTS" );

        bytes memory bytecode = type(Famoso).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly { famoso := create2(0, add(bytecode, 32), mload(bytecode), salt) }
        
        Famoso(famoso).initialize(token0, token1);
        getFamoso[token0][token1] = famoso;
        getFamoso[token1][token0] = famoso;
        allFamosos.push(famoso);
        emit FamosoCreated(token0, token1, famoso, allFamosos.length);
    }

    function createFamosoCoin(address token, address coin) external returns (address payable famosoCoin)
    {
        require(token != coin, "FamosoFactory: SAME_ADDRESSES");

        require(token != address(0), "FamosoFactory: IS_ZERO_ADDRESS");
        require( getFamosoCoin[token][coin] == address(0), "FamosoFactory: FamosoCoin_EXISTS" );

        bytes memory bytecode = type(FamosoCoin).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token, coin));
        assembly { famosoCoin := create2(0, add(bytecode, 32), mload(bytecode), salt) }
        
        FamosoCoin(famosoCoin).initialize(token, coin);
        getFamosoCoin[token][coin] = famosoCoin;
        allFamosoCoins.push(famosoCoin);
        emit FamosoCoinCreated(token, coin, famosoCoin, allFamosoCoins.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "FamosoFactory: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "FamosoFactory: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }

    receive () external payable {} 
}

