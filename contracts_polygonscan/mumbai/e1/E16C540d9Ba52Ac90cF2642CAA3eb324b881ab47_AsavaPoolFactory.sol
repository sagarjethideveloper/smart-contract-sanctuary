// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TierIDOPool.sol";
import "./AsvaInvestmentsInfo.sol";

/**
 * @dev This factory contract  for createPresale
 * Useful for lunching new NewIDO https://testnet.bscscan.com/address/0xe6d8d1bd5B3f514D4Bba82347e9864a0491cbF73#code
 */
contract AsavaPoolFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public nextPoolId;

    struct IDOPoolInfo {
        address contractAddr;
        address currency;
        address token;
    }

    event PoolCreated(
        uint256 indexed asvaId,
        uint256 presaleDbID,
        address indexed _token,
        address indexed _currency,
        address pool,
        address creator
    );
    
    struct IDOInfo {
        address _token;
        address _currency;
        uint256 _round1Start;
        uint256 _round1End;
        uint256 _round2Start;
        uint256 _round2End;
        uint256 _releaseTime;
        uint256 _price;
        uint256 _totalAmount;
        uint256 _Tier1MaxAmoutInvest;
        uint256 _Tier2MaxAmoutInvest;
        uint256 _Tier3MaxAmoutInvest;
        uint256 _Tier4MaxAmoutInvest;
        uint256 _presaleProjectID;
        address[] _whitelistedAddresses;
        uint8[] _tiers;
    }

    IDOPoolInfo[] public poolList;
    
    AsvaInvestmentsInfo public immutable AsvaInfo;
    IERC20 public platformToken; // Platform token

    constructor(address _asvaInfoAddress, address _platformToken) public {
        AsvaInfo = AsvaInvestmentsInfo(_asvaInfoAddress);
        platformToken = IERC20(_platformToken);
    }

    function createPoolPublic(
       IDOInfo calldata poolInfo
       ) external  {
        require(poolInfo._token != poolInfo._currency, "Currency and Token can not be the same");
        require(poolInfo._token != address(0));
        require(poolInfo._currency != address(0));
        
       // AsvaInvestmentsPresale presale = new AsvaInvestmentsPresale(address(this), AsvaInfo.owner());
        IERC20 tokenIDO = IERC20(poolInfo._token);

        TierIDOPool _idoPool = new TierIDOPool(
                poolInfo._token,
                poolInfo._currency,
                poolInfo._round1Start,   
                poolInfo._round1End,
                poolInfo._round2Start,
                poolInfo._round2End,
                poolInfo._releaseTime,
                poolInfo._price,
                poolInfo._totalAmount,
                poolInfo._Tier1MaxAmoutInvest,
                poolInfo._Tier2MaxAmoutInvest,
                poolInfo._Tier3MaxAmoutInvest,
                poolInfo._Tier4MaxAmoutInvest
        );

       tokenIDO.transferFrom(msg.sender, address(_idoPool), poolInfo._totalAmount);

        poolList.push(IDOPoolInfo(address(_idoPool), poolInfo._currency, poolInfo._token));
       
        uint256 asvaId = AsvaInfo.addPresaleAddress(address(_idoPool), poolInfo._presaleProjectID);

       _idoPool.setPlatformTokenAddress(address(platformToken));

       initializeWhitelisted(_idoPool, poolInfo._whitelistedAddresses, poolInfo._tiers);

        emit PoolCreated(asvaId, poolInfo._presaleProjectID, poolInfo._token, poolInfo._currency, address(_idoPool), msg.sender);
    }
    function initializeWhitelisted(
        TierIDOPool _pool,
        address[] calldata _whitelistedAddresses,
        uint8[] calldata _tiers
    ) internal {
        _pool.addToPoolWhiteList(_whitelistedAddresses, _tiers);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

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
    using SafeMath for uint256;
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
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
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
    constructor () internal {
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
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @dev This IDO contract
 * Useful for lunching new NewIDO 
 */
contract TierIDOPool is Ownable, ReentrancyGuard {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each investor
    struct Sale {
        address investor; // Address of user
        uint256 amount; // Amount of tokens purchased
        bool tokensWithdrawn; // Withdrawal status
    }

    struct Investor {
        address investor; // Address of user
        uint256 amount; // Amount of tokens purchased
    }

    IERC20 public platformToken; // Platform token

    // List investors
    Investor[] private investorInfo;
    // Info of each investor that buy tokens.
    mapping(address => Sale) public sales;
    // Round 1 start time
    uint256 public round1Start;
    // Round 1 end time
    uint256 public round1End;
    // Round 2 start time
    uint256 public round2Start;
    // Round 1 end time
    uint256 public round2End;
    // Price of each token
    uint256 public price;
    // Amount of tokens remaining
    uint256 public availableTokens;
    // Total amount of tokens to be sold
    uint256 public totalAmount;
    // Total amount sold
    uint256 public totalAmountSold;
    // // Min amount for each sale
    // uint256 public minPurchase;
    // // Max amount for each sake
    // uint256 public maxPurchase;
    // Release time
    uint256 public releaseTime;
    // Whitelist addresses
    mapping(address => uint8) public poolWhiteList;
    address[] private listWhitelists;
    // Number of investors
    uint256 public numberParticipants;
    // Tiers allocations
    mapping(uint8 => uint256) public tierAllocations;

    mapping(uint8 => uint256) public tierMaxAmoutInvest;

    // Token for sale
    IERC20 public token;
    // Token used to buy
    IERC20 public currency;

    



    event Buy(address indexed _user, uint256 _amount, uint256 _tokenAmount);
    event Claim(address indexed _user, uint256 _amount);
    event Withdraw(address indexed _user, uint256 _amount);
    event EmergencyWithdraw(address indexed _user, uint256 _amount);
    event Burn(address indexed _burnAddress, uint256 _amount);

    constructor(
        address _token,
        address _currency,
        uint256 _round1Start,
        uint256 _round1End,
        uint256 _round2Start,
        uint256 _round2End,
        uint256 _releaseTime,
        uint256 _price,
        uint256 _totalAmount,
        uint256 _Tier1MaxAmoutInvest,
        uint256 _Tier2MaxAmoutInvest,
        uint256 _Tier3MaxAmoutInvest,
        uint256 _Tier4MaxAmoutInvest
      ) public {
        require(_token != address(0), "Zero token address");
        require(_currency != address(0), "Zero token address");
        require(_round1Start < _round1End, "_round1Start must be < _round1End");
        require(
            _round1End <= _round2Start,
            "_round1End must be <= _round2Start"
        );
        require(_round2Start < _round2End, "_round2Start must be < _round2End");
        require(_totalAmount > 0, "_totalAmount must be > 0");
        // require(_minPurchase > 0, "_minPurchase must > 0");
        // require(
        //     _minPurchase <= _maxPurchase,
        //     "_minPurchase must be <= _maxPurchase"
        // );
       
        token = IERC20(_token);
        currency = IERC20(_currency);
        round1Start = _round1Start;
        round1End = _round1End;
        round2Start = _round2Start;
        round2End = _round2End;
        releaseTime = _releaseTime;
        price = _price;
        totalAmount = _totalAmount;
        availableTokens = _totalAmount;
       
        numberParticipants = 0;
        totalAmountSold = 0;
        tierMaxAmoutInvest[1] = _Tier1MaxAmoutInvest;
        tierMaxAmoutInvest[2] = _Tier2MaxAmoutInvest;
        tierMaxAmoutInvest[3] = _Tier3MaxAmoutInvest;
        tierMaxAmoutInvest[4] = _Tier4MaxAmoutInvest;
    }

    // Buy tokens
    function buy(uint256 amount) external publicSaleActive nonReentrant {
        require(availableTokens > 0, "All tokens were purchased");
        require(amount > 0, "Amount must be > 0");
        uint8 tier = getAddressTier(msg.sender);
        require(tier > 0, "You are not whitelisted");
      
        //uint256 remainingAllocation = tierAllocations[tier];
      
        // if (block.timestamp >= round2Start) {
        //     remainingAllocation = availableTokens;
        // }
      
        // require(
        //     amount <= remainingAllocation && amount <= availableTokens,
        //     "Not enough token"
        // );
        require(
            amount <= availableTokens,
            "Not enough token"
        );
      
        Sale storage sale = sales[msg.sender];
       
        // If round 1 is running then we check maxInvest amout as per tier
        if (block.timestamp <= round1End) {
            uint256 maxPurchase= tierMaxAmoutInvest[tier];
            require(amount <= maxPurchase.sub(sale.amount), "Exceed amount");
            if (sale.amount == 0) {
                require(
                    amount <= maxPurchase,
                    "Have to buy maxPurchase"
                );
            }
        }
        uint256 currencyAmount = amount.mul(price).div(1e18);
      
        require(
            currency.balanceOf(msg.sender) >= currencyAmount,
            "Insufficient account balance"
        );
        require(currency.approve(address(this), currencyAmount));
        availableTokens = availableTokens.sub(amount);
       
        // if (block.timestamp <= round1End) {
        //     tierAllocations[tier] = tierAllocations[tier].sub(amount);
        // }
       
        currency.safeTransferFrom(msg.sender, address(this), currencyAmount);
       
        if (sale.amount == 0) {
            sales[msg.sender] = Sale(msg.sender, amount, false);
            numberParticipants += 1;
        } else {
            sales[msg.sender] = Sale(msg.sender, amount + sale.amount, false);
        }
        totalAmountSold += amount;
        investorInfo.push(Investor(msg.sender, amount));
        emit Buy(msg.sender, currencyAmount, amount);
    }

    function getInvestors()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addrs = new address[](numberParticipants);
        uint256[] memory funds = new uint256[](numberParticipants);

        for (uint256 i = 0; i < numberParticipants; i++) {
            Investor storage investor = investorInfo[i];
            addrs[i] = investor.investor;
            funds[i] = investor.amount;
        }

        return (addrs, funds);
    }

    // Withdraw purchased tokens after release time
    function claimTokens() external canClaim nonReentrant {
        Sale storage sale = sales[msg.sender];
        require(sale.amount > 0, "Only investors");
        require(sale.tokensWithdrawn == false, "Already withdrawn");
        sale.tokensWithdrawn = true;
        token.transfer(sale.investor, sale.amount);
        emit Claim(msg.sender, sale.amount);
    }
    // Admin wit[hdraw after the sale ends
    // The remaining tokens will be burned
    function withdraw() external onlyOwner publicSaleEnded nonReentrant {
        if (availableTokens > 0) {
            availableTokens = 0;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, tokenBalance);
        emit Withdraw(msg.sender, tokenBalance);
        uint256 currencyBalance = currency.balanceOf(address(this));
        currency.safeTransfer(msg.sender, currencyBalance);
        emit Withdraw(msg.sender, currencyBalance);
    }

    // Withdraw without caring about progress. EMERGENCY ONLY.
    function emergencyWithdraw() external onlyOwner nonReentrant {
        if (availableTokens > 0) {
            availableTokens = 0;
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, tokenBalance);
        emit Withdraw(msg.sender, tokenBalance);
        uint256 currencyBalance = currency.balanceOf(address(this));
        currency.safeTransfer(msg.sender, currencyBalance);
        emit Withdraw(msg.sender, currencyBalance);
    }

    // Add addresses to whitelist
    function addToPoolWhiteList(address[] memory _users, uint8[] memory _tiers)
        public
        onlyOwner
        returns (bool)
    {
        require(_users.length == _tiers.length, "Invalid length");
    
        for (uint8 i = 0; i < _users.length; i++) {
            poolWhiteList[_users[i]] = _tiers[i];
        }

        return true;
    }

    // Set the platform Token
    function setPlatformTokenAddress(address _platformToken) external onlyOwner returns (bool) {
        platformToken = IERC20(_platformToken);
        return true;
    }

    // Get the whitelist
    function getPoolWhiteLists() public view returns (address[] memory) {
        return listWhitelists;
    }

    // Get user tier z
    function getAddressTier(address _user) public view returns (uint8) {
        return poolWhiteList[_user];
    }

    modifier isWhitelisted(address _address) {
        require(getAddressTier(_address) > 0, "You are not whitelisted");
        _;
    }

    modifier publicSaleActive() {
        require(
            (round1Start <= block.timestamp && block.timestamp <= round1End) ||
                (round2Start <= block.timestamp &&
                    block.timestamp <= round2End),
            "Not activated yet"
        );
        _;
    }

    modifier publicSaleNotActive() {
        require(
            block.timestamp < round1Start ||
                (round1End < block.timestamp && block.timestamp < round2Start),
            "Not started yet"
        );
        _;
    }

    modifier publicSaleEnded() {
        require(
            block.timestamp >= round2End || availableTokens == 0,
            "Not ended yet"
        );
        _;
    }

    modifier canClaim() {
        require(
            block.timestamp >= releaseTime,
            "Please wait until release time"
        );
        _;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @dev AsvaInvestmentsInfo Give  infromation regarding  IDO contract which lunch by ASVAFACTORY contract. link :https://testnet.bscscan.com/address/0x3109bf9e73f50209Cf92D2459B5Da0E38D8890C1#code
 */
contract AsvaInvestmentsInfo is Ownable {

    address[] private presaleAddresses;

    mapping (address => bool) public alreadyAdded;
    mapping (uint256 => address) public presaleAddressByProjectID;
    function validAsvaId(uint256 asvaId) public view returns (bool) {
        if(asvaId >=0 && asvaId <= presaleAddresses.length-1)
          return true;
    }

    function addPresaleAddress(address _presale, uint256 _presaleProjectID) external returns (uint256) {
        require(_presale != address(0), "Address cannot be a zero address");
        require(!alreadyAdded[_presale], "Address already added");

        presaleAddresses.push(_presale);
        alreadyAdded[_presale] = true;
        presaleAddressByProjectID[_presaleProjectID] =_presale;
        return presaleAddresses.length - 1;
    }

    function getPresalesCount() external view returns (uint256) {
        return presaleAddresses.length;
    }

    //get presale contract address by DB id 
    function getPresaleAddressByDbId(uint256 asvaDbId) external view returns (address) {
        return presaleAddressByProjectID[asvaDbId];
    }

    function getPresaleAddress(uint256 asvaId) external view returns (address) {
        require(validAsvaId(asvaId), "Not a valid Id");
        return presaleAddresses[asvaId];
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

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

pragma solidity >=0.6.0 <0.8.0;

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

    constructor () internal {
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

