// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./abstract/HellGoverned.sol";

contract AuctionHouseIndexer is Initializable, UUPSUpgradeable, OwnableUpgradeable, HellGoverned {
    address public _auctionHouseAddress;
    //////////////////////////////////////////////////////////////////////////
    // Total Trusted token auctions
    uint public _totalTrustedTokenAuctions;
    // Holds the ids of the trusted Auctions ( index => auctionId )
    mapping(uint => uint) public _trustedTokenAuctions;
    //////////////////////////////////////////////////////////////////////////
    // Total auctions made for a specific token
    mapping(address => uint) public _totalTokenAuctions;
    // Auctions created for the specific token address (Token Address => index => auction.id);
    mapping(address => mapping(uint => uint)) public _tokenAuctions;
    //////////////////////////////////////////////////////////////////////////
    // Holds the number of auctions the user has created
    mapping(address => uint) public _userTotalAuctions;
    // Auctions created by the specified user ( User address => index => auction.id)
    mapping(address => mapping(uint => uint)) public _userAuctions;
    //////////////////////////////////////////////////////////////////////////
    // Holds the amount of auctions where the user has participated by making bids or buyouts
    // UserAddress => totalParticipatedAuctions
    mapping(address => uint) public _userTotalParticipatedAuctions;
    // Holds the auction ids of all the auctions where the user participated
    // UserAddress => index => AuctionId
    mapping(address => mapping(uint => uint)) public _userParticipatedAuctions;
    // Holds a boolean to let know if the user has participated on a specific auction
    mapping(address => mapping(uint => bool)) public _userParticipatedInAuction;
    //////////////////////////////////////////////////////////////////////////
    // Total Auctions by paying currency
    mapping(address => uint) public _totalPaidWithTokenAuctions;
    // Auctions sold for the specific token address (Token Address => index => auction.id);
    mapping(address => mapping(uint => uint)) public _paidWithTokenAuctions;
    ////////////////////////////////////////////////////////////////////////
    // Total Auctions won by User Address
    mapping(address => uint) public _userTotalAuctionsWon;
    // Holds a boolean to let know if the user won a specific Auction
    mapping(address => mapping(uint => bool)) public _userWonTheAuction;
    ////////////////////////////////////////////////////////////////////////
    // Total Auctions sold by User Address
    mapping(address => uint) public _userTotalAuctionsSold;
    // Holds a boolean to let know if the user managed to sell a specific Auction
    mapping(address => mapping(uint => bool)) public _userSoldAuction;
    ////////////////////////////////////////////////////////////////////
    // Public Views                                                 ////
    ////////////////////////////////////////////////////////////////////
    function getAuctionIdsCreatedByAddress(address creatorAddress, uint[] memory indexes) external view returns(uint[] memory) {
        // PAG: Exceeds pagination limit
        require(indexes.length <= _hellGovernmentContract._generalPaginationLimit(), "PAG");
        uint[] memory auctionIds = new uint[](indexes.length);
        for(uint i = 0; i < indexes.length; i++) {
            auctionIds[i] = _userAuctions[creatorAddress][indexes[i]];
        }
        return auctionIds;
    }

    function getAuctionIdsParticipatedByAddress(address participatingAddress, uint[] memory indexes) external view returns(uint[] memory) {
        // PAG: Exceeds pagination limit
        require(indexes.length <= _hellGovernmentContract._generalPaginationLimit(), "PAG");
        uint[] memory auctionIds = new uint[](indexes.length);
        for(uint i = 0; i < indexes.length; i++) {
            auctionIds[i] = _userParticipatedAuctions[participatingAddress][indexes[i]];
        }
        return auctionIds;
    }

    function getAuctionIdsByAuctionedTokenAddress(address auctionedTokenAddress, uint[] memory indexes) external view returns(uint[] memory) {
        // PAG: Exceeds pagination limit
        require(indexes.length <= _hellGovernmentContract._generalPaginationLimit(), "PAG");
        uint[] memory auctionIds = new uint[](indexes.length);
        for(uint i = 0; i < indexes.length; i++) {
            auctionIds[i] = _tokenAuctions[auctionedTokenAddress][indexes[i]];
        }
        return auctionIds;
    }

    function getAuctionIdsPaidWithTokenAddress(address paidWithTokenAddress, uint[] memory indexes) external view returns(uint[] memory) {
        // PAG: Exceeds pagination limit
        require(indexes.length <= _hellGovernmentContract._generalPaginationLimit(), "PAG");
        uint[] memory auctionIds = new uint[](indexes.length);
        for(uint i = 0; i < indexes.length; i++) {
            auctionIds[i] = _paidWithTokenAuctions[paidWithTokenAddress][indexes[i]];
        }
        return auctionIds;
    }

    function getTrustedAuctionIds(uint[] memory indexes) external view returns(uint[] memory) {
        // PAG: Exceeds pagination limit
        require(indexes.length <= _hellGovernmentContract._generalPaginationLimit(), "PAG");
        uint[] memory auctionIds = new uint[](indexes.length);
        for(uint i = 0; i < indexes.length; i++) {
            auctionIds[i] = _trustedTokenAuctions[indexes[i]];
        }
        return auctionIds;
    }

    struct AuctionHouseUserStats {
        uint totalCreatedAuctions;
        uint totalParticipatedAuctions;
        uint totalAuctionsSold;
        uint totalAuctionsWon;
    }

    function getUserStats(address userAddress) external view returns(AuctionHouseUserStats memory) {
        AuctionHouseUserStats memory stats;
        stats.totalCreatedAuctions = _userTotalAuctions[userAddress];
        stats.totalParticipatedAuctions = _userTotalParticipatedAuctions[userAddress];
        stats.totalAuctionsSold = _userTotalAuctionsSold[userAddress];
        stats.totalAuctionsWon = _userTotalAuctionsWon[userAddress];
        return stats;
    }

    ////////////////////////////////////////////////////////////////////
    // Only Auction House                                           ////
    ////////////////////////////////////////////////////////////////////
    modifier onlyAuctionHouse() {
        require(_auctionHouseAddress == msg.sender, "Forbidden");
        _;
    }

    function _registerNewAuctionCreation(uint auctionId, address creatorAddress, address auctionedTokenAddress, address paidWithTokenAddress) external onlyAuctionHouse returns(bool) {
        // Register the token auction Index
        _totalTokenAuctions[auctionedTokenAddress] += 1;
        _tokenAuctions[auctionedTokenAddress][_totalTokenAuctions[auctionedTokenAddress]] = auctionId;
        // Register the auctions sold for this token
        _totalPaidWithTokenAuctions[paidWithTokenAddress] += 1;
        _paidWithTokenAuctions[paidWithTokenAddress][_totalPaidWithTokenAuctions[paidWithTokenAddress]] = auctionId;
        // Register the AuctionIndex for the User
        _userTotalAuctions[creatorAddress] += 1;
        _userAuctions[creatorAddress][_userTotalAuctions[creatorAddress]] = auctionId;
        // If both tokens are trusted, this Auction will be stored on the list of trusted Auctions
        if(_hellGovernmentContract._tokenIsTrusted(auctionedTokenAddress) && _hellGovernmentContract._tokenIsTrusted(paidWithTokenAddress)) {
            _totalTrustedTokenAuctions += 1;
            _trustedTokenAuctions[_totalTrustedTokenAuctions] = auctionId;
        }
        return true;
    }

    function _registerUserParticipation(uint auctionId, address userAddress) onlyAuctionHouse external returns(bool){
        if (_userParticipatedInAuction[userAddress][auctionId] == false) {
            _userParticipatedInAuction[userAddress][auctionId] = true;
            _userTotalParticipatedAuctions[userAddress] += 1;
            _userParticipatedAuctions[userAddress][_userTotalParticipatedAuctions[userAddress]] = auctionId;
        }
        return true;
    }

    function _registerAuctionSold(uint auctionId, address creatorAddress) onlyAuctionHouse external returns(bool) {
        if(_userSoldAuction[creatorAddress][auctionId] == false) {
            _userSoldAuction[creatorAddress][auctionId] = true;
            _userTotalAuctionsSold[creatorAddress] += 1;
        }
        return true;
    }

    function _registerAuctionWon(uint auctionId, address winnerAddress) onlyAuctionHouse external returns(bool) {
        if(_userWonTheAuction[winnerAddress][auctionId] == false) {
            _userWonTheAuction[winnerAddress][auctionId] = true;
            _userTotalAuctionsWon[winnerAddress] += 1;
        }
        return true;
    }

    ////////////////////////////////////////////////////////////////////
    // Only Owner                                                   ////
    ////////////////////////////////////////////////////////////////////
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}
    function initialize(address hellGovernmentAddress, address auctionHouseAddress) initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _setHellGovernmentContract(hellGovernmentAddress);
        _setAuctionHouseContractAddress(auctionHouseAddress);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
    function _setAuctionHouseContractAddress(address contractAddress) public onlyOwner {
        _auctionHouseAddress = contractAddress;
        emit AuctionHouseContractAddressUpdated(contractAddress);
    }
    ////////////////////////////////////////////////////////////////////
    // Events                                                       ////
    ////////////////////////////////////////////////////////////////////
    event AuctionHouseContractAddressUpdated(address newAuctionHouseContractAddress);
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

import "../ERC1967/ERC1967UpgradeUpgradeable.sol";
import "./Initializable.sol";

/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
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
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable __self = address(this);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeTo(address newImplementation) external virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, new bytes(0), false);
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, data, true);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal override onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;
    uint256[50] private __gap;
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
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../HellGovernment.sol";


abstract contract HellGoverned is Initializable, OwnableUpgradeable {
    HellGovernment internal _hellGovernmentContract;

    function _setHellGovernmentContract(address hellGovernmentAddress) public onlyOwner {
        _hellGovernmentContract = HellGovernment(hellGovernmentAddress);
        emit HellGovernmentContractUpdated(hellGovernmentAddress);
    }

    event HellGovernmentContractUpdated(address newHellGovernmentAddress);
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
    function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallSecure(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
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
                abi.encodeWithSignature("upgradeTo(address)", oldImplementation)
            );
            rollbackTesting.value = false;
            // Check rollback was effective
            require(oldImplementation == _getImplementation(), "ERC1967Upgrade: upgrade breaks further upgrades");
            // Finally reset to the new implementation and log the upgrade
            _upgradeTo(newImplementation);
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
        require(AddressUpgradeable.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            AddressUpgradeable.isContract(IBeaconUpgradeable(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(
        address newBeacon,
        bytes memory data,
        bool forceCall
    ) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(IBeaconUpgradeable(newBeacon).implementation(), data);
        }
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function _functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
        require(AddressUpgradeable.isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return AddressUpgradeable.verifyCallResult(success, returndata, "Address: low-level delegate call failed");
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
        assembly {
            size := extcodesize(account)
        }
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

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
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
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
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
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
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
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

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
import "../proxy/utils/Initializable.sol";

/**
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
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract HellGovernment is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // General variables
    address payable public _hellTreasuryAddress;
    uint16 public _generalPaginationLimit;
    // Help us know if a specific token address was marked as trusted or not.
    mapping(address => bool) public _tokenIsTrusted;
    // Auction House variables
    uint16 public _auctionHouseTreasuryFee;
    uint public _minimumAuctionLength;
    uint public _maximumAuctionLength;
    // Greed Starter variables
    uint16 public _greedStarterTreasuryFee;
    uint public _minimumProjectLength;
    uint public _maximumProjectLength;
    ////////////////////////////////////////////////////////////////////
    // Only Owner                                                   ////
    ////////////////////////////////////////////////////////////////////
    function _authorizeUpgrade(address) internal override onlyOwner {}
    /////////////////////////////////////
    // General                      ////
    ////////////////////////////////////
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}
    function initialize(address payable treasuryAddress, uint16 auctionHouseFee, uint minimumAuctionLength, uint maximumAuctionLength, uint16 greedStarterFee, uint minimumProjectLength, uint maximumProjectLength) initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _generalPaginationLimit = 40;
        _setTreasuryAddress(treasuryAddress);
        // Initialize Auction House Variables
        _setAuctionHouseTreasuryFees(auctionHouseFee);
        _setMinimumAndMaximumAuctionLength(minimumAuctionLength, maximumAuctionLength);
        // Initialize Greed Starter Variables
        _setGreedStarterTreasuryFees(greedStarterFee);
        _setMinimumAndMaximumProjectLength(minimumProjectLength, maximumProjectLength);
        // By default the only trusted token will be the Network currency
        _tokenIsTrusted[address(0)] = true;
    }

    function _setTreasuryAddress(address payable treasuryAddress) public onlyOwner {
        _hellTreasuryAddress = treasuryAddress;
        emit TreasuryAddressUpdated(treasuryAddress);
    }

    function _setGeneralPaginationLimit(uint16 newPaginationLimit) public onlyOwner {
        _generalPaginationLimit = newPaginationLimit;
        emit GeneralPaginationLimitUpdated(newPaginationLimit);
    }

    function _setTokenTrust(address tokenAddress, bool isTrusted) external onlyOwner {
        _tokenIsTrusted[tokenAddress] = isTrusted;
        emit UpdatedTokenTrust(tokenAddress, isTrusted);
    }
    /////////////////////////////////////
    // Auction House                ////
    ////////////////////////////////////
    function _setMinimumAndMaximumAuctionLength(uint newMinimumLength, uint newMaximumLength) public onlyOwner {
        _minimumAuctionLength = newMinimumLength;
        _maximumAuctionLength = newMaximumLength;
        emit MinimumAndMaximumAuctionLengthUpdated(newMinimumLength, newMaximumLength);
    }

    function _setAuctionHouseTreasuryFees(uint16 newFee) public onlyOwner {
        _auctionHouseTreasuryFee = newFee;
        emit AuctionHouseTreasuryFeesUpdated(newFee);
    }
    /////////////////////////////////////
    // Greed Starter                ////
    ////////////////////////////////////
    function _setMinimumAndMaximumProjectLength(uint newMinimumLength, uint newMaximumLength) public onlyOwner {
        _minimumProjectLength = newMinimumLength;
        _maximumProjectLength = newMaximumLength;
        emit MinimumAndMaximumProjectLengthUpdated(newMinimumLength, newMaximumLength);
    }

    function _setGreedStarterTreasuryFees(uint16 newFee) public onlyOwner {
        _greedStarterTreasuryFee = newFee;
        emit GreedStarterTreasuryFeesUpdated(newFee);
    }
    ////////////////////////////////////////////////////////////////////
    // Events                                                       ////
    ////////////////////////////////////////////////////////////////////
    event TreasuryAddressUpdated(address indexed treasuryAddress);
    event GeneralPaginationLimitUpdated(uint16 newLimit);
    event UpdatedTokenTrust(address tokenAddress, bool isTrusted);
    // Auction House
    event AuctionHouseTreasuryFeesUpdated(uint16 newFee);
    event MinimumAndMaximumAuctionLengthUpdated(uint newMinimumLength, uint newMaximumLength);
    // Greed Starter
    event GreedStarterTreasuryFeesUpdated(uint16 newFee);
    event MinimumAndMaximumProjectLengthUpdated(uint newMinimumLength, uint newMaximumLength);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ReentrancyGuardUpgradeable is Initializable {
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

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

