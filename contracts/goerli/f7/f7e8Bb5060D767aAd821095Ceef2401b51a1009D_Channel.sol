// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

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
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import {FacetCut, LibDiamond, DiamondBase} from "contracts/shared/diamond/LibDiamond.sol";
import {Roles} from "contracts/shared/Schema.sol";
import {LibAccessControl} from "contracts/shared/utility/LibAccessControl.sol";
import {AppBase} from "./LibChannel.sol";
import {IChannel} from "./IChannel.sol";

struct DiamondArgs {
    address[] userAddresses;
    Roles[] memberRoles;
}

/**
 * @dev This is the base diamond contract that controls the Channel. It delegate calls all non-diamond functions to its various Facets
 */
contract Channel is AppBase, DiamondBase, IChannel {
    /**
     * @notice Initialization function. Should only be called by Channel Factory directly after contract is created
     * @dev Disabled after first use
     * @param _diamondCut List of Facet functions to add upon initialization
     * @param _args Initialization args such as initial members, etc.
     */
    function initialize(FacetCut[] memory _diamondCut, DiamondArgs memory _args)
        external
        override
        initializer
    {
        require(
            _args.userAddresses.length > 0 &&
                _args.userAddresses.length == _args.memberRoles.length,
            "Init Error: Addresses and Users invalid"
        );
        require(
            _args.memberRoles[0].roles[0] == 0x00,
            "Init Error: First user must be Admin"
        );

        LibDiamond.diamondCut(_diamondCut, address(0), new bytes(0));
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[bytes4(0x01ffc9a7)] = true; //type(IERC165).interfaceId
        ds.supportedInterfaces[bytes4(0x1f931c1c)] = true; //type(IDiamondCut).interfaceId
        ds.supportedInterfaces[bytes4(0x48e2b093)] = true; //type(IDiamondLoupe).interfaceId
        // Assumption made that TokenManager facet is included by default.
        ds.supportedInterfaces[bytes4(0x150b7a02)] = true; //type(IERC721Receiver).interfaceId
        ds.supportedInterfaces[bytes4(0x4e2312e0)] = true; //type(IERC1155Receiver).interfaceId

        s.masterfile = payable(msg.sender);

        // Set initial users
        for (uint256 i; i < _args.userAddresses.length; i++) {
            require(
                _args.userAddresses[i] != address(0),
                "Init Error: Zero Address can't be user"
            );

            // set roles
            for (uint256 j; j < _args.memberRoles[i].roles.length; j++) {
                LibAccessControl._grantRole(
                    _args.memberRoles[i].roles[j],
                    _args.userAddresses[i]
                );
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import {FacetCut} from "contracts/shared/diamond/LibDiamond.sol";
import {DiamondArgs} from "./Channel.sol";

interface IChannel {

    function initialize(FacetCut[] memory _diamondCut, DiamondArgs memory _args)
        external;
        
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {LibAccessControl} from "contracts/shared/utility/LibAccessControl.sol";
import {LibMeta} from "contracts/shared/utility/LibMeta.sol";

struct AppStorage {
    address payable masterfile;
    uint256 totalShares;
    uint256 divRate;
    mapping(address => mapping(address => uint256)) userReleased;
    mapping(address => uint256) totalReleased;
    mapping(address => uint256) totalFiller;
}

library LibApp {
    /**
     * @dev Calling this function give access to the state storage of the Channel
     * @dev Since the storage here is implemented at slot 0, any contract that inherits `AppBase` can access a state variable by calling s.xxx
     */
    function appStorage() internal pure returns (AppStorage storage state) {
        // bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            state.slot := 0
        }
    }
    /**
     * @dev Call this function to get masterfile address
     * @return _masterfile Masterfile address
     */
    function masterfile() internal view returns (address _masterfile) {
        return (appStorage().masterfile);
    }
}

/**
 * @title AppBase
 * @dev Base contract that Channel Facets inherit. Adds permissions and access to AppStorage
 */
contract AppBase {
    AppStorage internal s;

    /**
     * @notice Allows only users with `Role` role to call function
     */
    modifier onlyRole(bytes32 role) {
        LibAccessControl._checkRole(role, LibMeta.msgSender());
        _;
    }

    /**
     * @notice Allows only users who hold shares to call function
     */
    // modifier onlyShareholder() {
    //     Membership memory operator = s.members[LibMeta.msgSender()];
    //     require(
    //         operator.exsists && operator.shares > 0,
    //         "Management Error: Operator not shareholder"
    //     );
    //     _;
    // }

    modifier onlyMasterfile() {
        require(
            msg.sender == s.masterfile,
            "Channel Error: Function can only be called by Masterfile Protocol"
        );
        _;
    }
}

// uint256 constant NONCE_MASK =  uint256(uint128(~0)) << 128;
// uint256 constant INDEX_MASK = uint128(~0);
// uint256 constant TYPE_NF_BIT = 1 << 255;

// Apply index:
// id | INDEX_MASK;

// Get index from tokenid:
// id & INDEX_MASK;

// Get base token id from instance:
// id & NONCE_MASK;

// Apply base token id:
// id = (nonce << 128);

// Apply TYPE_NF_BIT: (TYPE_NF_BIT = 0; unencrypted, TYPE_NF_BIT = 1; encrypted)
// id | TYPE_NF_BIT;

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

struct Signature {
    bytes32 sigR;
    bytes32 sigS;
    uint8 sigV;
}

// Yoinked from Rarible: https://github.com/rariblecom/protocol-contracts/blob/master/royalties/contracts/LibPart.sol
struct Part {
    address payable account;
    uint96 value;
}

struct TokenDetail {
    string arweaveHash;
    uint256 maxQuantity;
    address payable royaltyRecipient;
    uint96 royaltyBps;
}

struct Roles {
    bytes32[] roles;
}

struct InitialSaleListing {
    address collection;
    uint256 startDate;
    uint256 endDate;
}

bytes32 constant ASSET_TYPEHASH = keccak256(
    "Asset(bytes4 assetClass,bytes4 assetStatus,address collection,uint256 tokenNonceOrId)"
);

bytes4 constant ERC20_ASSET_CLASS = bytes4(keccak256("ERC20"));
bytes4 constant ERC721_ASSET_CLASS = bytes4(keccak256("ERC721"));
bytes4 constant ERC1155_ASSET_CLASS = bytes4(keccak256("ERC1155"));
bytes4 constant FORGED_ASSET_STATUS = bytes4(keccak256("FORGED"));
bytes4 constant MINTED_ASSET_STATUS = bytes4(keccak256("MINTED"));

struct Asset {
    // assetClass Options:
    // - ERC721: bytes4(keccak256("ERC721"));
    // - ERC1155: bytes4(keccak256("ERC1155"));
    bytes4 assetClass;
    // assetStatus Options:
    // - Forged (Not yet minted): bytes4(keccak256("FORGED"));
    // - Minted: bytes4(keccak256("MINTED"));
    bytes4 assetStatus;
    // Address where token is deployed
    address collection;
    // If issued, this is tokenNonce
    // If minted, this is tokenId
    uint256 tokenNonceOrId;
}

bytes32 constant LISTING_TYPEHASH = keccak256(
    "Listing(bytes4 assetId,bytes4 listingType,uint256 startDate,uint256 endDate,uint256 quantity,uint256 initialPrice,address paymentToken)"
);

bytes32 constant LISTING_ID_TYPEHASH = keccak256(
    "ListingId(bytes4 assetId,address lister)"
);

bytes4 constant DIRECT_LISTING_TYPE = bytes4(keccak256("DIRECT"));

// Goal is to make this listing type as extensible as possible
// i.e. be able to be used for direct listings, auctions, etc.
struct Listing {
    // Hashed asset selector
    bytes8 assetId;
    // listingType Options:
    // - Direct (One asking price): bytes4(keccak256("DIRECT"));
    bytes4 listingType;
    uint256 startDate;
    uint256 endDate;
    // usually one except for initial listings. Also leaves options open for semi-fungible tokens in the future
    uint256 quantity;
    // Called initial price because it may act like a reserve (english auction), price to decrease from (dutch auction), or just unit price (direct listing)
    uint256 initialPrice;
    address paymentToken;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

// import { IDiamondCut } from "./IDiamondCut.sol";

enum FacetCutAction {
    Add,
    Replace,
    Remove
}

struct FacetCut {
    address facetAddress;
    FacetCutAction action;
    bytes4[] functionSelectors;
}

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndSelectorPosition {
        address facetAddress;
        uint16 selectorPosition;
    }

    struct DiamondStorage {
        // maps function selectors to the facets that execute the functions.
        // and maps the selectors to their position in the selectorSlots array.
        // func selector => address facet, selector position
        mapping(bytes4 => bytes32) facets;
        // array of slots of function selectors.
        // each slot holds 8 function selectors.
        mapping(uint256 => bytes32) selectorSlots;
        // The number of function selectors in selectorSlots
        uint16 selectorCount;
        // Used to query if a contract implements an interface.
        // Used to implement ERC-165.
        mapping(bytes4 => bool) supportedInterfaces;
        // If diamond has been initialized
        bool initialized;
    }

    function diamondStorage()
        internal
        pure
        returns (DiamondStorage storage ds)
    {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);

    bytes32 constant CLEAR_ADDRESS_MASK =
        bytes32(uint256(0xffffffffffffffffffffffff));
    bytes32 constant CLEAR_SELECTOR_MASK = bytes32(uint256(0xffffffff << 224));

    // Internal function version of diamondCut
    // This code is almost the same as the external diamondCut,
    // except it is using 'Facet[] memory _diamondCut' instead of
    // 'Facet[] calldata _diamondCut'.
    // The code is duplicated to prevent copying calldata to memory which
    // causes an error for a two dimensional array.
    function diamondCut(
        FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        DiamondStorage storage ds = diamondStorage();
        uint256 originalSelectorCount = ds.selectorCount;
        uint256 selectorCount = originalSelectorCount;
        bytes32 selectorSlot;
        // Check if last selector slot is not full
        if (selectorCount & 7 > 0) {
            // get last selectorSlot
            selectorSlot = ds.selectorSlots[selectorCount >> 3];
        }
        // loop through diamond cut
        for (
            uint256 facetIndex;
            facetIndex < _diamondCut.length;
            facetIndex++
        ) {
            (selectorCount, selectorSlot) = addReplaceRemoveFacetSelectors(
                selectorCount,
                selectorSlot,
                _diamondCut[facetIndex].facetAddress,
                _diamondCut[facetIndex].action,
                _diamondCut[facetIndex].functionSelectors
            );
        }
        if (selectorCount != originalSelectorCount) {
            ds.selectorCount = uint16(selectorCount);
        }
        // If last selector slot is not full
        if (selectorCount & 7 > 0) {
            ds.selectorSlots[selectorCount >> 3] = selectorSlot;
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    /**
     * @notice Add, Replace, Remove a Facet Selector from/to a Diamond
     * @param _selectorCount Number of selectors
     * @param _selectorSlot Slots of the selectors
     * @param _newFacetAddress New facet address of the selectors
     * @param _action Facet action Add | Replace | Remove
     * @param _selectors Selectors to add/replace/remove
     * @dev Returns _selectorCount and _selectorSlot
     */
    function addReplaceRemoveFacetSelectors(
        uint256 _selectorCount,
        bytes32 _selectorSlot,
        address _newFacetAddress,
        FacetCutAction _action,
        bytes4[] memory _selectors
    ) internal returns (uint256, bytes32) {
        DiamondStorage storage ds = diamondStorage();
        require(
            _selectors.length > 0,
            "LibDiamondCut: No selectors in facet to cut"
        );
        if (_action == FacetCutAction.Add) {
            enforceHasContractCode(
                _newFacetAddress,
                "LibDiamondCut: Add facet has no code"
            );
            for (
                uint256 selectorIndex;
                selectorIndex < _selectors.length;
                selectorIndex++
            ) {
                bytes4 selector = _selectors[selectorIndex];
                bytes32 oldFacet = ds.facets[selector];
                require(
                    address(bytes20(oldFacet)) == address(0),
                    "LibDiamondCut: Can't add function that already exists"
                );
                // add facet for selector
                ds.facets[selector] =
                    bytes20(_newFacetAddress) |
                    bytes32(_selectorCount);
                uint256 selectorInSlotPosition = (_selectorCount & 7) << 5;
                // clear selector position in slot and add selector
                _selectorSlot =
                    (_selectorSlot &
                        ~(CLEAR_SELECTOR_MASK >> selectorInSlotPosition)) |
                    (bytes32(selector) >> selectorInSlotPosition);
                // if slot is full then write it to storage
                if (selectorInSlotPosition == 224) {
                    ds.selectorSlots[_selectorCount >> 3] = _selectorSlot;
                    _selectorSlot = 0;
                }
                _selectorCount++;
            }
        } else if (_action == FacetCutAction.Replace) {
            enforceHasContractCode(
                _newFacetAddress,
                "LibDiamondCut: Replace facet has no code"
            );
            for (
                uint256 selectorIndex;
                selectorIndex < _selectors.length;
                selectorIndex++
            ) {
                bytes4 selector = _selectors[selectorIndex];
                bytes32 oldFacet = ds.facets[selector];
                address oldFacetAddress = address(bytes20(oldFacet));
                // only useful if immutable functions exist
                require(
                    oldFacetAddress != address(this),
                    "LibDiamondCut: Can't replace immutable function"
                );
                require(
                    oldFacetAddress != _newFacetAddress,
                    "LibDiamondCut: Can't replace function with same function"
                );
                require(
                    oldFacetAddress != address(0),
                    "LibDiamondCut: Can't replace function that doesn't exist"
                );
                // replace old facet address
                ds.facets[selector] =
                    (oldFacet & CLEAR_ADDRESS_MASK) |
                    bytes20(_newFacetAddress);
            }
        } else if (_action == FacetCutAction.Remove) {
            require(
                _newFacetAddress == address(0),
                "LibDiamondCut: Remove facet address must be address(0)"
            );
            uint256 selectorSlotCount = _selectorCount >> 3;
            uint256 selectorInSlotIndex = _selectorCount & 7;
            for (
                uint256 selectorIndex;
                selectorIndex < _selectors.length;
                selectorIndex++
            ) {
                if (_selectorSlot == 0) {
                    // get last selectorSlot
                    selectorSlotCount--;
                    _selectorSlot = ds.selectorSlots[selectorSlotCount];
                    selectorInSlotIndex = 7;
                } else {
                    selectorInSlotIndex--;
                }
                bytes4 lastSelector;
                uint256 oldSelectorsSlotCount;
                uint256 oldSelectorInSlotPosition;
                // adding a block here prevents stack too deep error
                {
                    bytes4 selector = _selectors[selectorIndex];
                    bytes32 oldFacet = ds.facets[selector];
                    require(
                        address(bytes20(oldFacet)) != address(0),
                        "LibDiamondCut: Can't remove function that doesn't exist"
                    );
                    // only useful if immutable functions exist
                    require(
                        address(bytes20(oldFacet)) != address(this),
                        "LibDiamondCut: Can't remove immutable function"
                    );
                    // replace selector with last selector in ds.facets
                    // gets the last selector
                    lastSelector = bytes4(
                        _selectorSlot << (selectorInSlotIndex << 5)
                    );
                    if (lastSelector != selector) {
                        // update last selector slot position info
                        ds.facets[lastSelector] =
                            (oldFacet & CLEAR_ADDRESS_MASK) |
                            bytes20(ds.facets[lastSelector]);
                    }
                    delete ds.facets[selector];
                    uint256 oldSelectorCount = uint16(uint256(oldFacet));
                    oldSelectorsSlotCount = oldSelectorCount >> 3;
                    oldSelectorInSlotPosition = (oldSelectorCount & 7) << 5;
                }
                if (oldSelectorsSlotCount != selectorSlotCount) {
                    bytes32 oldSelectorSlot = ds.selectorSlots[
                        oldSelectorsSlotCount
                    ];
                    // clears the selector we are deleting and puts the last selector in its place.
                    oldSelectorSlot =
                        (oldSelectorSlot &
                            ~(CLEAR_SELECTOR_MASK >>
                                oldSelectorInSlotPosition)) |
                        (bytes32(lastSelector) >> oldSelectorInSlotPosition);
                    // update storage with the modified slot
                    ds.selectorSlots[oldSelectorsSlotCount] = oldSelectorSlot;
                } else {
                    // clears the selector we are deleting and puts the last selector in its place.
                    _selectorSlot =
                        (_selectorSlot &
                            ~(CLEAR_SELECTOR_MASK >>
                                oldSelectorInSlotPosition)) |
                        (bytes32(lastSelector) >> oldSelectorInSlotPosition);
                }
                if (selectorInSlotIndex == 0) {
                    delete ds.selectorSlots[selectorSlotCount];
                    _selectorSlot = 0;
                }
            }
            _selectorCount = selectorSlotCount * 8 + selectorInSlotIndex;
        } else {
            revert("LibDiamondCut: Incorrect FacetCutAction");
        }
        return (_selectorCount, _selectorSlot);
    }

    /**
     * @notice Initialize a new diamond cut
     * @param _init Address of the contract or facet to execute _calldata
     * @param _calldata Data to delegateCall to the `_init` address
     */
    function initializeDiamondCut(address _init, bytes memory _calldata)
        internal
    {
        if (_init == address(0)) {
            require(
                _calldata.length == 0,
                "LibDiamondCut: _init is address(0) but_calldata is not empty"
            );
        } else {
            require(
                _calldata.length > 0,
                "LibDiamondCut: _calldata is empty but _init is not address(0)"
            );
            if (_init != address(this)) {
                enforceHasContractCode(
                    _init,
                    "LibDiamondCut: _init address has no code"
                );
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    // bubble up the error
                    revert(string(error));
                } else {
                    revert("LibDiamondCut: _init function reverted");
                }
            }
        }
    }
    /**
     * @notice Require the contract to have a code data
     * @param _contract Contract address
     * @param _errorMessage Custom Error message if code is not found
     */
    function enforceHasContractCode(
        address _contract,
        string memory _errorMessage
    ) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0 || _contract == address(this), _errorMessage);
    }
}

/**
 * @title DiamondBase
 */
contract DiamondBase {
    modifier initializer() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "DiamondError: Already initialize");
        ds.initialized = true;
        _;
    }

    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    /**
     * @notice all non-Diamond function calls are caught but this fallback and then, if it is an approved Facet function, delegated to that function. Context is always kept from this Contract address/memory
     */
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
        address facet = address(bytes20(ds.facets[msg.sig]));
        require(facet != address(0), "Diamond: Function does not exist");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import { LibMeta } from "./LibMeta.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

struct RoleData {
  mapping(address => bool) members;
  bytes32 adminRole;
}

struct AccessControlStorage {
  mapping(bytes32 => RoleData) _roles;
}

library LibAccessControl {
  bytes32 constant APP_STORAGE_POSITION =
    keccak256("masterfile.app.accessControl");

  event RoleAdminChanged(
    bytes32 indexed role,
    bytes32 indexed previousAdminRole,
    bytes32 indexed newAdminRole
  );
  event RoleGranted(
    bytes32 indexed role,
    address indexed account,
    address indexed sender
  );
  event RoleRevoked(
    bytes32 indexed role,
    address indexed account,
    address indexed sender
  );

  function accessControlStorage()
    internal
    pure
    returns (AccessControlStorage storage state)
  {
    bytes32 position = APP_STORAGE_POSITION;
    assembly {
      state.slot := position
    }
  }

  /**
   * @dev Returns `true` if `account` has been granted `role`.
   * @param role Hash of role's name
   * @param account Account to check if it has the role
   * @return doesHaveRole true if account has the role otherwise false
   */
  function _hasRole(bytes32 role, address account)
    internal
    view
    returns (bool)
  {
    return accessControlStorage()._roles[role].members[account];
  }

  /**
   * @dev Returns the admin role that controls `role`. See {grantRole} and
   * {revokeRole}.
   *
   * To change a role's admin, use {_setRoleAdmin}.
   *
   * @param role Hash of the role's name
   * @return admin 
   */
  function _getRoleAdmin(bytes32 role) internal view returns (bytes32) {
    return LibAccessControl.accessControlStorage()._roles[role].adminRole;
  }

  function _checkSenderRole(bytes32 role) internal view {
    _checkRole(role, LibMeta.msgSender());
  }

  /**
   * @dev Revert with a standard message if `account` is missing `role`.
   *
   * The format of the revert reason is given by the following regular expression:
   *
   *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
   */
  function _checkRole(bytes32 role, address account) internal view {
    if (!_hasRole(role, account)) {
      revert(
        string(
          abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(account), 20),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
          )
        )
      );
    }
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
  function _setupRole(bytes32 role, address account) internal {
    _grantRole(role, account);
  }

  /**
   * @dev Sets `adminRole` as ``role``'s admin role.
   *
   * Emits a {RoleAdminChanged} event.
   */
  function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
    emit RoleAdminChanged(role, _getRoleAdmin(role), adminRole);
    accessControlStorage()._roles[role].adminRole = adminRole;
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
   * @param role Hash of the role's name
   * @param account Account to be granted a role with
   */
  function _grantRole(bytes32 role, address account) internal {
    if (!_hasRole(role, account)) {
      accessControlStorage()._roles[role].members[account] = true;
      emit RoleGranted(role, account, LibMeta.msgSender());
    }
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
   * @param role Hash of the role's name
   * @param account Account to be renounced a role with
   */
  function _renounceRole(bytes32 role, address account) internal {
    require(
      account == LibMeta.msgSender(),
      "AccessControl: can only renounce roles for self"
    );
    _revokeRole(role, account);
  }

  /**
   * @dev Revokes `role` from `account`.
   *
   * If `account` had been granted `role`, emits a {RoleRevoked} event.
   *
   * Requirements:
   *
   * - the caller must have ``role``'s admin role.
   * @param role Hash of the role's name
   * @param account Account to be revoked a role with
   */
  function _revokeRole(bytes32 role, address account) internal {
    if (_hasRole(role, account)) {
      accessControlStorage()._roles[role].members[account] = false;
      emit RoleRevoked(role, account, LibMeta.msgSender());
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

struct MetaStorage {
  bytes32 domainSeparator;
  mapping(address => uint256) nonces; // Meta transaction nonces
}

library LibMeta {
  bytes32 constant APP_STORAGE_POSITION =
    keccak256("masterfile.app.metatransactions");
  bytes32 constant META_TRANSACTION_TYPEHASH =
    keccak256(
      bytes(
        "MetaTransaction(uint256 nonce,address from,bytes functionSignature)"
      )
    );

  function metaStorage() internal pure returns (MetaStorage storage state) {
    bytes32 position = APP_STORAGE_POSITION;
    assembly {
      state.slot := position
    }
  }

  function _getChainID() internal view returns (uint256) {
    uint256 id;
    assembly {
      id := chainid()
    }
    return id;
  }

  function _verify(
    address owner,
    uint256 nonce,
    uint256 chainID,
    bytes memory functionSignature,
    bytes32 sigR,
    bytes32 sigS,
    uint8 sigV
  ) internal view returns (bool) {
    bytes32 hash = prefixed(
      keccak256(abi.encodePacked(nonce, this, chainID, functionSignature))
    );
    address signer = ecrecover(hash, sigV, sigR, sigS);
    require(signer != address(0), "Invalid signature");
    return (owner == signer);
  }

  // Builds a prefixed hash to mimic the behavior of eth_sign.
  function prefixed(bytes32 hash) internal pure returns (bytes32) {
    return
      keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
  }

  function msgSender() internal view returns (address sender) {
    if (msg.sender == address(this)) {
      bytes memory array = msg.data;
      uint256 index = msg.data.length;
      assembly {
        // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
        sender := and(
          mload(add(array, index)),
          0xffffffffffffffffffffffffffffffffffffffff
        )
      }
    } else {
      return msg.sender;
    }
  }
}

