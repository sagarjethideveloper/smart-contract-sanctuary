// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ContextMixin} from "../common/ContextMixin.sol";
import {IMintableERC721} from "./root/IMintableERC721.sol";
import {IMintHelper} from "./IMintHelper.sol";

contract ParcelMinter is Ownable, ContextMixin {
    mapping(address => uint256) public epicMinters;
    mapping(address => uint256) public standardMinters;
    mapping(address => uint256) public mediumMinters;
    mapping(address => uint256) public giantMinters;
    mapping(address => uint256) public largeMinters;

    mapping(uint256 => bool) public isMinted;

    IMintableERC721 public netvrkMap;
    IMintHelper public mintHelper;

    event ParcelMinted(
        address indexed minter,
        uint256 tokenId,
        uint8 parcelType
    );

    constructor(address mapAddress, address helperAddress) {
        netvrkMap = IMintableERC721(mapAddress);
        mintHelper = IMintHelper(helperAddress);
    }

    function addEpicMinters(address[] calldata addr) external onlyOwner {
        for (uint256 i = 0; i < addr.length; i++) {
            epicMinters[addr[i]]++;
        }
    }

    function addStandardMinters(address[] calldata addr) external onlyOwner {
        for (uint256 i = 0; i < addr.length; i++) {
            standardMinters[addr[i]]++;
        }
    }

    function addMediumMinters(address[] calldata addr) external onlyOwner {
        for (uint256 i = 0; i < addr.length; i++) {
            mediumMinters[addr[i]]++;
        }
    }

    function addGiantMinters(address[] calldata addr) external onlyOwner {
        for (uint256 i = 0; i < addr.length; i++) {
            giantMinters[addr[i]]++;
        }
    }

    function addLargeMinters(address[] calldata addr) external onlyOwner {
        for (uint256 i = 0; i < addr.length; i++) {
            largeMinters[addr[i]]++;
        }
    }

    function setEpicMinters(address[] calldata addr, uint256[] calldata allowed)
        external
        onlyOwner
    {
        require(addr.length != allowed.length, "ParcelMinter: Error");

        for (uint256 i = 0; i < addr.length; i++) {
            epicMinters[addr[i]] = allowed[i];
        }
    }

    function addStandardMinters(
        address[] calldata addr,
        uint256[] calldata allowed
    ) external onlyOwner {
        require(addr.length != allowed.length, "ParcelMinter: Error");

        for (uint256 i = 0; i < addr.length; i++) {
            standardMinters[addr[i]] = allowed[i];
        }
    }

    function addMediumMinters(
        address[] calldata addr,
        uint256[] calldata allowed
    ) external onlyOwner {
        require(addr.length != allowed.length, "ParcelMinter: Error");

        for (uint256 i = 0; i < addr.length; i++) {
            mediumMinters[addr[i]] = allowed[i];
        }
    }

    function addGiantMinters(
        address[] calldata addr,
        uint256[] calldata allowed
    ) external onlyOwner {
        require(addr.length != allowed.length, "ParcelMinter: Error");

        for (uint256 i = 0; i < addr.length; i++) {
            giantMinters[addr[i]] = allowed[i];
        }
    }

    function addLargeMinters(
        address[] calldata addr,
        uint256[] calldata allowed
    ) external onlyOwner {
        require(addr.length == allowed.length, "ParcelMinter: Error");

        for (uint256 i = 0; i < addr.length; i++) {
            largeMinters[addr[i]] = allowed[i];
        }
    }

    function redeemParcels(uint256 tokenId) public {
        require(isMinted[tokenId] == false, "ParcelMinter: Already Minted");

        uint8 parcelType = mintHelper.getParcelType(tokenId);
        require(
            parcelType >= 1 && parcelType <= 5,
            "ParcelMinter: Invalid Parcel"
        );

        address minter = _msgSender();
        if (parcelType == 1) {
            require(epicMinters[minter] > 0, "ParcelMinter: Not Allowed");
            epicMinters[minter]--;
        } else if (parcelType == 2) {
            require(giantMinters[minter] > 0, "ParcelMinter: Not Allowed");
            giantMinters[minter]--;
        } else if (parcelType == 3) {
            require(largeMinters[minter] > 0, "ParcelMinter: Not Allowed");
            largeMinters[minter]--;
        } else if (parcelType == 4) {
            require(mediumMinters[minter] > 0, "ParcelMinter: Not Allowed");
            mediumMinters[minter]--;
        } else if (parcelType == 5) {
            require(standardMinters[minter] > 0, "ParcelMinter: Not Allowed");
            standardMinters[minter]--;
        }

        isMinted[tokenId] = true;

        netvrkMap.mint(minter, tokenId);
        emit ParcelMinted(minter, tokenId, parcelType);
    }

    function _updateAddresses(address mapAddress, address helperAddress)
        external
        onlyOwner
    {
        netvrkMap = IMintableERC721(mapAddress);
        mintHelper = IMintHelper(helperAddress);
    }

    function _msgSender()
        internal
        view
        override
        returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
    constructor () internal {
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.8.0;

abstract contract ContextMixin {
    function msgSender() internal view returns (address payable sender) {
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
            sender = msg.sender;
        }
        return sender;
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMintableERC721 is IERC721 {
    /**
     * @notice called by predicate contract to mint tokens while withdrawing
     * @dev Should be callable only by MintableERC721Predicate
     * Make sure minting is done only by this function
     * @param user user address for whom token is being minted
     * @param tokenId tokenId being minted
     */
    function mint(address user, uint256 tokenId) external;

    /**
     * @notice called by predicate contract to mint tokens while withdrawing with metadata from L2
     * @dev Should be callable only by MintableERC721Predicate
     * Make sure minting is only done either by this function/ �
     * @param user user address for whom token is being minted
     * @param tokenId tokenId being minted
     * @param metaData Associated token metadata, to be decoded & set using `setTokenMetadata`
     *
     * Note : If you're interested in taking token metadata from L2 to L1 during exit, you must
     * implement this method
     */
    function mint(
        address user,
        uint256 tokenId,
        bytes calldata metaData
    ) external;

    /**
     * @notice check if token already exists, return true if it does exist
     * @dev this check will be used by the predicate to determine if the token needs to be minted or transfered
     * @param tokenId tokenId being checked
     */
    function exists(uint256 tokenId) external view returns (bool);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.8.0;

interface IMintHelper {
    function getParcelType(uint256 tokenId) external returns (uint8);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "../../introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
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

pragma solidity >=0.6.0 <0.8.0;

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

