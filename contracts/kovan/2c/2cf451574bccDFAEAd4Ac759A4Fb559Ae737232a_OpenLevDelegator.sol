// SPDX-License-Identifier: MIT


pragma solidity 0.7.3;

abstract contract Adminable {
    address payable public admin;
    address payable public pendingAdmin;

    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    event NewAdmin(address oldAdmin, address newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "caller must be admin");
        _;
    }

    function setPendingAdmin(address payable newPendingAdmin) external virtual onlyAdmin {
        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;
        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;
        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    function acceptAdmin() external virtual {
        require(msg.sender == pendingAdmin, "only pendingAdmin can accept admin");
        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;
        // Store admin with value pendingAdmin
        admin = pendingAdmin;
        // Clear the pending value
        pendingAdmin = address(0);
        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./liquidity/LPoolInterface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract ControllerStorage {

    //lpool-pair
    struct LPoolPair {
        address lpool0;
        address lpool1;
    }
    //lpool-distribution
    struct LPoolDistribution {
        uint64 startTime;
        uint64 endTime;
        uint64 duration;
        uint64 lastUpdateTime;
        uint256 totalAmount;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
    }
    //lpool-rewardByAccount
    struct LPoolRewardByAccount {
        uint rewardPerTokenStored;
        uint rewards;
    }

    struct OLETokenDistribution {
        uint liquidatorBalance;
        uint liquidatorMaxPer;
        uint liquidatorOLERatio;
        uint supplyBorrowBalance;
    }

    uint64 public constant LPOOL_DISTRIBUTION_MIN_DURATION = 30 days;

    ERC20 public oleToken;

    address public wChainToken;

    address public lpoolImplementation;

    //interest param
    uint256 public baseRatePerBlock;
    uint256 public multiplierPerBlock;
    uint256 public jumpMultiplierPerBlock;
    uint256 public kink;

    address public openLev;

    bool public tradeAllowed = true;

    OLETokenDistribution public oleTokenDistribution;
    //token0=>token1=>pair
    mapping(address => mapping(address => LPoolPair)) public lpoolPairs;
    //marketId=>isDistribution
    mapping(uint => bool) public marketLiqDistribution;
    //pool=>allowed
    mapping(address => bool) public lpoolUnAlloweds;
    //pool=>bool=>distribution(true is borrow,false is supply)
    mapping(LPoolInterface => mapping(bool => LPoolDistribution)) public lpoolDistributions;
    //pool=>bool=>distribution(true is borrow,false is supply)
    mapping(LPoolInterface => mapping(bool => mapping(address => LPoolRewardByAccount))) public lPoolRewardByAccounts;

    event LPoolPairCreated(address token0, address pool0, address token1, address pool1, uint16 marketId, uint32 marginRatio);

    event Distribution2Pool(address pool, uint supplyAmount, uint borrowerAmount, uint64 startTime, uint64 duration);

}
/**
  * @title Controller
  * @author OpenLeverage
  */
interface ControllerInterface {

    /*** Policy Hooks ***/

    function mintAllowed(address lpool, address minter, uint mintAmount) external;

    function transferAllowed(address lpool, address from, address to) external;

    function redeemAllowed(address lpool, address redeemer, uint redeemTokens) external;

    function borrowAllowed(address lpool, address borrower, address payee, uint borrowAmount) external;

    function repayBorrowAllowed(address lpool, address payer, address borrower, uint repayAmount) external;

    function liquidateAllowed(uint marketId, address liqMarker, address liquidator, uint liquidateAmount) external;

    function marginTradeAllowed(uint marketId) external;

    function createLPoolPair(address tokenA, address tokenB, uint32 marginRatio) external;

    /*** Admin Functions ***/

    function setLPoolImplementation(address _lpoolImplementation) external;

    function setOpenLev(address _openlev) external;

    function setInterestParam(uint256 _baseRatePerBlock, uint256 _multiplierPerBlock, uint256 _jumpMultiplierPerBlock, uint256 _kink) external;

    function setLPoolUnAllowed(address lpool, bool unAllowed) external;

    function setMarginTradeAllowed(bool isAllowed) external;

    // liquidatorOLERatio: Two decimal in percentage, ex. 300% => 300
    function setOLETokenDistribution(uint moreLiquidatorBalance, uint liquidatorMaxPer, uint liquidatorOLERatio, uint moreSupplyBorrowBalance) external;

    function distributeRewards2Pool(address pool, uint supplyAmount, uint borrowAmount, uint64 startTime, uint64 duration) external;

    function distributeRewards2PoolMore(address pool, uint supplyAmount, uint borrowAmount) external;

    function distributeLiqRewards2Market(uint marketId, bool isDistribution) external;

    /***Distribution Functions ***/

    function earned(LPoolInterface lpool, address account, bool isBorrow) external view returns (uint256);

    function getSupplyRewards(LPoolInterface[] calldata lpools, address account) external;

}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;


contract DelegateInterface {
    /**
     * Implementation address for this contract
     */
    address public implementation;

}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;


abstract contract DelegatorInterface {
    /**
     * Implementation address for this contract
     */
    address public implementation;

    /**
     * Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function setImplementation(address implementation_) public virtual;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./OpenLevInterface.sol";
import "./Types.sol";
import "./dex/PriceOracleInterface.sol";
import "./Adminable.sol";
import "./DelegatorInterface.sol";
import "./dex/IUniswapV2Callee.sol";


/**
  * @title OpenLevDelegator
  * @author OpenLeverage
  */
contract OpenLevDelegator is DelegatorInterface, OpenLevInterface, OpenLevStorage, Adminable, IUniswapV2Callee {

    constructor(
        ControllerInterface _controller,
        IUniswapV2Factory _uniswapFactory,
        address _treasury,
        PriceOracleInterface _priceOracle,
        ReferralInterface referral,
        address payable _admin,
        address implementation_){
        admin = msg.sender;
        // Creator of the contract is admin during initialization
        // First delegate gets to initialize the delegator (i.e. storage contract)
        delegateTo(implementation_, abi.encodeWithSignature("initialize(address,address,address,address,address)",
            _controller,
            _treasury,
            _priceOracle,
            _uniswapFactory,
            referral));
        implementation = implementation_;

        // Set the proper admin now that initialization is done
        admin = _admin;
    }

    /**
     * Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     */
    function setImplementation(address implementation_) public override onlyAdmin {
        address oldImplementation = implementation;
        implementation = implementation_;
        emit NewImplementation(oldImplementation, implementation);
    }

    function addMarket(
        LPoolInterface pool0,
        LPoolInterface pool1,
        uint32 marginRatio
    ) external override returns (uint16){
        bytes memory data = delegateToImplementation(abi.encodeWithSignature("addMarket(address,address,uint32)", pool0, pool1, marginRatio));
        return abi.decode(data, (uint16));
    }

    function marginTrade(
        uint16 marketId,
        bool longToken,
        bool depositToken,
        uint deposit,
        uint borrow,
        uint minBuyAmount,
        address referrer
    ) external override {
        delegateToImplementation(abi.encodeWithSignature("marginTrade(uint16,bool,bool,uint256,uint256,uint256,address)",
            marketId, longToken, depositToken, deposit, borrow, minBuyAmount, referrer));
    }

    function closeTrade(uint16 marketId, bool longToken, uint closeAmount, uint minBuyAmount) external override {
        delegateToImplementation(abi.encodeWithSignature("closeTrade(uint16,bool,uint256,uint256)",
            marketId, longToken, closeAmount, minBuyAmount));
    }


    function marginRatio(address owner, uint16 marketId, bool longToken) external override view returns (uint current, uint32 marketLimit){
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("marginRatio(address,uint16,bool)", owner, marketId, longToken));
        return abi.decode(data, (uint, uint32));
    }

    function liqMarker(address owner, uint16 marketId, bool longToken) external override {
        delegateToImplementation(abi.encodeWithSignature("liqMarker(address,uint16,bool)",
            owner, marketId, longToken));
    }

    function liqMarkerReset(address owner, uint16 marketId, bool longToken) external override {
        delegateToImplementation(abi.encodeWithSignature("liqMarkerReset(address,uint16,bool)",
            owner, marketId, longToken));
    }

    function liquidate(address owner, uint16 marketId, bool longToken) external override {
        delegateToImplementation(abi.encodeWithSignature("liquidate(address,uint16,bool)",
            owner, marketId, longToken));
    }

    /*** uniswap Functions ***/

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        delegateToImplementation(abi.encodeWithSignature("uniswapV2Call(address,uint256,uint256,bytes)",
            sender, amount0, amount1, data));
    }

    //
    //    function hswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
    //        delegateToImplementation(abi.encodeWithSignature("hswapV2Call(address,uint256,uint256,bytes)",
    //            sender, amount0, amount1, data));
    //    }
    //
    //    function pancakeCall(address sender, uint amount0, uint amount1, bytes calldata data) external override {
    //        delegateToImplementation(abi.encodeWithSignature("pancakeCall(address,uint256,uint256,bytes)",
    //            sender, amount0, amount1, data));
    //    }

    function calBuyAmount(address buyToken, address sellToken, uint sellAmount) external override view returns (uint){
        bytes memory data = delegateToViewImplementation(abi.encodeWithSignature("calBuyAmount(address,address,uint256)", buyToken, sellToken, sellAmount));
        return abi.decode(data, (uint));
    }

    /*** Admin Functions ***/

    function setDefaultMarginRatio(uint32 newRatio) external override {
        delegateToImplementation(abi.encodeWithSignature("setDefaultMarginRatio(uint32)", newRatio));
    }

    function setMarketMarginLimit(uint16 marketId, uint32 newRatio) external override {
        delegateToImplementation(abi.encodeWithSignature("setMarketMarginLimit(uint16,uint32)", marketId, newRatio));
    }

    function setFeesRate(uint newRate) external override {
        delegateToImplementation(abi.encodeWithSignature("setFeesRate(uint256)", newRate));
    }

    function setInsuranceRatio(uint8 newRatio) external override {
        delegateToImplementation(abi.encodeWithSignature("setInsuranceRatio(uint8)", newRatio));
    }

    function setController(address newController) external override {
        delegateToImplementation(abi.encodeWithSignature("setController(address)", newController));
    }

    function setPriceOracle(PriceOracleInterface newPriceOracle) external override {
        delegateToImplementation(abi.encodeWithSignature("setPriceOracle(address)", newPriceOracle));
    }

    function setUniswapFactory(IUniswapV2Factory _uniswapFactory) external override {
        delegateToImplementation(abi.encodeWithSignature("setUniswapFactory(address)", _uniswapFactory));
    }
    function setReferral(ReferralInterface  _referral) external override {
        delegateToImplementation(abi.encodeWithSignature("setReferral(address)", _referral));
    }

    function moveInsurance(uint16 marketId, uint8 poolIndex, address to, uint amount) external override {
        delegateToImplementation(abi.encodeWithSignature("moveInsurance(uint16,uint8,address,uint256)", marketId, poolIndex, to, amount));
    }

    function delegateTo(address callee, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = callee.delegatecall(data);
        assembly {
            if eq(success, 0) {revert(add(returnData, 0x20), returndatasize())}
        }
        return returnData;
    }

    function delegateToImplementation(bytes memory data) public returns (bytes memory) {
        return delegateTo(implementation, data);
    }

    function delegateToViewImplementation(bytes memory data) public view returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).staticcall(abi.encodeWithSignature("delegateToImplementation(bytes)", data));
        assembly {
            if eq(success, 0) {revert(add(returnData, 0x20), returndatasize())}
        }
        return abi.decode(returnData, (bytes));
    }

    /**
     * Delegates execution to an implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     */
    receive() external payable {
        require(msg.value == 0, "cannot send value to fallback");
        // delegate all other functions to current implementation
        (bool success,) = implementation.delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 {revert(free_mem_ptr, returndatasize())}
            default {return (free_mem_ptr, returndatasize())}
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./Types.sol";
import "./liquidity/LPoolInterface.sol";
import "./ControllerInterface.sol";
import "./dex/IUniswapV2Factory.sol";
import "./dex/PriceOracleInterface.sol";
import "./Referral.sol";


abstract contract OpenLevStorage {
    using SafeMath for uint;
    using SafeERC20 for IERC20;


    // number of markets
    uint16 public numPairs;

    // marketId => Pair
    mapping(uint16 => Types.Market) public markets;

    // owner => marketId => long0(true)/long1(false) => Trades
    mapping(address => mapping(uint16 => mapping(bool => Types.Trade))) public activeTrades;

    /**
     * @dev Total number of Ltokens in circulation
     */
    uint public _totalSupply;

    /**
     * @dev Official record of Ltoken balances for each account
     */
    //    mapping(address => uint) internal balance;

    address public treasury;

    ReferralInterface public referral;

    PriceOracleInterface public priceOracle;

    address public controller;

    event NewFeesRate(uint oldFeesRate, uint newFeesRate);

    event NewDefaultMarginRatio(uint32 oldRatio, uint32 newRatio);

    event NewMarketMarginLimit(uint16 marketId, uint32 oldRatio, uint32 newRatio);

    event NewInsuranceRatio(uint8 oldInsuranceRatio, uint8 newInsuranceRatio);

    event NewController(address oldController, address newController);

    event NewPriceOracle(PriceOracleInterface oldPriceOracle, PriceOracleInterface newPriceOracle);

    event NewUniswapFactory(IUniswapV2Factory oldUniswapFactory, IUniswapV2Factory newUniswapFactory);

    event NewReferral(ReferralInterface oldReferral, ReferralInterface newReferral);


    // 0.3%
    uint public feesRate = 30; // 0.003

    uint8 public insuranceRatio = 33; // 33%

    uint32 public defaultMarginRatio = 3000; // 30%

    event MarginTrade(
        address trader,
        uint16 marketId,
        bool longToken, // 0 => long token 0; 1 => long token 1;
        bool depositToken,
        uint deposited,
        uint borrowed,
        uint held,
        uint fees,
        uint atPrice,
        uint8 priceDecimals
    );

    event TradeClosed(
        address owner,
        uint16 marketId,
        bool longToken,
        uint closeAmount,
        uint depositDecrease,
        uint depositReturn,
        uint fees,
        uint atPrice,
        uint8 priceDecimals
    );

    event LiquidationMarker(
        address owner,
        uint16 marketId,
        bool longToken,
        address marker,
        uint atPrice,
        uint8 priceDecimals
    );
    event LiquidationMarkerReset(
        address owner,
        uint16 marketId,
        bool longToken,
        address marker,
        address resetBy,
        uint atPrice,
        uint8 priceDecimals
    );
    event Liquidation(
        address owner,
        uint16 marketId,
        bool longToken,
        uint liquidationAmount,
        address liquidator1,
        address liquidator2,
        uint depositDecrease,
        uint depositReturn,
        uint atPrice,
        uint8 priceDecimals
    );
}

/**
  * @title OpenLevInterface
  * @author OpenLeverage
  */
interface OpenLevInterface {

    function addMarket(
        LPoolInterface pool0,
        LPoolInterface pool1,
        uint32 marginRatio
    ) external returns (uint16);


    function marginTrade(
        uint16 marketId,
        bool longToken,
        bool depositToken,
        uint deposit,
        uint borrow,
        uint minBuyAmount,
        address referrer
    ) external;

    function closeTrade(uint16 marketId, bool longToken, uint closeAmount, uint minBuyAmount) external;

    function marginRatio(address owner, uint16 marketId, bool longToken) external view returns (uint current, uint32 marketLimit);

    function liqMarker(address owner, uint16 marketId, bool longToken) external;

    function liqMarkerReset(address owner, uint16 marketId, bool longToken) external;

    function liquidate(address owner, uint16 marketId, bool longToken) external;


    /*** Admin Functions ***/

    function setDefaultMarginRatio(uint32 newRatio) external;

    function setMarketMarginLimit(uint16 marketId, uint32 newRatio) external;

    function setFeesRate(uint newRate) external;

    function setInsuranceRatio(uint8 newRatio) external;

    function setController(address newController) external;

    function setPriceOracle(PriceOracleInterface newPriceOracle) external;

    function setUniswapFactory(IUniswapV2Factory _uniswapFactory) external;

    function setReferral(ReferralInterface _referral) external;

    function moveInsurance(uint16 marketId, uint8 poolIndex, address to, uint amount) external;


}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./OpenLevInterface.sol";
import "./ReferralInterface.sol";
import "./Adminable.sol";
import "./DelegateInterface.sol";

contract Referral is DelegateInterface, ReferralInterface, ReferralStorage, Adminable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    constructor() {}

    function initialize(address _openLev) external {
        require(msg.sender == admin, "not admin");
        openLev = _openLev;
    }

    function registerReferrer() override external {
        Account storage account = accounts[msg.sender];
        require(!account.isActive, "Already registered");
        account.isActive = true;
        emit NewReferrer(msg.sender);
    }

    function calReferralReward(address referee, address referrer, uint baseAmount, address token) external override returns (uint referrerReward, uint refereeDiscount) {
        require(msg.sender == openLev, "Only call from OpenLev allowed");
        require(referee != address(0), "Referee empty");

        Account storage refereeAcct = accounts[referee];
        address registeredReferrer = refereeAcct.referrer;

        // make referee as a active user and referrer after any trade
        if (!refereeAcct.isActive) {
            refereeAcct.isActive = true;
            emit NewReferrer(msg.sender);
        }

        if (registeredReferrer != address(0)) {// already has registered referrer, ignoring the one passed in
            Account storage registeredReferrerAcct = accounts[registeredReferrer];
            return payReward(registeredReferrerAcct, baseAmount, token);
        } else {
            if (referrer == address(0)) {// not found registeredReferrer and not passed-in any referrer
                return (0, 0);
            } else {// new referrer
                require(!isCircularReference(referrer, referee), "Circular referral");
                Account storage referrerAcct = accounts[referrer];

                // only make referral if referrer is active
                if (referrerAcct.isActive) {
                    refereeAcct.referrer = referrer;
                    referrerAcct.referredCount = referrerAcct.referredCount.add(1);
                    emit RegisteredReferral(referee, referrer);
                    return payReward(referrerAcct, baseAmount, token);
                } else {// referrer inactive
                    return (0, 0);
                }
            }
        }
    }

    function getReward(address referrer, address token) external view override returns (uint){
        return accounts[referrer].reward[token];
    }

    function withdrawReward(address token) external override {
        uint withdrawAmt = accounts[msg.sender].reward[token];
        require(withdrawAmt > 0, "balance is 0");
        accounts[msg.sender].reward[token] = 0;
        IERC20(token).transfer(msg.sender, withdrawAmt);
    }

    function payReward(Account storage referrerAcct, uint baseAmount, address token) internal returns (uint, uint) {
        uint firstLevelReward = calAmount(firstLevelRate, baseAmount);
        referrerAcct.reward[token] = referrerAcct.reward[token].add(firstLevelReward);
        uint calRefereeDiscount = calAmount(refereeDiscount, baseAmount);

        if (referrerAcct.referrer != address(0)) {// two level referral
            uint secondLevelReward = calAmount(secondLevelRate, baseAmount);
            Account storage upperReferrerAcct = accounts[referrerAcct.referrer];
            upperReferrerAcct.reward[token] = upperReferrerAcct.reward[token].add(secondLevelReward);
            return (firstLevelReward.add(secondLevelReward), calRefereeDiscount);
        } else {
            return (firstLevelReward, calRefereeDiscount);
        }
    }

    function calAmount(uint rate, uint baseAmount) internal pure returns (uint){
        return baseAmount.mul(rate).div(100);
    }

    function isCircularReference(address referrer, address referee) internal view returns (bool){
        address parent = referrer;

        for (uint i; i < 5; i++) {
            if (parent == address(0)) {
                break;
            }
            if (parent == referee) {
                return true;
            }
            parent = accounts[parent].referrer;
        }
        return false;
    }

    /*** Admin Functions ***/

    function setRate(uint _firstLevelRate, uint _secondLevelRate, uint _refereeDiscount) override external onlyAdmin {
        firstLevelRate = _firstLevelRate;
        secondLevelRate = _secondLevelRate;
        refereeDiscount = _refereeDiscount;
    }

    function setOpenLev(address _openLev) override external onlyAdmin {
        openLev = _openLev;
    }

}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

abstract contract ReferralStorage {
    using SafeMath for uint;

    struct Account {
        address referrer;
        mapping(address => uint) reward; // Reward by token
        uint referredCount;
        bool isActive;
    }

    address public openLev;
    uint public firstLevelRate = 16;
    uint public secondLevelRate = 8;
    uint public refereeDiscount = 8;

    mapping(address => Account) public accounts;

    event NewReferrer(address referrer);

    event RegisteredReferral(address referee, address referrer);
}

interface ReferralInterface {


    function registerReferrer() external;

    function calReferralReward(address referee, address referrer, uint baseAmount, address token) external returns (uint referrerReward, uint refereeDiscount);

    function getReward(address referrer, address token) external view returns (uint);

    function withdrawReward(address token) external;

    /*** Admin Functions ***/

    function setRate(uint _firstLevelRate, uint _secondLevelRate, uint _refereeDiscount) external;

    function setOpenLev(address _openLev) external;


}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "./liquidity/LPoolInterface.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


library Types {
    using SafeERC20 for IERC20;

    struct Market {// Market info
        LPoolInterface pool0;       // Lending Pool 0
        LPoolInterface pool1;       // Lending Pool 1
        uint32 marginRatio;         // Margin ratio limit for specific trading pair. Two decimal in percentage, ex. 15.32% => 1532
        uint pool0Insurance;        // Insurance balance for token 0
        uint pool1Insurance;        // Insurance balance for token 1
    }

    struct MarketVars {// A variables holder for market info
        LPoolInterface buyPool;     // Lending pool address of the token to buy. It's a calculated field on open or close trade.
        LPoolInterface sellPool;    // Lending pool address of the token to sell. It's a calculated field on open or close trade.
        IERC20 buyToken;            // Token to buy
        IERC20 sellToken;           // Token to sell
        uint buyPoolInsurance;      // Insurance balance of token to buy
        uint sellPoolInsurance;     // Insurance balance of token to sell
        uint32 marginRatio;         // Margin Ratio Limit for specific trading pair.
    }

    struct TradeVars {// A variables holder for trade info
        uint depositValue;          // Deposit value
        IERC20 depositErc20;        // Deposit Token address
        uint fees;                  // Fees value
        uint depositAfterFees;      // Deposit minus fees
        uint tradeSize;             // Trade amount to be swap on DEX
        uint newHeld;               // Latest held position
    }

    struct CloseTradeVars {// A variables holder for close trade info
        uint closeRatio;          // Close ratio
        bool isPartialClose;        // Is partial close
        uint closeAmountAfterFees;  // Close amount sub Fees value
        uint repayAmount;           // Repay to pool value
        uint depositDecrease;       // Deposit decrease
        uint depositReturn;         // Deposit actual returns
        uint fees;                  // Fees value
        uint settlePrice;           // Settle price at close
        uint8 priceDecimals;        // Settle price decimal at close
    }

    struct Trade {// Trade storage
        uint deposited;             // Balance of deposit token
        uint held;                  // Balance of held position
        address liqMarker;          // Address of who marks the trade liquidating
        uint liqBlockNum;           // Block number when the trade was marked liquidating
        bool depositToken;          // Indicate if the deposit token is token 0 or token 1
        uint lastBlockNum;          // Block number when the trade was touched last time, to prevent more than one operation within same block
    }

    struct LiquidateVars {// A variable holder for liquidation process
        uint settlePrice;           // Settle price at liquidation
        uint8 priceDecimals;        // Settle price decimal at liquidation
        uint borrowed;              // Total borrowed balance of trade
        uint fees;                  // Fees for liquidation process
        uint remaining;             // Remaining token for repayment
        bool isSellAllHeld;         // Is need sell all held
        uint depositDecrease;       // Deposit decrease
        uint depositReturn;         // Deposit actual returns
    }


}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "./IUniswapV2Factory.sol";

abstract contract IUniswapV2Callee {
    IUniswapV2Factory public uniswapFactory;

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external virtual;

//    function hswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external virtual;
//
//    function pancakeCall(address sender, uint amount0, uint amount1, bytes calldata data) external virtual;

    function calBuyAmount(address buyToken, address sellToken, uint sellAmount) external virtual view returns (uint) ;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
//mainnet:0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f

interface IUniswapV2Factory {

    function getPair(address tokenA, address tokenB) external view returns (address pair);

}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface PriceOracleInterface {
    //price,decimals
    function getPrice(address desToken, address quoteToken) external view returns (uint256, uint8);

}

// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;


abstract contract LPoolStorage {

    //Guard variable for re-entrancy checks
    bool internal _notEntered;

    /**
     * EIP-20 token name for this token
     */
    string public name;

    /**
     * EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * EIP-20 token decimals for this token
     */
    uint8 public decimals;

    /**
    * Total number of tokens in circulation
    */
    uint public totalSupply;


    //Official record of token balances for each account
    mapping(address => uint) internal accountTokens;

    //Approved token transfer amounts on behalf of others
    mapping(address => mapping(address => uint)) internal transferAllowances;


    //Maximum borrow rate that can ever be applied (.0005% / block)
    uint internal constant borrowRateMaxMantissa = 0.0005e16;

    /**
    * Maximum fraction of borrower cap(80%)
    */
    uint public  borrowCapFactorMantissa = 0.8e18;
    /**
     * Contract which oversees inter-lToken operations
     */
    address public controller;


    // Initial exchange rate used when minting the first lTokens (used when totalSupply = 0)
    uint internal initialExchangeRateMantissa;

    /**
     * Block number that interest was last accrued at
     */
    uint public accrualBlockNumber;

    /**
     * Accumulator of the total earned interest rate since the opening of the market
     */
    uint public borrowIndex;

    /**
     * Total amount of outstanding borrows of the underlying in this market
     */
    uint public totalBorrows;

    /**
    * @notice Fraction of interest currently set aside for reserves 20%
    */
    uint public reserveFactorMantissa = 0.2e18;


    uint public totalReserves;


    address public underlying;

    /**
     * Container for borrow balance information
     * principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    uint256 public baseRatePerBlock;
    uint256 public multiplierPerBlock;
    uint256 public jumpMultiplierPerBlock;
    uint256 public kink;

    // Mapping of account addresses to outstanding borrow balances

    mapping(address => BorrowSnapshot) internal accountBorrows;


    /*** Token Events ***/

    /**
    * Event emitted when tokens are minted
    */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /*** Market Events ***/

    /**
     * Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, address payee, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /*** Admin Events ***/

    /**
     * Event emitted when controller is changed
     */
    event NewController(address oldController, address newController);

    /**
     * Event emitted when interestParam is changed
     */
    event NewInterestParam(uint baseRatePerBlock, uint multiplierPerBlock, uint jumpMultiplierPerBlock, uint kink);

    /**
    * @notice Event emitted when the reserve factor is changed
    */
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);

    /**
     * @notice Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @notice Event emitted when the reserves are reduced
     */
    event ReservesReduced(address to, uint reduceAmount, uint newTotalReserves);


}

abstract contract LPoolInterface is LPoolStorage {


    /*** User Interface ***/

    function transfer(address dst, uint amount) external virtual returns (bool);

    function transferFrom(address src, address dst, uint amount) external virtual returns (bool);

    function approve(address spender, uint amount) external virtual returns (bool);

    function allowance(address owner, address spender) external virtual view returns (uint);

    function balanceOf(address owner) external virtual view returns (uint);

    function balanceOfUnderlying(address owner) external virtual returns (uint);

    /*** Lender & Borrower Functions ***/

    function mint(uint mintAmount) external virtual;

    function redeem(uint redeemTokens) external virtual;

    function redeemUnderlying(uint redeemAmount) external virtual;

    function borrowBehalf(address borrower, uint borrowAmount) external virtual;

    function repayBorrowBehalf(address borrower, uint repayAmount) external virtual;

    function availableForBorrow() external view virtual returns (uint);

    function getAccountSnapshot(address account) external virtual view returns (uint, uint, uint);

    function borrowRatePerBlock() external virtual view returns (uint);

    function supplyRatePerBlock() external virtual view returns (uint);

    function totalBorrowsCurrent() external virtual view returns (uint);

    function borrowBalanceCurrent(address account) external virtual view returns (uint);

    function borrowBalanceStored(address account) external virtual view returns (uint);

    function exchangeRateCurrent() public virtual returns (uint);

    function exchangeRateStored() public virtual view returns (uint);

    function getCash() external view virtual returns (uint);

    function accrueInterest() public virtual;


    /*** Admin Functions ***/

    function setController(address newController) external virtual;

    function setBorrowCapFactorMantissa(uint newBorrowCapFactorMantissa) external virtual;

    function setInterestParams(uint baseRatePerBlock_, uint multiplierPerBlock_, uint jumpMultiplierPerBlock_, uint kink_) external virtual;

    function setReserveFactor(uint newReserveFactorMantissa) external virtual;

    function addReserves(uint addAmount) external virtual;

    function reduceReserves(address payable to, uint reduceAmount) external virtual;

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "../../utils/Context.sol";
import "./IERC20.sol";
import "../../math/SafeMath.sol";

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
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

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
    function decimals() public view virtual returns (uint8) {
        return _decimals;
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
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
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
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
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

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
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
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

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

pragma solidity ^0.7.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

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
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

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

