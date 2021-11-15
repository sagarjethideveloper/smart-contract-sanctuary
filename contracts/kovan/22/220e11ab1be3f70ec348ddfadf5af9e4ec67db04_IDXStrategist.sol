// contracts/IDXStrategist.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interface/compound/CErc20.sol";
import "./interface/compound/CEther.sol";
import "./interface/compound/Comptroller.sol";
import "./vaults/CompoundVault.sol";


/**

IDX Digital Labs Strategist

  - CREATE VAULT
  - UPDATE VAULT
  - RETURN iVault token rate

 
  Compound balancer (contract pair)  individual contract deployed to farm Compound whit low / high risk

  Compound vault Comp Boost by Borrowing any available Compound on behalf of the vault 

  COMPOUND cDAI/cUSDC  => crvCOMP  = Yearn CRV Comp

*/

contract IDXStrategist is Initializable, AccessControlUpgradeable, PausableUpgradeable{

  using SafeERC20Upgradeable for IERC20Upgradeable;


  CErc20 cCOMP;
  IERC20Upgradeable COMP;

  uint256 vaultCount;
  mapping(address => uint256) public vaultsIds;
  mapping(uint256 => _Vaults) public vaults;

  struct _Vaults{
    uint256 id;
    uint256 tier;
    uint256 lastClaimBlock; 
    uint256 accumulatedCompPerShare;
    uint256 accumulatedIvaultPerShare;
    uint256 fees;
    uint256 feeBase;
    uint256 mentissa;
    CompoundVault logic;
    IERC20Upgradeable asset;
    CErc20 collateral;
    IERC20Upgradeable protocolAsset;
    address protocollCollateral;
    address creator;
  }

  event Vaults( 
    uint256 id,
    uint256 vaultTier,
    address vaultAddress                                                                                                             
  );

mapping(address => mapping(address => uint256)) public avgIdx;

bytes32 STRATEGIST_ROLE;
bytes32 VAULT_ROLE;
bytes32 CONTROLLER_ROLE;

function initialize(

  address startegist

  ) public initializer {
  

  __AccessControl_init();
  __Pausable_init();


  STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
  VAULT_ROLE = keccak256("VAULT_ROLE");

  _setupRole(STRATEGIST_ROLE, startegist);     
  _setupRole(DEFAULT_ADMIN_ROLE, startegist); 
  COMP = IERC20Upgradeable(0x61460874a7196d6a22D1eE4922473664b3E95270);
  cCOMP = CErc20(0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4);  
}

    /// @notice Create and Deploy a new vault
    /// @dev Will add a contract vault to the vaults
    /// @param cToken collaterall token
    /// @param asset native asset
    /// @param tier tier access
    /// @param fees vault fees
    /// @param symbol the symbol of the vault (token)

    function createVault(
      address cToken,
      address asset,
      address protocolAsset,
      uint256 tier, 
      uint256 fees, 
      uint256 feeBase,
      uint256 mentissa,
      string memory symbol,
      string memory name
      ) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "IDXStrategist : Unauthorized?");

        _Vaults storage vault = vaults[vaultCount];
        
        vault.id = vaultCount;
        vault.tier = tier;
        vault.lastClaimBlock = block.number;
        vault.accumulatedCompPerShare = 0;
        vault.fees = fees;
       // vault.symbol = symbol;
        vault.mentissa = mentissa;
        vault.protocolAsset = IERC20Upgradeable(protocolAsset);
        vault.collateral = CErc20(cToken);
        vault.asset = IERC20Upgradeable(asset);
        vault.logic = new CompoundVault();
        vault.logic.initialize(address(this), cToken, asset, fees, feeBase,mentissa, symbol, name);

        vaultsIds[address(vault.logic)] = vaultCount;
        vaultCount += 1;
    }


    /// @notice UPDATE VAULT.
    /// @param vaultAddress The asset we update the pool on
    /// @dev each vault start with a ratio of one to one

    function updateCompoundVault(address vaultAddress) public {
        _Vaults storage vault = vaults[vaultsIds[vaultAddress]];
        require(address(vault.logic) == msg.sender,'iCOMP : Unauthorized');
        if (block.number <= vault.lastClaimBlock) {
            return;
        }

        uint256 currentSupply = vault.collateral.balanceOfUnderlying(address(vault.logic)); // total vault value in USD
        
        if (currentSupply == 0) {
            vault.lastClaimBlock = block.number;
            return;
        }
        
         uint256 vaultAssetPerShare = currentSupply * vault.mentissa / vault.logic.totalSupply(); 
         //uint256 compClaimed = vault.logic.claimComp();
         //cCOMP.mint(compClaimed);
        
         //uint256 cCompSupply = CErc20(vault.protocollCollateral).balanceOfUnderlying(address(this));
         //uint256 compPerShare = cCompSupply * vault.mentissa / vault.logic.totalSupply();
  
        //vault.accumulatedCompPerShare += compPerShare;
        vault.accumulatedIvaultPerShare += vaultAssetPerShare; 
  
    }




     /// @notice Get Vault Return
     /// @dev fees are already deducted on the share value based on earning
     /// @param vaultAddress address of the vault
     /// @param account the account 
     /// @return shares the amount of Asset available to redeemed
    

        function _getVaultReturn(address vaultAddress, address account) public view returns (uint256[] memory shares) {
          
          _Vaults memory vault = vaults[vaultsIds[vaultAddress]];
          shares = new uint256[](2);

          uint256 accountAvgPrice = avgIdx[account][address(vault.logic)] / vault.logic.balanceOf(account);
          uint256 currentPrice = vault.collateral.balanceOfUnderlying(address(vault.logic)) * vault.mentissa / vault.logic.totalSupply();
        
          uint256 accountValue =  ((currentPrice * vault.logic.balanceOf(account)) - (avgIdx[account][address(vault.logic)] / vault.logic.balanceOf(account) )) / vault.mentissa; 
          uint256 gain = accountValue - accountAvgPrice;
          uint256 fees = (gain /vault.feeBase * vault.fees);
          shares[0] = fees;                                    // the fees 
          shares[1] = accountValue - fees;                     // the amount left to redeem in asset unit              
          //shares[3] = 
          return shares;
        }

    /// @notice Get Vault Rate
     /// @dev fees are already deducted on the share value based on earning
     /// @param vaultAddress address of the vault
     /// @return price the amount of iVault per Unit

    function getCurrentRate(address vaultAddress)
        public
        view
        returns (uint256 price)
    {
        _Vaults memory vault = vaults[vaultsIds[vaultAddress]];
        if(vault.logic.totalSupply() == 0){
          return  vault.mentissa;
        }else{
           return vault.collateral.balanceOfUnderlying(address(vault.logic)) / vault.logic.totalSupply() / vault.mentissa;
        }
       
    }
    


    /// @notice returns a quotient
    /// @dev this function assumed you checked the values already
    /// @param numerator the amount filled
    /// @param denominator the amount in order
    /// @param precision the decimal places we keep
    /// @return _quotient

    function quotient(
        uint256 numerator,
        uint256 denominator,
        uint256 precision
    ) internal pure returns (uint256 _quotient) {
        uint256 _numerator = numerator * 10**(precision + 1);
        _quotient = ((_numerator / denominator) + 5) / 10;
        return (_quotient);
    }



}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../utils/introspection/ERC165Upgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControlUpgradeable {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
}

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControlUpgradeable is Initializable, ContextUpgradeable, IAccessControlUpgradeable, ERC165Upgradeable {
    function __AccessControl_init() internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
    }

    function __AccessControl_init_unchained() internal initializer {
    }
    struct RoleData {
        mapping (address => bool) members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlUpgradeable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual override {
        require(hasRole(getRoleAdmin(role), _msgSender()), "AccessControl: sender must be an admin to grant");

        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual override {
        require(hasRole(getRoleAdmin(role), _msgSender()), "AccessControl: sender must be an admin to revoke");

        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, getRoleAdmin(role), adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

import "../../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
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
import "../../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
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
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
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

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
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
    function __Pausable_init() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface CErc20 {
    function mint(uint256 mintAmount) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address _owner) external view returns (uint256);

    function borrowBalanceCurrent(address account) external view returns (uint);

    function underlying() external view returns (address);

    function getCash() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);

    function borrowRatePerBlock() external view returns (uint);

    function totalBorrowsCurrent() external view returns (uint);

    function totalSupply() external view returns (uint);

    function totalReserves() external view returns (uint);

    function exchangeRateCurrent() external ;

    function balanceOfUnderlying(address account) external view returns (uint);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface CEther {
    function balanceOf(address owner) external view returns (uint);

    function approve(address spender, uint256 amount) external returns (bool);

    function mint() external payable;

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);

    function exchangeRateStored() external view returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow() external payable;

    function getCash() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);

    function borrowRatePerBlock() external view returns (uint);

    function totalBorrowsCurrent() external view returns (uint);

    function totalSupply() external view returns (uint);

    function totalReserves() external view returns (uint);

    function exchangeRateCurrent() external;

    function balanceOfUnderlying(address account) external view returns (uint);

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface Comptroller {

    function enterMarkets(address[] calldata) external returns (uint256[] memory);

    function exitMarket(address cToken) external returns (uint);

    function claimComp(address holder, address[] calldata) external;

    function getAssetsIn(address account) external view returns (address[] memory);

    function markets(address cTokenAddress) external view returns (bool, uint, bool);

    function getAccountLiquidity(address account) external view returns (uint, uint, uint);

    function liquidationIncentiveMantissa() external view returns (uint);

}

// CompoundVault.sol
// SPDX-License-Identifier: MIT

/**
        IDX Digital Labs Earning Protocol.
        Compound Vault
        Gihub :
        Testnet : 

 */
pragma solidity ^0.8.0;

import "../interface/compound/Comptroller.sol";
import "../interface/compound/CErc20.sol";
import "../interface/compound/CEther.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

interface StrategistProxy{

     function _getVaultReturn(address vaultAddress, address account)
        external
        view
        returns (uint256[] memory strategistData);

    function updateCompoundVault(address vault) external;

     function getCurrentRate(address vaultAddress)
        external
        view
        returns (uint256 price);
}

contract CompoundVault is
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public ETHER;
    address public COMP;
    address public collateral;
    address public farming;
    address public strategist;
    uint256 public mentissa;
    uint256 public fees;
    uint256 public feeBase;
    uint256 public startBlock;
   
    string public version;

    bytes32 STRATEGIST_ROLE;
    StrategistProxy STRATEGIST; 
    Comptroller comptroller;

    event Mint(address asset,uint256 amount);
    event Redeem(address asset,uint256 amount);
    event CompoundClaimed(address caller, uint256 amount);

    /// @notice Initializer
    /// @dev Constructor for Upgradeable Contract
    /// @param _strategist adress of the strategist contract the deployer

    function initialize(
        address _strategist,
        address _compoundedAsset,
        address _underlyingAsset,
        uint256 _protocolFees,
        uint256 _feeBase,
        uint256 _mentissa,
        string memory _symbol,
        string memory _name

    ) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __ERC20_init(_name, _symbol);
        STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
        _setupRole(STRATEGIST_ROLE, _strategist);
        strategist = _strategist;
        fees = _protocolFees;
        mentissa = _mentissa;
        feeBase = _feeBase;
        collateral = _compoundedAsset;
        farming = _underlyingAsset;
        COMP = 0x61460874a7196d6a22D1eE4922473664b3E95270;
        comptroller = Comptroller(0x5eAe89DC1C671724A672ff0630122ee834098657);
        version = "1.0";
        STRATEGIST = StrategistProxy(_strategist);
        _enterCompMarket(_compoundedAsset);

    }

    /// @notice Mint idxComp.
    /// @dev Must be approved
    /// @param _amount The amount to deposit that must be approved in farming asset
    /// @return returnedCollateral the amount minted
    function mint(
        uint256 _amount
    ) public payable whenNotPaused returns(uint256 returnedCollateral) {
        IERC20Upgradeable asset = IERC20Upgradeable(farming);
        STRATEGIST.updateCompoundVault(address(this));

        if (farming == ETHER) {
            require(msg.value > 0,'iCOMP : Zero Ether!');
            returnedCollateral = buyETHPosition(msg.value);
        } else if (farming != ETHER) {
            require(_amount > 0,'iCOMP : Zero Amount!');
            require(asset.allowance(msg.sender,address(this)) >= _amount,"iCOMP : Insuficient allowance!");
            require(asset.transferFrom(msg.sender, address(this), _amount),'iCOMP : Transfer failled!');
            returnedCollateral = buyERC20Position(_amount);
        }
         
        
        _mint(msg.sender, STRATEGIST.getCurrentRate(address(this)) * _amount );

        emit Mint(farming,_amount);

        return  returnedCollateral;
    }



    /// @notice Redeem you position
    /// @dev Will send back to user the native asset
    /// @param _amount the amount to withdraw (see max withdraw to withdraw all available funds)
    /// @dev this function is meant to withdraw an amount less than total mosition

    function redeem(
 
        uint256 _amount   // in farming asset
   
    ) external whenNotPaused {
        require(_amount > 0,'iCOMP : Zero Amount!');
        STRATEGIST.updateCompoundVault(address(this));
        uint256[] memory strategistData = STRATEGIST._getVaultReturn(address(this), msg.sender);

        if (_amount  >= strategistData[1]){
           _amount = strategistData[1];  // max available after fees
        }

        if (farming == ETHER) {
            CEther cToken = CEther(collateral);
            cToken.exchangeRateCurrent();  
            uint256 transferedAmount = sellETHPosition(_amount);
            payable(msg.sender).transfer(transferedAmount);
        } else if(farming != ETHER){
            IERC20Upgradeable asset = IERC20Upgradeable(farming);
            uint256 returned = sellERC20Position(_amount);
            asset.transfer(msg.sender, returned);
        }
          
          _burn(msg.sender, _amount);
          emit Redeem(farming, _amount);
    }

    /// @notice BUY ERC20 Position
    /// @dev buy a position in compound
    /// @param _amount the amount to deposit in
    /// @return returnedAmount in collateral shares

    function buyERC20Position(uint256 _amount)
        internal
        whenNotPaused
        returns (uint256 returnedAmount)
    {
        CErc20 cToken = CErc20(collateral);
        IERC20Upgradeable asset = IERC20Upgradeable(farming);
        uint256 balanceBefore = cToken.balanceOf(address(this));
        asset.safeApprove(address(cToken), _amount);
        assert(cToken.mint(_amount) == 0);
        uint256 balanceAfter = cToken.balanceOf(address(this));
        returnedAmount = balanceAfter - balanceBefore;

        return returnedAmount; // cERC20
    }

    /// @notice BUY ETH Position
    /// @dev 
    /// @param _amount the amount to deposit in
    /// @return returnedAmount in collateral shares

    function buyETHPosition(uint256 _amount)
        internal
        whenNotPaused
        returns (uint256 returnedAmount)
    {
        CEther cToken = CEther(collateral);
        uint256 balanceBefore = cToken.balanceOf(address(this));
        cToken.mint{value: _amount}();
        uint256 balanceAfter = cToken.balanceOf(address(this));
        returnedAmount = balanceAfter - balanceBefore;

        return returnedAmount; // in cEther
    }

    /// @notice SELL ERC20 Position
    /// @dev will get the current rate to sell position at current price.

    /// @param _amount the amount in USD 
    /// @return returnedAmount is based on blance

    function sellERC20Position(uint256 _amount)
        internal
        whenNotPaused
        returns (uint256 returnedAmount)
    {
        CErc20 cToken = CErc20(collateral);
        IERC20Upgradeable asset = IERC20Upgradeable(farming);
        // we want latest rate
        cToken.exchangeRateCurrent();
        uint256 balanceB = asset.balanceOf(address(this));
        uint256 sellAmount = _getCollateralAmount(_amount); // SELL C Token

        cToken.approve(address(cToken), sellAmount);
        require(
            cToken.redeem(sellAmount) == 0,
            "iCOMP : CToken Redeemed Error?"
        );
        uint256 balanceA = asset.balanceOf(address(this));
        returnedAmount = balanceA - balanceB;

        return returnedAmount; //in ERC20
    }

    /// @notice SELL ERC20 Position
    /// @dev will get the current rate to sell position at current price.
    /// @param _amount in USD
    /// @return returnedAmount in ETH based on balance

    function sellETHPosition(uint256 _amount)
        internal
        whenNotPaused
        returns (uint256 returnedAmount)
    {
        CEther cToken = CEther(collateral);
        uint256 balanceBefore = address(this).balance;
        uint256 sellAmount = _getCollateralAmount(_amount);

        cToken.approve(address(cToken), sellAmount);
        require(
            cToken.redeem(sellAmount) == 0,
            "iCOMP : CToken Redeemed Error?"
        );
        uint256 balanceAfter = address(this).balance;
        returnedAmount = balanceAfter - balanceBefore;

        return returnedAmount; // in Ether
    }

    /// @notice GET RATE FROM Strategit
    /// @dev get update before transactions
    /// @return value

    function curentVaultValue() public view returns(uint256 value){
       if(totalSupply() == 0 ){
           value = mentissa;   // 1 : 1
       }
       else if(totalSupply() > 0){
        CErc20 cToken = CErc20(collateral);
        value = cToken.balanceOfUnderlying(address(this));
       }

         return value;
    }







    /// @notice returns the stored compound rate    
    /// @dev this is not the current rate. (last time recorded and free to call)
    /// @return rate the amount of asset per ctoken

    function _getRate() internal view returns (uint256 rate) {

        if(farming == ETHER){
          CEther cToken = CEther(collateral);
          rate = cToken.exchangeRateStored();
        }
        else{
          CErc20 cToken = CErc20(collateral);
          rate = cToken.exchangeRateStored();
        }
        return rate;
    }

    /// @notice returns the earning on the position
    /// @dev 
    /// @param _amount the amount of the asset
    /// @return collateralAmount : The amount of cToken for the input amount in farmed asset

    function _getCollateralAmount(uint256 _amount)
          internal 
          view
        returns (uint256 collateralAmount)
    {
        collateralAmount = (_amount * mentissa) / _getRate();
        return collateralAmount;
    }

   

    /// @notice returns a quotient
    /// @dev this function assumed you checked the values already
    /// @param numerator the amount filled
    /// @param denominator the amount in order
    /// @param precision the decimal places we keep
    /// @return _quotient

    function quotient(
        uint256 numerator,
        uint256 denominator,
        uint256 precision
    ) internal pure returns (uint256 _quotient) {
        uint256 _numerator = numerator * 10**(precision + 1);
        _quotient = ((_numerator / denominator) + 5) / 10;
        return (_quotient);
    }

    /// @notice CLAIM COMP TOKEN.
    /// @dev this function can be called from the IDYS proxy

    function claimComp() public whenNotPaused returns (uint256 amountClaimed) {
        require(hasRole(STRATEGIST_ROLE, msg.sender), "iCOMP : Unauthorized?");
            address[] memory cTokens = new address[](1);
            cTokens[0] = collateral;
            IERC20Upgradeable Comp = IERC20Upgradeable(COMP);
            comptroller.claimComp(address(this), cTokens);
            amountClaimed = Comp.balanceOf(address(this));
            Comp.transfer(strategist, amountClaimed);
            emit CompoundClaimed(msg.sender, amountClaimed);
        }
    

    

    /// @notice ENTER COMPOUND MARKET ON DEPLOYMENT
    /// @dev asset address is translated to collateral address make sure you set a collateral first

    function _enterCompMarket(address cAsset) internal {
        address[] memory cTokens = new address[](1);  
        cTokens[0] = cAsset;
        uint256[] memory errors = comptroller.enterMarkets(cTokens);
        require(errors[0] == 0,'iCOMP : Market Fail');
    }

    /// @notice SET VAULT FEES.
    /// @param _fees the fees in %
    /// @dev base3 where  200 = 2%

    function setFees(uint256 _fees) external{
        require(hasRole(STRATEGIST_ROLE, msg.sender), "iCOMP : Unauthorized?");
        fees = _fees;
    }

    /// @notice THIS VAULT ACCEPT ETHER
    receive() external payable {
        // nothing to do
    }

    /// @notice SECURITY.

    /// @notice pause or unpause.
    /// @dev Security feature to use with Defender for vault monitoring

    function pause() public whenNotPaused {
        require(
            hasRole(STRATEGIST_ROLE, msg.sender),
            "iCOMP : Unauthorized to pause"
        );
        _pause();
    }

    function unpause() public whenPaused {
        require(
            hasRole(STRATEGIST_ROLE, msg.sender),
            "iCOMP : Unauthorized to unpause"
        );
        _unpause();
    }
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

pragma solidity ^0.8.0;

import "./IERC165Upgradeable.sol";
import "../../proxy/utils/Initializable.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165Upgradeable is Initializable, IERC165Upgradeable {
    function __ERC165_init() internal initializer {
        __ERC165_init_unchained();
    }

    function __ERC165_init_unchained() internal initializer {
    }
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165Upgradeable).interfaceId;
    }
    uint256[50] private __gap;
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
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
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable {
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
    uint256[45] private __gap;
}

