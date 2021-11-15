pragma solidity ^0.8.1;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Bank is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    /// @notice Event emitted when user deposit assets.
    event Deposit(address indexed account, address token, uint256 amount);

    /// @notice Event emitted when user withdraw assets.
    event Withdraw(address indexed account, address token, uint256 amount);

    /// @notice Event emitted when user create request for credit.
    event newCreditRequest(uint64 indexed id, address account, address borrowToken, uint256 borrowAmount, uint256 reimbursementAmount, address pledgeToken, uint256 pledgeAmount, uint32 creditPeriodDays);

    /// @notice Event emitted when bank owner give credit for user.
    event newApproveCredit(uint64 indexed id);

    /// @notice Event emitted when user close credit.
    event newCloseCredit(uint64 indexed id);

    struct CreditRequest {
        address account;

        address borrowToken;
        uint256 borrowAmount;

        uint256 reimbursementAmount;

        address pledgeToken;
        uint256 pledgeAmount;

        uint256 creationTime; // UNIX timestamp
        uint32 creditPeriodDays;
    }

    /// @notice Possible states that a credit may be in
    enum CreditState {
        NotExist,
        Exist,
        Active,
        Finished
    }

    /// @notice Total number of credit requests.
    uint64 public totalCreditRequests;

    /// @dev All credit requests.
    mapping(uint64 => CreditRequest) internal creditRequests;

    /// @dev state of credits
    mapping(uint64 => CreditState) internal creditRequestsState;

    /// @notice accountAddress => tokenAddress => amount
    mapping(address => mapping(address => uint256)) public balanceOf;

    function depositETH() external payable {
        registerDeposit(address(0), msg.value, address(msg.sender));
    }

    function depositERC20(IERC20 _token, uint256 _amount) external nonReentrant {
        uint256 balanceBefore = _token.balanceOf(address(this));

        // perform ERC20 `transferFrom`
        (bool callSuccess, bytes memory callReturnValueEncoded) =
            address(_token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), _amount));

        // `transferFrom` method may return (bool) or nothing.
        bool returnedSuccess = callReturnValueEncoded.length == 0 || abi.decode(callReturnValueEncoded, (bool));
        require(callSuccess && returnedSuccess, "ERC20 transferFrom fails"); 

        uint256 balanceAfter = _token.balanceOf(address(this));
        uint256 depositAmount = balanceAfter.sub(balanceBefore);

        registerDeposit(address(_token), depositAmount, address(msg.sender));
    }

    function withdrawETH(uint256 _amount) external nonReentrant {
        address to = address(msg.sender);
        (bool callSuccess, ) = to.call{value: _amount}("");
        require(callSuccess, "failed send ETH");
        registerWithdraw(address(0), _amount, address(msg.sender));
    }

    function withdrawERC20(IERC20 _token, uint256 _amount) external nonReentrant {
        uint256 balanceBefore = _token.balanceOf(address(this));
        
        // perform ERC20 `transfer`
        (bool callSuccess, bytes memory callReturnValueEncoded) =
            address(_token).call(abi.encodeWithSignature("transfer(address,uint256)", address(msg.sender), _amount));
        
        // `transfer` method may return (bool) or nothing.
        bool returnedSuccess = callReturnValueEncoded.length == 0 || abi.decode(callReturnValueEncoded, (bool));
        require(callSuccess && returnedSuccess, "ERC20 transfer fails");

        uint256 balanceAfter = _token.balanceOf(address(this));
        uint256 withdrawAmount = balanceBefore.sub(balanceAfter);

        registerWithdraw(address(_token), withdrawAmount, address(msg.sender));
    }

    function requestCredit(address _borrowToken, uint256 _borrowAmount, uint256 _reimbursementAmount, address _pledgeToken, uint256 _pledgeAmount, uint32 _creditPeriodDays) external nonReentrant {
        require(_creditPeriodDays > 30);
        require(_reimbursementAmount > _borrowAmount);
        creditRequests[totalCreditRequests] = CreditRequest({
            account: address(msg.sender),
            borrowToken: _borrowToken,
            borrowAmount: _borrowAmount,
            reimbursementAmount: _reimbursementAmount,
            pledgeToken: _pledgeToken,
            pledgeAmount: _pledgeAmount,
            creationTime: block.timestamp,
            creditPeriodDays: _creditPeriodDays
        });
        creditRequestsState[totalCreditRequests] = CreditState.Exist;
        emit newCreditRequest(totalCreditRequests, address(msg.sender), _borrowToken, _borrowAmount, _reimbursementAmount, _pledgeToken, _pledgeAmount, _creditPeriodDays);
        totalCreditRequests++;
    }

    function approveCredit(uint64 _id) external onlyOwner {
        require(_id < totalCreditRequests, "credit id is greater than total credit requests");
        require(creditRequestsState[_id] == CreditState.Exist, "credit state is not exists");
        CreditRequest storage request = creditRequests[_id];

        require(request.creationTime + 3 days < block.timestamp, "the request has expired");
        require(balanceOf[request.account][request.pledgeToken] >= request.pledgeAmount, "insufficient number of tokens in user");
        require(balanceOf[address(msg.sender)][request.borrowToken] >= request.borrowAmount, "insufficient number of tokens in bank");
        
        uint256 borowTokenUserBalance = balanceOf[request.account][request.borrowToken];
        balanceOf[request.account][request.borrowToken] = borowTokenUserBalance.add(request.borrowAmount);

        uint256 borowTokenBankBalance = balanceOf[address(msg.sender)][request.borrowToken];
        balanceOf[address(msg.sender)][request.borrowToken] = borowTokenBankBalance.sub(request.borrowAmount);

        uint256 pledgeTokenUserBalance = balanceOf[request.account][request.pledgeToken];
        balanceOf[request.account][request.pledgeToken] = pledgeTokenUserBalance.sub(request.pledgeAmount);

        creditRequestsState[_id] = CreditState.Active;
        emit newApproveCredit(_id);
    }

    function closeCredit(uint64 _id) external nonReentrant {
        require(_id < totalCreditRequests, "credit id is greater than total credit requests");
        require(creditRequestsState[_id] == CreditState.Active, "credit state is not active");
        CreditRequest storage request = creditRequests[_id];
        
        address bankOwner = owner();
        require(request.account == address(msg.sender));
        require(balanceOf[request.account][request.borrowToken] >= request.reimbursementAmount, "insufficient number of borrow tokens in user");
        require(balanceOf[bankOwner][request.pledgeToken] >= request.pledgeAmount, "insufficient number of pledge tokens in bank");
        
        uint256 borowTokenUserBalance = balanceOf[request.account][request.borrowToken];
        balanceOf[request.account][request.borrowToken] = borowTokenUserBalance.sub(request.reimbursementAmount);

        uint256 borowTokenBankBalance = balanceOf[bankOwner][request.borrowToken];
        balanceOf[bankOwner][request.borrowToken] = borowTokenBankBalance.add(request.reimbursementAmount);

        uint256 pledgeTokenUserBalance = balanceOf[request.account][request.pledgeToken];
        balanceOf[request.account][request.pledgeToken] = pledgeTokenUserBalance.add(request.pledgeAmount);

        uint256 pledgeTokenBankBalance = balanceOf[bankOwner][request.pledgeToken];
        balanceOf[bankOwner][request.pledgeToken] = pledgeTokenBankBalance.sub(request.pledgeAmount);

        creditRequestsState[_id] = CreditState.Finished;
        emit newCloseCredit(_id);
    }
    
    function registerDeposit(
        address _token,
        uint256 _amount,
        address _owner
    ) internal {
        uint256 balance = balanceOf[_owner][_token];
        balanceOf[_owner][_token] = balance.add(_amount);
        emit Deposit(_owner, _token, _amount);
    }

    function registerWithdraw(
        address _token,
        uint256 _amount,
        address _owner
    ) internal {
        uint256 balance = balanceOf[_owner][_token];
        balanceOf[_owner][_token] = balance.sub(_amount);
        emit Withdraw(_owner, _token, _amount);
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

