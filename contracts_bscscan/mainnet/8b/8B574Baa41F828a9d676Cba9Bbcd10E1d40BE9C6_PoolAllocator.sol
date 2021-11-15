pragma solidity ^0.8.0;

import "./interfaces/IBEP20.sol";
import "./Auth.sol";
import "./SafeStake.sol";
import { IPancakeRouter02 } from "pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';

contract PoolAllocator is Auth, ReentrancyGuard {

    struct Pool {
        address sc;
        uint alloc;
    }

    //The pools that are active at a certain time
    Pool[] public activePools;
    //The history of pools
    Pool[] public exPools;
    mapping (address => mapping (uint => Pool)) public pools;
    address marketingAddress;

    //How much allocation all active pools combined have.
    uint public totalAllocs;
    //How many pools we have concurrently running
    uint public activePoolCount;

    uint bpScale = 10000;
    uint marketingFee = 100; //measured in bp, 100 bcp = 1%. should then divide by 10000 (bpScale) whenever this is used
    uint allocatorIncentive = 100;

    //Event declarations
    event Distribute(uint amt, uint incentive);
    event LiquifiedPool(address add, uint amt);
    event PoolAdded(address add, uint allocs);

    constructor () public Auth(msg.sender) {
        marketingAddress = msg.sender;
    }

    //Makes the whole contract payable
    receive() external payable {

    }

    //Gives incentives for whoever distributes BNB amongst RBLOs.
    function distribute() public nonReentrant {
        require(address(this).balance > 0, "Too late, someone else distributed :(");
        require(activePoolCount > 0, "There are no pools yet to distribute BNB to");

        //calculating fees & incentives
        uint bal = address(this).balance;
        uint incentive = address(this).balance * allocatorIncentive / bpScale;
        uint mkt = address(this).balance * marketingFee / bpScale;

        uint balanceBeforeDistribution = address(this).balance - incentive - mkt;

        //distribution for pools
        uint maxLength = exPools.length;
        for (uint i = 0; i < maxLength; i++) {
            if (activePools[i].sc != address(0))
                _sendBNBToPool(activePools[i], balanceBeforeDistribution);
        }

        //paying due rewards!
        payable(msg.sender).call{value:incentive}("");
        payable(marketingAddress).call{value:address(this).balance}("");

        emit Distribute(bal, incentive);
    }

    // Sends BNB proportional to _totalBnbToDistribute based on allocs
    function _sendBNBToPool(Pool memory _pool, uint _totalBnbToDistribute) internal {
        uint accScale = 1 ether * 1 ether;//using ether as 1e18, accScale = 1e36
        uint liqToAssign = _pool.alloc * accScale / totalAllocs; // Proportions of allocs to give to the pool
        uint bnbToGive = liqToAssign * _totalBnbToDistribute / accScale;
        address (_pool.sc).call{value:bnbToGive}(""); // Pools handle the logic of liquifying themselves on receive()
        emit LiquifiedPool(_pool.sc, bnbToGive);
    }

    // Updates a single Pool allocs given a poolId
    function updatePoolAllocs(uint _poolId, uint _newAllocs) external authorized {
        activePools[_poolId].alloc = _newAllocs;
    }

    function addPool(address _poolHash, uint alloc) external authorized {
        Pool memory pool = Pool(_poolHash, alloc);
        pools[_poolHash][activePools.length] = pool;
        activePools.push(pool);
        exPools.push(pool);
        totalAllocs = totalAllocs + alloc;
        activePoolCount = activePoolCount + 1;
        emit PoolAdded(_poolHash, alloc);
    }

    function removePool(uint poolId) external authorized {
        totalAllocs = totalAllocs - activePools[poolId].alloc;
        activePoolCount = activePoolCount - 1;
        delete activePools[poolId];
    }

    function setMarketingAddress(address _add) external authorized {
        marketingAddress = _add;
    }

    function setRates(uint incentive, uint mkt, uint scale) external authorized {
        allocatorIncentive = incentive;
        marketingFee = mkt;
        bpScale = scale;
    }
}

/**
 * BEP20 standard interface.
 */
interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * Allows for contract ownership along with multi-address authorization
 */
abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * Authorize address. Owner only
     */
    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    /**
     * Check if address is owner
     */
    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    /**
     * Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    /**
     * Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
     */
    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

pragma solidity ^0.8.0;

import { IDividendDistributor } from "./interfaces/IDividendDistributor.sol";
import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { Auth } from "./Auth.sol";
import { IDEXRouter } from "./interfaces/IDEXRouter.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IReflectionPool.sol";
import "./ReflectionLocker02.sol";
import "./SafeEarn.sol";


contract SafeStake is IReflectionPool, Auth, Pausable {
    using SafeMath for uint256;

    IBEP20 public rewardsToken;

    mapping (address => bool) excludeSwapperRole;
    mapping (address => ReflectionLocker02) public lockers;

    ReflectionLocker02[] public lockersArr;
    DividendDistributor distributor;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    SafeEarn safeEarn;
//    IBEP20 safeMoon = IBEP20(0x8076C74C5e3F5852037F31Ff0093Eeb8c8ADd8D3);
    IBEP20 safeMoon = IBEP20(0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e);

    IDEXRouter router;
    uint public lunchTime;

    struct TokenPool {
        uint totalShares;
        uint totalDividends;
        uint totalDistributed;
        uint dividendsPerShare;
        IBEP20 stakingToken;
    }

    TokenPool public tokenPool;

    //Shares by token vault
    mapping ( address => Share) public shares;

    uint public duration = 14 days;

    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    constructor (address _router, IBEP20 _rewardsToken, SafeEarn _stakingToken) Auth (msg.sender) {
        router = _router != address(0)
            ? IDEXRouter(_router)
            : IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        rewardsToken = _rewardsToken;
        tokenPool.stakingToken = _stakingToken;
        safeEarn = SafeEarn(_stakingToken);
        lunchTime = block.timestamp;
        distributor = DividendDistributor(_stakingToken.distributorAddress());
    }

    function lunch() external authorized {
        lunchTime = block.timestamp;
    }

    // Lets you stake token A. Creates a reflection locker to handle the reflections in an efficient way.
    function enterStaking(uint256 amount) external whenNotPaused {
        if (amount == 0)
            amount = tokenPool.stakingToken.balanceOf(msg.sender);

        require(amount <= tokenPool.stakingToken.balanceOf(msg.sender), "Insufficient balance to enter staking");
        require(tokenPool.stakingToken.allowance(msg.sender, address(this)) >= amount, "Not enough allowance");

        // Transfer the tokens to the staking contract
        safeEarn.setIsFeeExempt(msg.sender, true);
        bool success = tokenPool.stakingToken.transferFrom(msg.sender, address(this), amount);
        safeEarn.setIsFeeExempt(msg.sender, false);

        require(success, "Failed to fetch tokens towards the staking contract");

        // Create a reflection locker for type A pool
        if (address(tokenPool.stakingToken) == address(safeEarn)) {
            bool lockerExists = address(lockers[msg.sender]) == address (0);

            ReflectionLocker02 locker;
            if (!lockerExists) {
                locker = lockers[msg.sender];
            } else {
                locker = new ReflectionLocker02(msg.sender, safeEarn, safeEarn.distributorAddress(), address(safeMoon));
                lockersArr.push(locker); //Stores locker in array
                lockers[msg.sender] = locker; //Stores it in a mapping
                address lockerAdd = address(lockers[msg.sender]);
                safeEarn.setIsFeeExempt(lockerAdd, true);

                emit ReflectionLockerCreated(lockerAdd);
            }
            tokenPool.stakingToken.transfer(address(locker), amount);
        }

        // Give out rewards if already staking
        if (shares[msg.sender].amount > 0) {
            giveStakingReward(msg.sender);
        }

        addShareHolder(msg.sender, amount);
        emit EnterStaking(msg.sender, amount);
    }


    function reflectionsInLocker(address holder) public view returns (uint) {
        return safeMoon.balanceOf(address(lockers[holder])) + distributor.getUnpaidEarnings(address(lockers[holder]));
    }

    function leaveStaking(uint amt) external {
        require(shares[msg.sender].amount > 0, "You are not currently staking.");

        // Pay native token rewards.
        if (getUnpaidEarnings(msg.sender) > 0) {
            giveStakingReward(msg.sender);
        }

        uint amtMoonClaimed = 0;
        // Get rewards from locker
        if (address(tokenPool.stakingToken) == address(safeEarn)) {
            lockers[msg.sender].claimTokens(amt);
            amtMoonClaimed = lockers[msg.sender].claimReflections();
        } else {
            // Get rewards from contract
            tokenPool.stakingToken.transfer(msg.sender, shares[msg.sender].amount);
        }

        if (amt == 0) {
            amt = shares[msg.sender].amount;
            removeShareHolder();
        } else {
            _removeShares(amt);
        }

        emit LeaveStaking(msg.sender, amt, amtMoonClaimed);
    }


    function giveStakingReward(address shareholder) internal {
        require(shares[shareholder].amount > 0, "You are not currently staking");

        uint256 amount = getUnpaidEarnings(shareholder);

        if(amount > 0){
            tokenPool.totalDistributed = tokenPool.totalDistributed.add(amount);
            rewardsToken.transfer(shareholder, amount);
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }


    function harvest() external whenNotPaused {
        require(getUnpaidEarnings(msg.sender) > 0 || reflectionsInLocker(msg.sender) > 0, "No earnings yet ser");
        uint unpaid = getUnpaidEarnings(msg.sender);
        uint amtMoonClaimed = 0;
        if (!isLiquid(getUnpaidEarnings(msg.sender))) {
            getRewardsToken(address(this).balance);
        }
        amtMoonClaimed = lockers[msg.sender].claimReflections();
        giveStakingReward(msg.sender);
        emit Harvest(msg.sender, unpaid, amtMoonClaimed);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }


    receive() external payable {
        require(!paused(), "Contract has been paused.");
        require(block.timestamp < (lunchTime + duration), "Contract has ended.");

        if (!excludeSwapperRole[msg.sender]) {
            getRewardsToken(address(this).balance);
        }
    }

    // Update pool shares and user data
    function addShareHolder(address shareholder, uint amount) internal {
        tokenPool.totalShares = tokenPool.totalShares.add(amount);
        shares[shareholder].amount = shares[shareholder].amount + amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function removeShareHolder() internal {
        tokenPool.totalShares = tokenPool.totalShares.sub(shares[msg.sender].amount);
        shares[msg.sender].amount = 0;
        shares[msg.sender].totalExcluded = 0;
    }

    function _removeShares(uint amt) internal {
        tokenPool.totalShares = tokenPool.totalShares.sub(shares[msg.sender].amount);
        shares[msg.sender].amount = shares[msg.sender].amount.sub(shares[msg.sender].amount);
        shares[msg.sender].totalExcluded = getCumulativeDividends(shares[msg.sender].amount);
    }


    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(tokenPool.dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function isLiquid(uint amount) internal returns (bool){
        return rewardsToken.balanceOf(address(this)) > amount;
    }

    function getRewardsTokenPath() internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(rewardsToken);
        return path;
    }

    function getRewardsToken(uint amt) internal returns (uint) {
        uint256 balanceBefore = rewardsToken.balanceOf(address(this));
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amt}(
            0,
            getRewardsTokenPath(),
            address(this),
            block.timestamp
        );
        uint256 amount = rewardsToken.balanceOf(address(this)).sub(balanceBefore);

        tokenPool.totalDividends = tokenPool.totalDividends.add(amount);
        tokenPool.dividendsPerShare = tokenPool.dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(tokenPool.totalShares));
        return amount;
    }

    function setSwapperExcluded(address _add, bool _excluded) external authorized {
        excludeSwapperRole[_add] = _excluded;
    }

    function emergencyWithdraw() external {
        if (address(tokenPool.stakingToken) == address(safeEarn)) {
            uint amtClaimed = lockers[msg.sender].claimTokens(0);
            safeEarn.transfer(msg.sender, amtClaimed);
        } else {
            tokenPool.stakingToken.transfer(msg.sender, shares[msg.sender].amount);
        }
        removeShareHolder();
    }

    function pause(bool _pauseStatus) external authorized {
        if (_pauseStatus) {
            _pause();
        } else {
            _unpause();
        }
    }

    // Grabs any shitcoin someone sends to our contract, converts it to rewards for our holders ♥
//    function fuckShitcoins(IBEP20 _shitcoin) external authorized {
//        address[] memory path = new address[](2);
//        path[0] = address(_shitcoin);
//        path[1] = router.WETH();
//
//        uint256 balanceBefore = rewardsToken.balanceOf(address(this));
//        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amt}(
//            0,
//            path,
//            address(this),
//            block.timestamp
//        );
//        uint256 amount = rewardsToken.balanceOf(address(this)).sub(balanceBefore);
//
//        tokenPool.totalDividends = tokenPool.totalDividends.add(amount);
//        tokenPool.dividendsPerShare = tokenPool.dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(tokenPool.totalShares));
//        return amount;
//    }

    //Events
    event ReflectionLockerCreated(address);
    event EnterStaking(address, uint);
    event LeaveStaking(address, uint, uint);
    event Harvest(address, uint, uint);
    event PoolLiquified(uint, uint);


    //Unused


    function claimReflections(address _shareholder) internal {
        //        (uint earn, uint moon) = lockers[_shareholder].claimAll();
        uint smClaimed = lockers[_shareholder].claimReflections();
        safeMoon.transfer(_shareholder, smClaimed);
    }

    function claimFromLocker(address _shareholder, uint amt) internal {
        uint smClaimed = lockers[_shareholder].claimTokens(amt);
        require(smClaimed == amt, "Error claiming tokens, funds are safu tho.");
    }
}

pragma solidity >=0.6.2;

import './IPancakeRouter01.sol';

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

interface IDividendDistributor {
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
    function setShare(address shareholder, uint256 amount) external;
    function deposit() external payable;
    function process(uint256 gas) external;
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

interface IDEXRouter {
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor () {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

interface IReflectionPool {

}

import "./DividendDistributor01.sol";
import "./interfaces/IReflectionLocker.sol";
import "./interfaces/IReflectionPool.sol";

contract ReflectionLocker02 is IReflectionLocker {

    IBEP20 safeMoon = IBEP20(0x8076C74C5e3F5852037F31Ff0093Eeb8c8ADd8D3);
    IBEP20 safeEarn;

    IReflectionPool rblo;
    DividendDistributor distributor;
    address lockOwner;

    constructor (address _lockOwner, IBEP20 stakingToken, address dividendDistributor, address reflectedToken) public {
        lockOwner = _lockOwner;
        rblo = IReflectionPool(msg.sender);
        safeEarn = stakingToken;
        distributor = DividendDistributor(dividendDistributor);
        safeMoon = IBEP20(reflectedToken);
    }

    modifier onlyLockOwner {
        require(tx.origin == lockOwner || msg.sender == address(rblo) || msg.sender == address (this), "Fuck off.");
        _;
    }

    function unstakeAmount(uint amt) public onlyLockOwner {
        if (amt == 0)
            amt = safeEarn.balanceOf(address(this));
        uint tokensClaimed = claimTokens(amt);
        emit Unstake(tokensClaimed);
    }

    function claimSafemoon() public onlyLockOwner {
        claimReflections();
    }

    // Amt 0 is claim all
    function claimTokens(uint amt) public override onlyLockOwner returns (uint) {
        require(safeEarn.balanceOf(address (this)) >= amt, "Not enough tokens");
        if (amt == 0) {
            amt = safeEarn.balanceOf(address(this));
            safeEarn.transfer(lockOwner, amt);
        }
        else {
            safeEarn.transfer(lockOwner, amt);
        }
        return amt;
    }

    function claimReflections() public override onlyLockOwner returns (uint) {
        _getFromDistributor();
        uint balance = safeMoon.balanceOf(address(this));
        _transferSafemoon(lockOwner);
        emit ClaimReflections(balance);
        return balance;
    }

    function claimAll() public override onlyLockOwner returns (uint, uint) {
        _getFromDistributor();
        uint amtMoon = safeMoon.balanceOf(address(this));
        _transferSafemoon(lockOwner);
        uint amtEarn = safeEarn.balanceOf(address(this));
        safeEarn.transfer(lockOwner, amtEarn);
        emit ClaimAll(amtEarn, amtMoon);
        return (amtEarn, amtMoon);
    }

    function _getFromDistributor() internal {
        try distributor.claimDividend() {

        } catch {

        }
    }

    function _transferSafemoon(address to) internal {
        if (safeMoon.balanceOf(address (this)) > 0)
            safeMoon.transfer(to, safeMoon.balanceOf(address(this)));
    }

    function emergencyWithdraw() external onlyLockOwner {
        uint amtEarn = safeEarn.balanceOf(address(this));
        safeEarn.transfer(msg.sender, amtEarn);
    }

    event ClaimAll(uint indexed amtEarn, uint indexed amtMoon);
    event ClaimReflections(uint indexed amtMoon);
    event Unstake(uint indexed amt);


}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { IBEP20 } from "./interfaces/IBEP20.sol";
import { Auth } from "./Auth.sol";
import { IDEXRouter } from "./interfaces/IDEXRouter.sol";
import { IDividendDistributor } from "./interfaces/IDividendDistributor.sol";
import "./DividendDistributor01.sol";

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract SafeEarn is IBEP20, Auth {
    using SafeMath for uint256;

    uint256 public constant MASK = type(uint128).max;
    address SM = 0x8076C74C5e3F5852037F31Ff0093Eeb8c8ADd8D3;
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address DEAD_NON_CHECKSUM = 0x000000000000000000000000000000000000dEaD;

    string constant _name = "TESTS";
    string constant _symbol = "TESTS";
    uint8 constant _decimals = 9;

    uint256 _totalSupply = 1_000_000_000_000_000 * (10 ** _decimals);
    uint256 public _maxTxAmount = _totalSupply.div(400); // 0.25%

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isDividendExempt;

    uint256 liquidityFee = 100;
    uint256 buybackFee = 400;
    uint256 reflectionFee = 700;
    uint256 marketingFee = 200;
    uint256 totalFee = 1400;
    uint256 feeDenominator = 10000;

    address public autoLiquidityReceiver;
    address public marketingFeeReceiver;

    uint256 targetLiquidity = 25;
    uint256 targetLiquidityDenominator = 100;

    IDEXRouter public router;
    address public pair;

    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;

    uint256 buybackMultiplierNumerator = 200;
    uint256 buybackMultiplierDenominator = 100;
    uint256 buybackMultiplierTriggeredAt;
    uint256 buybackMultiplierLength = 30 minutes;

    bool public autoBuybackEnabled = false;
    mapping (address => bool) buyBacker;
    uint256 autoBuybackCap;
    uint256 autoBuybackAccumulator;
    uint256 autoBuybackAmount;
    uint256 autoBuybackBlockPeriod;
    uint256 autoBuybackBlockLast;

    DividendDistributor distributor;
    address public distributorAddress;

    uint256 distributorGas = 500000;

    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply / 2000; // 0.005%
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor (
        address _dexRouter
    ) Auth(msg.sender) {
        router = IDEXRouter(_dexRouter);
        pair = IDEXFactory(router.factory()).createPair(WBNB, address(this));
        _allowances[address(this)][address(router)] = _totalSupply;
        WBNB = router.WETH();
        distributor = new DividendDistributor(_dexRouter, SM);
        distributorAddress = address(distributor);

        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;
        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        buyBacker[msg.sender] = true;

        autoLiquidityReceiver = msg.sender;
        marketingFeeReceiver = msg.sender;

        approve(_dexRouter, _totalSupply);
        approve(address(pair), _totalSupply);
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    modifier onlyBuybacker() { require(buyBacker[msg.sender] == true, ""); _; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, _totalSupply);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != _totalSupply){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        checkTxLimit(sender, amount);
        //
        if(shouldSwapBack()){ swapBack(); }
        if(shouldAutoBuyback()){ triggerAutoBuyback(); }

        //        if(!launched() && recipient == pair){ require(_balances[sender] > 0); launch(); }

        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(sender, recipient, amount) : amount;

        _balances[recipient] = _balances[recipient].add(amountReceived);

        if(!isDividendExempt[sender]){ try distributor.setShare(sender, _balances[sender]) {} catch {} }
        if(!isDividendExempt[recipient]){ try distributor.setShare(recipient, _balances[recipient]) {} catch {} }

        try distributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        //        emit Transfer(sender, recipient, amount);
        return true;
    }



    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
    }

    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }

    function getTotalFee(bool selling) public returns (uint256) {
        if(launchedAt + 1 >= block.number){ return feeDenominator.sub(1); }
        if(selling){ return getMultipliedFee(); }
        return totalFee;
    }

    function getMultipliedFee() public returns (uint256) {
        if (launchedAtTimestamp + 1 days > block.timestamp) {
            return totalFee.mul(18000).div(feeDenominator);
        } else if (buybackMultiplierTriggeredAt.add(buybackMultiplierLength) > block.timestamp) {
            uint256 remainingTime = buybackMultiplierTriggeredAt.add(buybackMultiplierLength).sub(block.timestamp);
            uint256 feeIncrease = totalFee.mul(buybackMultiplierNumerator).div(buybackMultiplierDenominator).sub(totalFee);
            return totalFee.add(feeIncrease.mul(remainingTime).div(buybackMultiplierLength));
        }
        return totalFee;
    }

    function takeFee(address sender, address receiver, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount.mul(getTotalFee(receiver == pair)).div(feeDenominator);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }

    function swapBack() internal swapping {
        uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : liquidityFee;
        uint256 amountToLiquify = swapThreshold.mul(dynamicLiquidityFee).div(totalFee).div(2);
        uint256 amountToSwap = swapThreshold.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountBNB = address(this).balance.sub(balanceBefore);

        uint256 totalBNBFee = totalFee.sub(dynamicLiquidityFee.div(2));

        uint256 amountBNBLiquidity = amountBNB.mul(dynamicLiquidityFee).div(totalBNBFee).div(2);
        uint256 amountBNBReflection = amountBNB.mul(reflectionFee).div(totalBNBFee);
        uint256 amountBNBMarketing = amountBNB.mul(marketingFee).div(totalBNBFee);

        try distributor.deposit{value: amountBNBReflection}() {} catch {}
        payable(marketingFeeReceiver).call{value: amountBNBMarketing, gas: 30000}("");

        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }

    function shouldAutoBuyback() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && autoBuybackEnabled
        && autoBuybackBlockLast + autoBuybackBlockPeriod <= block.number // After N blocks from last buyback
        && address(this).balance >= autoBuybackAmount;
    }

    function triggerZeusBuyback(uint256 amount, bool triggerBuybackMultiplier) external authorized {
        buyTokens(amount, DEAD);
        if(triggerBuybackMultiplier){
            buybackMultiplierTriggeredAt = block.timestamp;
            emit BuybackMultiplierActive(buybackMultiplierLength);
        }
    }

    function clearBuybackMultiplier() external authorized {
        buybackMultiplierTriggeredAt = 0;
    }

    function triggerAutoBuyback() internal {
        buyTokens(autoBuybackAmount, DEAD);
        autoBuybackBlockLast = block.number;
        autoBuybackAccumulator = autoBuybackAccumulator.add(autoBuybackAmount);
        if(autoBuybackAccumulator > autoBuybackCap){ autoBuybackEnabled = false; }
    }

    function buyTokens(uint256 amount, address to) internal swapping {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(this);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            to,
            block.timestamp
        );
    }

    function setAutoBuybackSettings(bool _enabled, uint256 _cap, uint256 _amount, uint256 _period) external authorized {
        autoBuybackEnabled = _enabled;
        autoBuybackCap = _cap;
        autoBuybackAccumulator = 0;
        autoBuybackAmount = _amount;
        autoBuybackBlockPeriod = _period;
        autoBuybackBlockLast = block.number;
    }

    function setBuybackMultiplierSettings(uint256 numerator, uint256 denominator, uint256 length) external authorized {
        require(numerator / denominator <= 2 && numerator > denominator);
        buybackMultiplierNumerator = numerator;
        buybackMultiplierDenominator = denominator;
        buybackMultiplierLength = length;
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch(uint256 timestamp) public authorized {
        require(launchedAt == 0, "Already launched boi");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function setTxLimit(uint256 amount) external authorized {
        require(amount >= _totalSupply / 1000);
        _maxTxAmount = amount;
    }

    function setIsDividendExempt(address holder, bool exempt) external authorized {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if(exempt){
            distributor.setShare(holder, 0);
        }else{
            distributor.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external authorized {
        isFeeExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(address holder, bool exempt) external authorized {
        isTxLimitExempt[holder] = exempt;
    }

    function setFees(uint256 _liquidityFee, uint256 _buybackFee, uint256 _reflectionFee, uint256 _marketingFee, uint256 _feeDenominator) external authorized {
        liquidityFee = _liquidityFee;
        buybackFee = _buybackFee;
        reflectionFee = _reflectionFee;
        marketingFee = _marketingFee;
        totalFee = _liquidityFee.add(_buybackFee).add(_reflectionFee).add(_marketingFee);
        feeDenominator = _feeDenominator;
        require(totalFee < feeDenominator/4);
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver) external authorized {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount) external authorized {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

    function setTargetLiquidity(uint256 _target, uint256 _denominator) external authorized {
        targetLiquidity = _target;
        targetLiquidityDenominator = _denominator;
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external authorized {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setDistributorSettings(uint256 gas) external authorized {
        require(gas < 750000);
        distributorGas = gas;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
        return accuracy.mul(balanceOf(pair).mul(2)).div(getCirculatingSupply());
    }

    function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool) {
        return getLiquidityBacking(accuracy) > target;
    }

    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
    event BuybackMultiplierActive(uint256 duration);
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

import { SafeMath } from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import { IBEP20 } from "./interfaces/IBEP20.sol";
import { Auth } from "./Auth.sol";
import { IDEXRouter } from "./interfaces/IDEXRouter.sol";
import "./interfaces/IDividendDistributor.sol";

contract DividendDistributor is IDividendDistributor {
    using SafeMath for uint256;

    address _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IBEP20 SM = IBEP20(0x8076C74C5e3F5852037F31Ff0093Eeb8c8ADd8D3);
    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    IDEXRouter router;

    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;

    mapping (address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 1;
    uint256 public minDistribution = 100;

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }

    constructor (address _router, address reflectionToken) {
        router = _router != address(0)
        ? IDEXRouter(_router)
        : IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        _token = msg.sender;
        SM = IBEP20(reflectionToken);
    }

    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override onlyToken {
        uint256 balanceBefore = SM.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(SM);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amount = SM.balanceOf(address(this)).sub(balanceBefore);

        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares));
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while(gasUsed < gas && iterations < shareholderCount) {
            if(currentIndex >= shareholderCount){
                currentIndex = 0;
            }

            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
        && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0){
            totalDistributed = totalDistributed.add(amount);
            SM.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
}

interface IReflectionLocker {
    function claimTokens(uint) external returns (uint);
    function claimReflections() external returns (uint);
    function claimAll() external returns (uint, uint);

}

pragma solidity >=0.6.2;

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

