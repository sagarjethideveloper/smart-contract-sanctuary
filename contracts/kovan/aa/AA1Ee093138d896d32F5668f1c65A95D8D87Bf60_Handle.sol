// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/Bank/IHandle.sol";
import "../interfaces/Bank/ITreasury.sol";
import "../interfaces/IValidator.sol";
import "../interfaces/Bank/IVaultLibrary.sol";
import "../interfaces/Bank/IComptroller.sol";
import "../interfaces/Bank/IOracle.sol";
import "../interfaces/Bank/IInterest.sol";
import "./Roles.sol";

contract Handle is IHandle, Initializable, UUPSUpgradeable, IValidator, Roles {
    using SafeMath for uint256;

    // Collateral token configuration.
    address[] private collateralTokens;
    mapping(address => bool) public override isCollateralValid;
    mapping(address => CollateralData) private collateralDetails;
    // tokenAddress=>collateral balance held
    mapping(address => uint256) public totalBalances;

    // fxToken configuration.
    address[] public validFxTokens;
    mapping(address => bool) public override isFxTokenValid;

    // User address => fxToken address => Vault data
    mapping(address => mapping(address => Vault)) public vaults;

    // Ratio of maximum Treasury collateral that can be managed by the PCT.
    uint256 public override pctCollateralUpperBound;
    // Per mille fee settings
    uint256 public override mintFeePerMille;
    uint256 public override burnFeePerMille;
    uint256 public override withdrawFeePerMille;
    uint256 public override depositFeePerMille;

    // Address for sending protocol fees.
    address public override FeeRecipient;
    // Canonical Wrapped Ether address.
    address public override WETH;
    // ERC20 address => oracle aggregator address
    mapping(address => address) public oracles;

    bool public override isPaused;

    // Handle contract components.
    address payable public override treasury;
    address public override comptroller;
    address public override vaultLibrary;
    address public override fxKeeperPool;
    address public override pct;
    address public override liquidator;
    address public override interest;

    modifier notPaused() {
        require(!isPaused, "Paused");
        _;
    }

    function initialize(address weth) public initializer {
        __AccessControl_init();
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        WETH = weth;
    }

    function setCollateralUpperBoundPCT(uint256 ratio)
        external
        override
        onlyAdmin
    {
        pctCollateralUpperBound = ratio;
    }

    function setPaused(bool value) external override onlyAdmin {
        isPaused = value;
    }

    function setFxToken(address token) public override onlyAdmin {
        validFxTokens.push(token);
        isFxTokenValid[token] = true;
        emit ConfigureFxToken(token);
    }

    function removeFxToken(address token) external override onlyAdmin {
        uint256 tokenIndex = validFxTokens.length;
        for (uint256 i = 0; i < tokenIndex; i++) {
            if (validFxTokens[i] == token) {
                tokenIndex = i;
                break;
            }
        }
        // Assert that token was found.
        assert(tokenIndex < validFxTokens.length);
        delete isFxTokenValid[token];
        if (tokenIndex < validFxTokens.length - 1) {
            delete validFxTokens[tokenIndex];
            // Replace to-be-deleted item with last element and then pop array.
            validFxTokens[tokenIndex] = validFxTokens[validFxTokens.length - 1];
            validFxTokens.pop();
        } else {
            // Token index is last element, so no need to pop array.
            delete validFxTokens[tokenIndex];
        }
        emit ConfigureFxToken(token);
    }

    function setCollateralToken(
        address token,
        uint256 mintCR,
        uint256 liquidationFee,
        uint256 interestRatePerMille
    ) external override onlyOperatorOrAdmin {
        require(mintCR >= 110, "CR");
        CollateralData storage collateral = collateralDetails[token];
        // Only push new collateral token if it does not exist.
        if (collateral.mintCR == 0) {
            collateralTokens.push(token);
            isCollateralValid[token] = true;
        }
        // Charge interest to write R value for current interest rate.
        IInterest(interest).charge();
        collateral.mintCR = mintCR;
        collateral.liquidationFee = liquidationFee;
        collateral.interestRate = interestRatePerMille;
        emit ConfigureCollateralToken(token);
    }

    function removeCollateralToken(address token) external override onlyAdmin {
        // Cannot remove a token, as this would orphan user collateral. Mark it invalid instead.
        delete isCollateralValid[token];
        emit ConfigureCollateralToken(token);
    }

    /**
     * @notice updates contract components
     * @param components an array with the address of the components, where:
              index 0: treasury
              index 1: comptroller
              index 2: vaultLibrary
              index 3: fxKeeperPool
              index 4: pct
              index 5: liquidator
              index 6: interest
     */
    function setComponents(address[] memory components)
        external
        override
        onlyAdmin
    {
        uint256 l = components.length;
        for (uint256 i = 0; i < l; i++) {
            require(components[i] != address(0), "Invalid address");
        }
        treasury = payable(components[0]);
        comptroller = components[1];
        vaultLibrary = components[2];
        fxKeeperPool = components[3];
        pct = components[4];
        liquidator = components[5];
        interest = components[6];
        for (uint256 i = 0; i < 7; i++) {
            // Skip VaultLibrary and fxKeeperPool.
            if (i == 2 || i == 3) continue;
            // Grant operator roles if needed.
            if (!hasRole(OPERATOR_ROLE, components[i]))
                grantRole(OPERATOR_ROLE, components[i]);
        }
    }

    function getAllCollateralTypes()
        public
        view
        override
        returns (address[] memory collateral)
    {
        collateral = collateralTokens;
    }

    function getCollateralDetails(address collateral)
        external
        view
        override
        returns (CollateralData memory)
    {
        return collateralDetails[collateral];
    }

    /**
     * @notice updates a vault's debt position
     * @dev can only be called by the comptroller
     * @param account vault account
     * @param fxToken vault fxToken
     * @param increase whether to increase or decrease the position
     */
    function updateDebtPosition(
        address account,
        uint256 amount,
        address fxToken,
        bool increase
    ) external override onlyOperator notPaused {
        // Charge interest.
        IInterest(interest).charge();
        // Compound debt by getting current principal + interest.
        uint256 debt = getDebt(account, fxToken);
        // Reset R0 value.
        resetVaultR0(account, fxToken);
        // Increase/decrease vault debt.
        vaults[account][fxToken].debt = increase
            ? debt.add(amount)
            : debt.sub(amount);
        emit UpdateDebt(account, fxToken);
    }

    function updateCollateralBalance(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken,
        bool increase
    ) external override onlyOperator notPaused {
        uint256 currentAccountBalance =
            vaults[account][fxToken].collateralBalance[collateralToken];

        vaults[account][fxToken].collateralBalance[collateralToken] = increase
            ? currentAccountBalance.add(amount)
            : currentAccountBalance.sub(amount);

        totalBalances[collateralToken] = increase
            ? totalBalances[collateralToken].add(amount)
            : totalBalances[collateralToken].sub(amount);

        emit UpdateCollateral(account, fxToken, collateralToken);
    }

    function setFeeRecipient(address feeRecipient)
        external
        override
        onlyAdmin
        validAddress(feeRecipient)
    {
        FeeRecipient = feeRecipient;
    }

    function setFees(
        uint256 _withdrawFeePerMille,
        uint256 _depositFeePerMille,
        uint256 _mintFeePerMille,
        uint256 _burnFeePerMille
    ) external override onlyAdmin {
        withdrawFeePerMille = _withdrawFeePerMille;
        depositFeePerMille = _depositFeePerMille;
        burnFeePerMille = _burnFeePerMille;
        mintFeePerMille = _mintFeePerMille;
    }

    /**
     * @notice Returns a user's collateral balance for a given collateral type
     * @param account the user's address
     * @param fxToken the vault to check
     * @param collateralType the collateral token address
     * @return balance
     */
    function getCollateralBalance(
        address account,
        address collateralType,
        address fxToken
    ) external view override returns (uint256 balance) {
        balance = vaults[account][fxToken].collateralBalance[collateralType];
    }

    /**
     * @notice returns the total amount of ETH lodged as collateral
     * @param account the account to check
     * @param fxToken the vault to check
     * @return collateral the collateral checked
     * @return balances the balances
     */
    function getBalance(address account, address fxToken)
        external
        view
        override
        returns (address[] memory collateral, uint256[] memory balances)
    {
        collateral = getAllCollateralTypes();
        uint256 j = collateral.length;
        uint256[] memory _balances = new uint256[](j);
        for (uint256 i = 0; i < j; i++) {
            _balances[i] = vaults[account][fxToken].collateralBalance[
                collateral[i]
            ];
        }
        balances = _balances;
    }

    /**
     * @notice getter for vault collateral R0
     * @param account the vault owner
     * @param fxToken the vault to get the value for
     * @param collateral the collateral token for the R0 value
     * @return R0 the R0 interest value
     */
    function getCollateralR0(
        address account,
        address fxToken,
        address collateral
    ) external view override returns (uint256 R0) {
        R0 = vaults[account][fxToken].R0[collateral];
    }

    /**
     * @notice sets the R0 values to the current R values for the vault
     * @param account the vault owner
     * @param fxToken the vault fxToken
     */
    function resetVaultR0(address account, address fxToken) private {
        (uint256[] memory R, address[] memory collateralTokens) =
            IInterest(interest).getCurrentR();
        uint256 j = collateralTokens.length;
        Vault storage vault = vaults[account][fxToken];
        for (uint256 i = 0; i < j; i++) {
            vault.R0[collateralTokens[i]] = R[i];
        }
    }

    /**
     * @notice returns the total vault debt with interest
     * @param account the vault account
     * @param fxToken the vault to get the debt for
     * @return _debt the amount of fxToken debt outstanding
     */
    function getDebt(address account, address fxToken)
        public
        view
        override
        returns (uint256)
    {
        uint256 debt = vaults[account][fxToken].debt;
        return
            debt.add(
                IVaultLibrary(vaultLibrary).calculateInterest(account, fxToken)
            );
    }

    /**
     * @notice returns the total vault debt without interest
     * @param account the vault account
     * @param fxToken the vault to get the debt for
     * @return _debt the amount of fxToken debt outstanding
     */
    function getPrincipalDebt(address account, address fxToken)
        external
        view
        override
        returns (uint256)
    {
        return vaults[account][fxToken].debt;
    }

    /**
     * @notice Returns the amount of ETH required to purchase 1 unit of token
     * @param token the fxToken to get the price of
     * @return quote The price of 1 token in ETH
     */
    function getTokenPrice(address token)
        public
        view
        override
        returns (uint256 quote)
    {
        if (token == WETH) return 1 ether;
        require(oracles[token] != address(0), "No oracle for token");
        quote = IOracle(oracles[token]).getRate(token);
        require(quote > 0, "Token price is zero");
    }

    /**
     * @notice sets an oracle for a given fxToken
     * @param _fxToken the fxToken to set the oracle for
     * @param _oracle the oracle to use for the fxToken
     */
    function setOracle(address _fxToken, address _oracle)
        external
        override
        onlyAdmin
    {
        require(_fxToken != address(0) && _oracle != address(0), "IZ");
        oracles[_fxToken] = _oracle;
    }

    function _authorizeUpgrade(address) internal override onlyAdmin {}
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

import "../ERC1967/ERC1967UpgradeUpgradeable.sol";
import "./Initializable.sol";

/**
 * @dev Base contract for building openzeppelin-upgrades compatible implementations for the {ERC1967Proxy}. It includes
 * publicly available upgrade functions that are called by the plugin and by the secure upgrade mechanism to verify
 * continuation of the upgradability.
 *
 * The {_authorizeUpgrade} function MUST be overridden to include access restriction to the upgrade mechanism.
 *
 * _Available since v4.1._
 */
abstract contract UUPSUpgradeable is Initializable, ERC1967UpgradeUpgradeable {
    function __UUPSUpgradeable_init() internal initializer {
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();
    }

    function __UUPSUpgradeable_init_unchained() internal initializer {
    }
    function upgradeTo(address newImplementation) external virtual {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, bytes(""), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;
    uint256[50] private __gap;
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

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

pragma abicoder v2;

interface IHandle {
    struct Vault {
        // Collateral token address => balance
        mapping(address => uint256) collateralBalance;
        uint256 debt;
        // Collateral token address => R0
        mapping(address => uint256) R0;
    }

    struct CollateralData {
        uint256 mintCR;
        uint256 liquidationFee;
        uint256 interestRate;
    }

    event UpdateDebt(address indexed account, address indexed fxToken);

    event UpdateCollateral(
        address indexed account,
        address indexed fxToken,
        address indexed collateralToken
    );

    event ConfigureCollateralToken(address indexed collateralToken);

    event ConfigureFxToken(address indexed fxToken);

    function setCollateralUpperBoundPCT(uint256 ratio) external;

    function setPaused(bool value) external;

    function setFxToken(address token) external;

    function removeFxToken(address token) external;

    function setCollateralToken(
        address token,
        uint256 mintCR,
        uint256 liquidationFee,
        uint256 interestRatePerMille
    ) external;

    function removeCollateralToken(address token) external;

    function getAllCollateralTypes()
        external
        view
        returns (address[] memory collateral);

    function getCollateralDetails(address collateral)
        external
        view
        returns (CollateralData memory);

    function WETH() external view returns (address);

    function treasury() external view returns (address payable);

    function comptroller() external view returns (address);

    function vaultLibrary() external view returns (address);

    function fxKeeperPool() external view returns (address);

    function pct() external view returns (address);

    function liquidator() external view returns (address);

    function interest() external view returns (address);

    function pctCollateralUpperBound() external view returns (uint256);

    function isFxTokenValid(address fxToken) external view returns (bool);

    function isCollateralValid(address collateral) external view returns (bool);

    function setComponents(address[] memory components) external;

    function updateDebtPosition(
        address account,
        uint256 amount,
        address fxToken,
        bool increase
    ) external;

    function updateCollateralBalance(
        address account,
        uint256 amount,
        address fxToken,
        address collateralToken,
        bool increase
    ) external;

    function setFeeRecipient(address feeRecipient) external;

    function setFees(
        uint256 withdrawFeePerMille,
        uint256 depositFeePerMille,
        uint256 mintFeePerMille,
        uint256 burnFeePerMille
    ) external;

    function getCollateralBalance(
        address account,
        address collateralType,
        address fxToken
    ) external view returns (uint256 balance);

    function getBalance(address account, address fxToken)
        external
        view
        returns (address[] memory collateral, uint256[] memory balances);

    function getDebt(address owner, address fxToken)
        external
        view
        returns (uint256 _debt);

    function getPrincipalDebt(address owner, address fxToken)
        external
        view
        returns (uint256 _debt);

    function getCollateralR0(
        address account,
        address fxToken,
        address collateral
    ) external view returns (uint256 R0);

    function getTokenPrice(address token) external view returns (uint256 quote);

    function setOracle(address fxToken, address oracle) external;

    function FeeRecipient() external view returns (address);

    function mintFeePerMille() external view returns (uint256);

    function burnFeePerMille() external view returns (uint256);

    function withdrawFeePerMille() external view returns (uint256);

    function depositFeePerMille() external view returns (uint256);

    function isPaused() external view returns (bool);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ITreasury {
    function depositCollateral(
        address account,
        uint256 depositAmount,
        address collateralType,
        address fxToken
    ) external;

    function depositCollateralETH(address account, address fxToken)
        external
        payable;

    function withdrawCollateral(
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) external;

    function withdrawCollateralETH(
        address to,
        uint256 amount,
        address fxToken
    ) external;

    function withdrawCollateralFrom(
        address from,
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) external;

    function forceWithdrawCollateral(
        address from,
        address collateralToken,
        address to,
        uint256 amount,
        address fxToken
    ) external;

    function forceWithdrawAnyCollateral(
        address from,
        address to,
        uint256 amount,
        address fxToken,
        bool requireFullAmount
    )
        external
        returns (
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts
        );

    function requestFundsPCT(address token, uint256 amount) external;

    function setMaximumTotalDepositAllowed(uint256 value) external;

    // function totalCollateralDeposited() external view returns (uint256);

    // function maximumTotalDepositAllowed() external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IValidator {
    modifier dueBy(uint256 date) {
        require(block.timestamp <= date, "Transaction has exceeded deadline");
        _;
    }

    modifier validAddress(address _address) {
        require(_address != address(0), "Invalid Address");
        _;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IVaultLibrary {
    function doesMeetRatio(address account, address fxToken)
        external
        view
        returns (bool);

    function getFreeCollateralAsEth(address account, address fxToken)
        external
        view
        returns (uint256);

    function getFreeCollateralAsEthFromMinimumRatio(
        address account,
        address fxToken,
        uint256 minimumRatio
    ) external view returns (uint256);

    function getMinimumRatio(address account, address fxToken)
        external
        view
        returns (uint256 ratio);

    function getMinimumCollateral(
        uint256 tokenAmount,
        uint256 ratio,
        uint256 unitPrice
    ) external view returns (uint256 minimum);

    function getDebtAsEth(address account, address fxToken)
        external
        view
        returns (uint256 debt);

    function getTotalCollateralBalanceAsEth(address account, address fxToken)
        external
        view
        returns (uint256 balance);

    function getCurrentRatio(address account, address fxToken)
        external
        view
        returns (uint256 ratio);

    function getCollateralForAmount(
        address account,
        address fxToken,
        uint256 amountEth
    )
        external
        view
        returns (
            address[] memory collateralTypes,
            uint256[] memory collateralAmounts,
            bool metAmount
        );

    function getDecimalsAmount(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) external pure returns (uint256);

    function calculateInterest(address account, address fxToken)
        external
        view
        returns (uint256 interest);

    function getInterestRate(address account, address fxToken)
        external
        view
        returns (uint256 rate);

    function getInterestDeltaR(address account, address fxToken)
        external
        view
        returns (uint256 dR);

    function getLiquidationFee(address account, address fxToken)
        external
        view
        returns (uint256 fee);

    function getCollateralShares(address account, address fxToken)
        external
        view
        returns (uint256[] memory shares);

    function getCollateralTypesSortedByLiquidationRank()
        external
        view
        returns (address[] memory sortedCollateralTypes);

    function getNewMinimumRatio(
        address account,
        address fxToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 collateralQuote,
        bool isDeposit
    ) external view returns (uint256 ratio, uint256 newCollateralAsEther);

    function canMint(
        address account,
        address fxToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 tokenAmount,
        uint256 fxQuote,
        uint256 collateralQuote
    ) external view returns (bool);

    function quickSort(
        uint256[] memory array,
        int256 left,
        int256 right
    ) external pure;

    function getTokenUnit(address token) external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IComptroller {
    event MintToken(
        uint256 tokenRate,
        uint256 amountMinted,
        address indexed token
    );

    event BurnToken(uint256 amountBurned, address indexed token);

    function mintWithEth(
        uint256 tokenAmountDesired,
        address fxToken,
        uint256 deadline
    ) external payable;

    function mint(
        uint256 amountDesired,
        address fxToken,
        address collateralToken,
        uint256 collateralAmount,
        uint256 deadline
    ) external;

    function mintWithoutCollateral(
        uint256 tokenAmountDesired,
        address token,
        uint256 deadline
    ) external;

    function burn(
        uint256 amount,
        address token,
        uint256 deadline
    ) external;

    function setMinimumMintingAmount(uint256 amount) external;

    function minimumMintingAmount() external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IOracle {
    /**
     * @notice Returns the price of 1 fxAsset in ETH
     * @param fxAsset the asset to get a rate for
     * @return unitPrice the cost of a single fxAsset in ETH
     */
    function getRate(address fxAsset) external view returns (uint256 unitPrice);

    /**
     * @notice A setter function to add or update an oracle for a given fx asset.
     * @param fxAsset the asset to update
     * @param oracle the oracle to set for the fxAsset
     */
    function setOracle(address fxAsset, address oracle) external;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IInterest {
    struct ExternalAssetData {
        bytes32 makerDaoCollateralIlk;
    }

    function setCollateralExternalAssetData(
        address collateral,
        bytes32 makerDaoCollateralIlk
    ) external;

    function unsetCollateralExternalAssetData(address collateral) external;

    function setMaxExternalSourceInterest(uint256 interestPerMille) external;

    function charge() external;

    function getCurrentR()
        external
        view
        returns (uint256[] memory R, address[] memory collateralTokens);

    function setDataSource(address source) external;

    function tryUpdateRates() external;

    function updateRates() external;

    function fetchRate(address token) external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract Roles is AccessControlUpgradeable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "NO");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "NA");
        _;
    }

    modifier onlyOperatorOrAdmin() {
        require(
            hasRole(OPERATOR_ROLE, msg.sender) ||
                hasRole(ADMIN_ROLE, msg.sender),
            "NW"
        );
        _;
    }

    modifier onlyAddressOrOperatorExcludeAdmin(address addressAllowed) {
        // Protect user deposits from abuse
        require(
            msg.sender == addressAllowed ||
                (hasRole(OPERATOR_ROLE, msg.sender) &&
                    !hasRole(ADMIN_ROLE, msg.sender)),
            "NW"
        );
        _;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../beacon/IBeaconUpgradeable.sol";
import "../../utils/AddressUpgradeable.sol";
import "../../utils/StorageSlotUpgradeable.sol";
import "../utils/Initializable.sol";

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 *
 * @custom:oz-upgrades-unsafe-allow delegatecall
 */
abstract contract ERC1967UpgradeUpgradeable is Initializable {
    function __ERC1967Upgrade_init() internal initializer {
        __ERC1967Upgrade_init_unchained();
    }

    function __ERC1967Upgrade_init_unchained() internal initializer {
    }
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(AddressUpgradeable.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallSecure(address newImplementation, bytes memory data, bool forceCall) internal {
        address oldImplementation = _getImplementation();

        // Initial upgrade and setup call
        _setImplementation(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }

        // Perform rollback test if not already in progress
        StorageSlotUpgradeable.BooleanSlot storage rollbackTesting = StorageSlotUpgradeable.getBooleanSlot(_ROLLBACK_SLOT);
        if (!rollbackTesting.value) {
            // Trigger rollback using upgradeTo from the new implementation
            rollbackTesting.value = true;
            _functionDelegateCall(
                newImplementation,
                abi.encodeWithSignature(
                    "upgradeTo(address)",
                    oldImplementation
                )
            );
            rollbackTesting.value = false;
            // Check rollback was effective
            require(oldImplementation == _getImplementation(), "ERC1967Upgrade: upgrade breaks further upgrades");
            // Finally reset to the new implementation and log the upgrade
            _setImplementation(newImplementation);
            emit Upgraded(newImplementation);
        }
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(address newBeacon, bytes memory data, bool forceCall) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(IBeaconUpgradeable(newBeacon).implementation(), data);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Emitted when the beacon is upgraded.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(
            AddressUpgradeable.isContract(newBeacon),
            "ERC1967: new beacon is not a contract"
        );
        require(
            AddressUpgradeable.isContract(IBeaconUpgradeable(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /*
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function _functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
        require(AddressUpgradeable.isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, "Address: low-level delegate call failed");
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
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeaconUpgradeable {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
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
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlotUpgradeable {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../utils/StringsUpgradeable.sol";
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
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

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
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
     */
    function _checkRole(bytes32 role, address account) internal view {
        if(!hasRole(role, account)) {
            revert(string(abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(account), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(role), 32)
            )));
        }
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
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
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
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
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

/**
 * @dev String operations.
 */
library StringsUpgradeable {
    bytes16 private constant alphabet = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = alphabet[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

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

