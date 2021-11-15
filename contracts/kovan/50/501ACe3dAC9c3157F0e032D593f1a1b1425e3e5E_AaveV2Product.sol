// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

import "../interface/AaveV2/IAaveProtocolDataProvider.sol";
import "../interface/AaveV2/IAToken.sol";
import "./BaseProduct.sol";

/**
 * @title AaveV2Product
 * @author solace.fi
 * @notice The **Aave(V2)** product that is users can buy policy for **Aave(V2)**. It is a concrete smart contract that inherits from abstract [`BaseProduct`](./BaseProduct).
 */
contract AaveV2Product is BaseProduct {

    // IAaveProtocolDataProvider.
    IAaveProtocolDataProvider internal _aaveDataProvider;

    /**
      * @notice Constructs the AaveV2Product.
      * @param governance_ The address of the [governor](/docs/user-docs/Governance).
      * @param policyManager_ The [`PolicyManager`](../PolicyManager) contract.
      * @param registry_ The [`Registry`](../Registry) contract.
      * @param dataProvider_ Aave protocol data provider address.
      * @param minPeriod_ The minimum policy period in blocks to purchase a **policy**.
      * @param maxPeriod_ The maximum policy period in blocks to purchase a **policy**.
      * @param price_ The cover price for the **Product**.
      * @param maxCoverPerUserDivisor_ The max cover amount divisor for per user. (maxCover / divisor = maxCoverPerUser).
      * @param quoter_ The exchange quoter address.
     */
    constructor (
        address governance_,
        IPolicyManager policyManager_,
        IRegistry registry_,
        address dataProvider_,
        uint40 minPeriod_,
        uint40 maxPeriod_,
        uint24 price_,
        uint32 maxCoverPerUserDivisor_,
        address quoter_
    ) BaseProduct(
        governance_,
        policyManager_,
        registry_,
        dataProvider_,
        minPeriod_,
        maxPeriod_,
        price_,
        maxCoverPerUserDivisor_,
        quoter_,
        "Solace.fi-AaveV2Product",
        "1"
    ) {
        _aaveDataProvider = IAaveProtocolDataProvider(dataProvider_);
        _SUBMIT_CLAIM_TYPEHASH = keccak256("AaveV2ProductSubmitClaim(uint256 policyID,uint256 amountOut,uint256 deadline)");
        _productName = "AaveV2";
    }
    /**
     * @notice Calculate the value of a user's Aave V2 position in **ETH**.
     * The `positionContract` must be an [**aToken**](https://etherscan.io/tokens/label/aave-v2).
     * @param policyholder The owner of the position.
     * @param positionContract The address of the **aToken**.
     * @return positionAmount The value of the position.
     */
    function appraisePosition(address policyholder, address positionContract) public view override returns (uint256 positionAmount) {
        // verify positionContract
        IAToken token = IAToken(positionContract);
        address underlying = token.UNDERLYING_ASSET_ADDRESS();
        ( address aTokenAddress, , ) = _aaveDataProvider.getReserveTokensAddresses(underlying);
        require(positionContract == aTokenAddress, "Invalid position contract");
        // swap math
        uint256 balance = token.balanceOf(policyholder);
        return _quoter.tokenToEth(underlying, balance);
    }

    /**
     * @notice Aave's Data Provider.
     * @return dataProvider_ The data provider.
     */
    function aaveDataProvider() external view returns (address dataProvider_) {
        return address(_aaveDataProvider);
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Changes the covered platform.
     * The function should be used if the the protocol changes their registry but keeps the children contracts.
     * A new version of the protocol will likely require a new Product.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param dataProvider_ The new Data Provider.
     */
    function setCoveredPlatform(address dataProvider_) public override {
        super.setCoveredPlatform(dataProvider_);
        _aaveDataProvider = IAaveProtocolDataProvider(dataProvider_);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// code borrowed from https://etherscan.io/address/0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d#code

pragma solidity 0.8.6;

interface IAaveProtocolDataProvider {
    function getReserveTokensAddresses(address asset) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress);
    // solhint-disable-next-line func-name-mixedcase
    function ADDRESSES_PROVIDER() external view returns (address);
}

// SPDX-License-Identifier: GPL-3.0-or-later
// code borrowed from https://etherscan.io/address/0x7b2a3cf972c3193f26cdec6217d27379b6417bd0#code

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


/**
 * @title Aave ERC20 AToken
 * @author Aave
 * @notice Implementation of the interest bearing token for the Aave protocol
 */
interface IAToken is IERC20Metadata {
    // solhint-disable-next-line func-name-mixedcase
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    // solhint-disable-next-line func-name-mixedcase
    function POOL() external view returns (address);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "../Governable.sol";
import "../interface/IPolicyManager.sol";
import "../interface/IRiskManager.sol";
import "../interface/ITreasury.sol";
import "../interface/IClaimsEscrow.sol";
import "../interface/IRegistry.sol";
import "../interface/IExchangeQuoter.sol";
import "../interface/IProduct.sol";


/**
 * @title BaseProduct
 * @author solace.fi
 * @notice The abstract smart contract that is inherited by every concrete individual **Product** contract.
 *
 * It is required to extend [`IProduct`](../interface/IProduct) and recommended to extend `BaseProduct`. `BaseProduct` extends [`IProduct`](../interface/IProduct) and takes care of the heavy lifting; new products simply need to set some variables in the constructor and implement [`appraisePosition()`](#appraiseposition). It has some helpful functionality not included in [`IProduct`](../interface/IProduct) including [`ExchangeQuoter` price oracles](../interface/IExchangeQuoter) and claim signers.
 */
abstract contract BaseProduct is IProduct, EIP712, ReentrancyGuard, Governable {
    using Address for address;

    /***************************************
    GLOBAL VARIABLES
    ***************************************/

    /// @notice Policy Manager.
    IPolicyManager internal _policyManager; // Policy manager ERC721 contract

    // Registry.
    IRegistry internal _registry;

    /// @notice The minimum policy period in blocks.
    uint40 internal _minPeriod;
    /// @notice The maximum policy period in blocks.
    uint40 internal _maxPeriod;
    /// @notice Covered platform.
    /// A platform contract which locates contracts that are covered by this product.
    /// (e.g., UniswapProduct will have Factory as coveredPlatform contract, because every Pair address can be located through getPool() function).
    address internal _coveredPlatform;
    /// @notice Price in wei per 1e12 wei of coverage per block.
    uint24 internal _price;
    /// @notice The max cover amount divisor for per user (maxCover / divisor = maxCoverPerUser).
    uint32 internal _maxCoverPerUserDivisor;
    /// @notice Cannot buy new policies while paused. (Default is False)
    bool internal _paused;

    /****
        Book-Keeping Variables
    ****/
    /// @notice The total policy count this product sold.
    uint256 internal _productPolicyCount;
    /// @notice The current amount covered (in wei).
    uint256 internal _activeCoverAmount;
    /// @notice The authorized signers.
    mapping(address => bool) internal _isAuthorizedSigner;

    // IExchangeQuoter.
    IExchangeQuoter internal _quoter;

    // Typehash for claim submissions.
    // Must be unique for all products.
    // solhint-disable-next-line var-name-mixedcase
    bytes32 internal _SUBMIT_CLAIM_TYPEHASH;

    // The name of the product.
    string internal _productName;

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when a claim signer is added.
    event SignerAdded(address indexed signer);
    /// @notice Emitted when a claim signer is removed.
    event SignerRemoved(address indexed signer);
    /// @notice Emitted when the exchange quoter is set.
    event QuoterSet(address indexed quoter);

    modifier whileUnpaused() {
        require(!_paused, "cannot buy when paused");
        _;
    }

    /**
     * @notice Constructs the product. `BaseProduct` by itself is not deployable, only its subclasses.
     * @param governance_ The governor.
     * @param policyManager_ The IPolicyManager contract.
     * @param registry_ The IRegistry contract.
     * @param coveredPlatform_ A platform contract which locates contracts that are covered by this product.
     * @param minPeriod_ The minimum policy period in blocks to purchase a **policy**.
     * @param maxPeriod_ The maximum policy period in blocks to purchase a **policy**.
     * @param price_ The cover price for the **Product**.
     * @param maxCoverPerUserDivisor_ The max cover amount divisor for per user. (maxCover / divisor = maxCoverPerUser).
     * @param quoter_ The exchange quoter address.
     * @param domain_ The user readable name of the EIP712 signing domain.
     * @param version_ The current major version of the signing domain.
     */
    constructor (
        address governance_,
        IPolicyManager policyManager_,
        IRegistry registry_,
        address coveredPlatform_,
        uint40 minPeriod_,
        uint40 maxPeriod_,
        uint24 price_,
        uint32 maxCoverPerUserDivisor_,
        address quoter_,
        string memory domain_,
        string memory version_
    ) EIP712(domain_, version_) Governable(governance_) {
        _policyManager = policyManager_;
        _registry = registry_;
        _coveredPlatform = coveredPlatform_;
        _minPeriod = minPeriod_;
        _maxPeriod = maxPeriod_;
        _price = price_;
        _maxCoverPerUserDivisor = maxCoverPerUserDivisor_;
        _quoter = IExchangeQuoter(quoter_);
    }

    /***************************************
    POLICYHOLDER FUNCTIONS
    ***************************************/

    /**
     * @notice Purchases and mints a policy on the behalf of the policyholder.
     * User will need to pay **ETH**.
     * @param policyholder Holder of the position to cover.
     * @param positionContract The contract address where the policyholder has a position to be covered.
     * @param coverAmount The value to cover in **ETH**. Will only cover up to the appraised value.
     * @param blocks The length (in blocks) for policy.
     * @return policyID The ID of newly created policy.
     */
    function buyPolicy(address policyholder, address positionContract, uint256 coverAmount, uint40 blocks) external payable override nonReentrant whileUnpaused returns (uint256 policyID){
        // check that the buyer has a position in the covered protocol
        uint256 positionAmount = appraisePosition(policyholder, positionContract);
        coverAmount = min(positionAmount, coverAmount);
        require(coverAmount != 0, "zero position value");

        // check that the product can provide coverage for this policy
        {
        uint256 maxCover = maxCoverAmount();
        uint256 maxUserCover = maxCover / _maxCoverPerUserDivisor;
        require(_activeCoverAmount + coverAmount <= maxCover, "max covered amount is reached");
        require(coverAmount <= maxUserCover, "over max cover single user");
        }
        // check that the buyer has paid the correct premium
        uint256 premium = coverAmount * blocks * _price / 1e12;
        require(msg.value >= premium && premium != 0, "insufficient payment");

        // check that the buyer provided valid period
        require(blocks >= _minPeriod && blocks <= _maxPeriod, "invalid period");

        // create the policy
        uint40 expirationBlock = uint40(block.number + blocks);
        policyID = _policyManager.createPolicy(policyholder, positionContract, coverAmount, expirationBlock, _price);

        // update local book-keeping variables
        _activeCoverAmount += coverAmount;
        _productPolicyCount++;

        // return excess payment
        if(msg.value > premium) payable(msg.sender).transfer(msg.value - premium);
        // transfer premium to the treasury
        ITreasury(payable(_registry.treasury())).routePremiums{value: premium}();

        emit PolicyCreated(policyID);

        return policyID;
    }

    /**
     * @notice Increase or decrease the cover amount of the policy.
     * User may need to pay **ETH** for increased cover amount or receive a refund for decreased cover amount.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     * @param coverAmount The new value to cover in **ETH**. Will only cover up to the appraised value.
     */
    function updateCoverAmount(uint256 policyID, uint256 coverAmount) external payable override nonReentrant whileUnpaused {
        (address policyholder, address product, address positionContract, uint256 previousCoverAmount, uint40 expirationBlock, uint24 purchasePrice) = _policyManager.getPolicyInfo(policyID);
        // check msg.sender is policyholder
        require(policyholder == msg.sender, "!policyholder");
        // check for correct product
        require(product == address(this), "wrong product");
        // check for policy expiration
        require(expirationBlock >= block.number, "policy is expired");

        // check that the buyer has a position in the covered protocol
        uint256 positionAmount = appraisePosition(policyholder, positionContract);
        coverAmount = min(positionAmount, coverAmount);
        require(coverAmount != 0, "zero position value");
        // check that the product can provide coverage for this policy
        {
        uint256 maxCover = maxCoverAmount();
        uint256 maxUserCover = maxCover / _maxCoverPerUserDivisor;
        require(_activeCoverAmount + coverAmount - previousCoverAmount <= maxCover, "max covered amount is reached");
        require(coverAmount <= maxUserCover, "over max cover single user");
        }
        // calculate premium needed for new cover amount as if policy is bought now
        uint256 remainingBlocks = expirationBlock - block.number;
        uint256 newPremium = coverAmount * remainingBlocks * _price / 1e12;

        // calculate premium already paid based on current policy
        uint256 paidPremium = previousCoverAmount * remainingBlocks * purchasePrice / 1e12;

        if (newPremium >= paidPremium) {
            uint256 premium = newPremium - paidPremium;
            // check that the buyer has paid the correct premium
            require(msg.value >= premium, "insufficient payment");
            if(msg.value > premium) payable(msg.sender).transfer(msg.value - premium);
            // transfer premium to the treasury
            ITreasury(payable(_registry.treasury())).routePremiums{value: premium}();
        } else {
            if(msg.value > 0) payable(msg.sender).transfer(msg.value);
            uint256 refundAmount = paidPremium - newPremium;
            ITreasury(payable(_registry.treasury())).refund(msg.sender, refundAmount);
        }
        // update policy's URI and emit event
        _policyManager.setPolicyInfo(policyID, policyholder, positionContract, coverAmount, expirationBlock, _price);
        emit PolicyUpdated(policyID);
    }

    /**
     * @notice Extend a policy.
     * User will need to pay **ETH**.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     * @param extension The length of extension in blocks.
     */
    function extendPolicy(uint256 policyID, uint40 extension) external payable override nonReentrant whileUnpaused {
        // check that the msg.sender is the policyholder
        (address policyholder, address product, address positionContract, uint256 coverAmount, uint40 expirationBlock, uint24 purchasePrice) = _policyManager.getPolicyInfo(policyID);
        require(policyholder == msg.sender,"!policyholder");
        require(product == address(this), "wrong product");
        require(expirationBlock >= block.number, "policy is expired");

        // compute the premium
        uint256 premium = coverAmount * extension * purchasePrice / 1e12;
        // check that the buyer has paid the correct premium
        require(msg.value >= premium, "insufficient payment");
        if(msg.value > premium) payable(msg.sender).transfer(msg.value - premium);
        // transfer premium to the treasury
        ITreasury(payable(_registry.treasury())).routePremiums{value: premium}();
        // check that the buyer provided valid period
        uint40 newExpirationBlock = expirationBlock + extension;
        uint40 duration = newExpirationBlock - uint40(block.number);
        require(duration >= _minPeriod && duration <= _maxPeriod, "invalid period");
        // update the policy's URI
        _policyManager.setPolicyInfo(policyID, policyholder, positionContract, coverAmount, newExpirationBlock, purchasePrice);
        emit PolicyExtended(policyID);
    }

    /**
     * @notice Extend a policy and update its cover amount.
     * User may need to pay **ETH** for increased cover amount or receive a refund for decreased cover amount.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     * @param coverAmount The new value to cover in **ETH**. Will only cover up to the appraised value.
     * @param extension The length of extension in blocks.
     */
    function updatePolicy(uint256 policyID, uint256 coverAmount, uint40 extension) external payable override nonReentrant whileUnpaused {
        (address policyholder, address product, address positionContract, uint256 previousCoverAmount, uint40 previousExpirationBlock, uint24 purchasePrice) = _policyManager.getPolicyInfo(policyID);
        require(policyholder == msg.sender,"!policyholder");
        require(product == address(this), "wrong product");
        require(previousExpirationBlock >= block.number, "policy is expired");

        // appraise the position
        uint256 positionAmount = appraisePosition(policyholder, positionContract);
        coverAmount = min(positionAmount, coverAmount);
        require(coverAmount > 0, "zero position value");

        // check that the product can still provide coverage
        {
        uint256 maxCover = maxCoverAmount();
        uint256 maxUserCover = maxCover / _maxCoverPerUserDivisor;
        require(_activeCoverAmount + coverAmount - previousCoverAmount <= maxCover, "max covered amount is reached");
        require(coverAmount <= maxUserCover, "over max cover single user");
        }
        // add new block extension
        uint40 newExpirationBlock = previousExpirationBlock + extension;

        // check if duration is valid
        uint40 duration = newExpirationBlock - uint40(block.number);
        require(duration >= _minPeriod && duration <= _maxPeriod, "invalid period");

        // update policy info
        _policyManager.setPolicyInfo(policyID, policyholder, positionContract, coverAmount, newExpirationBlock, _price);

        // calculate premium needed for new cover amount as if policy is bought now
        uint256 newPremium = coverAmount * duration * _price / 1e12;

        // calculate premium already paid based on current policy
        uint256 paidPremium = previousCoverAmount * (previousExpirationBlock - uint40(block.number)) * purchasePrice / 1e12;

        if (newPremium >= paidPremium) {
            uint256 premium = newPremium - paidPremium;
            require(msg.value >= premium, "insufficient payment");
            if(msg.value > premium) payable(msg.sender).transfer(msg.value - premium);
            ITreasury(payable(_registry.treasury())).routePremiums{value: premium}();
        } else {
            if(msg.value > 0) payable(msg.sender).transfer(msg.value);
            uint256 refund = paidPremium - newPremium;
            ITreasury(payable(_registry.treasury())).refund(msg.sender, refund);
        }
        emit PolicyUpdated(policyID);
    }

    /**
     * @notice Cancel and burn a policy.
     * User will receive a refund for the remaining blocks.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     */
    function cancelPolicy(uint256 policyID) external override nonReentrant {
        (address policyholder, address product, , uint256 coverAmount, uint40 expirationBlock, uint24 purchasePrice) = _policyManager.getPolicyInfo(policyID);
        require(policyholder == msg.sender,"!policyholder");
        require(product == address(this), "wrong product");

        uint40 blocksLeft = expirationBlock - uint40(block.number);
        uint256 refundAmount = blocksLeft * coverAmount * purchasePrice / 1e12;
        _policyManager.burn(policyID);
        ITreasury(payable(_registry.treasury())).refund(msg.sender, refundAmount);
        _activeCoverAmount -= coverAmount;
        emit PolicyCanceled(policyID);
    }

    /**
     * @notice Submit a claim.
     * The user can only submit one claim per policy and the claim must be signed by an authorized signer.
     * If successful the policy is burnt and a new claim is created.
     * The new claim will be in [`ClaimsEscrow`](../ClaimsEscrow) and have the same ID as the policy.
     * Can only be called by the policyholder.
     * @param policyID The policy that suffered a loss.
     * @param amountOut The amount the user will receive.
     * @param deadline Transaction must execute before this timestamp.
     * @param signature Signature from the signer.
     */
    function submitClaim(
        uint256 policyID,
        uint256 amountOut,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        // validate inputs
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp <= deadline, "expired deadline");
        (address policyholder, address product, , , , ) = _policyManager.getPolicyInfo(policyID);
        require(policyholder == msg.sender, "!policyholder");
        require(product == address(this), "wrong product");
        // verify signature
        {
        bytes32 structHash = keccak256(abi.encode(_SUBMIT_CLAIM_TYPEHASH, policyID, amountOut, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);
        require(_isAuthorizedSigner[signer], "invalid signature");
        }
        // burn policy
        _policyManager.burn(policyID);
        // submit claim to ClaimsEscrow
        IClaimsEscrow(payable(_registry.claimsEscrow())).receiveClaim(policyID, policyholder, amountOut);
        emit ClaimSubmitted(policyID);
    }

    /***************************************
    QUOTE VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice Calculate the value of a user's position in **ETH**.
     * Every product will have a different mechanism to determine a user's total position in that product's protocol.
     * @dev It should validate that the `positionContract` belongs to the protocol and revert if it doesn't.
     * @param policyholder The owner of the position.
     * @param positionContract The address of the smart contract the `policyholder` has their position in (e.g., for `UniswapV2Product` this would be the Pair's address).
     * @return positionAmount The value of the position.
     */
    function appraisePosition(address policyholder, address positionContract) public view virtual override returns (uint256 positionAmount);

    /**
     * @notice Calculate a premium quote for a policy.
     * @param policyholder The holder of the position to cover.
     * @param positionContract The address of the exact smart contract the policyholder has their position in (e.g., for UniswapProduct this would be Pair's address).
     * @param coverAmount The value to cover in **ETH**.
     * @param blocks The length for policy.
     * @return premium The quote for their policy in **Wei**.
     */
    // solhint-disable-next-line no-unused-vars
    function getQuote(address policyholder, address positionContract, uint256 coverAmount, uint40 blocks) external view override returns (uint256 premium){
        return coverAmount * blocks * _price / 1e12;
    }

    /**
     * The address of the current [`ExchangeQuoter`](../interface/IExchangeQuoter).
     * @return quoter_ Address of the quoter.
     */
    function quoter() external view returns (address quoter_) {
        return address(_quoter);
    }
    /***************************************
    GLOBAL VIEW FUNCTIONS
    ***************************************/

    /// @notice Price in wei per 1e12 wei of coverage per block.
    function price() external view override returns (uint24) {
        return _price;
    }

    /// @notice The minimum policy period in blocks.
    function minPeriod() external view override returns (uint40) {
        return _minPeriod;
    }

    /// @notice The maximum policy period in blocks.
    function maxPeriod() external view override returns (uint40) {
        return _maxPeriod;
    }

    /**
     * @notice The maximum sum of position values that can be covered by this product.
     * @return maxCover The max cover amount.
     */
    function maxCoverAmount() public view override returns (uint256 maxCover) {
        return IRiskManager(_registry.riskManager()).maxCoverAmount(address(this));
    }

    /**
     * @notice The maximum cover amount for a single policy.
     * @return maxCover The max cover amount per user.
     */
    function maxCoverPerUser() external view override returns (uint256 maxCover) {
        return maxCoverAmount() / _maxCoverPerUserDivisor;
    }

    /// @notice The max cover amount divisor for per user (maxCover / divisor = maxCoverPerUser).
    function maxCoverPerUserDivisor() external view override returns (uint32) {
        return _maxCoverPerUserDivisor;
    }
    /// @notice Covered platform.
    /// A platform contract which locates contracts that are covered by this product.
    /// (e.g., `UniswapProduct` will have `Factory` as `coveredPlatform` contract, because every `Pair` address can be located through `getPool()` function).
    function coveredPlatform() external view override returns (address) {
        return _coveredPlatform;
    }
    /// @notice The total policy count this product sold.
    function productPolicyCount() external view override returns (uint256) {
        return _productPolicyCount;
    }
    /// @notice The current amount covered (in wei).
    function activeCoverAmount() external view override returns (uint256) {
        return _activeCoverAmount;
    }

    /**
     * @notice Returns the name of the product.
     * @return productName The name of the product.
     */
    function name() external view virtual override returns (string memory productName) {
        return _productName;
    }

    /// @notice Cannot buy new policies while paused. (Default is False)
    function paused() external view override returns (bool) {
        return _paused;
    }

    /// @notice Address of the [`PolicyManager`](../PolicyManager).
    function policyManager() external view override returns (address) {
        return address(_policyManager);
    }

    /**
     * @notice Returns true if the given account is authorized to sign claims.
     * @param account Potential signer to query.
     * @return status True if is authorized signer.
     */
     function isAuthorizedSigner(address account) external view override returns (bool status) {
        return _isAuthorizedSigner[account];
     }

    /***************************************
    MUTATOR FUNCTIONS
    ***************************************/

    /**
     * @notice Updates the product's book-keeping variables.
     * Can only be called by the [`PolicyManager`](../PolicyManager).
     * @param coverDiff The change in active cover amount.
     */
    function updateActiveCoverAmount(int256 coverDiff) external override {
        require(msg.sender == address(_policyManager), "!policymanager");
        _activeCoverAmount = add(_activeCoverAmount, coverDiff);
    }

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Sets the price for this product.
     * @param price_ Price in wei per 1e12 wei of coverage per block.
     */
    function setPrice(uint24 price_) external override onlyGovernance {
        _price = price_;
    }

    /**
     * @notice Sets the minimum number of blocks a policy can be purchased for.
     * @param minPeriod_ The minimum number of blocks.
     */
    function setMinPeriod(uint40 minPeriod_) external override onlyGovernance {
        _minPeriod = minPeriod_;
    }

    /**
     * @notice Sets the maximum number of blocks a policy can be purchased for.
     * @param maxPeriod_ The maximum number of blocks
     */
    function setMaxPeriod(uint40 maxPeriod_) external override onlyGovernance {
        _maxPeriod = maxPeriod_;
    }

    /**
     * @notice Sets the max cover amount divisor per user (maxCover / divisor = maxCoverPerUser).
     * @param maxCoverPerUserDivisor_ The new divisor.
     */
    function setMaxCoverPerUserDivisor(uint32 maxCoverPerUserDivisor_) external override onlyGovernance {
        _maxCoverPerUserDivisor = maxCoverPerUserDivisor_;
    }

    /**
     * @notice Sets a new ExchangeQuoter.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param quoter_ The new quoter address.
     */
    function setExchangeQuoter(address quoter_) external onlyGovernance {
        _quoter = IExchangeQuoter(quoter_);
    }

    /**
     * @notice Adds a new signer that can authorize claims.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param signer The signer to add.
     */
    function addSigner(address signer) external onlyGovernance {
        _isAuthorizedSigner[signer] = true;
        emit SignerAdded(signer);
    }

    /**
     * @notice Removes a signer.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param signer The signer to remove.
     */
    function removeSigner(address signer) external onlyGovernance {
        _isAuthorizedSigner[signer] = false;
        emit SignerRemoved(signer);
    }

    /**
     * @notice Pauses or unpauses buying and extending policies.
     * Cancelling policies and submitting claims are unaffected by pause.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @dev Used for security and to gracefully phase out old products.
     * @param paused_ True to pause, false to unpause.
     */
    function setPaused(bool paused_) external onlyGovernance {
        _paused = paused_;
    }

    /**
     * @notice Changes the covered platform.
     * The function should be used if the the protocol changes their registry but keeps the children contracts.
     * A new version of the protocol will likely require a new Product.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param coveredPlatform_ The platform to cover.
     */
    function setCoveredPlatform(address coveredPlatform_) public virtual override onlyGovernance {
        _coveredPlatform = coveredPlatform_;
    }

    /**
     * @notice Changes the policy manager.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param policyManager_ The new policy manager.
     */
    function setPolicyManager(address policyManager_) external override onlyGovernance {
        _policyManager = IPolicyManager(policyManager_);
    }

    /***************************************
    HELPER FUNCTIONS
    ***************************************/

    /**
     * @notice The function is used to add two numbers.
     * @param a The first number as a uint256.
     * @param b The second number as an int256.
     * @return c The sum as a uint256.
     */
    function add(uint256 a, int256 b) internal pure returns (uint256 c) {
        return (b > 0)
            ? a + uint256(b)
            : a - uint256(-b);
    }

    /**
     * @notice The function is used to return minimum number between two numbers..
     * @param a The first number as a uint256.
     * @param b The second number as an int256.
     * @return c The min as a uint256.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

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
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
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
abstract contract ReentrancyGuard {
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

    constructor() {
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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ECDSA.sol";

/**
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP 712] is a standard for hashing and signing of typed structured data.
 *
 * The encoding specified in the EIP is very generic, and such a generic implementation in Solidity is not feasible,
 * thus this contract does not implement the encoding itself. Protocols need to implement the type-specific encoding
 * they need in their contracts using a combination of `abi.encode` and `keccak256`.
 *
 * This contract implements the EIP 712 domain separator ({_domainSeparatorV4}) that is used as part of the encoding
 * scheme, and the final step of the encoding to obtain the message digest that is then signed via ECDSA
 * ({_hashTypedDataV4}).
 *
 * The implementation of the domain separator was designed to be as efficient as possible while still properly updating
 * the chain id to protect against replay attacks on an eventual fork of the chain.
 *
 * NOTE: This contract implements the version of the encoding known as "v4", as implemented by the JSON RPC method
 * https://docs.metamask.io/guide/signing-data.html[`eth_signTypedDataV4` in MetaMask].
 *
 * _Available since v3.4._
 */
abstract contract EIP712 {
    /* solhint-disable var-name-mixedcase */
    // Cache the domain separator as an immutable value, but also store the chain id that it corresponds to, in order to
    // invalidate the cached domain separator if the chain id changes.
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    /* solhint-enable var-name-mixedcase */

    /**
     * @dev Initializes the domain separator and parameter caches.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP 712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    constructor(string memory name, string memory version) {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(typeHash, hashedName, hashedVersion);
        _TYPE_HASH = typeHash;
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(this)));
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

import "./interface/IGovernable.sol";

/**
 * @title Governable
 * @author solace.fi
 * @notice Enforces access control for important functions to [**governor**](/docs/user-docs/Governance).
 *
 * Many contracts contain functionality that should only be accessible to a privileged user. The most common access control pattern is [OpenZeppelin's `Ownable`](https://docs.openzeppelin.com/contracts/4.x/access-control#ownership-and-ownable). We instead use `Governable` with a few key differences:
 * - Transferring the governance role is a two step process. The current governance must [`setGovernance(newGovernance_)`](#setgovernance) then the new governance must [`acceptGovernance()`](#acceptgovernance). This is to safeguard against accidentally setting ownership to the wrong address and locking yourself out of your contract.
 * - `governance` is a constructor argument instead of `msg.sender`. This is especially useful when deploying contracts via a [`SingletonFactory`](./interface/ISingletonFactory)
 */
contract Governable is IGovernable {

    /***************************************
    GLOBAL VARIABLES
    ***************************************/

    // Governor.
    address private _governance;

    // governance to take over.
    address private _newGovernance;

    /**
     * @notice Constructs the governable contract.
     * @param governance_ The address of the [governor](/docs/user-docs/Governance).
     */
    constructor(address governance_) {
        _governance = governance_;
    }

    /***************************************
    MODIFIERS
    ***************************************/

    // can only be called by governor
    modifier onlyGovernance() {
        require(msg.sender == _governance, "!governance");
        _;
    }

    // can only be called by new governor
    modifier onlyNewGovernance() {
        require(msg.sender == _newGovernance, "!governance");
        _;
    }

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    /// @notice Address of the current governor.
    function governance() public view override returns (address) {
        return _governance;
    }

    /// @notice Address of the governor to take over.
    function newGovernance() public view override returns (address) {
        return _newGovernance;
    }

    /***************************************
    MUTATOR FUNCTIONS
    ***************************************/

    /**
     * @notice Initiates transfer of the governance role to a new governor.
     * Transfer is not complete until the new governor accepts the role.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param newGovernance_ The new governor.
     */
    function setGovernance(address newGovernance_) external override onlyGovernance {
        _newGovernance = newGovernance_;
    }

    /**
     * @notice Accepts the governance role.
     * Can only be called by the new governor.
     */
    function acceptGovernance() external override onlyNewGovernance {
        _governance = _newGovernance;
        _newGovernance = address(0x0);
        emit GovernanceTransferred(_governance);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
 * @title IPolicyManager
 * @author solace.fi
 * @notice The **PolicyManager** manages the creation of new policies and modification of existing policies.
 *
 * Most users will not interact with **PolicyManager** directly. To buy, modify, or cancel policies, users should use the respective [**product**](../products/BaseProduct) for the position they would like to cover. Use **PolicyManager** to view policies.
 *
 * Policies are [**ERC721s**](https://docs.openzeppelin.com/contracts/4.x/api/token/erc721#ERC721).
 */
interface IPolicyManager is IERC721Enumerable /*, IERC721Metadata*/ {

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when a policy is created.
    event PolicyCreated(uint256 policyID);
    /// @notice Emitted when a policy is burned.
    event PolicyBurned(uint256 policyID);
    /// @notice Emitted when a new product is added.
    event ProductAdded(address product);
    /// @notice Emitted when a new product is removed.
    event ProductRemoved(address product);

    /***************************************
    POLICY VIEW FUNCTIONS
    ***************************************/

    /// @notice PolicyInfo struct.
    struct PolicyInfo {
        uint256 coverAmount;
        address policyholder;
        uint40 expirationBlock;
        address product;
        uint24 price;
        address positionContract;
    }

    /**
     * @notice Information about a policy.
     * @param policyID The policy ID to return info.
     * @return info info in a struct.
     */
    function policyInfo(uint256 policyID) external view returns (PolicyInfo memory info);

    /**
     * @notice Information about a policy.
     * @param policyID The policy ID to return info.
     * @return policyholder The address of the policy holder.
     * @return product The product of the policy.
     * @return positionContract The covered contract for the policy.
     * @return coverAmount The amount covered for the policy.
     * @return expirationBlock The expiration block of the policy.
     * @return price The price of the policy.
     */
    function getPolicyInfo(uint256 policyID) external view returns (address policyholder, address product, address positionContract, uint256 coverAmount, uint40 expirationBlock, uint24 price);

    /**
     * @notice The holder of the policy.
     * @param policyID The policy ID.
     * @return policyholder The address of the policy holder.
     */
    function getPolicyholder(uint256 policyID) external view returns (address policyholder);

    /**
     * @notice The product used to purchase the policy.
     * @param policyID The policy ID.
     * @return product The product of the policy.
     */
    function getPolicyProduct(uint256 policyID) external view returns (address product);

    /**
     * @notice The position contract the policy covers.
     * @param policyID The policy ID.
     * @return positionContract The position contract of the policy.
     */
    function getPolicyPositionContract(uint256 policyID) external view returns (address positionContract);

    /**
     * @notice The expiration block of the policy.
     * @param policyID The policy ID.
     * @return expirationBlock The expiration block of the policy.
     */
    function getPolicyExpirationBlock(uint256 policyID) external view returns (uint40 expirationBlock);

    /**
     * @notice The cover amount of the policy.
     * @param policyID The policy ID.
     * @return coverAmount The cover amount of the policy.
     */
    function getPolicyCoverAmount(uint256 policyID) external view returns (uint256 coverAmount);

    /**
     * @notice The cover price in wei per block per wei multiplied by 1e12.
     * @param policyID The policy ID.
     * @return price The price of the policy.
     */
    function getPolicyPrice(uint256 policyID) external view returns (uint24 price);

    /**
     * @notice Lists all policies for a given policy holder.
     * @param policyholder The address of the policy holder.
     * @return policyIDs The list of policy IDs that the policy holder has in any order.
     */
    function listPolicies(address policyholder) external view returns (uint256[] memory policyIDs);

    /*
     * @notice These functions can be used to check a policys stage in the lifecycle.
     * There are three major lifecycle events:
     *   1 - policy is bought (aka minted)
     *   2 - policy expires
     *   3 - policy is burnt (aka deleted)
     * There are four stages:
     *   A - pre-mint
     *   B - pre-expiration
     *   C - post-expiration
     *   D - post-burn
     * Truth table:
     *               A B C D
     *   exists      0 1 1 0
     *   isActive    0 1 0 0
     *   hasExpired  0 0 1 0

    /**
     * @notice Checks if a policy exists.
     * @param policyID The policy ID.
     * @return status True if the policy exists.
     */
    function exists(uint256 policyID) external view returns (bool status);

    /**
     * @notice Checks if a policy is active.
     * @param policyID The policy ID.
     * @return status True if the policy is active.
     */
    function policyIsActive(uint256 policyID) external view returns (bool);

    /**
     * @notice Checks whether a given policy is expired.
     * @param policyID The policy ID.
     * @return status True if the policy is expired.
     */
    function policyHasExpired(uint256 policyID) external view returns (bool);

    /// @notice The total number of policies ever created.
    function totalPolicyCount() external view returns (uint256 count);

    /// @notice The address of the [`PolicyDescriptor`](./PolicyDescriptor) contract.
    function policyDescriptor() external view returns (address);

    /***************************************
    POLICY MUTATIVE FUNCTIONS
    ***************************************/

    /**
     * @notice Creates a new policy.
     * Can only be called by **products**.
     * @param policyholder The receiver of new policy token.
     * @param positionContract The contract address of the position.
     * @param expirationBlock The policy expiration block number.
     * @param coverAmount The policy coverage amount (in wei).
     * @param price The coverage price.
     * @return policyID The policy ID.
     */
    function createPolicy(
        address policyholder,
        address positionContract,
        uint256 coverAmount,
        uint40 expirationBlock,
        uint24 price
    ) external returns (uint256 policyID);

    /**
     * @notice Modifies a policy.
     * Can only be called by **products**.
     * @param policyID The policy ID.
     * @param policyholder The receiver of new policy token.
     * @param positionContract The contract address where the position is covered.
     * @param expirationBlock The policy expiration block number.
     * @param coverAmount The policy coverage amount (in wei).
     * @param price The coverage price.
     */
    function setPolicyInfo(uint256 policyID, address policyholder, address positionContract, uint256 coverAmount, uint40 expirationBlock, uint24 price) external;

    /**
     * @notice Burns expired or cancelled policies.
     * Can only be called by **products**.
     * @param policyID The ID of the policy to burn.
     */
    function burn(uint256 policyID) external;

    /**
     * @notice Burns expired policies.
     * @param policyIDs The list of expired policies.
     */
    function updateActivePolicies(uint256[] calldata policyIDs) external;

    /***************************************
    PRODUCT VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice Checks is an address is an active product.
     * @param product The product to check.
     * @return status True if the product is active.
     */
    function productIsActive(address product) external view returns (bool status);

    /**
     * @notice Returns the number of products.
     * @return count The number of products.
     */
    function numProducts() external view returns (uint256 count);

    /**
     * @notice Returns the product at the given index.
     * @param productNum The index to query.
     * @return product The address of the product.
     */
    function getProduct(uint256 productNum) external view returns (address product);

    /***************************************
    OTHER VIEW FUNCTIONS
    ***************************************/

    function activeCoverAmount() external view returns (uint256);

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Adds a new product.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param product the new product
     */
    function addProduct(address product) external;

    /**
     * @notice Removes a product.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param product the product to remove
     */
    function removeProduct(address product) external;


    /**
     * @notice Set the token descriptor.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param policyDescriptor The new token descriptor address.
     */
    function setPolicyDescriptor(address policyDescriptor) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;


/**
 * @title IRiskManager
 * @author solace.fi
 * @notice Calculates the acceptable risk, sellable cover, and capital requirements of Solace products and capital pool.
 *
 * The total amount of sellable coverage is proportional to the assets in the [**risk backing capital pool**](../Vault). The max cover is split amongst products in a weighting system. [**Governance**](/docs/user-docs/Governance). can change these weights and with it each product's sellable cover.
 *
 * The minimum capital requirement is proportional to the amount of cover sold to [active policies](../PolicyManager).
 *
 * Solace can use leverage to sell more cover than the available capital. The amount of leverage is stored as [`partialReservesFactor`](#partialreservesfactor) and is settable by [**governance**](/docs/user-docs/Governance).
 */
interface IRiskManager {

    /***************************************
    MAX COVER VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice The maximum amount of cover that Solace as a whole can sell.
     * @return cover The max amount of cover in wei.
     */
    function maxCover() external view returns (uint256 cover);

    /**
     * @notice The maximum amount of cover that a product can sell.
     * @param prod The product that wants to sell cover.
     * @return cover The max amount of cover in wei.
     */
    function maxCoverAmount(address prod) external view returns (uint256 cover);

    /**
     * @notice Return the number of registered products.
     * @return count Number of products.
     */
    function numProducts() external view returns (uint256 count);

    /**
     * @notice Return the product at an index.
     * @dev Enumerable `[0, numProducts-1]`.
     * @param index Index to query.
     * @return prod The product address.
     */
    function product(uint256 index) external view returns (address prod);

    /**
     * @notice Returns the weight of a product.
     * @param prod Product to query.
     * @return mass The product's weight.
     */
    function weight(address prod) external view returns (uint32 mass);

    /**
     * @notice Returns the sum of weights.
     * @return sum WeightSum.
     */
    function weightSum() external view returns (uint32 sum);

    /***************************************
    MIN CAPITAL VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice The minimum amount of capital required to safely cover all policies.
     * @return mcr The minimum capital requirement.
     */
    function minCapitalRequirement() external view returns (uint256 mcr);

    /**
     * @notice Multiplier for minimum capital requirement.
     * @return factor Partial reserves factor in BPS.
     */
    function partialReservesFactor() external view returns (uint16 factor);

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Adds a new product and sets its weight.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param product_ Address of new product.
     * @param weight_ The products weight.
     */
    function addProduct(address product_, uint32 weight_) external;

    /**
     * @notice Sets the products and their weights.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param products_ The products.
     * @param weights_ The product weights.
     */
    function setProductWeights(address[] calldata products_, uint32[] calldata weights_) external;

    /**
     * @notice Sets the partial reserves factor.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param partialReservesFactor_ New partial reserves factor in BPS.
     */
    function setPartialReservesFactor(uint16 partialReservesFactor_) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;


/**
 * @title ITreasury
 * @author solace.fi
 * @notice The war chest of Castle Solace.
 *
 * As policies are purchased, premiums will flow from [**policyholders**](/docs/user-docs/Policy%20Holders) to the `Treasury`. By default `Treasury` reroutes 100% of the premiums into the [`Vault`](../Vault) where it is split amongst the [**capital providers**](/docs/user-docs/Capital%20Providers).
 *
 * If a [**policyholder**](/docs/user-docs/Policy%20Holders) updates or cancels a policy they may receive a refund. Refunds will be paid out from the [`Vault`](../Vault). If there are not enough funds to pay out the refund in whole, the [`unpaidRefunds()`](#unpaidrefunds) will be tracked and can be retrieved later via [`withdraw()`](#withdraw).
 *
 * [**Governance**](/docs/user-docs/Governance) can change the premium recipients via [`setPremiumRecipients()`](#setpremiumrecipients). This can be used to add new building blocks to Castle Solace or enact a protocol fee. Premiums can be stored in the `Treasury` and managed with a number of functions.
 */
interface ITreasury {

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when a token is spent.
    event FundsSpent(address token, uint256 amount, address recipient);
    /// @notice Emitted when premium recipients are set.
    event RecipientsSet();

    /***************************************
    FUNDS IN
    ***************************************/

    /**
     * @notice Routes the **premiums** to the `recipients`.
     * Each recipient will receive a `recipientWeight / weightSum` portion of the premiums.
     * Will be called by products with `msg.value = premium`.
     */
    function routePremiums() external payable;

    /**
     * @notice Number of premium recipients.
     * @return count The number of premium recipients.
     */
    function numPremiumRecipients() external view returns (uint256 count);

    /**
     * @notice Gets the premium recipient at `index`.
     * @param index Index to query, enumerable `[0, numPremiumRecipients()-1]`.
     * @return recipient The receipient address.
     */
    function premiumRecipient(uint256 index) external view returns (address recipient);

    /**
     * @notice Gets the weight of the recipient.
     * @param index Index to query, enumerable `[0, numPremiumRecipients()]`.
     * @return weight The recipient weight.
     */
    function recipientWeight(uint256 index) external view returns (uint32 weight);

    /**
     * @notice Gets the sum of all premium recipient weights.
     * @return weight The sum of weights.
     */
    function weightSum() external view returns (uint32 weight);

    /***************************************
    FUNDS OUT
    ***************************************/

    /**
     * @notice Refunds some **ETH** to the user.
     * Will attempt to send the entire `amount` to the `user`.
     * If there is not enough available at the moment, it is recorded and can be pulled later via [`withdraw()`](#withdraw).
     * Can only be called by active products.
     * @param user The user address to send refund amount.
     * @param amount The amount to send the user.
     */
    function refund(address user, uint256 amount) external;

    /**
     * @notice The amount of **ETH** that a user is owed if any.
     * @param user The user.
     * @return amount The amount.
     */
    function unpaidRefunds(address user) external view returns (uint256 amount);

    /**
     * @notice Transfers the unpaid refunds to the user.
     */
    function withdraw() external;

    /***************************************
    FUND MANAGEMENT
    ***************************************/

    /**
     * @notice Sets the premium recipients and their weights.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param recipients The premium recipients, plus an implicit `address(this)` at the end.
     * @param weights The recipient weights.
     */
    function setPremiumRecipients(address payable[] calldata recipients, uint32[] calldata weights) external;

    /**
     * @notice Spends an **ERC20** token or **ETH**.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param token The address of the token to spend.
     * @param amount The amount of the token to spend.
     * @param recipient The address of the token receiver.
     */
    function spend(address token, uint256 amount, address recipient) external;

    /**
     * @notice Manually swaps a token.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param path The path of pools to take.
     * @param amountIn The amount to swap.
     * @param amountOutMinimum The minimum about to receive.
     */
    function swap(bytes memory path, uint256 amountIn, uint256 amountOutMinimum) external;

    /**
     * @notice Wraps some **ETH** into **WETH**.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param amount The amount to wrap.
     */
    function wrap(uint256 amount) external;

    /**
     * @notice Unwraps some **WETH** into **ETH**.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param amount The amount to unwrap.
     */
    function unwrap(uint256 amount) external;

    /***************************************
    FALLBACK FUNCTIONS
    ***************************************/

    /**
     * @notice Fallback function to allow contract to receive **ETH**.
     */
    receive() external payable;

    /**
     * @notice Fallback function to allow contract to receive **ETH**.
     */
    fallback () external payable;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;


/**
 * @title IClaimsEscrow
 * @author solace.fi
 * @notice The payer of claims.
 *
 * [**Policyholders**](/docs/user-docs/Policy%20Holders) can submit claims through their policy's product contract, in the process burning the policy and converting it to a claim.
 *
 * The [**policyholder**](/docs/user-docs/Policy%20Holders) will then need to wait for a [`cooldownPeriod()`](#cooldownperiod) after which they can [`withdrawClaimsPayout()`](#withdrawclaimspayout).
 *
 * To pay the claims funds are taken from the [`Vault`](../Vault) and deducted from [**capital provider**](/docs/user-docs/Capital%20Providers) earnings.
 *
 * Claims are **ERC721**s and abbreviated as **SCT**.
 */
interface IClaimsEscrow {

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when a new claim is received.
    event ClaimReceived(uint256 indexed claimID, address indexed claimant, uint256 indexed amount);
    /// @notice Emitted when a claim is paid out.
    event ClaimWithdrawn(uint256 indexed claimID, address indexed claimant, uint256 indexed amount);

    /***************************************
    CLAIM CREATION
    ***************************************/

    /**
     * @notice Receives a claim.
     * The new claim will have the same ID that the policy had and will be withdrawable after a cooldown period.
     * Only callable by active products.
     * @param policyID ID of policy to claim.
     * @param claimant Address of the claimant.
     * @param amount Amount of ETH to claim.
     */
    function receiveClaim(uint256 policyID, address claimant, uint256 amount) external payable;

    /***************************************
    CLAIM PAYOUT
    ***************************************/

    /**
     * @notice Allows claimants to withdraw their claims payout.
     * Will attempt to withdraw the full amount then burn the claim if successful.
     * Only callable by the claimant.
     * Only callable after the cooldown period has elapsed (from the time the claim was approved and processed).
     * @param claimID The ID of the claim to withdraw payout for.
     */
    function withdrawClaimsPayout(uint256 claimID) external;

    /***************************************
    CLAIM VIEW
    ***************************************/

    /// @notice Claim struct.
    struct Claim {
        uint256 amount;
        uint256 receivedAt; // used to determine withdrawability after cooldown period
    }

    /**
     * @notice Gets information about a claim.
     * @param claimID Claim to query.
     * @return info Claim info as struct.
     */
    function claim(uint256 claimID) external view returns (Claim memory info);

    /**
     * @notice Gets information about a claim.
     * @param claimID Claim to query.
     * @return amount Claim amount in ETH.
     * @return receivedAt Time claim was received at.
     */
    function getClaim(uint256 claimID) external view returns (uint256 amount, uint256 receivedAt);

    /**
     * @notice Returns true if the claim exists.
     * @param claimID The ID to check.
     * @return status True if it exists, false if not.
     */
    function exists(uint256 claimID) external view returns (bool status);

    /**
     * @notice Returns true if the payout of the claim can be withdrawn.
     * @param claimID The ID to check.
     * @return status True if it is withdrawable, false if not.
     */
    function isWithdrawable(uint256 claimID) external view returns (bool status);

    /**
     * @notice The amount of time left until the payout is withdrawable.
     * @param claimID The ID to check.
     * @return time The duration in seconds.
     */
    function timeLeft(uint256 claimID) external view returns (uint256 time);

    /**
     * @notice List a user's claims.
     * @param claimant User to check.
     * @return claimIDs List of claimIDs.
     */
    function listClaims(address claimant) external view returns (uint256[] memory claimIDs);

    /***************************************
    GLOBAL VIEWS
    ***************************************/

    /// @notice Tracks how much **ETH** is required to payout all claims.
    function totalClaimsOutstanding() external view returns (uint256);

    /// @notice The duration of time in seconds the user must wait between submitting a claim and withdrawing the payout.
    function cooldownPeriod() external view returns (uint256);

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Adjusts the value of a claim.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param claimID The claim to adjust.
     * @param value The new payout of the claim.
     */
    function adjustClaim(uint256 claimID, uint256 value) external;

    /**
     * @notice Returns **ETH** to the [`Vault`](../Vault).
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param amount Amount to pull.
     */
    function returnEth(uint256 amount) external;

    /**
     * @notice Set the cooldown duration.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param cooldownPeriod_ New cooldown duration in seconds
     */
    function setCooldownPeriod(uint256 cooldownPeriod_) external;

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/


    /***************************************
    FALLBACK FUNCTIONS
    ***************************************/

    /**
     * Receive function. Deposits eth.
     */
    receive() external payable;

    /**
     * Fallback function. Deposits eth.
     */
    fallback () external payable;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

/**
 * @title IRegistry
 * @author solace.fi
 * @notice Tracks the contracts of the Solaverse.
 *
 * [**Governance**](/docs/user-docs/Governance) can set the contract addresses and anyone can look them up.
 *
 * Note that `Registry` doesn't track all Solace contracts. Farms are tracked in [`Master`](../Master), Products are tracked in [`PolicyManager`](../PolicyManager), and the `Registry` is untracked.
 */
interface IRegistry {

    /***************************************
    EVENTS
    ***************************************/

    // Emitted when WETH is set.
    event WethSet(address weth);
    // Emitted when Vault is set.
    event VaultSet(address vault);
    // Emitted when ClaimsEscrow is set.
    event ClaimsEscrowSet(address claimsEscrow);
    // Emitted when Treasury is set.
    event TreasurySet(address treasury);
    // Emitted when PolicyManager is set.
    event PolicyManagerSet(address policyManager);
    // Emitted when RiskManager is set.
    event RiskManagerSet(address riskManager);
    // Emitted when Solace Token is set.
    event SolaceSet(address solace);
    // Emitted when Master is set.
    event MasterSet(address master);
    // Emitted when Locker is set.
    event LockerSet(address locker);

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice Gets the [**WETH**](../WETH9) contract.
     * @return weth_ The address of the [**WETH**](../WETH9) contract.
     */
    function weth() external view returns (address);

    /**
     * @notice Gets the [`Vault`](../Vault) contract.
     * @return vault_ The address of the [`Vault`](../Vault) contract.
     */
    function vault() external view returns (address);

    /**
     * @notice Gets the [`ClaimsEscrow`](../ClaimsEscrow) contract.
     * @return claimsEscrow_ The address of the [`ClaimsEscrow`](../ClaimsEscrow) contract.
     */
    function claimsEscrow() external view returns (address);

    /**
     * @notice Gets the [`Treasury`](../Treasury) contract.
     * @return treasury_ The address of the [`Treasury`](../Treasury) contract.
     */
    function treasury() external view returns (address);

    /**
     * @notice Gets the [`PolicyManager`](../PolicyManager) contract.
     * @return policyManager_ The address of the [`PolicyManager`](../PolicyManager) contract.
     */
    function policyManager() external view returns (address);

    /**
     * @notice Gets the [`RiskManager`](../RiskManager) contract.
     * @return riskManager_ The address of the [`RiskManager`](../RiskManager) contract.
     */
    function riskManager() external view returns (address);

    /**
     * @notice Gets the [**SOLACE**](../SOLACE) contract.
     * @return solace_ The address of the [**SOLACE**](../SOLACE) contract.
     */
    function solace() external view returns (address);

    /**
     * @notice Gets the [`Master`](../Master) contract.
     * @return master_ The address of the [`Master`](../Master) contract.
     */
    function master() external view returns (address);

    /**
     * @notice Gets the [`Locker`](../Locker) contract.
     * @return locker_ The address of the [`Locker`](../Locker) contract.
     */
    function locker() external view returns (address);

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Sets the [**WETH**](../WETH9) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param weth_ The address of the [**WETH**](../WETH9) contract.
     */
    function setWeth(address weth_) external;

    /**
     * @notice Sets the [`Vault`](../Vault) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param vault_ The address of the [`Vault`](../Vault) contract.
     */
    function setVault(address vault_) external;

    /**
     * @notice Sets the [`Claims Escrow`](../ClaimsEscrow) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param claimsEscrow_ The address of the [`Claims Escrow`](../ClaimsEscrow) contract.
     */
    function setClaimsEscrow(address claimsEscrow_) external;

    /**
     * @notice Sets the [`Treasury`](../Treasury) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param treasury_ The address of the [`Treasury`](../Treasury) contract.
     */
    function setTreasury(address treasury_) external;

    /**
     * @notice Sets the [`Policy Manager`](../PolicyManager) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param policyManager_ The address of the [`Policy Manager`](../PolicyManager) contract.
     */
    function setPolicyManager(address policyManager_) external;

    /**
     * @notice Sets the [`Risk Manager`](../RiskManager) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param riskManager_ The address of the [`Risk Manager`](../RiskManager) contract.
     */
    function setRiskManager(address riskManager_) external;

    /**
     * @notice Sets the [**SOLACE**](../SOLACE) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param solace_ The address of the [**SOLACE**](../SOLACE) contract.
     */
    function setSolace(address solace_) external;

    /**
     * @notice Sets the [`Master`](../Master) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param master_ The address of the [`Master`](../Master) contract.
     */
    function setMaster(address master_) external;

    /**
     * @notice Sets the [`Locker`](../Locker) contract.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param locker_ The address of the [`Locker`](../Locker) contract.
     */
    function setLocker(address locker_) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;


/**
 * @title IExchangeQuoter
 * @author solace.fi
 * @notice Calculates exchange rates for trades between ERC20 tokens and Ether.
 */
interface IExchangeQuoter {
    /**
     * @notice Calculates the exchange rate for an amount of token to eth.
     * @param token The token to give.
     * @param amount The amount to give.
     * @return amountOut The amount of eth received.
     */
    function tokenToEth(address token, uint256 amount) external view returns (uint256 amountOut);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

/**
 * @title IProduct
 * @author solace.fi
 * @notice Interface for product contracts
 */
interface IProduct {

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when a policy is created.
    event PolicyCreated(uint256 indexed policyID);
    /// @notice Emitted when a policy is extended.
    event PolicyExtended(uint256 indexed policyID);
    /// @notice Emitted when a policy is canceled.
    event PolicyCanceled(uint256 indexed policyID);
    /// @notice Emitted when a policy is updated.
    event PolicyUpdated(uint256 indexed policyID);
    /// @notice Emitted when a claim is submitted.
    event ClaimSubmitted(uint256 indexed policyID);

    /***************************************
    POLICYHOLDER FUNCTIONS
    ***************************************/

    /**
     * @notice Purchases and mints a policy on the behalf of the policyholder.
     * User will need to pay **ETH**.
     * @param policyholder Holder of the position to cover.
     * @param positionContract The contract address where the policyholder has a position to be covered.
     * @param coverAmount The value to cover in **ETH**. Will only cover up to the appraised value.
     * @param blocks The length (in blocks) for policy.
     * @return policyID The ID of newly created policy.
     */
    function buyPolicy(address policyholder, address positionContract, uint256 coverAmount, uint40 blocks) external payable returns (uint256 policyID);

    /**
     * @notice Increase or decrease the cover amount of the policy.
     * User may need to pay **ETH** for increased cover amount or receive a refund for decreased cover amount.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     * @param newCoverAmount The new value to cover in **ETH**. Will only cover up to the appraised value.
     */
    function updateCoverAmount(uint256 policyID, uint256 newCoverAmount) external payable;

    /**
     * @notice Extend a policy.
     * User will need to pay **ETH**.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     * @param extension The length of extension in blocks.
     */
    function extendPolicy(uint256 policyID, uint40 extension) external payable;

    /**
     * @notice Extend a policy and update its cover amount.
     * User may need to pay **ETH** for increased cover amount or receive a refund for decreased cover amount.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     * @param newCoverAmount The new value to cover in **ETH**. Will only cover up to the appraised value.
     * @param extension The length of extension in blocks.
     */
    function updatePolicy(uint256 policyID, uint256 newCoverAmount, uint40 extension) external payable;

    /**
     * @notice Cancel and burn a policy.
     * User will receive a refund for the remaining blocks.
     * Can only be called by the policyholder.
     * @param policyID The ID of the policy.
     */
    function cancelPolicy(uint256 policyID) external;

    /***************************************
    QUOTE VIEW FUNCTIONS
    ***************************************/

    /**
     * @notice Calculate the value of a user's position in **ETH**.
     * Every product will have a different mechanism to determine a user's total position in that product's protocol.
     * @dev It should validate that the `positionContract` belongs to the protocol and revert if it doesn't.
     * @param policyholder The owner of the position.
     * @param positionContract The address of the smart contract the `policyholder` has their position in (e.g., for `UniswapV2Product` this would be the Pair's address).
     * @return positionAmount The value of the position.
     */
    function appraisePosition(address policyholder, address positionContract) external view returns (uint256 positionAmount);

    /**
     * @notice Calculate a premium quote for a policy.
     * @param policyholder The holder of the position to cover.
     * @param positionContract The address of the exact smart contract the policyholder has their position in (e.g., for UniswapProduct this would be Pair's address).
     * @param coverAmount The value to cover in **ETH**.
     * @param blocks The length for policy.
     * @return premium The quote for their policy in **Wei**.
     */
    function getQuote(address policyholder, address positionContract, uint256 coverAmount, uint40 blocks) external view returns (uint256 premium);

    /***************************************
    GLOBAL VIEW FUNCTIONS
    ***************************************/

    /// @notice Price in wei per 1e12 wei of coverage per block.
    function price() external view returns (uint24);
    /// @notice The minimum policy period in blocks.
    function minPeriod() external view returns (uint40);
    /// @notice The maximum policy period in blocks.
    function maxPeriod() external view returns (uint40);
    /**
     * @notice The maximum sum of position values that can be covered by this product.
     * @return maxCoverAmount The max cover amount.
     */
    function maxCoverAmount() external view returns (uint256 maxCoverAmount);
    /**
     * @notice The maximum cover amount for a single policy.
     * @return maxCoverAmountPerUser The max cover amount per user.
     */
    function maxCoverPerUser() external view returns (uint256 maxCoverAmountPerUser);
    /// @notice The max cover amount divisor for per user (maxCover / divisor = maxCoverPerUser).
    function maxCoverPerUserDivisor() external view returns (uint32);
    /// @notice Covered platform.
    /// A platform contract which locates contracts that are covered by this product.
    /// (e.g., `UniswapProduct` will have `Factory` as `coveredPlatform` contract, because every `Pair` address can be located through `getPool()` function).
    function coveredPlatform() external view returns (address);
    /// @notice The total policy count this product sold.
    function productPolicyCount() external view returns (uint256);
    /// @notice The current amount covered (in wei).
    function activeCoverAmount() external view returns (uint256);

    /**
     * @notice Returns the name of the product.
     * Must be implemented by child contracts.
     * @return productName The name of the product.
     */
    function name() external view returns (string memory productName);

    /// @notice Cannot buy new policies while paused. (Default is False)
    function paused() external view returns (bool);

    /// @notice Address of the [`PolicyManager`](../PolicyManager).
    function policyManager() external view returns (address);

    /**
     * @notice Returns true if the given account is authorized to sign claims.
     * @param account Potential signer to query.
     * @return status True if is authorized signer.
     */
     function isAuthorizedSigner(address account) external view returns (bool status);

    /***************************************
    MUTATOR FUNCTIONS
    ***************************************/

    /**
     * @notice Updates the product's book-keeping variables.
     * Can only be called by the [`PolicyManager`](../PolicyManager).
     * @param coverDiff The change in active cover amount.
     */
    function updateActiveCoverAmount(int256 coverDiff) external;

    /***************************************
    GOVERNANCE FUNCTIONS
    ***************************************/

    /**
     * @notice Sets the price for this product.
     * @param price_ Price in wei per 1e12 wei of coverage per block.
     */
    function setPrice(uint24 price_) external;

    /**
     * @notice Sets the minimum number of blocks a policy can be purchased for.
     * @param minPeriod_ The minimum number of blocks.
     */
    function setMinPeriod(uint40 minPeriod_) external;

    /**
     * @notice Sets the maximum number of blocks a policy can be purchased for.
     * @param maxPeriod_ The maximum number of blocks
     */
    function setMaxPeriod(uint40 maxPeriod_) external;

    /**
     * @notice Sets the max cover amount divisor per user (maxCover / divisor = maxCoverPerUser).
     * @param maxCoverPerUserDivisor_ The new divisor.
     */
    function setMaxCoverPerUserDivisor(uint32 maxCoverPerUserDivisor_) external;

    /**
     * @notice Changes the covered platform.
     * This function is used if the the protocol changes their registry but keeps the children contracts.
     * A new version of the protocol will likely require a new **Product**.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param coveredPlatform_ The platform to cover.
     */
    function setCoveredPlatform(address coveredPlatform_) external;

    /**
     * @notice Changes the policy manager.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param policyManager_ The new policy manager.
     */
    function setPolicyManager(address policyManager_) external;
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
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Check the signature length
        // - case 65: r,s,v signature (standard)
        // - case 64: r,vs signature (cf https://eips.ethereum.org/EIPS/eip-2098) _Available since v4.1._
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return recover(hash, v, r, s);
        } else if (signature.length == 64) {
            bytes32 r;
            bytes32 vs;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            assembly {
                r := mload(add(signature, 0x20))
                vs := mload(add(signature, 0x40))
            }
            return recover(hash, r, vs);
        } else {
            revert("ECDSA: invalid signature length");
        }
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r` and `vs` short-signature fields separately.
     *
     * See https://eips.ethereum.org/EIPS/eip-2098[EIP-2098 short signatures]
     *
     * _Available since v4.2._
     */
    function recover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address) {
        bytes32 s;
        uint8 v;
        assembly {
            s := and(vs, 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            v := add(shr(255, vs), 27)
        }
        return recover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`, `r` and `s` signature fields separately.
     */
    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        require(
            uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "ECDSA: invalid signature 's' value"
        );
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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.6;

/**
 * @title IGovernable
 * @author solace.fi
 * @notice Enforces access control for important functions to [**governor**](/docs/user-docs/Governance).
 *
 * Many contracts contain functionality that should only be accessible to a privileged user. The most common access control pattern is [OpenZeppelin's `Ownable`](https://docs.openzeppelin.com/contracts/4.x/access-control#ownership-and-ownable). We instead use `Governable` with a few key differences:
 * - Transferring the governance role is a two step process. The current governance must [`setGovernance(newGovernance_)`](#setgovernance) then the new governance must [`acceptGovernance()`](#acceptgovernance). This is to safeguard against accidentally setting ownership to the wrong address and locking yourself out of your contract.
 * - `governance` is a constructor argument instead of `msg.sender`. This is especially useful when deploying contracts via a [`SingletonFactory`](./ISingletonFactory)
 */
interface IGovernable {

    /***************************************
    EVENTS
    ***************************************/

    /// @notice Emitted when Governance is set.
    event GovernanceTransferred(address newGovernance);

    /***************************************
    VIEW FUNCTIONS
    ***************************************/

    /// @notice Address of the current governor.
    function governance() external view returns (address);

    /// @notice Address of the governor to take over.
    function newGovernance() external view returns (address);

    /***************************************
    MUTATORS
    ***************************************/

    /**
     * @notice Initiates transfer of the governance role to a new governor.
     * Transfer is not complete until the new governor accepts the role.
     * Can only be called by the current [**governor**](/docs/user-docs/Governance).
     * @param newGovernance_ The new governor.
     */
    function setGovernance(address newGovernance_) external;

    /**
     * @notice Accepts the governance role.
     * Can only be called by the new governor.
     */
    function acceptGovernance() external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Enumerable is IERC721 {
    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
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

