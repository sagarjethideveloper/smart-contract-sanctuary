// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

import "../../utils/Address.sol";

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
pragma solidity 0.8.1;
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/IBSWrapperToken.sol";
import "./interfaces/IDebtToken.sol";

////////////////////////////////////////////////////////////////////////////////////////////
/// @title DataTypes
/// @author @samparsky
////////////////////////////////////////////////////////////////////////////////////////////

library DataTypes {
    struct BorrowAssetConfig {
        uint256 initialExchangeRateMantissa;
        uint256 reserveFactorMantissa;
        uint256 collateralFactor;
        IBSWrapperToken wrappedBorrowAsset;
        uint256 liquidationFee;
        IDebtToken debtToken;
    }

    function validBorrowAssetConfig(BorrowAssetConfig memory self, address _owner) internal view {
        require(self.initialExchangeRateMantissa > 0, "E");
        require(self.reserveFactorMantissa > 0, "F");
        require(self.collateralFactor > 0, "C");
        require(self.liquidationFee > 0, "L");
        require(address(self.wrappedBorrowAsset) != address(0), "B");
        require(address(self.debtToken) != address(0), "IB");
        require(self.wrappedBorrowAsset.owner() == _owner, "IW");
        require(self.debtToken.owner() == _owner, "IVW");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IPriceOracleAggregator.sol";
import "./IBSWrapperToken.sol";
import "./IDebtToken.sol";
import "./IBSVault.sol";
import "../DataTypes.sol";

interface IBSLendingPair {
    event Initialized(
        address indexed pair,
        address indexed asset,
        address indexed collateralAsset,
        address pauseGuardian
    );

    /**
     * Emitted on deposit
     *
     * @param pair The pair being interacted with
     * @param asset The asset deposited in the pair
     * @param tokenReceipeint The user the receives the bsTokens
     * @param user The user that made the deposit
     * @param amount The amount deposited
     **/
    event Deposit(
        address indexed pair,
        address indexed asset,
        address indexed tokenReceipeint,
        address user,
        uint256 amount
    );

    event Borrow(address indexed borrower, uint256 amount);

    /**
     * Emitted on Redeem
     *
     * @param pair The pair being interacted with
     * @param asset The asset withdraw in the pair
     * @param user The user that's making the withdrawal
     * @param to The user the receives the withdrawn tokens
     * @param amount The amount being withdrawn
     **/
    event Redeem(
        address indexed pair,
        address indexed asset,
        address indexed user,
        address to,
        uint256 amount,
        uint256 amountofWrappedBurned
    );

    event WithdrawCollateral(address account, uint256 amount);

    event ReserveWithdraw(address user, uint256 shares);

    /**
     * Emitted on repay
     *
     * @param pair The pair being interacted with
     * @param asset The asset repaid in the pair
     * @param beneficiary The user that's getting their debt reduced
     * @param repayer The user that's providing the funds
     * @param amount The amount being repaid
     **/
    event Repay(
        address indexed pair,
        address indexed asset,
        address indexed beneficiary,
        address repayer,
        uint256 amount
    );

    /**
     * Emitted on liquidation
     *
     * @param pair The pair being interacted with
     * @param asset The asset that getting liquidated
     * @param user The user that's getting liquidated
     * @param liquidatedCollateralAmount The of collateral transferred to the liquidator
     * @param liquidator The liquidator
     **/
    event Liquidate(
        address indexed pair,
        address indexed asset,
        address indexed user,
        uint256 liquidatedCollateralAmount,
        address liquidator
    );

    /**
     * @dev Emitted on flashLoan
     * @param target The address of the flash loan receiver contract
     * @param initiator The address initiating the flash loan
     * @param asset The address of the asset being flash borrowed
     * @param amount The amount flash borrowed
     * @param premium The fee flash borrowed
     **/
    event FlashLoan(
        address indexed target,
        address indexed initiator,
        address indexed asset,
        uint256 amount,
        uint256 premium
    );

    /**
     * @dev Emitted on interest accrued
     * @param accrualBlockNumber block number
     * @param borrowIndex borrow index
     * @param totalBorrows total borrows
     * @param totalReserves total reserves
     **/
    event InterestAccrued(
        address indexed pair,
        uint256 accrualBlockNumber,
        uint256 borrowIndex,
        uint256 totalBorrows,
        uint256 totalReserves
    );

    event InterestShortCircuit(uint256 blockNumber);

    event ActionPaused(uint8 action, uint256 timestamp);
    event ActionUnPaused(uint8 action, uint256 timestamp);

    function initialize(
        string memory _name,
        string memory _symbol,
        IERC20 _asset,
        IERC20 _collateralAsset,
        DataTypes.BorrowAssetConfig calldata borrowConfig,
        IBSWrapperToken _wrappedCollateralAsset,
        IInterestRateModel _interestRate,
        address _pauseGuardian
    ) external;

    function asset() external view returns (IERC20);

    function depositBorrowAsset(address _tokenReceipeint, uint256 _amount) external;

    function depositCollateral(address _tokenReceipeint, uint256 _vaultShareAmount) external;

    function redeem(address _to, uint256 _amount) external;

    function collateralOfAccount(address _account) external view returns (uint256);

    function getMaxWithdrawAllowed(address account) external returns (uint256);

    function oracle() external view returns (IPriceOracleAggregator);

    function collateralAsset() external view returns (IERC20);

    function calcBorrowLimit(uint256 amount) external view returns (uint256);

    function accountInterestIndex(address) external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    function debtToken() external view returns (IDebtToken);

    function borrowBalancePrior(address _account) external view returns (uint256);

    function wrapperBorrowedAsset() external view returns (IBSWrapperToken);

    function wrappedCollateralAsset() external view returns (IBSWrapperToken);

    function totalReserves() external view returns (uint256);

    function withdrawFees(uint256 amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IERC3156FlashLender.sol";

interface IBSVault is IERC3156FlashLender {
    // ************** //
    // *** EVENTS *** //
    // ************** //

    /// @notice Emitted on deposit
    /// @param token being deposited
    /// @param from address making the depsoit
    /// @param to address to credit the tokens being deposited
    /// @param amount being deposited
    /// @param shares the represent the amount deposited in the vault
    event Deposit(
        IERC20 indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 shares
    );

    /// @notice Emitted on withdraw
    /// @param token being deposited
    /// @param from address making the depsoit
    /// @param to address to credit the tokens being withdrawn
    /// @param amount Amount of underlying being withdrawn
    /// @param shares the represent the amount withdraw from the vault
    event Withdraw(
        IERC20 indexed token,
        address indexed from,
        address indexed to,
        uint256 shares,
        uint256 amount
    );

    event Transfer(IERC20 indexed token, address indexed from, address indexed to, uint256 amount);

    event FlashLoan(
        address indexed borrower,
        IERC20 indexed token,
        uint256 amount,
        uint256 feeAmount,
        address indexed receiver
    );

    event TransferControl(address _newTeam, uint256 timestamp);

    event UpdateFlashLoanRate(uint256 newRate);

    event Approval(address indexed user, address indexed allowed, bool status);

    event OwnershipAccepted(address newOwner, uint256 timestamp);

    event RegisterProtocol(address sender);

    event AllowContract(address whitelist, bool status);

    // ************** //
    // *** FUNCTIONS *** //
    // ************** //

    function initialize(uint256 _flashLoanRate, address _owner) external;

    function approveContract(
        address _user,
        address _contract,
        bool _status,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function deposit(
        IERC20 _token,
        address _from,
        address _to,
        uint256 _amount
    ) external returns (uint256);

    function withdraw(
        IERC20 _token,
        address _from,
        address _to,
        uint256 _amount
    ) external returns (uint256);

    function balanceOf(IERC20, address) external view returns (uint256);

    function transfer(
        IERC20 _token,
        address _from,
        address _to,
        uint256 _shares
    ) external;

    function toShare(
        IERC20 token,
        uint256 amount,
        bool ceil
    ) external view returns (uint256);

    function toUnderlying(IERC20 token, uint256 share) external view returns (uint256);

}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRewardDistributorManager.sol";

interface IBSWrapperTokenBase is IERC20 {
    function initialize(
        address _owner,
        address _underlying,
        string memory _tokenName,
        string memory _tokenSymbol,
        IRewardDistributorManager _manager
    ) external;

    function burn(address _from, uint256 _amount) external;

    function owner() external view returns (address);
}

interface IBSWrapperToken is IBSWrapperTokenBase {
    function mint(address _to, uint256 _amount) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import {IBSWrapperTokenBase} from "./IBSWrapperToken.sol";

interface IDebtToken is IBSWrapperTokenBase {
    event DelegateBorrow(address from, address to, uint256 amount, uint256 timestamp);

    function increaseTotalDebt(uint256 _amount) external;

    function principal(address _account) external view returns (uint256);

    function mint(
        address _to,
        address _owner,
        uint256 _amount
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

interface IERC3156FlashBorrower {
    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.1;
import "./IERC3156FlashBorrower.sol";

interface IERC3156FlashLender {
    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256);

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256);

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

interface IInterestRateModel {
    /**
     * @notice Calculates the current borrow interest rate per block
     * @param cash The total amount of cash the market has
     * @param borrows The total amount of borrows the market has outstanding
     * @param reserves The total amount of reserves the market has
     * @return The borrow rate per block (as a percentage, and scaled by 1e18)
     */
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);

    /**
     * @notice Calculates the current supply interest rate per block
     * @param cash The total amount of cash the market has
     * @param borrows The total amount of borrows the market has outstanding
     * @param reserves The total amount of reserves the market has
     * @param reserveFactorMantissa The current reserve factor the market has
     * @return The supply rate per block (as a percentage, and scaled by 1e18)
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

interface IOracle {
    /// @notice Price update event
    /// @param asset the asset
    /// @param newPrice price of the asset
    event PriceUpdated(address asset, uint256 newPrice);

    /// @dev returns latest answer
    function latestAnswer() external view returns (int256);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IOracle.sol";

interface IPriceOracleAggregator {
    event UpdateOracle(IERC20 token, IOracle oracle);

    function getPriceInUSD(IERC20 _token) external view returns (uint256);

    function getPriceInUSDMultiple(IERC20[] calldata _tokens)
        external
        view
        returns (uint256[] memory);

    function setOracleForAsset(IERC20[] calldata _asset, IOracle[] calldata _oracle) external;

    event OwnershipAccepted(address newOwner, uint256 timestamp);
    event TransferControl(address _newTeam, uint256 timestamp);
    event StableTokenAdded(IERC20 _token, uint256 timestamp);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardDistributor {
    event Initialized(
        IERC20 indexed _rewardToken,
        uint256 _amountDistributePerSecond,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        address _guardian,
        uint256 timestamp
    );

    function accumulateReward(address _tokenAddr, address _user) external;

    function endTimestamp() external returns (uint256);

    function initialize(
        string calldata _name,
        IERC20 _rewardToken,
        uint256 _amountDistributePerSecond,
        uint256 _startTimestamp,
        uint256 _endTimestamp,
        address _guardian
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "./IRewardDistributor.sol";

interface IRewardDistributorManager {
    /// @dev Emitted on Initialization
    event Initialized(address owner, uint256 timestamp);

    event ApprovedDistributor(IRewardDistributor distributor, uint256 timestamp);
    event AddReward(address tokenAddr, IRewardDistributor distributor, uint256 timestamp);
    event RemoveReward(address tokenAddr, IRewardDistributor distributor, uint256 timestamp);
    event TransferControl(address _newTeam, uint256 timestamp);
    event OwnershipAccepted(address newOwner, uint256 timestamp);

    function activateReward(address _tokenAddr) external;

    function removeReward(address _tokenAddr, IRewardDistributor _distributor) external;

    function accumulateRewards(address _from, address _to) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRewardDistributor.sol";
import "../interfaces/IBSLendingPair.sol";
import "../upgradability/UUPSProxiable.sol";
import "../interfaces/IRewardDistributorManager.sol";

abstract contract RewardDistirbutorManagerStorageV1 is UUPSProxiable, IRewardDistributorManager {
    /// @dev admin
    address public owner;

    /// @dev newAdmin
    address internal newOwner;

    /// @dev approvedistributions
    mapping(IRewardDistributor => bool) public approvedDistributors;

    /// @dev receipt token address => distributor
    mapping(address => IRewardDistributor[]) public tokenRewardToDistributors;
}

contract RewardDistributorManager is RewardDistirbutorManagerStorageV1 {
    modifier onlyOwner {
        require(owner == msg.sender, "ONLY_OWNER");
        _;
    }

    /// @notice initialize
    /// @param _owner owner to perform owner functions
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "INVALID_OWNER");

        owner = _owner;

        emit Initialized(_owner, block.timestamp);
    }

    /// @dev Accumulates rewards for users
    /// @param _from user address
    /// @param _to user address
    function accumulateRewards(address _from, address _to) external override {
        IRewardDistributor[] memory distributors = tokenRewardToDistributors[msg.sender];
        uint256 size = distributors.length;

        if (size == 0) return;

        /// We need to manage the size of the rewards to prevent
        /// astronomical increase in gas cost
        for (uint256 i = 0; i < size; i++) {
            if (_from != address(0)) distributors[i].accumulateReward(msg.sender, _from);
            if (_to != address(0)) distributors[i].accumulateReward(msg.sender, _to);
        }
    }

    /// @dev approves a distributor contract for a token
    /// @param _distributor The distributor contract address
    /// @param _approve the status of the distributor contract
    function setDistributorStatus(IRewardDistributor _distributor, bool _approve)
        external
        onlyOwner
    {
        approvedDistributors[_distributor] = _approve;
        emit ApprovedDistributor(_distributor, block.timestamp);
    }

    /// @dev Enables a distributor contract to activate reward for a token
    /// @param _tokenAddr the token the distributor contract is adding a reward for
    function activateReward(address _tokenAddr) external override {
        require(
            approvedDistributors[IRewardDistributor(msg.sender)] == true,
            "ONLY_APPROVED_DISTRIBUTOR"
        );

        IRewardDistributor[] storage distributors = tokenRewardToDistributors[_tokenAddr];

        require(
            findRewardDistributor(distributors, IRewardDistributor(msg.sender)) == -1,
            "DISTRIBUTOR_EXISTS"
        );

        distributors.push(IRewardDistributor(msg.sender));

        emit AddReward(_tokenAddr, IRewardDistributor(msg.sender), block.timestamp);
    }

    /// @dev Remove  a reward distributor
    /// @param _tokenAddr address of the receipt token
    /// @param _distributor distributor contract
    function removeReward(address _tokenAddr, IRewardDistributor _distributor)
        external
        override
        onlyOwner
    {
        IRewardDistributor[] storage distributors = tokenRewardToDistributors[_tokenAddr];
        uint256 size = distributors.length;

        int256 rewardIndex = findRewardDistributor(distributors, _distributor);
        if (rewardIndex == -1) return;

        distributors[uint256(rewardIndex)] = distributors[size - 1];
        // used pop instead of delete because pop reduces array length
        distributors.pop();

        emit RemoveReward(_tokenAddr, _distributor, block.timestamp);
    }

    function findRewardDistributor(
        IRewardDistributor[] memory distributors,
        IRewardDistributor _distributor
    ) internal pure returns (int256 index) {
        index = -1;
        uint256 size = distributors.length;
        for (uint256 i = 0; i < size; i++) {
            if (address(distributors[i]) == address(_distributor)) {
                index = int256(i);
                break;
            }
        }
    }

    function commitOwnerTransfer(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "INVALID_NEW_OWNER");
        newOwner = _newOwner;
        emit TransferControl(_newOwner, block.timestamp);
    }

    function acceptOwnerTransfer() external {
        require(msg.sender == newOwner, "invalid owner");
        owner = newOwner;
        newOwner = address(0);
        emit OwnershipAccepted(newOwner, block.timestamp);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // UUPSProxiable
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("org.warp.contracts.warprewards.implementation");
    }

    function updateCode(address newAddress) external override onlyOwner {
        _updateCodeAddress(newAddress);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import {UUPSUtils} from "./UUPSUtils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev UUPS (Universal Upgradeable Proxy Standard) Proxiable contract.
 */
abstract contract UUPSProxiable is Initializable {
    /**
     * @dev Get current implementation code address.
     */
    function getCodeAddress() public view returns (address codeAddress) {
        return UUPSUtils.implementation();
    }

    function updateCode(address newAddress) external virtual;

    /**
     * @dev Proxiable UUID marker function.
     *      This would help to avoid wrong logic contract to be used for upgrading.
     */
    function proxiableUUID() public view virtual returns (bytes32);

    /**
     * @dev Update code address function.
     *      It is internal, so the derived contract could setup its own permission logic.
     */
    function _updateCodeAddress(address newAddress) internal {
        require(UUPSUtils.implementation() != address(0), "UUPSProxiable: not upgradable");
        require(
            proxiableUUID() == UUPSProxiable(newAddress).proxiableUUID(),
            "UUPSProxiable: not compatible logic"
        );
        UUPSUtils.setImplementation(newAddress);
        emit CodeUpdated(proxiableUUID(), newAddress);
    }

    event CodeUpdated(bytes32 uuid, address codeAddress);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

/**
 * @title UUPS (Universal Upgradeable Proxy Standard) Shared Library
 */
library UUPSUtils {
    /**
     * @dev Implementation slot constant.
     * Using https://eips.ethereum.org/EIPS/eip-1967 standard
     * Storage slot 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
     * (obtained as bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)).
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Get implementation address.
    function implementation() internal view returns (address impl) {
        assembly {
            // solium-disable-line
            impl := sload(_IMPLEMENTATION_SLOT)
        }
    }

    /// @dev Set new implementation address.
    function setImplementation(address codeAddress) internal {
        assembly {
            // solium-disable-line
            sstore(_IMPLEMENTATION_SLOT, codeAddress)
        }
    }
}

