// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.5;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./ParachainLightClient.sol";
import "./RewardSource.sol";

contract IncentivizedInboundChannel is AccessControl {
    uint64 public nonce;

    struct Message {
        address target;
        uint64 nonce;
        uint256 fee;
        bytes payload;
    }

    event MessageDispatched(uint64 nonce, bool result);

    uint256 public constant MAX_GAS_PER_MESSAGE = 100000;
    uint256 public constant GAS_BUFFER = 60000;

    // Governance contracts will administer using this role.
    bytes32 public constant CONFIG_UPDATE_ROLE =
        keccak256("CONFIG_UPDATE_ROLE");

    RewardSource private rewardSource;

    BeefyLightClient public beefyLightClient;

    constructor(BeefyLightClient _beefyLightClient) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        beefyLightClient = _beefyLightClient;
        nonce = 0;
    }

    // Once-off post-construction call to set initial configuration.
    function initialize(address _configUpdater, address _rewardSource)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Set initial configuration
        grantRole(CONFIG_UPDATE_ROLE, _configUpdater);
        rewardSource = RewardSource(_rewardSource);

        // drop admin privileges
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function submit(
        Message[] calldata _messages,
        ParachainLightClient.ParachainVerifyInput
            calldata _parachainVerifyInput,
        ParachainLightClient.BeefyMMRLeafPartial calldata _beefyMMRLeafPartial,
        uint256 _beefyMMRLeafIndex,
        uint256 _beefyMMRLeafCount,
        bytes32[] calldata _beefyMMRLeafProof
    ) public {
        // Proof
        // 1. Compute our parachain's message `commitment` by ABI encoding and hashing the `_messages`
        bytes32 commitment = keccak256(abi.encode(_messages));

        ParachainLightClient.verifyCommitmentInParachain(
            commitment,
            _parachainVerifyInput,
            _beefyMMRLeafPartial,
            _beefyMMRLeafIndex,
            _beefyMMRLeafCount,
            _beefyMMRLeafProof,
            beefyLightClient
        );

        // Require there is enough gas to play all messages
        require(
            gasleft() >= (_messages.length * MAX_GAS_PER_MESSAGE) + GAS_BUFFER,
            "insufficient gas for delivery of all messages"
        );

        processMessages(payable(msg.sender), _messages);
    }

    function processMessages(
        address payable _relayer,
        Message[] calldata _messages
    ) internal {
        uint256 _rewardAmount = 0;

        for (uint256 i = 0; i < _messages.length; i++) {
            // Check message nonce is correct and increment nonce for replay protection
            require(_messages[i].nonce == nonce + 1, "invalid nonce");

            nonce = nonce + 1;

            // Deliver the message to the target
            // Delivery will have fixed maximum gas allowed for the target app
            (bool success, ) = _messages[i].target.call{
                value: 0,
                gas: MAX_GAS_PER_MESSAGE
            }(_messages[i].payload);

            _rewardAmount = _rewardAmount + _messages[i].fee;
            emit MessageDispatched(_messages[i].nonce, success);
        }

        // reward the relayer
        rewardSource.reward(_relayer, _rewardAmount);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
import "../utils/Strings.sol";
import "../utils/introspection/ERC165.sol";

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControl {
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
abstract contract AccessControl is Context, IAccessControl, ERC165 {
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
        return interfaceId == type(IAccessControl).interfaceId
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
                Strings.toHexString(uint160(account), 20),
                " is missing role ",
                Strings.toHexString(uint256(role), 32)
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
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.5;

import "./BeefyLightClient.sol";
import "./utils/MerkleProof.sol";
import "./ScaleCodec.sol";

library ParachainLightClient {
    struct OwnParachainHead {
        bytes32 parentHash;
        uint32 number;
        bytes32 stateRoot;
        bytes32 extrinsicsRoot;
        bytes32 commitment;
    }

    struct ParachainHeadProof {
        uint256 pos;
        uint256 width;
        bytes32[] proof;
    }

    struct BeefyMMRLeafPartial {
        uint8 version;
        uint32 parentNumber;
        bytes32 parentHash;
        uint64 nextAuthoritySetId;
        uint32 nextAuthoritySetLen;
        bytes32 nextAuthoritySetRoot;
    }

    bytes4 public constant PARACHAIN_ID_SCALE = 0xe8030000;

    struct ParachainVerifyInput {
        bytes ownParachainHeadPrefixBytes;
        bytes ownParachainHeadSuffixBytes;
        ParachainHeadProof parachainHeadProof;
    }

    function verifyCommitmentInParachain(
        bytes32 commitment,
        ParachainVerifyInput calldata _parachainVerifyInput,
        BeefyMMRLeafPartial calldata _beefyMMRLeafPartial,
        uint256 _beefyMMRLeafIndex,
        uint256 _beefyMMRLeafCount,
        bytes32[] calldata _beefyMMRLeafProof,
        BeefyLightClient beefyLightClient
    ) internal {
        // 1. Compute our parachains merkle leaf by combining the parachain id, commitment data
        // and other misc bytes provided for the parachain header and hashing them.
        bytes32 ownParachainHeadHash = createParachainMerkleLeaf(
            _parachainVerifyInput.ownParachainHeadPrefixBytes,
            commitment,
            _parachainVerifyInput.ownParachainHeadSuffixBytes
        );

        // 2. Compute `parachainHeadsRoot` by verifying the merkle proof using `ownParachainHeadHash` and
        // `_parachainHeadsProof`
        bytes32 parachainHeadsRoot = MerkleProof.computeRootFromProofAtPosition(
            ownParachainHeadHash,
            _parachainVerifyInput.parachainHeadProof.pos,
            _parachainVerifyInput.parachainHeadProof.width,
            _parachainVerifyInput.parachainHeadProof.proof
        );

        // 3. Compute the `beefyMMRLeaf` using `parachainHeadsRoot` and `_beefyMMRLeafPartial`
        bytes32 beefyMMRLeaf = createMMRLeafHash(
            _beefyMMRLeafPartial,
            parachainHeadsRoot
        );

        // 4. Verify inclusion of the beefy MMR leaf in the beefy MMR root using that `beefyMMRLeaf` as well as
        // `_beefyMMRLeafIndex`, `_beefyMMRLeafCount` and `_beefyMMRLeafProof`
        require(
            beefyLightClient.verifyBeefyMerkleLeaf(
                beefyMMRLeaf,
                _beefyMMRLeafIndex,
                _beefyMMRLeafCount,
                _beefyMMRLeafProof
            ),
            "Invalid proof"
        );
    }

    function createParachainMerkleLeaf(
        bytes calldata _ownParachainHeadPrefixBytes,
        bytes32 commitment,
        bytes calldata _ownParachainHeadSuffixBytes
    ) public pure returns (bytes32) {
        bytes memory scaleEncodedParachainHead = bytes.concat(
            PARACHAIN_ID_SCALE,
            _ownParachainHeadPrefixBytes,
            commitment,
            _ownParachainHeadSuffixBytes
        );

        return keccak256(scaleEncodedParachainHead);
    }

    function createMMRLeafHash(
        BeefyMMRLeafPartial calldata leaf,
        bytes32 parachainHeadsRoot
    ) public pure returns (bytes32) {
        bytes memory scaleEncodedMMRLeaf = abi.encodePacked(
            ScaleCodec.encode8(leaf.version),
            ScaleCodec.encode32(leaf.parentNumber),
            leaf.parentHash,
            ScaleCodec.encode64(leaf.nextAuthoritySetId),
            ScaleCodec.encode32(leaf.nextAuthoritySetLen),
            leaf.nextAuthoritySetRoot,
            parachainHeadsRoot
        );

        return keccak256(scaleEncodedMMRLeaf);
    }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

// Something that can reward a relayer
interface RewardSource {
    function reward(address payable feePayer, uint256 _amount) external;
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

/**
 * @dev String operations.
 */
library Strings {
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

import "./IERC165.sol";

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
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
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
interface IERC165 {
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

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.5;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./utils/Bits.sol";
import "./utils/Bitfield.sol";
import "./ValidatorRegistry.sol";
import "./MMRVerification.sol";
import "./ScaleCodec.sol";

/**
 * @title A entry contract for the Ethereum light client
 */
contract BeefyLightClient {
    using Bits for uint256;
    using Bitfield for uint256[];
    using ScaleCodec for uint256;
    using ScaleCodec for uint64;
    using ScaleCodec for uint32;
    using ScaleCodec for uint16;

    /* Events */

    /**
     * @notice Notifies an observer that the prover's attempt at initital
     * verification was successful.
     * @dev Note that the prover must wait until `n` blocks have been mined
     * subsequent to the generation of this event before the 2nd tx can be sent
     * @param prover The address of the calling prover
     * @param blockNumber The blocknumber in which the initial validation
     * succeeded
     * @param id An identifier to provide disambiguation
     */
    event InitialVerificationSuccessful(
        address prover,
        uint256 blockNumber,
        uint256 id
    );

    /**
     * @notice Notifies an observer that the complete verification process has
     *  finished successfuly and the new commitmentHash will be accepted
     * @param prover The address of the successful prover
     * @param id the identifier used
     */
    event FinalVerificationSuccessful(address prover, uint256 id);

    event NewMMRRoot(bytes32 mmrRoot, uint64 blockNumber);

    /* Types */

    /**
     * The Commitment, with its payload, is the core thing we are trying to verify with
     * this contract. It contains a MMR root that commits to the polkadot history, including
     * past blocks and parachain blocks and can be used to verify both polkadot and parachain blocks.
     * @param payload the payload of the new commitment in beefy justifications (in
     * our case, this is a new MMR root for all past polkadot blocks)
     * @param blockNumber block number for the given commitment
     * @param validatorSetId validator set id that signed the given commitment
     */
    struct Commitment {
        bytes32 payload;
        uint64 blockNumber;
        uint32 validatorSetId;
    }

    /**
     * The ValidatorProof is a collection of proofs used to verify the signatures from the validators signing
     * each new justification.
     * @param signatures an array of signatures from the randomly chosen validators
     * @param positions an array of the positions of the randomly chosen validators
     * @param publicKeys an array of the public key of each signer
     * @param publicKeyMerkleProofs an array of merkle proofs from the chosen validators proving that their public
     * keys are in the validator set
     */
    struct ValidatorProof {
        bytes[] signatures;
        uint256[] positions;
        address[] publicKeys;
        bytes32[][] publicKeyMerkleProofs;
    }

    /**
     * The ValidationData is the set of data used to link each pair of initial and complete verification transactions.
     * @param senderAddress the sender of the initial transaction
     * @param commitmentHash the hash of the commitment they are claiming has been signed
     * @param validatorClaimsBitfield a bitfield signalling which validators they claim have signed
     * @param blockNumber the block number for this commitment
     */
    struct ValidationData {
        address senderAddress;
        bytes32 commitmentHash;
        uint256[] validatorClaimsBitfield;
        uint256 blockNumber;
    }

    /**
     * The BeefyMMRLeaf is the structure of each leaf in each MMR that each commitment's payload commits to.
     * @param version version of the leaf type
     * @param parentNumber parent number of the block this leaf describes
     * @param parentHash parent hash of the block this leaf describes
     * @param parachainHeadsRoot merkle root of all parachain headers in this block
     * @param nextAuthoritySetId validator set id that will be part of consensus for the next block
     * @param nextAuthoritySetLen length of that validator set
     * @param nextAuthoritySetRoot merkle root of all public keys in that validator set
     */
    struct BeefyMMRLeaf {
        uint8 version;
        uint32 parentNumber;
        bytes32 parentHash;
        bytes32 parachainHeadsRoot;
        uint64 nextAuthoritySetId;
        uint32 nextAuthoritySetLen;
        bytes32 nextAuthoritySetRoot;
    }

    /* State */

    ValidatorRegistry public validatorRegistry;
    MMRVerification public mmrVerification;
    uint256 public currentId;
    bytes32 public latestMMRRoot;
    uint64 public latestBeefyBlock;
    mapping(uint256 => ValidationData) public validationData;

    /* Constants */

    // THRESHOLD_NUMERATOR - numerator for percent of validator signatures required
    // THRESHOLD_DENOMINATOR - denominator for percent of validator signatures required
    uint256 public constant THRESHOLD_NUMERATOR = 3;
    uint256 public constant THRESHOLD_DENOMINATOR = 250;
    uint64 public constant BLOCK_WAIT_PERIOD = 3;

    // We must ensure at least one block is processed every session,
    // so these constants are checked to enforce a maximum gap between commitments.
    uint64 public constant NUMBER_OF_BLOCKS_PER_SESSION = 2400;
    uint64 public constant ERROR_AND_SAFETY_BUFFER = 10;
    uint64 public constant MAXIMUM_BLOCK_GAP =
        NUMBER_OF_BLOCKS_PER_SESSION - ERROR_AND_SAFETY_BUFFER;

    /**
     * @notice Deploys the BeefyLightClient contract
     * @param _validatorRegistry The contract to be used as the validator registry
     * @param _mmrVerification The contract to be used for MMR verification
     */
    constructor(
        ValidatorRegistry _validatorRegistry,
        MMRVerification _mmrVerification,
        uint64 _startingBeefyBlock
    ) {
        validatorRegistry = _validatorRegistry;
        mmrVerification = _mmrVerification;
        currentId = 0;
        latestBeefyBlock = _startingBeefyBlock;
    }

    /* Public Functions */

    /**
     * @notice Executed by the incoming channel in order to verify commitment
     * @param beefyMMRLeaf contains the merkle leaf to be verified
     * @param beefyMMRLeafIndex contains the merkle leaf index
     * @param beefyMMRLeafCount contains the merkle leaf count
     * @param beefyMMRLeafProof contains the merkle proof to verify against
     */
    function verifyBeefyMerkleLeaf(
        bytes32 beefyMMRLeaf,
        uint256 beefyMMRLeafIndex,
        uint256 beefyMMRLeafCount,
        bytes32[] calldata beefyMMRLeafProof
    ) external returns (bool) {
        return
            mmrVerification.verifyInclusionProof(
                latestMMRRoot,
                beefyMMRLeaf,
                beefyMMRLeafIndex,
                beefyMMRLeafCount,
                beefyMMRLeafProof
            );
    }

    /**
     * @notice Executed by the prover in order to begin the process of block
     * acceptance by the light client
     * @param commitmentHash contains the commitmentHash signed by the validator(s)
     * @param validatorClaimsBitfield a bitfield containing a membership status of each
     * validator who has claimed to have signed the commitmentHash
     * @param validatorSignature the signature of one validator
     * @param validatorPosition the position of the validator, index starting at 0
     * @param validatorPublicKey the public key of the validator
     * @param validatorPublicKeyMerkleProof proof required for validation of the public key in the validator merkle tree
     */
    function newSignatureCommitment(
        bytes32 commitmentHash,
        uint256[] memory validatorClaimsBitfield,
        bytes memory validatorSignature,
        uint256 validatorPosition,
        address validatorPublicKey,
        bytes32[] calldata validatorPublicKeyMerkleProof
    ) public payable {
        /**
         * @dev Check if validatorPublicKeyMerkleProof is valid based on ValidatorRegistry merkle root
         */
        require(
            validatorRegistry.checkValidatorInSet(
                validatorPublicKey,
                validatorPosition,
                validatorPublicKeyMerkleProof
            ),
            "Error: Sender must be in validator set at correct position"
        );

        /**
         * @dev Check if validatorSignature is correct, ie. check if it matches
         * the signature of senderPublicKey on the commitmentHash
         */
        require(
            ECDSA.recover(commitmentHash, validatorSignature) ==
                validatorPublicKey,
            "Error: Invalid Signature"
        );

        /**
         * @dev Check that the bitfield actually contains enough claims to be succesful, ie, >= 2/3
         */
        require(
            validatorClaimsBitfield.countSetBits() >=
                requiredNumberOfSignatures(),
            "Error: Bitfield not enough validators"
        );

        // Accept and save the commitment
        validationData[currentId] = ValidationData(
            msg.sender,
            commitmentHash,
            validatorClaimsBitfield,
            block.number
        );

        emit InitialVerificationSuccessful(msg.sender, block.number, currentId);

        currentId = currentId + 1;
    }

    function createRandomBitfield(uint256 id)
        public
        view
        returns (uint256[] memory)
    {
        ValidationData storage data = validationData[id];

        /**
         * @dev verify that block wait period has passed
         */
        require(
            block.number >= data.blockNumber + BLOCK_WAIT_PERIOD,
            "Error: Block wait period not over"
        );

        uint256 numberOfValidators = validatorRegistry.numOfValidators();

        return
            Bitfield.randomNBitsWithPriorCheck(
                getSeed(data),
                data.validatorClaimsBitfield,
                requiredNumberOfSignatures(numberOfValidators),
                numberOfValidators
            );
    }

    function createInitialBitfield(uint256[] calldata bitsToSet, uint256 length)
        public
        pure
        returns (uint256[] memory)
    {
        return Bitfield.createBitfield(bitsToSet, length);
    }

    /**
     * @notice Performs the second step in the validation logic
     * @param id an identifying value generated in the previous transaction
     * @param commitment contains the full commitment that was used for the commitmentHash
     * @param validatorProof a struct containing the data needed to verify all validator signatures
     */
    function completeSignatureCommitment(
        uint256 id,
        Commitment calldata commitment,
        ValidatorProof calldata validatorProof,
        BeefyMMRLeaf calldata latestMMRLeaf,
        uint64 leafIndex,
        uint64 leafCount,
        bytes32[] calldata mmrProofItems
    ) public {
        verifyCommitment(id, commitment, validatorProof);
        verifyNewestMMRLeaf(
            latestMMRLeaf,
            mmrProofItems,
            commitment.payload,
            leafIndex,
            leafCount
        );

        processPayload(commitment.payload, commitment.blockNumber);

        applyValidatorSetChanges(
            latestMMRLeaf.nextAuthoritySetId,
            latestMMRLeaf.nextAuthoritySetLen,
            latestMMRLeaf.nextAuthoritySetRoot
        );

        emit FinalVerificationSuccessful(msg.sender, id);

        /**
         * @dev We no longer need the data held in state, so delete it for a gas refund
         */
        delete validationData[id];
    }

    /* Private Functions */

    /**
     * @notice Deterministically generates a seed from the block hash at the block number of creation of the validation
     * data plus MAXIMUM_NUM_SIGNERS
     * @dev Note that `blockhash(blockNum)` will only work for the 256 most recent blocks. If
     * `completeSignatureCommitment` is called too late, a new call to `newSignatureCommitment` is necessary to reset
     * validation data's block number
     * @param data a storage reference to the validationData struct
     * @return onChainRandNums an array storing the random numbers generated inside this function
     */
    function getSeed(ValidationData storage data)
        private
        view
        returns (uint256)
    {
        // @note Get payload.blocknumber, add BLOCK_WAIT_PERIOD
        uint256 randomSeedBlockNum = data.blockNumber + BLOCK_WAIT_PERIOD;
        // @note Create a hash seed from the block number
        bytes32 randomSeedBlockHash = blockhash(randomSeedBlockNum);

        return uint256(randomSeedBlockHash);
    }

    function verifyNewestMMRLeaf(
        BeefyMMRLeaf calldata leaf,
        bytes32[] calldata proof,
        bytes32 root,
        uint64 leafIndex,
        uint64 leafCount
    ) public {
        bytes memory encodedLeaf = encodeMMRLeaf(leaf);
        bytes32 hashedLeaf = hashMMRLeaf(encodedLeaf);

        mmrVerification.verifyInclusionProof(
            root,
            hashedLeaf,
            leafIndex,
            leafCount,
            proof
        );
    }

    /**
     * @notice Perform some operation[s] using the payload
     * @param payload The payload variable passed in via the initial function
     */
    function processPayload(bytes32 payload, uint64 blockNumber) private {
        // Check that payload.leaf.block_number is > last_known_block_number;
        require(
            blockNumber > latestBeefyBlock,
            "Payload blocknumber is too old"
        );

        // Check that payload is within the current or next session
        // to ensure we get at least one payload each session
        require(
            blockNumber < latestBeefyBlock + MAXIMUM_BLOCK_GAP,
            "Payload blocknumber is too new"
        );

        latestMMRRoot = payload;
        latestBeefyBlock = blockNumber;
        emit NewMMRRoot(latestMMRRoot, blockNumber);
    }

    /**
     * @notice Check if the payload includes a new validator set,
     * and if it does then update the new validator set
     * @dev This function should call out to the validator registry contract
     * @param nextAuthoritySetId The id of the next authority set
     * @param nextAuthoritySetLen The number of validators in the next authority set
     * @param nextAuthoritySetRoot The merkle root of the merkle tree of the next validators
     */
    function applyValidatorSetChanges(
        uint64 nextAuthoritySetId,
        uint32 nextAuthoritySetLen,
        bytes32 nextAuthoritySetRoot
    ) internal {
        if (nextAuthoritySetId != validatorRegistry.id()) {
            validatorRegistry.update(
                nextAuthoritySetRoot,
                nextAuthoritySetLen,
                nextAuthoritySetId
            );
        }
    }

    function requiredNumberOfSignatures() public view returns (uint256) {
        return
            (validatorRegistry.numOfValidators() *
                THRESHOLD_NUMERATOR +
                THRESHOLD_DENOMINATOR -
                1) / THRESHOLD_DENOMINATOR;
    }

    function requiredNumberOfSignatures(uint256 numValidators)
        public
        pure
        returns (uint256)
    {
        return
            (numValidators * THRESHOLD_NUMERATOR + THRESHOLD_DENOMINATOR - 1) /
            THRESHOLD_DENOMINATOR;
    }

    function verifyCommitment(
        uint256 id,
        Commitment calldata commitment,
        ValidatorProof calldata proof
    ) internal view {
        ValidationData storage data = validationData[id];

        // Verify that sender is the same as in `newSignatureCommitment`
        require(
            msg.sender == data.senderAddress,
            "Error: Sender address does not match original validation data"
        );

        uint256 numberOfValidators = validatorRegistry.numOfValidators();
        uint256 requiredNumOfSignatures = requiredNumberOfSignatures(
            numberOfValidators
        );

        /**
         * @dev verify that block wait period has passed
         */
        require(
            block.number >= data.blockNumber + BLOCK_WAIT_PERIOD,
            "Error: Block wait period not over"
        );

        uint256[] memory randomBitfield = Bitfield.randomNBitsWithPriorCheck(
            getSeed(data),
            data.validatorClaimsBitfield,
            requiredNumOfSignatures,
            numberOfValidators
        );

        verifyValidatorProofLengths(requiredNumOfSignatures, proof);

        verifyValidatorProofSignatures(
            randomBitfield,
            proof,
            requiredNumOfSignatures,
            commitment
        );
    }

    function verifyValidatorProofLengths(
        uint256 requiredNumOfSignatures,
        ValidatorProof calldata proof
    ) internal pure {
        /**
         * @dev verify that required number of signatures, positions, public keys and merkle proofs are
         * submitted
         */
        require(
            proof.signatures.length == requiredNumOfSignatures,
            "Error: Number of signatures does not match required"
        );
        require(
            proof.positions.length == requiredNumOfSignatures,
            "Error: Number of validator positions does not match required"
        );
        require(
            proof.publicKeys.length == requiredNumOfSignatures,
            "Error: Number of validator public keys does not match required"
        );
        require(
            proof.publicKeyMerkleProofs.length == requiredNumOfSignatures,
            "Error: Number of validator public keys does not match required"
        );
    }

    function verifyValidatorProofSignatures(
        uint256[] memory randomBitfield,
        ValidatorProof calldata proof,
        uint256 requiredNumOfSignatures,
        Commitment calldata commitment
    ) internal view {
        // Encode and hash the commitment
        bytes32 commitmentHash = createCommitmentHash(commitment);

        /**
         *  @dev For each randomSignature, do:
         */
        for (uint256 i = 0; i < requiredNumOfSignatures; i++) {
            verifyValidatorSignature(
                randomBitfield,
                proof.signatures[i],
                proof.positions[i],
                proof.publicKeys[i],
                proof.publicKeyMerkleProofs[i],
                commitmentHash
            );
        }
    }

    function verifyValidatorSignature(
        uint256[] memory randomBitfield,
        bytes calldata signature,
        uint256 position,
        address publicKey,
        bytes32[] calldata publicKeyMerkleProof,
        bytes32 commitmentHash
    ) internal view {
        /**
         * @dev Check if validator in randomBitfield
         */
        require(
            randomBitfield.isSet(position),
            "Error: Validator must be once in bitfield"
        );

        /**
         * @dev Remove validator from randomBitfield such that no validator can appear twice in signatures
         */
        randomBitfield.clear(position);

        /**
         * @dev Check if merkle proof is valid
         */
        require(
            validatorRegistry.checkValidatorInSet(
                publicKey,
                position,
                publicKeyMerkleProof
            ),
            "Error: Validator must be in validator set at correct position"
        );

        /**
         * @dev Check if signature is correct
         */
        require(
            ECDSA.recover(commitmentHash, signature) == publicKey,
            "Error: Invalid Signature"
        );
    }

    function createCommitmentHash(Commitment calldata commitment)
        public
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    commitment.payload,
                    commitment.blockNumber.encode64(),
                    commitment.validatorSetId.encode32()
                )
            );
    }

    // To scale encode the byte array, we need to prefix it
    // with it's length. This is the expected current length of a leaf.
    // The length here is 113 bytes:
    // - 1 byte for the version
    // - 4 bytes for the block number
    // - 32 bytes for the block hash
    // - 8 bytes for the next validator set ID
    // - 4 bytes for the length of it
    // - 32 bytes for the root hash of it
    // - 32 bytes for the parachain heads merkle root
    // That number is then compact encoded unsigned integer - see SCALE spec
    bytes2 public constant MMR_LEAF_LENGTH_SCALE_ENCODED =
        bytes2(uint16(0xc501));

    function encodeMMRLeaf(BeefyMMRLeaf calldata leaf)
        public
        pure
        returns (bytes memory)
    {
        bytes memory scaleEncodedMMRLeaf = abi.encodePacked(
            ScaleCodec.encode8(leaf.version),
            ScaleCodec.encode32(leaf.parentNumber),
            leaf.parentHash,
            ScaleCodec.encode64(leaf.nextAuthoritySetId),
            ScaleCodec.encode32(leaf.nextAuthoritySetLen),
            leaf.nextAuthoritySetRoot,
            leaf.parachainHeadsRoot
        );

        return bytes.concat(MMR_LEAF_LENGTH_SCALE_ENCODED, scaleEncodedMMRLeaf);
    }

    function hashMMRLeaf(bytes memory leaf) public pure returns (bytes32) {
        return keccak256(leaf);
    }
}

// "SPDX-License-Identifier: Apache-2.0"
pragma solidity ^0.8.5;

library MerkleProof {
    /**
     * @notice Verify that a specific leaf element is part of the Merkle Tree at a specific position in the tree
     *
     * @param root the root of the merkle tree
     * @param leaf the leaf which needs to be proven
     * @param pos the position of the leaf, index starting with 0
     * @param width the width or number of leaves in the tree
     * @param proof the array of proofs to help verify the leaf's membership, ordered from leaf to root
     * @return a boolean value representing the success or failure of the operation
     */
    function verifyMerkleLeafAtPosition(
        bytes32 root,
        bytes32 leaf,
        uint256 pos,
        uint256 width,
        bytes32[] calldata proof
    ) public pure returns (bool) {
        bytes32 computedHash = computeRootFromProofAtPosition(
            leaf,
            pos,
            width,
            proof
        );

        return computedHash == root;
    }

    /**
     * @notice Compute the root of a MMR from a leaf and proof
     *
     * @param leaf the leaf we want to prove
     * @param proof an array of nodes to be hashed in order that they should be hashed
     * @param side an array of booleans signalling whether the corresponding node should be hashed on the left side or
     * the right side of the current hash
     */
    function computeRootFromProofAndSide(
        bytes32 leaf,
        bytes32[] calldata proof,
        bool[] calldata side
    ) public pure returns (bytes32) {
        bytes32 node = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            if (side[i]) {
                node = keccak256(abi.encodePacked(proof[i], node));
            } else {
                node = keccak256(abi.encodePacked(node, proof[i]));
            }
        }
        return node;
    }

    function computeRootFromProofAtPosition(
        bytes32 leaf,
        uint256 pos,
        uint256 width,
        bytes32[] calldata proof
    ) public pure returns (bytes32) {
        bytes32 computedHash = leaf;

        require(pos < width, "Merkle position is too high");

        uint256 i = 0;
        for (uint256 height = 0; width > 1; height++) {
            bool computedHashLeft = pos % 2 == 0;

            // check if at rightmost branch and whether the computedHash is left
            if (pos + 1 == width && computedHashLeft) {
                // there is no sibling and also no element in proofs, so we just go up one layer in the tree
                pos /= 2;
                width = ((width - 1) / 2) + 1;
                continue;
            }

            require(i < proof.length, "Merkle proof is too short");

            bytes32 proofElement = proof[i];

            if (computedHashLeft) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }

            pos /= 2;
            width = ((width - 1) / 2) + 1;
            i++;
        }

        return computedHash;
    }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.7.6;

library ScaleCodec {
    // Decodes a SCALE encoded uint256 by converting bytes (bid endian) to little endian format
    function decodeUint256(bytes memory data) public pure returns (uint256) {
        uint256 number;
        for (uint256 i = data.length; i > 0; i--) {
            number = number + uint256(uint8(data[i - 1])) * (2**(8 * (i - 1)));
        }
        return number;
    }

    // Decodes a SCALE encoded compact unsigned integer
    function decodeUintCompact(bytes memory data)
        public
        pure
        returns (uint256 v)
    {
        uint8 b = readByteAtIndex(data, 0); // read the first byte
        uint8 mode = b & 3; // bitwise operation

        if (mode == 0) {
            // [0, 63]
            return b >> 2; // right shift to remove mode bits
        } else if (mode == 1) {
            // [64, 16383]
            uint8 bb = readByteAtIndex(data, 1); // read the second byte
            uint64 r = bb; // convert to uint64
            r <<= 6; // multiply by * 2^6
            r += b >> 2; // right shift to remove mode bits
            return r;
        } else if (mode == 2) {
            // [16384, 1073741823]
            uint8 b2 = readByteAtIndex(data, 1); // read the next 3 bytes
            uint8 b3 = readByteAtIndex(data, 2);
            uint8 b4 = readByteAtIndex(data, 3);

            uint32 x1 = uint32(b) | (uint32(b2) << 8); // convert to little endian
            uint32 x2 = x1 | (uint32(b3) << 16);
            uint32 x3 = x2 | (uint32(b4) << 24);

            x3 >>= 2; // remove the last 2 mode bits
            return uint256(x3);
        } else if (mode == 3) {
            // [1073741824, 4503599627370496]
            uint8 l = b >> 2; // remove mode bits
            require(
                l > 32,
                "Not supported: number cannot be greater than 32 bytes"
            );
        } else {
            revert("Code should be unreachable");
        }
    }

    // Read a byte at a specific index and return it as type uint8
    function readByteAtIndex(bytes memory data, uint8 index)
        internal
        pure
        returns (uint8)
    {
        return uint8(data[index]);
    }

    // Sources:
    //   * https://ethereum.stackexchange.com/questions/15350/how-to-convert-an-bytes-to-address-in-solidity/50528
    //   * https://graphics.stanford.edu/~seander/bithacks.html#ReverseParallel

    function reverse256(uint256 input) internal pure returns (uint256 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);

        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
            ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }

    function reverse128(uint128 input) internal pure returns (uint128 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((v & 0x00000000FFFFFFFF00000000FFFFFFFF) << 32);

        // swap 8-byte long pairs
        v = (v >> 64) | (v << 64);
    }

    function reverse64(uint64 input) internal pure returns (uint64 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = (v >> 32) | (v << 32);
    }

    function reverse32(uint32 input) internal pure returns (uint32 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00) >> 8) |
            ((v & 0x00FF00FF) << 8);

        // swap 2-byte long pairs
        v = (v >> 16) | (v << 16);
    }

    function reverse16(uint16 input) internal pure returns (uint16 v) {
        v = input;

        // swap bytes
        v = (v >> 8) | (v << 8);
    }

    function encode256(uint256 input) public pure returns (bytes32) {
        return bytes32(reverse256(input));
    }

    function encode128(uint128 input) public pure returns (bytes16) {
        return bytes16(reverse128(input));
    }

    function encode64(uint64 input) public pure returns (bytes8) {
        return bytes8(reverse64(input));
    }

    function encode32(uint32 input) public pure returns (bytes4) {
        return bytes4(reverse32(input));
    }

    function encode16(uint16 input) public pure returns (bytes2) {
        return bytes2(reverse16(input));
    }

    function encode8(uint8 input) public pure returns (bytes1) {
        return bytes1(input);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Divide the signature in r, s and v variables
        bytes32 r;
        bytes32 s;
        uint8 v;

        // Check the signature length
        // - case 65: r,s,v signature (standard)
        // - case 64: r,vs signature (cf https://eips.ethereum.org/EIPS/eip-2098) _Available since v4.1._
        if (signature.length == 65) {
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            // solhint-disable-next-line no-inline-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
        } else if (signature.length == 64) {
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let vs := mload(add(signature, 0x40))
                r := mload(add(signature, 0x20))
                s := and(vs, 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                v := add(shr(255, vs), 27)
            }
        } else {
            revert("ECDSA: invalid signature length");
        }

        return recover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "ECDSA: invalid signature 's' value");
        require(v == 27 || v == 28, "ECDSA: invalid signature 'v' value");

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "ECDSA: invalid signature");

        return signer;
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from a `hash`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /**
     * @dev Returns an Ethereum Signed Typed Data, created from a
     * `domainSeparator` and a `structHash`. This produces hash corresponding
     * to the one signed with the
     * https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`]
     * JSON-RPC method as part of EIP-712.
     *
     * See {recover}.
     */
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

// SPDX-License-Identifier: Apache-2.0
// Code from https://github.com/ethereum/solidity-examples
pragma solidity >=0.7.6;
pragma experimental ABIEncoderV2;

library Bits {
    uint256 internal constant ONE = uint256(1);
    uint256 internal constant ONES = type(uint256).max;

    // Sets the bit at the given 'index' in 'self' to '1'.
    // Returns the modified value.
    function setBit(uint256 self, uint8 index) internal pure returns (uint256) {
        return self | (ONE << index);
    }

    // Sets the bit at the given 'index' in 'self' to '0'.
    // Returns the modified value.
    function clearBit(uint256 self, uint8 index)
        internal
        pure
        returns (uint256)
    {
        return self & ~(ONE << index);
    }

    // Sets the bit at the given 'index' in 'self' to:
    //  '1' - if the bit is '0'
    //  '0' - if the bit is '1'
    // Returns the modified value.
    function toggleBit(uint256 self, uint8 index)
        internal
        pure
        returns (uint256)
    {
        return self ^ (ONE << index);
    }

    // Get the value of the bit at the given 'index' in 'self'.
    function bit(uint256 self, uint8 index) internal pure returns (uint8) {
        return uint8((self >> index) & 1);
    }

    // Check if the bit at the given 'index' in 'self' is set.
    // Returns:
    //  'true' - if the value of the bit is '1'
    //  'false' - if the value of the bit is '0'
    function bitSet(uint256 self, uint8 index) internal pure returns (bool) {
        return (self >> index) & 1 == 1;
    }

    // Checks if the bit at the given 'index' in 'self' is equal to the corresponding
    // bit in 'other'.
    // Returns:
    //  'true' - if both bits are '0' or both bits are '1'
    //  'false' - otherwise
    function bitEqual(
        uint256 self,
        uint256 other,
        uint8 index
    ) internal pure returns (bool) {
        return ((self ^ other) >> index) & 1 == 0;
    }

    // Get the bitwise NOT of the bit at the given 'index' in 'self'.
    function bitNot(uint256 self, uint8 index) internal pure returns (uint8) {
        return uint8(1 - ((self >> index) & 1));
    }

    // Computes the bitwise AND of the bit at the given 'index' in 'self', and the
    // corresponding bit in 'other', and returns the value.
    function bitAnd(
        uint256 self,
        uint256 other,
        uint8 index
    ) internal pure returns (uint8) {
        return uint8(((self & other) >> index) & 1);
    }

    // Computes the bitwise OR of the bit at the given 'index' in 'self', and the
    // corresponding bit in 'other', and returns the value.
    function bitOr(
        uint256 self,
        uint256 other,
        uint8 index
    ) internal pure returns (uint8) {
        return uint8(((self | other) >> index) & 1);
    }

    // Computes the bitwise XOR of the bit at the given 'index' in 'self', and the
    // corresponding bit in 'other', and returns the value.
    function bitXor(
        uint256 self,
        uint256 other,
        uint8 index
    ) internal pure returns (uint8) {
        return uint8(((self ^ other) >> index) & 1);
    }

    // Gets 'numBits' consecutive bits from 'self', starting from the bit at 'startIndex'.
    // Returns the bits as a 'uint'.
    // Requires that:
    //  - '0 < numBits <= 256'
    //  - 'startIndex < 256'
    //  - 'numBits + startIndex <= 256'
    function bits(
        uint256 self,
        uint8 startIndex,
        uint16 numBits
    ) internal pure returns (uint256) {
        require(0 < numBits && startIndex < 256 && startIndex + numBits <= 256);
        return (self >> startIndex) & (ONES >> (256 - numBits));
    }

    // Computes the index of the highest bit set in 'self'.
    // Returns the highest bit set as an 'uint8'.
    // Requires that 'self != 0'.
    function highestBitSet(uint256 self) internal pure returns (uint8 highest) {
        require(self != 0);
        uint256 val = self;
        for (uint8 i = 128; i >= 1; i >>= 1) {
            if (val & (((ONE << i) - 1) << i) != 0) {
                highest += i;
                val >>= i;
            }
        }
    }

    // Computes the index of the lowest bit set in 'self'.
    // Returns the lowest bit set as an 'uint8'.
    // Requires that 'self != 0'.
    function lowestBitSet(uint256 self) internal pure returns (uint8 lowest) {
        require(self != 0);
        uint256 val = self;
        for (uint8 i = 128; i >= 1; i >>= 1) {
            if (val & ((ONE << i) - 1) == 0) {
                lowest += i;
                val >>= i;
            }
        }
    }
}

// "SPDX-License-Identifier: Apache-2.0"
pragma solidity ^0.8.5;

import "./Bits.sol";

library Bitfield {
    /**
     * @dev Constants used to efficiently calculate the hamming weight of a bitfield. See
     * https://en.wikipedia.org/wiki/Hamming_weight#Efficient_implementation for an explanation of those constants.
     */
    uint256 internal constant M1 =
        0x5555555555555555555555555555555555555555555555555555555555555555;
    uint256 internal constant M2 =
        0x3333333333333333333333333333333333333333333333333333333333333333;
    uint256 internal constant M4 =
        0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
    uint256 internal constant M8 =
        0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff;
    uint256 internal constant M16 =
        0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff;
    uint256 internal constant M32 =
        0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff;
    uint256 internal constant M64 =
        0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff;
    uint256 internal constant M128 =
        0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;

    uint256 internal constant ONE = uint256(1);
    using Bits for uint256;

    /**
     * @notice Draws a random number, derives an index in the bitfield, and sets the bit if it is in the `prior` and not
     * yet set. Repeats that `n` times.
     */
    function randomNBitsWithPriorCheck(
        uint256 seed,
        uint256[] memory prior,
        uint256 n,
        uint256 length
    ) public pure returns (uint256[] memory bitfield) {
        require(
            n <= countSetBits(prior),
            "`n` must be <= number of set bits in `prior`"
        );

        bitfield = new uint256[](prior.length);
        uint256 found = 0;

        for (uint256 i = 0; found < n; i++) {
            bytes32 randomness = keccak256(abi.encode(seed + i));
            uint256 index = uint256(randomness) % length;

            // require randomly seclected bit to be set in prior
            if (!isSet(prior, index)) {
                continue;
            }

            // require a not yet set (new) bit to be set
            if (isSet(bitfield, index)) {
                continue;
            }

            set(bitfield, index);

            found++;
        }

        return bitfield;
    }

    function createBitfield(uint256[] calldata bitsToSet, uint256 length)
        public
        pure
        returns (uint256[] memory bitfield)
    {
        // Calculate length of uint256 array based on rounding up to number of uint256 needed
        uint256 arrayLength = (length + 255) / 256;

        bitfield = new uint256[](arrayLength);

        for (uint256 i = 0; i < bitsToSet.length; i++) {
            set(bitfield, bitsToSet[i]);
        }

        return bitfield;
    }

    /**
     * @notice Calculates the number of set bits by using the hamming weight of the bitfield.
     * The alogrithm below is implemented after https://en.wikipedia.org/wiki/Hamming_weight#Efficient_implementation.
     * Further improvements are possible, see the article above.
     */
    function countSetBits(uint256[] memory self) public pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < self.length; i++) {
            uint256 x = self[i];

            x = (x & M1) + ((x >> 1) & M1); //put count of each  2 bits into those  2 bits
            x = (x & M2) + ((x >> 2) & M2); //put count of each  4 bits into those  4 bits
            x = (x & M4) + ((x >> 4) & M4); //put count of each  8 bits into those  8 bits
            x = (x & M8) + ((x >> 8) & M8); //put count of each 16 bits into those 16 bits
            x = (x & M16) + ((x >> 16) & M16); //put count of each 32 bits into those 32 bits
            x = (x & M32) + ((x >> 32) & M32); //put count of each 64 bits into those 64 bits
            x = (x & M64) + ((x >> 64) & M64); //put count of each 128 bits into those 128 bits
            x = (x & M128) + ((x >> 128) & M128); //put count of each 256 bits into those 256 bits
            count += x;
        }
        return count;
    }

    function isSet(uint256[] memory self, uint256 index)
        internal
        pure
        returns (bool)
    {
        uint256 element = index / 256;
        uint8 within = uint8(index % 256);
        return self[element].bit(within) == 1;
    }

    function set(uint256[] memory self, uint256 index) internal pure {
        uint256 element = index / 256;
        uint8 within = uint8(index % 256);
        self[element] = self[element].setBit(within);
    }

    function clear(uint256[] memory self, uint256 index) internal pure {
        uint256 element = index / 256;
        uint8 within = uint8(index % 256);
        self[element] = self[element].clearBit(within);
    }
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.5;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./utils/MerkleProof.sol";

/**
 * @title A contract storing state on the current validator set
 * @dev Stores the validator set as a Merkle root
 * @dev Inherits `Ownable` to ensure it can only be callable by the
 * instantiating contract account (which is the BeefyLightClient contract)
 */
contract ValidatorRegistry is Ownable {
    /* Events */

    event ValidatorRegistryUpdated(
        bytes32 root,
        uint256 numOfValidators,
        uint64 id
    );

    /* State */

    bytes32 public root;
    uint256 public numOfValidators;
    uint64 public id;

    /**
     * @notice Updates the validator registry and number of validators
     * @param _root The new root
     * @param _numOfValidators The new number of validators
     */
    function update(
        bytes32 _root,
        uint256 _numOfValidators,
        uint64 _id
    ) public onlyOwner {
        root = _root;
        numOfValidators = _numOfValidators;
        id = _id;
        emit ValidatorRegistryUpdated(_root, _numOfValidators, _id);
    }

    /**
     * @notice Checks if a validators address is a member of the merkle tree
     * @param addr The address of the validator to check
     * @param pos The position of the validator to check, index starting at 0
     * @param proof Merkle proof required for validation of the address
     * @return Returns true if the validator is in the set
     */
    function checkValidatorInSet(
        address addr,
        uint256 pos,
        bytes32[] memory proof
    ) public view returns (bool) {
        bytes32 hashedLeaf = keccak256(abi.encodePacked(addr));
        return
            MerkleProof.verifyMerkleLeafAtPosition(
                root,
                hashedLeaf,
                pos,
                numOfValidators,
                proof
            );
    }
}

// "SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.5;

/**
 * @dev MMRVerification library for MMR inclusion proofs generated
 *      by https://github.com/nervosnetwork/merkle-mountain-range.

 *                  Sample 7-leaf MMR:
 *
 *          Height 3 |      7
 *          Height 2 |   3      6     10
 *          Height 1 | 1  2   4  5   8  9    11
 *                   | |--|---|--|---|--|-----|-
 *      Leaf indexes | 0  1   2  3   4  5     6
 *
 *      General definitions:
 *      - Height:         the height of the tree.
 *      - Width:          the number of leaves in the tree.
 *      - Size:           the number of nodes in the tree.
 *      - Nodes:          an item in the tree. A node is a leaf or a parent. Nodes' positions are ordered from 1
 *                        to size in the order that they were added to the tree.
 *      - Leaf Index:     the leaf's location in an ordered array of all leaf nodes. Because Solidity interprets
 *                        0 as null, this MMR implementation internally converts leaf index to leaf position.
 *      - Parent Node:    leaf nodes are hashed together into parent nodes. To maintain the tree's structure,
 *                        parent nodes are hashed together until they form a mountain with a peak.
 *      - Mountain Peak:  the local root of a mountain; it has a greater height than other nodes in the mountain.
 *      - MMR root:       hashing each peak's hash together right-to-left gives the MMR root.
 *
 *      Our 7-leaf MMR has:
 *      - Height:          3
 *      - Size:            11
 *      - Nodes:          [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
 *      - Leaf Indexes:   [0, 1, 2, 3, 4, 5, 6] which correspond to nodes [1, 2, 4, 5, 8, 9, 11]
 *      - Parent Nodes:   [3, 6, 7, 10, 11]
 *      - Mountain peaks: [7, 10, 11]
 *      - MMR root:       hash(hash(11, 10), 7)
 */
contract MMRVerification {
    struct MountainData {
        uint256 position;
        bytes32 hash;
        uint256 height;
    }

    mapping(uint256 => MountainData) public queue;

    /**
     * @dev Verify an MMR inclusion proof for a leaf at a given index.
     */
    function verifyInclusionProof(
        bytes32 root,
        bytes32 leafNodeHash,
        uint256 leafIndex,
        uint256 leafCount,
        bytes32[] memory proofItems
    ) public returns (bool) {
        // Input index must be a leaf
        uint256 leafPos = leafIndexToPos(leafIndex);
        if (!isLeaf(leafPos)) {
            return false;
        }

        // Handle 1-leaf MMR
        if (leafCount == 1 && leafPos == 1 && leafNodeHash == root) {
            return true;
        }

        // Calculate the position of our leaf's mountain peak
        uint256 targetPeakPos;
        uint256 numLeftPeaks;
        uint256[] memory peakPositions = getPeakPositions(leafCount);
        for (uint256 i = 0; i < peakPositions.length; i++) {
            if (peakPositions[i] >= leafPos) {
                targetPeakPos = peakPositions[i];
                break;
            }
            numLeftPeaks++;
        }

        // Calculate our leaf's mountain peak hash
        bytes32 mountainHash =
            calculatePeakRoot(
                numLeftPeaks,
                leafNodeHash,
                leafPos,
                targetPeakPos,
                proofItems
            );

        // Bag peaks
        bytes32 bagger = mountainHash;

        // All right peaks are rolled up into one hash. If there are any, bag them.
        if (targetPeakPos < peakPositions[peakPositions.length - 1]) {
            bagger = keccak256(
                abi.encodePacked(proofItems[proofItems.length - 1], bagger)
            );
        }

        // Bag left peaks one-by-one
        for (uint256 i = numLeftPeaks; i > 0; i--) {
            bagger = keccak256(abi.encodePacked(bagger, proofItems[i - 1]));
        }

        return bagger == root;
    }

    /**
     * @dev Calculate a leaf's mountain peak based on it's hash, it's position,
     *      the mountain peak's position, and the proof contents.
     */
    function calculatePeakRoot(
        uint256 numLeftPeaks,
        bytes32 leafNodeHash,
        uint256 leafPos,
        uint256 peakPos,
        bytes32[] memory proofItems
    ) public returns (bytes32) {
        if (leafPos == peakPos) {
            return leafNodeHash;
        }
        uint256 proofItemsCounter = numLeftPeaks;
        uint256 qFront;
        uint256 qBack;

        MountainData memory mountainData =
            MountainData(leafPos, leafNodeHash, 1);
        queue[qBack] = mountainData;
        qBack = qBack + 1;

        while (qBack >= qFront) {
            MountainData memory mData = queue[qFront];
            uint256 pos = mData.position;

            // Calculate sibling and parent position
            uint256 siblingPos;
            uint256 parentPos;

            uint256 nextHeight = heightAt(pos + 1);
            uint256 sibOffset = siblingOffset(mData.height - 1);
            if (nextHeight > mData.height) {
                // Current position is right sibling
                siblingPos = pos - sibOffset;
                parentPos = pos + 1;
            } else {
                // Current position is left sibling
                siblingPos = pos + sibOffset;
                parentPos = pos + parentOffset(mData.height - 1);
            }

            // Sibling hash is either next in queue or next proof item
            bytes32 siblingHash;
            if (siblingPos == queue[qFront].position) {
                siblingHash = queue[qFront].hash;
            } else {
                siblingHash = proofItems[proofItemsCounter];
                proofItemsCounter = proofItemsCounter + 1;
            }

            // Calculate parent hash
            bytes32 parentHash;
            if (nextHeight > mData.height) {
                parentHash = keccak256(
                    abi.encodePacked(siblingHash, mData.hash)
                );
            } else {
                parentHash = keccak256(
                    abi.encodePacked(mData.hash, siblingHash)
                );
            }

            if (parentPos < peakPos) {
                // Parent is not the mountain peak
                queue[qBack] = MountainData(
                    parentPos,
                    parentHash,
                    mData.height + 1
                );
                qBack = qBack + 1;
            } else {
                // Parent is the peak
                delete (queue[qFront]);
                return parentHash;
            }

            // Move to next item in queue
            delete (queue[qFront]);
            qFront = qFront + 1;
        }
        revert();
    }

    /**
     * @dev It returns the height of the highest peak
     */
    function mountainHeight(uint256 size) public pure returns (uint8) {
        uint8 height = 1;
        while (uint256(1) << height <= size + height) {
            height++;
        }
        return height - 1;
    }

    /**
     * @dev It returns the height of the index
     */
    function heightAt(uint256 index) public pure returns (uint8 height) {
        uint256 reducedIndex = index;
        uint256 peakIndex;
        // If an index has a left mountain subtract the mountain
        while (reducedIndex > peakIndex) {
            reducedIndex -= (uint256(1) << height) - 1;
            height = mountainHeight(reducedIndex);
            peakIndex = (uint256(1) << height) - 1;
        }
        // Index is on the right slope
        height = height - uint8((peakIndex - reducedIndex));
    }

    /**
     * @dev It returns whether the index is the leaf node or not
     */
    function isLeaf(uint256 index) public pure returns (bool) {
        return heightAt(index) == 1;
    }

    /**
     * @dev It returns positions of all peaks
     */
    function getPeakPositions(uint256 width)
        public
        pure
        returns (uint256[] memory peakPositions)
    {
        peakPositions = new uint256[](numOfPeaks(width));
        uint256 count;
        uint256 size;
        for (uint256 i = 255; i > 0; i--) {
            if (width & (1 << (i - 1)) != 0) {
                // peak exists
                size = size + (1 << i) - 1;
                peakPositions[count++] = size;
            }
        }
        require(count == peakPositions.length, "Invalid bit calculation");
    }

    /**
     * @dev Return number of peaks from number of leaves
     */
    function numOfPeaks(uint256 numLeaves)
        public
        pure
        returns (uint256 numPeaks)
    {
        uint256 bits = numLeaves;
        while (bits > 0) {
            if (bits % 2 == 1) numPeaks++;
            bits = bits >> 1;
        }
        return numPeaks;
    }

    /**
     * @dev Return MMR size from number of leaves
     */
    function getSize(uint256 numLeaves) internal pure returns (uint256) {
        return (numLeaves << 1) - numOfPeaks(numLeaves);
    }

    /**
     * @dev Counts the number of 1s in the binary representation of an integer
     */
    function bitCount(uint256 n) internal pure returns (uint256) {
        uint256 count;
        while (n > 0) {
            count = count + 1;
            n = n & (n - 1);
        }
        return count;
    }

    /**
     * @dev Return position of leaf at given leaf index
     */
    function leafIndexToPos(uint256 index) internal pure returns (uint256) {
        return leafIndexToMmrSize(index) - trailingZeros(index + 1);
    }

    /**
     * @dev Return
     */
    function leafIndexToMmrSize(uint256 index) internal pure returns (uint256) {
        uint256 leavesCount = index + 1;
        uint256 peaksCount = bitCount(leavesCount);
        return (2 * leavesCount) - peaksCount;
    }

    /**
     * @dev Counts the number of trailing 0s in the binary representation of an integer
     */
    function trailingZeros(uint256 x) internal pure returns (uint256) {
        if (x == 0) return (32);
        uint256 n = 1;
        if ((x & 0x0000FFFF) == 0) {
            n = n + 16;
            x = x >> 16;
        }
        if ((x & 0x000000FF) == 0) {
            n = n + 8;
            x = x >> 8;
        }
        if ((x & 0x0000000F) == 0) {
            n = n + 4;
            x = x >> 4;
        }
        if ((x & 0x00000003) == 0) {
            n = n + 2;
            x = x >> 2;
        }
        return n - (x & 1);
    }

    /**
     * @dev Return parent offset at a given height
     */
    function parentOffset(uint256 height) internal pure returns (uint256 num) {
        return 2 << height;
    }

    /**
     * @dev Return sibling offset at a given height
     */
    function siblingOffset(uint256 height) internal pure returns (uint256 num) {
        return (2 << height) - 1;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
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
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
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
}

