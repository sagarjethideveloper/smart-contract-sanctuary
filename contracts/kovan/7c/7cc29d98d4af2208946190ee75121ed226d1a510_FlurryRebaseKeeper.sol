//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IFlurryRebaseKeeper.sol"; 
import "../interfaces/IVault.sol"; 

contract FlurryRebaseKeeper is OwnableUpgradeable, IFlurryRebaseKeeper {

    uint256 public rebaseInterval; // Daily rebasing interval with 1 = 1 second
    uint256 public lastTimeStamp;

    IVault[] public vaults;
    mapping(address => bool) vaultRegistered;

    function initialize(uint256 interval) public initializer {
        OwnableUpgradeable.__Ownable_init();
        rebaseInterval = interval;
        lastTimeStamp = block.timestamp;        
    }

    function checkUpkeep(bytes calldata checkData) external override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > rebaseInterval;
        performData = checkData;
    }

    function performUpkeep(bytes calldata performData) external override {
        lastTimeStamp = block.timestamp;
        for (uint i = 0; i < vaults.length; i++) {
            vaults[i].rebase();
        }
        performData;
    }

    function setRebaseInterval(uint256 interval) external override onlyOwner {
        rebaseInterval = interval;
    }

    function registerVault(address vaultAddr) external override onlyOwner {
        require(!vaultRegistered[vaultAddr], "This vault is already registered.");
        vaults.push(IVault(vaultAddr));
        vaultRegistered[vaultAddr] = true;   
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";
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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IFlurryRebaseKeeper {
    /**
     * @dev checkUpkeep compatible.
     * Return upkeepNeeded (in bool) and performData (in bytes) and untilKeepNeeded (in uint).
     */
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);
    
    /**
     * @dev performUpkeep compatible.
     */
    function performUpkeep(bytes calldata performData) external;

    /**
     * @dev Set rebase interval.
     */
    function setRebaseInterval(uint256 interval) external ;

    /**
     * @dev Register vaults into Flurry Rebase Keeper contract.
     */
    function registerVault(address vaultAddr) external;
}

//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "../rhoTokens/RhoToken.sol";
import "./chainlink/AggregatorV3Interface.sol";
import "./IRhoStrategy.sol";


interface IVault {
    struct Strategy {
        string name;
        IRhoStrategy target;
        bool enabled;
    }
    struct VaultSupplyRateDetail {
        uint256 APY;
        StrategySupplyRateDetail[] strategies;
    }
    struct StrategySupplyRateDetail {
        string name;
        uint256 APY;
    }
    function ethPriceFeed() external view returns (AggregatorV3Interface);

    function setEthPriceFeed(address addr) external;

    /**
     * @dev Getter function for Rho token minting fee
     * @return Return the minting fee (in bps)
     */
    function mintingFee() external view returns (uint256);

    /**
     * @dev Setter function for minting fee (in bps)
     */
    function setMintingFee(uint256 _feeInBps) external;

    /**
     * @dev Getter function for Rho token redemption fee
     * @return Return the redeem fee (in bps)
     */
    function redeemFee() external view returns (uint256);

    /**
     * @dev Setter function for Rho token redemption fee
     */
    function setRedeemFee(uint256 _feeInBps) external;

    /**
     * @dev set the allocation threshold (denominated in underlying asset)
     */
    function setReserveBoundary(uint256 _lowerBound, uint256 _upperBound) external;

    /**
     * @dev Getter function for allocation lowerbound and upperbound
     */
    function reserveBoundary(uint index) external view returns (uint256);

    /**
     * Each Vault currently only supports one underlying asset
     * @return Returns the contract address of the underlying asset
     */
    function underlying() external view returns (IERC20MetadataUpgradeable);

    /**
     * @return True if the asset is supported by this vault
     */
    function supportsAsset(address _asset) external view returns (bool);

    /**
     * @return Returns the address of the Rho token contract
     */
    function rhoToken() external view returns (IRhoToken);

    /**
     * @dev function that trigggers the distribution of interest earned to Rho token holders
     */
    function rebase() external;

    /**
     * @dev function that trigggers allocation and unallocation of funds based on reserve pool bounds
     */
    function rebalance() external;

    /**
     * @dev Add strategy object which implments the IRhoStrategy interface to the vault
     */
    function addStrategy(string memory name, address at, bool enabled) external;

    /**
     * @dev Disable a strategy from the vaule
     * Before a strategy can be disabled, withdrawAll() should be called to liquidate and remove all funds from the strategy
     */
    function disableStrategy(uint256 index) external;

    function enableStrategy(uint256 index) external;

    /**
     * @dev Allocate funds to strategies
     */
    // function allocate() external;

    /**
     * admin functions to pause/unpause certain operations
     */
    function mint(uint256 amount) external;

    function redeem(uint256 amount) external;

     /**
     * admin functions to withdraw random token transfer to this contract
     */
    function sweepERC20Token(address token,address to)external;

    function sweepRhoTokenContractERC20Token(address token, address to) external;

    function setManagementFee(uint256 _feeInBps) external;
    function managementFee() external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
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

import "../IERC20Upgradeable.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
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

//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IRhoTokenRewards.sol";
import "../interfaces/IRhoToken.sol";

contract RhoToken is OwnableUpgradeable, ERC20Upgradeable, IRhoToken {
    using AddressUpgradeable for address;

    mapping (address => uint256) private _eoaBalances;
    mapping (address => uint256) private _contractBalances;

    // mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _eoaTotalSupply;
    uint256 private _contractTotalSupply;

    uint256 private constant ONE = 1e36;

    uint256 private multiplier;

    address public tokenRewardsAddress;

    function __initialize(string memory name_, string memory symbol_) public initializer {
        ERC20Upgradeable.__ERC20_init(name_, symbol_);
        OwnableUpgradeable.__Ownable_init();
        _setMultiplier(ONE);
    }
    function totalSupply() public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        return _timesMultiplier(rebasingSupply()) + nonRebasingSupply();
    }
    function rebasingSupply() public view virtual override returns (uint256) {
        return _eoaTotalSupply;
    }
    function nonRebasingSupply() public view virtual override returns (uint256) {
        return _contractTotalSupply;
    }
    function balanceOf(address account) public view virtual override(ERC20Upgradeable, IERC20Upgradeable) returns (uint256) {
        if (account.isContract()){
            return _contractBalances[account];
        }
        return _timesMultiplier(_eoaBalances[account]);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override virtual updateTokenRewards(sender) updateTokenRewards(recipient) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);
        if (sender.isContract() && recipient.isContract()) {
            _transferC2C(sender, recipient, amount);
            return;
        }
        if (sender.isContract() && !recipient.isContract()) {
            _transferC2E(sender, recipient, amount);
            return;
        }
        if (!sender.isContract() && !recipient.isContract()) {
            _transferE2E(sender, recipient, amount);
            return;
        }
        _transferE2C(sender, recipient, amount);

    }

    function _transferE2E(address sender, address recipient, uint256 amount) internal virtual {
        uint256 senderBalance = _eoaBalances[sender];
        uint256 amountToDeduct = _dividedByMultiplier(amount);
        uint256 amountToAdd = amountToDeduct;
        require(senderBalance >= amountToDeduct, "ERC20: transfer amount exceeds balance");
        _eoaBalances[sender] = senderBalance - amountToDeduct;
        _eoaBalances[recipient] += amountToAdd;
        emit Transfer(sender, recipient, _timesMultiplier(amountToDeduct));

    }
    function _transferC2C(address sender, address recipient, uint256 amount) internal virtual {
        uint256 senderBalance = _contractBalances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _contractBalances[sender] = senderBalance - amount;
        _contractBalances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }
    function _transferE2C(address sender, address recipient, uint256 amount) internal virtual {
        uint256 amountToDeduct = _dividedByMultiplier(amount);
        uint256 amountToAdd = _timesMultiplier(amountToDeduct);
        require(_eoaBalances[sender] >= amountToDeduct, "ERC20: transfer amount exceeds balance");
        _eoaBalances[sender] -= amountToDeduct;
        _contractBalances[recipient] += amountToAdd;
        _eoaTotalSupply -= amountToDeduct;
        _contractTotalSupply += amountToAdd;
        emit Transfer(sender, recipient, amountToAdd);
    }
    function _transferC2E(address sender, address recipient, uint256 amount) internal virtual {
        uint256 amountToAdd = _dividedByMultiplier(amount);
        uint256 amountToDeduct = _timesMultiplier(amountToAdd);
        require(_contractBalances[sender] >= amountToDeduct, "ERC20: transfer amount exceeds balance");
        _contractBalances[sender] -= amountToDeduct;
        _eoaBalances[recipient] += amountToAdd;
        _contractTotalSupply -= amountToDeduct;
        _eoaTotalSupply += amountToAdd;
        emit Transfer(sender, recipient, amountToDeduct);
    }
    function _mint(address account, uint256 amount) internal virtual override updateTokenRewards(account) {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);
        if (account.isContract()) {
            _contractTotalSupply += amount;
            _contractBalances[account] += amount;
            emit Transfer(address(0), account, amount);
            return;
        }
        uint256 amountToAdd = _dividedByMultiplier(amount);
        _eoaTotalSupply += amountToAdd;
        _eoaBalances[account] += amountToAdd;
        emit Transfer(address(0), account, _timesMultiplier(amountToAdd));
    }
    function _burn(address account, uint256 amount) internal virtual override updateTokenRewards(account) {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);
        if (account.isContract()) {
            uint256 accountBalance = _contractBalances[account];
            require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
            _contractBalances[account] = accountBalance - amount;
            _contractTotalSupply -= amount;
            emit Transfer(account, address(0), amount);
            return;
        }
        uint256 amountToDeduct = _dividedByMultiplier(amount);
        uint256 __accountBalance = _eoaBalances[account];
        require(__accountBalance >= amountToDeduct, "ERC20: burn amount exceeds balance");
        _eoaBalances[account] = __accountBalance - amountToDeduct;
        _eoaTotalSupply -= amountToDeduct;
        emit Transfer(account, address(0), _timesMultiplier(amountToDeduct));
    }

    /* multiplier */
    // event MultiplierChange(uint256 to);

    function setMultiplier(uint256 multiplier_) external override onlyOwner updateTokenRewards(address(0)) {
        _setMultiplier(multiplier_);
        emit MultiplierChange(multiplier_);
    }
    function _setMultiplier(uint256 multiplier_) internal {
        multiplier = multiplier_;
    }
    function getMultiplier() external view override returns(uint256) {
        return multiplier;
    }
    function mint(address account, uint256 amount) external virtual override onlyOwner updateTokenRewards(account) {
        require(amount > 0, "amount must be greater than zero");
        return _mint(account, amount);
    }
    function burn(address account, uint256 amount) external virtual override onlyOwner updateTokenRewards(account) {
        require(amount > 0, "amount must be greater than zero");
        return _burn(account, amount);
    }

    /* utils */
    /* think of a way to group this in a library */
    function _timesMultiplier(uint256 input) internal virtual view returns (uint256) {
        return input * multiplier / ONE;
    }
    function _dividedByMultiplier(uint256 input) internal virtual view returns (uint256) {
        return input * ONE / multiplier;
    }

    /* token rewards */
    function setTokenRewards(address tokenRewards) external override onlyOwner {
        tokenRewardsAddress = tokenRewards;
    }

    // withdraw random token transfer into this contract
    function sweepERC20Token(address token, address to) external override onlyOwner {
        IERC20Upgradeable tokenToSweep = IERC20Upgradeable(token);
        tokenToSweep.transfer(to, tokenToSweep.balanceOf(address(this)));
    }

    /* ========== MODIFIERS ========== */
    modifier updateTokenRewards(address account) {
        if (tokenRewardsAddress != address(0)) {
            IRhoTokenRewards(tokenRewardsAddress).updateReward(account, address(this));
        }
        _;
    }
}

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

//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./uniswap/IUniswapV2Router02.sol";

/**
 * @notice Interface for yield farming strategies to integrate with various DeFi Protocols like Compound, Aave, dYdX.. etc
 */
interface IRhoStrategy {
    /**
     Events
     */
    event WithdrawAll();
    event WithdrawUnderlying(uint256 amount);
    event Deploy(uint256 amount);

    /**
     * @dev the underlying token
     */
    function underlying() external view returns (IERC20MetadataUpgradeable);
    /**
     * @dev unlock when TVL exceed the this target
     */
    function switchingLockTarget() external view returns(uint256);
    /**
     * @dev duration of which the strategy is locked
     */
    function switchLockDuration() external view returns(uint256);
    /**
     * @dev unlock after this block
     */
    function switchLockedUntil() external view returns(uint256);
    /**
     * @dev setter of switchLockDuration
     */
    function setSwitchLockDuration(uint256 durationInBlock) external;
    /**
     * @dev lock the strategy with a lock target
     */
    function switchingLock(uint256 lockTarget) external;
    /**
     * @dev Deploy the underlying to DeFi platform
     */
    function balanceOfUnderlying() external view returns(uint256);
    /**
     * @dev Deploy the underlying to DeFi platform
     */
    function deploy(uint256 _amount) external;

    /**
     * @notice current supply rate excluding bonus token (such as Aave / Comp)
     * @dev Returns the current going supply rate available for the given underlying stablecoin
     */
    function supplyRate() external view returns (uint256 _amount);

    /**
     * @notice current effective supply rate of the RhoStrategy
     * @dev returns the effective supply rate fomr the underlying DeFi protocol
     * taking into account any rewards tokens
     * @return supply rate (in wei)
     */
    function effectiveSupplyRate() external view returns (uint256);

    /**
     * @notice current effective supply rate of the RhoStrategy
     * @dev returns the effective supply rate fomr the underlying DeFi protocol
     * taking into account any rewards tokens AND the change in balance.
     * if balanceOffset >= current balance, returns the effective supply rate
     * as if balance is 0.
     * @return supply rate (in wei)
     */
    function effectiveSupplyRate(uint256 delta, bool isPositive) external view returns (uint256);

    /**
     * @dev Withdraw the amount in underlying from DeFi platform
     */
    function withdrawUnderlying(uint256 _amount) external;

    /**
     * @dev Withdraw all deployed assets and return them to vault
     */
    function withdrawAll() external;

    /**
     * @dev Return the updated balance of the underlying asset
     */
    function updateBalanceOfUnderlying() external returns (uint256);

    /**
     * @dev Collect any bonus reward tokens available for the strategy
     */
    function collectRewardToken() external;

    /**
     * @dev The threshold (denominated in reward tokens) over which rewards tokens will automatically
     * be converted into the underlying asset
     */
    function rewardConversionThreshold() external view returns (uint256);

    /**
     * @dev Set the threshold (denominated in reward tokens) over which rewards tokens will automatically
     * be converted into the underlying asset
     */
    function setRewardConversionThreshold(uint256 _threshold) external;

    /**
     * admin functions to withdraw random token transfer to this contract
     */
    function sweepERC20Token(
        address token,
        address to
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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

import "./IERC20Upgradeable.sol";
import "./extensions/IERC20MetadataUpgradeable.sol";
import "../../utils/ContextUpgradeable.sol";
import "../../proxy/utils/Initializable.sol";

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
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
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
    function __ERC20_init(string memory name_, string memory symbol_) internal initializer {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal initializer {
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
    uint256[45] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title RhoToken Rewards Interface
 * @notice Interface for bonus FLURRY token rewards contract for RhoToken holders
 */
interface IRhoTokenRewards {

    /**
     * @return list of addresses of rhoTokens registered in this contract
     */
    function getRhoTokenList() external view returns (address[] memory);

    /**
     * @return reward rate for all rhoTokens earned per block
     */
    function rewardRate() external view returns (uint256);

    /**
     * @notice Admin function - set reward rate for all rhoTokens earned per block
     * @param newRewardRate - reward rate per block (number of FLURRY in wei)
     */
    function setRewardRate(uint256 newRewardRate) external;

    /**
     * @notice A method to allow a stakeholder to check his rewards.
     * @param user The stakeholder to check rewards for.
     * @param rhoTokenAddr Address of rhoToken contract
     * @return Accumulated rewards of addr holder (in wei)
     */
    function rewardOf(address user, address rhoTokenAddr) external view returns (uint256);

    /**
     * @notice A method to allow a stakeholder to check his rewards for all rhoToken
     * @param user The stakeholder to check rewards for
     * @return Accumulated rewards of addr holder (in wei)
     */
    function totalRewardOf(address user) external view returns (uint256);

    // function setRewardSpeed(uint256 flurrySpeed) public

    /**
     * @notice Total accumulated reward per token
     * @param rhoTokenAddr Address of rhoToken contract
     * @return Reward entitlement for rho token
     */
    function rewardsPerToken(address rhoTokenAddr) external view returns (uint256);

    /**
     * @notice Admin function - A method to set reward duration
     * @param rhoTokenAddr Address of rhoToken contract
     * @param rewardDuration Reward duration in number of blocks
     */
    function startRewards(address rhoTokenAddr, uint256 rewardDuration) external;

    /**
     * @notice Admin function - End Rewards distribution earlier, if there is one running
     */
    function endRewards(address rhoTokenAddr) external;

    /**
     * @notice Calculate and allocate rewards token for address holder
     * Rewards should accrue from _lastUpdateBlock to lastBlockApplicable
     * rewardsPerToken is based on the total supply of the RhoToken, hence
     * this function needs to be called every time total supply changes
     * @param user the user to update reward for
     * @param rhoTokenAddr the rhoToken to update reward for
     */
    function updateReward(address user, address rhoTokenAddr) external;

    /**
     * @notice A method to allow a rhoToken holder to claim his rewards for one rhoToken
     * @param rhoTokenAddr Address of rhoToken contract
     * Note: If stakingRewards contract do not have enough tokens to pay,
     * this will fail silently and user rewards remains as a credit in this contract
     */
    function claimReward(address rhoTokenAddr) external;

    /**
     * @notice A method to allow a rhoToken holder to claim his rewards for all rhoTokens
     * Note: If stakingRewards contract do not have enough tokens to pay,
     * this will fail silently and user rewards remains as a credit in this contract
     */
    function claimAllReward() external;

    /**
     * @notice A method to allow staking rewards contract to claim rewards on behalf of users
     * @param user address of the user (NOT msg.sender, the immediate caller)
     * @param rhoTokenAddr Address of rhoToken contract
     */
    function claimReward(address user, address rhoTokenAddr) external;

    /**
     * @notice A method to allow a rhoToken holder to claim his rewards for all rhoTokens
     * @param user address of the user (NOT msg.sender, the immediate caller)
     */
    function claimAllReward(address user) external;

    /**
     * @notice Admin function - register a rhoToken to this contract
     * @param rhoTokenAddr address of the rhoToken to be registered
     * @param allocPoint allocation points (weight) assigned to the given rhoToken
     */
    function addRhoToken(address rhoTokenAddr, uint256 allocPoint) external;

    /**
     * @notice Admin function - change the allocation points of a rhoToken registered in this contract
     * @param rhoTokenAddr address of the rhoToken subject to change
     * @param allocPoint allocation points (weight) assigned to the given rhoToken
     */
    function setRhoToken(address rhoTokenAddr, uint256 allocPoint) external;

    /**
     * Admin function - withdraw random token transfer to this contract
     * @param token ERC20 token address to be sweeped
     * @param to address for sending sweeped tokens to
     */
    function sweepERC20Token(address token, address to) external;

}

//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

/**
 * @notice Interface for yield farming strategies to integrate with various DeFi Protocols like Compound, Aave, dYdX.. etc
 */
interface IRhoToken is IERC20MetadataUpgradeable {

    function rebasingSupply() external view returns (uint256);

    function nonRebasingSupply() external view returns (uint256);

    event MultiplierChange(uint256 to);

    function setMultiplier(uint256 multiplier_) external;
    function getMultiplier() external view returns(uint256);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function setTokenRewards(address tokenRewards) external;

    function sweepERC20Token(address token, address to) external;

}

//SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

import './IUniswapV2Router01.sol';

interface IUniswapV2Router02 is IUniswapV2Router01 {
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

//SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

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

