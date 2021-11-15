// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "./interfaces/IUniswapV2Router01.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "./HATMaster.sol";
import "./tokenlock/ITokenLockFactory.sol";
import "./Governable.sol";


contract  HATVaults is Governable, HATMaster {
    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    struct PendingApproval {
        address beneficiary;
        uint256 sevirity;
    }

    //pid -> (approver->boolean)
    mapping (uint256=>mapping(address => bool)) public committees;
    mapping(address => uint256) public swapAndBurns;

    //pid -> PendingApproval
    mapping(uint256 => PendingApproval) public pendingApproval;
    //hackerAddress ->(token->amount)
    mapping(address => mapping(address => uint256)) public hackersHatRewards;
    uint256[4] public defaultRewardsSplit = [8500, 500, 500, 400];
    uint256[] public defaultRewardLevel = [2000, 4000, 6000, 8000, 10000];
    uint256 internal constant REWARDS_LEVEL_DENOMINATOR = 10000;
    address public projectsRegistery;
    string public vaultName;
    ITokenLockFactory public immutable tokenLockFactory;
    uint256 public hatVestingDuration = 90 days;
    uint256 public hatVestingPeriods = 90;
    uint256 public constant WITHDRAW_PERIOD =  3000;
    uint256 public constant WITHDRAW_DISABLE_PERIOD =  240;
    IUniswapV2Router01 public immutable uniSwapRouter;

    // Info of each pool.
    struct ClaimReward {
        uint256 hackerReward;
        uint256 approverReward;
        uint256 swapAndBurn;
        uint256 hackerHatReward;
    }

    modifier onlyWithdrawPeriod(uint256 _pid) {
        //disable withdraw for 240 blocks each 3000 blocks.
        //to enable safe approveClaim period which prevents front running on committee approveClaim calls.
        require(block.number % (WITHDRAW_PERIOD + WITHDRAW_DISABLE_PERIOD) < WITHDRAW_PERIOD, "safty period");
        require(pendingApproval[_pid].beneficiary == address(0), "pending approval exist");
        _;
    }

    modifier onlyCommittee(uint256 _pid) {
        require(committees[_pid][msg.sender], "only committee");
        _;
    }

    event SetCommittee(uint256 indexed _pid, address[] indexed _committee, bool[] indexed _status);

    event AddPool(uint256 indexed _pid,
                uint256 indexed _allocPoint,
                address indexed _lpToken,
                string _name,
                address[] _committee,
                string _descriptionHash,
                uint256[] _rewardsLevels,
                uint256[4] _rewardsSplit,
                uint256 _rewardVestingDuration,
                uint256 _rewardVestingPeriods);

    event SetPool(uint256 indexed _pid, uint256 indexed _allocPoint, bool indexed _registered, string _descriptionHash);
    event Claim(address indexed _claimer, string _descriptionHash);
    event SetRewardsSplit(uint256 indexed _pid, uint256[4] indexed _rewardsSplit);
    event SetRewardsLevels(uint256 indexed _pid, uint256[] indexed _rewardsLevels);

    event SwapAndSend(uint256 indexed _pid,
                    address indexed _beneficiary,
                    uint256 indexed _amountSwaped,
                    uint256 _amountReceived,
                    address _tokenLock);

    event SwapAndBurn(uint256 indexed _pid, uint256 indexed _amountSwaped, uint256 indexed _amountBurnet);
    event SetVestingParams(uint256 indexed _pid, uint256 indexed _duration, uint256 indexed _periods);
    event SetHatVestingParams(uint256 indexed _duration, uint256 indexed _periods);

    event ClaimApprove(address indexed _approver,
                    uint256 indexed _poolId,
                    address indexed _beneficiary,
                    uint256 _sevirity,
                    uint256 _hackerReward,
                    uint256 _approverReward,
                    uint256 _swapAndBurn,
                    uint256 _hackerHatReward,
                    address _tokenLock);

    event PendingApprovalLog(uint256 indexed _pid, address indexed _beneficiary, uint256 indexed _sevirity);

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _rewardsToken,//hat
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _halvingAfterBlock,
        address _governance,
        IUniswapV2Router01 _uniSwapRouter,
        ITokenLockFactory _tokenLockFactory
    ) HATMaster(HATToken(_rewardsToken), _rewardPerBlock, _startBlock, _halvingAfterBlock) {
        Governable.initialize(_governance);
        uniSwapRouter = _uniSwapRouter;
        tokenLockFactory = _tokenLockFactory;
    }

    function pendingApprovalClaim(uint256 _poolId, address _beneficiary, uint256 _sevirity)
    external
    onlyCommittee(_poolId) {
        require(_beneficiary != address(0), "beneficiary is zero");
        require(pendingApproval[_poolId].beneficiary == address(0), "there is already pending approval");
        require(block.number % (WITHDRAW_PERIOD + WITHDRAW_DISABLE_PERIOD) >= WITHDRAW_PERIOD,
        "none safty period");

        pendingApproval[_poolId] = PendingApproval({
            beneficiary: _beneficiary,
            sevirity: _sevirity
        });
        emit PendingApprovalLog(_poolId, _beneficiary, _sevirity);
    }

    function dismissPendingApprovalClaim(uint256 _poolId) external onlyGovernance {
        delete pendingApproval[_poolId];
    }

    function approveClaim(uint256 _poolId) external onlyGovernance {
        require(pendingApproval[_poolId].beneficiary != address(0), "no pending approval");
        PoolReward storage poolReward = poolsRewards[_poolId];
        address beneficiary = pendingApproval[_poolId].beneficiary;
        uint256 sevirity = pendingApproval[_poolId].sevirity;
        delete pendingApproval[_poolId];

        IERC20 lpToken = poolInfo[_poolId].lpToken;
        ClaimReward memory claimRewards = calcClaimRewards(_poolId, sevirity);

        //hacker get its reward to a vesting contract
        address tokenLock = tokenLockFactory.createTokenLock(
            address(lpToken),
            governance(),
            beneficiary,
            claimRewards.hackerReward,
            block.timestamp, //start
            block.timestamp + poolReward.vestingDuration, //end
            poolReward.vestingPeriods,
            0, //no release start
            0, //no cliff
            ITokenLock.Revocability.Disabled,
            false
        );

        lpToken.safeTransfer(tokenLock, claimRewards.hackerReward);
        //approver get its rewards
        lpToken.safeTransfer(msg.sender, claimRewards.approverReward);
        //storing the amount of token which can be swap and burned
        //so it could be swapAndBurn by any one in a seperate tx.

        swapAndBurns[address(lpToken)] = swapAndBurns[address(lpToken)].add(claimRewards.swapAndBurn);
        hackersHatRewards[beneficiary][address(lpToken)] =
        hackersHatRewards[beneficiary][address(lpToken)].add(claimRewards.hackerHatReward);
        poolReward.pendingLpTokenRewards =
        poolReward.pendingLpTokenRewards
        .add(claimRewards.swapAndBurn)
        .add(claimRewards.hackerHatReward);

        emit ClaimApprove(msg.sender,
                        _poolId,
                        beneficiary,
                        sevirity,
                        claimRewards.hackerReward,
                        claimRewards.approverReward,
                        claimRewards.swapAndBurn,
                        claimRewards.hackerHatReward,
                        tokenLock);
        require(lpToken.balanceOf(address(this)).sub(poolReward.pendingLpTokenRewards) > 0,
        "total supply cannot be zero");
    }

    //_descriptionHash - a hash of an ipfs encrypted file which describe the claim.
    // this can be use later on by the claimer to prove her claim
    function claim(string memory _descriptionHash) external {
        emit Claim(msg.sender, _descriptionHash);
    }

    function setVestingParams(uint256 _pid, uint256 _duration, uint256 _periods) external onlyGovernance {
        require(_duration < 120 days, "vesting duration is too long");
        require(_periods > 0, "vesting periods cannot be zero");
        require(_duration >= _periods, "vesting duration smaller than periods");
        poolsRewards[_pid].vestingDuration = _duration;
        poolsRewards[_pid].vestingPeriods = _periods;
        emit SetVestingParams(_pid, _duration, _periods);
    }

    function setHatVestingParams(uint256 _duration, uint256 _periods) external onlyGovernance {
        require(_duration < 120 days, "vesting duration is too long");
        require(_periods > 0, "vesting periods cannot be zero");
        require(_duration >= _periods, "vesting duration smaller than periods");
        hatVestingDuration = _duration;
        hatVestingPeriods = _periods;
        emit SetHatVestingParams(_duration, _periods);
    }

    function setRewardsSplit(uint256 _pid, uint256[4] memory _rewardsSplit)
    external
    onlyGovernance {
        require(
            _rewardsSplit[0]+
            _rewardsSplit[1]+
            _rewardsSplit[2]+
            _rewardsSplit[3] < REWARDS_LEVEL_DENOMINATOR,
        "total split % should be less than 10000");
        poolsRewards[_pid].hackerRewardSplit = _rewardsSplit[0];
        poolsRewards[_pid].approverRewardSplit = _rewardsSplit[1];
        poolsRewards[_pid].swapAndBurnSplit = _rewardsSplit[2];
        poolsRewards[_pid].hackerHatRewardSplit = _rewardsSplit[3];
        emit SetRewardsSplit(_pid, _rewardsSplit);
    }

    function setRewardsLevels(uint256 _pid, uint256[] memory _rewardsLevels)
    external
    onlyCommittee(_pid) {
        for (uint256 i=0; i < _rewardsLevels.length; i++) {
            require(_rewardsLevels[i] <= REWARDS_LEVEL_DENOMINATOR, "reward level can't be more than 10000");
        }
        if (_rewardsLevels.length == 0) {
            poolsRewards[_pid].rewardsLevels = defaultRewardLevel;
        } else {
            poolsRewards[_pid].rewardsLevels = _rewardsLevels;
        }
        emit SetRewardsLevels(_pid, _rewardsLevels);
    }

    //use also for committee checkin.
    function setCommittee(uint256 _pid, address[] memory _committee, bool[] memory _status)
    external {
        //check if commitee already checked in.
        if (msg.sender == governance() && !committees[_pid][msg.sender]) {
            require(!poolsRewards[_pid].committeeCheckIn, "Committee already checked in");
        } else {
            require(committees[_pid][msg.sender], "only committee");
            poolsRewards[_pid].committeeCheckIn = true;
        }
        require(_committee.length == _status.length, "wrong length");
        require(_committee.length != 0, "empty committee");

        bool atLeastOneAddressIsTrue;
        for (uint256 i=0; i < _committee.length; i++) {
            committees[_pid][_committee[i]] = _status[i];
            if (!atLeastOneAddressIsTrue && _status[i]) {
                atLeastOneAddressIsTrue = true;
            }
        }
        require(atLeastOneAddressIsTrue);
        emit SetCommittee(_pid, _committee, _status);
    }

    /**
   * @dev addPool - onlyGovernance
   * @param _allocPoint the pool allocation point
   * @param _lpToken pool token
   * @param _committee pools committee addresses array
   * @param _rewardsLevels pool reward levels(sevirities)
     each level is a number between 0 and 10000.
   * @param _rewardsSplit pool reward split.
     each entry is a number between 0 and 10000.
     total splits should be less than 10000
   * @param _committee pools committee addresses array
   * @param _descriptionHash the hash of the pool description.
 */
    function addPool(uint256 _allocPoint,
                    address _lpToken,
                    address[] memory _committee,
                    uint256[] memory _rewardsLevels,
                    uint256[4] memory _rewardsSplit,
                    string memory _descriptionHash,
                    uint256 _rewardVestingDuration,
                    uint256 _rewardVestingPeriods)
    external
    onlyGovernance {
        require(_rewardVestingDuration < 120 days, "vesting duration is too long");
        require(_rewardVestingPeriods > 0, "vesting periods cannot be zero");
        require(_rewardVestingDuration >= _rewardVestingPeriods, "vesting duration smaller than periods");
        add(_allocPoint, IERC20(_lpToken));
        uint256 poolId = poolLength()-1;
        for (uint256 i=0; i < _committee.length; i++) {
            committees[poolId][_committee[i]] = true;
        }
        uint256[] memory rewardsLevels = _rewardsLevels.length == 0 ? defaultRewardLevel : _rewardsLevels;

        uint256[4] memory rewardsSplit = _rewardsSplit[0] == 0 ? defaultRewardsSplit : _rewardsSplit;

        for (uint256 i=0; i < rewardsLevels.length; i++) {
            require(rewardsLevels[i] <= REWARDS_LEVEL_DENOMINATOR, "reward level can't be more than 10000");
        }
        require(rewardsSplit[0]+rewardsSplit[1]+rewardsSplit[2]+rewardsSplit[3] < REWARDS_LEVEL_DENOMINATOR,
        "total split % should be less than 10000");

        poolsRewards[poolId] = PoolReward({
            rewardsLevels: rewardsLevels,
            pendingLpTokenRewards: 0,
            hackerRewardSplit: rewardsSplit[0],
            approverRewardSplit :rewardsSplit[1],
            swapAndBurnSplit: rewardsSplit[2],
            hackerHatRewardSplit: rewardsSplit[3],
            committeeCheckIn: false,
            vestingDuration: _rewardVestingDuration,
            vestingPeriods: _rewardVestingPeriods
        });

        string memory name = ERC20(_lpToken).name();

        emit AddPool(poolId,
                    _allocPoint,
                    address(_lpToken),
                    name,
                    _committee,
                    _descriptionHash,
                    rewardsLevels,
                    rewardsSplit,
                    _rewardVestingDuration,
                    _rewardVestingPeriods);
    }

    /**
   * @dev setPool
   * @param _pid the pool id
   * @param _allocPoint the pool allocation point
   * @param _registered does this pool is registered (default true)
   * @param _descriptionHash the hash of the pool description.
 */
    function setPool(uint256 _pid,
                    uint256 _allocPoint,
                    bool _registered,
                    string memory _descriptionHash)
    external onlyGovernance {
        require(poolInfo[_pid].lpToken != IERC20(address(0)), "pool does not exist");
        set(_pid, _allocPoint);
        //set approver only if commite not checkin.
        emit SetPool(_pid, _allocPoint, _registered, _descriptionHash);
    }

    // swapBurnSend swap lptoken to HAT.
    // send to beneficiary its hats rewards .
    // burn the rest of HAT.
    // only committee or governance are unauthorized to call this function.
    function swapBurnSend(uint256 _pid, address _beneficiary) external {
        //only committee or governance can call it.
        require(committees[_pid][msg.sender] || msg.sender == governance(), "only committee or governance");

        IERC20 token = poolInfo[_pid].lpToken;
        uint256 amountToSwapAndBurn = swapAndBurns[address(token)];
        uint256 amountForHackersHatRewards = hackersHatRewards[_beneficiary][address(token)];
        uint256 amount = amountToSwapAndBurn.add(amountForHackersHatRewards);
        require(amount > 0, "amount is zero");
        swapAndBurns[address(token)] = 0;
        hackersHatRewards[_beneficiary][address(token)] = 0;
        require(token.approve(address(uniSwapRouter), amount), "token approve failed");
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(HAT);
        //Swaps an exact amount of input tokens for as many output tokens as possible,
        //along the route determined by the path.
        uint256 hatBalanceBefore = HAT.balanceOf(address(this));
        uint256 hatsRecieved =
         // solhint-disable-next-line not-rely-on-time
        uniSwapRouter.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp)[1];
        require(HAT.balanceOf(address(this)) == hatBalanceBefore.add(hatsRecieved), "wrong amount received");
        poolsRewards[_pid].pendingLpTokenRewards = poolsRewards[_pid].pendingLpTokenRewards.sub(amount);
        uint256 burnetHats = hatsRecieved.mul(amountToSwapAndBurn).div(amount);
        if (burnetHats > 0) {
          //burn the relative HATs amount.
            HAT.burn(burnetHats);
        }
        emit SwapAndBurn(_pid, amount, burnetHats);
        address tokenLock;
        if (hatsRecieved.sub(burnetHats) > 0) {
           //hacker get the rest ...
            tokenLock = tokenLockFactory.createTokenLock(
                address(HAT),
                governance(),
                _beneficiary,
                hatsRecieved.sub(burnetHats),
                block.timestamp, //start
                block.timestamp + hatVestingDuration, //end
                hatVestingPeriods,
                0, //no release start
                0, //no cliff
                ITokenLock.Revocability.Disabled,
                true
            );
            HAT.transfer(tokenLock, hatsRecieved.sub(burnetHats));
        }
        emit SwapAndSend(_pid, _beneficiary, amount, hatsRecieved.sub(burnetHats), tokenLock);
    }

    function withdraw(uint256 _pid, uint256 _amount) external onlyWithdrawPeriod(_pid) {
        _withdraw(_pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) external onlyWithdrawPeriod(_pid) {
        _emergencyWithdraw(_pid);
    }

    function getPoolRewardsLevels(uint256 _poolId) external view returns(uint256[] memory) {
        return poolsRewards[_poolId].rewardsLevels;
    }

    function getPoolRewardsPendingLpToken(uint256 _poolId) external view returns(uint256) {
        return poolsRewards[_poolId].pendingLpTokenRewards;
    }

    function getPoolRewards(uint256 _poolId) external view returns(PoolReward memory) {
        return poolsRewards[_poolId];
    }

    function calcClaimRewards(uint256 _poolId, uint256 _sevirity) public view returns(ClaimReward memory claimRewards) {
        IERC20 lpToken = poolInfo[_poolId].lpToken;
        uint256 totalSupply = lpToken.balanceOf(address(this)).sub(poolsRewards[_poolId].pendingLpTokenRewards);
        require(totalSupply > 0, "totalSupply is zero");
        require(_sevirity < poolsRewards[_poolId].rewardsLevels.length, "_sevirity is not in the range");
        //hackingRewardAmount
        uint256 claimRewardAmount =
        totalSupply.mul(poolsRewards[_poolId].rewardsLevels[_sevirity]).div(REWARDS_LEVEL_DENOMINATOR);
        //hackerReward
        claimRewards.hackerReward =
        claimRewardAmount.mul(poolsRewards[_poolId].hackerRewardSplit).div(REWARDS_LEVEL_DENOMINATOR);
        //approverReward
        claimRewards.approverReward =
        claimRewardAmount.mul(poolsRewards[_poolId].approverRewardSplit).div(REWARDS_LEVEL_DENOMINATOR);
        //swapAndBurnAmount
        claimRewards.swapAndBurn =
        claimRewardAmount.mul(poolsRewards[_poolId].swapAndBurnSplit).div(REWARDS_LEVEL_DENOMINATOR);
        //hackerHatReward
        claimRewards.hackerHatReward =
        claimRewardAmount.mul(poolsRewards[_poolId].hackerHatRewardSplit).div(REWARDS_LEVEL_DENOMINATOR);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IUniswapV2Router01 {
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
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
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
contract ERC20 is Context, IERC20 {
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
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
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
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overloaded;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;


import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";
import "./HATToken.sol";


contract HATMaster {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct PoolUpdate {
        uint256 blockNumber;// update blocknumber
        uint256 totalAllocPoint; //totalAllocPoint
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardPerShare;
        uint256 totalUsersAmount;
        uint256 lastProcessedTotalAllocPoint;
    }

    // Info of each pool.
    struct PoolReward {
        uint256 pendingLpTokenRewards;
        uint256 hackerRewardSplit;
        uint256 approverRewardSplit;
        uint256 swapAndBurnSplit;
        uint256 hackerHatRewardSplit;
        uint256[]  rewardsLevels;
        bool committeeCheckIn;
        uint256 vestingDuration;
        uint256 vestingPeriods;
    }

    HATToken public immutable HAT;

    uint256 public immutable REWARD_PER_BLOCK;
    uint256[] public REWARD_MULTIPLIER = [688, 413, 310, 232, 209, 188, 169, 152, 137, 123, 111, 100];
    uint256[] public HALVING_AT_BLOCK;

    uint256 public immutable START_BLOCK;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    //blockNumber to index in globalPoolUpdates
    mapping(uint256 => uint256) public totalAllocPointUpdatedAtBlock;
    PoolUpdate[] public globalPoolUpdates;
    mapping(address => uint256) public poolId1; // poolId1 count from 1, subtraction 1 before using with poolInfo
    // Info of each user that stakes LP tokens. pid => user address => info
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    //pid -> PoolReward
    mapping (uint256=>PoolReward) internal poolsRewards;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SendReward(address indexed user, uint256 indexed pid, uint256 amount, uint256 requestedAmount);
    event MassUpdatePools(uint256 _fromPid, uint256 _toPid);

    constructor(
        HATToken _HAT,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _halvingAfterBlock
    ) {
        HAT = _HAT;
        REWARD_PER_BLOCK = _rewardPerBlock;
        START_BLOCK = _startBlock;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtBlock = _halvingAfterBlock.mul(i + 1).add(_startBlock);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        HALVING_AT_BLOCK.push(type(uint256).max);
    }

  /**
   * @dev massUpdatePools - Update reward vairables for all pools
   * Be careful of gas spending!
   * @param _fromPid update pools range from this pool id
   * @param _toPid update pools range to this pool id
   */
    function massUpdatePools(uint256 _fromPid, uint256 _toPid) external {
        require(_toPid <= poolInfo.length, "pool range is too big");
        require(_fromPid <= _toPid, "invalid pool range");
        for (uint256 pid = _fromPid; pid < _toPid; ++pid) {
            updatePool(pid);
        }
        emit MassUpdatePools(_fromPid, _toPid);
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        pool.lastProcessedTotalAllocPoint = globalPoolUpdates.length-1;

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.totalUsersAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 reward = calcPoolReward(_pid);
        //the original BDPMaster was reverted if the reward is zero to to the cap check of at the BDP token.
        if (reward > 0) {
            HAT.mint(address(this), reward);
        }

        pool.rewardPerShare = pool.rewardPerShare.add(reward.mul(1e12).div(pool.totalUsersAmount));
        pool.lastRewardBlock = block.number;
    }

    // --------- For user ----------------
    function deposit(uint256 _pid, uint256 _amount) public {
        require(poolsRewards[_pid].committeeCheckIn, "committee not checked in yet");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeTransferReward(msg.sender, pending, _pid);
            }
        }
        if (_amount > 0) {
            uint256 lpSupply = pool.lpToken.balanceOf(address(this)).sub(poolsRewards[_pid].pendingLpTokenRewards);
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 factoredAmount = _amount;
            if (pool.totalUsersAmount > 0) {
                factoredAmount = pool.totalUsersAmount.mul(_amount).div(lpSupply);
            }
            user.amount = user.amount.add(factoredAmount);
            pool.totalUsersAmount = pool.totalUsersAmount.add(factoredAmount);
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function claimReward(uint256 _pid) public {
        deposit(_pid, 0);
    }

    // GET INFO for UI
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256 result) {
        if (_from < START_BLOCK) return 0;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }
    }

    function getPoolReward(uint256 _from, uint256 _to, uint256 _allocPoint, uint256 _totalAllocPoint)
    public
    view
    returns (uint) {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount = (multiplier.mul(REWARD_PER_BLOCK).mul(_allocPoint).div(_totalAllocPoint)).div(100);
        uint256 amountCanMint = HAT.minters(address(this));
        return amountCanMint < amount ? amountCanMint : amount;
    }

    function getRewardPerBlock(uint256 pid1) public view returns (uint256) {
        uint256 multiplier = getMultiplier(block.number -1, block.number);
        if (pid1 == 0) {
            return (multiplier.mul(REWARD_PER_BLOCK)).div(100);
        } else {
            return (multiplier
                .mul(REWARD_PER_BLOCK)
                .mul(poolInfo[pid1 - 1].allocPoint)
                .div(globalPoolUpdates[globalPoolUpdates.length-1].totalAllocPoint))
                .div(100);
        }
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        if (block.number > pool.lastRewardBlock && pool.totalUsersAmount > 0) {
            uint256 reward = calcPoolReward(_pid);
            rewardPerShare = rewardPerShare.add(reward.mul(1e12).div(pool.totalUsersAmount));
        }
        return user.amount.mul(rewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function getGlobalPoolUpdatesLength() public view returns (uint256) {
        return globalPoolUpdates.length;
    }

    function getStakedAmount(uint _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return  user.amount;
    }

    /**
     * @dev calcPoolReward -
     * calculate rewards for a pool by iterate over the history of totalAllocPoints updates.
     * and sum up all rewards periods from pool.lastRewardBlock till current block number.
     * Be careful of gas spending!
     * @param _pid pool id
     * @return reward
     */
    function calcPoolReward(uint256 _pid) public view returns(uint256 reward) {
        uint256 from = poolInfo[_pid].lastRewardBlock;
        uint256 poolAllocPoint = poolInfo[_pid].allocPoint;
        PoolUpdate[] memory poolUpdates  =  globalPoolUpdates;
        uint256 poolUpdatesLength = poolUpdates.length;

        if (poolUpdates[poolUpdatesLength-1].blockNumber <= from) {
            return getPoolReward(from,
            block.number,
            poolAllocPoint,
            poolUpdates[poolUpdatesLength-1].totalAllocPoint);
        }

        uint256 index = poolInfo[_pid].lastProcessedTotalAllocPoint;

        for (index; index < poolUpdatesLength; index++) {
            reward = reward.add(getPoolReward(from,
            poolUpdates[index].blockNumber,
            poolAllocPoint,
            poolUpdates[index-1].totalAllocPoint));
            from = poolUpdates[index].blockNumber;
        }

        return reward.add(getPoolReward(from,
                block.number,
                poolAllocPoint,
                poolUpdates[poolUpdatesLength-1].totalAllocPoint));
    }

    function _withdraw(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 lpSupply = pool.lpToken.balanceOf(address(this)).sub(poolsRewards[_pid].pendingLpTokenRewards);
        require(user.amount >= _amount, "withdraw: not enough user balance");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeTransferReward(msg.sender, pending, _pid);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount.mul(lpSupply).div(pool.totalUsersAmount));
            pool.totalUsersAmount = pool.totalUsersAmount.sub(_amount);

        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function _emergencyWithdraw(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "user.amount = 0");

        uint256 lpSupply = pool.lpToken.balanceOf(address(this)).sub(poolsRewards[_pid].pendingLpTokenRewards);
        uint256 factoredBalance = user.amount.mul(lpSupply).div(pool.totalUsersAmount);
        pool.totalUsersAmount = pool.totalUsersAmount.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), factoredBalance);
        emit EmergencyWithdraw(msg.sender, _pid, factoredBalance);
    }

    // -------- For manage pool ---------
    function add(uint256 _allocPoint, IERC20 _lpToken) internal {
        require(poolId1[address(_lpToken)] == 0, "HATMaster::add: lp is already in pool");
        uint256 lastRewardBlock = block.number > START_BLOCK ? block.number : START_BLOCK;

        poolId1[address(_lpToken)] = poolInfo.length + 1;

        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            rewardPerShare: 0,
            totalUsersAmount: 0,
            lastProcessedTotalAllocPoint: 0
        }));

        uint256 totalAllocPoint = (globalPoolUpdates.length == 0) ? _allocPoint :
        globalPoolUpdates[globalPoolUpdates.length-1].totalAllocPoint.add(_allocPoint);

        if (totalAllocPointUpdatedAtBlock[block.number] != 0) {
           //already update in this block
            globalPoolUpdates[totalAllocPointUpdatedAtBlock[block.number]-1].totalAllocPoint = totalAllocPoint;
        } else {
            globalPoolUpdates.push(PoolUpdate({
                blockNumber: block.number,
                totalAllocPoint: totalAllocPoint
            }));
            totalAllocPointUpdatedAtBlock[block.number] = globalPoolUpdates.length;
        }
    }

    function set(uint256 _pid, uint256 _allocPoint) internal {
        updatePool(_pid);
        uint256 totalAllocPoint =
        globalPoolUpdates[globalPoolUpdates.length-1].totalAllocPoint
        .sub(poolInfo[_pid].allocPoint).add(_allocPoint);

        if (totalAllocPointUpdatedAtBlock[block.number] != 0) {
           //already update in this block
            globalPoolUpdates[totalAllocPointUpdatedAtBlock[block.number]-1].totalAllocPoint = totalAllocPoint;
        } else {
            globalPoolUpdates.push(PoolUpdate({
                blockNumber: block.number,
                totalAllocPoint: totalAllocPoint
            }));
            totalAllocPointUpdatedAtBlock[block.number] = globalPoolUpdates.length;
        }
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // -----------------------------
    function safeTransferReward(address _to, uint256 _amount, uint256 _pid) internal {
        uint256 bal = HAT.balanceOf(address(this));
        if (_amount > bal) {
            HAT.transfer(_to, bal);
            emit SendReward(_to, _pid, bal, _amount);
        } else {
            HAT.transfer(_to, _amount);
            emit SendReward(_to, _pid, _amount, _amount);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ITokenLock.sol";

interface ITokenLockFactory {
    // -- Factory --
    function setMasterCopy(address _masterCopy) external;

    function createTokenLock(
        address _token,
        address _owner,
        address _beneficiary,
        uint256 _managedAmount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _periods,
        uint256 _releaseStartTime,
        uint256 _vestingCliffTime,
        ITokenLock.Revocability _revocable,
        bool _canDelegate
    ) external returns(address contractAddress);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an governance) that can be granted exclusive access to
 * specific functions.
 *
 * The governance account will be passed on initialization of the contract. This
 * can later be changed with {setPendingGovernance and then transferGovernorship  after 12000 blocks}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyGovernance`, which can be applied to your functions to restrict their use to
 * the governance.
 */
contract Governable {
    address private _governance;
    address public governancePending;
    uint256 public setGovernancePendingAtBlock;
    uint256 public constant TIME_LOCK_DELAY_IN_BLOCKS_UNIT = 12000;


    /// @notice An event thats emitted when a new governance address is set
    event GovernorshipTransferred(address indexed _previousGovernance, address indexed _newGovernance);
    /// @notice An event thats emitted when a new governance address is pending
    event GovernancePending(address indexed _previousGovernance, address indexed _newGovernance, uint256 _atBlock);

    /**
     * @dev Throws if called by any account other than the governance.
     */
    modifier onlyGovernance() {
        require(msg.sender == _governance, "only governance");
        _;
    }

    /**
     * @dev setPendingGovernance set a pending governance address.
     * NOTE: transferGovernorship can be called after a time delay of 12000 blocks.
     */
    function setPendingGovernance(address _newGovernance) external  onlyGovernance {
        require(_newGovernance != address(0), "Governable:new governance is the zero address");
        governancePending = _newGovernance;
        setGovernancePendingAtBlock = block.number;
        emit GovernancePending(_governance, _newGovernance, block.number);
    }

    /**
     * @dev transferGovernorship transfer governorship to the pending governance address.
     * NOTE: transferGovernorship can be called after a time delay of 12000 blocks from the latest setPendingGovernance.
     */
    function transferGovernorship() external  onlyGovernance {
        require(setGovernancePendingAtBlock > 0, "Governable: no pending governance");
        require(block.number - setGovernancePendingAtBlock > TIME_LOCK_DELAY_IN_BLOCKS_UNIT,
        "Governable: cannot confirm governance at this time");
        emit GovernorshipTransferred(_governance, governancePending);
        _governance = governancePending;
        setGovernancePendingAtBlock = 0;
    }

    /**
     * @dev Returns the address of the current governance.
     */
    function governance() public view returns (address) {
        return _governance;
    }

    /**
     * @dev Initializes the contract setting the initial governance.
     */
    function initialize(address _initialGovernance) internal {
        _governance = _initialGovernance;
        emit GovernorshipTransferred(address(0), _initialGovernance);
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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";


contract HATToken {

    struct PendingMinter {
        uint256 seedAmount;
        uint256 setMinterPendingAtBlock;
    }

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice EIP-20 token name for this token
    string public constant name = "HATToken";

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = "HAT";

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Total number of tokens in circulation
    uint public totalSupply;

    address public governance;
    address public governancePending;
    uint256 public setGovernancePendingAtBlock;
    uint256 public timeLockDelayInBlocksUnits;
    uint256 public cap = 500000e18;

    /// @notice Address which may mint new tokens
    /// minter -> minting seedAmount
    mapping (address => uint256) public minters;

    /// @notice Address which may mint new tokens
    /// minter -> minting seedAmount
    mapping (address => PendingMinter) public pendingMinters;

    // @notice Allowance amounts on behalf of others
    mapping (address => mapping (address => uint96)) internal allowances;

    // @notice Official record of token balances for each account
    mapping (address => uint96) internal balances;

    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice An event thats emitted when a new minter address is pending
    event MinterPending(address indexed minter, uint256 seedAmount, uint256 atBlock);
    /// @notice An event thats emitted when the minter address is changed
    event MinterChanged(address indexed minter, uint256 seedAmount);
    /// @notice An event thats emitted when a new governance address is pending
    event GovernancePending(address indexed oldGovernance, address indexed newGovernance, uint256 atBlock);
    /// @notice An event thats emitted when a new governance address is set
    event GovernanceChanged(address indexed oldGovernance, address indexed newGovernance);
    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);
    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @notice The standard EIP-20 approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /**
     * @notice Construct a new HAT token
     */
    constructor(address _governance, uint256 _timeLockDelayInBlocksUnits) {
        governance = _governance;
        timeLockDelayInBlocksUnits = _timeLockDelayInBlocksUnits;
    }

    function setPendingGovernance(address _governance) public {
        require(msg.sender == governance, "HAT:!governance");
        require(_governance != address(0), "HAT:!_governance");
        governancePending = _governance;
        setGovernancePendingAtBlock = block.number;
        emit GovernancePending(governance, _governance, block.number);
    }

    function confirmGovernance() public {
        require(msg.sender == governance, "HAT:!governance");
        require(setGovernancePendingAtBlock > 0, "HAT:!governancePending");
        require(block.number - setGovernancePendingAtBlock > timeLockDelayInBlocksUnits,
        "HAT: cannot confirm governance at this time");
        emit GovernanceChanged(governance, governancePending);
        governance = governancePending;
        setGovernancePendingAtBlock = 0;
    }

    function setPendingMinter(address _minter, uint256 _cap) public {
        require(msg.sender == governance, "HAT::!governance");
        pendingMinters[_minter].seedAmount = _cap;
        pendingMinters[_minter].setMinterPendingAtBlock = block.number;
        emit MinterPending(_minter, _cap, block.number);
    }

    function confirmMinter(address _minter) public {
        require(msg.sender == governance, "HAT::mint: only the governance can confirm minter");
        require(pendingMinters[_minter].setMinterPendingAtBlock > 0, "HAT:: no pending minter was set");
        require(block.number - pendingMinters[_minter].setMinterPendingAtBlock > timeLockDelayInBlocksUnits,
        "HATToken: cannot confirm at this time");
        minters[_minter] = pendingMinters[_minter].seedAmount;
        pendingMinters[_minter].setMinterPendingAtBlock = 0;
        emit MinterChanged(_minter, pendingMinters[_minter].seedAmount);
    }

    function burn(uint256 _amount) public {
        return _burn(msg.sender, _amount);
    }

    function mint(address _account, uint _amount) public {
        require(minters[msg.sender] >= _amount, "HATToken: amount greater than limitation");
        minters[msg.sender] = SafeMath.sub(minters[msg.sender], _amount);
        _mint(_account, _amount);
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender) external view returns (uint) {
        return allowances[account][spender];
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint rawAmount) external returns (bool) {
        uint96 amount;
        if (rawAmount == type(uint256).max) {
            amount = type(uint96).max;
        } else {
            amount = safe96(rawAmount, "HAT::approve: amount exceeds 96 bits");
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
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
    function increaseAllowance(address spender, uint addedValue) public virtual returns (bool) {
        require(spender != address(0), "HAT: increaseAllowance to the zero address");
        uint96 valueToAdd = safe96(addedValue, "HAT::increaseAllowance: addedValue exceeds 96 bits");
        allowances[msg.sender][spender] =
        add96(allowances[msg.sender][spender], valueToAdd, "HAT::increaseAllowance: overflows");
        emit Approval(msg.sender, spender, allowances[msg.sender][spender]);
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
    function decreaseAllowance(address spender, uint subtractedValue) public virtual returns (bool) {
        require(spender != address(0), "HAT: decreaseAllowance to the zero address");
        uint96 valueTosubtract = safe96(subtractedValue, "HAT::decreaseAllowance: subtractedValue exceeds 96 bits");
        allowances[msg.sender][spender] = sub96(allowances[msg.sender][spender], valueTosubtract,
        "HAT::decreaseAllowance: spender allowance is less than subtractedValue");
        emit Approval(msg.sender, spender, allowances[msg.sender][spender]);
        return true;
    }

    /**
     * @notice Triggers an approval from owner to spends
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(address owner, address spender, uint rawAmount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        uint96 amount;
        if (rawAmount == type(uint256).max) {
            amount = type(uint96).max;
        } else {
            amount = safe96(rawAmount, "HAT::permit: amount exceeds 96 bits");
        }

        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, rawAmount, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "HAT::permit: invalid signature");
        require(signatory == owner, "HAT::permit: unauthorized");
        require(block.timestamp <= deadline, "HAT::permit: signature expired");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint rawAmount) external returns (bool) {
        uint96 amount = safe96(rawAmount, "HAT::transfer: amount exceeds 96 bits");
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint rawAmount) external returns (bool) {
        address spender = msg.sender;
        uint96 spenderAllowance = allowances[src][spender];
        uint96 amount = safe96(rawAmount, "HAT::approve: amount exceeds 96 bits");

        if (spender != src && spenderAllowance != type(uint96).max) {
            uint96 newAllowance = sub96(spenderAllowance, amount, "HAT::transferFrom: transfer amount exceeds spender allowance");
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(address delegatee, uint nonce, uint expiry, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "HAT::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "HAT::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "HAT::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, "HAT::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    /**
     * @notice Mint new tokens
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to be minted
     */
    function _mint(address dst, uint rawAmount) internal {
        require(dst != address(0), "HAT::mint: cannot transfer to the zero address");
        require(SafeMath.add(totalSupply, rawAmount) <= cap, "ERC20Capped: cap exceeded");

        // mint the amount
        uint96 amount = safe96(rawAmount, "HAT::mint: amount exceeds 96 bits");
        totalSupply = safe96(SafeMath.add(totalSupply, amount), "HAT::mint: totalSupply exceeds 96 bits");

        // transfer the amount to the recipient
        balances[dst] = add96(balances[dst], amount, "HAT::mint: transfer amount overflows");
        emit Transfer(address(0), dst, amount);

        // move delegates
        _moveDelegates(address(0), delegates[dst], amount);
    }

    /**
     * Burn tokens
     * @param src The address of the source account
     * @param rawAmount The number of tokens to be burned
     */
    function _burn(address src, uint rawAmount) internal {
        require(src != address(0), "HAT::burn: cannot burn to the zero address");

        // mint the amount
        uint96 amount = safe96(rawAmount, "HAT::burn: amount exceeds 96 bits");
        totalSupply = safe96(SafeMath.sub(totalSupply, amount), "HAT::mint: totalSupply exceeds 96 bits");

        // transfer the amount to the recipient
        balances[src] = sub96(balances[src], amount, "HAT::burn: burn amount exceeds balance");
        emit Transfer(src, address(0), amount);

        // move delegates
        _moveDelegates(delegates[src], address(0), amount);
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _transferTokens(address src, address dst, uint96 amount) internal {
        require(src != address(0), "HAT::_transferTokens: cannot transfer from the zero address");
        require(dst != address(0), "HAT::_transferTokens: cannot transfer to the zero address");

        balances[src] = sub96(balances[src], amount, "HAT::_transferTokens: transfer amount exceeds balance");
        balances[dst] = add96(balances[dst], amount, "HAT::_transferTokens: transfer amount overflows");
        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    function _moveDelegates(address srcRep, address dstRep, uint96 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = sub96(srcRepOld, amount, "HAT::_moveVotes: vote amount underflows");
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, "HAT::_moveVotes: vote amount overflows");
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint96 oldVotes, uint96 newVotes) internal {
      uint32 blockNumber = safe32(block.number, "HAT::_writeCheckpoint: block number exceeds 32 bits");

      if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function safe96(uint n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function add96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(uint96 a, uint96 b, string memory errorMessage) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

interface ITokenLock {
    enum Revocability { NotSet, Enabled, Disabled }

    // -- Balances --

    function currentBalance() external view returns (uint256);

    // -- Time & Periods --

    function currentTime() external view returns (uint256);

    function duration() external view returns (uint256);

    function sinceStartTime() external view returns (uint256);

    function amountPerPeriod() external view returns (uint256);

    function periodDuration() external view returns (uint256);

    function currentPeriod() external view returns (uint256);

    function passedPeriods() external view returns (uint256);

    // -- Locking & Release Schedule --

    function availableAmount() external view returns (uint256);

    function vestedAmount() external view returns (uint256);

    function releasableAmount() external view returns (uint256);

    function totalOutstandingAmount() external view returns (uint256);

    function surplusAmount() external view returns (uint256);

    // -- Value Transfer --

    function release() external;

    function withdrawSurplus(uint256 _amount) external;

    function revoke() external;
}

