// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

// import "hardhat/console.sol";

import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    ISuperAgreement,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";//"@superfluid-finance/ethereum-monorepo/packages/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {
    IConstantFlowAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {
    IInstantDistributionAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";

import {
    SuperAppBase
} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./tellor/UsingTellor.sol";

import "./StreamExchangeStorage.sol";
import "./StreamExchangeHelper.sol";
import "./tellor/ITellor.sol";



contract StreamExchange is Ownable, SuperAppBase, UsingTellor {

    // TODO: uint256 public constant RATE_PERCISION = 1000000;
    using SafeERC20 for ERC20;
    using StreamExchangeHelper for StreamExchangeStorage.StreamExchange;
    using StreamExchangeStorage for StreamExchangeStorage.StreamExchange;
    StreamExchangeStorage.StreamExchange internal _exchange;

    event UpdatedStream(address from, int96 newRate, int96 totalInflow);

    constructor(
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        IInstantDistributionAgreementV1  ida,
        ISuperToken inputToken,
        ISuperToken outputToken,
        ISuperToken subsidyToken,
        IUniswapV2Router02 sushiRouter,
        address payable oracle,
        uint256 requestId,
        string memory registrationKey)
        UsingTellor(oracle) {
        require(address(host) != address(0), "host");
        require(address(cfa) != address(0), "cfa");
        require(address(ida) != address(0), "ida");
        require(address(inputToken) != address(0), "inputToken");
        require(address(outputToken) != address(0), "output");
        require(!host.isApp(ISuperApp(msg.sender)), "owner SA");

        _exchange.sushiRouter = sushiRouter;
        _exchange.host = host;
        _exchange.cfa = cfa;
        _exchange.ida = ida;
        _exchange.inputToken = inputToken;
        _exchange.outputToken = outputToken;
        _exchange.subsidyToken = subsidyToken;
        _exchange.oracle = ITellor(oracle);
        _exchange.requestId = requestId;
        _exchange.feeRate = 20000;
        _exchange.rateTolerance = 10000;
        _exchange.subsidyIndexId = 1;
        _exchange.subsidyRate = 4e17; // 0.4 tokens/second ~ 1,000,000 tokens in a month
        _exchange.owner = msg.sender;

         // Unlimited approve for sushiswap
        ERC20(_exchange.inputToken.getUnderlyingToken()).safeIncreaseAllowance(address(_exchange.sushiRouter), 2**256 - 1);
        ERC20(_exchange.outputToken.getUnderlyingToken()).safeIncreaseAllowance(address(_exchange.sushiRouter), 2**256 - 1);
        // and Supertoken upgrades
        ERC20(_exchange.inputToken.getUnderlyingToken()).safeIncreaseAllowance(address(_exchange.inputToken), 2**256 - 1);
        ERC20(_exchange.outputToken.getUnderlyingToken()).safeIncreaseAllowance(address(_exchange.outputToken), 2**256 - 1);

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        if(bytes(registrationKey).length > 0) {
            _exchange.host.registerAppWithKey(configWord, registrationKey);
        } else {
            _exchange.host.registerApp(configWord);
        }

        // Set up the IDA for sending tokens back
        _exchange._createIndex(_exchange.outputIndexId, _exchange.outputToken);

        // Give the owner 1 share just to start up the contract
        _exchange._updateSubscription(_exchange.outputIndexId, msg.sender, 1, _exchange.outputToken);

        // Setup Liquidity Mining
        _exchange._initalizeLiquidityMining();

        _exchange.lastDistributionAt = block.timestamp;
    }

    /**************************************************************************
     * Stream Exchange Logic
     *************************************************************************/

    /// @dev If a new stream is opened, or an existing one is opened
  function _updateOutflow(bytes calldata ctx, bytes calldata agreementData, bool doDistributeFirst)
      private
      returns (bytes memory newCtx)
  {

    newCtx = ctx;

    (, , uint128 totalUnitsApproved, uint128 totalUnitsPending) = _exchange.ida.getIndex(
                                                                         _exchange.outputToken,
                                                                         address(this),
                                                                         _exchange.outputIndexId);
    // Check balance and account for
    uint256 balance = ISuperToken(_exchange.inputToken).balanceOf(address(this)) /
                      (10 ** (18 - ERC20(_exchange.inputToken.getUnderlyingToken()).decimals()));

    if (doDistributeFirst && totalUnitsApproved + totalUnitsPending > 0 && balance > 0) {
      newCtx = _exchange._distribute(newCtx);
    }

    (address requester, address flowReceiver) = abi.decode(agreementData, (address, address));
    require(flowReceiver == address(this), "!appflow");
    int96 appFlowRate = _exchange.cfa.getNetFlow(_exchange.inputToken, address(this));
    (, int96 requesterFlowRate, , ) = _exchange.cfa.getFlow(_exchange.inputToken, requester, address(this));

    // Make sure the requester has at least 8 hours of balance to stream
    require(int(_exchange.inputToken.balanceOf(requester)) >= requesterFlowRate * 8 hours, "!enoughTokens");

    require(requesterFlowRate >= 0, "!negativeRates");
    newCtx = _exchange._updateSubscriptionWithContext(newCtx, _exchange.outputIndexId, requester, uint128(uint(int(requesterFlowRate))), _exchange.outputToken);
    newCtx = _exchange._updateSubscriptionWithContext(newCtx, _exchange.subsidyIndexId, requester, uint128(uint(int(requesterFlowRate))), _exchange.subsidyToken);

    emit UpdatedStream(requester, requesterFlowRate, appFlowRate);

  }


  function distribute() external {
   _exchange._distribute(new bytes(0));
  }

  function closeStream(address streamer) public {
    _exchange._closeStream(streamer);
  }

  function emergencyCloseStream(address streamer) public {
    _exchange._emergencyCloseStream(streamer);
  }

  function emergencyDrain() public {
    _exchange._emergencyDrain();
  }

  function setSubsidyRate(uint128 subsidyRate) external onlyOwner {
    _exchange.subsidyRate = subsidyRate;
  }

  function setFeeRate(uint128 feeRate) external onlyOwner {
    _exchange.feeRate = feeRate;
  }

  function setRateTolerance(uint128 rateTolerance) external onlyOwner {
    _exchange.rateTolerance = rateTolerance;
  }

  function setOracle(address oracle) external onlyOwner {
    _exchange.oracle = ITellor(oracle);
  }

  function setRequestId(uint256 requestId) external onlyOwner {
    _exchange.requestId = requestId;
  }

  function isAppJailed() external view returns (bool) {
   return _exchange.host.isAppJailed(this);
  }

  function getIDAShares(uint32 index, address streamer) external view returns (bool exist,
                bool approved,
                uint128 units,
                uint256 pendingDistribution) {

    ISuperToken idaToken;
    if(index == _exchange.outputIndexId) {

      idaToken = _exchange.outputToken;

    } else if (index == _exchange.subsidyIndexId) {

      idaToken = _exchange.subsidyToken;

    } else {
      return (exist, approved, units, pendingDistribution);
    }

    (exist, approved, units, pendingDistribution) = _exchange.ida.getSubscription(
                                                                  idaToken,
                                                                  address(this),
                                                                  index,
                                                                  streamer);
  }

  function getInputToken() external view returns (ISuperToken) {
   return _exchange.inputToken;
  }

  function getOutputToken() external view returns (ISuperToken) {
   return _exchange.outputToken;
  }

  function getOutputIndexId() external view returns (uint32) {
   return _exchange.outputIndexId;
  }

  function getSubsidyToken() external view returns (ISuperToken) {
   return _exchange.subsidyToken;
  }

  function getSubsidyIndexId() external view returns (uint32) {
   return _exchange.subsidyIndexId;
  }

  function getSubsidyRate() external view returns (uint256) {
    return _exchange.subsidyRate;
  }

  function getTotalInflow() external view returns (int96) {
    return _exchange.cfa.getNetFlow(_exchange.inputToken, address(this));
  }

  function getLastDistributionAt() external view returns (uint256) {
    return _exchange.lastDistributionAt;
  }

  function getSushiRouter() external view returns (address) {
    return address(_exchange.sushiRouter);
  }

  function getTellorOracle() external view returns (address) {
    return address(_exchange.oracle);
  }

  function getRequestId() external view returns (uint256) {
    return _exchange.requestId;
  }

  function getOwner() external view returns (address) {
    return _exchange.owner;
  }

  function getFeeRate() external view returns (uint128) {
    return _exchange.feeRate;
  }

  function getRateTolerance() external view returns (uint256) {
    return _exchange.rateTolerance;
  }

  function getStreamRate(address streamer) external view returns (int96 requesterFlowRate) {
    (, requesterFlowRate, , ) = _exchange.cfa.getFlow(_exchange.inputToken, streamer, address(this));
  }



  /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     * NOTE: Override this to add changing the
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        super.transferOwnership(newOwner);
        _exchange.owner = newOwner;
    }

  /**************************************************************************
   * SuperApp callbacks
   *************************************************************************/

  function afterAgreementCreated(
      ISuperToken _superToken,
      address _agreementClass,
      bytes32, // _agreementId,
      bytes calldata _agreementData,
      bytes calldata ,// _cbdata,
      bytes calldata _ctx
  )
      external override
      onlyExpected(_superToken, _agreementClass)
      onlyHost
      returns (bytes memory newCtx)
  {
      if (!_exchange._isInputToken(_superToken) || !_exchange._isCFAv1(_agreementClass)) return _ctx;
      return _updateOutflow(_ctx, _agreementData, true);
  }

  function afterAgreementUpdated(
      ISuperToken _superToken,
      address _agreementClass,
      bytes32 ,//_agreementId,
      bytes calldata _agreementData,
      bytes calldata ,//_cbdata,
      bytes calldata _ctx
  )
      external override
      onlyExpected(_superToken, _agreementClass)
      onlyHost
      returns (bytes memory newCtx)
  {
      if (!_exchange._isInputToken(_superToken) || !_exchange._isCFAv1(_agreementClass)) return _ctx;
      return _updateOutflow(_ctx, _agreementData, true);
  }

  function afterAgreementTerminated(
      ISuperToken _superToken,
      address _agreementClass,
      bytes32 ,//_agreementId,
      bytes calldata _agreementData,
      bytes calldata ,//_cbdata,
      bytes calldata _ctx
  )
      external override
      onlyHost
      returns (bytes memory newCtx)
  {
      console.log("afterAgreementTerminated");
      // According to the app basic law, we should never revert in a termination callback
      if (!_exchange._isInputToken(_superToken) || !_exchange._isCFAv1(_agreementClass)) return _ctx;
      // Skip distribution when terminating to avoid reverts
      return _updateOutflow(_ctx, _agreementData, false);
  }



  modifier onlyHost() {
      require(msg.sender == address(_exchange.host), "one host");
      _;
  }

  modifier onlyExpected(ISuperToken superToken, address agreementClass) {
    if (_exchange._isCFAv1(agreementClass)) {
      require(_exchange._isInputToken(superToken), "!inputAccepted");
    } else if (_exchange._isIDAv1(agreementClass)) {
      require(_exchange._isOutputToken(superToken) || _exchange._isSubsidyToken(superToken), "!outputAccepted");
    }
    _;
  }


  }

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;
// This is required by the batchCall and decodeCtx
pragma experimental ABIEncoderV2;

import { ISuperfluidGovernance } from "./ISuperfluidGovernance.sol";
import { ISuperfluidToken } from "./ISuperfluidToken.sol";
import { ISuperToken } from "./ISuperToken.sol";
import { ISuperTokenFactory } from "./ISuperTokenFactory.sol";
import { ISuperAgreement } from "./ISuperAgreement.sol";
import { ISuperApp } from "./ISuperApp.sol";
import {
    SuperAppDefinitions,
    ContextDefinitions,
    BatchOperation,
    SuperfluidGovernanceConfigs
} from "./Definitions.sol";
import { TokenInfo } from "../tokens/TokenInfo.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC777 } from "@openzeppelin/contracts/token/ERC777/IERC777.sol";


/**
 * @dev Superfluid host interface.

 * It is the central contract of the system where super agreement, super app
 * and super token features are connected together.
 *
 * The superfluid host contract is also the entry point for the protocol users,
 * where batch call and meta transaction are provided for UX improvements.
 *
 * @author Superfluid
 */
interface ISuperfluid {

    /**************************************************************************
     * Governance
     *************************************************************************/

    /**
     * @dev Get the current governace of the Superfluid host
     */
    function getGovernance() external view returns(ISuperfluidGovernance governance);

    event GovernanceReplaced(ISuperfluidGovernance oldGov, ISuperfluidGovernance newGov);
    /**
     * @dev Replace the current governance with a new one
     */
    function replaceGovernance(ISuperfluidGovernance newGov) external;

    /**************************************************************************
     * Agreement Whitelisting
     *************************************************************************/

    event AgreementClassRegistered(bytes32 agreementType, address code);
    /**
     * @dev Register a new agreement class to the system
     * @param agreementClassLogic INitial agreement class code
     *
     * Modifiers:
     *  - onlyGovernance
     */
    function registerAgreementClass(ISuperAgreement agreementClassLogic) external;

    event AgreementClassUpdated(bytes32 agreementType, address code);
    /**
    * @dev Update code of an agreement class
    * @param agreementClassLogic New code for the agreement class
    *
    * Modifiers:
    *  - onlyGovernance
    */
    function updateAgreementClass(ISuperAgreement agreementClassLogic) external;

    /**
    * @dev Check if the agreement class is whitelisted
    */
    function isAgreementTypeListed(bytes32 agreementType) external view returns(bool yes);

    /**
    * @dev Check if the agreement class is whitelisted
    */
    function isAgreementClassListed(ISuperAgreement agreementClass) external view returns(bool yes);

    /**
    * @dev Get agreement class
    */
    function getAgreementClass(bytes32 agreementType) external view returns(ISuperAgreement agreementClass);

    /**
    * @dev Map list of the agreement classes using a bitmap
    * @param bitmap Agreement class bitmap
    */
    function mapAgreementClasses(uint256 bitmap)
        external view
        returns (ISuperAgreement[] memory agreementClasses);

    /**
    * @dev Create a new bitmask by adding a agreement class to it.
    * @param bitmap Agreement class bitmap
    */
    function addToAgreementClassesBitmap(uint256 bitmap, bytes32 agreementType)
        external view
        returns (uint256 newBitmap);

    /**
    * @dev Create a new bitmask by removing a agreement class from it.
    * @param bitmap Agreement class bitmap
    */
    function removeFromAgreementClassesBitmap(uint256 bitmap, bytes32 agreementType)
        external view
        returns (uint256 newBitmap);

    /**************************************************************************
    * Super Token Factory
    **************************************************************************/

    /**
     * @dev Get the super token factory
     * @return factory The factory
     */
    function getSuperTokenFactory() external view returns (ISuperTokenFactory factory);

    /**
     * @dev Get the super token factory logic (applicable to upgradable deployment)
     * @return logic The factory logic
     */
    function getSuperTokenFactoryLogic() external view returns (address logic);

    event SuperTokenFactoryUpdated(ISuperTokenFactory newFactory);
    /**
     * @dev Update super token factory
     * @param newFactory New factory logic
     */
    function updateSuperTokenFactory(ISuperTokenFactory newFactory) external;

    event SuperTokenLogicUpdated(ISuperToken indexed token, address code);
    /**
     * @dev Update the super token logic to the latest
     *
     * NOTE:
     * - Refer toISuperTokenFactory.Upgradability for expected behaviours.
     */
    function updateSuperTokenLogic(ISuperToken token) external;

    /**************************************************************************
     * App Registry
     *************************************************************************/

    /**
     * @dev App registered event
     */
    event AppRegistered(ISuperApp indexed app);

    /**
     * @dev Jail event for the app
     */
    event Jail(ISuperApp indexed app, uint256 reason);

    /**
     * @dev Message sender declares it as a super app
     * @param configWord The super app manifest configuration, flags are defined in
     *                   `SuperAppDefinitions`
     */
    function registerApp(uint256 configWord) external;

    /**
     * @dev Message sender declares it as a super app, using a registration key
     * @param configWord The super app manifest configuration, flags are defined in
     *                   `SuperAppDefinitions`
     * @param registrationKey The registration key issued by the governance
     */
    function registerAppWithKey(uint256 configWord, string calldata registrationKey) external;

    /**
     * @dev Query if the app is registered
     * @param app Super app address
     */
    function isApp(ISuperApp app) external view returns(bool);

    /**
     * @dev Query app level
     * @param app Super app address
     */
    function getAppLevel(ISuperApp app) external view returns(uint8 appLevel);

    /**
     * @dev Get the manifest of the super app
     * @param app Super app address
     */
    function getAppManifest(
        ISuperApp app
    )
        external view
        returns (
            bool isSuperApp,
            bool isJailed,
            uint256 noopMask
        );

    /**
     * @dev Query if the app has been jailed
     * @param app Super app address
     */
    function isAppJailed(ISuperApp app) external view returns (bool isJail);

    /**
     * @dev White-list the target app for app composition for the source app (msg.sender)
     * @param targetApp The taget super app address
     */
    function allowCompositeApp(ISuperApp targetApp) external;

    /**
     * @dev Query if source app  is allowed to call the target app as downstream app.
     * @param app Super app address
     * @param targetApp The taget super app address
     */
    function isCompositeAppAllowed(
        ISuperApp app,
        ISuperApp targetApp
    )
        external view
        returns (bool isAppAllowed);

    /**************************************************************************
     * Agreement Framework
     *
     * Agreements use these function to trigger super app callbacks, updates
     * app allowance and charge gas fees.
     *
     * These functions can only be called by registered agreements.
     *************************************************************************/

    function callAppBeforeCallback(
        ISuperApp app,
        bytes calldata callData,
        bool isTermination,
        bytes calldata ctx
    )
        external
        // onlyAgreement
        // isAppActive(app)
        returns(bytes memory cbdata);

    function callAppAfterCallback(
        ISuperApp app,
        bytes calldata callData,
        bool isTermination,
        bytes calldata ctx
    )
        external
        // onlyAgreement
        // isAppActive(app)
        returns(bytes memory appCtx);

    function appCallbackPush(
        bytes calldata ctx,
        ISuperApp app,
        uint256 appAllowanceGranted,
        int256 appAllowanceUsed,
        ISuperfluidToken appAllowanceToken
    )
        external
        // onlyAgreement
        returns (bytes memory appCtx);

    function appCallbackPop(
        bytes calldata ctx,
        int256 appAllowanceUsedDelta
    )
        external
        // onlyAgreement
        returns (bytes memory newCtx);

    function ctxUseAllowance(
        bytes calldata ctx,
        uint256 appAllowanceWantedMore,
        int256 appAllowanceUsedDelta
    )
        external
        // onlyAgreement
        returns (bytes memory newCtx);

    function jailApp(
        bytes calldata ctx,
        ISuperApp app,
        uint256 reason
    )
        external
        // onlyAgreement
        returns (bytes memory newCtx);

    /**************************************************************************
     * Contextless Call Proxies
     *
     * NOTE: For EOAs or non-app contracts, they are the entry points for interacting
     * with agreements or apps.
     *
     * NOTE: The contextual call data should be generated using
     * abi.encodeWithSelector. The context parameter should be set to "0x",
     * an empty bytes array as a placeholder to be replaced by the host
     * contract.
     *************************************************************************/

     /**
      * @dev Call agreement function
      * @param callData The contextual call data with placeholder ctx
      * @param userData Extra user data being sent to the super app callbacks
      */
     function callAgreement(
         ISuperAgreement agreementClass,
         bytes calldata callData,
         bytes calldata userData
     )
        external
        //cleanCtx
        returns(bytes memory returnedData);

    /**
     * @dev Call app action
     * @param callData The contextual call data.
     *
     * NOTE: See callAgreement about contextual call data.
     */
    function callAppAction(
        ISuperApp app,
        bytes calldata callData
    )
        external
        //cleanCtx
        //isAppActive(app)
        returns(bytes memory returnedData);

    /**************************************************************************
     * Contextual Call Proxies and Context Utilities
     *
     * For apps, they must use context they receive to interact with
     * agreements or apps.
     *
     * The context changes must be saved and returned by the apps in their
     * callbacks always, any modification to the context will be detected and
     * the violating app will be jailed.
     *************************************************************************/

    /**
     * @dev ABIv2 Encoded memory data of context
     *
     * NOTE on backward compatibility:
     * - Non-dynamic fields are padded to 32bytes and packed
     * - Dynamic fields are referenced through a 32bytes offset to their "parents" field (or root)
     * - The order of the fields hence should not be rearranged in order to be backward compatible:
     *    - non-dynamic fields will be parsed at the same memory location,
     *    - and dynamic fields will simply have a greater offset than it was.
     */
    struct Context {
        //
        // Call context
        //
        // callback level
        uint8 appLevel;
        // type of call
        uint8 callType;
        // the system timestsamp
        uint256 timestamp;
        // The intended message sender for the call
        address msgSender;

        //
        // Callback context
        //
        // For callbacks it is used to know which agreement function selector is called
        bytes4 agreementSelector;
        // User provided data for app callbacks
        bytes userData;

        //
        // App context
        //
        // app allowance granted
        uint256 appAllowanceGranted;
        // app allowance wanted by the app callback
        uint256 appAllowanceWanted;
        // app allowance used, allowing negative values over a callback session
        int256 appAllowanceUsed;
        // app address
        address appAddress;
        // app allowance in super token
        ISuperfluidToken appAllowanceToken;
    }

    function callAgreementWithContext(
        ISuperAgreement agreementClass,
        bytes calldata callData,
        bytes calldata userData,
        bytes calldata ctx
    )
        external
        // validCtx(ctx)
        // onlyAgreement(agreementClass)
        returns (bytes memory newCtx, bytes memory returnedData);

    function callAppActionWithContext(
        ISuperApp app,
        bytes calldata callData,
        bytes calldata ctx
    )
        external
        // validCtx(ctx)
        // isAppActive(app)
        returns (bytes memory newCtx);

    function decodeCtx(bytes calldata ctx)
        external pure
        returns (Context memory context);

    function isCtxValid(bytes calldata ctx) external view returns (bool);

    /**************************************************************************
    * Batch call
    **************************************************************************/
    /**
     * @dev Batch operation data
     */
    struct Operation {
        // Operation. Defined in BatchOperation (Definitions.sol)
        uint32 operationType;
        // Operation target
        address target;
        // Data specific to the operation
        bytes data;
    }

    /**
     * @dev Batch call function
     * @param operations Array of batch operations.
     */
    function batchCall(Operation[] memory operations) external;

    /**
     * @dev Batch call function for trusted forwarders (EIP-2771)
     * @param operations Array of batch operations.
     */
    function forwardBatchCall(Operation[] memory operations) external;

    /**************************************************************************
     * Function modifiers for access control and parameter validations
     *
     * While they cannot be explicitly stated in function definitions, they are
     * listed in function definition comments instead for clarity.
     *
     * TODO: turning these off because solidity-coverage don't like it
     *************************************************************************/

     /* /// @dev The current superfluid context is clean.
     modifier cleanCtx() virtual;

     /// @dev The superfluid context is valid.
     modifier validCtx(bytes memory ctx) virtual;

     /// @dev The agreement is a listed agreement.
     modifier isAgreement(ISuperAgreement agreementClass) virtual;

     // onlyGovernance

     /// @dev The msg.sender must be a listed agreement.
     modifier onlyAgreement() virtual;

     /// @dev The app is registered and not jailed.
     modifier isAppActive(ISuperApp app) virtual; */
}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperAgreement } from "../superfluid/ISuperAgreement.sol";
import { ISuperfluidToken } from "../superfluid/ISuperfluidToken.sol";


/**
 * @dev Superfluid's constant flow agreement interface
 *
 * @author Superfluid
 */
abstract contract IConstantFlowAgreementV1 is ISuperAgreement {

    /// @dev ISuperAgreement.agreementType implementation
    function agreementType() external override pure returns (bytes32) {
        return keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    }

    /**
     * @dev Get the maximum flow rate allowed with the deposit
     * @param deposit Deposit amount used for creating the flow
     */
    function getMaximumFlowRateFromDeposit(
        ISuperfluidToken token,
        uint256 deposit)
        external view virtual
        returns (int96 flowRate);

    /**
     * @dev Get the deposit required for creating the flow
     * @param flowRate Flow rate to be tested
     */
    function getDepositRequiredForFlowRate(
        ISuperfluidToken token,
        int96 flowRate)
        external view virtual
        returns (uint256 deposit);

    /**
     * @dev Create a flow betwen sender and receiver.
     * @param token Super token address.
     * @param receiver Flow receiver address.
     * @param flowRate New flow rate in amount per second.
     *
     * # App callbacks
     *
     * - AgreementCreated
     *   - agreementId - can be used in getFlowByID
     *   - agreementData - abi.encode(address flowSender, address flowReceiver)
     *
     * NOTE:
     * - A deposit is taken as safety margin for the solvency agents.
     * - A extra gas fee may be taken to pay for solvency agent liquidations.
     */
    function createFlow(
        ISuperfluidToken token,
        address receiver,
        int96 flowRate,
        bytes calldata ctx
    )
        external virtual
        returns(bytes memory newCtx);

    /**
     * @dev Update the flow rate between sender and receiver.
     * @param token Super token address.
     * @param receiver Flow receiver address.
     * @param flowRate New flow rate in amount per second.
     *
     * # App callbacks
     *
     * - AgreementUpdated
     *   - agreementId - can be used in getFlowByID
     *   - agreementData - abi.encode(address flowSender, address flowReceiver)
     *
     * NOTE:
     * - Only the flow sender may update the flow rate.
     * - Even if the flow rate is zero, the flow is not deleted
     * from the system.
     * - Deposit amount will be adjusted accordingly.
     * - No new gas fee is charged.
     */
    function updateFlow(
        ISuperfluidToken token,
        address receiver,
        int96 flowRate,
        bytes calldata ctx
    )
        external virtual
        returns(bytes memory newCtx);


    /**
     * @dev Get the flow data between `sender` and `receiver`.
     * @param token Super token address.
     * @param sender Flow receiver.
     * @param receiver Flow sender.
     * @return timestamp Timestamp of when the flow is updated.
     * @return flowRate The flow rate.
     * @return deposit The amount of deposit the flow.
     * @return owedDeposit The amount of owed deposit of the flow.
     */
    function getFlow(
        ISuperfluidToken token,
        address sender,
        address receiver
    )
        external view virtual
        returns (
            uint256 timestamp,
            int96 flowRate,
            uint256 deposit,
            uint256 owedDeposit
        );

    /**
     * @dev Get flow data using agreement ID
     * @param token Super token address.
     * @param agreementId The agreement ID.
     * @return timestamp Timestamp of when the flow is updated.
     * @return flowRate The flow rate.
     * @return deposit The amount of deposit the flow.
     * @return owedDeposit The amount of owed deposit of the flow.
     */
    function getFlowByID(
       ISuperfluidToken token,
       bytes32 agreementId
    )
        external view virtual
        returns (
            uint256 timestamp,
            int96 flowRate,
            uint256 deposit,
            uint256 owedDeposit
        );

    /**
     * @dev Get the aggregated flow info of the account
     * @param token Super token address.
    * @param account Account for the query.
    */
    function getAccountFlowInfo(
        ISuperfluidToken token,
        address account
    )
        external view virtual
        returns (
            uint256 timestamp,
            int96 flowRate,
            uint256 deposit,
            uint256 owedDeposit);

    /**
     * @dev Get the net flow rate of the account
     * @param token Super token address.
     * @param account Account for the query.
     * @return flowRate Flow rate.
     */
    function getNetFlow(
        ISuperfluidToken token,
        address account
    )
        external view virtual
        returns (int96 flowRate);

    /**
     * @dev Delete the flow between sender and receiver
     * @param token Super token address.
     * @param ctx Context bytes.
     * @param receiver Flow receiver address.
     *
     * # App callbacks
     *
     * - AgreementTerminated
     *   - agreementId - can be used in getFlowByID
     *   - agreementData - abi.encode(address flowSender, address flowReceiver)
     *
     * NOTE:
     * - Both flow sender and receiver may delete the flow.
     * - If Sender account is insolvent or in critical state, a solvency agent may
     *   also terminate the agreement.
     * - Gas fee may be returned to the sender.
     */
    function deleteFlow(
        ISuperfluidToken token,
        address sender,
        address receiver,
        bytes calldata ctx
    )
        external virtual
        returns(bytes memory newCtx);

     /**
      * @dev Flow updated event.
      * @param token Super token address.
      * @param sender Flow sender address.
      * @param receiver Flow recipient address.
      * @param flowRate Flow rate in amount per second for this flow.
      * @param flowRate Total flow rate in amount per second for the sender.
      * @param flowRate Total flow rate in amount per second for the receiver.
      * @param userData The user provided data.
      */
     event FlowUpdated(
         ISuperfluidToken indexed token,
         address indexed sender,
         address indexed receiver,
         int96 flowRate,
         int256 totalSenderFlowRate,
         int256 totalReceiverFlowRate,
         bytes userData
     );

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperAgreement } from "../superfluid/ISuperAgreement.sol";
import { ISuperfluidToken } from "../superfluid/ISuperfluidToken.sol";


/**
 * @title Superfluid's instant distribution agreement interface.
 *
 * @author Superfluid
 *
 * Notes:
 *   - A publisher can create as many as indeces as possibily identifiable with `indexId`.
 *     - `indexId` is deliberately limited to 32 bits, to avoid the chance for sha-3 collision.
 *       Despite knowing sha-3 collision is only theoratical.
 *   - A publisher can create subscription to an index for any subscriber.
 *   - A subscription consists of:
 *     - The index it subscribes to.
 *     - Number of units subscribed.
 *   - An index consists of:
 *     - Current value as `uint128 indexValue`.
 *     - Total units of the approved subscriptions as `uint128 totalUnitsApproved`.
 *     - Total units of the non approved subscription as `uint128 totalUnitsPending`.
 *   - A publisher can update index with new value that doesn't decrease.
 *   - A publisher can update subscription with any number of units.
 *   - A publisher or a subscriber can delete subscription and reset units to zero.
 *   - A subscriber must approve the index in order to receive distributions from the publisher
 *     each time the index is updated.
 *     - The amount distributed is $$\Delta{index} * units$$
 *   - Distributions to a non approved subscription stays in the publisher's deposit until:
 *     - the subscriber approve the subscription (side effect),
 *     - the publisher update the subscription (side effect),
 *     - the subscriber delete the subscription even if it is never approved (side effect),
 *     - or the subscriber can explicitly claim them.
 */
abstract contract IInstantDistributionAgreementV1 is ISuperAgreement {

    /// @dev ISuperAgreement.agreementType implementation
    function agreementType() external override pure returns (bytes32) {
        return keccak256("org.superfluid-finance.agreements.InstantDistributionAgreement.v1");
    }

    /**************************************************************************
     * Index operations
     *************************************************************************/

    /**
     * @dev Create a new index for the publisher.
     * @param token Super token address.
     * @param indexId Id of the index.
     *
     * # App callbacks
     *
     * None
     */
    function createIndex(
        ISuperfluidToken token,
        uint32 indexId,
        bytes calldata ctx)
            external
            virtual
            returns(bytes memory newCtx);

    event IndexCreated(
        ISuperfluidToken indexed token,
        address indexed publisher,
        uint32 indexed indexId,
        bytes userData);

    /**
     * @dev Query the data of a index.
     * @param token Super token address.
     * @param publisher The publisher of the index.
     * @param indexId Id of the index.
     * @return exist Does the index exist.
     * @return indexValue Value of the current index.
     * @return totalUnitsApproved Total units approved for the index.
     * @return totalUnitsPending Total units pending approval for the index.
     */
    function getIndex(
        ISuperfluidToken token,
        address publisher,
        uint32 indexId)
            external
            view
            virtual
            returns(
                bool exist,
                uint128 indexValue,
                uint128 totalUnitsApproved,
                uint128 totalUnitsPending);

    /**
     * @dev Calculate actual distribution amount
     * @param token Super token address.
     * @param publisher The publisher of the index.
     * @param indexId Id of the index.
     * @param amount The amount of tokens desired to be distributed.
     */
    function calculateDistribution(
       ISuperfluidToken token,
       address publisher,
       uint32 indexId,
       uint256 amount)
           external view
           virtual
           returns(
               uint256 actualAmount,
               uint128 newIndexValue);

    /**
     * @dev Update index value of an index.
     * @param token Super token address.
     * @param indexId Id of the index.
     * @param indexValue Value of the index.
     *
     * # App callbacks
     *
     * None
     */
    function updateIndex(
        ISuperfluidToken token,
        uint32 indexId,
        uint128 indexValue,
        bytes calldata ctx)
            external
            virtual
            returns(bytes memory newCtx);

    event IndexUpdated(
        ISuperfluidToken indexed token,
        address indexed publisher,
        uint32 indexed indexId,
        uint128 oldIndexValue,
        uint128 newIndexValue,
        uint128 totalUnitsPending,
        uint128 totalUnitsApproved,
        bytes userData);

    /**
     * @dev Distribute tokens through the index.
     * @param token Super token address.
     * @param indexId Id of the index.
     * @param amount The amount of tokens desired to be distributed.
     *
     * NOTE:
     * - This is a convenient version of updateIndex. It adds to the index
     *   a delta that equals to `amount / totalUnits`.
     * - The actual amount distributed could be obtained via
     *   `calculateDistribution`. This is due to precision error with index
     *   value and units data range.
     *
     * # App callbacks
     *
     * None
     */
    function distribute(
        ISuperfluidToken token,
        uint32 indexId,
        uint256 amount,
        bytes calldata ctx)
            external
            virtual
            returns(bytes memory newCtx);


    /**************************************************************************
     * Subscription operations
     *************************************************************************/

    /**
     * @dev Approve the subscription of an index.
     * @param token Super token address.
     * @param publisher The publisher of the index.
     * @param indexId Id of the index.
     *
     * # App callbacks
     *
     * - if subscription exist
     *   - AgreementCreated callback to the publisher:
     *      - agreementId is for the subscription
     * - if subscription does not exist
     *   - AgreementUpdated callback to the publisher:
     *      - agreementId is for the subscription
     */
    function approveSubscription(
        ISuperfluidToken token,
        address publisher,
        uint32 indexId,
        bytes calldata ctx)
            external
            virtual
            returns(bytes memory newCtx);

    event IndexSubscribed(
        ISuperfluidToken indexed token,
        address indexed publisher,
        uint32 indexed indexId,
        address subscriber,
        bytes userData);

    event SubscriptionApproved(
        ISuperfluidToken indexed token,
        address indexed subscriber,
        address publisher,
        uint32 indexId,
        bytes userData);

    /**
    * @dev Revoke the subscription of an index.
    * @param token Super token address.
    * @param publisher The publisher of the index.
    * @param indexId Id of the index.
    *
    * # App callbacks
    * - AgreementUpdated callback to the publisher:
    *    - agreementId is for the subscription
    */
    function revokeSubscription(
        ISuperfluidToken token,
        address publisher,
        uint32 indexId,
        bytes calldata ctx)
         external
         virtual
         returns(bytes memory newCtx);

    event IndexUnsubscribed(
        ISuperfluidToken indexed token,
        address indexed publisher,
        uint32 indexed indexId,
        address subscriber,
        bytes userData);

    event SubscriptionRevoked(
        ISuperfluidToken indexed token,
        address indexed subscriber,
        address publisher,
        uint32 indexId,
        bytes userData);

    /**
     * @dev Update the nuber of units of a subscription.
     * @param token Super token address.
     * @param indexId Id of the index.
     * @param subscriber The subscriber of the index.
     * @param units Number of units of the subscription.
     *
     * # App callbacks
     *
     * - if subscription exist
     *   - AgreementCreated callback to the subscriber:
     *      - agreementId is for the subscription
     * - if subscription does not exist
     *   - AgreementUpdated callback to the subscriber:
     *      - agreementId is for the subscription
     */
    function updateSubscription(
        ISuperfluidToken token,
        uint32 indexId,
        address subscriber,
        uint128 units,
        bytes calldata ctx)
            external
            virtual
            returns(bytes memory newCtx);

    event IndexUnitsUpdated(
        ISuperfluidToken indexed token,
        address indexed publisher,
        uint32 indexed indexId,
        address subscriber,
        uint128 units,
        bytes userData);

    event SubscriptionUnitsUpdated(
        ISuperfluidToken indexed token,
        address indexed subscriber,
        address publisher,
        uint32 indexId,
        uint128 units,
        bytes userData);

    /**
     * @dev Get data of a subscription
     * @param token Super token address.
     * @param publisher The publisher of the index.
     * @param indexId Id of the index.
     * @param subscriber The subscriber of the index.
     * @return exist Does the subscription exist?
     * @return approved Is the subscription approved?
     * @return units Units of the suscription.
     * @return pendingDistribution Pending amount of tokens to be distributed for unapproved subscription.
     */
    function getSubscription(
        ISuperfluidToken token,
        address publisher,
        uint32 indexId,
        address subscriber)
            external
            view
            virtual
            returns(
                bool exist,
                bool approved,
                uint128 units,
                uint256 pendingDistribution
            );

    /**
     * @dev Get data of a subscription by agreement ID
     * @param token Super token address.
     * @param agreementId The agreement ID.
     * @return publisher The publisher of the index.
     * @return indexId Id of the index.
     * @return approved Is the subscription approved?
     * @return units Units of the suscription.
     * @return pendingDistribution Pending amount of tokens to be distributed for unapproved subscription.
     */
    function getSubscriptionByID(
        ISuperfluidToken token,
        bytes32 agreementId)
            external
            view
            virtual
            returns(
                address publisher,
                uint32 indexId,
                bool approved,
                uint128 units,
                uint256 pendingDistribution
            );

    /**
     * @dev List subscriptions of an user.
     * @param token Super token address.
     * @param subscriber The user, a subscriber.
     * @return publishers Publishers of the subcriptions.
     * @return indexIds Indexes of the subscriptions.
     * @return unitsList Units of the subscriptions.
     */
    function listSubscriptions(
        ISuperfluidToken token,
        address subscriber)
            external
            view
            virtual
            returns(
                address[] memory publishers,
                uint32[] memory indexIds,
                uint128[] memory unitsList);

    /**
     * @dev Delete the subscription of an user.
     * @param token Super token address.
     * @param publisher The publisher of the index.
     * @param indexId Id of the index.
     * @param subscriber The user, a subscriber.
     *
     * # App callbacks
     *
     * - if the subscriber called it
     *   - AgreementTerminated callback to the publsiher:
     *      - agreementId is for the subscription
     * - if the publisher called it
     *   - AgreementTerminated callback to the subscriber:
     *      - agreementId is for the subscription
     */
    function deleteSubscription(
        ISuperfluidToken token,
        address publisher,
        uint32 indexId,
        address subscriber,
        bytes calldata ctx)
            external
            virtual
            returns(bytes memory newCtx);

    /**
    * @dev Claim pending distributions.
    * @param token Super token address.
    * @param publisher The publisher of the index.
    * @param indexId Id of the index.
    * @param subscriber The user, a subscriber.
    *
    * The subscription should not exist yet.
    *
    * # App callbacks
    *
    * - AgreementUpdated callback to the publisher:
    *    - agreementId is for the subscription
    */
    function claim(
        ISuperfluidToken token,
        address publisher,
        uint32 indexId,
        address subscriber,
        bytes calldata ctx)
        external
        virtual
        returns(bytes memory newCtx);

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    SuperAppDefinitions
} from "../interfaces/superfluid/ISuperfluid.sol";

abstract contract SuperAppBase is ISuperApp {

    function beforeAgreementCreated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*ctx*/
    )
        external
        view
        virtual
        override
        returns (bytes memory /*cbdata*/)
    {
        revert("Unsupported callback - Before Agreement Created");
    }

    function afterAgreementCreated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*cbdata*/,
        bytes calldata /*ctx*/
    )
        external
        virtual
        override
        returns (bytes memory /*newCtx*/)
    {
        revert("Unsupported callback - After Agreement Created");
    }

    function beforeAgreementUpdated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*ctx*/
    )
        external
        view
        virtual
        override
        returns (bytes memory /*cbdata*/)
    {
        revert("Unsupported callback - Before Agreement updated");
    }

    function afterAgreementUpdated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*cbdata*/,
        bytes calldata /*ctx*/
    )
        external
        virtual
        override
        returns (bytes memory /*newCtx*/)
    {
        revert("Unsupported callback - After Agreement Updated");
    }

    function beforeAgreementTerminated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*ctx*/
    )
        external
        view
        virtual
        override
        returns (bytes memory /*cbdata*/)
    {
        revert("Unsupported callback -  Before Agreement Terminated");
    }

    function afterAgreementTerminated(
        ISuperToken /*superToken*/,
        address /*agreementClass*/,
        bytes32 /*agreementId*/,
        bytes calldata /*agreementData*/,
        bytes calldata /*cbdata*/,
        bytes calldata /*ctx*/
    )
        external
        virtual
        override
        returns (bytes memory /*newCtx*/)
    {
        revert("Unsupported callback - After Agreement Terminated");
    }

}

pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

pragma solidity >=0.6.2;

import './IUniswapV2Router01.sol';

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
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
    constructor() {
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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITellor.sol";

/**
 * @title UserContract
 * This contracts creates for easy integration to the Tellor System
 * by allowing smart contracts to read data off Tellor
 */
contract UsingTellor {
    ITellor private tellor;

    /*Constructor*/
    /**
     * @dev the constructor sets the storage address and owner
     * @param _tellor is the TellorMaster address
     */
    constructor(address payable _tellor) {
        tellor = ITellor(_tellor);
    }

    /**
     * @dev Retreive value from oracle based on requestId/timestamp
     * @param _requestId being requested
     * @param _timestamp to retreive data/value from
     * @return uint value for requestId/timestamp submitted
     */
    function retrieveData(uint256 _requestId, uint256 _timestamp)
        public
        view
        returns (uint256)
    {
        return tellor.retrieveData(_requestId, _timestamp);
    }

    /**
     * @dev Gets the 5 miners who mined the value for the specified requestId/_timestamp
     * @param _requestId to looku p
     * @param _timestamp is the timestamp to look up miners for
     * @return bool true if requestId/timestamp is under dispute
     */
    function isInDispute(uint256 _requestId, uint256 _timestamp)
        public
        view
        returns (bool)
    {
        return tellor.isInDispute(_requestId, _timestamp);
    }

    /**
     * @dev Counts the number of values that have been submited for the request
     * @param _requestId the requestId to look up
     * @return uint count of the number of values received for the requestId
     */
    function getNewValueCountbyRequestId(uint256 _requestId)
        public
        view
        returns (uint256)
    {
        return tellor.getNewValueCountbyRequestId(_requestId);
    }

    /**
     * @dev Gets the timestamp for the value based on their index
     * @param _requestId is the requestId to look up
     * @param _index is the value index to look up
     * @return uint timestamp
     */

    function getTimestampbyRequestIDandIndex(uint256 _requestId, uint256 _index)
        public
        view
        returns (uint256)
    {
        return tellor.getTimestampbyRequestIDandIndex(_requestId, _index);
    }

    /**
     * @dev Allows the user to get the latest value for the requestId specified
     * @param _requestId is the requestId to look up the value for
     * @return ifRetrieve bool true if it is able to retreive a value, the value, and the value's timestamp
     * @return value the value retrieved
     * @return _timestampRetrieved the value's timestamp
     */
    function getCurrentValue(uint256 _requestId)
        public
        view
        returns (
            bool ifRetrieve,
            uint256 value,
            uint256 _timestampRetrieved
        )
    {
        uint256 _count = tellor.getNewValueCountbyRequestId(_requestId);
        uint256 _time =
            tellor.getTimestampbyRequestIDandIndex(_requestId, _count - 1);
        uint256 _value = tellor.retrieveData(_requestId, _time);
        if (_value > 0) return (true, _value, _time);
        return (false, 0, _time);
    }

    // slither-disable-next-line calls-loop
    function getIndexForDataBefore(uint256 _requestId, uint256 _timestamp)
        public
        view
        returns (bool found, uint256 index)
    {
        uint256 _count = tellor.getNewValueCountbyRequestId(_requestId);
        if (_count > 0) {
            uint256 middle;
            uint256 start = 0;
            uint256 end = _count - 1;
            uint256 _time;

            //Checking Boundaries to short-circuit the algorithm
            _time = tellor.getTimestampbyRequestIDandIndex(_requestId, start);
            if (_time >= _timestamp) return (false, 0);
            _time = tellor.getTimestampbyRequestIDandIndex(_requestId, end);
            if (_time < _timestamp) return (true, end);

            //Since the value is within our boundaries, do a binary search
            while (true) {
                middle = (end - start) / 2 + 1 + start;
                _time = tellor.getTimestampbyRequestIDandIndex(
                    _requestId,
                    middle
                );
                if (_time < _timestamp) {
                    //get imeadiate next value
                    uint256 _nextTime =
                        tellor.getTimestampbyRequestIDandIndex(
                            _requestId,
                            middle + 1
                        );
                    if (_nextTime >= _timestamp) {
                        //_time is correct
                        return (true, middle);
                    } else {
                        //look from middle + 1(next value) to end
                        start = middle + 1;
                    }
                } else {
                    uint256 _prevTime =
                        tellor.getTimestampbyRequestIDandIndex(
                            _requestId,
                            middle - 1
                        );
                    if (_prevTime < _timestamp) {
                        // _prevtime is correct
                        return (true, middle - 1);
                    } else {
                        //look from start to middle -1(prev value)
                        end = middle - 1;
                    }
                }
                //We couldn't found a value
                //if(middle - 1 == start || middle == _count) return (false, 0);
            }
        }
        return (false, 0);
    }

    /**
     * @dev Allows the user to get the first value for the requestId before the specified timestamp
     * @param _requestId is the requestId to look up the value for
     * @param _timestamp before which to search for first verified value
     * @return _ifRetrieve bool true if it is able to retreive a value, the value, and the value's timestamp
     * @return _value the value retrieved
     * @return _timestampRetrieved the value's timestamp
     */
    function getDataBefore(uint256 _requestId, uint256 _timestamp)
        public
        view
        returns (
            bool _ifRetrieve,
            uint256 _value,
            uint256 _timestampRetrieved
        )
    {
        (bool _found, uint256 _index) =
            getIndexForDataBefore(_requestId, _timestamp);
        if (!_found) return (false, 0, 0);
        uint256 _time =
            tellor.getTimestampbyRequestIDandIndex(_requestId, _index);
        _value = tellor.retrieveData(_requestId, _time);
        //If value is diputed it'll return zero
        if (_value > 0) return (true, _value, _time);
        return (false, 0, 0);
    }
}

import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    ISuperAgreement,
    SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";


import {
    IConstantFlowAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";


import {
    IInstantDistributionAgreementV1
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IInstantDistributionAgreementV1.sol";

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import "./tellor/ITellor.sol";

library StreamExchangeStorage  {

  struct Stream {
    int96 rate;
  }

  struct StreamExchange {                 // An exchange generate when StreamExchange is deployed
    ISuperfluid host;                     // Superfluid host contract
    IConstantFlowAgreementV1 cfa;         // The stored constant flow agreement class address
    IInstantDistributionAgreementV1 ida;  // The stored instant dist. agreement class address
    ISuperToken inputToken;               // The input token (e.g. DAIx)
    ISuperToken outputToken;              // The output token (e.g. ETHx)
    uint32 outputIndexId;
    ISuperToken subsidyToken;             // The token to use as the subsidy
    uint256 subsidyRate;                  // The number of tokens to distribute subsidy in units per second
    uint32 subsidyIndexId;
    uint256 lastDistributionAt;           // The last time a distribution was made
    IUniswapV2Router02 sushiRouter;       // Address of sushsiwap router
    ITellor oracle;                       // Address of deployed simple oracle for input//output token
    uint256 requestId;                    // The id of the tellor request that has input/output exchange rate
    uint128 feeRate;                      // The fee taken as a % with 6 decimals
    address owner;                        // The owner of the exchange
    uint256 rateTolerance;                // The percentage to deviate from the oracle scaled to 1e6
  }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "hardhat/console.sol";

import {
    ISuperfluid,
    ISuperToken,
    ISuperToken,
    ISuperAgreement
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./tellor/UsingTellor.sol";
import "./StreamExchangeStorage.sol";


library StreamExchangeHelper {

  using SafeERC20 for ERC20;

  // TODO: Emit these events where appropriate
  event Distribution(uint256 totalAmount, uint256 feeCollected, address token);
  event UpdatedStream(address from, int96 newRate, int96 totalInflow);


  function _closeStream(StreamExchangeStorage.StreamExchange storage self, address streamer) public {
    // Only closable iff their balance is less than 8 hours of streaming
    (,int96 streamerFlowRate,,) = self.cfa.getFlow(self.inputToken, streamer, address(this));
    require(int(self.inputToken.balanceOf(streamer)) <= streamerFlowRate * 8 hours,
              "!closable");

    // Update Subscriptions
    _updateSubscription(self, self.subsidyIndexId, streamer, 0, self.subsidyToken);
    _updateSubscription(self, self.outputIndexId, streamer, 0, self.outputToken);
    emit UpdatedStream(streamer, 0, self.cfa.getNetFlow(self.inputToken, address(this)));

    // Close the streamers stream
    self.host.callAgreement(
        self.cfa,
        abi.encodeWithSelector(
            self.cfa.deleteFlow.selector,
            self.inputToken,
            streamer,
            address(this),
            new bytes(0) // placeholder
        ),
        "0x"
    );

  }

  function _emergencyCloseStream(StreamExchangeStorage.StreamExchange storage self, address streamer) public {
    // Allows anyone to close any stream iff the app is jailed
    bool isJailed = ISuperfluid(msg.sender).isAppJailed(ISuperApp(address(this)));
    require(isJailed, "!jailed");
    self.host.callAgreement(
        self.cfa,
        abi.encodeWithSelector(
            self.cfa.deleteFlow.selector,
            self.inputToken,
            streamer,
            address(this),
            new bytes(0) // placeholder
        ),
        "0x"
    );
  }

  function _emergencyDrain(StreamExchangeStorage.StreamExchange storage self) public {
    require(self.cfa.getNetFlow(self.inputToken, address(this)) == 0, "!zeroStreamers");
    self.inputToken.transfer(self.owner, self.inputToken.balanceOf(address(this)));
    self.outputToken.transfer(self.owner, self.outputToken.balanceOf(address(this)));
  }


  function _getCurrentValue(
    StreamExchangeStorage.StreamExchange storage self,
    uint256 _requestId
  )
      public
      view
      returns (
          bool ifRetrieve,
          uint256 value,
          uint256 _timestampRetrieved
      )
  {
      uint256 _count = self.oracle.getNewValueCountbyRequestId(_requestId);
      uint256 _time =
          self.oracle.getTimestampbyRequestIDandIndex(_requestId, _count - 1);
      uint256 _value = self.oracle.retrieveData(_requestId, _time);
      if (_value > 0) return (true, _value, _time);
      return (false, 0, _time);
  }


  // @dev Distribute a single `amount` of outputToken among all streamers
  // @dev Calculates the amount to distribute
  function _distribute(
    StreamExchangeStorage.StreamExchange storage self,
    bytes memory ctx
  )
    external returns (bytes memory newCtx)
  {

     newCtx = ctx;
     require(self.host.isCtxValid(newCtx) || newCtx.length == 0, "!distributeCtx");

     // Get the exchange rate as inputToken per outputToken
     bool _didGet;
     uint _timestamp;
     uint _value;

     (_didGet, _value, _timestamp) = _getCurrentValue(self, self.requestId);

     require(_didGet, "!getCurrentValue");
     require(_timestamp >= block.timestamp - 3600, "!currentValue");

     _swap(self, ISuperToken(self.inputToken).balanceOf(address(this)), _value, block.timestamp + 3600);

     uint256 outputBalance = ISuperToken(self.outputToken).balanceOf(address(this));
     (uint256 actualAmount,) = self.ida.calculateDistribution(
        self.outputToken,
        address(this),
        self.outputIndexId,
        outputBalance);

     console.log("outputBalance", outputBalance);
     console.log("actualAmount", actualAmount);

      // Return if there's not anything to actually distribute
      if (actualAmount == 0) { return newCtx; }

      // Calculate the fee for making the distribution
      uint256 feeCollected = actualAmount * self.feeRate / 1e6;
      uint256 distAmount = actualAmount - feeCollected;

      // Calculate subside
      uint256 subsidyAmount = (block.timestamp - self.lastDistributionAt) * self.subsidyRate;

     // Confirm the app has enough to distribute
     require(self.outputToken.balanceOf(address(this)) >= actualAmount, "!enough");
     newCtx = _idaDistribute(self, self.outputIndexId, uint128(distAmount), self.outputToken, newCtx);
     emit Distribution(distAmount, feeCollected, address(self.outputToken));

     // Distribute a subsidy if possible
     if(self.subsidyToken.balanceOf(address(this)) >= subsidyAmount) {
       newCtx = _idaDistribute(self, self.subsidyIndexId, uint128(subsidyAmount), self.subsidyToken, newCtx);
       emit Distribution(subsidyAmount, 0, address(self.subsidyToken));
     }

     self.lastDistributionAt = block.timestamp;

     // Take the fee
     ISuperToken(self.outputToken).transfer(self.owner, feeCollected);
     // NOTE: After swapping any token with < 18 decimals, there may be dust left so just leave it
     require(self.inputToken.balanceOf(address(this)) /
             10 ** (18 - ERC20(self.inputToken.getUnderlyingToken()).decimals()) == 0,
             "!sellAllInput");


     return newCtx;

   }

   function _swap(
         StreamExchangeStorage.StreamExchange storage self,
         uint256 amount,  // Assumes this is outputToken.balanceOf(address(this))
         uint256 exchangeRate,
         uint256 deadline
     ) public returns(uint) {

    address inputToken;           // The underlying input token address
    address outputToken;          // The underlying output token address
    address[] memory path;        // The path to take
    uint256 minOutput;            // The minimum amount of output tokens based on Tellor
    uint256 outputAmount; // The balance before the swap

    inputToken = self.inputToken.getUnderlyingToken();
    outputToken = self.outputToken.getUnderlyingToken();

    // Downgrade and scale the input amount
    console.log("Amount", amount);
    self.inputToken.downgrade(amount);
    // Scale it to 1e18 for calculations
    amount = ERC20(inputToken).balanceOf(address(this)) * (10 ** (18 - ERC20(inputToken).decimals()));

    // TODO: This needs to be "invertable"
    // USD >> TOK
    minOutput = amount * 1e18 / exchangeRate / 1e12;
    // TOK >> USD
    // minOutput = amount  * exchangeRate / 1e6;
    minOutput = minOutput * (1e6 - self.rateTolerance) / 1e6;

    // Scale back from 1e18 to outputToken decimals
    minOutput = minOutput * (10 ** (ERC20(outputToken).decimals())) / 1e18;
    // Scale it back to inputToken decimals
    amount = amount / (10 ** (18 - ERC20(inputToken).decimals()));

    path = new address[](2);
    path[0] = inputToken;
    path[1] = outputToken;
    console.log("amount",amount);
    console.log("inputToken",inputToken);
    console.log("outputToken",outputToken);
    self.sushiRouter.swapExactTokensForTokens(
       amount,
       0, // Accept any amount but fail if we're too far from the oracle price
       path,
       address(this),
       deadline
    );
    // Assumes `amount` was outputToken.balanceOf(address(this))
    outputAmount = ERC20(outputToken).balanceOf(address(this));
    console.log("outputAmount", outputAmount);
    require(outputAmount >= minOutput, "BAD_EXCHANGE_RATE: Try again later");

    // Convert the outputToken back to its supertoken version
    self.outputToken.upgrade(outputAmount * (10 ** (18 - ERC20(outputToken).decimals())));

    return outputAmount;
  }


  function _initalizeLiquidityMining(StreamExchangeStorage.StreamExchange storage self) internal {
    // Create the index for IDA
    _createIndex(self, self.subsidyIndexId, self.subsidyToken);
    // Give the initalizer 1 share to get it started
    _updateSubscription(self, self.subsidyIndexId, msg.sender, 1, self.subsidyToken);
  }

  function _idaDistribute(StreamExchangeStorage.StreamExchange storage self, uint32 index, uint128 distAmount, ISuperToken distToken, bytes memory ctx) internal returns (bytes memory newCtx) {
    newCtx = ctx;
    if (newCtx.length == 0) { // No context provided
      self.host.callAgreement(
        self.ida,
        abi.encodeWithSelector(
            self.ida.distribute.selector,
            distToken,
            index,
            distAmount,
            new bytes(0) // placeholder ctx
        ),
        new bytes(0) // user data
      );
    } else {
      require(self.host.isCtxValid(newCtx) || newCtx.length == 0, "!distribute");
      (newCtx, ) = self.host.callAgreementWithContext(
        self.ida,
        abi.encodeWithSelector(
            self.ida.distribute.selector,
            distToken,
            index,
            distAmount,
            new bytes(0) // placeholder ctx
        ),
        new bytes(0), // user data
        newCtx
      );
    }
  }

  function _createIndex(StreamExchangeStorage.StreamExchange storage self, uint256 index, ISuperToken distToken) internal {
    self.host.callAgreement(
       self.ida,
       abi.encodeWithSelector(
           self.ida.createIndex.selector,
           distToken,
           index,
           new bytes(0) // placeholder ctx
       ),
       new bytes(0) // user data
     );
  }

  function _updateSubscription(
      StreamExchangeStorage.StreamExchange storage self,
      uint256 index,
      address subscriber,
      uint128 shares,
      ISuperToken distToken) internal {
    self.host.callAgreement(
       self.ida,
       abi.encodeWithSelector(
           self.ida.updateSubscription.selector,
           distToken,
           index,
           // one share for the to get it started
           subscriber,
           shares / 1e9,
           new bytes(0) // placeholder ctx
       ),
       new bytes(0) // user data
   );
  }

  function _updateSubscriptionWithContext(
      StreamExchangeStorage.StreamExchange storage self,
      bytes memory ctx,
      uint256 index,
      address subscriber,
      uint128 shares,
      ISuperToken distToken)
      internal returns (bytes memory newCtx)  {

      newCtx = ctx;
      (newCtx, ) = self.host.callAgreementWithContext(
        self.ida,
        abi.encodeWithSelector(
            self.ida.updateSubscription.selector,
            distToken,
            index,
            subscriber,
            shares / 1e9,  // Number of shares is proportional to their rate
            new bytes(0)
        ),
        new bytes(0), // user data
        newCtx
      );
  }

  function _deleteSubscriptionWithContext(
      StreamExchangeStorage.StreamExchange storage self,
      bytes memory ctx,
      address receiver,
      uint256 index,
      address subscriber,
      ISuperToken distToken)
      internal returns (bytes memory newCtx)  {

      (newCtx, ) = self.host.callAgreementWithContext(
        self.ida,
        abi.encodeWithSelector(
            self.ida.deleteSubscription.selector,
            distToken,
            receiver,
            index,
            subscriber,
            new bytes(0)
        ),
        new bytes(0), // user data
        newCtx
      );
  }


  /**************************************************************************
   * SuperApp callbacks
   *************************************************************************/

  function _isInputToken(StreamExchangeStorage.StreamExchange storage self, ISuperToken superToken) internal view returns (bool) {
      return address(superToken) == address(self.inputToken);
  }

  function _isOutputToken(StreamExchangeStorage.StreamExchange storage self, ISuperToken superToken) internal view returns (bool) {
      return address(superToken) == address(self.outputToken);
  }

  function _isSubsidyToken(StreamExchangeStorage.StreamExchange storage self, ISuperToken superToken) internal view returns (bool) {
      return address(superToken) == address(self.subsidyToken);
  }

  function _isCFAv1(StreamExchangeStorage.StreamExchange storage self, address agreementClass) internal view returns (bool) {
      return ISuperAgreement(agreementClass).agreementType()
          == keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
  }

  function _isIDAv1(StreamExchangeStorage.StreamExchange storage self, address agreementClass) internal view returns (bool) {
      return ISuperAgreement(agreementClass).agreementType()
          == keccak256("org.superfluid-finance.agreements.InstantDistributionAgreement.v1");
  }

  }

// SPDX-License-Identifier: MIT
pragma solidity >=0.5.16;

interface ITellor {
    /**
     * @dev Helps initialize a dispute by assigning it a disputeId
     * when a miner returns a false on the validate array(in Tellor.ProofOfWork) it sends the
     * invalidated value information to POS voting
     * @param _requestId being disputed
     * @param _timestamp being disputed
     * @param _minerIndex the index of the miner that submitted the value being disputed. Since each official value
     * requires 5 miners to submit a value.
     */
    function beginDispute(
        uint256 _requestId,
        uint256 _timestamp,
        uint256 _minerIndex
    ) external;

    /**
     * @dev Allows token holders to vote
     * @param _disputeId is the dispute id
     * @param _supportsDispute is the vote (true=the dispute has basis false = vote against dispute)
     */
    function vote(uint256 _disputeId, bool _supportsDispute) external;

    /**
     * @dev tallies the votes.
     * @param _disputeId is the dispute id
     */
    function tallyVotes(uint256 _disputeId) external;

    /**
     * @dev Allows for a fork to be proposed
     * @param _propNewTellorAddress address for new proposed Tellor
     */
    function proposeFork(address _propNewTellorAddress) external;

    /**
     * @dev Add tip to Request value from oracle
     * @param _requestId being requested to be mined
     * @param _tip amount the requester is willing to pay to be get on queue. Miners
     * mine the onDeckQueryHash, or the api with the highest payout pool
     */
    function addTip(uint256 _requestId, uint256 _tip) external;

    /**
     * @dev This is called by the miner when they submit the PoW solution (proof of work and value)
     * @param _nonce uint submitted by miner
     * @param _requestId the apiId being mined
     * @param _value of api query
     *
     */
    function submitMiningSolution(
        string calldata _nonce,
        uint256 _requestId,
        uint256 _value
    ) external;

    /**
     * @dev This is called by the miner when they submit the PoW solution (proof of work and value)
     * @param _nonce uint submitted by miner
     * @param _requestId is the array of the 5 PSR's being mined
     * @param _value is an array of 5 values
     */
    function submitMiningSolution(
        string calldata _nonce,
        uint256[5] calldata _requestId,
        uint256[5] calldata _value
    ) external;

    /**
     * @dev Allows the current owner to propose transfer control of the contract to a
     * newOwner and the ownership is pending until the new owner calls the claimOwnership
     * function
     * @param _pendingOwner The address to transfer ownership to.
     */
    function proposeOwnership(address payable _pendingOwner) external;

    /**
     * @dev Allows the new owner to claim control of the contract
     */
    function claimOwnership() external;

    /**
     * @dev This function allows miners to deposit their stake.
     */
    function depositStake() external;

    /**
     * @dev This function allows stakers to request to withdraw their stake (no longer stake)
     * once they lock for withdraw(stakes.currentStatus = 2) they are locked for 7 days before they
     * can withdraw the stake
     */
    function requestStakingWithdraw() external;

    /**
     * @dev This function allows users to withdraw their stake after a 7 day waiting period from request
     */
    function withdrawStake() external;

    /**
     * @dev This function approves a _spender an _amount of tokens to use
     * @param _spender address
     * @param _amount amount the spender is being approved for
     * @return true if spender appproved successfully
     */
    function approve(address _spender, uint256 _amount) external returns (bool);

    /**
     * @dev Allows for a transfer of tokens to _to
     * @param _to The address to send tokens to
     * @param _amount The amount of tokens to send
     * @return true if transfer is successful
     */
    function transfer(address _to, uint256 _amount) external returns (bool);

    /**
     * @dev Sends _amount tokens to _to from _from on the condition it
     * is approved by _from
     * @param _from The address holding the tokens being transferred
     * @param _to The address of the recipient
     * @param _amount The amount of tokens to be transferred
     * @return True if the transfer was successful
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);

    /**
     * @dev Allows users to access the token's name
     */
    function name() external pure returns (string memory);

    /**
     * @dev Allows users to access the token's symbol
     */
    function symbol() external pure returns (string memory);

    /**
     * @dev Allows users to access the number of decimals
     */
    function decimals() external pure returns (uint8);

    /**
     * @dev Getter for the current variables that include the 5 requests Id's
     * @return _challenge _requestIds _difficultky _tip the challenge, 5 requestsId, difficulty and tip
     */
    function getNewCurrentVariables()
        external
        view
        returns (
            bytes32 _challenge,
            uint256[5] memory _requestIds,
            uint256 _difficutly,
            uint256 _tip
        );

    /**
     * @dev Getter for the top tipped 5 requests Id's
     * @return _requestIds the 5 requestsId
     */
    function getTopRequestIDs()
        external
        view
        returns (uint256[5] memory _requestIds);

    /**
     * @dev Getter for the 5 requests Id's next in line to get mined
     * @return idsOnDeck tipsOnDeck  the 5 requestsId
     */
    function getNewVariablesOnDeck()
        external
        view
        returns (uint256[5] memory idsOnDeck, uint256[5] memory tipsOnDeck);

    /**
     * @dev Updates the Tellor address after a proposed fork has
     * passed the vote and day has gone by without a dispute
     * @param _disputeId the disputeId for the proposed fork
     */
    function updateTellor(uint256 _disputeId) external;

    /**
     * @dev Allows disputer to unlock the dispute fee
     * @param _disputeId to unlock fee from
     */
    function unlockDisputeFee(uint256 _disputeId) external;

    /**
     * @param _user address
     * @param _spender address
     * @return Returns the remaining allowance of tokens granted to the _spender from the _user
     */
    function allowance(address _user, address _spender)
        external
        view
        returns (uint256);

    /**
     * @dev This function returns whether or not a given user is allowed to trade a given amount
     * @param _user address
     * @param _amount uint of amount
     * @return true if the user is alloed to trade the amount specified
     */
    function allowedToTrade(address _user, uint256 _amount)
        external
        view
        returns (bool);

    /**
     * @dev Gets balance of owner specified
     * @param _user is the owner address used to look up the balance
     * @return Returns the balance associated with the passed in _user
     */
    function balanceOf(address _user) external view returns (uint256);

    /**
     * @dev Queries the balance of _user at a specific _blockNumber
     * @param _user The address from which the balance will be retrieved
     * @param _blockNumber The block number when the balance is queried
     * @return The balance at _blockNumber
     */
    function balanceOfAt(address _user, uint256 _blockNumber)
        external
        view
        returns (uint256);

    /**
     * @dev This function tells you if a given challenge has been completed by a given miner
     * @param _challenge the challenge to search for
     * @param _miner address that you want to know if they solved the challenge
     * @return true if the _miner address provided solved the
     */
    function didMine(bytes32 _challenge, address _miner)
        external
        view
        returns (bool);

    /**
     * @dev Checks if an address voted in a given dispute
     * @param _disputeId to look up
     * @param _address to look up
     * @return bool of whether or not party voted
     */
    function didVote(uint256 _disputeId, address _address)
        external
        view
        returns (bool);

    /**
     * @dev allows Tellor to read data from the addressVars mapping
     * @param _data is the keccak256("variable_name") of the variable that is being accessed.
     * These are examples of how the variables are saved within other functions:
     * addressVars[keccak256("_owner")]
     * addressVars[keccak256("tellorContract")]
     * return address
     */
    function getAddressVars(bytes32 _data) external view returns (address);

    /**
     * @dev Gets all dispute variables
     * @param _disputeId to look up
     * @return bytes32 hash of dispute
     * @return bool executed where true if it has been voted on
     * @return bool disputeVotePassed
     * @return bool isPropFork true if the dispute is a proposed fork
     * @return address of reportedMiner
     * @return address of reportingParty
     * @return address of proposedForkAddress
     *    uint of requestId
     *    uint of timestamp
     *    uint of value
     *    uint of minExecutionDate
     *    uint of numberOfVotes
     *    uint of blocknumber
     *    uint of minerSlot
     *    uint of quorum
     *    uint of fee
     * @return int count of the current tally
     */
    function getAllDisputeVars(uint256 _disputeId)
        external
        view
        returns (
            bytes32,
            bool,
            bool,
            bool,
            address,
            address,
            address,
            uint256[9] memory,
            int256
        );

    /**
     * @dev Getter function for variables for the requestId being currently mined(currentRequestId)
     * @return current challenge, curretnRequestId, level of difficulty, api/query string, and granularity(number of decimals requested), total tip for the request
     */
    function getCurrentVariables()
        external
        view
        returns (
            bytes32,
            uint256,
            uint256,
            string memory,
            uint256,
            uint256
        );

    /**
     * @dev Checks if a given hash of miner,requestId has been disputed
     * @param _hash is the sha256(abi.encodePacked(_miners[2],_requestId));
     * @return uint disputeId
     */
    function getDisputeIdByDisputeHash(bytes32 _hash)
        external
        view
        returns (uint256);

    /**
     * @dev Checks for uint variables in the disputeUintVars mapping based on the disuputeId
     * @param _disputeId is the dispute id;
     * @param _data the variable to pull from the mapping. _data = keccak256("variable_name") where variable_name is
     * the variables/strings used to save the data in the mapping. The variables names are
     * commented out under the disputeUintVars under the Dispute struct
     * @return uint value for the bytes32 data submitted
     */
    function getDisputeUintVars(uint256 _disputeId, bytes32 _data)
        external
        view
        returns (uint256);

    /**
     * @dev Gets the a value for the latest timestamp available
     * @return value for timestamp of last proof of work submited
     * @return true if the is a timestamp for the lastNewValue
     */
    function getLastNewValue() external view returns (uint256, bool);

    /**
     * @dev Gets the a value for the latest timestamp available
     * @param _requestId being requested
     * @return value for timestamp of last proof of work submited and if true if it exist or 0 and false if it doesn't
     */
    function getLastNewValueById(uint256 _requestId)
        external
        view
        returns (uint256, bool);

    /**
     * @dev Gets blocknumber for mined timestamp
     * @param _requestId to look up
     * @param _timestamp is the timestamp to look up blocknumber
     * @return uint of the blocknumber which the dispute was mined
     */
    function getMinedBlockNum(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (uint256);

    /**
     * @dev Gets the 5 miners who mined the value for the specified requestId/_timestamp
     * @param _requestId to look up
     * @param _timestamp is the timestamp to look up miners for
     * @return the 5 miners' addresses
     */
    function getMinersByRequestIdAndTimestamp(
        uint256 _requestId,
        uint256 _timestamp
    ) external view returns (address[5] memory);

    /**
     * @dev Counts the number of values that have been submited for the request
     * if called for the currentRequest being mined it can tell you how many miners have submitted a value for that
     * request so far
     * @param _requestId the requestId to look up
     * @return uint count of the number of values received for the requestId
     */
    function getNewValueCountbyRequestId(uint256 _requestId)
        external
        view
        returns (uint256);

    /**
     * @dev Getter function for the specified requestQ index
     * @param _index to look up in the requestQ array
     * @return uint of reqeuestId
     */
    function getRequestIdByRequestQIndex(uint256 _index)
        external
        view
        returns (uint256);

    /**
     * @dev Getter function for requestId based on timestamp
     * @param _timestamp to check requestId
     * @return uint of reqeuestId
     */
    function getRequestIdByTimestamp(uint256 _timestamp)
        external
        view
        returns (uint256);

    /**
     * @dev Getter function for requestId based on the queryHash
     * @param _request is the hash(of string api and granularity) to check if a request already exists
     * @return uint requestId
     */
    function getRequestIdByQueryHash(bytes32 _request)
        external
        view
        returns (uint256);

    /**
     * @dev Getter function for the requestQ array
     * @return the requestQ arrray
     */
    function getRequestQ() external view returns (uint256[51] memory);

    /**
     * @dev Allowes access to the uint variables saved in the apiUintVars under the requestDetails struct
     * for the requestId specified
     * @param _requestId to look up
     * @param _data the variable to pull from the mapping. _data = keccak256("variable_name") where variable_name is
     * the variables/strings used to save the data in the mapping. The variables names are
     * commented out under the apiUintVars under the requestDetails struct
     * @return uint value of the apiUintVars specified in _data for the requestId specified
     */
    function getRequestUintVars(uint256 _requestId, bytes32 _data)
        external
        view
        returns (uint256);

    /**
     * @dev Gets the API struct variables that are not mappings
     * @param _requestId to look up
     * @return string of api to query
     * @return string of symbol of api to query
     * @return bytes32 hash of string
     * @return bytes32 of the granularity(decimal places) requested
     * @return uint of index in requestQ array
     * @return uint of current payout/tip for this requestId
     */
    function getRequestVars(uint256 _requestId)
        external
        view
        returns (
            string memory,
            string memory,
            bytes32,
            uint256,
            uint256,
            uint256
        );

    /**
     * @dev This function allows users to retireve all information about a staker
     * @param _staker address of staker inquiring about
     * @return uint current state of staker
     * @return uint startDate of staking
     */
    function getStakerInfo(address _staker)
        external
        view
        returns (uint256, uint256);

    /**
     * @dev Gets the 5 miners who mined the value for the specified requestId/_timestamp
     * @param _requestId to look up
     * @param _timestamp is the timestampt to look up miners for
     * @return address[5] array of 5 addresses ofminers that mined the requestId
     */
    function getSubmissionsByTimestamp(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (uint256[5] memory);

    /**
     * @dev Gets the timestamp for the value based on their index
     * @param _requestID is the requestId to look up
     * @param _index is the value index to look up
     * @return uint timestamp
     */
    function getTimestampbyRequestIDandIndex(uint256 _requestID, uint256 _index)
        external
        view
        returns (uint256);

    /**
     * @dev Getter for the variables saved under the TellorStorageStruct uintVars variable
     * @param _data the variable to pull from the mapping. _data = keccak256("variable_name") where variable_name is
     * the variables/strings used to save the data in the mapping. The variables names are
     * commented out under the uintVars under the TellorStorageStruct struct
     * This is an example of how data is saved into the mapping within other functions:
     * self.uintVars[keccak256("stakerCount")]
     * @return uint of specified variable
     */
    function getUintVar(bytes32 _data) external view returns (uint256);

    /**
     * @dev Getter function for next requestId on queue/request with highest payout at time the function is called
     * @return onDeck/info on request with highest payout-- RequestId, Totaltips, and API query string
     */
    function getVariablesOnDeck()
        external
        view
        returns (
            uint256,
            uint256,
            string memory
        );

    /**
     * @dev Gets the 5 miners who mined the value for the specified requestId/_timestamp
     * @param _requestId to look up
     * @param _timestamp is the timestamp to look up miners for
     * @return bool true if requestId/timestamp is under dispute
     */
    function isInDispute(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (bool);

    /**
     * @dev Retreive value from oracle based on timestamp
     * @param _requestId being requested
     * @param _timestamp to retreive data/value from
     * @return value for timestamp submitted
     */
    function retrieveData(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (uint256);

    /**
     * @dev Getter for the total_supply of oracle tokens
     * @return uint total supply
     */
    function totalSupply() external view returns (uint256);
}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperAgreement } from "./ISuperAgreement.sol";
import { ISuperToken } from "./ISuperToken.sol";
import { ISuperfluidToken  } from "./ISuperfluidToken.sol";
import { ISuperfluid } from "./ISuperfluid.sol";


/**
 * @dev Superfluid's Governance interface
 *
 * @author Superfluid
 */
interface ISuperfluidGovernance {

    /**
     * @dev Replace the current governance with a new governance
     */
    function replaceGovernance(
        ISuperfluid host,
        address newGov) external;

    /**
     * @dev Register a new agreement class
     */
    function registerAgreementClass(
        ISuperfluid host,
        address agreementClass) external;

    /**
     * @dev Update logics of the contracts
     *
     * NOTE:
     * - Because they might have inter-dependencies, it is good to have one single function to update them all
     */
    function updateContracts(
        ISuperfluid host,
        address hostNewLogic,
        address[] calldata agreementClassNewLogics,
        address superTokenFactoryNewLogic
    ) external;

    /**
     * @dev Update supertoken logic contract to the latest that is managed by the super token factory
     */
    function updateSuperTokenLogic(
        ISuperfluid host,
        ISuperToken token) external;

    /// @dev Get configuration as address value
    function getConfigAsAddress(
        ISuperfluid host,
        ISuperfluidToken superToken,
        bytes32 key) external view returns (address value);

    /// @dev Get configuration as uint256 value
    function getConfigAsUint256(
        ISuperfluid host,
        ISuperfluidToken superToken,
        bytes32 key) external view returns (uint256 value);

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperAgreement } from "./ISuperAgreement.sol";


/**
 * @title Superfluid's token interface.
 *
 * @author Superfluid
 */
interface ISuperfluidToken {

    /**************************************************************************
     * Basic information
     *************************************************************************/

    /**
     * @dev Get superfluid host contract address
     */
    function getHost() external view returns(address host);

    /**************************************************************************
     * Real-time balance functions
     *************************************************************************/

    /**
    * @dev Calculate the real balance of a user, taking in consideration all agreements of the account
    * @param account for the query
    * @param timestamp Time of balance
    * @return availableBalance Real-time balance
    * @return deposit Account deposit
    * @return owedDeposit Account owed Deposit
    */
    function realtimeBalanceOf(
       address account,
       uint256 timestamp
    )
        external view
        returns (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit);

    /// @dev realtimeBalanceOf with timestamp equals to block timestamp
    function realtimeBalanceOfNow(
       address account
    )
        external view
        returns (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit,
            uint256 timestamp);

    /**
    * @dev Check if one account is critical
    * @param account Account check if is critical by a future time
    * @param timestamp Time of balance
    * @return isCritical
    */
    function isAccountCritical(
        address account,
        uint256 timestamp
    )
        external view
        returns(bool isCritical);

    /**
    * @dev Check if one account is critical now
    * @param account Account check if is critical by a future time
    * @return isCritical
    */
    function isAccountCriticalNow(
        address account
    )
        external view
        returns(bool isCritical);

    /**
     * @dev Check if one account is solvent
     * @param account Account check if is solvent by a future time
     * @param timestamp Time of balance
     * @return isSolvent
     */
    function isAccountSolvent(
        address account,
        uint256 timestamp
    )
        external view
        returns(bool isSolvent);

    /**
     * @dev Check if one account is solvent now
     * @param account Account check if is solvent now
     * @return isSolvent
     */
    function isAccountSolventNow(
        address account
    )
        external view
        returns(bool isSolvent);

    /**
    * @dev Get a list of agreements that is active for the account
    * @dev An active agreement is one that has state for the account
    * @param account Account to query
    * @return activeAgreements List of accounts that have non-zero states for the account
    */
    function getAccountActiveAgreements(address account)
       external view
       returns(ISuperAgreement[] memory activeAgreements);


   /**************************************************************************
    * Super Agreement hosting functions
    *************************************************************************/

    /**
     * @dev Create a new agreement
     * @param id Agreement ID
     * @param data Agreement data
     */
    function createAgreement(
        bytes32 id,
        bytes32[] calldata data
    )
        external;

    /**
     * @dev Agreement creation event
     * @param agreementClass Contract address of the agreement
     * @param id Agreement ID
     * @param data Agreement data
     */
    event AgreementCreated(
        address indexed agreementClass,
        bytes32 id,
        bytes32[] data
    );

    /**
     * @dev Get data of the agreement
     * @param agreementClass Contract address of the agreement
     * @param id Agreement ID
     * @return data Data of the agreement
     */
    function getAgreementData(
        address agreementClass,
        bytes32 id,
        uint dataLength
    )
        external view
        returns(bytes32[] memory data);

    /**
     * @dev Create a new agreement
     * @param id Agreement ID
     * @param data Agreement data
     */
    function updateAgreementData(
        bytes32 id,
        bytes32[] calldata data
    )
        external;

    /**
     * @dev Agreement creation event
     * @param agreementClass Contract address of the agreement
     * @param id Agreement ID
     * @param data Agreement data
     */
    event AgreementUpdated(
        address indexed agreementClass,
        bytes32 id,
        bytes32[] data
    );

    /**
     * @dev Close the agreement
     * @param id Agreement ID
     */
    function terminateAgreement(
        bytes32 id,
        uint dataLength
    )
        external;

    /**
     * @dev Agreement termination event
     * @param agreementClass Contract address of the agreement
     * @param id Agreement ID
     */
    event AgreementTerminated(
        address indexed agreementClass,
        bytes32 id
    );

    /**
     * @dev Update agreement state slot
     * @param account Account to be updated
     *
     * NOTE
     * - To clear the storage out, provide zero-ed array of intended length
     */
    function updateAgreementStateSlot(
        address account,
        uint256 slotId,
        bytes32[] calldata slotData
    )
        external;

    /**
     * @dev Agreement account state updated event
     * @param agreementClass Contract address of the agreement
     * @param account Account updated
     * @param slotId slot id of the agreement state
     */
    event AgreementStateUpdated(
        address indexed agreementClass,
        address indexed account,
        uint256 slotId
    );

    /**
     * @dev Get data of the slot of the state of a agreement
     * @param agreementClass Contract address of the agreement
     * @param account Account to query
     * @param slotId slot id of the state
     * @param dataLength length of the state data
     */
    function getAgreementStateSlot(
        address agreementClass,
        address account,
        uint256 slotId,
        uint dataLength
    )
        external view
        returns (bytes32[] memory slotData);

    /**
     * @dev Agreement account state updated event
     * @param agreementClass Contract address of the agreement
     * @param account Account of the agrement
     * @param state Agreement state of the account
     */
    event AgreementAccountStateUpdated(
        address indexed agreementClass,
        address indexed account,
        bytes state
    );

    /**
     * @dev Settle balance from an account by the agreement.
     *      The agreement needs to make sure that the balance delta is balanced afterwards
     * @param account Account to query.
     * @param delta Amount of balance delta to be settled
     *
     * Modifiers:
     *  - onlyAgreement
     */
    function settleBalance(
        address account,
        int256 delta
    )
        external;

    /**
     * @dev Agreement liquidation event (DEPRECATED BY AgreementLiquidatedBy)
     * @param agreementClass Contract address of the agreement
     * @param id Agreement ID
     * @param penaltyAccount Account of the agreement to be penalized
     * @param rewardAccount Account that collect the reward
     * @param rewardAmount Amount of liquidation reward
     */
    event AgreementLiquidated(
        address indexed agreementClass,
        bytes32 id,
        address indexed penaltyAccount,
        address indexed rewardAccount,
        uint256 rewardAmount
    );

    /**
     * @dev System bailout occurred (DEPRECATIED BY AgreementLiquidatedBy)
     * @param bailoutAccount Account that bailout the penalty account
     * @param bailoutAmount Amount of account bailout
     */
    event Bailout(
        address indexed bailoutAccount,
        uint256 bailoutAmount
    );

    /**
     * @dev Agreement liquidation event (including agent account)
     * @param agreementClass Contract address of the agreement
     * @param id Agreement ID
     * @param liquidatorAccount Account of the agent that performed the liquidation.
     * @param penaltyAccount Account of the agreement to be penalized
     * @param bondAccount Account that collect the reward or bailout accounts
     * @param rewardAmount Amount of liquidation reward
     * @param bailoutAmount Amount of liquidation bailouot
     *
     * NOTE:
     * Reward account rule:
     * - if bailout is equal to 0, then
     *   - the bondAccount will get the rewardAmount,
     *   - the penaltyAccount will pay for the rewardAmount.
     * - if bailout is larger than 0, then
     *   - the liquidatorAccount will get the rewardAmouont,
     *   - the bondAccount will pay for both the rewardAmount and bailoutAmount,
     *   - the penaltyAccount will pay for the rewardAmount while get the bailoutAmount.
     */
    event AgreementLiquidatedBy(
        address liquidatorAccount,
        address indexed agreementClass,
        bytes32 id,
        address indexed penaltyAccount,
        address indexed bondAccount,
        uint256 rewardAmount,
        uint256 bailoutAmount
    );

    /**
     * @dev Make liquidation payouts
     * @param id Agreement ID
     * @param liquidator Address of the executer of liquidation
     * @param penaltyAccount Account of the agreement to be penalized
     * @param rewardAmount Amount of liquidation reward
     * @param bailoutAmount Amount of account bailout needed
     *
     * NOTE:
     * Liquidation rules:
     *  - If a bailout is required (bailoutAmount > 0)
     *     - the actual reward goes to the liquidator,
     *     - while the reward account becomes the bailout account
     *     - total bailout include: bailout amount + reward amount
     *
     * Modifiers:
     *  - onlyAgreement
     */
    function makeLiquidationPayouts
    (
        bytes32 id,
        address liquidator,
        address penaltyAccount,
        uint256 rewardAmount,
        uint256 bailoutAmount
    )
        external;

    /**************************************************************************
     * Function modifiers for access control and parameter validations
     *
     * While they cannot be explicitly stated in function definitions, they are
     * listed in function definition comments instead for clarity.
     *
     * NOTE: solidity-coverage not supporting it
     *************************************************************************/

     /// @dev The msg.sender must be host contract
     //modifier onlyHost() virtual;

    /// @dev The msg.sender must be a listed agreement.
    //modifier onlyAgreement() virtual;

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperfluid } from "./ISuperfluid.sol";
import { ISuperfluidToken } from "./ISuperfluidToken.sol";
import { TokenInfo } from "../tokens/TokenInfo.sol";
import { IERC777 } from "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Superfluid's super token (Superfluid Token + ERC20 + ERC777) interface
 *
 * @author Superfluid
 */
interface ISuperToken is ISuperfluidToken, TokenInfo, IERC20, IERC777 {

    /// @dev Initialize the contract
    function initialize(
        IERC20 underlyingToken,
        uint8 underlyingDecimals,
        string calldata n,
        string calldata s
    ) external;

    /**************************************************************************
    * TokenInfo & ERC777
    *************************************************************************/

    /**
     * @dev Returns the name of the token.
     */
    function name() external view override(IERC777, TokenInfo) returns (string memory);

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view override(IERC777, TokenInfo) returns (string memory);

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: SuperToken always uses 18 decimals.
     *
     * Note: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() external view override(TokenInfo) returns (uint8);

    /**************************************************************************
    * ERC20 & ERC777
    *************************************************************************/

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view override(IERC777, IERC20) returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by an account (`owner`).
     */
    function balanceOf(address account) external view override(IERC777, IERC20) returns(uint256 balance);

    /**************************************************************************
    * ERC20
    *************************************************************************/

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external override(IERC20) returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external override(IERC20) view returns (uint256);

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
    function approve(address spender, uint256 amount) external override(IERC20) returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override(IERC20) returns (bool);

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
     function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    /**************************************************************************
    * ERC777
    *************************************************************************/

    /**
     * @dev Returns the smallest part of the token that is not divisible. This
     * means all token operations (creation, movement and destruction) must have
     * amounts that are a multiple of this number.
     *
     * For super token contracts, this value is 1 always
     */
    function granularity() external view override(IERC777) returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * If send or receive hooks are registered for the caller and `recipient`,
     * the corresponding functions will be called with `data` and empty
     * `operatorData`. See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits a {Sent} event.
     *
     * Requirements
     *
     * - the caller must have at least `amount` tokens.
     * - `recipient` cannot be the zero address.
     * - if `recipient` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function send(address recipient, uint256 amount, bytes calldata data) external override(IERC777);

    /**
     * @dev Destroys `amount` tokens from the caller's account, reducing the
     * total supply.
     *
     * If a send hook is registered for the caller, the corresponding function
     * will be called with `data` and empty `operatorData`. See {IERC777Sender}.
     *
     * Emits a {Burned} event.
     *
     * Requirements
     *
     * - the caller must have at least `amount` tokens.
     */
    function burn(uint256 amount, bytes calldata data) external override(IERC777);

    /**
     * @dev Returns true if an account is an operator of `tokenHolder`.
     * Operators can send and burn tokens on behalf of their owners. All
     * accounts are their own operator.
     *
     * See {operatorSend} and {operatorBurn}.
     */
    function isOperatorFor(address operator, address tokenHolder) external override(IERC777) view returns (bool);

    /**
     * @dev Make an account an operator of the caller.
     *
     * See {isOperatorFor}.
     *
     * Emits an {AuthorizedOperator} event.
     *
     * Requirements
     *
     * - `operator` cannot be calling address.
     */
    function authorizeOperator(address operator) external override(IERC777);

    /**
     * @dev Revoke an account's operator status for the caller.
     *
     * See {isOperatorFor} and {defaultOperators}.
     *
     * Emits a {RevokedOperator} event.
     *
     * Requirements
     *
     * - `operator` cannot be calling address.
     */
    function revokeOperator(address operator) external override(IERC777);

    /**
     * @dev Returns the list of default operators. These accounts are operators
     * for all token holders, even if {authorizeOperator} was never called on
     * them.
     *
     * This list is immutable, but individual holders may revoke these via
     * {revokeOperator}, in which case {isOperatorFor} will return false.
     */
    function defaultOperators() external override(IERC777) view returns (address[] memory);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient`. The caller must
     * be an operator of `sender`.
     *
     * If send or receive hooks are registered for `sender` and `recipient`,
     * the corresponding functions will be called with `data` and
     * `operatorData`. See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits a {Sent} event.
     *
     * Requirements
     *
     * - `sender` cannot be the zero address.
     * - `sender` must have at least `amount` tokens.
     * - the caller must be an operator for `sender`.
     * - `recipient` cannot be the zero address.
     * - if `recipient` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function operatorSend(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external override(IERC777);

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the total supply.
     * The caller must be an operator of `account`.
     *
     * If a send hook is registered for `account`, the corresponding function
     * will be called with `data` and `operatorData`. See {IERC777Sender}.
     *
     * Emits a {Burned} event.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     * - the caller must be an operator for `account`.
     */
    function operatorBurn(
        address account,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external override(IERC777);

    /**************************************************************************
     * SuperToken custom token functions
     *************************************************************************/

    /**
     * @dev Mint new tokens for the account
     *
     * Modifiers:
     *  - onlySelf
     */
    function selfMint(
        address account,
        uint256 amount,
        bytes memory userData
    ) external;

   /**
    * @dev Burn existing tokens for the account
    *
    * Modifiers:
    *  - onlySelf
    */
   function selfBurn(
       address account,
       uint256 amount,
       bytes memory userData
   ) external;

    /**************************************************************************
     * SuperToken extra functions
     *************************************************************************/

    /**
     * @dev Transfer all available balance from `msg.sender` to `recipient`
     */
    function transferAll(address recipient) external;

    /**************************************************************************
     * ERC20 wrapping
     *************************************************************************/

    /**
     * @dev Return the underlying token contract
     * @return tokenAddr Underlying token address
     */
    function getUnderlyingToken() external view returns(address tokenAddr);

    /**
     * @dev Upgrade ERC20 to SuperToken.
     * @param amount Number of tokens to be upgraded (in 18 decimals)
     *
     * NOTE: It will use ´transferFrom´ to get tokens. Before calling this
     * function you should ´approve´ this contract
     */
    function upgrade(uint256 amount) external;

    /**
     * @dev Upgrade ERC20 to SuperToken and transfer immediately
     * @param to The account to received upgraded tokens
     * @param amount Number of tokens to be upgraded (in 18 decimals)
     * @param data User data for the TokensRecipient callback
     *
     * NOTE: It will use ´transferFrom´ to get tokens. Before calling this
     * function you should ´approve´ this contract
     */
    function upgradeTo(address to, uint256 amount, bytes calldata data) external;

    /**
     * @dev Token upgrade event
     * @param account Account where tokens are upgraded to
     * @param amount Amount of tokens upgraded (in 18 decimals)
     */
    event TokenUpgraded(
        address indexed account,
        uint256 amount
    );

    /**
     * @dev Downgrade SuperToken to ERC20.
     * @dev It will call transfer to send tokens
     * @param amount Number of tokens to be downgraded
     */
    function downgrade(uint256 amount) external;

    /**
     * @dev Token downgrade event
     * @param account Account whose tokens are upgraded
     * @param amount Amount of tokens downgraded
     */
    event TokenDowngraded(
        address indexed account,
        uint256 amount
    );

    /**************************************************************************
    * Batch Operations
    *************************************************************************/

    /**
    * @dev Perform ERC20 approve by host contract.
    * @param account The account owner to be approved.
    * @param spender The spender of account owner's funds.
    * @param amount Number of tokens to be approved.
    *
    * Modifiers:
    *  - onlyHost
    */
    function operationApprove(
        address account,
        address spender,
        uint256 amount
    ) external;

    /**
    * @dev Perform ERC20 transfer from by host contract.
    * @param account The account to spend sender's funds.
    * @param spender  The account where the funds is sent from.
    * @param recipient The recipient of thefunds.
    * @param amount Number of tokens to be transferred.
    *
    * Modifiers:
    *  - onlyHost
    */
    function operationTransferFrom(
        address account,
        address spender,
        address recipient,
        uint256 amount
    ) external;

    /**
    * @dev Upgrade ERC20 to SuperToken by host contract.
    * @param account The account to be changed.
    * @param amount Number of tokens to be upgraded (in 18 decimals)
    *
    * Modifiers:
    *  - onlyHost
    */
    function operationUpgrade(address account, uint256 amount) external;

    /**
    * @dev Downgrade ERC20 to SuperToken by host contract.
    * @param account The account to be changed.
    * @param amount Number of tokens to be downgraded (in 18 decimals)
    *
    * Modifiers:
    *  - onlyHost
    */
    function operationDowngrade(address account, uint256 amount) external;


    /**************************************************************************
    * Function modifiers for access control and parameter validations
    *
    * While they cannot be explicitly stated in function definitions, they are
    * listed in function definition comments instead for clarity.
    *
    * NOTE: solidity-coverage not supporting it
    *************************************************************************/

    /// @dev The msg.sender must be the contract itself
    //modifier onlySelf() virtual

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperToken } from "./ISuperToken.sol";

import {
    IERC20,
    ERC20WithTokenInfo
} from "../tokens/ERC20WithTokenInfo.sol";


interface ISuperTokenFactory {

    /**
     * @dev Get superfluid host contract address
     */
    function getHost() external view returns(address host);

    /// @dev Initialize the contract
    function initialize() external;

    /**
     * @dev Get the current super token logic used by the factory
     */
    function getSuperTokenLogic() external view returns (ISuperToken superToken);

    /**
     * @dev Upgradability modes
     */
    enum Upgradability {
        /// Non upgradable super token, `host.updateSuperTokenLogic` will revert
        NON_UPGRADABLE,
        /// Upgradable through `host.updateSuperTokenLogic` operation
        SEMI_UPGRADABLE,
        /// Always using the latest super token logic
        FULL_UPGRADABE
    }

    /**
     * @dev Create new super token wrapper for the underlying ERC20 token
     * @param underlyingToken Underlying ERC20 token
     * @param underlyingDecimals Underlying token decimals
     * @param upgradability Upgradability mode
     * @param name Super token name
     * @param symbol Super token symbol
     */
    function createERC20Wrapper(
        IERC20 underlyingToken,
        uint8 underlyingDecimals,
        Upgradability upgradability,
        string calldata name,
        string calldata symbol
    )
        external
        returns (ISuperToken superToken);

    /**
     * @dev Create new super token wrapper for the underlying ERC20 token with extra token info
     * @param underlyingToken Underlying ERC20 token
     * @param upgradability Upgradability mode
     * @param name Super token name
     * @param symbol Super token symbol
     *
     * NOTE:
     * - It assumes token provide the .decimals() function
     */
    function createERC20Wrapper(
        ERC20WithTokenInfo underlyingToken,
        Upgradability upgradability,
        string calldata name,
        string calldata symbol
    )
        external
        returns (ISuperToken superToken);

    function initializeCustomSuperToken(
        address customSuperTokenProxy
    )
        external;

    event SuperTokenLogicCreated(ISuperToken indexed tokenLogic);

    event SuperTokenCreated(ISuperToken indexed token);

    event CustomSuperTokenCreated(ISuperToken indexed token);

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperfluidToken } from "./ISuperfluidToken.sol";

/**
 * @title Superfluid's agreement interface.
 *
 * @author Superfluid
 */
interface ISuperAgreement {

    /**
     * @dev Initialize the agreement contract
     */
    function initialize() external;

    /**
     * @dev Get the type of the agreement class.
     */
    function agreementType() external view returns (bytes32);

    /**
     * @dev Calculate the real-time balance for the account of this agreement class.
     * @param account Account the state belongs to
     * @param time Future time used for the calculation.
     * @return dynamicBalance Dynamic balance portion of real-time balance of this agreement.
     * @return deposit Account deposit amount of this agreement.
     * @return owedDeposit Account owed deposit amount of this agreement.
     */
    function realtimeBalanceOf(
        ISuperfluidToken token,
        address account,
        uint256 time
    )
        external
        view
        returns (
            int256 dynamicBalance,
            uint256 deposit,
            uint256 owedDeposit
        );

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

import { ISuperToken } from "./ISuperToken.sol";


/**
 * @title Superfluid's app interface.
 *
 * NOTE:
 * - Be fearful of the app jail, when the word permitted is used.
 *
 * @author Superfluid
 */
interface ISuperApp {

    /**
     * @dev Callback before a new agreement is created.
     * @param superToken The super token used for the agreement.
     * @param agreementClass The agreement class address.
     * @param agreementId The agreementId
     * @param agreementData The agreement data (non-compressed)
     * @param ctx The context data.
     * @return cbdata A free format in memory data the app can use to pass
     *          arbitary information to the after-hook callback.
     *
     * NOTE:
     * - It will be invoked with `staticcall`, no state changes are permitted.
     * - Only revert with a "reason" is permitted.
     */
    function beforeAgreementCreated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata ctx
    )
        external
        view
        returns (bytes memory cbdata);

    /**
     * @dev Callback after a new agreement is created.
     * @param superToken The super token used for the agreement.
     * @param agreementClass The agreement class address.
     * @param agreementId The agreementId
     * @param agreementData The agreement data (non-compressed)
     * @param cbdata The data returned from the before-hook callback.
     * @param ctx The context data.
     * @return newCtx The current context of the transaction.
     *
     * NOTE:
     * - State changes is permitted.
     * - Only revert with a "reason" is permitted.
     */
    function afterAgreementCreated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata cbdata,
        bytes calldata ctx
    )
        external
        returns (bytes memory newCtx);

    /**
     * @dev Callback before a new agreement is updated.
     * @param superToken The super token used for the agreement.
     * @param agreementClass The agreement class address.
     * @param agreementId The agreementId
     * @param agreementData The agreement data (non-compressed)
     * @param ctx The context data.
     * @return cbdata A free format in memory data the app can use to pass
     *          arbitary information to the after-hook callback.
     *
     * NOTE:
     * - It will be invoked with `staticcall`, no state changes are permitted.
     * - Only revert with a "reason" is permitted.
     */
    function beforeAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata ctx
    )
        external
        view
        returns (bytes memory cbdata);


    /**
    * @dev Callback after a new agreement is updated.
    * @param superToken The super token used for the agreement.
    * @param agreementClass The agreement class address.
    * @param agreementId The agreementId
    * @param agreementData The agreement data (non-compressed)
    * @param cbdata The data returned from the before-hook callback.
    * @param ctx The context data.
    * @return newCtx The current context of the transaction.
    *
    * NOTE:
    * - State changes is permitted.
    * - Only revert with a "reason" is permitted.
    */
    function afterAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata cbdata,
        bytes calldata ctx
    )
        external
        returns (bytes memory newCtx);

    /**
    * @dev Callback before a new agreement is terminated.
    * @param superToken The super token used for the agreement.
    * @param agreementClass The agreement class address.
    * @param agreementId The agreementId
    * @param agreementData The agreement data (non-compressed)
    * @param ctx The context data.
    * @return cbdata A free format in memory data the app can use to pass
    *          arbitary information to the after-hook callback.
    *
    * NOTE:
    * - It will be invoked with `staticcall`, no state changes are permitted.
    * - Revert is not permitted.
    */
    function beforeAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata ctx
    )
        external
        view
        returns (bytes memory cbdata);

    /**
    * @dev Callback after a new agreement is terminated.
    * @param superToken The super token used for the agreement.
    * @param agreementClass The agreement class address.
    * @param agreementId The agreementId
    * @param agreementData The agreement data (non-compressed)
    * @param cbdata The data returned from the before-hook callback.
    * @param ctx The context data.
    * @return newCtx The current context of the transaction.
    *
    * NOTE:
    * - State changes is permitted.
    * - Revert is not permitted.
    */
    function afterAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata cbdata,
        bytes calldata ctx
    )
        external
        returns (bytes memory newCtx);
}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.7.0;

/**
 * @dev Super app definitions library
 */
library SuperAppDefinitions {

    /**************************************************************************
    / App manifest config word
    /**************************************************************************/

    /*
     * App level is a way to allow the app to whitelist what other app it can
     * interact with (aka. composite app feature).
     *
     * For more details, refer to the technical paper of superfluid protocol.
     */
    uint256 constant internal APP_LEVEL_MASK = 0xFF;

    // The app is at the final level, hence it doesn't want to interact with any other app
    uint256 constant internal APP_LEVEL_FINAL = 1 << 0;

    // The app is at the second level, it may interact with other final level apps if whitelisted
    uint256 constant internal APP_LEVEL_SECOND = 1 << 1;

    function getAppLevel(uint256 configWord) internal pure returns (uint8) {
        return uint8(configWord & APP_LEVEL_MASK);
    }

    uint256 constant internal APP_JAIL_BIT = 1 << 15;
    function isAppJailed(uint256 configWord) internal pure returns (bool) {
        return (configWord & SuperAppDefinitions.APP_JAIL_BIT) > 0;
    }

    /**************************************************************************
    / Callback implementation bit masks
    /**************************************************************************/
    uint256 constant internal AGREEMENT_CALLBACK_NOOP_BITMASKS = 0xFF << 32;
    uint256 constant internal BEFORE_AGREEMENT_CREATED_NOOP = 1 << (32 + 0);
    uint256 constant internal AFTER_AGREEMENT_CREATED_NOOP = 1 << (32 + 1);
    uint256 constant internal BEFORE_AGREEMENT_UPDATED_NOOP = 1 << (32 + 2);
    uint256 constant internal AFTER_AGREEMENT_UPDATED_NOOP = 1 << (32 + 3);
    uint256 constant internal BEFORE_AGREEMENT_TERMINATED_NOOP = 1 << (32 + 4);
    uint256 constant internal AFTER_AGREEMENT_TERMINATED_NOOP = 1 << (32 + 5);

    /**************************************************************************
    / App Jail Reasons
    /**************************************************************************/

    uint256 constant internal APP_RULE_REGISTRATION_ONLY_IN_CONSTRUCTOR = 1;
    uint256 constant internal APP_RULE_NO_REGISTRATION_FOR_EOA = 2;
    uint256 constant internal APP_RULE_NO_REVERT_ON_TERMINATION_CALLBACK = 10;
    uint256 constant internal APP_RULE_NO_CRITICAL_SENDER_ACCOUNT = 11;
    uint256 constant internal APP_RULE_NO_CRITICAL_RECEIVER_ACCOUNT = 12;
    uint256 constant internal APP_RULE_CTX_IS_READONLY = 20;
    uint256 constant internal APP_RULE_CTX_IS_NOT_CLEAN = 21;
    uint256 constant internal APP_RULE_CTX_IS_MALFORMATED = 22;
    uint256 constant internal APP_RULE_COMPOSITE_APP_IS_NOT_WHITELISTED = 30;
    uint256 constant internal APP_RULE_COMPOSITE_APP_IS_JAILED = 31;
    uint256 constant internal APP_RULE_MAX_APP_LEVEL_REACHED = 40;
}

/**
 * @dev Context definitions library
 */
library ContextDefinitions {

    /**************************************************************************
    / Call info
    /**************************************************************************/

    // app level
    uint256 constant internal CALL_INFO_APP_LEVEL_MASK = 0xFF;

    // call type
    uint256 constant internal CALL_INFO_CALL_TYPE_SHIFT = 32;
    uint256 constant internal CALL_INFO_CALL_TYPE_MASK = 0xF << CALL_INFO_CALL_TYPE_SHIFT;
    uint8 constant internal CALL_INFO_CALL_TYPE_AGREEMENT = 1;
    uint8 constant internal CALL_INFO_CALL_TYPE_APP_ACTION = 2;
    uint8 constant internal CALL_INFO_CALL_TYPE_APP_CALLBACK = 3;

    function decodeCallInfo(uint256 callInfo)
        internal pure
        returns (uint8 appLevel, uint8 callType)
    {
        appLevel = uint8(callInfo & CALL_INFO_APP_LEVEL_MASK);
        callType = uint8((callInfo & CALL_INFO_CALL_TYPE_MASK) >> CALL_INFO_CALL_TYPE_SHIFT);
    }

    function encodeCallInfo(uint8 appLevel, uint8 callType)
        internal pure
        returns (uint256 callInfo)
    {
        return uint256(appLevel) | (uint256(callType) << CALL_INFO_CALL_TYPE_SHIFT);
    }

}

/**
 * @dev Batch operation library
 */
library BatchOperation {
    /**
     * @dev ERC20.approve batch operation type
     *
     * Call spec:
     * ISuperToken(target).operationApprove(
     *     abi.decode(data, (address spender, uint256 amount))
     * )
     */
    uint32 constant internal OPERATION_TYPE_ERC20_APPROVE = 1;
    /**
     * @dev ERC20.transferFrom batch operation type
     *
     * Call spec:
     * ISuperToken(target).operationTransferFrom(
     *     abi.decode(data, (address sender, address recipient, uint256 amount)
     * )
     */
    uint32 constant internal OPERATION_TYPE_ERC20_TRANSFER_FROM = 2;
    /**
     * @dev SuperToken.upgrade batch operation type
     *
     * Call spec:
     * ISuperToken(target).operationUpgrade(
     *     abi.decode(data, (uint256 amount)
     * )
     */
    uint32 constant internal OPERATION_TYPE_SUPERTOKEN_UPGRADE = 1 + 100;
    /**
     * @dev SuperToken.downgrade batch operation type
     *
     * Call spec:
     * ISuperToken(target).operationDowngrade(
     *     abi.decode(data, (uint256 amount)
     * )
     */
    uint32 constant internal OPERATION_TYPE_SUPERTOKEN_DOWNGRADE = 2 + 100;
    /**
     * @dev Superfluid.callAgreement batch operation type
     *
     * Call spec:
     * callAgreement(
     *     ISuperAgreement(target)),
     *     abi.decode(data, (bytes calldata, bytes userdata)
     * )
     */
    uint32 constant internal OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT = 1 + 200;
    /**
     * @dev Superfluid.callAppAction batch operation type
     *
     * Call spec:
     * callAppAction(
     *     ISuperApp(target)),
     *     data
     * )
     */
    uint32 constant internal OPERATION_TYPE_SUPERFLUID_CALL_APP_ACTION = 2 + 200;
}

library SuperfluidGovernanceConfigs {

    bytes32 constant internal SUPERFLUID_REWARD_ADDRESS_CONFIG_KEY =
        keccak256("org.superfluid-finance.superfluid.rewardAddress");

    bytes32 constant internal CFAv1_LIQUIDATION_PERIOD_CONFIG_KEY =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1.liquidationPeriod");

    function getTrustedForwarderConfigKey(address forwarder) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            "org.superfluid-finance.superfluid.trustedForwarder",
            forwarder));
    }

    function getAppWhiteListingSecretKey(address deployer, string memory registrationkey) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            "org.superfluid-finance.superfluid.appWhiteListing.seed",
            deployer,
            registrationkey));
    }

}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.5.0;

/**
 * @dev ERC20 token info interface
 *
 * NOTE: ERC20 standard interface does not specify these functions, but
 * often the token implementations have them.
 *
 */
interface TokenInfo {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
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
 * @dev Interface of the ERC777Token standard as defined in the EIP.
 *
 * This contract uses the
 * https://eips.ethereum.org/EIPS/eip-1820[ERC1820 registry standard] to let
 * token holders and recipients react to token movements by using setting implementers
 * for the associated interfaces in said registry. See {IERC1820Registry} and
 * {ERC1820Implementer}.
 */
interface IERC777 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the smallest part of the token that is not divisible. This
     * means all token operations (creation, movement and destruction) must have
     * amounts that are a multiple of this number.
     *
     * For most token contracts, this value will equal 1.
     */
    function granularity() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by an account (`owner`).
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * If send or receive hooks are registered for the caller and `recipient`,
     * the corresponding functions will be called with `data` and empty
     * `operatorData`. See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits a {Sent} event.
     *
     * Requirements
     *
     * - the caller must have at least `amount` tokens.
     * - `recipient` cannot be the zero address.
     * - if `recipient` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function send(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @dev Destroys `amount` tokens from the caller's account, reducing the
     * total supply.
     *
     * If a send hook is registered for the caller, the corresponding function
     * will be called with `data` and empty `operatorData`. See {IERC777Sender}.
     *
     * Emits a {Burned} event.
     *
     * Requirements
     *
     * - the caller must have at least `amount` tokens.
     */
    function burn(uint256 amount, bytes calldata data) external;

    /**
     * @dev Returns true if an account is an operator of `tokenHolder`.
     * Operators can send and burn tokens on behalf of their owners. All
     * accounts are their own operator.
     *
     * See {operatorSend} and {operatorBurn}.
     */
    function isOperatorFor(address operator, address tokenHolder) external view returns (bool);

    /**
     * @dev Make an account an operator of the caller.
     *
     * See {isOperatorFor}.
     *
     * Emits an {AuthorizedOperator} event.
     *
     * Requirements
     *
     * - `operator` cannot be calling address.
     */
    function authorizeOperator(address operator) external;

    /**
     * @dev Revoke an account's operator status for the caller.
     *
     * See {isOperatorFor} and {defaultOperators}.
     *
     * Emits a {RevokedOperator} event.
     *
     * Requirements
     *
     * - `operator` cannot be calling address.
     */
    function revokeOperator(address operator) external;

    /**
     * @dev Returns the list of default operators. These accounts are operators
     * for all token holders, even if {authorizeOperator} was never called on
     * them.
     *
     * This list is immutable, but individual holders may revoke these via
     * {revokeOperator}, in which case {isOperatorFor} will return false.
     */
    function defaultOperators() external view returns (address[] memory);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient`. The caller must
     * be an operator of `sender`.
     *
     * If send or receive hooks are registered for `sender` and `recipient`,
     * the corresponding functions will be called with `data` and
     * `operatorData`. See {IERC777Sender} and {IERC777Recipient}.
     *
     * Emits a {Sent} event.
     *
     * Requirements
     *
     * - `sender` cannot be the zero address.
     * - `sender` must have at least `amount` tokens.
     * - the caller must be an operator for `sender`.
     * - `recipient` cannot be the zero address.
     * - if `recipient` is a contract, it must implement the {IERC777Recipient}
     * interface.
     */
    function operatorSend(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the total supply.
     * The caller must be an operator of `account`.
     *
     * If a send hook is registered for `account`, the corresponding function
     * will be called with `data` and `operatorData`. See {IERC777Sender}.
     *
     * Emits a {Burned} event.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     * - the caller must be an operator for `account`.
     */
    function operatorBurn(
        address account,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    event Sent(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data,
        bytes operatorData
    );

    event Minted(address indexed operator, address indexed to, uint256 amount, bytes data, bytes operatorData);

    event Burned(address indexed operator, address indexed from, uint256 amount, bytes data, bytes operatorData);

    event AuthorizedOperator(address indexed operator, address indexed tokenHolder);

    event RevokedOperator(address indexed operator, address indexed tokenHolder);
}

// SPDX-License-Identifier: AGPLv3
pragma solidity >= 0.5.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TokenInfo } from "./TokenInfo.sol";


/**
 *
 * @dev Interface for ERC20 token with token info
 *
 * NOTE: Using abstract contract instead of interfaces because old solidity
 * does not support interface inheriting other interfaces
 * solhint-disable-next-line no-empty-blocks
 *
 */
// solhint-disable-next-line no-empty-blocks
abstract contract ERC20WithTokenInfo is IERC20, TokenInfo {}

pragma solidity >=0.6.2;

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
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
        return msg.data;
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
pragma solidity >= 0.4.22 <0.9.0;

library console {
	address constant CONSOLE_ADDRESS = address(0x000000000000000000636F6e736F6c652e6c6f67);

	function _sendLogPayload(bytes memory payload) private view {
		uint256 payloadLength = payload.length;
		address consoleAddress = CONSOLE_ADDRESS;
		assembly {
			let payloadStart := add(payload, 32)
			let r := staticcall(gas(), consoleAddress, payloadStart, payloadLength, 0, 0)
		}
	}

	function log() internal view {
		_sendLogPayload(abi.encodeWithSignature("log()"));
	}

	function logInt(int p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(int)", p0));
	}

	function logUint(uint p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
	}

	function logString(string memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string)", p0));
	}

	function logBool(bool p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
	}

	function logAddress(address p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address)", p0));
	}

	function logBytes(bytes memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
	}

	function logBytes1(bytes1 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes1)", p0));
	}

	function logBytes2(bytes2 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes2)", p0));
	}

	function logBytes3(bytes3 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes3)", p0));
	}

	function logBytes4(bytes4 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes4)", p0));
	}

	function logBytes5(bytes5 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes5)", p0));
	}

	function logBytes6(bytes6 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes6)", p0));
	}

	function logBytes7(bytes7 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes7)", p0));
	}

	function logBytes8(bytes8 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes8)", p0));
	}

	function logBytes9(bytes9 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes9)", p0));
	}

	function logBytes10(bytes10 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes10)", p0));
	}

	function logBytes11(bytes11 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes11)", p0));
	}

	function logBytes12(bytes12 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes12)", p0));
	}

	function logBytes13(bytes13 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes13)", p0));
	}

	function logBytes14(bytes14 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes14)", p0));
	}

	function logBytes15(bytes15 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes15)", p0));
	}

	function logBytes16(bytes16 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes16)", p0));
	}

	function logBytes17(bytes17 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes17)", p0));
	}

	function logBytes18(bytes18 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes18)", p0));
	}

	function logBytes19(bytes19 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes19)", p0));
	}

	function logBytes20(bytes20 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes20)", p0));
	}

	function logBytes21(bytes21 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes21)", p0));
	}

	function logBytes22(bytes22 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes22)", p0));
	}

	function logBytes23(bytes23 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes23)", p0));
	}

	function logBytes24(bytes24 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes24)", p0));
	}

	function logBytes25(bytes25 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes25)", p0));
	}

	function logBytes26(bytes26 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes26)", p0));
	}

	function logBytes27(bytes27 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes27)", p0));
	}

	function logBytes28(bytes28 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes28)", p0));
	}

	function logBytes29(bytes29 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes29)", p0));
	}

	function logBytes30(bytes30 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes30)", p0));
	}

	function logBytes31(bytes31 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes31)", p0));
	}

	function logBytes32(bytes32 p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes32)", p0));
	}

	function log(uint p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
	}

	function log(string memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string)", p0));
	}

	function log(bool p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
	}

	function log(address p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address)", p0));
	}

	function log(uint p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint)", p0, p1));
	}

	function log(uint p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string)", p0, p1));
	}

	function log(uint p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool)", p0, p1));
	}

	function log(uint p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address)", p0, p1));
	}

	function log(string memory p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint)", p0, p1));
	}

	function log(string memory p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
	}

	function log(string memory p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool)", p0, p1));
	}

	function log(string memory p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
	}

	function log(bool p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint)", p0, p1));
	}

	function log(bool p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string)", p0, p1));
	}

	function log(bool p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool)", p0, p1));
	}

	function log(bool p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address)", p0, p1));
	}

	function log(address p0, uint p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint)", p0, p1));
	}

	function log(address p0, string memory p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string)", p0, p1));
	}

	function log(address p0, bool p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool)", p0, p1));
	}

	function log(address p0, address p1) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address)", p0, p1));
	}

	function log(uint p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint)", p0, p1, p2));
	}

	function log(uint p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string)", p0, p1, p2));
	}

	function log(uint p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool)", p0, p1, p2));
	}

	function log(uint p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool)", p0, p1, p2));
	}

	function log(uint p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address)", p0, p1, p2));
	}

	function log(uint p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint)", p0, p1, p2));
	}

	function log(uint p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string)", p0, p1, p2));
	}

	function log(uint p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool)", p0, p1, p2));
	}

	function log(uint p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address)", p0, p1, p2));
	}

	function log(uint p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint)", p0, p1, p2));
	}

	function log(uint p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string)", p0, p1, p2));
	}

	function log(uint p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool)", p0, p1, p2));
	}

	function log(uint p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool)", p0, p1, p2));
	}

	function log(string memory p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool)", p0, p1, p2));
	}

	function log(string memory p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool)", p0, p1, p2));
	}

	function log(string memory p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address)", p0, p1, p2));
	}

	function log(string memory p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint)", p0, p1, p2));
	}

	function log(string memory p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string)", p0, p1, p2));
	}

	function log(string memory p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool)", p0, p1, p2));
	}

	function log(string memory p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address)", p0, p1, p2));
	}

	function log(bool p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint)", p0, p1, p2));
	}

	function log(bool p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string)", p0, p1, p2));
	}

	function log(bool p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool)", p0, p1, p2));
	}

	function log(bool p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool)", p0, p1, p2));
	}

	function log(bool p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address)", p0, p1, p2));
	}

	function log(bool p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint)", p0, p1, p2));
	}

	function log(bool p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string)", p0, p1, p2));
	}

	function log(bool p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool)", p0, p1, p2));
	}

	function log(bool p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address)", p0, p1, p2));
	}

	function log(bool p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint)", p0, p1, p2));
	}

	function log(bool p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string)", p0, p1, p2));
	}

	function log(bool p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool)", p0, p1, p2));
	}

	function log(bool p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address)", p0, p1, p2));
	}

	function log(address p0, uint p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint)", p0, p1, p2));
	}

	function log(address p0, uint p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string)", p0, p1, p2));
	}

	function log(address p0, uint p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool)", p0, p1, p2));
	}

	function log(address p0, uint p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address)", p0, p1, p2));
	}

	function log(address p0, string memory p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint)", p0, p1, p2));
	}

	function log(address p0, string memory p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string)", p0, p1, p2));
	}

	function log(address p0, string memory p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool)", p0, p1, p2));
	}

	function log(address p0, string memory p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address)", p0, p1, p2));
	}

	function log(address p0, bool p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint)", p0, p1, p2));
	}

	function log(address p0, bool p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string)", p0, p1, p2));
	}

	function log(address p0, bool p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool)", p0, p1, p2));
	}

	function log(address p0, bool p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address)", p0, p1, p2));
	}

	function log(address p0, address p1, uint p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint)", p0, p1, p2));
	}

	function log(address p0, address p1, string memory p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string)", p0, p1, p2));
	}

	function log(address p0, address p1, bool p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool)", p0, p1, p2));
	}

	function log(address p0, address p1, address p2) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address)", p0, p1, p2));
	}

	function log(uint p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,uint,address,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,string,address,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,bool,address,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,uint,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,string,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,bool,address)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,uint)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,string)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,bool)", p0, p1, p2, p3));
	}

	function log(uint p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint,address,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,uint,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,string,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,bool,address,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,uint,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,string,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,bool,address)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,uint)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,string)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,bool)", p0, p1, p2, p3));
	}

	function log(string memory p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string,address,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,uint,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,string,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,bool,address,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,uint,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,string,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,bool,address)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,uint)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,string)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,bool)", p0, p1, p2, p3));
	}

	function log(bool p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool,address,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, uint p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,uint,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, string memory p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,string,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, bool p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,bool,address,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, uint p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,uint,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, string memory p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,string,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, bool p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,bool,address)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, uint p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,uint)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, string memory p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,string)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, bool p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,bool)", p0, p1, p2, p3));
	}

	function log(address p0, address p1, address p2, address p3) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address,address,address,address)", p0, p1, p2, p3));
	}

}

