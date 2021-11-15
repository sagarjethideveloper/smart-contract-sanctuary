// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface AggregatorV3Interface {

  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

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

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

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
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
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

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
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
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

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

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

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

        _totalSupply += amount;
        _balances[account] += amount;
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

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

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

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
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

pragma solidity 0.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "./MedPingTeamMngt.sol";

contract MedPingCrowdSale  is ReentrancyGuard,MedPingTeamManagement{
    /**
    * @Legend: CrowdsalePeriodExtended = CPE
    * @Legend: CrowdsaleOperationFinished = COF
    */
    using SafeMath for uint256;
    IERC20 public _BUSDContract;
    AggregatorV3Interface internal BNBUSD;

    uint256 public _rate;
    uint256 public _tokensSold;
    uint256 public _weiRaisedBNB;
    uint256 public _weiRaisedBUSD;
    uint256  _tokensReamaining; 
    uint256 _crossDecimal = 10**8;
    
    bool private _finalized = false;
  
    
    // Crowdsale Stages
    enum CrowdsaleStage { PreSale,PrivateSale,PublicSale,Paused,Ended }
    // Default to presale stage
    CrowdsaleStage public stage = CrowdsaleStage.Paused;
    
    mapping(CrowdsaleStage=> mapping(address => uint256)) _contributions;
    mapping(CrowdsaleStage=> mapping(address => uint256)) _receiving;
    mapping(CrowdsaleStage=> uint256) public CrowdsaleStageBalance;
    
   
    
    /**
    * @dev EVENTS:
    */
    event COF();
    event CPE(uint256 oldEndTime, uint256 newEndTime);
    event BuyPing(
        address indexed _from,
        uint256 indexed _tokens,
        uint256  _value
    );
    
    /**
     * @dev Reverts if not in crowdsale time range.
     */
    modifier onlyWhileOpen {
        require(isOpen(), "Crowdsale: not open");
        _;
    }

    constructor(
                MedPingToken token,
                MedPingInvestorsVault vault,
                IERC20 _BUSD,
                uint256 startingTime,
                uint256 endingTime,
                address payable wallet,
                address payable DevMarketing,
                address payable TeamToken,
                address payable ListingLiquidity,
                address payable OperationsManagement
                )
    ReentrancyGuard()
    MedPingTeamManagement(DevMarketing,TeamToken,ListingLiquidity,OperationsManagement,token,vault)
    { 
        require(startingTime >= block.timestamp, "Crowdsale: start time is before current time");
        require(endingTime > startingTime, "Crowdsale: start time is invalid");
        admin =  payable (msg.sender);//assign an admin
        _tokenContract = token;//link to token contract 
        _BUSDContract = _BUSD; //link to token vault contract 
        _wallet = wallet;//token wallet 
        updateStage(4);//set default stage balance
        BNBUSD = AggregatorV3Interface(BNBUSD_Aggregator);
        _startTime = startingTime;//set periods management
        _endTime = endingTime;//set periods management
        _finalized = false;//set periods management
        
    }
    function participateBNB(uint80 _roundId) payable public onlyWhileOpen returns (bool){
        uint256 _numberOfTokens = _MedPingReceiving(msg.value,_roundId);
        _preValidateParticipation(msg.value, _numberOfTokens, msg.sender);
        //require that the transaction is successful 
        _processParticipationBNB(msg.sender, _numberOfTokens);
        _postParticipation(msg.sender,msg.value,_numberOfTokens);  

        emit BuyPing(msg.sender,_numberOfTokens,msg.value); 
        return true;
    }
    function participateBUSD(uint80 _roundId) public onlyWhileOpen returns(bool){
        require(_BUSDContract.allowance(msg.sender, address(this)) > 0);
        uint busdVal = _BUSDContract.allowance(msg.sender, address(this));
        uint bnbEquv = (busdVal.div(uint256(getBNBUSDPrice(_roundId)))).mul(_crossDecimal);
        uint256 _numberOfTokens = _MedPingReceiving(bnbEquv,_roundId);
        _preValidateParticipation(bnbEquv, _numberOfTokens, msg.sender);
        require(_BUSDContract.transferFrom(msg.sender, address(this), busdVal));
        _processParticipationBUSD(msg.sender, _numberOfTokens,busdVal);
        _postParticipation(msg.sender,bnbEquv,_numberOfTokens);
        emit BuyPing(msg.sender,_numberOfTokens,busdVal); 
       return true;
    }
    function _MedPingReceiving(uint256 _weiSent, uint80 _roundId) internal view returns (uint256 ){
        int _channelRate = 0;
        _channelRate  =  getBNBUSDPrice(_roundId);
        int _MedRate = int(_rate)/(_channelRate/int(_crossDecimal));
        uint256 _weiMedRate =  uint256((_MedRate * 10 **18 )/int(_crossDecimal));
        uint256 tempR = _weiSent.div(_weiMedRate);
        return tempR * 10 ** 18;
    }
    //sets the ICO Stage, rates  and the CrowdsaleStageBalance 
    function updateStage(uint _stage)public onlyOwner returns (bool){
       
         if(uint(CrowdsaleStage.PreSale) == _stage) {
          stage = CrowdsaleStage.PreSale;
          CrowdsaleStageBalance[stage]=12500000 * (10**18) ; //
          investorMinCap   = 0.1 * (10**18);
          investorMaxCap  = 1.5 * (10**18);
          _rate = 0.0095 * (10**8); //usd 
        }else if (uint(CrowdsaleStage.PrivateSale) == _stage) {
            emptyStageBalanceToBurnBucket();
         stage = CrowdsaleStage.PrivateSale;
          CrowdsaleStageBalance[stage]=37500000 * (10**18); //
          investorMinCap   = 0.2 * (10**18);
          investorMaxCap  = 5 * (10**18);
           _rate = 0.025 * (10**8); // usd
        }
        else if (uint(CrowdsaleStage.PublicSale) == _stage) {
            emptyStageBalanceToBurnBucket();
         stage = CrowdsaleStage.PublicSale;
          CrowdsaleStageBalance[stage]=20000000 * (10**18); //
          investorMinCap   = 0.1 * (10**18);
          investorMaxCap  = 5 * (10**18);
           _rate = 0.075 * (10**8); // usd
        }else if(uint(CrowdsaleStage.Paused) == _stage){
            stage = CrowdsaleStage.Paused;
            CrowdsaleStageBalance[stage]=0;
            _rate = 0; //0.00 eth
        }else if(uint(CrowdsaleStage.Ended) == _stage){
            emptyStageBalanceToBurnBucket();
            stage = CrowdsaleStage.Ended;
            CrowdsaleStageBalance[stage]=0;
            _rate = 0; //0.00 eth
        }
        return true;
    }
    function emptyStageBalanceToBurnBucket() internal {
        uint256 perviousBal = CrowdsaleStageBalance[stage];
        if(perviousBal > 0){
            
            require(_tokenContract.transfer(_tokenContract.getBurnBucket(), perviousBal),"crowdsale balance transfer failed");
        }
    }
    function getStageBalance() public view returns (uint256) {
        return CrowdsaleStageBalance[stage];
    }
    function getParticipantGivings(CrowdsaleStage _stage,address _participant) public view returns (uint256){
        return _contributions[_stage][_participant];
    }
    function getParticipantReceivings(CrowdsaleStage _stage,address _participant) public view returns (uint256){
        return _receiving[_stage][_participant];
    }
    function _updateParticipantBalance(address _participant, uint256 _giving,uint256 _numOfTokens) internal returns (bool){
        uint256 oldGivings = getParticipantGivings(stage,_participant);
        uint256 oldReceivings = getParticipantReceivings(stage,_participant);
        
        uint256 newGivings = oldGivings.add(_giving);
        uint256 newReceiving = oldReceivings.add(_numOfTokens);
        
        _contributions[stage][_participant] = newGivings;
        _receiving[stage][_participant] = newReceiving;
        return true;
    }
    function _isIndividualCapped(address _participant, uint256 _weiAmount)  internal view returns (bool){
        uint256 _oldGiving = getParticipantGivings(stage,_participant);
        uint256 _newGiving = _oldGiving.add(_weiAmount);
        require(_newGiving >= investorMinCap && _newGiving <= investorMaxCap);
        return true;
    }
    function _addToCrowdsaleStageBalance(uint256 amount)  internal{
        uint256 currentBal = getStageBalance();
        uint256 newBal = currentBal.add(amount);
        CrowdsaleStageBalance[stage]=newBal;
    }
    function _subFromCrowdsaleStageBalance(uint256 amount)  internal{
        uint256 currentBal = getStageBalance();
        uint256 newBal = currentBal.sub(amount);
        CrowdsaleStageBalance[stage]=newBal;
    }
    function _preValidateParticipation(uint256 _sentValue,uint256 _numberOfTokens, address _participant) internal view {
        //Require that contract has enough tokens 
        require(_tokenContract.balanceOf(address(this)) >= _numberOfTokens,'token requested not available');
        //require that participant giving is between the caped range per stage
        require(_isIndividualCapped(_participant,  _sentValue),'request not within the cap range');
    }
    function _processParticipationBNB(address recipient, uint256 amount) nonReentrant() internal{
        require( _forwardBNBFunds());
        require(_tokenContract.transfer(recipient, amount));
        _weiRaisedBNB += amount;
    }
    function _processParticipationBUSD(address recipient, uint256 amount,uint256 weiAmount) nonReentrant() internal{
        require( _forwardBUSDFunds(weiAmount));
        require(_tokenContract.transfer(recipient, amount));
        _weiRaisedBUSD += amount;
    }
    function _postParticipation(address _participant,uint256 amount , uint256 _numberOfTokens) nonReentrant() internal returns(bool){
        //record participant givings and receivings
        require(_updateParticipantBalance(_participant,amount,_numberOfTokens));
        //track number of tokens sold  and amount raised
        _tokensSold += _numberOfTokens;
        //subtract from crowdsale stage balance 
        _subFromCrowdsaleStageBalance(_numberOfTokens);
        //lock investments of initial investors 
       if(stage == CrowdsaleStage.PreSale){
            _tokenContract.addToLock(_numberOfTokens,0,_participant); 
        }
        if(stage == CrowdsaleStage.PrivateSale ){
            _tokenContract.addToLock(0,_numberOfTokens,_participant);
        }
        return true;
    }
    function releaseRistrictions () internal returns(bool) {
        require(_tokenContract.getFirstListingDate() != 1,"First listing date has to be set");
        _tokenContract.releaseTokenTransfer();
        return true;
    }
    function addFirstListingDate (uint256 _date) public onlyOwner() returns (bool){
        require(_tokenContract.setFirstListingDate(_date));
        return  true;
    }
    /**
     * Returns the BNBUSD latest price
     */
    function getBNBUSDPrice(uint80 roundId) public view returns (int) {
        (
            uint80 id, 
            int price,
            uint startedAt,
            uint timeStamp,
        ) = BNBUSD.getRoundData(roundId);
         require(timeStamp > 0, "Round not complete");
         require(block.timestamp <= timeStamp + 1 days);
        return price;
    }
    /**
    * @dev forwards funds to the sale Wallet
    */
    function _forwardBNBFunds() internal returns (bool){
        _wallet.transfer(msg.value);
        return true;
    }
    /**
    * @dev forwards funds to the sale Wallet
    */
    function _forwardBUSDFunds(uint256 weiAmount) internal returns (bool){
        _BUSDContract.transfer(_wallet,weiAmount);
        return true;
    }

    function startTime() public view returns (uint256) {
        return _startTime;
    }
    function endTime() public view returns (uint256) {
        return _endTime;
    }
    function isOpen() public view returns (bool) {
       require(block.timestamp >= _startTime && block.timestamp <= _endTime ,"Crowdsale: not opened");
       require(stage != CrowdsaleStage.Paused && stage != CrowdsaleStage.Ended,"Crowdsale: not opened");
       return true;
    }
    function hasClosed() public view returns (bool) {
        return block.timestamp > _endTime;
    }
    function extendTime(uint256 newEndTime) public onlyOwner {
        require(!hasClosed(), "Crowdsale: close already");
        require(newEndTime > _endTime, "Crowdsale: new endtime must be after current endtime");
        _endTime = newEndTime;
        emit CPE(_endTime, newEndTime);
    }
    function setCaps(uint256 _softCap, uint256 _hardCap) public onlyOwner returns (bool){
        medPingSoftCap = _softCap;
        medPingHardCap =_hardCap;
        return true;
    }
    function getSoftCap() public view returns (uint256){
        return medPingSoftCap;
    }
    function getHardCap() public view returns (uint256){
        return medPingHardCap;
    }
    function getInvestorMinCap() public view returns (uint256){
        return investorMinCap;
    }
    function getInvestorMaxCap() public view returns (uint256){
        return investorMaxCap;
    }
    function lockTeamVault() public onlyOwner() returns (bool){
        require(hasClosed(), "Crowdsale: has not ended");
        lockVault();
        return true;
    }
    function isFinalized() public view returns (bool) {
        return _finalized;
    }
    
    function finalize() public onlyOwner{
        require(vaultIsLocked(), "Vault not locked");
        require(!isFinalized(), "Crowdsale: already finalized");
        require(updateStage(4),"Crowdsale: should be marked as ended");
        require(releaseRistrictions(),"Unable to release Ristrictions");
        _finalized = true;
        uint256 tsupply = _tokenContract.totalSupply();
        uint256 crowdsaleTk = (tsupply.mul(20*100)).div(1000); //balance of crowdsale contract
        uint256 crowdsaleBal = crowdsaleTk - _tokensSold;
        //transfer remaining tokens back to admin account then update the balance sheet
         require(_tokenContract.updatecrowdsaleBal(crowdsaleBal,tsupply),"crowdsale balance update failed");
        emit COF();
    }
    
}

pragma solidity 0.8;


import "./MedPingToken.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol";

contract MedPingInvestorsVault is Ownable{
    MedPingToken _token;
    address _operator;

    struct VaultStruct {
        address _beneficiary;
        uint256 _balanceDue;
        uint256 _dueBy;
    }
    modifier onlyOperator {
        require(msg.sender == _operator, "You can not use this vault");
        _;
    }
    mapping(uint256 => VaultStruct) public VaultStructs; // This could be a mapping by address, but these numbered lockBoxes support possibility of multiple tranches per address
    mapping(address => uint256[]) public VaultKeys; 

    event LogVaultDeposit(address sender, uint256 amount, uint256 dueBy);   
    event LogVaultWithdrawal(address receiver, uint256 amount);

    constructor(MedPingToken token) Ownable() {
        _token = token;
    }

    function getOperator() public view returns (address){
        return _operator;
    }
    function setOperator(address operator) public onlyOwner returns (bool){
          _operator = operator;
          return true;
    }
    
    function createVaultKey(address beneficiary, uint identifier) internal view returns (uint256) {
         uint arrLen = VaultKeys[beneficiary].length;
         uint enc = arrLen * block.timestamp + identifier;
        return uint256( keccak256( abi.encodePacked(enc, block.difficulty)));
    }
    function getVaultKeys(address _beneficiary) public view returns (uint256[] memory) {
        return VaultKeys[_beneficiary];
    }

    function getVaultRecord(uint vaultKey) public view returns (address,uint,uint){
        VaultStruct storage v = VaultStructs[vaultKey];
        return (v._beneficiary,v._balanceDue,v._dueBy);
    }

    function recordShareToVault(address beneficiary, uint256 amount, uint256 dueBy,uint identifier) onlyOperator public returns(uint vaultKey) {
        uint key = createVaultKey(beneficiary,identifier);
        VaultStruct memory vault;
        vault._beneficiary = beneficiary;
        vault._balanceDue = amount;
        vault._dueBy = dueBy;
        VaultStructs[key] = vault;
        VaultKeys[beneficiary].push(key);
        emit LogVaultDeposit(msg.sender, amount, dueBy);
        return key;
    }

    function withdrawFromVault(uint vaultKey) public returns(bool success) {
        VaultStruct storage v = VaultStructs[vaultKey];
        require(v._beneficiary == msg.sender);
        require(v._dueBy <= block.timestamp);
        uint256 amount = v._balanceDue;
        v._balanceDue = 0;
        require(_token.transfer(msg.sender, amount));
        emit LogVaultWithdrawal(msg.sender, amount);
        return true;
    }    
}

pragma solidity ^ 0.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
contract MedPingLockBox is Ownable{
    
    using SafeMath for uint256;
    address crowdsale;
    address payable burnBucket;
    uint256 crowdsaleBal; // token remaining after crowdsale 
    uint256 burnBucketBal;
    uint256 lockStageGlobal;
    mapping(uint256 => mapping(address=>bool)) provisionsTrack;
    /** If false we are are in transfer lock up period.*/
    bool public released = false;
    uint256 firstListingDate = 1; //date for first exchange listing
    
    struct lockAllowance{uint256 presale_total; uint256 privatesale_total; uint256 allowance; uint256 spent; uint lockStage;}   
    mapping(address => lockAllowance) lockAllowances; //early investors allowance profile
    mapping(address => bool) earlyInvestors;//list of early investors

    uint256 [] provisionDates;
    uint256 [] burnDates;
    mapping(uint256=>bool) burnDateStatus;

    /** MODIFIER: Limits actions to only crowdsale.*/
    modifier onlyCrowdSale() {
        require(crowdsale == msg.sender,"you are not permitted to make transactions");
        _;
    }
    /** MODIFIER: Limits actions to only burner.*/
    modifier onlyBurner() {
        require(burnBucket == msg.sender,"you are not permitted to make transactions");
        _;
    }
    /** MODIFIER: Limits token transfer until the lockup period is over.*/
    modifier canTransfer() {
        if(!released) {
            require(crowdsale == msg.sender,"you are not permitted to make transactions");
        }
        _;
    }
    /** MODIFIER: Limits and manages early investors transfer.
    *check if is early investor and if within the 30days constraint
    */
    modifier investorChecks(uint256 _value,address _sender){
        if(isEarlyInvestor(_sender)){
            if((firstListingDate + (13 * 30 days)) > block.timestamp){ //is investor and within 13 months constraint 
                 lockAllowance storage lock = lockAllowances[_sender]; 
                 if(!isAllowanceProvisioned(_sender,lockStageGlobal)){
                    provisionLockAllownces(_sender,lock.lockStage); 
                 }
                 require(lock.allowance >= _value,"allocation lower than amount you want to spend"); //validate spending amount
                 require(updateLockAllownces(_value,_sender)); //update lock spent 
            }
        }
        _;
    }
    constructor()
    Ownable() {
    }
    /** Allows only the crowdsale address to relase the tokens into the wild */
    function releaseTokenTransfer() onlyCrowdSale() public {
            released = true;       
    }
    /**Set the crowdsale address. **/
    function setReleaser(address _crowdsale) onlyOwner() public { /**Set the crowdsale address. **/
        crowdsale = _crowdsale;
    }
    /**Set the burnBucket address. **/
    function setBurner(address payable _burnBucket) onlyOwner() public { /**Set the crowdsale address. **/
        burnBucket = _burnBucket;
    }
    function setFirstListingDate(uint256 _date) public onlyCrowdSale() returns(bool){
        firstListingDate = _date; 
        uint firstReleaseDate = _date + (3 * 30 days); //3months after the listing date
        provisionDates.push(firstReleaseDate);
        for (uint256 index = 1; index <= 10; index++) { //remaining released monthly after the first release
            uint nextReleaseDate = firstReleaseDate +(index * 30 days);
            provisionDates.push(nextReleaseDate);
            
             uint _burndate = firstReleaseDate + (index *(3 * 30 days));
            burnDates.push(_burndate);
            burnDateStatus[_burndate] = false;
        }
        return true; 
    }
    /** lock early investments per tokenomics.*/
    function addToLock(uint256 _presale_total,uint256 _privatesale_total, address _investor) public onlyCrowdSale(){
        //check if the early investor's address is not registered
        if(!earlyInvestors[_investor]){
            lockAllowance memory lock;
            lock.presale_total = _presale_total;
            lock.privatesale_total = _privatesale_total;
            lock.allowance = 0;
            lock.spent = 0;
            lockAllowances[_investor] = lock;
            earlyInvestors[_investor]=true;
        }else{
            lockAllowance storage lock = lockAllowances[_investor];
            lock.presale_total +=  _presale_total;
            lock.privatesale_total +=  _privatesale_total;
        }
    }
    function investorAllowance(address investor) public view returns (uint256 presale_total, uint256 privatesale_total,uint256 allowance,uint256 spent, uint lockStage){
        lockAllowance storage l =  lockAllowances[investor];
        return (l.presale_total,l.privatesale_total,l.allowance,l.spent,l.lockStage);
    }
     /** update allowance box.*/
    function updateLockAllownces(uint256 _spending, address _sender) internal returns (bool){
        lockAllowance storage lock = lockAllowances[_sender];
        lock.allowance -= _spending;
        lock.spent += _spending;
        return true; 
    }
     /** provision allowance box.*/
    function provisionLockAllownces(address _beneficiary,uint _lockStage) internal  returns (bool){
        require(block.timestamp >= provisionDates[0]);
        lockAllowance storage lock = lockAllowances[_beneficiary];
        uint256 presaleInital = lock.presale_total;
        uint256 privatesaleInital = lock.privatesale_total;
        require(_lockStage <= 10);
        require(lock.lockStage  == _lockStage);
        if(lock.lockStage < 1){//first allowance provision
            if(presaleInital > 0){
                presaleInital = (lock.presale_total.mul(20 *100)).div(10000);
                lock.allowance += presaleInital;
            }
            if(privatesaleInital > 0){
               privatesaleInital = (lock.privatesale_total.mul(30 *100)).div(10000);
               lock.allowance += privatesaleInital;
            }
                lock.presale_total -= presaleInital;
                lock.privatesale_total -= privatesaleInital;
                lock.lockStage = 1;
                provisionsTrack[lockStageGlobal][_beneficiary] = true;
        }else if(lock.lockStage >= 1){//following allowance provision
                if(presaleInital > 0){
                    presaleInital = (lock.presale_total.mul(10 *100)).div(10000);
                    lock.allowance += presaleInital;
                }
                if(privatesaleInital > 0){
                    privatesaleInital = (lock.privatesale_total.mul(10 *100)).div(10000);
                    lock.allowance += privatesaleInital; 
                }
                lock.lockStage += 1;
                provisionsTrack[lockStageGlobal][_beneficiary] = true;
        }
        return true; 
    }
    function isAllowanceProvisioned(address _beneficiary,uint _lockStageGlobal) public view returns (bool){
         return provisionsTrack[_lockStageGlobal][_beneficiary];
    }
    function updateLockStage() onlyBurner() public returns (bool){
         lockStageGlobal +=1;
         return true;
    }
    /** update token remaining after crowdsale .*/
    function updatecrowdsaleBal(uint256 _amount,uint256 _tSupply) public onlyCrowdSale() returns(bool success) {
        crowdsaleBal    += _amount;
        burnBucketBal   = (_tSupply.mul(5 *100)).div(10000) + crowdsaleBal; // 5% of total supply + crowdsale bal
        return true;
    }
    function isEarlyInvestor(address investor) public view returns(bool){
        if(earlyInvestors[investor]){
            return true; 
        }
        return false;
    }
    function getFirstListingDate() public view returns(uint256){
        return firstListingDate;
    }
    function getProvisionDates() public view returns (uint256 [] memory){
        return provisionDates;
    }
    function getCrowdsaleBal()  public view returns(uint256) {
        return crowdsaleBal;
    }
    function getBurnBucketBal()  public view returns(uint256) {
        return burnBucketBal;
    }
    function getBurnBucket()  public view returns(address payable) {
        return burnBucket;
    }
    function tokenBurnDates() public view returns (uint256 [] memory){
        return burnDates;
    }
    function isTokenBurntOnDate(uint256 _date) public view returns (bool){
        return burnDateStatus[_date];
    }
}

pragma solidity ^ 0.8; 
import "./MedPingToken.sol"; 
import "./MedPingInvestorsVault.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol";
contract MedPingTeamManagement is Ownable{
    uint  totalSup;
    MedPingInvestorsVault  _vaultContract;
    MedPingToken  _tokenContract;
    // Track investor contributions
    uint256  investorMinCap;
    uint256  investorMaxCap;
    uint256  medPingHardCap;
    uint256  medPingSoftCap;
    uint numParticipants;
    uint256 _startTime;
    uint256 _endTime;
      bool private _vaultLocked= false;
     /**
     * @dev ADDRESSES.
     */
    address BNBUSD_Aggregator = 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526;
    address payable admin;
    address payable  _wallet;
    address  public _DevMarketing;
    address  public _TeamToken;
    address  public _ListingLiquidity;
    address  public _OperationsManagement;

    struct TeamMembersLock{
        uint256 _percent;
        uint256 _releasePercent;
        uint256 _releaseInterval;
        uint256 _releaseStarts;
        uint256 _holdDuration;
        uint256 _vaultKeyId;
    }
    mapping(address => TeamMembersLock) public TeamMembersLockandEarlyInvestorsProfile;

    event VaultCreated(
        uint256 indexed _vaultKey,
        address indexed _beneficiary,
        uint256  releaseDay,
        uint256 amount
    );
    constructor (address payable DevMarketing,
                address payable TeamToken,
                address payable ListingLiquidity,
                address payable OperationsManagement,
                MedPingToken token,
                MedPingInvestorsVault vault
                )Ownable(){
        //set tokenomics
        _DevMarketing = DevMarketing;
        _TeamToken = TeamToken;
        _ListingLiquidity = ListingLiquidity;
        _OperationsManagement = OperationsManagement;
        _vaultContract = vault;//link to token vault contract 
        _tokenContract = token; //link to token contract 
        totalSup = _tokenContract.totalSupply();
    }

    function vaultIsLocked() public view returns (bool) {
        return _vaultLocked;
    }
    function calculatePercent(uint numerator, uint denominator) internal  pure returns (uint){
        return (denominator * (numerator * 100) ) /10000;
    }
    function setTeamMembersLock(address _beneficiary, uint percent,uint releaseInterval,  uint releasePercent, uint holdDuration, uint vaultKeyId,uint releaseStarts ) public onlyOwner returns (bool){
        TeamMembersLock memory lock;
        lock._percent = percent;
        lock._releasePercent = releasePercent;
        lock._releaseInterval = releaseInterval;
        lock._releaseStarts = releaseStarts;
        lock._holdDuration = holdDuration;
        lock._vaultKeyId = vaultKeyId;
        TeamMembersLockandEarlyInvestorsProfile[_beneficiary] = lock;
        return true;
    }
    function getTeamMembersLock(address _beneficiary) public view returns (uint256 percent,uint256 holdDuration,uint256 interval,uint256 releaserpercent,uint256 vualtKeyId,uint256 releaseStarts){
        TeamMembersLock storage lock = TeamMembersLockandEarlyInvestorsProfile[_beneficiary];
        return (lock._percent,lock._holdDuration,lock._releaseInterval,lock._releasePercent,lock._vaultKeyId,lock._releaseStarts);
    }
    function distributeToVault(address _beneficiary,uint listingDate) internal  returns (bool){
        uint releaseDay;
        TeamMembersLock storage lock = TeamMembersLockandEarlyInvestorsProfile[_beneficiary];
        uint totalFunds    = calculatePercent(lock._percent, totalSup);
        uint amountDue     = calculatePercent(lock._releasePercent, totalFunds);
        uint interval = lock._releaseInterval;
        uint startsFrom = lock._releaseStarts;
        uint hold = lock._holdDuration;
        for (uint i=interval; i <= hold; i += interval ){ 
                releaseDay = listingDate + (startsFrom + i) * 30 days; 
                uint key = _vaultContract.recordShareToVault(_beneficiary, amountDue , releaseDay,lock._vaultKeyId);
                emit VaultCreated(key,_beneficiary, releaseDay,amountDue);
        }
        return true;
    }
    function lockVault() internal {
        uint256 flistingDate = _tokenContract.getFirstListingDate();
        require(flistingDate != 1,"First listing date for token has to be set");
        //Dev&Marketing
        require(distributeToVault(_DevMarketing,flistingDate));
        // Team Token
        require(distributeToVault(_TeamToken,flistingDate));
        //Listing & Liquidity
        require(distributeToVault(_ListingLiquidity,flistingDate));
        //Operations & Management
        require(distributeToVault(_OperationsManagement,flistingDate));
         _vaultLocked = true;
    }

}

pragma solidity 0.8 ;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./MedPingLockBox.sol"; 

contract MedPingToken is ERC20,MedPingLockBox{
    using SafeMath for uint256;
    uint256 tSupply = 200 * 10**6 * (10 ** uint256(decimals()));

    constructor() ERC20("Medping", "PING"){
        _mint(msg.sender, tSupply);
    }
    
    function transfer(address _to, uint256 _value) canTransfer() investorChecks(_value,msg.sender) public override returns (bool success) {
        super.transfer(_to,_value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) canTransfer() investorChecks(_value,_from) public override returns (bool success) {
       super.transferFrom(_from, _to, _value);
        return true;
    }

    function burnPING(uint256 _date) public onlyBurner() returns(bool success){
        require(!isTokenBurntOnDate(_date));
        require(released);
        uint256 totalToBurn = (burnBucketBal.mul(10 *100)).div(10000); //burn 10 % of burnbucket quaterly
        _burn(msg.sender, totalToBurn);
        burnDateStatus[_date] = true;
        return true;
    }
}

