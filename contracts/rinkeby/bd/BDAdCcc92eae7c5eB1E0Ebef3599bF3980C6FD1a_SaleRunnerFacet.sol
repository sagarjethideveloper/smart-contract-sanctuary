// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "../../../interfaces/IEscrowTicketer.sol";
import "../../../interfaces/ISeenHausNFT.sol";
import "../../../interfaces/ISaleRunner.sol";
import "../MarketHandlerBase.sol";

/**
 * @title SaleRunnerFacet
 *
 * @notice Handles the operation of Seen.Haus sales.
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
contract SaleRunnerFacet is ISaleRunner, MarketHandlerBase {

    // Threshold to auction extension window // TODO move this to market controller configuration
    uint256 constant extensionWindow = 15 minutes;

    /**
     * @dev Modifier to protect initializer function from being invoked twice.
     */
    modifier onlyUnInitialized()
    {
        MarketHandlerLib.MarketHandlerInitializers storage mhi = MarketHandlerLib.marketHandlerInitializers();
        require(!mhi.saleRunnerFacet, "Initializer: contract is already initialized");
        mhi.saleRunnerFacet = true;
        _;
    }

    /**
     * @notice Facet Initializer
     *
     * Register supported interfaces
     */
    function initialize()
    public
    onlyUnInitialized
    {
        DiamondLib.addSupportedInterface(type(ISaleRunner).interfaceId);
    }

    /**
     * @notice Change the audience for a sale.
     *
     * Reverts if:
     *  - Caller does not have ADMIN role
     *  - Auction doesn't exist or has already been settled
     *
     * @param _consignmentId - the id of the consignment being sold
     * @param _audience - the new audience for the sale
     */
    function changeSaleAudience(uint256 _consignmentId, Audience _audience)
    external
    override
    onlyRole(ADMIN)
    {
        // Get Market Handler Storage slot
        MarketHandlerLib.MarketHandlerStorage storage mhs = MarketHandlerLib.marketHandlerStorage();

        // Get consignment (reverting if not valid)
        Consignment memory consignment = getMarketController().getConsignment(_consignmentId);

        // Make sure the sale exists and hasn't been settled
        Sale storage sale = mhs.sales[consignment.id];
        require(sale.start != 0, "Sale does not exist");
        require(sale.state != State.Ended, "Sale has already been settled");

        // Set the new audience for the consignment
        setAudience(_consignmentId, _audience);

    }

    /**
     * @notice Buy some amount of the remaining supply of the lot for sale.
     *
     * Ownership of the purchased inventory is transferred to the buyer.
     * The buyer's payment will be held for disbursement when sale is settled.
     *
     * Reverts if:
     *  - Caller is not in audience
     *  - Sale doesn't exist or hasn't started
     *  - Caller is a contract
     *  - The per-transaction buy limit is exceeded
     *  - Payment doesn't cover the order price
     *
     * Emits a Purchase event.
     * May emit a SaleStarted event, on the first purchase.
     *
     * @param _consignmentId - id of the consignment being sold
     * @param _amount - the amount of the remaining supply to buy
     */
    function buy(uint256 _consignmentId, uint256 _amount)
    external
    override
    payable
    onlyAudienceMember(_consignmentId)
    {
        // Get Market Handler Storage slot
        MarketHandlerLib.MarketHandlerStorage storage mhs = MarketHandlerLib.marketHandlerStorage();

        // Get the consignment
        Consignment memory consignment = getMarketController().getConsignment(_consignmentId);

        // Make sure the sale exists
        Sale storage sale = mhs.sales[_consignmentId];
        require(sale.start != 0, "Sale does not exist");

        // Make sure we can accept the buy order
        require(block.timestamp >= sale.start, "Sale hasn't started");
        require(!Address.isContract(msg.sender), "Contracts may not buy");
        require(_amount <= sale.perTxCap, "Per transaction limit for this sale exceeded");
        require(msg.value == sale.price * _amount, "Payment does not cover order price");

        // If this was the first successful purchase...
        if (sale.state == State.Pending) {

            // First buy updates sale state to Running
            sale.state = State.Running;

            // Notify listeners of state change
            emit SaleStarted(_consignmentId);

        }

        // Determine if consignment is physical
        address nft = getMarketController().getNft();
        if (nft == consignment.tokenAddress && ISeenHausNFT(nft).isPhysical(consignment.tokenId)) {

            // Issue an escrow ticket to the buyer
            address escrowTicketer = getMarketController().getEscrowTicketer(_consignmentId);
            IEscrowTicketer(escrowTicketer).issueTicket(_consignmentId, _amount, payable(msg.sender));

        } else {

            // Release the purchased amount of the consigned token supply to buyer
            getMarketController().releaseConsignment(_consignmentId, _amount, msg.sender);

        }

        // Announce the purchase
        emit Purchase(consignment.id, _amount, msg.sender);
    }

    /**
     * @notice Close out a successfully completed sale.
     *
     * Funds are disbursed as normal. See: {MarketClient.disburseFunds}
     *
     * Reverts if:
     * - Sale doesn't exist or hasn't started
     * - There is remaining inventory
     *
     * Emits a SaleEnded event.
     *
     * @param _consignmentId - id of the consignment being sold
     */
    function closeSale(uint256 _consignmentId)
    external
    override
    {
        // Get Market Handler Storage slot
        MarketHandlerLib.MarketHandlerStorage storage mhs = MarketHandlerLib.marketHandlerStorage();

        // Get consignment
        Consignment memory consignment = getMarketController().getConsignment(_consignmentId);

        // Make sure the sale exists and can be closed normally
        Sale storage sale = mhs.sales[_consignmentId];
        require(sale.start != 0, "Sale does not exist");
        require(sale.state != State.Ended, "Sale has already been settled");
        require(sale.state == State.Running, "Sale hasn't started");

        // Mark sale as settled
        sale.state = State.Ended;
        sale.outcome = Outcome.Closed;

        // Distribute the funds (handles royalties, staking, multisig, and seller)
        disburseFunds(_consignmentId, consignment.supply * sale.price);

        // Notify listeners about state change
        emit SaleEnded(_consignmentId, sale.outcome);

    }

    /**
     * @notice Cancel a sale that has remaining inventory.
     *
     * Remaining tokens are returned to seller. If there have been any purchases,
     * the funds are distributed normally.
     *
     * Reverts if:
     * - Caller doesn't have ADMIN role
     * - Sale doesn't exist or has already been settled
     *
     * Emits a SaleEnded event
     *
     * @param _consignmentId - id of the consignment being sold
     */
    function cancelSale(uint256 _consignmentId)
    external
    override
    onlyRole(ADMIN)
    {
        // Get Market Handler Storage slot
        MarketHandlerLib.MarketHandlerStorage storage mhs = MarketHandlerLib.marketHandlerStorage();

        // Get the consignment
        Consignment memory consignment = getMarketController().getConsignment(_consignmentId);

        // Make sure the sale exists and can canceled
        Sale storage sale = mhs.sales[_consignmentId];
        require(sale.start != 0, "Sale does not exist");
        require(sale.state != State.Ended, "Sale has already been settled");

        // Mark sale as settled
        sale.state = State.Ended;
        sale.outcome = Outcome.Canceled;

        // Determine the amount sold and remaining
        uint256 remaining = getMarketController().getSupply(_consignmentId);
        uint256 sold = consignment.supply - remaining;

        // Disburse the funds for the sold items
        if (sold > 0) {
            uint256 salesTotal = sold * sale.price;
            disburseFunds(_consignmentId, salesTotal);
        }

        if (remaining > 0) {

            // Transfer the remaining supply back to the seller
            getMarketController().releaseConsignment(_consignmentId, remaining, consignment.seller);

        }

        // Notify listeners about state change
        emit SaleEnded(_consignmentId, sale.outcome);

    }

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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../domain/SeenTypes.sol";

/**
 * @title IEscrowTicketer
 *
 * @notice Manages the issue and claim of escrow tickets.
 *
 * The ERC-165 identifier for this interface is: 0x84200a73
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
interface IEscrowTicketer {

    event TicketIssued(uint256 ticketId, uint256 indexed consignmentId, address indexed buyer, uint256 amount);
    event TicketClaimed(uint256 ticketId, address indexed claimant, uint256 amount);

    /**
     * @notice The nextTicket getter
     */
    function getNextTicket() external view returns (uint256);

    /**
     * @notice Get info about the ticket
     */
    function getTicket(uint256 _ticketId) external view returns (SeenTypes.EscrowTicket memory);

    /**
     * @notice Gets the URI for the ticket metadata
     *
     * This method normalizes how you get the URI,
     * since ERC721 and ERC1155 differ in approach
     *
     * @param _ticketId - the token id of the ticket
     */
    function getTicketURI(uint256 _ticketId) external view returns (string memory);

    /**
     * Issue an escrow ticket to the buyer
     *
     * For physical consignments, Seen.Haus must hold the items in escrow
     * until the buyer(s) claim them.
     *
     * When a buyer wins an auction or makes a purchase in a sale, the market
     * handler contract they interacted with will call this method to issue an
     * escrow ticket, which is an NFT that can be sold, transferred, or claimed.
     *
     * @param _consignmentId - the id of the consignment being sold
     * @param _amount - the amount of the given token to escrow
     * @param _buyer - the buyer of the escrowed item(s) to whom the ticket is issued
     */
    function issueTicket(uint256 _consignmentId, uint256 _amount, address payable _buyer) external;

    /**
     * Claim the holder's escrowed items associated with the ticket.
     *
     * @param _ticketId - the ticket representing the escrowed items
     */
    function claim(uint256 _ticketId) external;

}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../domain/SeenTypes.sol";
import "./IERC2981.sol";

/**
 * @title ISeenHausNFT
 *
 * @notice This is the interface for the Seen.Haus ERC-1155 NFT contract.
 *
 * The ERC-165 identifier for this interface is: 0x3ade32fd
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
*/
interface ISeenHausNFT is IERC2981, IERC1155 {

    /**
     * @notice The nextToken getter
     * @dev does not increment counter
     */
    function getNextToken() external view returns (uint256 nextToken);

    /**
     * @notice Get the info about a given token.
     *
     * @param _tokenId - the id of the token to check
     * @return tokenInfo - the info about the token. See: {SeenTypes.Token}
     */
    function getTokenInfo(uint256 _tokenId) external view returns (SeenTypes.Token memory tokenInfo);

    /**
     * @notice Check if a given token id corresponds to a physical lot.
     *
     * @param _tokenId - the id of the token to check
     * @return physical - true if the item corresponds to a physical lot
     */
    function isPhysical(uint256 _tokenId) external returns (bool);

    /**
     * @notice Mint a given supply of a token, marking it as physical.
     *
     * Entire supply must be minted at once.
     * More cannot be minted later for the same token id.
     * Can only be called by an address with the ESCROW_AGENT role.
     * Token supply is sent to the caller.
     *
     * @param _supply - the supply of the token
     * @param _creator - the creator of the NFT (where the royalties will go)
     * @param _tokenURI - the URI of the token metadata
     *
     * @return consignment - the registered primary market consignment of the newly minted token
     */
    function mintPhysical(
        uint256 _supply,
        address payable _creator,
        string memory _tokenURI,
        uint16 _royaltyPercentage
    )
    external
    returns(SeenTypes.Consignment memory consignment);

    /**
     * @notice Mint a given supply of a token.
     *
     * Entire supply must be minted at once.
     * More cannot be minted later for the same token id.
     * Can only be called by an address with the MINTER role.
     * Token supply is sent to the caller's address.
     *
     * @param _supply - the supply of the token
     * @param _creator - the creator of the NFT (where the royalties will go)
     * @param _tokenURI - the URI of the token metadata
     *
     * @return consignment - the registered primary market consignment of the newly minted token
     */
    function mintDigital(
        uint256 _supply,
        address payable _creator,
        string memory _tokenURI,
        uint16 _royaltyPercentage
    )
    external
    returns(SeenTypes.Consignment memory consignment);

}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../domain/SeenTypes.sol";
import "./IMarketHandler.sol";

/**
 * @title ISaleRunner
 *
 * @notice Handles the operation of Seen.Haus sales.
 *
 * The ERC-165 identifier for this interface is: 0x6164b6a0
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
interface ISaleRunner is IMarketHandler {

    // Events
    event SaleStarted(uint256 indexed consignmentId);
    event SaleEnded(uint256 indexed consignmentId, SeenTypes.Outcome indexed outcome);
    event Purchase(uint256 indexed consignmentId,  uint256 indexed amount, address indexed buyer);

    /**
     * @notice Change the audience for a sale.
     *
     * Reverts if:
     *  - Caller does not have ADMIN role
     *  - Auction doesn't exist or has already been settled
     *
     * @param _consignmentId - the id of the consignment being sold
     * @param _audience - the new audience for the sale
     */
    function changeSaleAudience(uint256 _consignmentId, SeenTypes.Audience _audience) external;

    /**
     * @notice Buy some amount of the remaining supply of the lot for sale.
     *
     * Ownership of the purchased inventory is transferred to the buyer.
     * The buyer's payment will be held for disbursement when sale is settled.
     *
     * Reverts if:
     *  - Caller is not in audience
     *  - Sale doesn't exist or hasn't started
     *  - Caller is a contract
     *  - The per-transaction buy limit is exceeded
     *  - Payment doesn't cover the order price
     *
     * Emits a Purchase event.
     * May emit a SaleStarted event, on the first purchase.
     *
     * @param _consignmentId - id of the consignment being sold
     * @param _amount - the amount of the remaining supply to buy
     */
    function buy(uint256 _consignmentId, uint256 _amount) external payable;

    /**
     * @notice Close out a successfully completed sale.
     *
     * Funds are disbursed as normal. See: {MarketClient.disburseFunds}
     *
     * Reverts if:
     * - Sale doesn't exist or hasn't started
     * - There is remaining inventory
     *
     * Emits a SaleEnded event.
     *
     * @param _consignmentId - id of the consignment being sold
     */
    function closeSale(uint256 _consignmentId) external;

    /**
     * @notice Cancel a sale that has remaining inventory.
     *
     * Remaining tokens are returned to seller. If there have been any purchases,
     * the funds are distributed normally.
     *
     * Reverts if:
     * - Caller doesn't have ADMIN role
     * - Sale doesn't exist or has already been settled
     *
     * Emits a SaleEnded event
     *
     * @param _consignmentId - id of the consignment being sold
     */
    function cancelSale(uint256 _consignmentId) external;

}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IMarketController.sol";
import "../../interfaces/IMarketHandler.sol";
import "../../domain/SeenConstants.sol";
import "../../interfaces/IERC2981.sol";
import "../../domain/SeenTypes.sol";
import "./MarketHandlerLib.sol";

/**
 * @title MarketHandlerBase
 *
 * @notice Provides base functionality for common actions taken by market handlers.
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
abstract contract MarketHandlerBase is IMarketHandler, SeenTypes, SeenConstants {

    /**
     * @dev Modifier that checks that the caller has a specific role.
     *
     * Reverts if caller doesn't have role.
     *
     * See: {AccessController.hasRole}
     */
    modifier onlyRole(bytes32 _role) {
        DiamondLib.DiamondStorage storage ds = DiamondLib.diamondStorage();
        require(ds.accessController.hasRole(_role, msg.sender), "Access denied, caller doesn't have role");
        _;
    }

    /**
     * @notice Gets the address of the Seen.Haus MarketController contract.
     *
     * @return marketController - the address of the MarketController contract
     */
    function getMarketController()
    internal
    view
    returns(IMarketController marketController)
    {
        return IMarketController(address(this));
    }

    /**
     * @notice Sets the audience for a consignment at sale or auction.
     *
     * Emits an AudienceChanged event.
     *
     * @param _consignmentId - the id of the consignment
     * @param _audience - the new audience for the consignment
     */
    function setAudience(uint256 _consignmentId, Audience _audience)
    internal
    {
        MarketHandlerLib.MarketHandlerStorage storage mhs = MarketHandlerLib.marketHandlerStorage();

        // Set the new audience
        mhs.audiences[_consignmentId] = _audience;

        // Notify listeners of state change
        emit AudienceChanged(_consignmentId, _audience);

    }

    /**
     * @notice Check if the caller is a Staker.
     *
     * @return status - true if caller's xSEEN ERC-20 balance is non-zero.
     */
    function isStaker()
    internal
    view
    returns (bool status)
    {
        IMarketController marketController = getMarketController();
        status = IERC20(marketController.getStaking()).balanceOf(msg.sender) > 0;
    }

    /**
     * @notice Check if the caller is a VIP Staker.
     *
     * See {MarketController:vipStakerAmount}
     *
     * @return status - true if caller's xSEEN ERC-20 balance is at least equal to the VIP Staker Amount.
     */
    function isVipStaker()
    internal
    view
    returns (bool status)
    {
        IMarketController marketController = getMarketController();
        status = IERC20(marketController.getStaking()).balanceOf(msg.sender) >= marketController.getVipStakerAmount();
    }

    /**
     * @notice Modifier that checks that caller is in consignment's audience
     *
     * Reverts if user is not in consignment's audience
     */
    modifier onlyAudienceMember(uint256 _consignmentId) {
        MarketHandlerLib.MarketHandlerStorage storage mhs = MarketHandlerLib.marketHandlerStorage();
        Audience audience = mhs.audiences[_consignmentId];
        if (audience != Audience.Open) {
            if (audience == Audience.Staker) {
                require(isStaker() == true, "Buyer is not a staker");
            } else if (audience == Audience.VipStaker) {
                require(isVipStaker() == true, "Buyer is not a VIP staker");
            }
        }
        _;
    }

    /**
     * @dev Modifier that checks that the caller is the consignor
     *
     * Reverts if caller isn't the consignor
     *
     * See: {MarketController.isConsignor}
     */
    modifier onlyConsignor(uint256 _consignmentId) {

        // Make sure the caller is the consignor
        require(getMarketController().isConsignor(_consignmentId, msg.sender), "Caller is not consignor");
        _;
    }

    /**
     * @notice Get a percentage of a given amount.
     *
     * N.B. Represent ercentage values are stored
     * as unsigned integers, the result of multiplying the given percentage by 100:
     * e.g, 1.75% = 175, 100% = 10000
     *
     * @param _amount - the amount to return a percentage of
     * @param _percentage - the percentage value represented as above
     */
    function getPercentageOf(uint256 _amount, uint16 _percentage)
    internal
    pure
    returns (uint256 share)
    {
        share = _amount * _percentage / 10000;
    }

    /**
     * @notice Deduct and pay royalties on sold secondary market consignments.
     *
     * Does nothing is this is a primary market sale.
     *
     * If the consigned item's contract supports NFT Royalty Standard EIP-2981,
     * it is queried for the expected royalty amount and recipient.
     *
     * Deducts royalty and pays to recipient:
     * - entire expected amount, if below or equal to the marketplace's maximum royalty percentage
     * - the marketplace's maximum royalty percentage See: {MarketController.maxRoyaltyPercentage}
     *
     * Emits a RoyaltyDisbursed event with the amount actually paid.
     *
     * @param _consignment - the consigned item
     * @param _grossSale - the gross sale amount
     *
     * @return net - the net amount of the sale after the royalty has been paid
     */
    function deductRoyalties(Consignment memory _consignment, uint256 _grossSale)
    internal
    returns (uint256 net)
    {
        // Get the MarketController
        IMarketController marketController = getMarketController();

        // Only pay royalties on secondary market sales
        uint256 royaltyAmount = 0;
        if (_consignment.market == Market.Secondary) {

            // Determine if NFT contract supports NFT Royalty Standard EIP-2981
            try IERC165(_consignment.tokenAddress).supportsInterface(type(IERC2981).interfaceId) returns (bool supported) {

                // If so, find out the who to pay and how much
                if (supported == true) {

                    // Get the royalty recipient and expected payment
                    (address recipient, uint256 expected) = IERC2981(_consignment.tokenAddress).royaltyInfo(_consignment.tokenId, _grossSale);

                    // Determine the max royalty we will pay
                    uint256 maxRoyalty = getPercentageOf(_grossSale, marketController.getMaxRoyaltyPercentage());

                    // If a royalty is expected...
                    if (expected > 0) {

                        // Lets pay, but only up to our platform policy maximum
                        royaltyAmount = (expected <= maxRoyalty) ? expected : maxRoyalty;
                        payable(recipient).transfer(royaltyAmount);

                        // Notify listeners of payment
                        emit RoyaltyDisbursed(_consignment.id, recipient, royaltyAmount);
                    }

                }

            // Any case where the check for interface support fails can be ignored
            } catch Error(string memory) {
            } catch (bytes memory) {
            }

        }

        // Return the net amount after royalty deduction
        net = _grossSale - royaltyAmount;
    }

    /**
     * @notice Deduct and pay fee on a sold consignment.
     *
     * Deducts marketplace fee and pays:
     * - Half to the staking contract
     * - Half to the multisig contract
     *
     * Emits a FeeDisbursed event for staking payment.
     * Emits a FeeDisbursed event for multisig payment.
     *
     * @param _consignment - the consigned item
     * @param _netAmount - the net amount after royalties
     *
     * @return payout - the payout amount for the seller
     */
    function deductFee(Consignment memory _consignment, uint256 _netAmount)
    internal
    returns (uint256 payout)
    {
        // Get the MarketController
        IMarketController marketController = getMarketController();

        // With the net after royalties, calculate and split
        // the auction fee between SEEN staking and multisig,
        uint256 feeAmount = getPercentageOf(_netAmount, marketController.getFeePercentage());
        uint256 split = feeAmount / 2;
        address payable staking = marketController.getStaking();
        address payable multisig = marketController.getMultisig();
        staking.transfer(split);
        multisig.transfer(split);

        // Return the seller payout amount after fee deduction
        payout = _netAmount - feeAmount;

        // Notify listeners of payment
        emit FeeDisbursed(_consignment.id, staking, split);
        emit FeeDisbursed(_consignment.id, multisig, split);
    }

    /**
     * @notice Disburse funds for a sale or auction, primary or secondary.
     *
     * Disburses funds in this order
     * - Pays any necessary royalties first. See {deductRoyalties}
     * - Deducts and distributes marketplace fee. See {deductFee}
     * - Pays the remaining amount to the seller.
     *
     * Emits a PayoutDisbursed event on success.
     *
     * @param _consignmentId - the id of the consignment being sold
     * @param _saleAmount - the gross sale amount
     */
    function disburseFunds(uint256 _consignmentId, uint256 _saleAmount)
    internal
    {
        // Get the MarketController
        IMarketController marketController = getMarketController();

        // Get consignment
        SeenTypes.Consignment memory consignment = marketController.getConsignment(_consignmentId);

        // Pay royalties if needed
        uint256 net = deductRoyalties(consignment, _saleAmount);

        // Pay marketplace fee
        uint256 payout = deductFee(consignment, net);

        // Pay seller
        consignment.seller.transfer(payout);

        // Notify listeners of payment
        emit PayoutDisbursed(_consignmentId, consignment.seller, payout);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title SeenTypes
 *
 * @notice Enums and structs used by the Seen.Haus contract ecosystem.
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
contract SeenTypes {

    enum Market {
        Primary,
        Secondary
    }

    enum Clock {
        Live,
        Trigger
    }

    enum Audience {
        Open,
        Staker,
        VipStaker
    }

    enum Outcome {
        Pending,
        Closed,
        Canceled
    }

    enum State {
        Pending,
        Running,
        Ended
    }

    enum Ticketer {
        Default,
        Lots,
        Items
    }

    struct Token {
        address payable creator;
        uint16 royaltyPercentage;
        bool isPhysical;
        uint256 id;
        uint256 supply;
        string uri;
    }

    struct Consignment {
        Market market;
        address payable seller;
        address tokenAddress;
        uint256 tokenId;
        uint256 supply;
        uint256 id;
        bool multiToken;
        bool marketed;
        bool released;
    }

    struct Auction {
        address payable buyer;
        uint256 consignmentId;
        uint256 start;
        uint256 duration;
        uint256 reserve;
        uint256 bid;
        Clock clock;
        State state;
        Outcome outcome;
    }

    struct Sale {
        uint256 consignmentId;
        uint256 start;
        uint256 price;
        uint256 perTxCap;
        State state;
        Outcome outcome;
    }

    struct EscrowTicket {
        uint256 amount;
        uint256 consignmentId;
        uint256 id;
        string itemURI;
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 *
 * _Available since v3.1._
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids) external view returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must be have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IERC2981 interface
 *
 * @notice NFT Royalty Standard.
 *
 * See https://eips.ethereum.org/EIPS/eip-2981
 */
interface IERC2981 is IERC165 {

    /**
     * @notice Determine how much royalty is owed (if any) and to whom.
     * @param _tokenId - the NFT asset queried for royalty information
     * @param _salePrice - the sale price of the NFT asset specified by _tokenId
     * @return receiver - address of who should be sent the royalty payment
     * @return royaltyAmount - the royalty payment amount for _salePrice
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (
        address receiver,
        uint256 royaltyAmount
    );

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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../domain/SeenTypes.sol";

/**
 * @title IMarketHandler
 *
 * @notice Provides no functions, only common events to market handler facets.
 *
 * No ERC-165 identifier for this interface, not checked or supported.
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
interface IMarketHandler {

    // Events
    event RoyaltyDisbursed(uint256 indexed consignmentId, address indexed recipient, uint256 amount);
    event FeeDisbursed(uint256 indexed consignmentId, address indexed recipient, uint256 amount);
    event PayoutDisbursed(uint256 indexed consignmentId, address indexed recipient, uint256 amount);
    event AudienceChanged(uint256 indexed consignmentId, SeenTypes.Audience indexed audience);

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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IMarketConfig.sol";
import "./IMarketClerk.sol";

/**
 * @title IMarketController
 *
 * @notice Manages configuration and consignments used by the Seen.Haus contract suite.
 *
 * The ERC-165 identifier for this interface is: 0xe5f2f941
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
interface IMarketController is IMarketClerk, IMarketConfig {}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title SeenConstants
 *
 * @notice Constants used by the Seen.Haus contract ecosystem.
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
contract SeenConstants {

    // Endpoint will serve dynamic metadata composed of ticket and ticketed item's info
    string internal constant ESCROW_TICKET_URI = "https://seen.haus/ticket/metadata/";

    // Access Control Roles
    bytes32 internal constant ADMIN = keccak256("ADMIN");                   // Deployer and any other admins as needed
    bytes32 internal constant SELLER = keccak256("SELLER");                 // Approved sellers amd Seen.Haus reps
    bytes32 internal constant MINTER = keccak256("MINTER");                 // Approved artists and Seen.Haus reps
    bytes32 internal constant ESCROW_AGENT = keccak256("ESCROW_AGENT");     // Seen.Haus Physical Item Escrow Agent
    bytes32 internal constant MARKET_HANDLER = keccak256("MARKET_HANDLER"); // Market Handler contracts

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../../interfaces/IMarketController.sol";
import "../../domain/SeenTypes.sol";
import "../diamond/DiamondLib.sol";

/**
 * @title MarketHandlerLib
 *
 * @dev Provides access to the the MarketHandler Storage and Intitializer slots for MarketHandler facets
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
library MarketHandlerLib {

    bytes32 constant MARKET_HANDLER_STORAGE_POSITION = keccak256("seen.haus.market.handler.storage");
    bytes32 constant MARKET_HANDLER_INITIALIZERS_POSITION = keccak256("seen.haus.market.handler.initializers");

    struct MarketHandlerStorage {

        // map a consignment id to an audience
        mapping(uint256 => SeenTypes.Audience) audiences;

        //s map a consignment id to a sale
        mapping(uint256 => SeenTypes.Sale) sales;

        // @dev map a consignment id to an auction
        mapping(uint256 => SeenTypes.Auction) auctions;

    }

    struct MarketHandlerInitializers {

        // AuctionBuilderFacet initialization state
        bool auctionBuilderFacet;

        // AuctionRunnerFacet initialization state
        bool auctionRunnerFacet;

        // SaleBuilderFacet initialization state
        bool saleBuilderFacet;

        // SaleRunnerFacet initialization state
        bool saleRunnerFacet;

    }

    function marketHandlerStorage() internal pure returns (MarketHandlerStorage storage mhs) {
        bytes32 position = MARKET_HANDLER_STORAGE_POSITION;
        assembly {
            mhs.slot := position
        }
    }

    function marketHandlerInitializers() internal pure returns (MarketHandlerInitializers storage mhi) {
        bytes32 position = MARKET_HANDLER_INITIALIZERS_POSITION;
        assembly {
            mhi.slot := position
        }
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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "../domain/SeenTypes.sol";

/**
 * @title IMarketController
 *
 * @notice Manages configuration and consignments used by the Seen.Haus contract suite.
 * @dev Contributes its events and functions to the IMarketController interface
 *
 * The ERC-165 identifier for this interface is: 0x4ea5d7dd
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
interface IMarketConfig {

    /// Events
    event NFTAddressChanged(address indexed nft);
    event EscrowTicketerAddressChanged(address indexed escrowTicketer, SeenTypes.Ticketer indexed ticketerType);
    event StakingAddressChanged(address indexed staking);
    event MultisigAddressChanged(address indexed multisig);
    event VipStakerAmountChanged(uint256 indexed vipStakerAmount);
    event FeePercentageChanged(uint16 indexed feePercentage);
    event MaxRoyaltyPercentageChanged(uint16 indexed maxRoyaltyPercentage);
    event OutBidPercentageChanged(uint16 indexed outBidPercentage);
    event DefaultTicketerTypeChanged(SeenTypes.Ticketer indexed ticketerType);

    /**
     * @notice Sets the address of the xSEEN ERC-20 staking contract.
     *
     * Emits a NFTAddressChanged event.
     *
     * @param _nft - the address of the nft contract
     */
    function setNft(address _nft) external;

    /**
     * @notice The nft getter
     */
    function getNft() external view returns (address);

    /**
     * @notice Sets the address of the Seen.Haus lots-based escrow ticketer contract.
     *
     * Emits a EscrowTicketerAddressChanged event.
     *
     * @param _lotsTicketer - the address of the items-based escrow ticketer contract
     */
    function setLotsTicketer(address _lotsTicketer) external;

    /**
     * @notice The lots-based escrow ticketer getter
     */
    function getLotsTicketer() external view returns (address);

    /**
     * @notice Sets the address of the Seen.Haus items-based escrow ticketer contract.
     *
     * Emits a EscrowTicketerAddressChanged event.
     *
     * @param _itemsTicketer - the address of the items-based escrow ticketer contract
     */
    function setItemsTicketer(address _itemsTicketer) external;

    /**
     * @notice The items-based escrow ticketer getter
     */
    function getItemsTicketer() external view returns (address);

    /**
     * @notice Sets the address of the xSEEN ERC-20 staking contract.
     *
     * Emits a StakingAddressChanged event.
     *
     * @param _staking - the address of the staking contract
     */
    function setStaking(address payable _staking) external;

    /**
     * @notice The staking getter
     */
    function getStaking() external view returns (address payable);

    /**
     * @notice Sets the address of the Seen.Haus multi-sig wallet.
     *
     * Emits a MultisigAddressChanged event.
     *
     * @param _multisig - the address of the multi-sig wallet
     */
    function setMultisig(address payable _multisig) external;

    /**
     * @notice The multisig getter
     */
    function getMultisig() external view returns (address payable);

    /**
     * @notice Sets the VIP staker amount.
     *
     * Emits a VipStakerAmountChanged event.
     *
     * @param _vipStakerAmount - the minimum amount of xSEEN ERC-20 a caller must hold to participate in VIP events
     */
    function setVipStakerAmount(uint256 _vipStakerAmount) external;

    /**
     * @notice The vipStakerAmount getter
     */
    function getVipStakerAmount() external view returns (uint256);

    /**
     * @notice Sets the marketplace fee percentage.
     *
     * Emits a FeePercentageChanged event.
     *
     * @param _feePercentage - the percentage that will be taken as a fee from the net of a Seen.Haus sale or auction (after royalties)
     */
    function setFeePercentage(uint16 _feePercentage) external;

    /**
     * @notice The feePercentage getter
     */
    function getFeePercentage() external view returns (uint16);

    /**
     * @notice Sets the external marketplace maximum royalty percentage.
     *
     * Emits a MaxRoyaltyPercentageChanged event.
     *
     * @param _maxRoyaltyPercentage - the maximum percentage of a Seen.Haus sale or auction that will be paid as a royalty
     */
    function setMaxRoyaltyPercentage(uint16 _maxRoyaltyPercentage) external;

    /**
     * @notice The maxRoyaltyPercentage getter
     */
    function getMaxRoyaltyPercentage() external view returns (uint16);

    /**
     * @notice Sets the marketplace auction outbid percentage.
     *
     * Emits a OutBidPercentageChanged event.
     *
     * @param _outBidPercentage - the minimum percentage a Seen.Haus auction bid must be above the previous bid to prevail
     */
    function setOutBidPercentage(uint16 _outBidPercentage) external;

    /**
     * @notice The outBidPercentage getter
     */
    function getOutBidPercentage() external view returns (uint16);

    /**
     * @notice Sets the default escrow ticketer type.
     *
     * Emits a DefaultTicketerTypeChanged event.
     *
     * Reverts if _ticketerType is Ticketer.Default
     * Reverts if _ticketerType is already the defaultTicketerType
     *
     * @param _ticketerType - the new default escrow ticketer type.
     */
    function setDefaultTicketerType(SeenTypes.Ticketer _ticketerType) external;

    /**
     * @notice The defaultTicketerType getter
     */
    function getDefaultTicketerType() external view returns (SeenTypes.Ticketer);

    /**
     * @notice Get the Escrow Ticketer to be used for a given consignment
     *
     * If a specific ticketer has not been set for the consignment,
     * the default escrow ticketer will be returned.
     *
     * @param _consignmentId - the id of the consignment
     * @return ticketer = the address of the escrow ticketer to use
     */
    function getEscrowTicketer(uint256 _consignmentId) external view returns (address ticketer);

}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../domain/SeenTypes.sol";

/**
 * @title IMarketClerk
 *
 * @notice Manages consignments for the Seen.Haus contract suite.
 *
 * The ERC-165 identifier for this interface is: 0xab572e9c
 *
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
interface IMarketClerk is IERC1155Receiver, IERC721Receiver {

    /// Events
    event ConsignmentTicketerChanged(uint256 consignmentId, SeenTypes.Ticketer indexed ticketerType);
    event ConsignmentRegistered(address indexed consignor, address indexed seller, SeenTypes.Consignment consignment);
    event ConsignmentMarketed(address indexed consignor, address indexed seller, uint256 indexed consignmentId);
    event ConsignmentReleased(uint256 indexed consignmentId, uint256 amount, address releasedTo);

    /**
     * @notice The nextConsignment getter
     */
    function getNextConsignment() external view returns (uint256);

    /**
     * @notice The consignment getter
     */
    function getConsignment(uint256 _consignmentId) external view returns (SeenTypes.Consignment memory);

    /**
     * @notice Get the remaining supply of the given consignment.
     *
     * @param _consignmentId - the id of the consignment
     * @return uint256 - the remaining supply held by the MarketController
     */
    function getSupply(uint256 _consignmentId) external view returns(uint256);

    /**
     * @notice Is the caller the consignor of the given consignment?
     *
     * @param _account - the _account to check
     * @param _consignmentId - the id of the consignment
     * @return  bool - true if caller is consignor
     */
    function isConsignor(uint256 _consignmentId, address _account) external view returns(bool);

    /**
     * @notice Registers a new consignment for sale or auction.
     *
     * Emits a ConsignmentRegistered event.
     *
     * @param _market - the market for the consignment. See {SeenTypes.Market}
     * @param _consignor - the address executing the consignment transaction
     * @param _seller - the seller of the consignment
     * @param _tokenAddress - the contract address issuing the NFT behind the consignment
     * @param _tokenId - the id of the token being consigned
     * @param _supply - the amount of the token being consigned
     *
     * @return Consignment - the registered consignment
     */
    function registerConsignment(
        SeenTypes.Market _market,
        address _consignor,
        address payable _seller,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _supply
    )
    external
    returns(SeenTypes.Consignment memory);

    /**
      * @notice Update consignment to indicate it has been marketed
      *
      * Emits a ConsignmentMarketed event.
      *
      * Reverts if consignment has already been marketed.
      *
      * @param _consignmentId - the id of the consignment
      */
    function marketConsignment(uint256 _consignmentId) external;

    /**
     * @notice Release the consigned item to a given address
     *
     * Emits a ConsignmentReleased event.
     *
     * Reverts if caller is does not have MARKET_HANDLER role.
     *
     * @param _consignmentId - the id of the consignment
     * @param _amount - the amount of the consigned supply to release
     * @param _releaseTo - the address to transfer the consigned token balance to
     */
    function releaseConsignment(uint256 _consignmentId, uint256 _amount, address _releaseTo) external;

    /**
     * @notice Set the type of Escrow Ticketer to be used for a consignment
     *
     * Default escrow ticketer is Ticketer.Lots. This only needs to be called
     * if overriding to Ticketer.Items for a given consignment.
     *
     * Emits a ConsignmentTicketerSet event.
     * Reverts if consignment is not registered.
     *
     * @param _consignmentId - the id of the consignment
     * @param _ticketerType - the type of ticketer to use. See: {SeenTypes.Ticketer}
     */
    function setConsignmentTicketer(uint256 _consignmentId, SeenTypes.Ticketer _ticketerType) external;

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev _Available since v3.1._
 */
interface IERC1155Receiver is IERC165 {

    /**
        @dev Handles the receipt of a single ERC1155 token type. This function is
        called at the end of a `safeTransferFrom` after the balance has been updated.
        To accept the transfer, this must return
        `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
        (i.e. 0xf23a6e61, or its own function selector).
        @param operator The address which initiated the transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param id The ID of the token being transferred
        @param value The amount of tokens being transferred
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    )
        external
        returns(bytes4);

    /**
        @dev Handles the receipt of a multiple ERC1155 token types. This function
        is called at the end of a `safeBatchTransferFrom` after the balances have
        been updated. To accept the transfer(s), this must return
        `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
        (i.e. 0xbc197c81, or its own function selector).
        @param operator The address which initiated the batch transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param ids An array containing ids of each token being transferred (order and length must match values array)
        @param values An array containing amounts of each token being transferred (order and length must match ids array)
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
    */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        external
        returns(bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IDiamondCut } from "../../interfaces/IDiamondCut.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DiamondLib
 *
 * @notice Diamond storage slot and supported interfaces
 *
 * @notice Based on Nick Mudge's gas-optimized diamond-2 reference.
 * Reference Implementation  : https://github.com/mudgen/diamond-2-hardhat
 * EIP-2535 Diamond Standard : https://eips.ethereum.org/EIPS/eip-2535
 *
 * N.B. Facet management functions from original `DiamondLib` were refactor/extracted
 * to JewelerLib, since business facets also use this library for access control and
 * managing supported interfaces.
 *
 * @author Nick Mudge <[email protected]> (https://twitter.com/mudgen)
 * @author Cliff Hall <[email protected]> (https://twitter.com/seaofarrows)
 */
library DiamondLib {

    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

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

        // notice the Seen.Haus AccessController
        IAccessControl accessController;

    }

    /**
     * @notice Get the Diamond storage slot
     *
     * @return ds - Diamond storage slot cast to DiamondStorage
     */
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /**
     * @notice Add a supported interface to the Diamond
     *
     * @param _interfaceId - the interface to add
     */
    function addSupportedInterface(bytes4 _interfaceId) internal {

        // Get the DiamondStorage struct
        DiamondStorage storage ds = diamondStorage();

        // Flag the interfaces as supported
        ds.supportedInterfaces[_interfaceId] = true;
    }

    /**
     * @notice Implementation of ERC-165 interface detection standard.
     *
     * @param _interfaceId - the sighash of the given interface
     */
    function supportsInterface(bytes4 _interfaceId) internal view returns (bool) {

        // Get the DiamondStorage struct
        DiamondStorage storage ds = diamondStorage();

        // Return the value
        return ds.supportedInterfaces[_interfaceId] || false;
    }

    /**
     * @notice Remove a supported interface from the Diamond
     *
     * @param _interfaceId - the interface to remove
     */
    function removeSupportedInterface(bytes4 _interfaceId) internal {

        // Get the DiamondStorage struct
        DiamondStorage storage ds = diamondStorage();

        // Remove interface supported flag
        delete ds.supportedInterfaces[_interfaceId];
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IDiamondCut
 *
 * @notice Diamond Facet management
 *
 * Reference Implementation  : https://github.com/mudgen/diamond-2-hardhat
 * EIP-2535 Diamond Standard : https://eips.ethereum.org/EIPS/eip-2535
 *
 * The ERC-165 identifier for this interface is: 0x1f931c1c
 *
 * @author Nick Mudge <[email protected]> (https://twitter.com/mudgen)
 */
interface IDiamondCut {

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);

    enum FacetCutAction {Add, Replace, Remove}

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /**
     * @notice Add/replace/remove any number of functions and
     * optionally execute a function with delegatecall
     *
     * _calldata is executed with delegatecall on _init
     *
     * @param _diamondCut Contains the facet addresses and function selectors
     * @param _init The address of the contract or facet to execute _calldata
     * @param _calldata A function call, including function selector and arguments
     */
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;
}

