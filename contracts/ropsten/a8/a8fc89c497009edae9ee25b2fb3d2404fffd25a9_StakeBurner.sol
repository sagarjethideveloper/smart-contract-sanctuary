// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';

import '../abstracts/Pausable.sol';
import '../abstracts/ExternallyCallable.sol';

import '../interfaces/IStakeBurner.sol';
import '../interfaces/IBpd.sol';
import '../interfaces/IToken.sol';
import '../interfaces/IAuction.sol';
import '../interfaces/IStakeToken.sol';
import '../interfaces/IStakeManager.sol';
import '../interfaces/IStakeCustodian.sol';
import '../interfaces/IStakingV1.sol';
import '../interfaces/IStakingV21.sol';

contract StakeBurner is IStakeBurner, Manageable, Migrateable, Pausable, ExternallyCallable {
    struct Settings {
        uint32 secondsInDay;
        uint32 lastSessionIdV2;
        uint32 lastSessionIdV1;
        uint32 bpdDayRange; //350 days, time of the first BPD
    }

    struct Contracts {
        IBpd bpd;
        IToken token;
        IAuction auction;
        IStakeToken stakeToken;
        IStakeManager stakeManager;
        IStakeCustodian stakeCustodian;
        IStakingV1 stakingV1;
        IStakingV21 stakingV2;
    }

    Settings internal settings;
    Contracts internal contracts;

    /** @dev unstake function
        Description: Unstake and burn NFT
        @param sessionId {uint256} - Id of stake
     */
    function burnStake(uint256 sessionId) external pausable {
        burnStakeInternal(sessionId, msg.sender);
    }

    /** @dev External Burn stake
        Description: Allow external to unstake
        @param sessionId {uint256}
        @param staker {address}

        Modifier: onlyExternalCaller, Pausable
     */
    function externalBurnStake(uint256 sessionId, address staker)
        external
        override
        onlyExternalCaller
        pausable
        returns (uint256)
    {
        return burnStakeInternal(sessionId, staker);
    }

    /** @dev Burn Stake Internal
        Description: Common functionality for unstaking
        @param sessionId {uint256}
        @param staker {address}
     */
    function burnStakeInternal(uint256 sessionId, address staker) internal returns (uint256) {
        require(
            contracts.stakeToken.isOwnerOf(staker, sessionId) ||
                contracts.stakeCustodian.isOwnerOf(staker, sessionId),
            'STAKE BURNER: Not owner of stake.'
        );

        (uint256 start, uint256 stakingDays, uint256 amount, uint256 shares, uint256 interest) =
            contracts.stakeManager.getStakeAndInterestById(sessionId);

        uint256 payout =
            handlePayoutAndPenalty(staker, interest, amount, start, stakingDays, shares);
        contracts.stakeManager.unsetStake(staker, sessionId, payout);

        return payout;
    }

    /** @dev Unstake Legacy
        Description: unstake function for layer1 stakes
        @param sessionId {uint256} - id of the layer 1 stake

        @return {uint256}
    */
    function unstakeLegacyStake(uint256 sessionId) external pausable returns (uint256) {
        return unstakeLegacyStakeInternal(sessionId, msg.sender, false);
    }

    /** @dev Unstake Legacy
        Description: unstake function for layer1 stakes
        @param sessionId {uint256} - id of the layer 1 stake
        @param staker {uint256} - Stake owner
        @param requireMature {bool} - ?

        @return {uint256}

        Modifiers: OnlyExternalCaller, Pauasable
    */
    function externalLegacyUnstake(
        uint256 sessionId,
        address staker,
        bool requireMature
    ) external override onlyExternalCaller pausable returns (uint256) {
        return unstakeLegacyStakeInternal(sessionId, staker, requireMature);
    }

    /** @dev Unstake Legacy
        Description: Internal functionality for unstake functions
        @param sessionId {uint256} - id of the layer 1 stake
        @param staker {uint256} - Stake owner
        @param requireMature {bool} - ?

        @return {uint256}

        Modifiers: OnlyExternalCaller, Pauasable
    */
    function unstakeLegacyStakeInternal(
        uint256 sessionId,
        address staker,
        bool requireMature
    ) internal returns (uint256) {
        require(sessionId <= settings.lastSessionIdV2, 'STAKE BURNER: invalid stakeId.');
        require(
            contracts.stakeManager.getStakeWithdrawnOrExists(sessionId) == false,
            'STAKE BURNER: stake is withdrawn or already v3.'
        );

        // first check if saved in v2
        (
            uint256 amount,
            uint256 start,
            uint256 end,
            uint256 shares,
            uint256 firstInterestDay,
            ,
            bool withdrawn,

        ) = contracts.stakingV2.sessionDataOf(staker, sessionId);

        if (shares != 0) {
            if (requireMature) {
                require(
                    end != 0 && end <= block.timestamp,
                    'STAKE BURNER: stake not mature or not set.'
                );
            }
            // if shares are not 0 it means it is v2 or has been upgraded and saved to v2

            require(withdrawn == false, 'STAKE BURNER: stake withdrawn on v2.');
        } else {
            require(sessionId <= settings.lastSessionIdV1, 'STAKE BURNER: invalid stakeId.');
            // otherwise check in v1 if valid v1 id
            (amount, start, end, shares, firstInterestDay) = contracts.stakingV1.sessionDataOf(
                staker,
                sessionId
            );

            if (requireMature) {
                require(
                    end != 0 && end <= block.timestamp,
                    'STAKE BURNER: stake not mature or not set.'
                );
            }

            require(shares != 0, 'STAKE BURNER: stake withdrawn on v1.');
        }

        uint256 stakingDays = (end - start) / settings.secondsInDay;

        uint256 interest =
            contracts.stakeManager.getStakeInterest(firstInterestDay, stakingDays, shares);

        uint256 payout =
            handlePayoutAndPenalty(staker, interest, amount, start, stakingDays, shares);

        contracts.stakeManager.unsetLegacyStake(
            staker,
            sessionId,
            shares,
            amount,
            start,
            firstInterestDay,
            stakingDays,
            payout
        );
        // Add to stake custodian as the v1 or v2 stake is now a v3 stake that has been withdrawn
        contracts.stakeCustodian.addStake(staker, sessionId);

        return payout;
    }

    /** @dev Get Payout and Penalty
        Description: calculate the amount the stake earned and any penalty because of early/late unstake
        @param amount {uint256} - amount of AXN staked
        @param start {uint256} - start date of the stake
        @param stakingDays {uint256}
        @param stakingInterest {uint256} - interest earned of the stake
    */
    function getPayoutAndPenaltyInternal(
        uint256 amount,
        uint256 start,
        uint256 stakingDays,
        uint256 stakingInterest
    ) internal view returns (uint256, uint256) {
        uint256 stakingSeconds = stakingDays * settings.secondsInDay;
        uint256 secondsStaked = block.timestamp - start;
        uint256 daysStaked = secondsStaked / settings.secondsInDay;
        uint256 amountAndInterest = amount + stakingInterest;

        // Early
        if (stakingDays > daysStaked) {
            uint256 payOutAmount = (amountAndInterest * secondsStaked) / stakingSeconds;

            uint256 earlyUnstakePenalty = amountAndInterest - payOutAmount;

            return (payOutAmount, earlyUnstakePenalty);
            // In time
        } else if (daysStaked < stakingDays + 14) {
            return (amountAndInterest, 0);
            // Late
        } else if (daysStaked < stakingDays + 714) {
            return (amountAndInterest, 0);
            /** Remove late penalties for now */

            // uint256 daysAfterStaking = daysStaked - stakingDays;

            // uint256 payOutAmount =
            //     amountAndInterest.mul(uint256(714).sub(daysAfterStaking)).div(
            //         700
            //     );

            // uint256 lateUnstakePenalty = amountAndInterest.sub(payOutAmount);

            // return (payOutAmount, lateUnstakePenalty);
        } else {
            return (0, amountAndInterest);
        }
    }

    /** @dev Handle Payout and Penalty
        Description: Generate payout and mint tokens to staker
        @param staker {address}
        @param interest {uint256}
        @param amount {uint256}
        @param start {uint256}
        @param stakingDays {uint256}
        @param shares {uint256}
     */
    function handlePayoutAndPenalty(
        address staker,
        uint256 interest,
        uint256 amount,
        uint256 start,
        uint256 stakingDays,
        uint256 shares
    ) internal returns (uint256) {
        if (stakingDays >= settings.bpdDayRange) {
            uint256 intendedEnd = start + (uint256(settings.secondsInDay) * stakingDays);

            interest += contracts.bpd.getBpdAmount(
                shares,
                start,
                block.timestamp < intendedEnd ? block.timestamp : intendedEnd
            );
        }

        (uint256 payout, uint256 penalty) =
            getPayoutAndPenaltyInternal(amount, start, stakingDays, interest);

        if (payout != 0) {
            contracts.token.mint(staker, payout);
        }

        if (penalty != 0) {
            contracts.auction.addTokensToNextAuction(penalty);
        }

        return payout;
    }

    /** Initialize ------------------------------------------------------------------ */
    function initialize(address _manager, address _migrator) external initializer {
        _setupRole(MANAGER_ROLE, _manager);
        _setupRole(MIGRATOR_ROLE, _migrator);
    }

    function init(
        address _bpd,
        address _token,
        address _auction,
        address _stakeToken,
        address _stakeReminter,
        address _stakeManager,
        address _stakeCustodian,
        address _stakingV1,
        address _stakingV2
    ) public onlyMigrator {
        _setupRole(EXTERNAL_CALLER_ROLE, _stakeReminter);

        contracts.bpd = IBpd(_bpd);
        contracts.token = IToken(_token);
        contracts.auction = IAuction(_auction);
        contracts.stakeToken = IStakeToken(_stakeToken);
        contracts.stakeManager = IStakeManager(_stakeManager);
        contracts.stakeCustodian = IStakeCustodian(_stakeCustodian);
        contracts.stakingV2 = IStakingV21(_stakingV2);
        contracts.stakingV1 = IStakingV1(_stakingV1);
    }

    function restore(
        uint32 _secondsInDay,
        uint32 _lastSessionIdV2,
        uint32 _lastSessionIdV1
    ) external onlyMigrator {
        settings.secondsInDay = _secondsInDay;
        settings.lastSessionIdV2 = _lastSessionIdV2;
        settings.lastSessionIdV1 = _lastSessionIdV1;
    }

    /** @dev Get Payout and Penalty 
        Description: Calls internal function, this will allow frontend to generate payout as well
        @param amount {uint256} - amount of AXN staked
        @param start {uint256} - start date of the stake
        @param stakingDays {uint256}
        @param stakingInterest {uint256} - interest earned of the stake
    */
    function getPayoutAndPenalty(
        uint256 amount,
        uint256 start,
        uint256 stakingDays,
        uint256 stakingInterest
    ) external view returns (uint256, uint256) {
        return getPayoutAndPenaltyInternal(amount, start, stakingDays, stakingInterest);
    }

    function getSettings() external view returns (Settings memory) {
        return settings;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library MathUpgradeable {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
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

pragma solidity >=0.8.0;

import "./Manageable.sol";
import "./Migrateable.sol";

abstract contract Pausable is Manageable, Migrateable {
    event SetPaused(bool paused);

    modifier pausable() {
        require(
            paused == false || hasRole(MIGRATOR_ROLE, msg.sender),
            'Function is paused'
        );
        _;
    }

    bool internal paused;

    function setPaused(bool _paused) external {
        require(
            hasRole(MIGRATOR_ROLE, msg.sender) ||
                hasRole(MANAGER_ROLE, msg.sender),
            'Caller must be manager or migrator'
        );

        paused = _paused;
        emit SetPaused(_paused);
    }

    function getPaused() external view returns (bool) {
        return paused;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract ExternallyCallable is AccessControlUpgradeable {
    bytes32 public constant EXTERNAL_CALLER_ROLE = keccak256('EXTERNAL_CALLER_ROLE');

    modifier onlyExternalCaller() {
        require(
            hasRole(EXTERNAL_CALLER_ROLE, msg.sender),
            'Caller is not allowed'
        );
        _;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IStakeBurner {
    function externalBurnStake(uint256 sessionId, address staker)
        external
        returns (uint256);

    function externalLegacyUnstake(
        uint256 sessionId,
        address staker,
        bool requireMature
    ) external returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IBpd {
    function addBpdShares(
        uint256 shares,
        uint256 start,
        uint256 stakingDays
    ) external;

    function addBpdMaxShares(
        uint256 oldShares,
        uint256 oldStart,
        uint256 oldEnd,
        uint256 newShares,
        uint256 newStart,
        uint256 newEnd
    ) external;

    function getBpdAmount(
        uint256 shares,
        uint256 start,
        uint256 end
    ) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';

interface IToken is IERC20Upgradeable {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

struct VentureToken {
    address coin; // address of token to buy from swap
    uint96 percentage; // % of token to buy NOTE: (On a VCA day all Venture tokens % should add up to 100%)
}

interface IAuction {
    function addTokensToNextAuction(uint256 amount) external;

    function getTodaysMode() external returns (uint256);

    function getTodaysTokens() external returns (VentureToken[] memory);

    function bid(
        address bidder,
        address ref,
        uint256 eth
    ) external returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';

interface IStakeToken is IERC721Upgradeable {
    function mint(address to, uint256 id) external;

    // function burn(address staker, uint id) external;

    function isOwnerOf(address account, uint256 tokenId) external returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '../enums/StakeStatus.sol';

struct StakeData1e18 {
    uint256 amount;
    uint256 shares;
    uint256 start;
    uint256 stakingDays;
    uint256 firstInterestDay;
    uint256 payout;
    StakeStatus status;
}

struct StakeUpgrade {
    uint256 id; // Id of stake
    address staker;
    uint256 firstInterestDay; // first day of divs
    uint256 shares; // # of shares owned for stake
    uint256 amount; // # amount of initial axn
    uint256 start; // Start Date in sconds
    uint256 stakingDays; // End date in seconds
}

interface IStakeManager {
    function createStake(
        address staker,
        uint256 amount,
        uint256 stakingDays
    ) external returns (uint256);

    function createExistingStake(
        uint256 id,
        uint256 amount,
        uint256 shares,
        uint256 start,
        uint256 end,
        uint256 firstInterestDay
    ) external;

    function upgradeExistingStake(uint256 id, address staker) external;

    function upgradeExistingLegacyStake(StakeUpgrade calldata stakeUpgrade) external;

    function unsetStake(
        address staker,
        uint256 id,
        uint256 payout
    ) external;

    function unsetLegacyStake(
        address staker,
        uint256 id,
        uint256 shares,
        uint256 amount,
        uint256 start,
        uint256 firstInterestDay,
        uint256 stakingDays,
        uint256 payout
    ) external;

    function getStake(uint256 id) external returns (StakeData1e18 memory);

    function getStakeEnd(uint256 id) external view returns (uint256);

    function getStakeShares(uint256 id) external view returns (uint256);

    function getStakeInterest(
        uint256 firstInterestDay,
        uint256 stakingDays,
        uint256 shares
    ) external view returns (uint256);

    function getStakeAndInterestById(uint256 stakeId)
        external
        view
        returns (
            uint256 start,
            uint256 stakingDays,
            uint256 amount,
            uint256 shares,
            uint256 interest
        );

    function getStakeWithdrawnOrExists(uint256 id) external view returns (bool);

    function getTotalVcaRegisteredShares() external view returns (uint256);

    function addTotalVcaRegisteredShares(uint256 shares) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IStakeCustodian {
    function addStake(address account, uint256 stakeId) external returns (bool);

    function removeStake(address account, uint256 stakeId) external returns (bool);

    function isOwnerOf(address account, uint256 stakeId) external view returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IStakingV1 {
    function sessionDataOf(address, uint256)
        external view returns (uint256, uint256, uint256, uint256, uint256);

    function sessionsOf_(address)
        external view returns (uint256[] memory);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IStakingV21 {
    function sessionDataOf(address staker, uint256 sessionId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        );

    function getTokenPricePerShare(address tokenAddress) external view returns (uint256);

    function getIsVCARegistered(address staker) external view returns (bool);

    function resolveTotalSharesOf(address account) external view returns (uint256);

    function getTotalSharesOf(address account) external view returns (uint256);

    function getDeductBalances(address account, address token) external view returns (uint256);

    function getDivTokens() external view returns (address[] memory);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract Manageable is AccessControlUpgradeable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    modifier onlyManager() {
        require(
            hasRole(MANAGER_ROLE, msg.sender),
            "Caller is not a manager"
        );
        _;
    }

    /** Roles management - only for multi sig address */
    function setupRole(bytes32 role, address account) external onlyManager {
        _setupRole(role, account);
    }

    function isManager(address account) external view returns (bool) {
        return hasRole(MANAGER_ROLE, account);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract Migrateable is AccessControlUpgradeable {
    bytes32 public constant MIGRATOR_ROLE = keccak256("MIGRATOR_ROLE");

    modifier onlyMigrator() {
        require(
            hasRole(MIGRATOR_ROLE, msg.sender),
            "Caller is not a migrator"
        );
        _;
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

import "../../utils/introspection/IERC165Upgradeable.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721Upgradeable is IERC165Upgradeable {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
      * @dev Safely transfers `tokenId` token from `from` to `to`.
      *
      * Requirements:
      *
      * - `from` cannot be the zero address.
      * - `to` cannot be the zero address.
      * - `tokenId` token must exist and be owned by `from`.
      * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
      * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
      *
      * Emits a {Transfer} event.
      */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

enum StakeStatus {Unknown, Withdrawn, Active}

