// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "../interface/IBookkeeper.sol";
import "./Controllable.sol";

/// @title Contract for holding statistical info and doesn't affect any funds.
/// @dev Only not critical functional. Use with TetuProxy
/// @author belbix
contract Bookkeeper is IBookkeeper, Initializable, Controllable {
  using SafeMathUpgradeable for uint256;

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant VERSION = "1.0.0";

  // DO NOT CHANGE NAMES OR ORDERING!
  /// @dev Add when Controller register vault. Can have another length than strategies.
  address[] private _vaults;
  /// @dev Add when Controller register strategy. Can have another length than vaults.
  address[] private _strategies;
  /// @inheritdoc IBookkeeper
  mapping(address => uint256) public override targetTokenEarned;
  mapping(address => HardWork) private _lastHardWork;
  /// @inheritdoc IBookkeeper
  mapping(address => mapping(address => uint256)) public override vaultUsersBalances;
  /// @inheritdoc IBookkeeper
  mapping(address => mapping(address => mapping(address => uint256))) public override userEarned;
  /// @inheritdoc IBookkeeper
  mapping(address => uint256) public override vaultUsersQuantity;
  /// @dev Hold last price per full share change for given user
  mapping(address => PpfsChange) private _lastPpfsChange;
  mapping(address => uint256) public fundKeeperEarned;

  /// @notice Vault added
  event RegisterVault(address value);
  /// @notice Vault removed
  event RemoveVault(address value);
  /// @notice Strategy added
  event RegisterStrategy(address value);
  /// @notice Strategy removed
  event RemoveStrategy(address value);
  /// @notice Strategy earned this TETU amount during doHardWork call
  event RegisterStrategyEarned(address indexed strategy, uint256 amount);
  /// @notice FundKeeper earned this USDC amount during doHardWork call
  event RegisterFundKeeperEarned(address indexed token, uint256 amount);
  /// @notice User deposit/withdraw action
  event RegisterUserAction(address indexed user, uint256 amount, bool deposit);
  /// @notice User claim reward
  event RegisterUserEarned(address indexed user, address vault, address token, uint256 amount);
  /// @notice Vault's PricePer Full Share changed
  event RegisterPpfsChange(address indexed vault, uint256 oldValue, uint256 newValue);

  /// @notice Initialize contract after setup it as proxy implementation
  /// @dev Use it only once after first logic setup
  /// @param _controller Controller address
  function initialize(address _controller) external initializer {
    Controllable.initializeControllable(_controller);
  }

  /// @dev Only registered strategy allowed
  modifier onlyStrategy() {
    require(IController(controller()).strategies(msg.sender), "only exist strategy");
    _;
  }

  /// @dev Only FeeRewardForwarder contract allowed
  modifier onlyFeeRewardForwarder() {
    require(IController(controller()).feeRewardForwarder() == msg.sender, "only exist forwarder");
    _;
  }

  /// @dev Only registered vault allowed
  modifier onlyVault() {
    require(IController(controller()).vaults(msg.sender), "only exist vault");
    _;
  }

  /// @notice Add Vault and Strategy if they not exist. Only Controller or Governance
  /// @dev Manually we should add a pair vault / strategy for keep both array in the same state
  /// @param _vault Vault address
  /// @param _strategy Strategy address
  function addVaultAndStrategy(address _vault, address _strategy) external onlyControllerOrGovernance {
    addVault(_vault);
    addStrategy(_strategy);
  }

  /// @notice Add Vault if it is not exist. Only Controller sender allowed
  /// @param _vault Vault address
  function addVault(address _vault) public override onlyControllerOrGovernance {
    if (!isVaultExist(_vault)) {
      _vaults.push(_vault);
      emit RegisterVault(_vault);
    }
  }

  /// @notice Add Strategy if it is not exist. Only Controller sender allowed
  /// @param _strategy Strategy address
  function addStrategy(address _strategy) public override onlyControllerOrGovernance {
    if (!isStrategyExist(_strategy)) {
      _strategies.push(_strategy);
      emit RegisterStrategy(_strategy);
    }
  }

  /// @notice Only Strategy action. Save TETU earned values
  /// @dev It should represent 100% of earned rewards including all fees.
  /// @param _targetTokenAmount Earned amount
  function registerStrategyEarned(uint256 _targetTokenAmount) external override onlyStrategy {
    targetTokenEarned[msg.sender] = targetTokenEarned[msg.sender].add(_targetTokenAmount);

    _lastHardWork[msg.sender] = HardWork(
      msg.sender,
      block.number,
      block.timestamp,
      _targetTokenAmount
    );
    emit RegisterStrategyEarned(msg.sender, _targetTokenAmount);
  }

  /// @notice Only FeeRewardForwarder action. Save Fund Token earned value for given token
  /// @param _fundTokenAmount Earned amount
  function registerFundKeeperEarned(address _token, uint256 _fundTokenAmount) external override onlyFeeRewardForwarder {
    fundKeeperEarned[_token] = fundKeeperEarned[_token].add(_fundTokenAmount);
    emit RegisterFundKeeperEarned(_token, _fundTokenAmount);
  }

  /// @notice FeeRewardForwarder action.
  ///         Register Price Per Full Share change for given vault
  /// @param vault Vault address
  /// @param value Price Per Full Share change
  function registerPpfsChange(address vault, uint256 value)
  external override onlyFeeRewardForwarder {
    PpfsChange memory lastPpfs = _lastPpfsChange[vault];
    _lastPpfsChange[vault] = PpfsChange(
      vault,
      block.number,
      block.timestamp,
      value,
      lastPpfs.block,
      lastPpfs.time,
      lastPpfs.value
    );
    emit RegisterPpfsChange(vault, lastPpfs.value, value);
  }

  /// @notice Vault action. Register user's deposit/withdraw
  /// @dev Should register any mint/burn of the share token
  /// @param _user User address
  /// @param _amount Share amount for deposit/withdraw
  /// @param _deposit true = deposit, false = withdraw
  function registerUserAction(address _user, uint256 _amount, bool _deposit)
  external override onlyVault {
    if (vaultUsersBalances[msg.sender][_user] == 0) {
      vaultUsersQuantity[msg.sender] = vaultUsersQuantity[msg.sender].add(1);
    }
    if (_deposit) {
      vaultUsersBalances[msg.sender][_user] = vaultUsersBalances[msg.sender][_user].add(_amount);
    } else {
      // avoid overflow if we missed something
      // in this unreal case better do nothing
      if (vaultUsersBalances[msg.sender][_user] >= _amount) {
        vaultUsersBalances[msg.sender][_user] = vaultUsersBalances[msg.sender][_user].sub(_amount);
      }
    }
    if (vaultUsersBalances[msg.sender][_user] == 0) {
      vaultUsersQuantity[msg.sender] = vaultUsersQuantity[msg.sender].sub(1);
    }
    emit RegisterUserAction(_user, _amount, _deposit);
  }

  /// @notice Vault action. Register any share token transfer.
  ///         Burn/mint ignored - should be handled in registerUserAction()
  /// @param from Sender address
  /// @param to Recipient address
  /// @param amount Transaction amount
  function registerVaultTransfer(address from, address to, uint256 amount) external override onlyVault {
    // in this unreal cases better to do nothing
    if (vaultUsersBalances[msg.sender][from] < amount || amount == 0) {
      return;
    }

    // don't count mint and burn - it should be covered in registerUserAction
    if (from == address(0) || to == address(0)) {
      return;
    }

    // decrease sender balance
    vaultUsersBalances[msg.sender][from] = vaultUsersBalances[msg.sender][from].sub(amount);

    // if recipient didn't have balance - increase user quantity
    if (vaultUsersBalances[msg.sender][to] == 0) {
      vaultUsersQuantity[msg.sender] = vaultUsersQuantity[msg.sender].add(1);
    }
    // increase recipient balance
    vaultUsersBalances[msg.sender][to] = vaultUsersBalances[msg.sender][to].add(amount);

    // if sender sent all amount decrease user quantity
    if (vaultUsersBalances[msg.sender][from] == 0) {
      vaultUsersQuantity[msg.sender] = vaultUsersQuantity[msg.sender].sub(1);
    }
  }

  /// @notice Only Vault can call it. Register user's claimed amount of given token
  /// @param _user User address
  /// @param _vault Vault address
  /// @param _rt Reward Token address
  /// @param _amount Claimed amount
  function registerUserEarned(address _user, address _vault, address _rt, uint256 _amount)
  external override onlyVault {
    userEarned[_user][_vault][_rt] = userEarned[_user][_vault][_rt].add(_amount);
    emit RegisterUserEarned(_user, _vault, _rt, _amount);
  }

  /// @notice Return vaults array
  /// @dev This function should not use in any critical logics because DoS possible
  /// @return Array of all registered vaults
  function vaults() external override view returns (address[] memory) {
    return _vaults;
  }

  /// @notice Return strategy array
  /// @dev This function should not use in any critical logics because DoS possible
  /// @return Array of all registered strategies
  function strategies() external override view returns (address[] memory) {
    return _strategies;
  }

  /// @notice Return info about last doHardWork call for given vault
  /// @param vault Vault address
  /// @return HardWork struct with result
  function lastHardWork(address vault) external view override returns (HardWork memory) {
    return _lastHardWork[vault];
  }

  /// @notice Return info about last PricePerFullShare change for given vault
  /// @param vault Vault address
  /// @return PpfsChange struct with result
  function lastPpfsChange(address vault) external view override returns (PpfsChange memory) {
    return _lastPpfsChange[vault];
  }

  /// @notice Return true for registered Vault
  /// @param _value Vault address
  /// @return true if Vault registered
  function isVaultExist(address _value) internal view returns (bool) {
    for (uint256 i = 0; i < _vaults.length; i++) {
      if (_vaults[i] == _value) {
        return true;
      }
    }
    return false;
  }

  /// @notice Return true for registered Strategu
  /// @param _value Strategy address
  /// @return true if Strategy registered
  function isStrategyExist(address _value) internal view returns (bool) {
    for (uint256 i = 0; i < _strategies.length; i++) {
      if (_strategies[i] == _value) {
        return true;
      }
    }
    return false;
  }

  /// @notice Governance action. Remove given Vault from vaults array
  /// @param index Index of vault in the vault array
  function removeFromVaults(uint256 index) external onlyControllerOrGovernance {
    require(index < _vaults.length, "wrong index");
    emit RemoveVault(_vaults[index]);

    for (uint256 i = index; i < _vaults.length - 1; i++) {
      _vaults[i] = _vaults[i + 1];
    }
    _vaults.pop();
  }

  /// @notice Governance action. Remove given Strategy from strategies array
  /// @param index Index of strategy in the strategies array
  function removeFromStrategies(uint256 index) external onlyControllerOrGovernance {
    require(index < _strategies.length, "wrong index");
    emit RemoveStrategy(_strategies[index]);

    for (uint256 i = index; i < _strategies.length - 1; i++) {
      _strategies[i] = _strategies[i + 1];
    }
    _strategies.pop();
  }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
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
library SafeMathUpgradeable {
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

interface IBookkeeper {

  struct PpfsChange {
    address vault;
    uint256 block;
    uint256 time;
    uint256 value;
    uint256 oldBlock;
    uint256 oldTime;
    uint256 oldValue;
  }

  struct HardWork {
    address strategy;
    uint256 block;
    uint256 time;
    uint256 targetTokenAmount;
  }

  function addVault(address _vault) external;

  function addStrategy(address _strategy) external;

  function registerStrategyEarned(uint256 _targetTokenAmount) external;

  function registerFundKeeperEarned(address _token, uint256 _fundTokenAmount) external;

  function registerUserAction(address _user, uint256 _amount, bool _deposit) external;

  function registerVaultTransfer(address from, address to, uint256 amount) external;

  function registerUserEarned(address _user, address _vault, address _rt, uint256 _amount) external;

  function registerPpfsChange(address vault, uint256 value) external;

  function vaults() external view returns (address[] memory);

  function strategies() external view returns (address[] memory);

  function lastPpfsChange(address vault) external view returns (PpfsChange memory);

  /// @notice Return total earned TETU tokens for strategy
  /// @dev Should be incremented after strategy rewards distribution
  /// @param vault Strategy address
  /// @return Earned TETU tokens
  function targetTokenEarned(address vault) external view returns (uint256);

  /// @notice Return share(xToken) balance of given user
  /// @dev Should be calculated for each xToken transfer
  /// @param vault Vault address
  /// @param user User address
  /// @return User share (xToken) balance
  function vaultUsersBalances(address vault, address user) external view returns (uint256);

  /// @notice Return earned token amount for given token and user
  /// @dev Fills when user claim rewards
  /// @param user User address
  /// @param vault Vault address
  /// @param token Token address
  /// @return User's earned tokens amount
  function userEarned(address user, address vault, address token) external view returns (uint256);

  function lastHardWork(address vault) external view returns (HardWork memory);

  /// @notice Return users quantity for given Vault
  /// @dev Calculation based in Bookkeeper user balances
  /// @param vault Vault address
  /// @return Users quantity
  function vaultUsersQuantity(address vault) external view returns (uint256);
}

// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interface/IController.sol";
import "../interface/IControllable.sol";

/// @title Implement basic functionality for any contract that require strict control
/// @dev Can be used with upgradeable pattern.
///      Require call initializeControllable() in any case.
/// @author belbix
abstract contract Controllable is Initializable, IControllable {
  bytes32 internal constant _CONTROLLER_SLOT = 0x5165972ef41194f06c5007493031d0b927c20741adcb74403b954009fd2c3617;
  bytes32 internal constant _CREATED_SLOT = 0x6f55f470bdc9cb5f04223fd822021061668e4dccb43e8727b295106dc9769c8a;

  /// @notice Controller address changed
  event UpdateController(address oldValue, address newValue);

  constructor() {
    assert(_CONTROLLER_SLOT == bytes32(uint256(keccak256("eip1967.controllable.controller")) - 1));
    assert(_CREATED_SLOT == bytes32(uint256(keccak256("eip1967.controllable.created")) - 1));
  }

  /// @notice Initialize contract after setup it as proxy implementation
  ///         Save block.timestamp in the "created" variable
  /// @dev Use it only once after first logic setup
  /// @param _controller Controller address
  function initializeControllable(address _controller) public initializer {
    setController(_controller);
    setCreated(block.timestamp);
  }

  function isController(address _adr) public override view returns (bool) {
    return _adr == controller();
  }

  /// @notice Return true is given address is setup as governance in Controller
  /// @param _adr Address for check
  /// @return true if given address is governance
  function isGovernance(address _adr) public override view returns (bool) {
    return IController(controller()).governance() == _adr;
  }

  // ************ MODIFIERS **********************

  /// @dev Allow operation only for Controller
  modifier onlyController() {
    require(controller() == msg.sender, "not controller");
    _;
  }

  /// @dev Allow operation only for Controller or Governance
  modifier onlyControllerOrGovernance() {
    require(isController(msg.sender) || isGovernance(msg.sender), "not controller or gov");
    _;
  }

  /// @dev Only smart contracts will be affected by this modifier
  ///      If it is a contract it should be whitelisted
  modifier onlyAllowedUsers() {
    require(IController(controller()).isAllowedUser(msg.sender), "not allowed");
    _;
  }

  /// @dev Only Reward Distributor allowed. Governance is Reward Distributor by default.
  modifier onlyRewardDistribution() {
    require(IController(controller()).isRewardDistributor(msg.sender), "only distr");
    _;
  }

  // ************* SETTERS/GETTERS *******************

  /// @notice Return controller address saved in the contract slot
  /// @return adr Controller address
  function controller() public view returns (address adr) {
    bytes32 slot = _CONTROLLER_SLOT;
    assembly {
      adr := sload(slot)
    }
  }

  /// @dev Set a controller address to contract slot
  /// @param _newController Controller address
  function setController(address _newController) internal {
    require(_newController != address(0), "zero address");
    emit UpdateController(controller(), _newController);
    bytes32 slot = _CONTROLLER_SLOT;
    assembly {
      sstore(slot, _newController)
    }
  }

  /// @notice Return creation timestamp
  /// @return ts Creation timestamp
  function created() external view returns (uint256 ts) {
    bytes32 slot = _CREATED_SLOT;
    assembly {
      ts := sload(slot)
    }
  }

  /// @dev Filled only once when contract initialized
  /// @param _created block.timestamp
  function setCreated(uint256 _created) private {
    bytes32 slot = _CREATED_SLOT;
    assembly {
      sstore(slot, _created)
    }
  }

}

// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

interface IController {

  function addVaultAndStrategy(address _vault, address _strategy) external;

  function addStrategy(address _strategy) external;

  function governance() external view returns (address);

  function dao() external view returns (address);

  function bookkeeper() external view returns (address);

  function feeRewardForwarder() external view returns (address);

  function mintHelper() external view returns (address);

  function rewardToken() external view returns (address);

  function fundToken() external view returns (address);

  function psVault() external view returns (address);

  function fund() external view returns (address);

  function announcer() external view returns (address);

  function whiteList(address _target) external view returns (bool);

  function vaults(address _target) external view returns (bool);

  function strategies(address _target) external view returns (bool);

  function psNumerator() external view returns (uint256);

  function psDenominator() external view returns (uint256);

  function fundNumerator() external view returns (uint256);

  function fundDenominator() external view returns (uint256);

  function isAllowedUser(address _adr) external view returns (bool);

  function isDao(address _adr) external view returns (bool);

  function isHardWorker(address _adr) external view returns (bool);

  function isRewardDistributor(address _adr) external view returns (bool);

  function isValidVault(address _vault) external view returns (bool);

  function isValidStrategy(address _strategy) external view returns (bool);

  // ************ DAO ACTIONS *************
  function setPSNumeratorDenominator(uint256 numerator, uint256 denominator) external;

  function setFundNumeratorDenominator(uint256 numerator, uint256 denominator) external;

  function addToWhiteListMulti(address[] calldata _targets) external;

  function addToWhiteList(address _target) external;

  function removeFromWhiteListMulti(address[] calldata _targets) external;

  function removeFromWhiteList(address _target) external;
}

// SPDX-License-Identifier: ISC
/**
* By using this software, you understand, acknowledge and accept that Tetu
* and/or the underlying software are provided “as is” and “as available”
* basis and without warranties or representations of any kind either expressed
* or implied. Any use of this open source software released under the ISC
* Internet Systems Consortium license is done at your own risk to the fullest
* extent permissible pursuant to applicable law any and all liability as well
* as all warranties, including any fitness for a particular purpose with respect
* to Tetu and/or the underlying software and the use thereof are disclaimed.
*/

pragma solidity 0.8.4;

interface IControllable {

  function isController(address _contract) external view returns (bool);

  function isGovernance(address _contract) external view returns (bool);
}

