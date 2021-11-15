// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../Interfaces/ERC721.sol";
import "../Libraries/SignedMessage.sol";
import "../Libraries/Helpers.sol";

contract JPGRegistry is Ownable, SignedMessage, Helpers {
    using SafeCast for uint256;

    event CuratorAdded(address indexed curator);
    event CreateSubRegistry(address indexed curator, bytes32 name, string description);
    event UpdateSubRegistry(address indexed curator, bytes32 name, string description);
    event RemoveSubRegistry(address indexed curator, bytes32 name);
    event ReinstateSubRegistry(address indexed curator, bytes32 name);

    event TokensListed(OwnerBundle[] bundles);

    event AddNFTToSubRegistry(address indexed curator, bytes32 name, CuratedNFT token);
    event RemoveNFTFromSubRegistry(address indexed curator, bytes32 name, NFT token);

    event TokenListedForSale(NFT token, uint256 price, address curator, address owner);
    event TokenSold(NFT token, uint256 price, address buyer, address seller, address curator);

    // Maximum percentage fee, with 2 decimal points beyond 1%
    uint16 internal constant MAX_FEE_PERC = 10000;
    uint16 internal constant CURATOR_TAKE_PER_10000 = 200;

    struct NFT {
        address tokenContract;
        uint256 tokenId;
    }

    struct CuratedNFT {
        address tokenContract;
        uint256 tokenId;
        string note;
    }

    struct Listing {
        bytes signedMessage;
        NFT nft;
    }

    struct OwnerBundle {
        address owner;
        Listing[] listings;
    }

    struct ListingPrice {
        uint256 artistTake;
        uint256 curatorTake;
        uint256 sellerTake;
        uint256 sellPrice;
    }

    struct SubRegistry {
        bool created;
        bool removed;
        string description;
        mapping(address => mapping(uint256 => NFTData)) nfts;
    }

    struct NFTData {
        bool active;
        string note;
    }

    struct SubRegistries {
        uint16 feePercentage;
        bytes32[] registryNames;
        mapping(bytes32 => SubRegistry) subRegistry;
        mapping(address => mapping(uint256 => NFTData)) nfts;
    }

    // We use uint96, since we only support ETH, which 2**96 = 79228162514264337593543950336,
    // which is 79228162514.26434 ETH, which is a ridiculous amount of dollar value
    // this lets us squeeze this into a single slot
    struct InternalPrice {
        address curator;
        uint96 sellerTake;
    }

    mapping(address => bool) public curators;
    mapping(address => mapping(uint256 => bool)) public mainRegistry;
    mapping(address => SubRegistries) internal subRegistries;
    mapping(address => mapping(address => mapping(uint256 => InternalPrice))) internal priceList;
    mapping(address => uint256) internal balances;

    constructor() {
        curators[msg.sender] = true;
    }

    /**
     * @notice Public method to list non-fungible token(s) on the main registry
     * @dev permissionless listing from dApp - array of tokens (can be one). Will
     * ensure token is owned by caller.
     * @param tokens An array of NFT struct instances
     */
    function bulkAddToMainRegistry(NFT[] calldata tokens) public {
        NFT[] memory listedTokens = new NFT[](tokens.length);
        Listing[] memory bundleListings = new Listing[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            mainRegistry[tokens[i].tokenContract][tokens[i].tokenId] = true;
            listedTokens[i] = tokens[i];
            bundleListings[i] = Listing({signedMessage: bytes("0"), nft: tokens[i]});
        }

        OwnerBundle[] memory bundle = new OwnerBundle[](1);
        bundle[0] = OwnerBundle({listings: bundleListings, owner: address(msg.sender)});
        emit TokensListed(bundle);
    }

    /**
     * @notice Called by token owner to allow JPG Registry to sell an NFT on their behalf
     * in a fixed price sale with minimum price
     * @param token An instance of an NFT struct
     * @param price The minimum price the seller will acccept
     */
    function listForSale(
        NFT calldata token,
        uint96 price,
        address curator
    ) public {
        require(price > 0, "JPGR:lFS:Price cannot be 0");
        require(mainRegistry[token.tokenContract][token.tokenId], "JPGR:lFS:Token not registered");

        // TODO: should we check that the msg.sender owns this NFT?

        priceList[msg.sender][token.tokenContract][token.tokenId] = InternalPrice({
            sellerTake: price,
            curator: curator
        });

        emit TokenListedForSale(token, price, curator, msg.sender);
    }

    /**
     * TODO: this is perhaps not necessary if we wish to use a subgraph from event data.
     */
    function getPrice(
        bytes32 subRegistryName,
        NFT calldata token,
        address curator,
        address owner
    ) public view returns (ListingPrice memory) {
        require(mainRegistry[token.tokenContract][token.tokenId], "JPGR:gp:Token not registered");
        require(inSubRegistry(subRegistryName, token, curator), "JPGR:gp:Token not curated by curator");

        InternalPrice memory priceInternal = priceList[owner][token.tokenContract][token.tokenId];
        require(
            priceInternal.curator != address(0) && priceInternal.curator == curator,
            "JPGR:gp:Curator not approved seller"
        );

        uint256 sellerTake = priceInternal.sellerTake;

        require(sellerTake > 0, "JPGR:bfp:Owner price 0");

        uint256 curatorTake = calculateCuratorTake(sellerTake, curator);
        uint256 totalPrice = sellerTake + curatorTake;

        // TODO: artist royalties
        return ListingPrice({curatorTake: curatorTake, sellerTake: sellerTake, artistTake: 0, sellPrice: totalPrice});
    }

    /**
     * @notice Called publicly to purchase an NFT that has been approved for fixed price sale
     * @param token An instance of an NFT struct
     */
    function buyFixedPrice(
        bytes32 subRegistryName,
        NFT calldata token,
        address curator,
        address owner
    ) public payable {
        ListingPrice memory price = getPrice(subRegistryName, token, curator, owner);

        require(msg.value >= price.sellPrice, "JPGR:bfp:Price too low");

        ERC721(token.tokenContract).transferFrom(owner, msg.sender, token.tokenId);

        balances[owner] += price.sellerTake;
        balances[curator] += price.curatorTake;
        delete priceList[owner][token.tokenContract][token.tokenId];
        emit TokenSold(token, price.sellPrice, msg.sender, owner, curator);
    }

    /**
     * @notice Called publicly to check withdrawable balance for message sender
     */
    function checkBalance() public view returns (uint256) {
        return balances[msg.sender];
    }

    /**
     * @notice Called publicly to withdraw balance for message sender
     */
    function withdrawBalance() public payable {
        uint256 balance = balances[msg.sender];
        if (balance > 0) {
            balances[msg.sender] = 0;
            payable(msg.sender).transfer(balance);
        }
    }

    /**
     * @notice Called internally to determine payout for a fixed price sale
     * @param price The current owner of a Token
     * @param curator Curator whose exhibit the token was purchased throuh, can be null address
     */
    function calculateCuratorTake(uint256 price, address curator) internal view returns (uint256) {
        return (price * subRegistries[curator].feePercentage) / MAX_FEE_PERC;
    }

    /**
     * @notice Called publicly by token owner to remove from ProtocolRegistry
     * @param listing An instance of a Listing struct
     */
    function removeFromMainRegistry(Listing calldata listing) public {
        try ERC721(listing.nft.tokenContract).ownerOf(listing.nft.tokenId) returns (address owner) {
            if (owner == msg.sender) {
                _removeFromMainRegistry(NFT({tokenContract: listing.nft.tokenContract, tokenId: listing.nft.tokenId}));
            }
        } catch {} // solhint-disable-line no-empty-blocks
    }

    /**
     * @notice Create subregistry and add array of tokens
     * @param subRegistryName The name of the subregistry
     * @param subRegistryDescription The description of the subregistry
     * @param tokens Array of NFTs
     * @param notes Array of notes corresponding to NFTs
     */
    function createSubregistry(
        bytes32 subRegistryName,
        string calldata subRegistryDescription,
        NFT[] calldata tokens,
        string[] calldata notes
    ) public {
        require(curators[msg.sender], "JPGR:ats:Only allowed curators");
        require(!subRegistries[msg.sender].subRegistry[subRegistryName].created, "JPGR:ats:Subregistry exists");

        subRegistries[msg.sender].subRegistry[subRegistryName].created = true;
        subRegistries[msg.sender].registryNames.push(subRegistryName);
        subRegistries[msg.sender].subRegistry[subRegistryName].description = subRegistryDescription;
        emit CreateSubRegistry(msg.sender, subRegistryName, subRegistryDescription);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (mainRegistry[tokens[i].tokenContract][tokens[i].tokenId]) {
                mainRegistry[tokens[i].tokenContract][tokens[i].tokenId] = true;
            }
            subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokens[i].tokenContract][tokens[i].tokenId]
                .note = notes[i];
            subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokens[i].tokenContract][tokens[i].tokenId]
                .active = true;
            emit AddNFTToSubRegistry(
                msg.sender,
                subRegistryName,
                CuratedNFT({tokenContract: tokens[i].tokenContract, tokenId: tokens[i].tokenId, note: notes[i]})
            );
        }
    }

    /**
     * @notice Update existing subregistry
     * @param subRegistryName The name of the subregistry
     * @param subRegistryDescription The description of the subregistry
     * @param tokensToUpsert Array of NFTs to add/update
     * @param tokensToRemove Array of NFTs to remove
     * @param notes Array of notes corresponding to NFTs
     */
    function updateSubregistry(
        bytes32 subRegistryName,
        string calldata subRegistryDescription,
        NFT[] calldata tokensToUpsert,
        NFT[] calldata tokensToRemove,
        string[] calldata notes
    ) public {
        // Subregistry doesn't belong to msg.sender or hasn't been created
        require(subRegistries[msg.sender].subRegistry[subRegistryName].created, "JPGR:ats:Permission denied");
        require(tokensToUpsert.length == notes.length, "JPGR:ats:Mismatched array length");

        subRegistries[msg.sender].subRegistry[subRegistryName].description = subRegistryDescription;

        if (tokensToRemove.length > 0) {
            for (uint256 i = 0; i < tokensToRemove.length; i++) {
                delete subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokensToRemove[i].tokenContract][
                    tokensToRemove[i].tokenId
                ];
                emit RemoveNFTFromSubRegistry(msg.sender, subRegistryName, tokensToRemove[i]);
            }
        }

        if (tokensToUpsert.length > 0) {
            for (uint256 i = 0; i < tokensToUpsert.length; i++) {
                mainRegistry[tokensToUpsert[i].tokenContract][tokensToUpsert[i].tokenId] = true;

                subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokensToUpsert[i].tokenContract][
                    tokensToUpsert[i].tokenId
                ]
                    .note = notes[i];
                subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokensToUpsert[i].tokenContract][
                    tokensToUpsert[i].tokenId
                ]
                    .active = true;

                emit AddNFTToSubRegistry(
                    msg.sender,
                    subRegistryName,
                    CuratedNFT({
                        tokenContract: tokensToUpsert[i].tokenContract,
                        tokenId: tokensToUpsert[i].tokenId,
                        note: notes[i]
                    })
                );
            }
        }
        emit UpdateSubRegistry(msg.sender, subRegistryName, subRegistryDescription);
    }

    /**
     * @notice Add an array of tokens to a subregistry
     * @param subRegistryName The name of the subregistry
     * @param tokens Array of NFTs
     * @param notes Array of notes corresponding to NFTs
     */
    function addToSubregistry(
        bytes32 subRegistryName,
        NFT[] calldata tokens,
        string[] calldata notes
    ) public {
        // Subregistry doesn't belong to msg.sender or hasn't been created
        require(subRegistries[msg.sender].subRegistry[subRegistryName].created, "JPGR:ats:Permission denied");

        for (uint256 i = 0; i < tokens.length; i++) {
            if (mainRegistry[tokens[i].tokenContract][tokens[i].tokenId]) {
                mainRegistry[tokens[i].tokenContract][tokens[i].tokenId] = true;
            }
            subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokens[i].tokenContract][tokens[i].tokenId]
                .active = true;
            subRegistries[msg.sender].subRegistry[subRegistryName].nfts[tokens[i].tokenContract][tokens[i].tokenId]
                .note = notes[i];
            emit AddNFTToSubRegistry(
                msg.sender,
                subRegistryName,
                CuratedNFT({tokenContract: tokens[i].tokenContract, tokenId: tokens[i].tokenId, note: notes[i]})
            );
        }
    }

    /**
     * @notice Remove a subregistry by tagging it as removed
     * @dev Due to `delete` operation not deleting a mapping, we just set a flag
     * @param subRegistryName The name of the subregistry
     */
    function removeSubRegistry(bytes32 subRegistryName) public {
        require(curators[msg.sender], "JPGR:ats:Only allowed curators");
        subRegistries[msg.sender].subRegistry[subRegistryName].removed = true;
        emit RemoveSubRegistry(msg.sender, subRegistryName);
    }

    /**
     * @notice Reinstates a subregistry that was removed
     * @dev We never actually delete a subregistry, so we can trivially reinstate one's status
     * @param subRegistryName The name of the subregistry
     */
    function reinstateSubRegistry(bytes32 subRegistryName) public {
        require(curators[msg.sender], "JPGR:ats:Only allowed curators");
        subRegistries[msg.sender].subRegistry[subRegistryName].removed = false;
        emit ReinstateSubRegistry(msg.sender, subRegistryName);
    }

    /**
     * @notice Get all subregistries of a curator
     * @param curator Address of the curator
     */
    function getSubRegistries(address curator) public view returns (string[] memory) {
        bytes32[] memory registryNames = subRegistries[curator].registryNames;
        // get non-removed registry length
        uint256 ctr;
        for (uint256 i = 0; i < registryNames.length; i++) {
            if (subRegistries[curator].subRegistry[registryNames[i]].removed) {
                continue;
            }
            ctr += 1;
        }
        // create new array of length non-removed
        string[] memory registryStrings = new string[](ctr);
        ctr = 0;
        for (uint256 i = 0; i < registryNames.length; i++) {
            // add to array if non-removed
            if (subRegistries[curator].subRegistry[registryNames[i]].removed) {
                continue;
            }
            registryStrings[ctr] = Helpers.bytes32ToString(registryNames[i]);
            ctr += 1;
        }
        return registryStrings;
    }

    /**
     * @notice Called by a curator to remove from their subregistry
     * @param subRegistryName name of the subregistry to remove it from
     * @param token An instance of an NFT struct
     */
    function removeFromSubregistry(bytes32 subRegistryName, NFT calldata token) public {
        require(curators[msg.sender], "JPGR:rfs:Only allowed curators");
        subRegistries[msg.sender].subRegistry[subRegistryName].nfts[token.tokenContract][token.tokenId].active = false;
        emit RemoveNFTFromSubRegistry(msg.sender, subRegistryName, token);
    }

    /**
     * @notice Called publicly to determine if NFT is in curator subregistry
     * @param nft An instance of an NFT struct
     * @param curator Address of a curator
     */
    function inSubRegistry(
        bytes32 subRegistryName,
        NFT calldata nft,
        address curator
    ) public view returns (bool) {
        return
            mainRegistry[nft.tokenContract][nft.tokenId] &&
            !subRegistries[curator].subRegistry[subRegistryName].removed &&
            subRegistries[curator].subRegistry[subRegistryName].nfts[nft.tokenContract][nft.tokenId].active;
    }

    /**
     * @notice Called by contract owner admin to add a curator the the list of allowed curators
     * @param curator wallet address to add to allow-list of curators
     */
    function allowCurator(address curator) public onlyOwner {
        curators[curator] = true;
        subRegistries[curator].feePercentage = CURATOR_TAKE_PER_10000;
        emit CuratorAdded(curator);
    }

    /**
     * @notice Public function for curator to set their curation fee as a whole number
     * percentage added to the owner list price.
     * @param feePercentage Fee percentage, with a base of 10000 == 100%
     */
    function setCuratorFee(uint16 feePercentage, address curator) public onlyOwner {
        require(curators[curator], "JPGR:scf:Curator only");
        require(feePercentage <= MAX_FEE_PERC, "JPGR:scf:Fee exceeds MAX_FEE");
        subRegistries[curator].feePercentage = feePercentage;
    }

    /**
     * @notice Called by contract owner admin to bulk add NFTs to ProtocolRegistry
     * @dev This saves listers gas by keeping things off-chain until a bulk add task is run
     * @param ownerBundles[] An array of OwnerBundle struct instances
     */
    function adminBulkAddToMainRegistry(OwnerBundle[] memory ownerBundles) public onlyOwner {
        for (uint256 j = 0; j < ownerBundles.length; j++) {
            Listing[] memory listings = ownerBundles[j].listings;

            for (uint256 i = 0; i < listings.length; i++) {
                try ERC721(listings[i].nft.tokenContract).ownerOf(listings[i].nft.tokenId) returns (address owner) {
                    address signer =
                        SignedMessage.getSigner(
                            listings[i].nft.tokenContract,
                            listings[i].nft.tokenId,
                            listings[i].signedMessage
                        );

                    if (owner == signer) {
                        mainRegistry[listings[i].nft.tokenContract][listings[i].nft.tokenId] = true;
                    } else {
                        delete ownerBundles[j].listings[i];
                    }
                } catch {
                    delete ownerBundles[j].listings[i];
                }
            }
        }

        emit TokensListed(ownerBundles);
    }

    /**
     * @notice Called by contract owner admin to bulk remove NFTs from ProtocolRegistry
     * @param tokens[] An array of NFT struct instances
     */
    function bulkRemoveFromMainRegistry(NFT[] calldata tokens) public onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            _removeFromMainRegistry(tokens[i]);
        }
    }

    /**
     * @notice Called internally to remove from ProtocolRegistry
     * @param token An instance of an NFT struct
     */
    function _removeFromMainRegistry(NFT memory token) internal {
        mainRegistry[token.tokenContract][token.tokenId] = false;
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Wrappers over Solidity's uintXX/intXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} and {SignedSafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and `int256` and then downcasting.
 */
library SafeCast {
    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value < 2**128, "SafeCast: value doesn\'t fit in 128 bits");
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value < 2**64, "SafeCast: value doesn\'t fit in 64 bits");
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value < 2**32, "SafeCast: value doesn\'t fit in 32 bits");
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value < 2**16, "SafeCast: value doesn\'t fit in 16 bits");
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits.
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value < 2**8, "SafeCast: value doesn\'t fit in 8 bits");
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v3.1._
     */
    function toInt128(int256 value) internal pure returns (int128) {
        require(value >= -2**127 && value < 2**127, "SafeCast: value doesn\'t fit in 128 bits");
        return int128(value);
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v3.1._
     */
    function toInt64(int256 value) internal pure returns (int64) {
        require(value >= -2**63 && value < 2**63, "SafeCast: value doesn\'t fit in 64 bits");
        return int64(value);
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v3.1._
     */
    function toInt32(int256 value) internal pure returns (int32) {
        require(value >= -2**31 && value < 2**31, "SafeCast: value doesn\'t fit in 32 bits");
        return int32(value);
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v3.1._
     */
    function toInt16(int256 value) internal pure returns (int16) {
        require(value >= -2**15 && value < 2**15, "SafeCast: value doesn\'t fit in 16 bits");
        return int16(value);
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits.
     *
     * _Available since v3.1._
     */
    function toInt8(int256 value) internal pure returns (int8) {
        require(value >= -2**7 && value < 2**7, "SafeCast: value doesn\'t fit in 8 bits");
        return int8(value);
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        require(value < 2**255, "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }
}

// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity >=0.8.0 <0.9.0;

interface ERC721 {
    /// @dev This emits when ownership of any NFT changes by any mechanism.
    ///  This event emits when NFTs are created (`from` == 0) and destroyed
    ///  (`to` == 0). Exception: during contract creation, any number of NFTs
    ///  may be created and assigned without emitting Transfer. At the time of
    ///  any transfer, the approved address for that NFT (if any) is reset to none.
    event Transfer(address indexed _from, address indexed _to, uint256 indexed _tokenId);

    /// @dev This emits when the approved address for an NFT is changed or
    ///  reaffirmed. The zero address indicates there is no approved address.
    ///  When a Transfer event emits, this also indicates that the approved
    ///  address for that NFT (if any) is reset to none.
    event Approval(address indexed _owner, address indexed _approved, uint256 indexed _tokenId);

    /// @dev This emits when an operator is enabled or disabled for an owner.
    ///  The operator can manage all NFTs of the owner.
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

    /// @notice Count all NFTs assigned to an owner
    /// @dev NFTs assigned to the zero address are considered invalid, and this
    ///  function throws for queries about the zero address.
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) external view returns (uint256);

    /// @notice Find the owner of an NFT
    /// @dev NFTs assigned to zero address are considered invalid, and queries
    ///  about them do throw.
    /// @param _tokenId The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 _tokenId) external view returns (address);

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT. When transfer is complete, this function
    ///  checks if `_to` is a smart contract (code size > 0). If so, it calls
    ///  `onERC721Received` on `_to` and throws if the return value is not
    ///  `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    /// @param data Additional data with no specified format, sent in call to `_to`
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes calldata data
    ) external payable;

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev This works identically to the other function with an extra data parameter,
    ///  except this function just sets data to "".
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable;

    /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
    ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
    ///  THEY MAY BE PERMANENTLY LOST
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable;

    /// @notice Change or reaffirm the approved address for an NFT
    /// @dev The zero address indicates there is no approved address.
    ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
    ///  operator of the current owner.
    /// @param _approved The new approved NFT controller
    /// @param _tokenId The NFT to approve
    function approve(address _approved, uint256 _tokenId) external payable;

    /// @notice Enable or disable approval for a third party ("operator") to manage
    ///  all of `msg.sender`'s assets
    /// @dev Emits the ApprovalForAll event. The contract MUST allow
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved) external;

    /// @notice Get the approved address for a single NFT
    /// @dev Throws if `_tokenId` is not a valid NFT.
    /// @param _tokenId The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 _tokenId) external view returns (address);

    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract SignedMessage {
    function getMessageHash(address _tokenContract, uint256 _tokenId) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_tokenContract, _tokenId, address(this)));
    }

    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns (bytes32) {
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function getSigner(
        address _tokenContract,
        uint256 _tokenId,
        bytes memory signature
    ) public view returns (address) {
        bytes32 messageHash = getMessageHash(_tokenContract, _tokenId);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return recoverSigner(ethSignedMessageHash, signature);
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) public pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

contract Helpers {
    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
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

