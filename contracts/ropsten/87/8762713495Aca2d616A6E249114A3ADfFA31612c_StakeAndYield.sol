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
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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

pragma solidity 0.6.12;

//import "zeppelin-solidity/contracts/math/SafeMath.sol";
//import "zeppelin-solidity/contracts/ownership/Ownable.sol";

import "./SafeMath.sol";
import "./Ownable.sol";

interface StandardToken {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IController {
    function withdrawETH(uint256 amount) external;
    function depositForStrategy(uint256 amount, address addr) external;
    function buyForStrategy(
        uint256 amount,
        address rewardToken,
        address recipient
    ) external;
    function getStrategy(address vault) external view returns (address);
}

interface IStrategy {
    function getLastEpochTime() external view returns(uint256);
}

contract StakeAndYield is Ownable {
    uint256 constant STAKE = 1;
    uint256 constant YIELD = 2;
    uint256 constant BOTH = 3;

    uint256 public PERIOD = 24 hours;
    uint256 public lastUpdateTime;
    uint256 public rewardRate;
    uint256 public rewardRateYield;

    uint256 public rewardTillNowPerToken = 0;
    uint256 public yieldRewardTillNowPerToken = 0;

    uint256 public _totalSupply = 0;
    uint256 public _totalSupplyYield = 0;

    uint256 public _totalYieldWithdrawed = 0;

    // false: withdraw from YEARN and then pay the user
    // true: pay the user w/o withdrawing from YEARN
    bool public allowEmergencyWithdraw = false;

    IController public controller;

    struct User {
        uint256 depositAmount;
        uint256 yieldDepositAmount;
        uint256 bothDepositAmount;

        // When user is staking or withdrawing
        // we will calculate the pending rewards until now
        // and save here

        uint256 paidReward;
        uint256 yieldPaidReward;

        uint256 paidRewardPerToken;
        uint256 yieldPaidRewardPerToken;

        uint256 withdrawable;
        uint256 withdrawTime;
    }

    using SafeMath for uint256;

    mapping (address => User) public users;

    uint256 public lastUpdatedBlock;
    uint256 public rewardPerBlock;
    uint256 public yieldRewardPerBlock;

    uint256 public periodFinish = 0;

    uint256 public scale = 1e18;

    uint256 public daoShare;
    address public daoWallet;

    StandardToken public stakedToken;
    StandardToken public rewardToken;
    StandardToken public yieldRewardToken;

    event Deposit(address user, uint256 amount, uint256 stakeType);
    event Withdraw(address user, uint256 amount, uint256 stakeType);
    event Unfreeze(address user, uint256 amount, uint256 stakeType);
    event EmergencyWithdraw(address user, uint256 amount);
    event RewardClaimed(address user, uint256 amount, uint256 stakeType);
    event RewardPerBlockChanged(uint256 oldValue, uint256 newValue, uint256 oldYieldValue, uint256 newYeildValue);

    constructor (
		address _stakedToken,
		address _rewardToken,
        address _yieldRewardToken,
		uint256 _daoShare,
		address _daoWallet,
        address _controller
    ) public {
			
        stakedToken = StandardToken(_stakedToken);
        rewardToken = StandardToken(_rewardToken);
        yieldRewardToken = StandardToken(_yieldRewardToken);
        controller = IController(_controller);
        daoShare = _daoShare;
        daoWallet = _daoWallet;
    }

    modifier onlyOwnerOrController(){
        require(msg.sender == owner() || msg.sender==address(controller),
            "!ownerOrController"
        );
        _;
    }

    modifier updateReward(address account, uint256 stakeType) {
        if(stakeType == STAKE || stakeType == BOTH){
            rewardTillNowPerToken = rewardPerToken(STAKE);
            lastUpdateTime = lastTimeRewardApplicable();
            if (account != address(0)) {
                sendReward(
                    account,
                    earned(account, STAKE),
                    earned(account, YIELD)
                );
                users[account].paidRewardPerToken = rewardTillNowPerToken;
            }
        }

        if(stakeType == YIELD || stakeType == BOTH){
            yieldRewardTillNowPerToken = rewardPerToken(YIELD);
            lastUpdateTime = lastTimeRewardApplicable();
            if (account != address(0)) {
                sendReward(
                    account,
                    earned(account, STAKE),
                    earned(account, YIELD)
                );
                users[account].yieldPaidRewardPerToken = yieldRewardTillNowPerToken;
            }
        }
        _;
    }

    function setDaoWallet(address _daoWallet) public onlyOwner {
        daoWallet = _daoWallet;
    }

    function setDaoShare(uint256 _daoShare) public onlyOwner {
        daoShare = _daoShare;
    }

    function earned(address account, uint256 stakeType) public view returns(uint256) {
        User storage user = users[account];
        
        uint256 paidPerToken = stakeType == STAKE ? 
            user.paidRewardPerToken : user.yieldPaidRewardPerToken;

        return balanceOf(account, stakeType).mul(
            rewardPerToken(stakeType).
            sub(paidPerToken)
        ).div(1e18);
    }

	function deposit(uint256 amount, uint256 stakeType) public {
		depositFor(msg.sender, amount, stakeType);
    }

    function depositFor(address _user, uint256 amount, uint256 stakeType) updateReward(_user, stakeType) public {
        require(stakeType==STAKE || stakeType ==YIELD || stakeType==BOTH, "Invalid stakeType");
        User storage user = users[_user];

        stakedToken.transferFrom(address(msg.sender), address(this), amount);

        if(stakeType == STAKE){
            user.depositAmount = user.depositAmount.add(amount);
            _totalSupply = _totalSupply.add(amount);
        }else if(stakeType == YIELD){
            user.yieldDepositAmount = user.yieldDepositAmount.add(amount);
            _totalSupplyYield = _totalSupplyYield.add(amount);
        }else{
            user.bothDepositAmount = user.bothDepositAmount.add(amount);
            _totalSupplyYield = _totalSupplyYield.add(amount);
            _totalSupply = _totalSupply.add(amount);
        }
        
        emit Deposit(_user, amount, stakeType);
    }

	function sendReward(address userAddress, uint256 amount, uint256 yieldAmount) private {
        User storage user = users[userAddress];
		uint256 _daoShare = amount.mul(daoShare).div(scale);
        uint256 _yieldDaoShare = yieldAmount.mul(daoShare).div(scale);

        if(amount > 0){
            rewardToken.transfer(userAddress, amount.sub(_daoShare));
            rewardToken.transfer(daoWallet, _daoShare);
            user.paidReward = user.paidReward.add(
                amount
            );
        }

        if(yieldAmount > 0){
            yieldRewardToken.transfer(userAddress, yieldAmount.sub(_yieldDaoShare));
            yieldRewardToken.transfer(daoWallet, _yieldDaoShare);   
            
            user.yieldPaidReward = user.yieldPaidReward.add(
                yieldAmount
            );
        }
        
        if(amount > 0 || yieldAmount > 0){
            emit RewardClaimed(userAddress, amount, yieldAmount);
        }
	}

    function unfreeze(uint256 amount, uint256 stakeType) updateReward(msg.sender, stakeType) public {
        require(stakeType==STAKE || stakeType ==YIELD || stakeType==BOTH, "Invalid stakeType");
        User storage user = users[msg.sender];
        require(
            (stakeType==STAKE && user.depositAmount > amount) ||
            (stakeType==YIELD && user.yieldDepositAmount > amount) || 
            (stakeType==BOTH && user.bothDepositAmount > amount)
         , "withdraw > deposit");

        if (amount > 0) {
            if(stakeType == STAKE){
                user.depositAmount = user.depositAmount.sub(amount);
                _totalSupply = _totalSupply.sub(amount);
            }else if (stakeType == YIELD){
                user.yieldDepositAmount = user.yieldDepositAmount.sub(
                    amount
                );
                _totalSupplyYield = _totalSupplyYield.sub(amount);
            }else{
                user.bothDepositAmount = user.bothDepositAmount.sub(
                    amount
                );
                _totalSupply = _totalSupply.sub(amount);
                _totalSupplyYield = _totalSupplyYield.sub(amount);
            }

            if(allowEmergencyWithdraw || stakeType==STAKE){
                stakedToken.transfer(address(msg.sender), amount);
                emit Withdraw(msg.sender, amount, stakeType);
            }else{
                user.withdrawable += amount;
                user.withdrawTime = now;

                _totalYieldWithdrawed += amount;

                emit Unfreeze(msg.sender, amount, stakeType);
            }
        }
    }

    function withdrawUnfreezed() public{
        User storage user = users[msg.sender];
        require(user.withdrawable > 0, "amount is 0");
        
        uint256 lastEpochTime = IStrategy(
            controller.getStrategy(address(this))
        ).getLastEpochTime();
        require(user.withdrawTime < lastEpochTime,
            "Can't withdraw yet");

        stakedToken.transfer(address(msg.sender), user.withdrawable);
        emit Withdraw(msg.sender, user.withdrawable, YIELD);
        user.withdrawable = 0;
    }

    // just Controller and admin should be able to call this
    function notifyRewardAmount(uint256 reward, uint256 stakeType) public onlyOwnerOrController  updateReward(address(0), stakeType){
        if (block.timestamp >= periodFinish) {
            if(stakeType == STAKE){
                rewardRate = reward.div(PERIOD);    
            }else{
                rewardRateYield = reward.div(PERIOD);
            }
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            if(stakeType == STAKE){
                uint256 leftover = remaining.mul(rewardRate);
                rewardRate = reward.add(leftover).div(PERIOD);    
            }else{
                uint256 leftover = remaining.mul(rewardRateYield);
                rewardRateYield = reward.add(leftover).div(PERIOD);
            }
            
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(PERIOD);
    }

    function balanceOf(address account, uint256 stakeType) public view returns(uint256) {
        User storage user = users[account];
        return user.bothDepositAmount.add(
            stakeType == STAKE ? user.depositAmount :
            user.yieldDepositAmount
        );
    }

    function totalYieldWithdrawed() public view returns(uint256) {
        return _totalYieldWithdrawed;
    }

    function lastTimeRewardApplicable() public view returns(uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken(uint256 stakeType) public view returns(uint256) {
        uint256 supply = stakeType == STAKE ? _totalSupply : _totalSupplyYield;        
        if (supply == 0) {
            return stakeType == STAKE ? rewardTillNowPerToken : yieldRewardTillNowPerToken;
        }
        if(stakeType == STAKE){
            return rewardTillNowPerToken.add(
                lastTimeRewardApplicable().sub(lastUpdateTime)
                .mul(rewardRate).mul(1e18).div(_totalSupply)
            );
        }else{
            return yieldRewardTillNowPerToken.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).
                mul(rewardRateYield).mul(1e18).div(_totalSupplyYield)
            );
        }
    }

    function getRewardToken() public view returns(address){
        return address(rewardToken);
    }

    function setController(address _controller) public onlyOwner{
        if(_controller != address(0)){
            controller = IController(_controller);
        }
    }

	function emergencyWithdrawFor(address _user) public onlyOwner{
        User storage user = users[_user];

        uint256 amount = user.depositAmount.add(
            user.bothDepositAmount).add(user.yieldDepositAmount);

        stakedToken.transfer(_user, amount);

        emit EmergencyWithdraw(_user, amount);

        //add other fields
        user.depositAmount = 0;
        user.yieldDepositAmount = 0;
        user.bothDepositAmount = 0;
        user.paidReward = 0;
        user.yieldPaidReward = 0;
    }

    function setAllowEmergencyWithdraw(bool _val) public onlyOwner{
        allowEmergencyWithdraw = _val;
    }

    function emergencyWithdrawETH(uint256 amount, address addr) public onlyOwner{
        require(addr != address(0));
        payable(addr).transfer(amount);
    }

    function emergencyWithdrawERC20Tokens(address _tokenAddr, address _to, uint _amount) public onlyOwner {
        require(_tokenAddr != address(stakedToken), "Forbidden.");        
        StandardToken(_tokenAddr).transfer(_to, _amount);
    }
}


//Dar panah khoda

