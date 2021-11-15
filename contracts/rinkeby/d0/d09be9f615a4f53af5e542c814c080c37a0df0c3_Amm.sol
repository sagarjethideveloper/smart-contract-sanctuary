// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { BlockContext } from "./utils/BlockContext.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "./utils/Decimal.sol";
import { SignedDecimal } from "./utils/SignedDecimal.sol";
import { MixedDecimal } from "./utils/MixedDecimal.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { IAmm } from "./interface/IAmm.sol";

contract Amm is IAmm, PerpFiOwnableUpgrade, BlockContext {
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    //
    // CONSTANT
    //
    // because position decimal rounding error,
    // if the position size is less than IGNORABLE_DIGIT_FOR_SHUTDOWN, it's equal size is 0
    uint256 private constant IGNORABLE_DIGIT_FOR_SHUTDOWN = 100;

    // a margin to prevent from rounding when calc liquidity multiplier limit
    uint256 private constant MARGIN_FOR_LIQUIDITY_MIGRATION_ROUNDING = 1e9;

    //
    // EVENTS
    //
    event SwapInput(Dir dir, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event SwapOutput(Dir dir, uint256 quoteAssetAmount, uint256 baseAssetAmount);
    event FundingRateUpdated(int256 rate, uint256 underlyingPrice);
    event ReserveSnapshotted(uint256 quoteAssetReserve, uint256 baseAssetReserve, uint256 timestamp);
    event LiquidityChanged(uint256 quoteReserve, uint256 baseReserve, int256 cumulativeNotional);
    event CapChanged(uint256 maxHoldingBaseAsset, uint256 openInterestNotionalCap);
    event Shutdown(uint256 settlementPrice);
    event PriceFeedUpdated(address priceFeed);

    //
    // MODIFIERS
    //
    modifier onlyOpen() {
        require(open, "amm was closed");
        _;
    }

    modifier onlyCounterParty() {
        require(counterParty == _msgSender(), "caller is not counterParty");
        _;
    }

    //
    // enum and struct
    //
    struct ReserveSnapshot {
        Decimal.decimal quoteAssetReserve;
        Decimal.decimal baseAssetReserve;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // internal usage
    enum QuoteAssetDir { QUOTE_IN, QUOTE_OUT }
    // internal usage
    enum TwapCalcOption { RESERVE_ASSET, INPUT_ASSET }

    // To record current base/quote asset to calculate TWAP

    struct TwapInputAsset {
        Dir dir;
        Decimal.decimal assetAmount;
        QuoteAssetDir inOrOut;
    }

    struct TwapPriceCalcParams {
        TwapCalcOption opt;
        uint256 snapshotIndex;
        TwapInputAsset asset;
    }

    //
    // Constant
    //
    // 10%
    uint256 public constant MAX_ORACLE_SPREAD_RATIO = 1e17;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    // DEPRECATED
    // update during every swap and calculate total amm pnl per funding period
    SignedDecimal.signedDecimal private baseAssetDeltaThisFundingPeriod;

    // update during every swap and used when shutting amm down. it's trader's total base asset size
    SignedDecimal.signedDecimal public totalPositionSize;

    // latest funding rate = ((twap market price - twap oracle price) / twap oracle price) / 24
    SignedDecimal.signedDecimal public fundingRate;

    SignedDecimal.signedDecimal private cumulativeNotional;

    Decimal.decimal private settlementPrice;
    Decimal.decimal public tradeLimitRatio;
    Decimal.decimal public quoteAssetReserve;
    Decimal.decimal public baseAssetReserve;
    Decimal.decimal public fluctuationLimitRatio;

    // owner can update
    Decimal.decimal public tollRatio;
    Decimal.decimal public spreadRatio;
    Decimal.decimal public tollAmount;
    Decimal.decimal private maxHoldingBaseAsset;
    Decimal.decimal private openInterestNotionalCap;

    // init cumulativePositionMultiplier is 1, will be updated every time when amm reserve increase/decrease
    Decimal.decimal private cumulativePositionMultiplier;

    // snapshot of amm reserve when change liquidity's invariant
    LiquidityChangedSnapshot[] private liquidityChangedSnapshots;

    uint256 public spotPriceTwapInterval;
    uint256 public fundingPeriod;
    uint256 public fundingBufferPeriod;
    uint256 public nextFundingTime;
    bytes32 public priceFeedKey;
    ReserveSnapshot[] public reserveSnapshots;

    address private counterParty;
    address public globalShutdown;
    IERC20 public override quoteAsset;
    IPriceFeed public priceFeed;
    bool public override open;
    uint256[50] private __gap;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//

    //
    // FUNCTIONS
    //
    function initialize(
        uint256 _quoteAssetReserve,
        uint256 _baseAssetReserve,
        uint256 _tradeLimitRatio,
        uint256 _fundingPeriod,
        IPriceFeed _priceFeed,
        bytes32 _priceFeedKey,
        address _quoteAsset,
        uint256 _fluctuationLimitRatio,
        uint256 _tollRatio,
        uint256 _spreadRatio
    ) public initializer {
        require(
            _quoteAssetReserve != 0 &&
                _tradeLimitRatio != 0 &&
                _baseAssetReserve != 0 &&
                _fundingPeriod != 0 &&
                address(_priceFeed) != address(0) &&
                _quoteAsset != address(0),
            "invalid input"
        );
        __Ownable_init();

        quoteAssetReserve = Decimal.decimal(_quoteAssetReserve);
        baseAssetReserve = Decimal.decimal(_baseAssetReserve);
        tradeLimitRatio = Decimal.decimal(_tradeLimitRatio);
        tollRatio = Decimal.decimal(_tollRatio);
        spreadRatio = Decimal.decimal(_spreadRatio);
        fluctuationLimitRatio = Decimal.decimal(_fluctuationLimitRatio);
        fundingPeriod = _fundingPeriod;
        fundingBufferPeriod = _fundingPeriod.div(2);
        spotPriceTwapInterval = 1 hours;
        priceFeedKey = _priceFeedKey;
        quoteAsset = IERC20(_quoteAsset);
        priceFeed = _priceFeed;
        cumulativePositionMultiplier = Decimal.one();
        liquidityChangedSnapshots.push(
            LiquidityChangedSnapshot({
                cumulativeNotional: SignedDecimal.zero(),
                baseAssetReserve: baseAssetReserve,
                quoteAssetReserve: quoteAssetReserve,
                totalPositionSize: SignedDecimal.zero()
            })
        );
        reserveSnapshots.push(ReserveSnapshot(quoteAssetReserve, baseAssetReserve, _blockTimestamp(), _blockNumber()));
        emit ReserveSnapshotted(quoteAssetReserve.toUint(), baseAssetReserve.toUint(), _blockTimestamp());
    }

    /**
     * @notice Swap your quote asset to base asset, the impact of the price MUST be less than `fluctuationLimitRatio`
     * @dev Only clearingHouse can call this function
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short
     * @param _quoteAssetAmount quote asset amount
     * @param _baseAssetAmountLimit minimum base asset amount expected to get to prevent front running
     * @param _canOverFluctuationLimit if tx can go over fluctuation limit once; for partial liquidation
     * @return base asset amount
     */
    function swapInput(
        Dir _dirOfQuote,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _baseAssetAmountLimit,
        bool _canOverFluctuationLimit
    ) external override onlyOpen onlyCounterParty returns (Decimal.decimal memory) {
        if (_quoteAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }
        if (_dirOfQuote == Dir.REMOVE_FROM_AMM) {
            require(
                quoteAssetReserve.mulD(tradeLimitRatio).toUint() >= _quoteAssetAmount.toUint(),
                "over trading limit"
            );
        }

        Decimal.decimal memory baseAssetAmount = getInputPrice(_dirOfQuote, _quoteAssetAmount);
        // If LONG, exchanged base amount should be more than _baseAssetAmountLimit,
        // otherwise(SHORT), exchanged base amount should be less than _baseAssetAmountLimit.
        // In SHORT case, more position means more debt so should not be larger than _baseAssetAmountLimit
        if (_baseAssetAmountLimit.toUint() != 0) {
            if (_dirOfQuote == Dir.ADD_TO_AMM) {
                require(baseAssetAmount.toUint() >= _baseAssetAmountLimit.toUint(), "Less than minimal base token");
            } else {
                require(baseAssetAmount.toUint() <= _baseAssetAmountLimit.toUint(), "More than maximal base token");
            }
        }

        updateReserve(_dirOfQuote, _quoteAssetAmount, baseAssetAmount, _canOverFluctuationLimit);
        emit SwapInput(_dirOfQuote, _quoteAssetAmount.toUint(), baseAssetAmount.toUint());
        return baseAssetAmount;
    }

    /**
     * @notice swap your base asset to quote asset; NOTE it is only used during close/liquidate positions so it always allows going over fluctuation limit
     * @dev only clearingHouse can call this function
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from swapInput
     * @param _baseAssetAmount base asset amount
     * @param _quoteAssetAmountLimit limit of quote asset amount; for slippage protection
     * @return quote asset amount
     */
    function swapOutput(
        Dir _dirOfBase,
        Decimal.decimal calldata _baseAssetAmount,
        Decimal.decimal calldata _quoteAssetAmountLimit
    ) external override onlyOpen onlyCounterParty returns (Decimal.decimal memory) {
        return implSwapOutput(_dirOfBase, _baseAssetAmount, _quoteAssetAmountLimit);
    }

    /**
     * @notice update funding rate
     * @dev only allow to update while reaching `nextFundingTime`
     * @return premium fraction of this period in 18 digits
     */
    function settleFunding() external override onlyOpen onlyCounterParty returns (SignedDecimal.signedDecimal memory) {
        require(_blockTimestamp() >= nextFundingTime, "settle funding too early");

        // premium = twapMarketPrice - twapIndexPrice
        // timeFraction = fundingPeriod(1 hour) / 1 day
        // premiumFraction = premium * timeFraction
        Decimal.decimal memory underlyingPrice = getUnderlyingTwapPrice(spotPriceTwapInterval);
        SignedDecimal.signedDecimal memory premium =
            MixedDecimal.fromDecimal(getTwapPrice(spotPriceTwapInterval)).subD(underlyingPrice);
        SignedDecimal.signedDecimal memory premiumFraction = premium.mulScalar(fundingPeriod).divScalar(int256(1 days));

        // update funding rate = premiumFraction / twapIndexPrice
        updateFundingRate(premiumFraction, underlyingPrice);

        // in order to prevent multiple funding settlement during very short time after network congestion
        uint256 minNextValidFundingTime = _blockTimestamp().add(fundingBufferPeriod);

        // floor((nextFundingTime + fundingPeriod) / 3600) * 3600
        uint256 nextFundingTimeOnHourStart = nextFundingTime.add(fundingPeriod).div(1 hours).mul(1 hours);

        // max(nextFundingTimeOnHourStart, minNextValidFundingTime)
        nextFundingTime = nextFundingTimeOnHourStart > minNextValidFundingTime
            ? nextFundingTimeOnHourStart
            : minNextValidFundingTime;

        // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
        // reset funding related states
        baseAssetDeltaThisFundingPeriod = SignedDecimal.zero();

        return premiumFraction;
    }

    function calcBaseAssetAfterLiquidityMigration(
        SignedDecimal.signedDecimal memory _baseAssetAmount,
        Decimal.decimal memory _fromQuoteReserve,
        Decimal.decimal memory _fromBaseReserve
    ) public view override returns (SignedDecimal.signedDecimal memory) {
        if (_baseAssetAmount.toUint() == 0) {
            return _baseAssetAmount;
        }

        bool isPositiveValue = _baseAssetAmount.toInt() > 0 ? true : false;

        // measure the trader position's notional value on the old curve
        // (by simulating closing the position)
        Decimal.decimal memory posNotional =
            getOutputPriceWithReserves(
                isPositiveValue ? Dir.ADD_TO_AMM : Dir.REMOVE_FROM_AMM,
                _baseAssetAmount.abs(),
                _fromQuoteReserve,
                _fromBaseReserve
            );

        // calculate and apply the required size on the new curve
        SignedDecimal.signedDecimal memory newBaseAsset =
            MixedDecimal.fromDecimal(
                getInputPrice(isPositiveValue ? Dir.REMOVE_FROM_AMM : Dir.ADD_TO_AMM, posNotional)
            );
        return newBaseAsset.mulScalar(isPositiveValue ? 1 : int256(-1));
    }

    /**
     * @notice shutdown amm,
     * @dev only `globalShutdown` or owner can call this function
     * The price calculation is in `globalShutdown`.
     */
    function shutdown() external override {
        require(_msgSender() == owner() || _msgSender() == globalShutdown, "not owner nor globalShutdown");
        implShutdown();
    }

    /**
     * @notice set counter party
     * @dev only owner can call this function
     * @param _counterParty address of counter party
     */
    function setCounterParty(address _counterParty) external onlyOwner {
        counterParty = _counterParty;
    }

    /**
     * @notice set `globalShutdown`
     * @dev only owner can call this function
     * @param _globalShutdown address of `globalShutdown`
     */
    function setGlobalShutdown(address _globalShutdown) external onlyOwner {
        globalShutdown = _globalShutdown;
    }

    /**
     * @notice set fluctuation limit rate. Default value is `1 / max leverage`
     * @dev only owner can call this function
     * @param _fluctuationLimitRatio fluctuation limit rate in 18 digits, 0 means skip the checking
     */
    function setFluctuationLimitRatio(Decimal.decimal memory _fluctuationLimitRatio) public onlyOwner {
        fluctuationLimitRatio = _fluctuationLimitRatio;
    }

    /**
     * @notice set time interval for twap calculation, default is 1 hour
     * @dev only owner can call this function
     * @param _interval time interval in seconds
     */
    function setSpotPriceTwapInterval(uint256 _interval) external onlyOwner {
        require(_interval != 0, "can not set interval to 0");
        spotPriceTwapInterval = _interval;
    }

    /**
     * @notice set `open` flag. Amm is open to trade if `open` is true. Default is false.
     * @dev only owner can call this function
     * @param _open open to trade is true, otherwise is false.
     */
    function setOpen(bool _open) external onlyOwner {
        if (open == _open) return;

        open = _open;
        if (_open) {
            nextFundingTime = _blockTimestamp().add(fundingPeriod).div(1 hours).mul(1 hours);
        }
    }

    /**
     * @notice set new toll ratio
     * @dev only owner can call
     * @param _tollRatio new toll ratio in 18 digits
     */
    function setTollRatio(Decimal.decimal memory _tollRatio) public onlyOwner {
        tollRatio = _tollRatio;
    }

    /**
     * @notice set new spread ratio
     * @dev only owner can call
     * @param _spreadRatio new toll spread in 18 digits
     */
    function setSpreadRatio(Decimal.decimal memory _spreadRatio) public onlyOwner {
        spreadRatio = _spreadRatio;
    }

    /**
     * @notice set new cap during guarded period, which is max position size that traders can hold
     * @dev only owner can call. assume this will be removes soon once the guarded period has ended. must be set before opening amm
     * @param _maxHoldingBaseAsset max position size that traders can hold in 18 digits
     * @param _openInterestNotionalCap open interest cap, denominated in quoteToken
     */
    function setCap(Decimal.decimal memory _maxHoldingBaseAsset, Decimal.decimal memory _openInterestNotionalCap)
        public
        onlyOwner
    {
        maxHoldingBaseAsset = _maxHoldingBaseAsset;
        openInterestNotionalCap = _openInterestNotionalCap;
        emit CapChanged(maxHoldingBaseAsset.toUint(), openInterestNotionalCap.toUint());
    }

    /**
     * @notice set priceFee address
     * @dev only owner can call
     * @param _priceFeed new price feed for this AMM
     */
    function setPriceFeed(IPriceFeed _priceFeed) public onlyOwner {
        require(address(_priceFeed) != address(0), "invalid PriceFeed address");
        priceFeed = _priceFeed;
        emit PriceFeedUpdated(address(priceFeed));
    }

    //
    // VIEW FUNCTIONS
    //

    function isOverFluctuationLimit(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        external
        view
        override
        returns (bool)
    {
        // Skip the check if the limit is 0
        if (fluctuationLimitRatio.toUint() == 0) {
            return false;
        }

        (Decimal.decimal memory upperLimit, Decimal.decimal memory lowerLimit) = getPriceBoundariesOfLastBlock();

        Decimal.decimal memory quoteAssetExchanged = getOutputPrice(_dirOfBase, _baseAssetAmount);
        Decimal.decimal memory price =
            (_dirOfBase == Dir.REMOVE_FROM_AMM)
                ? quoteAssetReserve.addD(quoteAssetExchanged).divD(baseAssetReserve.subD(_baseAssetAmount))
                : quoteAssetReserve.subD(quoteAssetExchanged).divD(baseAssetReserve.addD(_baseAssetAmount));

        if (price.cmp(upperLimit) <= 0 && price.cmp(lowerLimit) >= 0) {
            return false;
        }
        return true;
    }

    /**
     * @notice get input twap amount.
     * returns how many base asset you will get with the input quote amount based on twap price.
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short.
     * @param _quoteAssetAmount quote asset amount
     * @return base asset amount
     */
    function getInputTwap(Dir _dirOfQuote, Decimal.decimal memory _quoteAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return implGetInputAssetTwapPrice(_dirOfQuote, _quoteAssetAmount, QuoteAssetDir.QUOTE_IN, 15 minutes);
    }

    /**
     * @notice get output twap amount.
     * return how many quote asset you will get with the input base amount on twap price.
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from `getInputTwap`.
     * @param _baseAssetAmount base asset amount
     * @return quote asset amount
     */
    function getOutputTwap(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return implGetInputAssetTwapPrice(_dirOfBase, _baseAssetAmount, QuoteAssetDir.QUOTE_OUT, 15 minutes);
    }

    /**
     * @notice get input amount. returns how many base asset you will get with the input quote amount.
     * @param _dirOfQuote ADD_TO_AMM for long, REMOVE_FROM_AMM for short.
     * @param _quoteAssetAmount quote asset amount
     * @return base asset amount
     */
    function getInputPrice(Dir _dirOfQuote, Decimal.decimal memory _quoteAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return getInputPriceWithReserves(_dirOfQuote, _quoteAssetAmount, quoteAssetReserve, baseAssetReserve);
    }

    /**
     * @notice get output price. return how many quote asset you will get with the input base amount
     * @param _dirOfBase ADD_TO_AMM for short, REMOVE_FROM_AMM for long, opposite direction from `getInput`.
     * @param _baseAssetAmount base asset amount
     * @return quote asset amount
     */
    function getOutputPrice(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        public
        view
        override
        returns (Decimal.decimal memory)
    {
        return getOutputPriceWithReserves(_dirOfBase, _baseAssetAmount, quoteAssetReserve, baseAssetReserve);
    }

    /**
     * @notice get underlying price provided by oracle
     * @return underlying price
     */
    function getUnderlyingPrice() public view override returns (Decimal.decimal memory) {
        return Decimal.decimal(priceFeed.getPrice(priceFeedKey));
    }

    /**
     * @notice get underlying twap price provided by oracle
     * @return underlying price
     */
    function getUnderlyingTwapPrice(uint256 _intervalInSeconds) public view returns (Decimal.decimal memory) {
        return Decimal.decimal(priceFeed.getTwapPrice(priceFeedKey, _intervalInSeconds));
    }

    /**
     * @notice get spot price based on current quote/base asset reserve.
     * @return spot price
     */
    function getSpotPrice() public view override returns (Decimal.decimal memory) {
        return quoteAssetReserve.divD(baseAssetReserve);
    }

    /**
     * @notice get twap price
     */
    function getTwapPrice(uint256 _intervalInSeconds) public view returns (Decimal.decimal memory) {
        return implGetReserveTwapPrice(_intervalInSeconds);
    }

    /**
     * @notice get current quote/base asset reserve.
     * @return (quote asset reserve, base asset reserve)
     */
    function getReserve() external view returns (Decimal.decimal memory, Decimal.decimal memory) {
        return (quoteAssetReserve, baseAssetReserve);
    }

    function getSnapshotLen() external view returns (uint256) {
        return reserveSnapshots.length;
    }

    function getLiquidityHistoryLength() external view override returns (uint256) {
        return liquidityChangedSnapshots.length;
    }

    function getCumulativeNotional() external view override returns (SignedDecimal.signedDecimal memory) {
        return cumulativeNotional;
    }

    function getLatestLiquidityChangedSnapshots() public view returns (LiquidityChangedSnapshot memory) {
        return liquidityChangedSnapshots[liquidityChangedSnapshots.length.sub(1)];
    }

    function getLiquidityChangedSnapshots(uint256 i) external view override returns (LiquidityChangedSnapshot memory) {
        require(i < liquidityChangedSnapshots.length, "incorrect index");
        return liquidityChangedSnapshots[i];
    }

    function getSettlementPrice() external view override returns (Decimal.decimal memory) {
        return settlementPrice;
    }

    // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
    function getBaseAssetDeltaThisFundingPeriod() external view override returns (SignedDecimal.signedDecimal memory) {
        return baseAssetDeltaThisFundingPeriod;
    }

    function getMaxHoldingBaseAsset() external view override returns (Decimal.decimal memory) {
        return maxHoldingBaseAsset;
    }

    function getOpenInterestNotionalCap() external view override returns (Decimal.decimal memory) {
        return openInterestNotionalCap;
    }

    function getBaseAssetDelta() external view override returns (SignedDecimal.signedDecimal memory) {
        return totalPositionSize;
    }

    function isOverSpreadLimit() external view override returns (bool) {
        Decimal.decimal memory oraclePrice = getUnderlyingPrice();
        require(oraclePrice.toUint() > 0, "underlying price is 0");
        Decimal.decimal memory marketPrice = getSpotPrice();
        Decimal.decimal memory oracleSpreadRatioAbs =
            MixedDecimal.fromDecimal(marketPrice).subD(oraclePrice).divD(oraclePrice).abs();

        return oracleSpreadRatioAbs.toUint() >= MAX_ORACLE_SPREAD_RATIO ? true : false;
    }

    /**
     * @notice calculate total fee (including toll and spread) by input quoteAssetAmount
     * @param _quoteAssetAmount quoteAssetAmount
     * @return total tx fee
     */
    function calcFee(Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        override
        returns (Decimal.decimal memory, Decimal.decimal memory)
    {
        if (_quoteAssetAmount.toUint() == 0) {
            return (Decimal.zero(), Decimal.zero());
        }
        return (_quoteAssetAmount.mulD(tollRatio), _quoteAssetAmount.mulD(spreadRatio));
    }

    /*       plus/minus 1 while the amount is not dividable
     *
     *        getInputPrice                         getOutputPrice
     *
     *     ＡＤＤ      (amount - 1)              (amount + 1)   ＲＥＭＯＶＥ
     *      ◥◤            ▲                         |             ◢◣
     *      ◥◤  ------->  |                         ▼  <--------  ◢◣
     *    -------      -------                   -------        -------
     *    |  Q  |      |  B  |                   |  Q  |        |  B  |
     *    -------      -------                   -------        -------
     *      ◥◤  ------->  ▲                         |  <--------  ◢◣
     *      ◥◤            |                         ▼             ◢◣
     *   ＲＥＭＯＶＥ  (amount + 1)              (amount + 1)      ＡＤＤ
     **/

    function getInputPriceWithReserves(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public pure override returns (Decimal.decimal memory) {
        if (_quoteAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }

        bool isAddToAmm = _dirOfQuote == Dir.ADD_TO_AMM;
        SignedDecimal.signedDecimal memory invariant =
            MixedDecimal.fromDecimal(_quoteAssetPoolAmount.mulD(_baseAssetPoolAmount));
        SignedDecimal.signedDecimal memory baseAssetAfter;
        Decimal.decimal memory quoteAssetAfter;
        Decimal.decimal memory baseAssetBought;
        if (isAddToAmm) {
            quoteAssetAfter = _quoteAssetPoolAmount.addD(_quoteAssetAmount);
        } else {
            quoteAssetAfter = _quoteAssetPoolAmount.subD(_quoteAssetAmount);
        }
        require(quoteAssetAfter.toUint() != 0, "quote asset after is 0");

        baseAssetAfter = invariant.divD(quoteAssetAfter);
        baseAssetBought = baseAssetAfter.subD(_baseAssetPoolAmount).abs();

        // if the amount is not dividable, return 1 wei less for trader
        if (invariant.abs().modD(quoteAssetAfter).toUint() != 0) {
            if (isAddToAmm) {
                baseAssetBought = baseAssetBought.subD(Decimal.decimal(1));
            } else {
                baseAssetBought = baseAssetBought.addD(Decimal.decimal(1));
            }
        }

        return baseAssetBought;
    }

    function getOutputPriceWithReserves(
        Dir _dirOfBase,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public pure override returns (Decimal.decimal memory) {
        if (_baseAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }

        bool isAddToAmm = _dirOfBase == Dir.ADD_TO_AMM;
        SignedDecimal.signedDecimal memory invariant =
            MixedDecimal.fromDecimal(_quoteAssetPoolAmount.mulD(_baseAssetPoolAmount));
        SignedDecimal.signedDecimal memory quoteAssetAfter;
        Decimal.decimal memory baseAssetAfter;
        Decimal.decimal memory quoteAssetSold;

        if (isAddToAmm) {
            baseAssetAfter = _baseAssetPoolAmount.addD(_baseAssetAmount);
        } else {
            baseAssetAfter = _baseAssetPoolAmount.subD(_baseAssetAmount);
        }
        require(baseAssetAfter.toUint() != 0, "base asset after is 0");

        quoteAssetAfter = invariant.divD(baseAssetAfter);
        quoteAssetSold = quoteAssetAfter.subD(_quoteAssetPoolAmount).abs();

        // if the amount is not dividable, return 1 wei less for trader
        if (invariant.abs().modD(baseAssetAfter).toUint() != 0) {
            if (isAddToAmm) {
                quoteAssetSold = quoteAssetSold.subD(Decimal.decimal(1));
            } else {
                quoteAssetSold = quoteAssetSold.addD(Decimal.decimal(1));
            }
        }

        return quoteAssetSold;
    }

    //
    // INTERNAL FUNCTIONS
    //
    // update funding rate = premiumFraction / twapIndexPrice
    function updateFundingRate(
        SignedDecimal.signedDecimal memory _premiumFraction,
        Decimal.decimal memory _underlyingPrice
    ) private {
        fundingRate = _premiumFraction.divD(_underlyingPrice);
        emit FundingRateUpdated(fundingRate.toInt(), _underlyingPrice.toUint());
    }

    function addReserveSnapshot() internal {
        uint256 currentBlock = _blockNumber();
        ReserveSnapshot storage latestSnapshot = reserveSnapshots[reserveSnapshots.length - 1];
        // update values in snapshot if in the same block
        if (currentBlock == latestSnapshot.blockNumber) {
            latestSnapshot.quoteAssetReserve = quoteAssetReserve;
            latestSnapshot.baseAssetReserve = baseAssetReserve;
        } else {
            reserveSnapshots.push(
                ReserveSnapshot(quoteAssetReserve, baseAssetReserve, _blockTimestamp(), currentBlock)
            );
        }
        emit ReserveSnapshotted(quoteAssetReserve.toUint(), baseAssetReserve.toUint(), _blockTimestamp());
    }

    function implSwapOutput(
        Dir _dirOfBase,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) internal returns (Decimal.decimal memory) {
        if (_baseAssetAmount.toUint() == 0) {
            return Decimal.zero();
        }
        if (_dirOfBase == Dir.REMOVE_FROM_AMM) {
            require(baseAssetReserve.mulD(tradeLimitRatio).toUint() >= _baseAssetAmount.toUint(), "over trading limit");
        }

        Decimal.decimal memory quoteAssetAmount = getOutputPrice(_dirOfBase, _baseAssetAmount);
        Dir dirOfQuote = _dirOfBase == Dir.ADD_TO_AMM ? Dir.REMOVE_FROM_AMM : Dir.ADD_TO_AMM;
        // If SHORT, exchanged quote amount should be less than _quoteAssetAmountLimit,
        // otherwise(LONG), exchanged base amount should be more than _quoteAssetAmountLimit.
        // In the SHORT case, more quote assets means more payment so should not be more than _quoteAssetAmountLimit
        if (_quoteAssetAmountLimit.toUint() != 0) {
            if (dirOfQuote == Dir.REMOVE_FROM_AMM) {
                // SHORT
                require(quoteAssetAmount.toUint() >= _quoteAssetAmountLimit.toUint(), "Less than minimal quote token");
            } else {
                // LONG
                require(quoteAssetAmount.toUint() <= _quoteAssetAmountLimit.toUint(), "More than maximal quote token");
            }
        }

        // as mentioned in swapOutput(), it always allows going over fluctuation limit because
        // it is only used by close/liquidate positions
        updateReserve(dirOfQuote, quoteAssetAmount, _baseAssetAmount, true);
        emit SwapOutput(_dirOfBase, quoteAssetAmount.toUint(), _baseAssetAmount.toUint());
        return quoteAssetAmount;
    }

    // the direction is in quote asset
    function updateReserve(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _baseAssetAmount,
        bool _canOverFluctuationLimit
    ) internal {
        // check if it's over fluctuationLimitRatio
        // this check should be before reserves being updated
        checkIsOverBlockFluctuationLimit(_dirOfQuote, _quoteAssetAmount, _baseAssetAmount, _canOverFluctuationLimit);

        if (_dirOfQuote == Dir.ADD_TO_AMM) {
            quoteAssetReserve = quoteAssetReserve.addD(_quoteAssetAmount);
            baseAssetReserve = baseAssetReserve.subD(_baseAssetAmount);
            // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
            baseAssetDeltaThisFundingPeriod = baseAssetDeltaThisFundingPeriod.subD(_baseAssetAmount);
            totalPositionSize = totalPositionSize.addD(_baseAssetAmount);
            cumulativeNotional = cumulativeNotional.addD(_quoteAssetAmount);
        } else {
            quoteAssetReserve = quoteAssetReserve.subD(_quoteAssetAmount);
            baseAssetReserve = baseAssetReserve.addD(_baseAssetAmount);
            // DEPRECATED only for backward compatibility before we upgrade ClearingHouse
            baseAssetDeltaThisFundingPeriod = baseAssetDeltaThisFundingPeriod.addD(_baseAssetAmount);
            totalPositionSize = totalPositionSize.subD(_baseAssetAmount);
            cumulativeNotional = cumulativeNotional.subD(_quoteAssetAmount);
        }

        // addReserveSnapshot must be after checking price fluctuation
        addReserveSnapshot();
    }

    function implGetInputAssetTwapPrice(
        Dir _dirOfQuote,
        Decimal.decimal memory _assetAmount,
        QuoteAssetDir _inOut,
        uint256 _interval
    ) internal view returns (Decimal.decimal memory) {
        TwapPriceCalcParams memory params;
        params.opt = TwapCalcOption.INPUT_ASSET;
        params.snapshotIndex = reserveSnapshots.length.sub(1);
        params.asset.dir = _dirOfQuote;
        params.asset.assetAmount = _assetAmount;
        params.asset.inOrOut = _inOut;
        return calcTwap(params, _interval);
    }

    function implGetReserveTwapPrice(uint256 _interval) internal view returns (Decimal.decimal memory) {
        TwapPriceCalcParams memory params;
        params.opt = TwapCalcOption.RESERVE_ASSET;
        params.snapshotIndex = reserveSnapshots.length.sub(1);
        return calcTwap(params, _interval);
    }

    function calcTwap(TwapPriceCalcParams memory _params, uint256 _interval)
        internal
        view
        returns (Decimal.decimal memory)
    {
        Decimal.decimal memory currentPrice = getPriceWithSpecificSnapshot(_params);
        if (_interval == 0) {
            return currentPrice;
        }

        uint256 baseTimestamp = _blockTimestamp().sub(_interval);
        ReserveSnapshot memory currentSnapshot = reserveSnapshots[_params.snapshotIndex];
        // return the latest snapshot price directly
        // if only one snapshot or the timestamp of latest snapshot is earlier than asking for
        if (reserveSnapshots.length == 1 || currentSnapshot.timestamp <= baseTimestamp) {
            return currentPrice;
        }

        uint256 previousTimestamp = currentSnapshot.timestamp;
        uint256 period = _blockTimestamp().sub(previousTimestamp);
        Decimal.decimal memory weightedPrice = currentPrice.mulScalar(period);
        while (true) {
            // if snapshot history is too short
            if (_params.snapshotIndex == 0) {
                return weightedPrice.divScalar(period);
            }

            _params.snapshotIndex = _params.snapshotIndex.sub(1);
            currentSnapshot = reserveSnapshots[_params.snapshotIndex];
            currentPrice = getPriceWithSpecificSnapshot(_params);

            // check if current round timestamp is earlier than target timestamp
            if (currentSnapshot.timestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice = weightedPrice.addD(currentPrice.mulScalar(previousTimestamp.sub(baseTimestamp)));
                break;
            }

            uint256 timeFraction = previousTimestamp.sub(currentSnapshot.timestamp);
            weightedPrice = weightedPrice.addD(currentPrice.mulScalar(timeFraction));
            period = period.add(timeFraction);
            previousTimestamp = currentSnapshot.timestamp;
        }
        return weightedPrice.divScalar(_interval);
    }

    function getPriceWithSpecificSnapshot(TwapPriceCalcParams memory params)
        internal
        view
        virtual
        returns (Decimal.decimal memory)
    {
        ReserveSnapshot memory snapshot = reserveSnapshots[params.snapshotIndex];

        // RESERVE_ASSET means price comes from quoteAssetReserve/baseAssetReserve
        // INPUT_ASSET means getInput/Output price with snapshot's reserve
        if (params.opt == TwapCalcOption.RESERVE_ASSET) {
            return snapshot.quoteAssetReserve.divD(snapshot.baseAssetReserve);
        } else if (params.opt == TwapCalcOption.INPUT_ASSET) {
            if (params.asset.assetAmount.toUint() == 0) {
                return Decimal.zero();
            }
            if (params.asset.inOrOut == QuoteAssetDir.QUOTE_IN) {
                return
                    getInputPriceWithReserves(
                        params.asset.dir,
                        params.asset.assetAmount,
                        snapshot.quoteAssetReserve,
                        snapshot.baseAssetReserve
                    );
            } else if (params.asset.inOrOut == QuoteAssetDir.QUOTE_OUT) {
                return
                    getOutputPriceWithReserves(
                        params.asset.dir,
                        params.asset.assetAmount,
                        snapshot.quoteAssetReserve,
                        snapshot.baseAssetReserve
                    );
            }
        }
        revert("not supported option");
    }

    function getPriceBoundariesOfLastBlock() internal view returns (Decimal.decimal memory, Decimal.decimal memory) {
        uint256 len = reserveSnapshots.length;
        ReserveSnapshot memory latestSnapshot = reserveSnapshots[len.sub(1)];
        // if the latest snapshot is the same as current block, get the previous one
        if (latestSnapshot.blockNumber == _blockNumber() && len > 1) {
            latestSnapshot = reserveSnapshots[len.sub(2)];
        }

        Decimal.decimal memory lastPrice = latestSnapshot.quoteAssetReserve.divD(latestSnapshot.baseAssetReserve);
        Decimal.decimal memory upperLimit = lastPrice.mulD(Decimal.one().addD(fluctuationLimitRatio));
        Decimal.decimal memory lowerLimit = lastPrice.mulD(Decimal.one().subD(fluctuationLimitRatio));
        return (upperLimit, lowerLimit);
    }

    /**
     * @notice there can only be one tx in a block can skip the fluctuation check
     *         otherwise, some positions can never be closed or liquidated
     * @param _canOverFluctuationLimit if true, can skip fluctuation check for once; else, can never skip
     */
    function checkIsOverBlockFluctuationLimit(
        Dir _dirOfQuote,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _baseAssetAmount,
        bool _canOverFluctuationLimit
    ) internal view {
        // Skip the check if the limit is 0
        if (fluctuationLimitRatio.toUint() == 0) {
            return;
        }

        //
        // assume the price of the last block is 10, fluctuation limit ratio is 5%, then
        //
        //          current price
        //  --+---------+-----------+---
        //   9.5        10         10.5
        // lower limit           upper limit
        //
        // when `openPosition`, the price can only be between 9.5 - 10.5
        // when `liquidate` and `closePosition`, the price can exceed the boundary once
        // (either lower than 9.5 or higher than 10.5)
        // once it exceeds the boundary, all the rest txs in this block fail
        //

        (Decimal.decimal memory upperLimit, Decimal.decimal memory lowerLimit) = getPriceBoundariesOfLastBlock();

        Decimal.decimal memory price = quoteAssetReserve.divD(baseAssetReserve);
        require(price.cmp(upperLimit) <= 0 && price.cmp(lowerLimit) >= 0, "price is already over fluctuation limit");

        if (!_canOverFluctuationLimit) {
            price = (_dirOfQuote == Dir.ADD_TO_AMM)
                ? quoteAssetReserve.addD(_quoteAssetAmount).divD(baseAssetReserve.subD(_baseAssetAmount))
                : quoteAssetReserve.subD(_quoteAssetAmount).divD(baseAssetReserve.addD(_baseAssetAmount));
            require(price.cmp(upperLimit) <= 0 && price.cmp(lowerLimit) >= 0, "price is over fluctuation limit");
        }
    }

    function checkLiquidityMultiplierLimit(
        SignedDecimal.signedDecimal memory _positionSize,
        Decimal.decimal memory _liquidityMultiplier
    ) internal view {
        // have lower bound when position size is long
        if (_positionSize.toInt() > 0) {
            Decimal.decimal memory liquidityMultiplierLowerBound =
                _positionSize
                    .addD(Decimal.decimal(MARGIN_FOR_LIQUIDITY_MIGRATION_ROUNDING))
                    .divD(baseAssetReserve)
                    .abs();
            require(_liquidityMultiplier.cmp(liquidityMultiplierLowerBound) >= 0, "illegal liquidity multiplier");
        }
    }

    function implShutdown() internal {
        LiquidityChangedSnapshot memory latestLiquiditySnapshot = getLatestLiquidityChangedSnapshots();

        // get last liquidity changed history to calc new quote/base reserve
        Decimal.decimal memory previousK =
            latestLiquiditySnapshot.baseAssetReserve.mulD(latestLiquiditySnapshot.quoteAssetReserve);
        SignedDecimal.signedDecimal memory lastInitBaseReserveInNewCurve =
            latestLiquiditySnapshot.totalPositionSize.addD(latestLiquiditySnapshot.baseAssetReserve);
        SignedDecimal.signedDecimal memory lastInitQuoteReserveInNewCurve =
            MixedDecimal.fromDecimal(previousK).divD(lastInitBaseReserveInNewCurve);

        // settlementPrice = SUM(Open Position Notional Value) / SUM(Position Size)
        // `Open Position Notional Value` = init quote reserve - current quote reserve
        // `Position Size` = init base reserve - current base reserve
        SignedDecimal.signedDecimal memory positionNotionalValue =
            lastInitQuoteReserveInNewCurve.subD(quoteAssetReserve);

        // if total position size less than IGNORABLE_DIGIT_FOR_SHUTDOWN, treat it as 0 positions due to rounding error
        if (totalPositionSize.toUint() > IGNORABLE_DIGIT_FOR_SHUTDOWN) {
            settlementPrice = positionNotionalValue.abs().divD(totalPositionSize.abs());
        }

        open = false;
        emit Shutdown(settlementPrice.toUint());
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

// wrap block.xxx functions for testing
// only support timestamp and number so far
abstract contract BlockContext {
    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _blockNumber() internal view virtual returns (uint256) {
        return block.number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

interface IPriceFeed {
    // get latest price
    function getPrice(bytes32 _priceFeedKey) external view returns (uint256);

    // get latest timestamp
    function getLatestTimestamp(bytes32 _priceFeedKey) external view returns (uint256);

    // get previous price with _back rounds
    function getPreviousPrice(bytes32 _priceFeedKey, uint256 _numOfRoundBack) external view returns (uint256);

    // get previous timestamp with _back rounds
    function getPreviousTimestamp(bytes32 _priceFeedKey, uint256 _numOfRoundBack) external view returns (uint256);

    // get twap price depending on _period
    function getTwapPrice(bytes32 _priceFeedKey, uint256 _interval) external view returns (uint256);
}

pragma solidity ^0.6.0;

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
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
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
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

pragma solidity ^0.6.0;

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
pragma solidity 0.6.9;

import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { DecimalMath } from "./DecimalMath.sol";

library Decimal {
    using DecimalMath for uint256;
    using SafeMath for uint256;

    struct decimal {
        uint256 d;
    }

    function zero() internal pure returns (decimal memory) {
        return decimal(0);
    }

    function one() internal pure returns (decimal memory) {
        return decimal(DecimalMath.unit(18));
    }

    function toUint(decimal memory x) internal pure returns (uint256) {
        return x.d;
    }

    function modD(decimal memory x, decimal memory y) internal pure returns (decimal memory) {
        return decimal(x.d.mul(DecimalMath.unit(18)) % y.d);
    }

    function cmp(decimal memory x, decimal memory y) internal pure returns (int8) {
        if (x.d > y.d) {
            return 1;
        } else if (x.d < y.d) {
            return -1;
        }
        return 0;
    }

    /// @dev add two decimals
    function addD(decimal memory x, decimal memory y) internal pure returns (decimal memory) {
        decimal memory t;
        t.d = x.d.add(y.d);
        return t;
    }

    /// @dev subtract two decimals
    function subD(decimal memory x, decimal memory y) internal pure returns (decimal memory) {
        decimal memory t;
        t.d = x.d.sub(y.d);
        return t;
    }

    /// @dev multiple two decimals
    function mulD(decimal memory x, decimal memory y) internal pure returns (decimal memory) {
        decimal memory t;
        t.d = x.d.muld(y.d);
        return t;
    }

    /// @dev multiple a decimal by a uint256
    function mulScalar(decimal memory x, uint256 y) internal pure returns (decimal memory) {
        decimal memory t;
        t.d = x.d.mul(y);
        return t;
    }

    /// @dev divide two decimals
    function divD(decimal memory x, decimal memory y) internal pure returns (decimal memory) {
        decimal memory t;
        t.d = x.d.divd(y.d);
        return t;
    }

    /// @dev divide a decimal by a uint256
    function divScalar(decimal memory x, uint256 y) internal pure returns (decimal memory) {
        decimal memory t;
        t.d = x.d.div(y);
        return t;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { SignedSafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SignedSafeMath.sol";
import { SignedDecimalMath } from "./SignedDecimalMath.sol";
import { Decimal } from "./Decimal.sol";

library SignedDecimal {
    using SignedDecimalMath for int256;
    using SignedSafeMath for int256;

    struct signedDecimal {
        int256 d;
    }

    function zero() internal pure returns (signedDecimal memory) {
        return signedDecimal(0);
    }

    function toInt(signedDecimal memory x) internal pure returns (int256) {
        return x.d;
    }

    function isNegative(signedDecimal memory x) internal pure returns (bool) {
        if (x.d < 0) {
            return true;
        }
        return false;
    }

    function abs(signedDecimal memory x) internal pure returns (Decimal.decimal memory) {
        Decimal.decimal memory t;
        if (x.d < 0) {
            t.d = uint256(0 - x.d);
        } else {
            t.d = uint256(x.d);
        }
        return t;
    }

    /// @dev add two decimals
    function addD(signedDecimal memory x, signedDecimal memory y) internal pure returns (signedDecimal memory) {
        signedDecimal memory t;
        t.d = x.d.add(y.d);
        return t;
    }

    /// @dev subtract two decimals
    function subD(signedDecimal memory x, signedDecimal memory y) internal pure returns (signedDecimal memory) {
        signedDecimal memory t;
        t.d = x.d.sub(y.d);
        return t;
    }

    /// @dev multiple two decimals
    function mulD(signedDecimal memory x, signedDecimal memory y) internal pure returns (signedDecimal memory) {
        signedDecimal memory t;
        t.d = x.d.muld(y.d);
        return t;
    }

    /// @dev multiple a signedDecimal by a int256
    function mulScalar(signedDecimal memory x, int256 y) internal pure returns (signedDecimal memory) {
        signedDecimal memory t;
        t.d = x.d.mul(y);
        return t;
    }

    /// @dev divide two decimals
    function divD(signedDecimal memory x, signedDecimal memory y) internal pure returns (signedDecimal memory) {
        signedDecimal memory t;
        t.d = x.d.divd(y.d);
        return t;
    }

    /// @dev divide a signedDecimal by a int256
    function divScalar(signedDecimal memory x, int256 y) internal pure returns (signedDecimal memory) {
        signedDecimal memory t;
        t.d = x.d.div(y);
        return t;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { Decimal } from "./Decimal.sol";
import { SignedDecimal } from "./SignedDecimal.sol";
import { SignedSafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SignedSafeMath.sol";

/// @dev To handle a signedDecimal add/sub/mul/div a decimal and provide convert decimal to signedDecimal helper
library MixedDecimal {
    using SignedDecimal for SignedDecimal.signedDecimal;
    using SignedSafeMath for int256;

    uint256 private constant _INT256_MAX = 2**255 - 1;
    string private constant ERROR_NON_CONVERTIBLE = "MixedDecimal: uint value is bigger than _INT256_MAX";

    modifier convertible(Decimal.decimal memory x) {
        require(_INT256_MAX >= x.d, ERROR_NON_CONVERTIBLE);
        _;
    }

    function fromDecimal(Decimal.decimal memory x)
        internal
        pure
        convertible(x)
        returns (SignedDecimal.signedDecimal memory)
    {
        return SignedDecimal.signedDecimal(int256(x.d));
    }

    function toUint(SignedDecimal.signedDecimal memory x) internal pure returns (uint256) {
        return x.abs().d;
    }

    /// @dev add SignedDecimal.signedDecimal and Decimal.decimal, using SignedSafeMath directly
    function addD(SignedDecimal.signedDecimal memory x, Decimal.decimal memory y)
        internal
        pure
        convertible(y)
        returns (SignedDecimal.signedDecimal memory)
    {
        SignedDecimal.signedDecimal memory t;
        t.d = x.d.add(int256(y.d));
        return t;
    }

    /// @dev subtract SignedDecimal.signedDecimal by Decimal.decimal, using SignedSafeMath directly
    function subD(SignedDecimal.signedDecimal memory x, Decimal.decimal memory y)
        internal
        pure
        convertible(y)
        returns (SignedDecimal.signedDecimal memory)
    {
        SignedDecimal.signedDecimal memory t;
        t.d = x.d.sub(int256(y.d));
        return t;
    }

    /// @dev multiple a SignedDecimal.signedDecimal by Decimal.decimal
    function mulD(SignedDecimal.signedDecimal memory x, Decimal.decimal memory y)
        internal
        pure
        convertible(y)
        returns (SignedDecimal.signedDecimal memory)
    {
        SignedDecimal.signedDecimal memory t;
        t = x.mulD(fromDecimal(y));
        return t;
    }

    /// @dev multiple a SignedDecimal.signedDecimal by a uint256
    function mulScalar(SignedDecimal.signedDecimal memory x, uint256 y)
        internal
        pure
        returns (SignedDecimal.signedDecimal memory)
    {
        require(_INT256_MAX >= y, ERROR_NON_CONVERTIBLE);
        SignedDecimal.signedDecimal memory t;
        t = x.mulScalar(int256(y));
        return t;
    }

    /// @dev divide a SignedDecimal.signedDecimal by a Decimal.decimal
    function divD(SignedDecimal.signedDecimal memory x, Decimal.decimal memory y)
        internal
        pure
        convertible(y)
        returns (SignedDecimal.signedDecimal memory)
    {
        SignedDecimal.signedDecimal memory t;
        t = x.divD(fromDecimal(y));
        return t;
    }

    /// @dev divide a SignedDecimal.signedDecimal by a uint256
    function divScalar(SignedDecimal.signedDecimal memory x, uint256 y)
        internal
        pure
        returns (SignedDecimal.signedDecimal memory)
    {
        require(_INT256_MAX >= y, ERROR_NON_CONVERTIBLE);
        SignedDecimal.signedDecimal memory t;
        t = x.divScalar(int256(y));
        return t;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { ContextUpgradeSafe } from "@openzeppelin/contracts-ethereum-package/contracts/GSN/Context.sol";

// copy from openzeppelin Ownable, only modify how the owner transfer
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
contract PerpFiOwnableUpgrade is ContextUpgradeSafe {
    address private _owner;
    address private _candidate;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */

    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    function candidate() public view returns (address) {
        return _candidate;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "PerpFiOwnableUpgrade: caller is not the owner");
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
     * @dev Set ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function setOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "PerpFiOwnableUpgrade: zero address");
        require(newOwner != _owner, "PerpFiOwnableUpgrade: same as original");
        require(newOwner != _candidate, "PerpFiOwnableUpgrade: same as candidate");
        _candidate = newOwner;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`_candidate`).
     * Can only be called by the new owner.
     */
    function updateOwner() public {
        require(_candidate != address(0), "PerpFiOwnableUpgrade: candidate is zero address");
        require(_candidate == _msgSender(), "PerpFiOwnableUpgrade: not the new owner");

        emit OwnershipTransferred(_owner, _candidate);
        _owner = _candidate;
        _candidate = address(0);
    }

    uint256[50] private __gap;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "../utils/Decimal.sol";
import { SignedDecimal } from "../utils/SignedDecimal.sol";

interface IAmm {
    /**
     * @notice asset direction, used in getInputPrice, getOutputPrice, swapInput and swapOutput
     * @param ADD_TO_AMM add asset to Amm
     * @param REMOVE_FROM_AMM remove asset from Amm
     */
    enum Dir { ADD_TO_AMM, REMOVE_FROM_AMM }

    struct LiquidityChangedSnapshot {
        SignedDecimal.signedDecimal cumulativeNotional;
        // the base/quote reserve of amm right before liquidity changed
        Decimal.decimal quoteAssetReserve;
        Decimal.decimal baseAssetReserve;
        // total position size owned by amm after last snapshot taken
        // `totalPositionSize` = currentBaseAssetReserve - lastLiquidityChangedHistoryItem.baseAssetReserve + prevTotalPositionSize
        SignedDecimal.signedDecimal totalPositionSize;
    }

    function swapInput(
        Dir _dir,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _baseAssetAmountLimit,
        bool _canOverFluctuationLimit
    ) external returns (Decimal.decimal memory);

    function swapOutput(
        Dir _dir,
        Decimal.decimal calldata _baseAssetAmount,
        Decimal.decimal calldata _quoteAssetAmountLimit
    ) external returns (Decimal.decimal memory);

    function shutdown() external;

    function settleFunding() external returns (SignedDecimal.signedDecimal memory);

    function calcFee(Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        returns (Decimal.decimal memory, Decimal.decimal memory);

    //
    // VIEW
    //

    function isOverFluctuationLimit(Dir _dirOfBase, Decimal.decimal memory _baseAssetAmount)
        external
        view
        returns (bool);

    function calcBaseAssetAfterLiquidityMigration(
        SignedDecimal.signedDecimal memory _baseAssetAmount,
        Decimal.decimal memory _fromQuoteReserve,
        Decimal.decimal memory _fromBaseReserve
    ) external view returns (SignedDecimal.signedDecimal memory);

    function getInputTwap(Dir _dir, Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getOutputTwap(Dir _dir, Decimal.decimal calldata _baseAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getInputPrice(Dir _dir, Decimal.decimal calldata _quoteAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getOutputPrice(Dir _dir, Decimal.decimal calldata _baseAssetAmount)
        external
        view
        returns (Decimal.decimal memory);

    function getInputPriceWithReserves(
        Dir _dir,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) external pure returns (Decimal.decimal memory);

    function getOutputPriceWithReserves(
        Dir _dir,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) external pure returns (Decimal.decimal memory);

    function getSpotPrice() external view returns (Decimal.decimal memory);

    function getLiquidityHistoryLength() external view returns (uint256);

    // overridden by state variable
    function quoteAsset() external view returns (IERC20);

    function open() external view returns (bool);

    // can not be overridden by state variable due to type `Deciaml.decimal`
    function getSettlementPrice() external view returns (Decimal.decimal memory);

    function getBaseAssetDeltaThisFundingPeriod() external view returns (SignedDecimal.signedDecimal memory);

    function getCumulativeNotional() external view returns (SignedDecimal.signedDecimal memory);

    function getMaxHoldingBaseAsset() external view returns (Decimal.decimal memory);

    function getOpenInterestNotionalCap() external view returns (Decimal.decimal memory);

    function getLiquidityChangedSnapshots(uint256 i) external view returns (LiquidityChangedSnapshot memory);

    function getBaseAssetDelta() external view returns (SignedDecimal.signedDecimal memory);

    function getUnderlyingPrice() external view returns (Decimal.decimal memory);

    function isOverSpreadLimit() external view returns (bool);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

/// @dev Implements simple fixed point math add, sub, mul and div operations.
/// @author Alberto Cuesta Cañada
library DecimalMath {
    using SafeMath for uint256;

    /// @dev Returns 1 in the fixed point representation, with `decimals` decimals.
    function unit(uint8 decimals) internal pure returns (uint256) {
        return 10**uint256(decimals);
    }

    /// @dev Adds x and y, assuming they are both fixed point with 18 decimals.
    function addd(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.add(y);
    }

    /// @dev Subtracts y from x, assuming they are both fixed point with 18 decimals.
    function subd(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.sub(y);
    }

    /// @dev Multiplies x and y, assuming they are both fixed point with 18 digits.
    function muld(uint256 x, uint256 y) internal pure returns (uint256) {
        return muld(x, y, 18);
    }

    /// @dev Multiplies x and y, assuming they are both fixed point with `decimals` digits.
    function muld(
        uint256 x,
        uint256 y,
        uint8 decimals
    ) internal pure returns (uint256) {
        return x.mul(y).div(unit(decimals));
    }

    /// @dev Divides x between y, assuming they are both fixed point with 18 digits.
    function divd(uint256 x, uint256 y) internal pure returns (uint256) {
        return divd(x, y, 18);
    }

    /// @dev Divides x between y, assuming they are both fixed point with `decimals` digits.
    function divd(
        uint256 x,
        uint256 y,
        uint8 decimals
    ) internal pure returns (uint256) {
        return x.mul(unit(decimals)).div(y);
    }
}

pragma solidity ^0.6.0;

/**
 * @title SignedSafeMath
 * @dev Signed math operations with safety checks that revert on error.
 */
library SignedSafeMath {
    int256 constant private _INT256_MIN = -2**255;

    /**
     * @dev Multiplies two signed integers, reverts on overflow.
     */
    function mul(int256 a, int256 b) internal pure returns (int256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        require(!(a == -1 && b == _INT256_MIN), "SignedSafeMath: multiplication overflow");

        int256 c = a * b;
        require(c / a == b, "SignedSafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Integer division of two signed integers truncating the quotient, reverts on division by zero.
     */
    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != 0, "SignedSafeMath: division by zero");
        require(!(b == -1 && a == _INT256_MIN), "SignedSafeMath: division overflow");

        int256 c = a / b;

        return c;
    }

    /**
     * @dev Subtracts two signed integers, reverts on overflow.
     */
    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a), "SignedSafeMath: subtraction overflow");

        return c;
    }

    /**
     * @dev Adds two signed integers, reverts on overflow.
     */
    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a), "SignedSafeMath: addition overflow");

        return c;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { SignedSafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SignedSafeMath.sol";

/// @dev Implements simple signed fixed point math add, sub, mul and div operations.
library SignedDecimalMath {
    using SignedSafeMath for int256;

    /// @dev Returns 1 in the fixed point representation, with `decimals` decimals.
    function unit(uint8 decimals) internal pure returns (int256) {
        return int256(10**uint256(decimals));
    }

    /// @dev Adds x and y, assuming they are both fixed point with 18 decimals.
    function addd(int256 x, int256 y) internal pure returns (int256) {
        return x.add(y);
    }

    /// @dev Subtracts y from x, assuming they are both fixed point with 18 decimals.
    function subd(int256 x, int256 y) internal pure returns (int256) {
        return x.sub(y);
    }

    /// @dev Multiplies x and y, assuming they are both fixed point with 18 digits.
    function muld(int256 x, int256 y) internal pure returns (int256) {
        return muld(x, y, 18);
    }

    /// @dev Multiplies x and y, assuming they are both fixed point with `decimals` digits.
    function muld(
        int256 x,
        int256 y,
        uint8 decimals
    ) internal pure returns (int256) {
        return x.mul(y).div(unit(decimals));
    }

    /// @dev Divides x between y, assuming they are both fixed point with 18 digits.
    function divd(int256 x, int256 y) internal pure returns (int256) {
        return divd(x, y, 18);
    }

    /// @dev Divides x between y, assuming they are both fixed point with `decimals` digits.
    function divd(
        int256 x,
        int256 y,
        uint8 decimals
    ) internal pure returns (int256) {
        return x.mul(unit(decimals)).div(y);
    }
}

pragma solidity ^0.6.0;
import "../Initializable.sol";

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
contract ContextUpgradeSafe is Initializable {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.

    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {


    }


    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }

    uint256[50] private __gap;
}

pragma solidity >=0.4.24 <0.7.0;


/**
 * @title Initializable
 *
 * @dev Helper contract to support initializer functions. To use it, replace
 * the constructor with a function that has the `initializer` modifier.
 * WARNING: Unlike constructors, initializer functions must be manually
 * invoked. This applies both to deploying an Initializable contract, as well
 * as extending an Initializable contract via inheritance.
 * WARNING: When used with inheritance, manual care must be taken to not invoke
 * a parent initializer twice, or ensure that all initializers are idempotent,
 * because this is not dealt with automatically as with constructors.
 */
contract Initializable {

  /**
   * @dev Indicates that the contract has been initialized.
   */
  bool private initialized;

  /**
   * @dev Indicates that the contract is in the process of being initialized.
   */
  bool private initializing;

  /**
   * @dev Modifier to use in the initializer function of a contract.
   */
  modifier initializer() {
    require(initializing || isConstructor() || !initialized, "Contract instance has already been initialized");

    bool isTopLevelCall = !initializing;
    if (isTopLevelCall) {
      initializing = true;
      initialized = true;
    }

    _;

    if (isTopLevelCall) {
      initializing = false;
    }
  }

  /// @dev Returns true if and only if the function is running in the constructor
  function isConstructor() private view returns (bool) {
    // extcodesize checks the size of the code stored in an address, and
    // address returns the current address. Since the code is still not
    // deployed when running a constructor, any checks on its code size will
    // yield zero, making it an effective way to detect if a contract is
    // under construction or not.
    address self = address(this);
    uint256 cs;
    assembly { cs := extcodesize(self) }
    return cs == 0;
  }

  // Reserved storage space to allow for layout changes in the future.
  uint256[50] private ______gap;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { ClearingHouseFake } from "./ClearingHouseFake.sol";
import { Amm } from "../Amm.sol";
import { Decimal } from "../utils/Decimal.sol";

contract TraderWallet {
    ClearingHouseFake public clearingHouse;

    enum ActionType { OPEN, CLOSE, LIQUIDATE }

    constructor(ClearingHouseFake _clearingHouse, IERC20 _token) public {
        clearingHouse = _clearingHouse;
        _token.approve(address(clearingHouse), uint256(-1));
    }

    function openPosition(
        Amm _amm,
        ClearingHouseFake.Side _side,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _leverage,
        Decimal.decimal calldata _minBaseAssetAmount
    ) external {
        clearingHouse.openPosition(_amm, _side, _quoteAssetAmount, _leverage, _minBaseAssetAmount);
    }

    function liquidate(Amm _amm, address _trader) external {
        clearingHouse.liquidate(_amm, _trader);
    }

    function closePosition(Amm _amm) external {
        clearingHouse.closePosition(_amm, Decimal.zero());
    }

    function multiActions(
        ActionType _action1,
        bool _setRestriction,
        ActionType _action2,
        Amm _amm,
        ClearingHouseFake.Side _side,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _leverage,
        Decimal.decimal calldata _baseAssetAmountLimit,
        address _trader
    ) external {
        executeAction(_action1, _amm, _side, _quoteAssetAmount, _leverage, _baseAssetAmountLimit, _trader);
        if (_setRestriction) {
            clearingHouse.mockSetRestrictionMode(_amm);
        }
        executeAction(_action2, _amm, _side, _quoteAssetAmount, _leverage, _baseAssetAmountLimit, _trader);
    }

    function twoLiquidations(
        Amm _amm,
        address _trader1,
        address _trader2
    ) external {
        clearingHouse.liquidate(_amm, _trader1);
        clearingHouse.liquidate(_amm, _trader2);
    }

    function threeLiquidations(
        Amm _amm,
        address _trader1,
        address _trader2,
        address _trader3
    ) external {
        clearingHouse.liquidate(_amm, _trader1);
        clearingHouse.liquidate(_amm, _trader2);
        clearingHouse.liquidate(_amm, _trader3);
    }

    function executeAction(
        ActionType _action,
        Amm _amm,
        ClearingHouseFake.Side _side,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit,
        address _trader
    ) internal {
        if (_action == ActionType.OPEN) {
            clearingHouse.openPosition(_amm, _side, _quoteAssetAmount, _leverage, _baseAssetAmountLimit);
        } else if (_action == ActionType.CLOSE) {
            clearingHouse.closePosition(_amm, Decimal.zero());
        } else if (_action == ActionType.LIQUIDATE) {
            clearingHouse.liquidate(_amm, _trader);
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../ClearingHouse.sol";
import "../interface/IAmm.sol";

// temporary commented unused functions to bypass contract too large error
contract ClearingHouseFake is ClearingHouse {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    // function mock_getCurrentTimestamp() public view returns (uint256) {
    //     return _blockTimestamp();
    // }

    function mock_getCurrentBlockNumber() public view returns (uint256) {
        return _blockNumber();
    }

    // // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }

    function mockSetRestrictionMode(IAmm _amm) external {
        enterRestrictionMode(_amm);
    }

    function isInRestrictMode(address _amm, uint256 _block) external view returns (bool) {
        return ammMap[_amm].lastRestrictionBlock == _block;
    }

    function getPrepaidBadDebt(address _token) public view returns (Decimal.decimal memory) {
        return prepaidBadDebt[_token];
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { BlockContext } from "./utils/BlockContext.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "./utils/Decimal.sol";
import { SignedDecimal } from "./utils/SignedDecimal.sol";
import { MixedDecimal } from "./utils/MixedDecimal.sol";
import { DecimalERC20 } from "./utils/DecimalERC20.sol";
import { ContextUpgradeSafe } from "@openzeppelin/contracts-ethereum-package/contracts/GSN/Context.sol";
// prettier-ignore
// solhint-disable-next-line
import { ReentrancyGuardUpgradeSafe } from "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import { OwnerPausableUpgradeSafe } from "./OwnerPausable.sol";
import { IAmm } from "./interface/IAmm.sol";
import { IInsuranceFund } from "./interface/IInsuranceFund.sol";
import { IMultiTokenRewardRecipient } from "./interface/IMultiTokenRewardRecipient.sol";

// note BaseRelayRecipient must come after OwnerPausableUpgradeSafe so its _msgSender() takes precedence
// (yes, the ordering is reversed comparing to Python)
contract ClearingHouse is DecimalERC20, OwnerPausableUpgradeSafe, ReentrancyGuardUpgradeSafe, BlockContext {
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    //
    // EVENTS
    //
    event MarginRatioChanged(uint256 marginRatio);
    event LiquidationFeeRatioChanged(uint256 liquidationFeeRatio);
    event MarginChanged(address indexed sender, address indexed amm, int256 amount, int256 fundingPayment);
    event PositionAdjusted(
        address indexed amm,
        address indexed trader,
        int256 newPositionSize,
        uint256 oldLiquidityIndex,
        uint256 newLiquidityIndex
    );
    event PositionSettled(address indexed amm, address indexed trader, uint256 valueTransferred);
    event RestrictionModeEntered(address amm, uint256 blockNumber);

    /// @notice This event is emitted when position change
    /// @param trader the address which execute this transaction
    /// @param amm IAmm address
    /// @param margin margin
    /// @param positionNotional margin * leverage
    /// @param exchangedPositionSize position size, e.g. ETHUSDC or LINKUSDC
    /// @param fee transaction fee
    /// @param positionSizeAfter position size after this transaction, might be increased or decreased
    /// @param realizedPnl realized pnl after this position changed
    /// @param unrealizedPnlAfter unrealized pnl after this position changed
    /// @param badDebt position change amount cleared by insurance funds
    /// @param liquidationPenalty amount of remaining margin lost due to liquidation
    /// @param spotPrice quote asset reserve / base asset reserve
    /// @param fundingPayment funding payment (+: trader paid, -: trader received)
    event PositionChanged(
        address indexed trader,
        address indexed amm,
        uint256 margin,
        uint256 positionNotional,
        int256 exchangedPositionSize,
        uint256 fee,
        int256 positionSizeAfter,
        int256 realizedPnl,
        int256 unrealizedPnlAfter,
        uint256 badDebt,
        uint256 liquidationPenalty,
        uint256 spotPrice,
        int256 fundingPayment
    );

    /// @notice This event is emitted when position liquidated
    /// @param trader the account address being liquidated
    /// @param amm IAmm address
    /// @param positionNotional liquidated position value minus liquidationFee
    /// @param positionSize liquidated position size
    /// @param liquidationFee liquidation fee to the liquidator
    /// @param liquidator the address which execute this transaction
    /// @param badDebt liquidation fee amount cleared by insurance funds
    event PositionLiquidated(
        address indexed trader,
        address indexed amm,
        uint256 positionNotional,
        uint256 positionSize,
        uint256 liquidationFee,
        address liquidator,
        uint256 badDebt
    );

    event ReferredPositionChanged(bytes32 indexed referralCode);

    //
    // Struct and Enum
    //

    enum Side { BUY, SELL }
    enum PnlCalcOption { SPOT_PRICE, TWAP, ORACLE }

    /// @notice This struct records personal position information
    /// @param size denominated in amm.baseAsset
    /// @param margin isolated margin
    /// @param openNotional the quoteAsset value of position when opening position. the cost of the position
    /// @param lastUpdatedCumulativePremiumFraction for calculating funding payment, record at the moment every time when trader open/reduce/close position
    /// @param liquidityHistoryIndex
    /// @param blockNumber the block number of the last position
    struct Position {
        SignedDecimal.signedDecimal size;
        Decimal.decimal margin;
        Decimal.decimal openNotional;
        SignedDecimal.signedDecimal lastUpdatedCumulativePremiumFraction;
        uint256 liquidityHistoryIndex;
        uint256 blockNumber;
    }

    /// @notice This struct is used for avoiding stack too deep error when passing too many var between functions
    struct PositionResp {
        Position position;
        // the quote asset amount trader will send if open position, will receive if close
        Decimal.decimal exchangedQuoteAssetAmount;
        // if realizedPnl + realizedFundingPayment + margin is negative, it's the abs value of it
        Decimal.decimal badDebt;
        // the base asset amount trader will receive if open position, will send if close
        SignedDecimal.signedDecimal exchangedPositionSize;
        // funding payment incurred during this position response
        SignedDecimal.signedDecimal fundingPayment;
        // realizedPnl = unrealizedPnl * closedRatio
        SignedDecimal.signedDecimal realizedPnl;
        // positive = trader transfer margin to vault, negative = trader receive margin from vault
        // it's 0 when internalReducePosition, its addedMargin when internalIncreasePosition
        // it's min(0, oldPosition + realizedFundingPayment + realizedPnl) when internalClosePosition
        SignedDecimal.signedDecimal marginToVault;
        // unrealized pnl after open position
        SignedDecimal.signedDecimal unrealizedPnlAfter;
    }

    struct AmmMap {
        // issue #1471
        // last block when it turn restriction mode on.
        // In restriction mode, no one can do multi open/close/liquidate position in the same block.
        // If any underwater position being closed (having a bad debt and make insuranceFund loss),
        // or any liquidation happened,
        // restriction mode is ON in that block and OFF(default) in the next block.
        // This design is to prevent the attacker being benefited from the multiple action in one block
        // in extreme cases
        uint256 lastRestrictionBlock;
        SignedDecimal.signedDecimal[] cumulativePremiumFractions;
        mapping(address => Position) positionMap;
    }

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//

    // only admin
    Decimal.decimal public initMarginRatio;

    // only admin
    Decimal.decimal public maintenanceMarginRatio;

    // only admin
    Decimal.decimal public liquidationFeeRatio;

    // key by amm address. will be deprecated or replaced after guarded period.
    // it's not an accurate open interest, just a rough way to control the unexpected loss at the beginning
    mapping(address => Decimal.decimal) public openInterestNotionalMap;

    // key by amm address
    mapping(address => AmmMap) internal ammMap;

    // prepaid bad debt balance, key by ERC20 token address
    mapping(address => Decimal.decimal) internal prepaidBadDebt;

    // contract dependencies
    IInsuranceFund public insuranceFund;
    IMultiTokenRewardRecipient public feePool;

    // designed for arbitragers who can hold unlimited positions. will be removed after guarded period
    address internal whitelist;

    uint256[50] private __gap;
    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//
    Decimal.decimal public partialLiquidationRatio;

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    //

    // FUNCTIONS
    //
    // openzeppelin doesn't support struct input
    // https://github.com/OpenZeppelin/openzeppelin-sdk/issues/1523
    function initialize(
        uint256 _initMarginRatio,
        uint256 _maintenanceMarginRatio,
        uint256 _liquidationFeeRatio,
        IInsuranceFund _insuranceFund
    ) public initializer {
        require(address(_insuranceFund) != address(0));

        __OwnerPausable_init();
        __ReentrancyGuard_init();

        initMarginRatio = Decimal.decimal(_initMarginRatio);
        maintenanceMarginRatio = Decimal.decimal(_maintenanceMarginRatio);
        liquidationFeeRatio = Decimal.decimal(_liquidationFeeRatio);
        insuranceFund = _insuranceFund;
    }

    //
    // External
    //

    /**
     * @notice set liquidation fee ratio
     * @dev only owner can call
     * @param _liquidationFeeRatio new liquidation fee ratio in 18 digits
     */
    function setLiquidationFeeRatio(Decimal.decimal memory _liquidationFeeRatio) external onlyOwner {
        liquidationFeeRatio = _liquidationFeeRatio;
        emit LiquidationFeeRatioChanged(liquidationFeeRatio.toUint());
    }

    /**
     * @notice set maintenance margin ratio
     * @dev only owner can call
     * @param _maintenanceMarginRatio new maintenance margin ratio in 18 digits
     */
    function setMaintenanceMarginRatio(Decimal.decimal memory _maintenanceMarginRatio) external onlyOwner {
        maintenanceMarginRatio = _maintenanceMarginRatio;
        emit MarginRatioChanged(maintenanceMarginRatio.toUint());
    }

    /**
     * @notice set the toll pool address
     * @dev only owner can call
     */
    function setTollPool(address _feePool) external onlyOwner {
        feePool = IMultiTokenRewardRecipient(_feePool);
    }

    /**
     * @notice add an address in the whitelist. People in the whitelist can hold unlimited positions.
     * @dev only owner can call
     * @param _whitelist an address
     */
    function setWhitelist(address _whitelist) external onlyOwner {
        whitelist = _whitelist;
    }

    /**
     * @notice set the margin ratio after deleveraging
     * @dev only owner can call
     */
    function setPartialLiquidationRatio(Decimal.decimal memory _ratio) external onlyOwner {
        require(_ratio.cmp(Decimal.one()) <= 0);
        partialLiquidationRatio = _ratio;
    }

    /**
     * @notice add margin to increase margin ratio
     * @param _amm IAmm address
     * @param _addedMargin added margin in 18 digits
     */
    function addMargin(IAmm _amm, Decimal.decimal calldata _addedMargin) external whenNotPaused() nonReentrant() {
        // check condition
        requireAmm(_amm, true);
        requireNonZeroInput(_addedMargin);
        // update margin part in personal position
        address trader = _msgSender();
        Position memory position = adjustPositionForLiquidityChanged(_amm, trader);
        position.margin = position.margin.addD(_addedMargin);
        setPosition(_amm, trader, position);
        // transfer token from trader
        _transferFrom(_amm.quoteAsset(), trader, address(this), _addedMargin);
        emit MarginChanged(trader, address(_amm), int256(_addedMargin.toUint()), 0);
    }

    /**
     * @notice remove margin to decrease margin ratio
     * @param _amm IAmm address
     * @param _removedMargin removed margin in 18 digits
     */
    function removeMargin(IAmm _amm, Decimal.decimal calldata _removedMargin) external whenNotPaused() nonReentrant() {
        // check condition
        requireAmm(_amm, true);
        requireNonZeroInput(_removedMargin);
        // update margin part in personal position
        address trader = _msgSender();
        Position memory position = adjustPositionForLiquidityChanged(_amm, trader);
        // realize funding payment if there's no bad debt
        SignedDecimal.signedDecimal memory marginDelta = MixedDecimal.fromDecimal(_removedMargin).mulScalar(-1);
        (
            Decimal.decimal memory remainMargin,
            Decimal.decimal memory badDebt,
            SignedDecimal.signedDecimal memory fundingPayment,
            SignedDecimal.signedDecimal memory latestCumulativePremiumFraction
        ) = calcRemainMarginWithFundingPayment(_amm, position, marginDelta);
        require(badDebt.toUint() == 0);
        position.margin = remainMargin;
        position.lastUpdatedCumulativePremiumFraction = latestCumulativePremiumFraction;
        setPosition(_amm, trader, position);
        // check margin ratio
        requireMoreMarginRatio(getMarginRatio(_amm, trader), initMarginRatio, true);
        // transfer token back to trader
        withdraw(_amm.quoteAsset(), trader, _removedMargin);
        emit MarginChanged(trader, address(_amm), marginDelta.toInt(), fundingPayment.toInt());
    }

    /**
     * @notice settle all the positions when amm is shutdown. The settlement price is according to IAmm.settlementPrice
     * @param _amm IAmm address
     */
    function settlePosition(IAmm _amm) external nonReentrant() {
        // check condition
        requireAmm(_amm, false);
        address trader = _msgSender();
        Position memory pos = getPosition(_amm, trader);
        requirePositionSize(pos.size);
        // update position
        clearPosition(_amm, trader);
        // calculate settledValue
        // If Settlement Price = 0, everyone takes back her collateral.
        // else Returned Fund = Position Size * (Settlement Price - Open Price) + Collateral
        Decimal.decimal memory settlementPrice = _amm.getSettlementPrice();
        Decimal.decimal memory settledValue;
        if (settlementPrice.toUint() == 0) {
            settledValue = pos.margin;
        } else {
            // returnedFund = positionSize * (settlementPrice - openPrice) + positionMargin
            // openPrice = positionOpenNotional / positionSize.abs()
            SignedDecimal.signedDecimal memory returnedFund =
                pos
                    .size
                    .mulD(MixedDecimal.fromDecimal(settlementPrice).subD(pos.openNotional.divD(pos.size.abs())))
                    .addD(pos.margin);
            // if `returnedFund` is negative, trader can't get anything back
            if (returnedFund.toInt() > 0) {
                settledValue = returnedFund.abs();
            }
        }
        // transfer token based on settledValue. no insurance fund support
        if (settledValue.toUint() > 0) {
            _transfer(_amm.quoteAsset(), trader, settledValue);
        }
        // emit event
        emit PositionSettled(address(_amm), trader, settledValue.toUint());
    }

    // if increase position
    //   marginToVault = addMargin
    //   marginDiff = realizedFundingPayment + realizedPnl(0)
    //   pos.margin += marginToVault + marginDiff
    //   vault.margin += marginToVault + marginDiff
    //   required(enoughMarginRatio)
    // else if reduce position()
    //   marginToVault = 0
    //   marginDiff = realizedFundingPayment + realizedPnl
    //   pos.margin += marginToVault + marginDiff
    //   if pos.margin < 0, badDebt = abs(pos.margin), set pos.margin = 0
    //   vault.margin += marginToVault + marginDiff
    //   required(enoughMarginRatio)
    // else if close
    //   marginDiff = realizedFundingPayment + realizedPnl
    //   pos.margin += marginDiff
    //   if pos.margin < 0, badDebt = abs(pos.margin)
    //   marginToVault = -pos.margin
    //   set pos.margin = 0
    //   vault.margin += marginToVault + marginDiff
    // else if close and open a larger position in reverse side
    //   close()
    //   positionNotional -= exchangedQuoteAssetAmount
    //   newMargin = positionNotional / leverage
    //   internalIncreasePosition(newMargin, leverage)
    // else if liquidate
    //   close()
    //   pay liquidation fee to liquidator
    //   move the remain margin to insuranceFund

    /**
     * @notice open a position with referral code
     * @param _amm amm address
     * @param _side enum Side; BUY for long and SELL for short
     * @param _quoteAssetAmount quote asset amount in 18 digits. Can Not be 0
     * @param _leverage leverage  in 18 digits. Can Not be 0
     * @param _baseAssetAmountLimit minimum base asset amount expected to get to prevent from slippage.
     * @param _referralCode referral code
     */
    // function openPositionWithReferral(
    //     IAmm _amm,
    //     Side _side,
    //     Decimal.decimal calldata _quoteAssetAmount,
    //     Decimal.decimal calldata _leverage,
    //     Decimal.decimal calldata _baseAssetAmountLimit,
    //     bytes32 _referralCode
    // ) external {
    //     openPosition(_amm, _side, _quoteAssetAmount, _leverage, _baseAssetAmountLimit);
    //     if (_referralCode != 0) {
    //         emit ReferredPositionChanged(_referralCode);
    //     }
    // }

    /**
     * @notice open a position
     * @param _amm amm address
     * @param _side enum Side; BUY for long and SELL for short
     * @param _quoteAssetAmount quote asset amount in 18 digits. Can Not be 0
     * @param _leverage leverage  in 18 digits. Can Not be 0
     * @param _baseAssetAmountLimit minimum base asset amount expected to get to prevent from slippage.
     */
    function openPosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit
    ) public whenNotPaused() nonReentrant() {
        requireAmm(_amm, true);
        requireNonZeroInput(_quoteAssetAmount);
        requireNonZeroInput(_leverage);
        requireMoreMarginRatio(MixedDecimal.fromDecimal(Decimal.one()).divD(_leverage), initMarginRatio, true);
        requireNotRestrictionMode(_amm);

        address trader = _msgSender();
        PositionResp memory positionResp;
        {
            // add scope for stack too deep error
            int256 oldPositionSize = adjustPositionForLiquidityChanged(_amm, trader).size.toInt();
            bool isNewPosition = oldPositionSize == 0 ? true : false;

            // increase or decrease position depends on old position's side and size
            if (isNewPosition || (oldPositionSize > 0 ? Side.BUY : Side.SELL) == _side) {
                positionResp = internalIncreasePosition(
                    _amm,
                    _side,
                    _quoteAssetAmount.mulD(_leverage),
                    _baseAssetAmountLimit,
                    _leverage
                );
            } else {
                positionResp = openReversePosition(
                    _amm,
                    _side,
                    trader,
                    _quoteAssetAmount,
                    _leverage,
                    _baseAssetAmountLimit,
                    false
                );
            }

            // update the position state
            setPosition(_amm, trader, positionResp.position);
            // if opening the exact position size as the existing one == closePosition, can skip the margin ratio check
            if (!isNewPosition && positionResp.position.size.toInt() != 0) {
                requireMoreMarginRatio(getMarginRatio(_amm, trader), maintenanceMarginRatio, true);
            }

            // to prevent attacker to leverage the bad debt to withdraw extra token from  insurance fund
            if (positionResp.badDebt.toUint() > 0) {
                enterRestrictionMode(_amm);
            }

            // transfer the actual token between trader and vault
            IERC20 quoteToken = _amm.quoteAsset();
            if (positionResp.marginToVault.toInt() > 0) {
                _transferFrom(quoteToken, trader, address(this), positionResp.marginToVault.abs());
            } else if (positionResp.marginToVault.toInt() < 0) {
                withdraw(quoteToken, trader, positionResp.marginToVault.abs());
            }
        }

        // calculate fee and transfer token for fees
        //@audit - can optimize by changing amm.swapInput/swapOutput's return type to (exchangedAmount, quoteToll, quoteSpread, quoteReserve, baseReserve) (@wraecca)
        Decimal.decimal memory transferredFee = transferFee(trader, _amm, positionResp.exchangedQuoteAssetAmount);

        // emit event
        uint256 spotPrice = _amm.getSpotPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt(); // pre-fetch for stack too deep error
        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            transferredFee.toUint(),
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            0,
            spotPrice,
            fundingPayment
        );
    }

    /**
     * @notice close position with referral code
     * @param _amm IAmm address
     * @param _referralCode referral code
     */
    // function closePositionWithReferral(
    //     IAmm _amm,
    //     Decimal.decimal calldata _quoteAssetAmountLimit,
    //     bytes32 _referralCode
    // ) external {
    //     closePosition(_amm, _quoteAssetAmountLimit);
    //     if (_referralCode != 0) {
    //         emit ReferredPositionChanged(_referralCode);
    //     }
    // }

    /**
     * @notice close all the positions
     * @param _amm IAmm address
     */
    function closePosition(IAmm _amm, Decimal.decimal memory _quoteAssetAmountLimit)
        public
        whenNotPaused()
        nonReentrant()
    {
        // check conditions
        requireAmm(_amm, true);
        requireNotRestrictionMode(_amm);

        // update position
        address trader = _msgSender();
        adjustPositionForLiquidityChanged(_amm, trader);

        PositionResp memory positionResp;
        {
            Position memory position = getPosition(_amm, trader);
            // if it is long position, close a position means short it(which means base dir is ADD_TO_AMM) and vice versa
            IAmm.Dir dirOfBase = position.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM;

            // check if this position exceed fluctuation limit
            // if over fluctuation limit, then close partial position. Otherwise close all.
            // if partialLiquidationRatio is 1, then close whole position
            if (
                _amm.isOverFluctuationLimit(dirOfBase, position.size.abs()) &&
                partialLiquidationRatio.cmp(Decimal.one()) < 0
            ) {
                Decimal.decimal memory partiallyClosedPositionNotional =
                    _amm.getOutputPrice(dirOfBase, position.size.mulD(partialLiquidationRatio).abs());

                positionResp = openReversePosition(
                    _amm,
                    position.size.toInt() > 0 ? Side.SELL : Side.BUY,
                    trader,
                    partiallyClosedPositionNotional,
                    Decimal.one(),
                    Decimal.zero(),
                    true
                );
                setPosition(_amm, trader, positionResp.position);
            } else {
                positionResp = internalClosePosition(_amm, trader, _quoteAssetAmountLimit);
            }

            // add scope for stack too deep error
            // transfer the actual token from trader and vault
            IERC20 quoteToken = _amm.quoteAsset();
            if (positionResp.badDebt.toUint() > 0) {
                enterRestrictionMode(_amm);
                realizeBadDebt(quoteToken, positionResp.badDebt);
            }
            withdraw(quoteToken, trader, positionResp.marginToVault.abs());
        }

        // calculate fee and transfer token for fees
        Decimal.decimal memory transferredFee = transferFee(trader, _amm, positionResp.exchangedQuoteAssetAmount);

        // prepare event
        uint256 spotPrice = _amm.getSpotPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt();
        emit PositionChanged(
            trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            transferredFee.toUint(),
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            0,
            spotPrice,
            fundingPayment
        );
    }

    /**
     * @notice liquidate trader's underwater position. Require trader's margin ratio less than maintenance margin ratio
     * @dev liquidator can NOT open any positions in the same block to prevent from price manipulation.
     * @param _amm IAmm address
     * @param _trader trader address
     */
    function liquidate(IAmm _amm, address _trader) external nonReentrant() {
        requireAmm(_amm, true);
        SignedDecimal.signedDecimal memory marginRatio = getMarginRatio(_amm, _trader);

        // including oracle-based margin ratio as reference price when amm is over spread limit
        if (_amm.isOverSpreadLimit()) {
            SignedDecimal.signedDecimal memory marginRatioBasedOnOracle = _getMarginRatioBasedOnOracle(_amm, _trader);
            if (marginRatioBasedOnOracle.subD(marginRatio).toInt() > 0) {
                marginRatio = marginRatioBasedOnOracle;
            }
        }
        requireMoreMarginRatio(marginRatio, maintenanceMarginRatio, false);

        // update states
        adjustPositionForLiquidityChanged(_amm, _trader);

        PositionResp memory positionResp;
        Decimal.decimal memory liquidationPenalty;
        {
            Decimal.decimal memory liquidationBadDebt;
            Decimal.decimal memory feeToLiquidator;
            Decimal.decimal memory feeToInsuranceFund;
            IERC20 quoteAsset = _amm.quoteAsset();

            if (
                marginRatio.toInt() > int256(liquidationFeeRatio.toUint()) &&
                partialLiquidationRatio.cmp(Decimal.one()) < 0 &&
                partialLiquidationRatio.toUint() != 0
            ) {
                Position memory position = getPosition(_amm, _trader);
                Decimal.decimal memory partiallyLiquidatedPositionNotional =
                    _amm.getOutputPrice(
                        position.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                        position.size.mulD(partialLiquidationRatio).abs()
                    );

                positionResp = openReversePosition(
                    _amm,
                    position.size.toInt() > 0 ? Side.SELL : Side.BUY,
                    _trader,
                    partiallyLiquidatedPositionNotional,
                    Decimal.one(),
                    Decimal.zero(),
                    true
                );

                // half of the liquidationFee goes to liquidator & another half goes to insurance fund
                liquidationPenalty = positionResp.exchangedQuoteAssetAmount.mulD(liquidationFeeRatio);
                feeToLiquidator = liquidationPenalty.divScalar(2);
                feeToInsuranceFund = liquidationPenalty.subD(feeToLiquidator);

                positionResp.position.margin = positionResp.position.margin.subD(liquidationPenalty);
                setPosition(_amm, _trader, positionResp.position);
            } else {
                liquidationPenalty = getPosition(_amm, _trader).margin;
                positionResp = internalClosePosition(_amm, _trader, Decimal.zero());
                Decimal.decimal memory remainMargin = positionResp.marginToVault.abs();
                feeToLiquidator = positionResp.exchangedQuoteAssetAmount.mulD(liquidationFeeRatio).divScalar(2);

                // if the remainMargin is not enough for liquidationFee, count it as bad debt
                // else, then the rest will be transferred to insuranceFund
                Decimal.decimal memory totalBadDebt = positionResp.badDebt;
                if (feeToLiquidator.toUint() > remainMargin.toUint()) {
                    liquidationBadDebt = feeToLiquidator.subD(remainMargin);
                    totalBadDebt = totalBadDebt.addD(liquidationBadDebt);
                } else {
                    remainMargin = remainMargin.subD(feeToLiquidator);
                }

                // transfer the actual token between trader and vault
                if (totalBadDebt.toUint() > 0) {
                    realizeBadDebt(quoteAsset, totalBadDebt);
                }
                if (remainMargin.toUint() > 0) {
                    feeToInsuranceFund = remainMargin;
                }
            }

            if (feeToInsuranceFund.toUint() > 0) {
                transferToInsuranceFund(quoteAsset, feeToInsuranceFund);
            }
            withdraw(quoteAsset, _msgSender(), feeToLiquidator);
            enterRestrictionMode(_amm);

            emit PositionLiquidated(
                _trader,
                address(_amm),
                positionResp.exchangedQuoteAssetAmount.toUint(),
                positionResp.exchangedPositionSize.toUint(),
                feeToLiquidator.toUint(),
                _msgSender(),
                liquidationBadDebt.toUint()
            );
        }

        // emit event
        uint256 spotPrice = _amm.getSpotPrice().toUint();
        int256 fundingPayment = positionResp.fundingPayment.toInt();
        emit PositionChanged(
            _trader,
            address(_amm),
            positionResp.position.margin.toUint(),
            positionResp.exchangedQuoteAssetAmount.toUint(),
            positionResp.exchangedPositionSize.toInt(),
            0,
            positionResp.position.size.toInt(),
            positionResp.realizedPnl.toInt(),
            positionResp.unrealizedPnlAfter.toInt(),
            positionResp.badDebt.toUint(),
            liquidationPenalty.toUint(),
            spotPrice,
            fundingPayment
        );
    }

    /**
     * @notice if funding rate is positive, traders with long position pay traders with short position and vice versa.
     * @param _amm IAmm address
     */
    function payFunding(IAmm _amm) external {
        requireAmm(_amm, true);

        SignedDecimal.signedDecimal memory premiumFraction = _amm.settleFunding();
        ammMap[address(_amm)].cumulativePremiumFractions.push(
            premiumFraction.addD(getLatestCumulativePremiumFraction(_amm))
        );

        // funding payment = premium fraction * position
        // eg. if alice takes 10 long position, totalPositionSize = 10
        // if premiumFraction is positive: long pay short, amm get positive funding payment
        // if premiumFraction is negative: short pay long, amm get negative funding payment
        // if totalPositionSize.side * premiumFraction > 0, funding payment is positive which means profit
        SignedDecimal.signedDecimal memory totalTraderPositionSize = _amm.getBaseAssetDelta();
        SignedDecimal.signedDecimal memory ammFundingPaymentProfit = premiumFraction.mulD(totalTraderPositionSize);

        IERC20 quoteAsset = _amm.quoteAsset();
        if (ammFundingPaymentProfit.toInt() < 0) {
            insuranceFund.withdraw(quoteAsset, ammFundingPaymentProfit.abs());
        } else {
            transferToInsuranceFund(quoteAsset, ammFundingPaymentProfit.abs());
        }
    }

    /**
     * @notice adjust msg.sender's position when liquidity migration happened
     * @param _amm Amm address
     */
    function adjustPosition(IAmm _amm) external {
        adjustPositionForLiquidityChanged(_amm, _msgSender());
    }

    //
    // VIEW FUNCTIONS
    //

    /**
     * @notice get margin ratio, marginRatio = (margin + funding payment + unrealized Pnl) / positionNotional
     * use spot and twap price to calculate unrealized Pnl, final unrealized Pnl depends on which one is higher
     * @param _amm IAmm address
     * @param _trader trader address
     * @return margin ratio in 18 digits
     */
    function getMarginRatio(IAmm _amm, address _trader) public view returns (SignedDecimal.signedDecimal memory) {
        Position memory position = getPosition(_amm, _trader);
        requirePositionSize(position.size);

        (Decimal.decimal memory spotPositionNotional, SignedDecimal.signedDecimal memory spotPricePnl) =
            (getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.SPOT_PRICE));
        (Decimal.decimal memory twapPositionNotional, SignedDecimal.signedDecimal memory twapPricePnl) =
            (getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.TWAP));
        (SignedDecimal.signedDecimal memory unrealizedPnl, Decimal.decimal memory positionNotional) =
            spotPricePnl.toInt() > twapPricePnl.toInt()
                ? (spotPricePnl, spotPositionNotional)
                : (twapPricePnl, twapPositionNotional);
        return _getMarginRatio(_amm, position, unrealizedPnl, positionNotional);
    }

    function _getMarginRatioBasedOnOracle(IAmm _amm, address _trader)
        internal
        view
        returns (SignedDecimal.signedDecimal memory)
    {
        Position memory position = getPosition(_amm, _trader);
        requirePositionSize(position.size);
        (Decimal.decimal memory oraclePositionNotional, SignedDecimal.signedDecimal memory oraclePricePnl) =
            (getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.ORACLE));
        return _getMarginRatio(_amm, position, oraclePricePnl, oraclePositionNotional);
    }

    function _getMarginRatio(
        IAmm _amm,
        Position memory _position,
        SignedDecimal.signedDecimal memory _unrealizedPnl,
        Decimal.decimal memory _positionNotional
    ) internal view returns (SignedDecimal.signedDecimal memory) {
        (Decimal.decimal memory remainMargin, Decimal.decimal memory badDebt, , ) =
            calcRemainMarginWithFundingPayment(_amm, _position, _unrealizedPnl);
        return MixedDecimal.fromDecimal(remainMargin).subD(badDebt).divD(_positionNotional);
    }

    /**
     * @notice get personal position information, and adjust size if migration is necessary
     * @param _amm IAmm address
     * @param _trader trader address
     * @return struct Position
     */
    function getPosition(IAmm _amm, address _trader) public view returns (Position memory) {
        Position memory pos = getUnadjustedPosition(_amm, _trader);
        uint256 latestLiquidityIndex = _amm.getLiquidityHistoryLength().sub(1);
        if (pos.liquidityHistoryIndex == latestLiquidityIndex) {
            return pos;
        }

        return calcPositionAfterLiquidityMigration(_amm, pos, latestLiquidityIndex);
    }

    /**
     * @notice get position notional and unrealized Pnl without fee expense and funding payment
     * @param _amm IAmm address
     * @param _trader trader address
     * @param _pnlCalcOption enum PnlCalcOption, SPOT_PRICE for spot price and TWAP for twap price
     * @return positionNotional position notional
     * @return unrealizedPnl unrealized Pnl
     */
    function getPositionNotionalAndUnrealizedPnl(
        IAmm _amm,
        address _trader,
        PnlCalcOption _pnlCalcOption
    ) public view returns (Decimal.decimal memory positionNotional, SignedDecimal.signedDecimal memory unrealizedPnl) {
        Position memory position = getPosition(_amm, _trader);
        Decimal.decimal memory positionSizeAbs = position.size.abs();
        if (positionSizeAbs.toUint() != 0) {
            bool isShortPosition = position.size.toInt() < 0;
            IAmm.Dir dir = isShortPosition ? IAmm.Dir.REMOVE_FROM_AMM : IAmm.Dir.ADD_TO_AMM;
            if (_pnlCalcOption == PnlCalcOption.TWAP) {
                positionNotional = _amm.getOutputTwap(dir, positionSizeAbs);
            } else if (_pnlCalcOption == PnlCalcOption.SPOT_PRICE) {
                positionNotional = _amm.getOutputPrice(dir, positionSizeAbs);
            } else {
                Decimal.decimal memory oraclePrice = _amm.getUnderlyingPrice();
                positionNotional = positionSizeAbs.mulD(oraclePrice);
            }
            // unrealizedPnlForLongPosition = positionNotional - openNotional
            // unrealizedPnlForShortPosition = positionNotionalWhenBorrowed - positionNotionalWhenReturned =
            // openNotional - positionNotional = unrealizedPnlForLongPosition * -1
            unrealizedPnl = isShortPosition
                ? MixedDecimal.fromDecimal(position.openNotional).subD(positionNotional)
                : MixedDecimal.fromDecimal(positionNotional).subD(position.openNotional);
        }
    }

    /**
     * @notice get latest cumulative premium fraction.
     * @param _amm IAmm address
     * @return latest cumulative premium fraction in 18 digits
     */
    function getLatestCumulativePremiumFraction(IAmm _amm) public view returns (SignedDecimal.signedDecimal memory) {
        uint256 len = ammMap[address(_amm)].cumulativePremiumFractions.length;
        if (len > 0) {
            return ammMap[address(_amm)].cumulativePremiumFractions[len - 1];
        }
    }

    //
    // INTERNAL FUNCTIONS
    //

    function enterRestrictionMode(IAmm _amm) internal {
        uint256 blockNumber = _blockNumber();
        ammMap[address(_amm)].lastRestrictionBlock = blockNumber;
        emit RestrictionModeEntered(address(_amm), blockNumber);
    }

    function setPosition(
        IAmm _amm,
        address _trader,
        Position memory _position
    ) internal {
        Position storage positionStorage = ammMap[address(_amm)].positionMap[_trader];
        positionStorage.size = _position.size;
        positionStorage.margin = _position.margin;
        positionStorage.openNotional = _position.openNotional;
        positionStorage.lastUpdatedCumulativePremiumFraction = _position.lastUpdatedCumulativePremiumFraction;
        positionStorage.blockNumber = _position.blockNumber;
        positionStorage.liquidityHistoryIndex = _position.liquidityHistoryIndex;
    }

    function clearPosition(IAmm _amm, address _trader) internal {
        // keep the record in order to retain the last updated block number
        ammMap[address(_amm)].positionMap[_trader] = Position({
            size: SignedDecimal.zero(),
            margin: Decimal.zero(),
            openNotional: Decimal.zero(),
            lastUpdatedCumulativePremiumFraction: SignedDecimal.zero(),
            blockNumber: _blockNumber(),
            liquidityHistoryIndex: 0
        });
    }

    // only called from openPosition and closeAndOpenReversePosition. caller need to ensure there's enough marginRatio
    function internalIncreasePosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _openNotional,
        Decimal.decimal memory _minPositionSize,
        Decimal.decimal memory _leverage
    ) internal returns (PositionResp memory positionResp) {
        address trader = _msgSender();
        Position memory oldPosition = getUnadjustedPosition(_amm, trader);
        positionResp.exchangedPositionSize = swapInput(_amm, _side, _openNotional, _minPositionSize, false);
        SignedDecimal.signedDecimal memory newSize = oldPosition.size.addD(positionResp.exchangedPositionSize);
        // if size is 0 (means a new position), set the latest liquidity index
        uint256 liquidityHistoryIndex = oldPosition.liquidityHistoryIndex;
        if (oldPosition.size.toInt() == 0) {
            liquidityHistoryIndex = _amm.getLiquidityHistoryLength().sub(1);
        }

        updateOpenInterestNotional(_amm, MixedDecimal.fromDecimal(_openNotional));
        // if the trader is not in the whitelist, check max position size
        if (trader != whitelist) {
            Decimal.decimal memory maxHoldingBaseAsset = _amm.getMaxHoldingBaseAsset();
            if (maxHoldingBaseAsset.toUint() > 0) {
                // total position size should be less than `positionUpperBound`
                require(newSize.abs().cmp(maxHoldingBaseAsset) <= 0);
            }
        }

        SignedDecimal.signedDecimal memory increaseMarginRequirement =
            MixedDecimal.fromDecimal(_openNotional.divD(_leverage));
        (
            Decimal.decimal memory remainMargin, // the 2nd return (bad debt) must be 0 - already checked from caller
            ,
            SignedDecimal.signedDecimal memory fundingPayment,
            SignedDecimal.signedDecimal memory latestCumulativePremiumFraction
        ) = calcRemainMarginWithFundingPayment(_amm, oldPosition, increaseMarginRequirement);

        (, SignedDecimal.signedDecimal memory unrealizedPnl) =
            getPositionNotionalAndUnrealizedPnl(_amm, trader, PnlCalcOption.SPOT_PRICE);

        // update positionResp
        positionResp.exchangedQuoteAssetAmount = _openNotional;
        positionResp.unrealizedPnlAfter = unrealizedPnl;
        positionResp.marginToVault = increaseMarginRequirement;
        positionResp.fundingPayment = fundingPayment;
        positionResp.position = Position(
            newSize,
            remainMargin,
            oldPosition.openNotional.addD(positionResp.exchangedQuoteAssetAmount),
            latestCumulativePremiumFraction,
            liquidityHistoryIndex,
            _blockNumber()
        );
    }

    function openReversePosition(
        IAmm _amm,
        Side _side,
        address _trader,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit,
        bool _canOverFluctuationLimit
    ) internal returns (PositionResp memory) {
        Decimal.decimal memory openNotional = _quoteAssetAmount.mulD(_leverage);
        (Decimal.decimal memory oldPositionNotional, SignedDecimal.signedDecimal memory unrealizedPnl) =
            getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.SPOT_PRICE);
        PositionResp memory positionResp;

        // reduce position if old position is larger
        if (oldPositionNotional.toUint() > openNotional.toUint()) {
            updateOpenInterestNotional(_amm, MixedDecimal.fromDecimal(openNotional).mulScalar(-1));
            Position memory oldPosition = getUnadjustedPosition(_amm, _trader);
            positionResp.exchangedPositionSize = swapInput(
                _amm,
                _side,
                openNotional,
                _baseAssetAmountLimit,
                _canOverFluctuationLimit
            );

            // realizedPnl = unrealizedPnl * closedRatio
            // closedRatio = positionResp.exchangedPositionSiz / oldPosition.size
            if (oldPosition.size.toInt() != 0) {
                positionResp.realizedPnl = unrealizedPnl.mulD(positionResp.exchangedPositionSize.abs()).divD(
                    oldPosition.size.abs()
                );
            }
            Decimal.decimal memory remainMargin;
            SignedDecimal.signedDecimal memory latestCumulativePremiumFraction;
            (
                remainMargin,
                positionResp.badDebt,
                positionResp.fundingPayment,
                latestCumulativePremiumFraction
            ) = calcRemainMarginWithFundingPayment(_amm, oldPosition, positionResp.realizedPnl);

            // positionResp.unrealizedPnlAfter = unrealizedPnl - realizedPnl
            positionResp.unrealizedPnlAfter = unrealizedPnl.subD(positionResp.realizedPnl);
            positionResp.exchangedQuoteAssetAmount = openNotional;

            // calculate openNotional (it's different depends on long or short side)
            // long: unrealizedPnl = positionNotional - openNotional => openNotional = positionNotional - unrealizedPnl
            // short: unrealizedPnl = openNotional - positionNotional => openNotional = positionNotional + unrealizedPnl
            // positionNotional = oldPositionNotional - exchangedQuoteAssetAmount
            SignedDecimal.signedDecimal memory remainOpenNotional =
                oldPosition.size.toInt() > 0
                    ? MixedDecimal.fromDecimal(oldPositionNotional).subD(positionResp.exchangedQuoteAssetAmount).subD(
                        positionResp.unrealizedPnlAfter
                    )
                    : positionResp.unrealizedPnlAfter.addD(oldPositionNotional).subD(
                        positionResp.exchangedQuoteAssetAmount
                    );
            require(remainOpenNotional.toInt() > 0, "value of openNotional <= 0");

            positionResp.position = Position(
                oldPosition.size.addD(positionResp.exchangedPositionSize),
                remainMargin,
                remainOpenNotional.abs(),
                latestCumulativePremiumFraction,
                oldPosition.liquidityHistoryIndex,
                _blockNumber()
            );
            return positionResp;
        }

        return closeAndOpenReversePosition(_amm, _side, _trader, _quoteAssetAmount, _leverage, _baseAssetAmountLimit);
    }

    function closeAndOpenReversePosition(
        IAmm _amm,
        Side _side,
        address _trader,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _baseAssetAmountLimit
    ) internal returns (PositionResp memory positionResp) {
        // new position size is larger than or equal to the old position size
        // so either close or close then open a larger position
        PositionResp memory closePositionResp = internalClosePosition(_amm, _trader, Decimal.zero());

        // the old position is underwater. trader should close a position first
        require(closePositionResp.badDebt.toUint() == 0);

        // update open notional after closing position
        Decimal.decimal memory openNotional =
            _quoteAssetAmount.mulD(_leverage).subD(closePositionResp.exchangedQuoteAssetAmount);

        // if remain exchangedQuoteAssetAmount is too small (eg. 1wei) then the required margin might be 0
        // then the clearingHouse will stop opening position
        if (openNotional.divD(_leverage).toUint() == 0) {
            positionResp = closePositionResp;
        } else {
            Decimal.decimal memory updatedBaseAssetAmountLimit;
            if (_baseAssetAmountLimit.toUint() > closePositionResp.exchangedPositionSize.toUint()) {
                updatedBaseAssetAmountLimit = _baseAssetAmountLimit.subD(closePositionResp.exchangedPositionSize.abs());
            }

            PositionResp memory increasePositionResp =
                internalIncreasePosition(_amm, _side, openNotional, updatedBaseAssetAmountLimit, _leverage);
            positionResp = PositionResp({
                position: increasePositionResp.position,
                exchangedQuoteAssetAmount: closePositionResp.exchangedQuoteAssetAmount.addD(
                    increasePositionResp.exchangedQuoteAssetAmount
                ),
                badDebt: closePositionResp.badDebt.addD(increasePositionResp.badDebt),
                fundingPayment: closePositionResp.fundingPayment.addD(increasePositionResp.fundingPayment),
                exchangedPositionSize: closePositionResp.exchangedPositionSize.addD(
                    increasePositionResp.exchangedPositionSize
                ),
                realizedPnl: closePositionResp.realizedPnl.addD(increasePositionResp.realizedPnl),
                unrealizedPnlAfter: SignedDecimal.zero(),
                marginToVault: closePositionResp.marginToVault.addD(increasePositionResp.marginToVault)
            });
        }
        return positionResp;
    }

    function internalClosePosition(
        IAmm _amm,
        address _trader,
        Decimal.decimal memory _quoteAssetAmountLimit
    ) private returns (PositionResp memory positionResp) {
        // check conditions
        Position memory oldPosition = getUnadjustedPosition(_amm, _trader);
        requirePositionSize(oldPosition.size);

        (, SignedDecimal.signedDecimal memory unrealizedPnl) =
            getPositionNotionalAndUnrealizedPnl(_amm, _trader, PnlCalcOption.SPOT_PRICE);
        (
            Decimal.decimal memory remainMargin,
            Decimal.decimal memory badDebt,
            SignedDecimal.signedDecimal memory fundingPayment,

        ) = calcRemainMarginWithFundingPayment(_amm, oldPosition, unrealizedPnl);

        positionResp.exchangedPositionSize = oldPosition.size.mulScalar(-1);
        positionResp.realizedPnl = unrealizedPnl;
        positionResp.badDebt = badDebt;
        positionResp.fundingPayment = fundingPayment;
        positionResp.marginToVault = MixedDecimal.fromDecimal(remainMargin).mulScalar(-1);
        // for amm.swapOutput, the direction is in base asset, from the perspective of Amm
        positionResp.exchangedQuoteAssetAmount = _amm.swapOutput(
            oldPosition.size.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
            oldPosition.size.abs(),
            _quoteAssetAmountLimit
        );

        // bankrupt position's bad debt will be also consider as a part of the open interest
        updateOpenInterestNotional(_amm, unrealizedPnl.addD(badDebt).addD(oldPosition.openNotional).mulScalar(-1));
        clearPosition(_amm, _trader);
    }

    function swapInput(
        IAmm _amm,
        Side _side,
        Decimal.decimal memory _inputAmount,
        Decimal.decimal memory _minOutputAmount,
        bool _canOverFluctuationLimit
    ) internal returns (SignedDecimal.signedDecimal memory) {
        // for amm.swapInput, the direction is in quote asset, from the perspective of Amm
        IAmm.Dir dir = (_side == Side.BUY) ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM;
        SignedDecimal.signedDecimal memory outputAmount =
            MixedDecimal.fromDecimal(_amm.swapInput(dir, _inputAmount, _minOutputAmount, _canOverFluctuationLimit));
        if (IAmm.Dir.REMOVE_FROM_AMM == dir) {
            return outputAmount.mulScalar(-1);
        }
        return outputAmount;
    }

    function transferFee(
        address _from,
        IAmm _amm,
        Decimal.decimal memory _positionNotional
    ) internal returns (Decimal.decimal memory) {
        (Decimal.decimal memory toll, Decimal.decimal memory spread) = _amm.calcFee(_positionNotional);
        bool hasToll = toll.toUint() > 0;
        bool hasSpread = spread.toUint() > 0;
        if (hasToll || hasSpread) {
            IERC20 quoteAsset = _amm.quoteAsset();

            // transfer spread to insurance fund
            if (hasSpread) {
                _transferFrom(quoteAsset, _from, address(insuranceFund), spread);
            }

            // transfer toll to feePool
            if (hasToll) {
                require(address(feePool) != address(0));
                _transferFrom(quoteAsset, _from, address(feePool), toll);
            }

            // fee = spread + toll
            return toll.addD(spread);
        }
    }

    function withdraw(
        IERC20 _token,
        address _receiver,
        Decimal.decimal memory _amount
    ) internal {
        // if withdraw amount is larger than entire balance of vault
        // means this trader's profit comes from other under collateral position's future loss
        // and the balance of entire vault is not enough
        // need money from IInsuranceFund to pay first, and record this prepaidBadDebt
        // in this case, insurance fund loss must be zero
        Decimal.decimal memory totalTokenBalance = _balanceOf(_token, address(this));
        if (totalTokenBalance.toUint() < _amount.toUint()) {
            Decimal.decimal memory balanceShortage = _amount.subD(totalTokenBalance);
            prepaidBadDebt[address(_token)] = prepaidBadDebt[address(_token)].addD(balanceShortage);
            insuranceFund.withdraw(_token, balanceShortage);
        }

        _transfer(_token, _receiver, _amount);
    }

    function realizeBadDebt(IERC20 _token, Decimal.decimal memory _badDebt) internal {
        Decimal.decimal memory badDebtBalance = prepaidBadDebt[address(_token)];
        if (badDebtBalance.toUint() > _badDebt.toUint()) {
            // no need to move extra tokens because vault already prepay bad debt, only need to update the numbers
            prepaidBadDebt[address(_token)] = badDebtBalance.subD(_badDebt);
        } else {
            // in order to realize all the bad debt vault need extra tokens from insuranceFund
            insuranceFund.withdraw(_token, _badDebt.subD(badDebtBalance));
            prepaidBadDebt[address(_token)] = Decimal.zero();
        }
    }

    function transferToInsuranceFund(IERC20 _token, Decimal.decimal memory _amount) internal {
        Decimal.decimal memory totalTokenBalance = _balanceOf(_token, address(this));
        _transfer(
            _token,
            address(insuranceFund),
            totalTokenBalance.toUint() < _amount.toUint() ? totalTokenBalance : _amount
        );
    }

    /**
     * @dev assume this will be removes soon once the guarded period has ended. caller need to ensure amm exist
     */
    function updateOpenInterestNotional(IAmm _amm, SignedDecimal.signedDecimal memory _amount) internal {
        // when cap = 0 means no cap
        uint256 cap = _amm.getOpenInterestNotionalCap().toUint();
        address ammAddr = address(_amm);
        if (cap > 0) {
            SignedDecimal.signedDecimal memory updatedOpenInterestNotional =
                _amount.addD(openInterestNotionalMap[ammAddr]);
            // the reduced open interest can be larger than total when profit is too high and other position are bankrupt
            if (updatedOpenInterestNotional.toInt() < 0) {
                updatedOpenInterestNotional = SignedDecimal.zero();
            }
            if (_amount.toInt() > 0) {
                // whitelist won't be restrict by open interest cap
                require(updatedOpenInterestNotional.toUint() <= cap || _msgSender() == whitelist);
            }
            openInterestNotionalMap[ammAddr] = updatedOpenInterestNotional.abs();
        }
    }

    //
    // INTERNAL VIEW FUNCTIONS
    //

    function adjustPositionForLiquidityChanged(IAmm _amm, address _trader) internal returns (Position memory) {
        Position memory unadjustedPosition = getUnadjustedPosition(_amm, _trader);
        if (unadjustedPosition.size.toInt() == 0) {
            return unadjustedPosition;
        }
        uint256 latestLiquidityIndex = _amm.getLiquidityHistoryLength().sub(1);
        if (unadjustedPosition.liquidityHistoryIndex == latestLiquidityIndex) {
            return unadjustedPosition;
        }

        Position memory adjustedPosition =
            calcPositionAfterLiquidityMigration(_amm, unadjustedPosition, latestLiquidityIndex);
        setPosition(_amm, _trader, adjustedPosition);
        emit PositionAdjusted(
            address(_amm),
            _trader,
            adjustedPosition.size.toInt(),
            unadjustedPosition.liquidityHistoryIndex,
            adjustedPosition.liquidityHistoryIndex
        );
        return adjustedPosition;
    }

    function calcPositionAfterLiquidityMigration(
        IAmm _amm,
        Position memory _position,
        uint256 _latestLiquidityIndex
    ) internal view returns (Position memory) {
        if (_position.size.toInt() == 0) {
            _position.liquidityHistoryIndex = _latestLiquidityIndex;
            return _position;
        }
        // get the change in Amm notional value
        // notionalDelta = current cumulative notional - cumulative notional of last snapshot
        IAmm.LiquidityChangedSnapshot memory lastSnapshot =
            _amm.getLiquidityChangedSnapshots(_position.liquidityHistoryIndex);
        SignedDecimal.signedDecimal memory notionalDelta =
            _amm.getCumulativeNotional().subD(lastSnapshot.cumulativeNotional);
        // update the old curve's reserve
        // by applying notionalDelta to the old curve
        Decimal.decimal memory updatedOldBaseReserve;
        Decimal.decimal memory updatedOldQuoteReserve;
        if (notionalDelta.toInt() != 0) {
            Decimal.decimal memory baseAssetWorth =
                _amm.getInputPriceWithReserves(
                    notionalDelta.toInt() > 0 ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
                    notionalDelta.abs(),
                    lastSnapshot.quoteAssetReserve,
                    lastSnapshot.baseAssetReserve
                );
            updatedOldQuoteReserve = notionalDelta.addD(lastSnapshot.quoteAssetReserve).abs();
            if (notionalDelta.toInt() > 0) {
                updatedOldBaseReserve = lastSnapshot.baseAssetReserve.subD(baseAssetWorth);
            } else {
                updatedOldBaseReserve = lastSnapshot.baseAssetReserve.addD(baseAssetWorth);
            }
        } else {
            updatedOldQuoteReserve = lastSnapshot.quoteAssetReserve;
            updatedOldBaseReserve = lastSnapshot.baseAssetReserve;
        }
        // calculate the new position size
        _position.size = _amm.calcBaseAssetAfterLiquidityMigration(
            _position.size,
            updatedOldQuoteReserve,
            updatedOldBaseReserve
        );
        _position.liquidityHistoryIndex = _latestLiquidityIndex;
        return _position;
    }

    function calcRemainMarginWithFundingPayment(
        IAmm _amm,
        Position memory _oldPosition,
        SignedDecimal.signedDecimal memory _marginDelta
    )
        private
        view
        returns (
            Decimal.decimal memory remainMargin,
            Decimal.decimal memory badDebt,
            SignedDecimal.signedDecimal memory fundingPayment,
            SignedDecimal.signedDecimal memory latestCumulativePremiumFraction
        )
    {
        // calculate funding payment
        latestCumulativePremiumFraction = getLatestCumulativePremiumFraction(_amm);
        if (_oldPosition.size.toInt() != 0) {
            fundingPayment = latestCumulativePremiumFraction
                .subD(_oldPosition.lastUpdatedCumulativePremiumFraction)
                .mulD(_oldPosition.size);
        }

        // calculate remain margin
        SignedDecimal.signedDecimal memory signedRemainMargin =
            _marginDelta.subD(fundingPayment).addD(_oldPosition.margin);

        // if remain margin is negative, set to zero and leave the rest to bad debt
        if (signedRemainMargin.toInt() < 0) {
            badDebt = signedRemainMargin.abs();
        } else {
            remainMargin = signedRemainMargin.abs();
        }
    }

    function getUnadjustedPosition(IAmm _amm, address _trader) public view returns (Position memory position) {
        position = ammMap[address(_amm)].positionMap[_trader];
    }

    //
    // REQUIRE FUNCTIONS
    //
    function requireAmm(IAmm _amm, bool _open) private view {
        require(insuranceFund.isExistedAmm(_amm));
        require(_open == _amm.open(), _open ? "amm was closed" : "amm is open");
    }

    function requireNonZeroInput(Decimal.decimal memory _decimal) private pure {
        require(_decimal.toUint() != 0);
    }

    function requirePositionSize(SignedDecimal.signedDecimal memory _size) private pure {
        require(_size.toInt() != 0);
    }

    function requireNotRestrictionMode(IAmm _amm) private view {
        uint256 currentBlock = _blockNumber();
        if (currentBlock == ammMap[address(_amm)].lastRestrictionBlock) {
            require(getUnadjustedPosition(_amm, _msgSender()).blockNumber != currentBlock);
        }
    }

    function requireMoreMarginRatio(
        SignedDecimal.signedDecimal memory _marginRatio,
        Decimal.decimal memory _baseMarginRatio,
        bool _largerThanOrEqualTo
    ) private pure {
        int256 remainingMarginRatio = _marginRatio.subD(_baseMarginRatio).toInt();
        require(_largerThanOrEqualTo ? remainingMarginRatio >= 0 : remainingMarginRatio < 0);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { Decimal } from "./Decimal.sol";

abstract contract DecimalERC20 {
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;

    mapping(address => uint256) private decimalMap;

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // INTERNAL functions
    //

    // CAUTION: do not input _from == _to s.t. this function will always fail
    function _transfer(
        IERC20 _token,
        address _to,
        Decimal.decimal memory _value
    ) internal {
        _updateDecimal(address(_token));
        Decimal.decimal memory balanceBefore = _balanceOf(_token, _to);
        uint256 roundedDownValue = _toUint(_token, _value);

        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory data) =
            address(_token).call(abi.encodeWithSelector(_token.transfer.selector, _to, roundedDownValue));

        require(success && (data.length == 0 || abi.decode(data, (bool))), "DecimalERC20: transfer failed");
        _validateBalance(_token, _to, roundedDownValue, balanceBefore);
    }

    function _transferFrom(
        IERC20 _token,
        address _from,
        address _to,
        Decimal.decimal memory _value
    ) internal {
        _updateDecimal(address(_token));
        Decimal.decimal memory balanceBefore = _balanceOf(_token, _to);
        uint256 roundedDownValue = _toUint(_token, _value);

        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory data) =
            address(_token).call(abi.encodeWithSelector(_token.transferFrom.selector, _from, _to, roundedDownValue));

        require(success && (data.length == 0 || abi.decode(data, (bool))), "DecimalERC20: transferFrom failed");
        _validateBalance(_token, _to, roundedDownValue, balanceBefore);
    }

    function _approve(
        IERC20 _token,
        address _spender,
        Decimal.decimal memory _value
    ) internal {
        _updateDecimal(address(_token));
        // to be compatible with some erc20 tokens like USDT
        __approve(_token, _spender, Decimal.zero());
        __approve(_token, _spender, _value);
    }

    //
    // VIEW
    //
    function _allowance(
        IERC20 _token,
        address _owner,
        address _spender
    ) internal view returns (Decimal.decimal memory) {
        return _toDecimal(_token, _token.allowance(_owner, _spender));
    }

    function _balanceOf(IERC20 _token, address _owner) internal view returns (Decimal.decimal memory) {
        return _toDecimal(_token, _token.balanceOf(_owner));
    }

    function _totalSupply(IERC20 _token) internal view returns (Decimal.decimal memory) {
        return _toDecimal(_token, _token.totalSupply());
    }

    function _toDecimal(IERC20 _token, uint256 _number) internal view returns (Decimal.decimal memory) {
        uint256 tokenDecimals = _getTokenDecimals(address(_token));
        if (tokenDecimals >= 18) {
            return Decimal.decimal(_number.div(10**(tokenDecimals.sub(18))));
        }

        return Decimal.decimal(_number.mul(10**(uint256(18).sub(tokenDecimals))));
    }

    function _toUint(IERC20 _token, Decimal.decimal memory _decimal) internal view returns (uint256) {
        uint256 tokenDecimals = _getTokenDecimals(address(_token));
        if (tokenDecimals >= 18) {
            return _decimal.toUint().mul(10**(tokenDecimals.sub(18)));
        }
        return _decimal.toUint().div(10**(uint256(18).sub(tokenDecimals)));
    }

    function _getTokenDecimals(address _token) internal view returns (uint256) {
        uint256 tokenDecimals = decimalMap[_token];
        if (tokenDecimals == 0) {
            (bool success, bytes memory data) = _token.staticcall(abi.encodeWithSignature("decimals()"));
            require(success && data.length != 0, "DecimalERC20: get decimals failed");
            tokenDecimals = abi.decode(data, (uint256));
        }
        return tokenDecimals;
    }

    //
    // PRIVATE
    //
    function _updateDecimal(address _token) private {
        uint256 tokenDecimals = _getTokenDecimals(_token);
        if (decimalMap[_token] != tokenDecimals) {
            decimalMap[_token] = tokenDecimals;
        }
    }

    function __approve(
        IERC20 _token,
        address _spender,
        Decimal.decimal memory _value
    ) private {
        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory data) =
            address(_token).call(abi.encodeWithSelector(_token.approve.selector, _spender, _toUint(_token, _value)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "DecimalERC20: approve failed");
    }

    // To prevent from deflationary token, check receiver's balance is as expectation.
    function _validateBalance(
        IERC20 _token,
        address _to,
        uint256 _roundedDownValue,
        Decimal.decimal memory _balanceBefore
    ) private view {
        require(
            _balanceOf(_token, _to).cmp(_balanceBefore.addD(_toDecimal(_token, _roundedDownValue))) == 0,
            "DecimalERC20: balance inconsistent"
        );
    }
}

pragma solidity ^0.6.0;
import "../Initializable.sol";

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
contract ReentrancyGuardUpgradeSafe is Initializable {
    bool private _notEntered;


    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {


        // Storing an initial non-zero value makes deployment a bit more
        // expensive, but in exchange the refund on every call to nonReentrant
        // will be lower in amount. Since refunds are capped to a percetange of
        // the total transaction's gas, it is best to keep them low in cases
        // like this one, to increase the likelihood of the full refund coming
        // into effect.
        _notEntered = true;

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
        require(_notEntered, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _notEntered = false;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _notEntered = true;
    }

    uint256[49] private __gap;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { PausableUpgradeSafe } from "@openzeppelin/contracts-ethereum-package/contracts/utils/Pausable.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";

contract OwnerPausableUpgradeSafe is PerpFiOwnableUpgrade, PausableUpgradeSafe {
    // solhint-disable func-name-mixedcase
    function __OwnerPausable_init() internal initializer {
        __Ownable_init();
        __Pausable_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    uint256[50] private __gap;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "../utils/Decimal.sol";
import { IAmm } from "./IAmm.sol";

interface IInsuranceFund {
    function withdraw(IERC20 _quoteToken, Decimal.decimal calldata _amount) external;

    function isExistedAmm(IAmm _amm) external view returns (bool);

    function getAllAmms() external view returns (IAmm[] memory);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "../utils/Decimal.sol";

interface IMultiTokenRewardRecipient {
    function notifyTokenAmount(IERC20 _token, Decimal.decimal calldata _amount) external;
}

pragma solidity ^0.6.0;

import "../GSN/Context.sol";
import "../Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
contract PausableUpgradeSafe is Initializable, ContextUpgradeSafe {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */

    function __Pausable_init() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal initializer {


        _paused = false;

    }


    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }

    uint256[49] private __gap;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "../utils/Decimal.sol";
import { PerpFiOwnableUpgrade } from "../utils/PerpFiOwnableUpgrade.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";
import { AddressArray } from "../utils/AddressArray.sol";
import { IRewardRecipient } from "../interface/IRewardRecipient.sol";

contract FeeTokenPoolDispatcherL1 is PerpFiOwnableUpgrade, DecimalERC20 {
    using AddressArray for address[];

    uint256 public constant TOKEN_AMOUNT_LIMIT = 20;
    //
    // EVENTS
    //
    event FeeRewardPoolAdded(address token, address feeRewardPool);
    event FeeRewardPoolRemoved(address token, address feeRewardPool);
    event FeeTransferred(address token, address feeRewardPool, uint256 amount);

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//

    mapping(IERC20 => IRewardRecipient) public feeRewardPoolMap;
    address[] public feeTokens;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize() external initializer {
        __Ownable_init();
    }

    function transferToFeeRewardPool() public {
        require(feeTokens.length != 0, "feeTokens not set yet");

        bool hasFee;
        for (uint256 i; i < feeTokens.length; i++) {
            hasFee = transferToPool(IERC20(feeTokens[i])) || hasFee;
        }
        // revert if the fee of all tokens is zero
        require(hasFee, "fee is now zero");
    }

    function addFeeRewardPool(IRewardRecipient _recipient) external onlyOwner {
        require(feeTokens.length < TOKEN_AMOUNT_LIMIT, "exceed token amount limit");

        IERC20 token = _recipient.token();
        require(feeTokens.add(address(token)), "invalid input");

        feeRewardPoolMap[token] = _recipient;
        emit FeeRewardPoolAdded(address(token), address(_recipient));
    }

    function removeFeeRewardPool(IRewardRecipient _recipient) external onlyOwner {
        require(address(_recipient) != address(0), "invalid input");

        IERC20 token = _recipient.token();
        address removedAddr = feeTokens.remove(address(token));
        require(removedAddr != address(0), "token does not exist");
        require(removedAddr == address(token), "remove wrong token");

        if (token.balanceOf(address(this)) > 0) {
            transferToPool(token);
        }
        IRewardRecipient feeRewardPool = feeRewardPoolMap[token];
        delete feeRewardPoolMap[token];
        emit FeeRewardPoolRemoved(address(token), address(feeRewardPool));
    }

    //
    // VIEW FUNCTIONS
    //
    function isFeeTokenExisted(IERC20 _token) public view returns (bool) {
        return feeTokens.isExisted(address(_token));
    }

    function getFeeTokenLength() external view returns (uint256) {
        return feeTokens.length;
    }

    //
    // INTERNAL FUNCTIONS
    //
    function transferToPool(IERC20 _token) private returns (bool) {
        Decimal.decimal memory balance = _balanceOf(_token, address(this));

        if (balance.toUint() != 0) {
            IRewardRecipient feeRewardPool = feeRewardPoolMap[_token];
            _transfer(_token, address(feeRewardPool), balance);
            feeRewardPool.notifyRewardAmount(balance);

            emit FeeTransferred(address(_token), address(feeRewardPool), balance.toUint());
            return true;
        }

        return false;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

library AddressArray {
    function add(address[] storage addrArray, address addr) internal returns (bool) {
        if (addr == address(0) || isExisted(addrArray, addr)) {
            return false;
        }
        addrArray.push(addr);
        return true;
    }

    function remove(address[] storage addrArray, address addr) internal returns (address) {
        if (addr == address(0)) {
            return address(0);
        }

        uint256 lengthOfArray = addrArray.length;
        for (uint256 i; i < lengthOfArray; i++) {
            if (addr == addrArray[i]) {
                if (i != lengthOfArray - 1) {
                    addrArray[i] = addrArray[lengthOfArray - 1];
                }
                addrArray.pop();
                return addr;
            }
        }
        return address(0);
    }

    function isExisted(address[] memory addrArray, address addr) internal pure returns (bool) {
        for (uint256 i; i < addrArray.length; i++) {
            if (addr == addrArray[i]) return true;
        }
        return false;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { Decimal } from "../utils/Decimal.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

interface IRewardRecipient {
    function notifyRewardAmount(Decimal.decimal calldata _amount) external;

    function token() external returns (IERC20);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { IRewardRecipient } from "./interface/IRewardRecipient.sol";
import { Decimal } from "./utils/Decimal.sol";

abstract contract RewardsDistributionRecipient is PerpFiOwnableUpgrade, IRewardRecipient {
    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//
    address public rewardsDistribution;
    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function notifyRewardAmount(Decimal.decimal calldata _amount) external virtual override;

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }

    modifier onlyRewardsDistribution() {
        require(rewardsDistribution == _msgSender(), "only rewardsDistribution");
        _;
    }
}

// source: https://github.com/balancer-labs/erc20-redeemable/blob/master/merkle/contracts/MerkleRedeem.sol
// changes:
// 1. add license and update solidity version to 0.6.9
// 2. make it upgradeable
// 3. add virtual modifier in claim functions

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { MerkleProof } from "@openzeppelin/contracts-ethereum-package/contracts/cryptography/MerkleProof.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { PerpFiOwnableUpgrade } from "../../utils/PerpFiOwnableUpgrade.sol";

contract MerkleRedeemUpgradeSafe is PerpFiOwnableUpgrade {
    event Claimed(address _claimant, uint256 _balance);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//
    // Recorded weeks
    mapping(uint256 => bytes32) public weekMerkleRoots;
    mapping(uint256 => mapping(address => bool)) public claimed;

    IERC20 public token;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function __MerkleRedeem_init(IERC20 _token) internal initializer {
        __Ownable_init();
        __MerkleRedeem_init_unchained(_token);
    }

    function __MerkleRedeem_init_unchained(IERC20 _token) internal initializer {
        token = _token;
    }

    function disburse(address _liquidityProvider, uint256 _balance) private {
        if (_balance > 0) {
            emit Claimed(_liquidityProvider, _balance);
            require(token.transfer(_liquidityProvider, _balance), "ERR_TRANSFER_FAILED");
        }
    }

    function claimWeek(
        address _liquidityProvider,
        uint256 _week,
        uint256 _claimedBalance,
        bytes32[] memory _merkleProof
    ) public virtual {
        require(!claimed[_week][_liquidityProvider], "Claimed already");
        require(verifyClaim(_liquidityProvider, _week, _claimedBalance, _merkleProof), "Incorrect merkle proof");

        claimed[_week][_liquidityProvider] = true;
        disburse(_liquidityProvider, _claimedBalance);
    }

    struct Claim {
        uint256 week;
        uint256 balance;
        bytes32[] merkleProof;
    }

    function claimWeeks(address _liquidityProvider, Claim[] memory claims) public virtual {
        uint256 totalBalance = 0;
        Claim memory claim;
        for (uint256 i = 0; i < claims.length; i++) {
            claim = claims[i];

            require(!claimed[claim.week][_liquidityProvider], "Claimed already");
            require(
                verifyClaim(_liquidityProvider, claim.week, claim.balance, claim.merkleProof),
                "Incorrect merkle proof"
            );

            totalBalance += claim.balance;
            claimed[claim.week][_liquidityProvider] = true;
        }
        disburse(_liquidityProvider, totalBalance);
    }

    function claimStatus(
        address _liquidityProvider,
        uint256 _begin,
        uint256 _end
    ) external view returns (bool[] memory) {
        uint256 size = 1 + _end - _begin;
        bool[] memory arr = new bool[](size);
        for (uint256 i = 0; i < size; i++) {
            arr[i] = claimed[_begin + i][_liquidityProvider];
        }
        return arr;
    }

    function merkleRoots(uint256 _begin, uint256 _end) external view returns (bytes32[] memory) {
        uint256 size = 1 + _end - _begin;
        bytes32[] memory arr = new bytes32[](size);
        for (uint256 i = 0; i < size; i++) {
            arr[i] = weekMerkleRoots[_begin + i];
        }
        return arr;
    }

    function verifyClaim(
        address _liquidityProvider,
        uint256 _week,
        uint256 _claimedBalance,
        bytes32[] memory _merkleProof
    ) public view virtual returns (bool valid) {
        bytes32 leaf = keccak256(abi.encodePacked(_liquidityProvider, _claimedBalance));
        return MerkleProof.verify(_merkleProof, weekMerkleRoots[_week], leaf);
    }

    function seedAllocations(
        uint256 _week,
        bytes32 _merkleRoot,
        uint256 _totalAllocation
    ) public virtual {
        require(weekMerkleRoots[_week] == bytes32(0), "cannot rewrite merkle root");
        weekMerkleRoots[_week] = _merkleRoot;

        require(token.transferFrom(msg.sender, address(this), _totalAllocation), "ERR_TRANSFER_FAILED");
    }
}

pragma solidity ^0.6.0;

/**
 * @dev These functions deal with verification of Merkle trees (hash trees),
 */
library MerkleProof {
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import {
    ReentrancyGuardUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import { Decimal, SafeMath } from "./utils/Decimal.sol";
import { SignedDecimal, MixedDecimal } from "./utils/MixedDecimal.sol";
import { RewardsDistributionRecipient } from "./RewardsDistributionRecipient.sol";
import { DecimalERC20 } from "./utils/DecimalERC20.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { SupplySchedule } from "./SupplySchedule.sol";
import { IMultiTokenRewardRecipient } from "./interface/IMultiTokenRewardRecipient.sol";

contract StakingReserve is
    RewardsDistributionRecipient,
    IMultiTokenRewardRecipient,
    DecimalERC20,
    BlockContext,
    ReentrancyGuardUpgradeSafe
{
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    //
    // EVENTS
    //
    event RewardWithdrawn(address staker, uint256 amount);
    event FeeInEpoch(address token, uint256 fee, uint256 epoch);

    //
    // STRUCT
    //

    // TODO can improve if change to cumulative version
    struct EpochReward {
        Decimal.decimal perpReward;
        // key by Fee ERC20 token address
        mapping(address => Decimal.decimal) feeMap;
    }

    struct StakeBalance {
        bool exist;
        // denominated in perpToken
        Decimal.decimal totalBalance;
        uint256 rewardEpochCursor;
        uint256 feeEpochCursor;
        // key by epochReward index (the starting epoch index when staker stake take effect)
        mapping(uint256 => LockedBalance) lockedBalanceMap;
    }

    struct LockedBalance {
        bool exist;
        // locked staking amount
        Decimal.decimal locked;
        // timeWeightedLocked = locked * (how long has it been until endOfThisEpoch / epochPeriod)
        Decimal.decimal timeWeightedLocked;
    }

    struct FeeBalance {
        address token;
        Decimal.decimal balance;
    }

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//
    SignedDecimal.signedDecimal private totalPendingStakeBalance;

    // the unit of vestingPeriod is epoch, by default 52 epochs equals to 1 year
    uint256 public vestingPeriod;

    // key by staker address
    mapping(address => StakeBalance) public stakeBalanceMap;

    // key by epoch index
    mapping(uint256 => Decimal.decimal) private totalEffectiveStakeMap;

    EpochReward[] public epochRewardHistory;

    address[] public stakers;

    address public perpToken;
    SupplySchedule private supplySchedule;

    /* @dev
     * record all the fee tokens (not remove)
     */
    IERC20[] public feeTokens;
    // key by Fee ERC20 token address
    mapping(IERC20 => Decimal.decimal) public feeMap;

    // address who can call `notifyTokenAmount`, it's `clearingHouse` for now.
    address public feeNotifier;

    IERC20 public override token;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function initialize(
        address _perpToken,
        SupplySchedule _supplySchedule,
        address _feeNotifier,
        uint256 _vestingPeriod
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        perpToken = _perpToken;
        supplySchedule = _supplySchedule;
        feeNotifier = _feeNotifier;
        vestingPeriod = _vestingPeriod;
    }

    function setVestingPeriod(uint256 _vestingPeriod) external onlyOwner {
        vestingPeriod = _vestingPeriod;
    }

    /**
     * @dev staker can increase staking any time,
     */
    function stake(Decimal.decimal memory _amount) public {
        require(_amount.toUint() > 0, "Input amount is zero");
        address sender = _msgSender();
        require(_amount.toUint() <= getUnlockedBalance(sender).toUint(), "Stake more than all balance");
        require(supplySchedule.isStarted(), "PERP reward has not started");

        uint256 epochDuration = supplySchedule.mintDuration();
        uint256 afterNextEpochIndex = nextEpochIndex().add(1);
        uint256 nextEndEpochTimestamp = supplySchedule.nextMintTime();

        // ignore this epoch if keeper didn't endEpoch in time
        Decimal.decimal memory timeWeightedLocked;
        if (nextEndEpochTimestamp > _blockTimestamp()) {
            // calculate timeWeightedLocked based on additional staking amount and the remain time during this epoch
            timeWeightedLocked = _amount.mulScalar(nextEndEpochTimestamp.sub(_blockTimestamp())).divScalar(
                epochDuration
            );

            // update stakerBalance for next epoch
            increaseStake(sender, nextEpochIndex(), _amount, timeWeightedLocked);
        }

        // update stakerBalance for next + 1 epoch
        StakeBalance storage balance = stakeBalanceMap[sender];
        if (balance.lockedBalanceMap[afterNextEpochIndex].exist) {
            increaseStake(sender, afterNextEpochIndex, _amount, _amount);
        } else {
            LockedBalance memory currentBalance = balance.lockedBalanceMap[nextEpochIndex()];
            balance.lockedBalanceMap[afterNextEpochIndex] = LockedBalance(
                true,
                currentBalance.locked,
                currentBalance.locked
            );
        }

        // update global stake balance states
        totalEffectiveStakeMap[nextEpochIndex()] = totalEffectiveStakeMap[nextEpochIndex()].addD(timeWeightedLocked);
        totalPendingStakeBalance = totalPendingStakeBalance.addD(_amount).subD(timeWeightedLocked);
    }

    /**
     * @dev staker can decrease staking from stakeBalanceForNextEpoch
     */
    function unstake(Decimal.decimal calldata _amount) external {
        require(_amount.toUint() > 0, "Input amount is zero");
        address sender = _msgSender();
        require(_amount.toUint() <= getUnstakableBalance(sender).toUint(), "Unstake more than locked balance");

        // decrease stake balance for after next epoch
        uint256 afterNextEpochIndex = nextEpochIndex().add(1);
        LockedBalance memory afterNextLockedBalance = getLockedBalance(sender, afterNextEpochIndex);
        stakeBalanceMap[sender].lockedBalanceMap[afterNextEpochIndex] = LockedBalance(
            true,
            afterNextLockedBalance.locked.subD(_amount),
            afterNextLockedBalance.timeWeightedLocked.subD(_amount)
        );

        // update global stake balance states
        totalPendingStakeBalance = totalPendingStakeBalance.subD(_amount);
    }

    function depositAndStake(Decimal.decimal calldata _amount) external nonReentrant() {
        deposit(_msgSender(), _amount);
        stake(_amount);
    }

    function withdraw(Decimal.decimal calldata _amount) external nonReentrant() {
        require(_amount.toUint() != 0, "Input amount is zero");
        address sender = _msgSender();
        require(_amount.toUint() <= getUnlockedBalance(sender).toUint(), "Not enough balance");
        stakeBalanceMap[sender].totalBalance = stakeBalanceMap[sender].totalBalance.subD(_amount);
        _transfer(IERC20(perpToken), sender, _amount);
    }

    /**
     * @dev add epoch reward, update totalEffectiveStakeMap
     */
    function notifyRewardAmount(Decimal.decimal calldata _amount) external override onlyRewardsDistribution {
        // record reward to epochRewardHistory
        Decimal.decimal memory totalBalanceBeforeEndEpoch = getTotalBalance();
        epochRewardHistory.push(EpochReward(_amount));

        // Note this is initialized AFTER a new entry is pushed to epochRewardHistory, hence the minus 1
        uint256 currentEpochIndex = nextEpochIndex().sub(1);
        for (uint256 i; i < feeTokens.length; i++) {
            IERC20 token = feeTokens[i];
            emit FeeInEpoch(address(token), feeMap[token].toUint(), currentEpochIndex);
            epochRewardHistory[currentEpochIndex].feeMap[address(token)] = feeMap[token];
            feeMap[token] = Decimal.zero();
        }

        // update totalEffectiveStakeMap for coming epoch
        SignedDecimal.signedDecimal memory updatedTotalEffectiveStakeBalance =
            totalPendingStakeBalance.addD(totalBalanceBeforeEndEpoch);
        require(updatedTotalEffectiveStakeBalance.toInt() >= 0, "Unstake more than locked balance");
        totalEffectiveStakeMap[(nextEpochIndex())] = updatedTotalEffectiveStakeBalance.abs();
        totalPendingStakeBalance = SignedDecimal.zero();
    }

    function notifyTokenAmount(IERC20 _token, Decimal.decimal calldata _amount) external override {
        require(feeNotifier == _msgSender(), "!feeNotifier");
        require(_amount.toUint() > 0, "amount can't be 0");

        feeMap[_token] = feeMap[_token].addD(_amount);
        if (!isExistedFeeToken(_token)) {
            feeTokens.push(_token);
        }
    }

    /*
     * claim all fees and vested reward at once
     * update lastUpdatedEffectiveStake
     */
    function claimFeesAndVestedReward() external nonReentrant() {
        // calculate fee and reward
        address staker = _msgSender();
        Decimal.decimal memory reward = getVestedReward(staker);
        FeeBalance[] memory fees = getFeeRevenue(staker);
        bool hasFees = fees.length > 0;
        bool hasReward = reward.toUint() > 0;
        require(hasReward || hasFees, "no vested reward or fee");

        // transfer fee reward
        stakeBalanceMap[staker].feeEpochCursor = epochRewardHistory.length;
        for (uint256 i = 0; i < fees.length; i++) {
            if (fees[i].balance.toUint() != 0) {
                _transfer(IERC20(fees[i].token), staker, fees[i].balance);
            }
        }

        // transfer perp reward
        if (hasReward && epochRewardHistory.length >= vestingPeriod) {
            // solhint-disable reentrancy
            stakeBalanceMap[staker].rewardEpochCursor = epochRewardHistory.length.sub(vestingPeriod);
            _transfer(IERC20(perpToken), staker, reward);
            emit RewardWithdrawn(staker, reward.toUint());
        }
    }

    function setFeeNotifier(address _notifier) external onlyOwner {
        feeNotifier = _notifier;
    }

    //
    // VIEW FUNCTIONS
    //

    function isExistedFeeToken(IERC20 _token) public view returns (bool) {
        for (uint256 i = 0; i < feeTokens.length; i++) {
            if (feeTokens[i] == _token) {
                return true;
            }
        }
        return false;
    }

    function nextEpochIndex() public view returns (uint256) {
        return epochRewardHistory.length;
    }

    /**
     * everyone can query total balance to check current collateralization ratio.
     * TotalBalance of time weighted locked PERP for coming epoch
     */
    function getTotalBalance() public view returns (Decimal.decimal memory) {
        return totalEffectiveStakeMap[nextEpochIndex()];
    }

    function getTotalEffectiveStake(uint256 _epochIndex) public view returns (Decimal.decimal memory) {
        return totalEffectiveStakeMap[_epochIndex];
    }

    function getFeeOfEpoch(uint256 _epoch, address _token) public view returns (Decimal.decimal memory) {
        return epochRewardHistory[_epoch].feeMap[_token];
    }

    function getFeeRevenue(address _staker) public view returns (FeeBalance[] memory feeBalance) {
        StakeBalance storage balance = stakeBalanceMap[_staker];
        if (balance.feeEpochCursor == nextEpochIndex()) {
            return feeBalance;
        }

        uint256 numberOfTokens = feeTokens.length;
        feeBalance = new FeeBalance[](numberOfTokens);
        Decimal.decimal memory latestLockedStake;
        // TODO enhancement, we can loop feeTokens first to save more gas if some feeToken was not used
        for (uint256 i = balance.feeEpochCursor; i < nextEpochIndex(); i++) {
            if (balance.lockedBalanceMap[i].timeWeightedLocked.toUint() != 0) {
                latestLockedStake = balance.lockedBalanceMap[i].timeWeightedLocked;
            }
            if (latestLockedStake.toUint() == 0) {
                continue;
            }
            Decimal.decimal memory effectiveStakePercentage = latestLockedStake.divD(totalEffectiveStakeMap[i]);

            for (uint256 j = 0; j < numberOfTokens; j++) {
                IERC20 token = feeTokens[j];
                Decimal.decimal memory feeInThisEpoch = getFeeOfEpoch(i, address(token));
                if (feeInThisEpoch.toUint() == 0) {
                    continue;
                }
                feeBalance[j].balance = feeBalance[j].balance.addD(feeInThisEpoch.mulD(effectiveStakePercentage));
                feeBalance[j].token = address(token);
            }
        }
    }

    function getVestedReward(address _staker) public view returns (Decimal.decimal memory reward) {
        if (nextEpochIndex() < vestingPeriod) {
            return Decimal.zero();
        }

        // Note that rewardableEpochEnd is exclusive. The last rewardable epoch index = rewardableEpochEnd - 1
        uint256 rewardableEpochEnd = nextEpochIndex().sub(vestingPeriod);
        StakeBalance storage balance = stakeBalanceMap[_staker];
        if (balance.rewardEpochCursor > rewardableEpochEnd) {
            return Decimal.zero();
        }

        Decimal.decimal memory latestLockedStake;
        for (uint256 i = balance.rewardEpochCursor; i < rewardableEpochEnd; i++) {
            if (balance.lockedBalanceMap[i].timeWeightedLocked.toUint() != 0) {
                latestLockedStake = balance.lockedBalanceMap[i].timeWeightedLocked;
            }
            if (latestLockedStake.toUint() == 0) {
                continue;
            }
            Decimal.decimal memory rewardInThisEpoch =
                epochRewardHistory[i].perpReward.mulD(latestLockedStake).divD(totalEffectiveStakeMap[i]);
            reward = reward.addD(rewardInThisEpoch);
        }
    }

    function getUnlockedBalance(address _staker) public view returns (Decimal.decimal memory) {
        Decimal.decimal memory lockedForNextEpoch = getLockedBalance(_staker, nextEpochIndex()).locked;
        return stakeBalanceMap[_staker].totalBalance.subD(lockedForNextEpoch);
    }

    // unstakable = [email protected]+1
    function getUnstakableBalance(address _staker) public view returns (Decimal.decimal memory) {
        return getLockedBalance(_staker, nextEpochIndex().add(1)).locked;
    }

    // only store locked balance when there's changed, so if the target lockedBalance is not exist,
    // use the lockedBalance from the closest previous epoch
    function getLockedBalance(address _staker, uint256 _epochIndex) public view returns (LockedBalance memory) {
        while (_epochIndex >= 0) {
            LockedBalance memory lockedBalance = stakeBalanceMap[_staker].lockedBalanceMap[_epochIndex];
            if (lockedBalance.exist) {
                return lockedBalance;
            }
            if (_epochIndex == 0) {
                break;
            }
            _epochIndex -= 1;
        }
        return LockedBalance(false, Decimal.zero(), Decimal.zero());
    }

    function getEpochRewardHistoryLength() external view returns (uint256) {
        return epochRewardHistory.length;
    }

    function getRewardEpochCursor(address _staker) public view returns (uint256) {
        return stakeBalanceMap[_staker].rewardEpochCursor;
    }

    function getFeeEpochCursor(address _staker) public view returns (uint256) {
        return stakeBalanceMap[_staker].feeEpochCursor;
    }

    //
    // Private
    //

    function increaseStake(
        address _sender,
        uint256 _epochIndex,
        Decimal.decimal memory _locked,
        Decimal.decimal memory _timeWeightedLocked
    ) private {
        LockedBalance memory lockedBalance = getLockedBalance(_sender, _epochIndex);
        stakeBalanceMap[_sender].lockedBalanceMap[_epochIndex] = LockedBalance(
            true,
            lockedBalance.locked.addD(_locked),
            lockedBalance.timeWeightedLocked.addD(_timeWeightedLocked)
        );
    }

    function deposit(address _sender, Decimal.decimal memory _amount) private {
        require(_amount.toUint() != 0, "Input amount is zero");
        StakeBalance storage balance = stakeBalanceMap[_sender];
        if (!balance.exist) {
            stakers.push(_sender);
            balance.exist = true;
            // set rewardEpochCursor for the first staking
            balance.rewardEpochCursor = nextEpochIndex();
        }
        balance.totalBalance = balance.totalBalance.addD(_amount);
        _transferFrom(IERC20(perpToken), _sender, address(this), _amount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { Decimal, SafeMath } from "./utils/Decimal.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { IMinter } from "./interface/IMinter.sol";

contract SupplySchedule is PerpFiOwnableUpgrade, BlockContext {
    using Decimal for Decimal.decimal;
    using SafeMath for uint256;

    //
    // CONSTANTS
    //

    // 4 years is 365 * 4 + 1 = 1,461 days
    // 7 days * 52 weeks * 4 years = 1,456 days. if we add one more week, total days will be 1,463 days.
    // it's over 4 years and closest to 4 years. 209 weeks = 4 * 52 + 1 weeks
    uint256 private constant SUPPLY_DECAY_PERIOD = 209 weeks;

    // Percentage growth of terminal supply per annum
    uint256 private constant TERMINAL_SUPPLY_EPOCH_RATE = 474970697307300; // 2.5% annual ~= 0.04749% weekly

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//
    Decimal.decimal public inflationRate;
    Decimal.decimal public decayRate;

    uint256 public mintDuration; // default is 1 week
    uint256 public nextMintTime;
    uint256 public supplyDecayEndTime; // startSchedule time + 4 years

    IMinter private minter;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function initialize(
        IMinter _minter,
        uint256 _inflationRate,
        uint256 _decayRate,
        uint256 _mintDuration
    ) public initializer {
        __Ownable_init();

        minter = _minter;
        inflationRate = Decimal.decimal(_inflationRate);
        mintDuration = _mintDuration;
        decayRate = Decimal.decimal(_decayRate);
    }

    //
    // PUBLIC FUNCTIONS
    //

    function startSchedule() external onlyOwner {
        require(mintDuration > 0, "mint duration is 0");
        nextMintTime = _blockTimestamp() + mintDuration;
        supplyDecayEndTime = _blockTimestamp().add(SUPPLY_DECAY_PERIOD);
    }

    function setDecayRate(Decimal.decimal memory _decayRate) public onlyOwner {
        decayRate = _decayRate;
    }

    function recordMintEvent() external {
        require(_msgSender() == address(minter), "!minter");
        //@audit - inflationRate will continue to decay even after supplyDecayEndTime, but I guess that should be fine? (@detoo)
        inflationRate = inflationRate.mulD(Decimal.one().subD(decayRate));
        nextMintTime = nextMintTime.add(mintDuration);
    }

    //
    // VIEW functions
    //
    function mintableSupply() external view returns (Decimal.decimal memory) {
        if (!isMintable()) {
            return Decimal.zero();
        }
        uint256 totalSupply = minter.getPerpToken().totalSupply();
        if (_blockTimestamp() >= supplyDecayEndTime) {
            return Decimal.decimal(totalSupply).mulD(Decimal.decimal(TERMINAL_SUPPLY_EPOCH_RATE));
        }
        return Decimal.decimal(totalSupply).mulD(inflationRate);
    }

    function isMintable() public view returns (bool) {
        if (nextMintTime == 0) {
            return false;
        }
        return _blockTimestamp() >= nextMintTime;
    }

    function isStarted() external view returns (bool) {
        return nextMintTime > 0;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "../utils/Decimal.sol";

interface IMinter {
    function mintReward() external;

    function mintForLoss(Decimal.decimal memory _amount) external;

    function getPerpToken() external view returns (IERC20);
}

// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { KeeperRewardBase } from "./KeeperRewardBase.sol";
import { IAmm } from "../interface/IAmm.sol";
import { IClearingHouse } from "../interface/IClearingHouse.sol";

contract KeeperRewardL2 is KeeperRewardBase {
    function initialize(IERC20 _perpToken) external initializer {
        __BaseKeeperReward_init(_perpToken);
    }

    /**
     * @notice call this function to pay funding payment and get token reward
     */
    function payFunding(IAmm _amm) external {
        bytes4 selector = IClearingHouse.payFunding.selector;
        TaskInfo memory task = getTaskInfo(selector);

        IClearingHouse(task.contractAddr).payFunding(_amm);
        postTaskAction(selector);
    }
}

// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { PerpFiOwnableUpgrade } from "../utils/PerpFiOwnableUpgrade.sol";
import { Decimal } from "../utils/Decimal.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";

abstract contract KeeperRewardBase is PerpFiOwnableUpgrade, DecimalERC20 {
    event KeeperCalled(address keeper, bytes4 func, uint256 reward);

    struct TaskInfo {
        address contractAddr;
        Decimal.decimal rewardAmount;
    }

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//

    IERC20 public rewardToken;

    // key by function selector
    mapping(bytes4 => TaskInfo) public tasksMap;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    function __BaseKeeperReward_init(IERC20 _rewardToken) internal initializer {
        __Ownable_init();
        rewardToken = _rewardToken;
    }

    /**
     * @dev set functions those keepers can get reward by call one of them.
            The size of these three array MUST be the same.
     * @param _funcSelectors array of function selectors to be executed
                             format: bytes4(keccak256(abi.encodePacked(address(contract), funcSelector)))
     * @param _contracts array of contract addresses those include corresponding _funcSelectors. 
                         Can be zero to reset corresponding selector.
     * @param _rewardAmount array of reward amount corresponding to different functions 
     */
    function setKeeperFunctions(
        bytes4[] calldata _funcSelectors,
        address[] calldata _contracts,
        uint256[] calldata _rewardAmount
    ) external onlyOwner {
        uint256 selectorLen = _funcSelectors.length;
        require(
            selectorLen == _contracts.length && selectorLen == _rewardAmount.length && selectorLen > 0,
            "inconsistent input size"
        );

        for (uint256 i; i < selectorLen; i++) {
            bytes4 selector = _funcSelectors[i];
            tasksMap[selector].contractAddr = _contracts[i];
            tasksMap[selector].rewardAmount = Decimal.decimal(_rewardAmount[i]);
        }
    }

    //
    // INTERNAL FUNCTIONS
    //

    /**
     * @dev need to check taskInfo is not empty before calling this.
     * @param _selector bytes4(keccak256(abi.encodePacked(address(contract), funcSelector)))
     */
    function postTaskAction(bytes4 _selector) internal {
        TaskInfo memory task = getTaskInfo(_selector);

        address keeper = _msgSender();
        _transfer(rewardToken, keeper, task.rewardAmount);

        emit KeeperCalled(keeper, _selector, task.rewardAmount.toUint());
    }

    /**
     * @dev return TaskInfo with selector as key
     * @param _selector bytes4(keccak256(abi.encodePacked(address(contract), funcSelector)))
     */
    function getTaskInfo(bytes4 _selector) internal view returns (TaskInfo memory task) {
        task = tasksMap[_selector];
        requireNonEmptyAddress(task.contractAddr);
    }

    function requireNonEmptyAddress(address _addr) internal pure {
        require(_addr != address(0), "cannot find contract addr");
    }
}

// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { Decimal } from "../utils/Decimal.sol";
import { SignedDecimal } from "../utils/SignedDecimal.sol";
import { IAmm } from "./IAmm.sol";

interface IClearingHouse {
    enum Side { BUY, SELL }

    /// @notice This struct records personal position information
    /// @param size denominated in amm.baseAsset
    /// @param margin isolated margin
    /// @param openNotional the quoteAsset value of position when opening position. the cost of the position
    /// @param lastUpdatedCumulativePremiumFraction for calculating funding payment, record at the moment every time when trader open/reduce/close position
    /// @param liquidityHistoryIndex
    /// @param blockNumber the block number of the last position
    struct Position {
        SignedDecimal.signedDecimal size;
        Decimal.decimal margin;
        Decimal.decimal openNotional;
        SignedDecimal.signedDecimal lastUpdatedCumulativePremiumFraction;
        uint256 liquidityHistoryIndex;
        uint256 blockNumber;
    }

    function addMargin(IAmm _amm, Decimal.decimal calldata _addedMargin) external;

    function removeMargin(IAmm _amm, Decimal.decimal calldata _removedMargin) external;

    function settlePosition(IAmm _amm) external;

    function openPosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _leverage,
        Decimal.decimal calldata _baseAssetAmountLimit
    ) external;

    function closePosition(IAmm _amm, Decimal.decimal calldata _quoteAssetAmountLimit) external;

    function liquidate(IAmm _amm, address _trader) external;

    function payFunding(IAmm _amm) external;

    // VIEW FUNCTIONS
    function getMarginRatio(IAmm _amm, address _trader) external view returns (SignedDecimal.signedDecimal memory);

    function getPosition(IAmm _amm, address _trader) external view returns (Position memory);
}

// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../../interface/IClearingHouse.sol";

contract ClearingHouseMock is IClearingHouse {
    function addMargin(IAmm _amm, Decimal.decimal calldata _addedMargin) external override {}

    function removeMargin(IAmm _amm, Decimal.decimal calldata _removedMargin) external override {}

    function settlePosition(IAmm _amm) external override {}

    function openPosition(
        IAmm _amm,
        Side _side,
        Decimal.decimal calldata _quoteAssetAmount,
        Decimal.decimal calldata _leverage,
        Decimal.decimal calldata _baseAssetAmountLimit
    ) external override {}

    function closePosition(IAmm _amm, Decimal.decimal calldata _quoteAssetAmountLimit) external override {}

    function liquidate(IAmm _amm, address _trader) external override {}

    event TestEventForPayFunding(address);

    function payFunding(IAmm _amm) external override {
        emit TestEventForPayFunding(address(_amm));
    }

    // VIEW FUNCTIONS
    function getMarginRatio(IAmm _amm, address _trader)
        external
        view
        override
        returns (SignedDecimal.signedDecimal memory)
    {}

    function getPosition(IAmm _amm, address _trader) external view override returns (Position memory) {}
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../utils/SignedDecimal.sol";

contract SignedDecimalFake {
    using SignedDecimal for SignedDecimal.signedDecimal;

    constructor() public {}

    /// @dev multiple two decimals
    function mul(SignedDecimal.signedDecimal memory x, SignedDecimal.signedDecimal memory y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.mulD(y);
    }

    /// @dev multiple a SignedDecimal.signedDecimal by a int256
    function mulScalar(SignedDecimal.signedDecimal memory x, int256 y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.mulScalar(y);
    }

    /// @dev divide two decimals
    function div(SignedDecimal.signedDecimal memory x, SignedDecimal.signedDecimal memory y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.divD(y);
    }

    /// @dev divide a SignedDecimal.signedDecimal by a int256
    function divScalar(SignedDecimal.signedDecimal memory x, int256 y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.divScalar(y);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../../utils/SignedDecimal.sol";
import "../../Amm.sol";

contract AmmMock {
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    event Dir(Amm.Dir dir);

    IERC20 public quoteAsset;
    Decimal.decimal public quoteAssetReserve;
    Decimal.decimal public baseAssetReserve;

    /*
     * For removeMargin mocks
     */
    Decimal.decimal private outputTwap;
    Decimal.decimal private outputPrice;
    Decimal.decimal private inputPrice;

    constructor() public {}

    /*
     * For payFundingRate mocks
     */
    SignedDecimal.signedDecimal private _fundingRate;

    function mockSetFundingRate(SignedDecimal.signedDecimal memory _fr) public {
        _fundingRate = _fr;
    }

    function mockSetQuoteAsset(IERC20 _quoteAsset) public {
        quoteAsset = _quoteAsset;
    }

    function fundingRate() public view returns (SignedDecimal.signedDecimal memory) {
        return _fundingRate;
    }

    function settleFunding() public {}

    function mockSetOutputTwap(Decimal.decimal memory _outputTwap) public {
        outputTwap = _outputTwap;
    }

    function mockSetOutputPrice(Decimal.decimal memory _outputPrice) public {
        outputPrice = _outputPrice;
    }

    function mockSetInputPrice(Decimal.decimal memory _inputPrice) public {
        inputPrice = _inputPrice;
    }

    function getOutputTwap(Amm.Dir, Decimal.decimal calldata) external view returns (Decimal.decimal memory) {
        return outputTwap;
    }

    function getOutputPrice(Amm.Dir, Decimal.decimal calldata) external view returns (Decimal.decimal memory) {
        return outputPrice;
    }

    function getInputPrice(Amm.Dir, Decimal.decimal calldata) external view returns (Decimal.decimal memory) {
        return inputPrice;
    }

    function getReserve() external view returns (Decimal.decimal memory, Decimal.decimal memory) {
        return (quoteAssetReserve, baseAssetReserve);
    }

    function swapInput(
        Amm.Dir,
        Decimal.decimal calldata,
        Decimal.decimal calldata
    ) external returns (Decimal.decimal memory) {
        return inputPrice;
    }

    function swapOutput(Amm.Dir, Decimal.decimal calldata) external returns (Decimal.decimal memory) {
        return outputPrice;
    }

    function mockSetBaseAssetReserve(Decimal.decimal memory _baseAssetReserve) public {
        baseAssetReserve = _baseAssetReserve;
    }

    function mockSetQuoteAssetReserve(Decimal.decimal memory _quoteAssetReserve) public {
        quoteAssetReserve = _quoteAssetReserve;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { Decimal } from "./utils/Decimal.sol";
import { SignedDecimal } from "./utils/SignedDecimal.sol";
import { MixedDecimal } from "./utils/MixedDecimal.sol";
import { IAmm } from "./interface/IAmm.sol";
import { IInsuranceFund } from "./interface/IInsuranceFund.sol";
import { ClearingHouse } from "./ClearingHouse.sol";

contract ClearingHouseViewer {
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;
    using MixedDecimal for SignedDecimal.signedDecimal;

    ClearingHouse public clearingHouse;

    //
    // FUNCTIONS
    //

    constructor(ClearingHouse _clearingHouse) public {
        clearingHouse = _clearingHouse;
    }

    //
    // Public
    //

    /**
     * @notice get unrealized PnL
     * @param _amm IAmm address
     * @param _trader trader address
     * @param _pnlCalcOption ClearingHouse.PnlCalcOption, can be SPOT_PRICE or TWAP.
     * @return unrealized PnL in 18 digits
     */
    function getUnrealizedPnl(
        IAmm _amm,
        address _trader,
        ClearingHouse.PnlCalcOption _pnlCalcOption
    ) external view returns (SignedDecimal.signedDecimal memory) {
        (, SignedDecimal.signedDecimal memory unrealizedPnl) =
            (clearingHouse.getPositionNotionalAndUnrealizedPnl(_amm, _trader, _pnlCalcOption));
        return unrealizedPnl;
    }

    /**
     * @notice get personal balance with funding payment
     * @param _quoteToken ERC20 token address
     * @param _trader trader address
     * @return margin personal balance with funding payment in 18 digits
     */
    function getPersonalBalanceWithFundingPayment(IERC20 _quoteToken, address _trader)
        external
        view
        returns (Decimal.decimal memory margin)
    {
        IInsuranceFund insuranceFund = clearingHouse.insuranceFund();
        IAmm[] memory amms = insuranceFund.getAllAmms();
        for (uint256 i = 0; i < amms.length; i++) {
            if (IAmm(amms[i]).quoteAsset() != _quoteToken) {
                continue;
            }
            Decimal.decimal memory posMargin = getPersonalPositionWithFundingPayment(amms[i], _trader).margin;
            margin = margin.addD(posMargin);
        }
    }

    /**
     * @notice get personal position with funding payment
     * @param _amm IAmm address
     * @param _trader trader address
     * @return position ClearingHouse.Position struct
     */
    function getPersonalPositionWithFundingPayment(IAmm _amm, address _trader)
        public
        view
        returns (ClearingHouse.Position memory position)
    {
        position = clearingHouse.getPosition(_amm, _trader);
        SignedDecimal.signedDecimal memory marginWithFundingPayment =
            MixedDecimal.fromDecimal(position.margin).addD(
                getFundingPayment(position, clearingHouse.getLatestCumulativePremiumFraction(_amm))
            );
        position.margin = marginWithFundingPayment.toInt() >= 0 ? marginWithFundingPayment.abs() : Decimal.zero();
    }

    /**
     * @notice verify if trader's position needs to be migrated
     * @param _amm IAmm address
     * @param _trader trader address
     * @return true if trader's position is not at the latest Amm curve, otherwise is false
     */
    function isPositionNeedToBeMigrated(IAmm _amm, address _trader) external view returns (bool) {
        ClearingHouse.Position memory unadjustedPosition = clearingHouse.getUnadjustedPosition(_amm, _trader);
        if (unadjustedPosition.size.toInt() == 0) {
            return false;
        }
        uint256 latestLiquidityIndex = _amm.getLiquidityHistoryLength().sub(1);
        if (unadjustedPosition.liquidityHistoryIndex == latestLiquidityIndex) {
            return false;
        }
        return true;
    }

    /**
     * @notice get personal margin ratio
     * @param _amm IAmm address
     * @param _trader trader address
     * @return personal margin ratio in 18 digits
     */
    function getMarginRatio(IAmm _amm, address _trader) external view returns (SignedDecimal.signedDecimal memory) {
        return clearingHouse.getMarginRatio(_amm, _trader);
    }

    //
    // PRIVATE
    //

    // negative means trader paid and vice versa
    function getFundingPayment(
        ClearingHouse.Position memory _position,
        SignedDecimal.signedDecimal memory _latestCumulativePremiumFraction
    ) private pure returns (SignedDecimal.signedDecimal memory) {
        return
            _position.size.toInt() == 0
                ? SignedDecimal.zero()
                : _latestCumulativePremiumFraction
                    .subD(_position.lastUpdatedCumulativePremiumFraction)
                    .mulD(_position.size)
                    .mulScalar(-1);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import {
    ReentrancyGuardUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "./utils/Decimal.sol";
import { IExchangeWrapper } from "./interface/IExchangeWrapper.sol";
import { IInsuranceFund } from "./interface/IInsuranceFund.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { DecimalERC20 } from "./utils/DecimalERC20.sol";
import { IMinter } from "./interface/IMinter.sol";
import { IAmm } from "./interface/IAmm.sol";
import { IInflationMonitor } from "./interface/IInflationMonitor.sol";

contract InsuranceFund is IInsuranceFund, PerpFiOwnableUpgrade, BlockContext, ReentrancyGuardUpgradeSafe, DecimalERC20 {
    using Decimal for Decimal.decimal;

    //
    // EVENTS
    //

    event Withdrawn(address withdrawer, uint256 amount);
    event TokenAdded(address tokenAddress);
    event TokenRemoved(address tokenAddress);
    event ShutdownAllAmms(uint256 blockNumber);
    event AmmAdded(address amm);
    event AmmRemoved(address amm);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    mapping(address => bool) private ammMap;
    mapping(address => bool) private quoteTokenMap;
    IAmm[] private amms;
    IERC20[] public quoteTokens;

    // contract dependencies
    IExchangeWrapper public exchange;
    IERC20 public perpToken;
    IMinter public minter;
    IInflationMonitor public inflationMonitor;
    address private beneficiary;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     * @dev only owner can call
     * @param _amm IAmm address
     */
    function addAmm(IAmm _amm) public onlyOwner {
        require(!isExistedAmm(_amm), "amm already added");
        ammMap[address(_amm)] = true;
        amms.push(_amm);
        emit AmmAdded(address(_amm));

        // add token if it's new one
        IERC20 token = _amm.quoteAsset();
        if (!isQuoteTokenExisted(token)) {
            quoteTokens.push(token);
            quoteTokenMap[address(token)] = true;
            emit TokenAdded(address(token));
        }
    }

    /**
     * @dev only owner can call. no need to call
     * @param _amm IAmm address
     */
    function removeAmm(IAmm _amm) external onlyOwner {
        require(isExistedAmm(_amm), "amm not existed");
        ammMap[address(_amm)] = false;
        uint256 ammLength = amms.length;
        for (uint256 i = 0; i < ammLength; i++) {
            if (amms[i] == _amm) {
                amms[i] = amms[ammLength - 1];
                amms.pop();
                emit AmmRemoved(address(_amm));
                break;
            }
        }
    }

    /**
     * @notice shutdown all Amms when fatal error happens
     * @dev only owner can call. Emit `ShutdownAllAmms` event
     */
    function shutdownAllAmm() external onlyOwner {
        if (!inflationMonitor.isOverMintThreshold()) {
            return;
        }
        for (uint256 i; i < amms.length; i++) {
            amms[i].shutdown();
        }
        emit ShutdownAllAmms(block.number);
    }

    function removeToken(IERC20 _token) external onlyOwner {
        require(isQuoteTokenExisted(_token), "token not existed");

        quoteTokenMap[address(_token)] = false;
        uint256 quoteTokensLength = getQuoteTokenLength();
        for (uint256 i = 0; i < quoteTokensLength; i++) {
            if (quoteTokens[i] == _token) {
                if (i < quoteTokensLength - 1) {
                    quoteTokens[i] = quoteTokens[quoteTokensLength - 1];
                }
                quoteTokens.pop();
                break;
            }
        }

        // exchange and transfer to the quoteToken with the most value. if no more quoteToken, buy protocol tokens
        // TODO use curve or balancer fund token for pooling the fees will be less painful
        if (balanceOf(_token).toUint() > 0) {
            address outputToken = getTokenWithMaxValue();
            if (outputToken == address(0)) {
                outputToken = address(perpToken);
            }
            swapInput(_token, IERC20(outputToken), balanceOf(_token), Decimal.zero());
        }

        emit TokenRemoved(address(_token));
    }

    /**
     * @notice withdraw token to caller
     * @param _amount the amount of quoteToken caller want to withdraw
     */
    function withdraw(IERC20 _quoteToken, Decimal.decimal calldata _amount) external override {
        require(beneficiary == _msgSender(), "caller is not beneficiary");
        require(isQuoteTokenExisted(_quoteToken), "Asset is not supported");

        Decimal.decimal memory quoteBalance = balanceOf(_quoteToken);
        if (_amount.toUint() > quoteBalance.toUint()) {
            Decimal.decimal memory insufficientAmount = _amount.subD(quoteBalance);
            swapEnoughQuoteAmount(_quoteToken, insufficientAmount);
            quoteBalance = balanceOf(_quoteToken);
        }
        require(quoteBalance.toUint() >= _amount.toUint(), "Fund not enough");

        _transfer(_quoteToken, _msgSender(), _amount);
        emit Withdrawn(_msgSender(), _amount.toUint());
    }

    //
    // SETTER
    //

    function setExchange(IExchangeWrapper _exchange) external onlyOwner {
        exchange = _exchange;
    }

    function setBeneficiary(address _beneficiary) external onlyOwner {
        beneficiary = _beneficiary;
    }

    function setMinter(IMinter _minter) public onlyOwner {
        minter = _minter;
        perpToken = minter.getPerpToken();
    }

    function setInflationMonitor(IInflationMonitor _inflationMonitor) external onlyOwner {
        inflationMonitor = _inflationMonitor;
    }

    function getQuoteTokenLength() public view returns (uint256) {
        return quoteTokens.length;
    }

    //
    // INTERNAL FUNCTIONS
    //

    function getTokenWithMaxValue() internal view returns (address) {
        uint256 numOfQuoteTokens = quoteTokens.length;
        if (numOfQuoteTokens == 0) {
            return address(0);
        }
        if (numOfQuoteTokens == 1) {
            return address(quoteTokens[0]);
        }

        IERC20 denominatedToken = quoteTokens[0];
        IERC20 maxValueToken = denominatedToken;
        Decimal.decimal memory valueOfMaxValueToken = balanceOf(denominatedToken);
        for (uint256 i = 1; i < numOfQuoteTokens; i++) {
            IERC20 quoteToken = quoteTokens[i];
            Decimal.decimal memory quoteTokenValue =
                exchange.getInputPrice(quoteToken, denominatedToken, balanceOf(quoteToken));
            if (quoteTokenValue.cmp(valueOfMaxValueToken) > 0) {
                maxValueToken = quoteToken;
                valueOfMaxValueToken = quoteTokenValue;
            }
        }
        return address(maxValueToken);
    }

    function swapInput(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal memory inputTokenSold,
        Decimal.decimal memory minOutputTokenBought
    ) internal returns (Decimal.decimal memory received) {
        if (inputTokenSold.toUint() == 0) {
            return Decimal.zero();
        }
        _approve(inputToken, address(exchange), inputTokenSold);
        received = exchange.swapInput(inputToken, outputToken, inputTokenSold, minOutputTokenBought, Decimal.zero());
        require(received.toUint() > 0, "Exchange swap error");
    }

    function swapOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal memory outputTokenBought,
        Decimal.decimal memory maxInputTokenSold
    ) internal returns (Decimal.decimal memory received) {
        if (outputTokenBought.toUint() == 0) {
            return Decimal.zero();
        }
        _approve(inputToken, address(exchange), maxInputTokenSold);
        received = exchange.swapOutput(inputToken, outputToken, outputTokenBought, maxInputTokenSold, Decimal.zero());
        require(received.toUint() > 0, "Exchange swap error");
    }

    function swapEnoughQuoteAmount(IERC20 _quoteToken, Decimal.decimal memory _requiredQuoteAmount) internal {
        IERC20[] memory orderedTokens = getOrderedQuoteTokens(_quoteToken);
        for (uint256 i = 0; i < orderedTokens.length; i++) {
            // get how many amount of quote token i is still required
            Decimal.decimal memory swappedQuoteToken;
            Decimal.decimal memory otherQuoteRequiredAmount =
                exchange.getOutputPrice(orderedTokens[i], _quoteToken, _requiredQuoteAmount);

            // if balance of token i can afford the left debt, swap and return
            if (otherQuoteRequiredAmount.toUint() <= balanceOf(orderedTokens[i]).toUint()) {
                swappedQuoteToken = swapInput(orderedTokens[i], _quoteToken, otherQuoteRequiredAmount, Decimal.zero());
                return;
            }

            // if balance of token i can't afford the left debt, show hand and move to the next one
            swappedQuoteToken = swapInput(orderedTokens[i], _quoteToken, balanceOf(orderedTokens[i]), Decimal.zero());
            _requiredQuoteAmount = _requiredQuoteAmount.subD(swappedQuoteToken);
        }

        // if all the quote tokens can't afford the debt, ask staking token to mint
        if (_requiredQuoteAmount.toUint() > 0) {
            Decimal.decimal memory requiredPerpAmount =
                exchange.getOutputPrice(perpToken, _quoteToken, _requiredQuoteAmount);
            minter.mintForLoss(requiredPerpAmount);
            swapInput(perpToken, _quoteToken, requiredPerpAmount, Decimal.zero());
        }
    }

    //
    // VIEW
    //
    function isExistedAmm(IAmm _amm) public view override returns (bool) {
        return ammMap[address(_amm)];
    }

    function getAllAmms() external view override returns (IAmm[] memory) {
        return amms;
    }

    function isQuoteTokenExisted(IERC20 _token) internal view returns (bool) {
        return quoteTokenMap[address(_token)];
    }

    function getOrderedQuoteTokens(IERC20 _exceptionQuoteToken) internal view returns (IERC20[] memory orderedTokens) {
        IERC20[] memory tokens = quoteTokens;
        // insertion sort
        for (uint256 i = 0; i < getQuoteTokenLength(); i++) {
            IERC20 currentToken = quoteTokens[i];
            Decimal.decimal memory currentPerpValue =
                exchange.getInputPrice(currentToken, perpToken, balanceOf(currentToken));

            for (uint256 j = i; j > 0; j--) {
                Decimal.decimal memory subsetPerpValue =
                    exchange.getInputPrice(tokens[j - 1], perpToken, balanceOf(tokens[j - 1]));
                if (currentPerpValue.toUint() > subsetPerpValue.toUint()) {
                    tokens[j] = tokens[j - 1];
                    tokens[j - 1] = currentToken;
                }
            }
        }

        orderedTokens = new IERC20[](tokens.length - 1);
        uint256 j;
        for (uint256 i = 0; i < tokens.length; i++) {
            // jump to the next token
            if (tokens[i] == _exceptionQuoteToken) {
                continue;
            }
            orderedTokens[j] = tokens[i];
            j++;
        }
    }

    function balanceOf(IERC20 _quoteToken) internal view returns (Decimal.decimal memory) {
        return _balanceOf(_quoteToken, address(this));
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { Decimal } from "../utils/Decimal.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

interface IExchangeWrapper {
    function swapInput(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal calldata inputTokenSold,
        Decimal.decimal calldata minOutputTokenBought,
        Decimal.decimal calldata maxPrice
    ) external returns (Decimal.decimal memory);

    function swapOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal calldata outputTokenBought,
        Decimal.decimal calldata maxInputTokeSold,
        Decimal.decimal calldata maxPrice
    ) external returns (Decimal.decimal memory);

    function getInputPrice(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal calldata inputTokenSold
    ) external view returns (Decimal.decimal memory);

    function getOutputPrice(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal calldata outputTokenBought
    ) external view returns (Decimal.decimal memory);

    function getSpotPrice(IERC20 inputToken, IERC20 outputToken) external view returns (Decimal.decimal memory);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { Decimal } from "../utils/Decimal.sol";

interface IInflationMonitor {
    function isOverMintThreshold() external view returns (bool);

    function appendMintedTokenHistory(Decimal.decimal calldata _amount) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../InsuranceFund.sol";

contract InsuranceFundFake is InsuranceFund {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    // make internal function testable
    function testGetOrderedQuoteTokens(IERC20 _exceptionQuoteToken)
        external
        view
        returns (IERC20[] memory orderedTokens)
    {
        return getOrderedQuoteTokens(_exceptionQuoteToken);
    }

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { Decimal } from "./utils/Decimal.sol";
import { SupplySchedule } from "./SupplySchedule.sol";
import { RewardsDistribution } from "./RewardsDistribution.sol";
import { IInflationMonitor } from "./interface/IInflationMonitor.sol";
import { IPerpToken } from "./interface/IPerpToken.sol";
import { IMinter } from "./interface/IMinter.sol";

contract Minter is IMinter, PerpFiOwnableUpgrade {
    using Decimal for Decimal.decimal;

    //
    // EVENT
    //
    event PerpMinted(uint256 amount);

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//

    address private perpToken;
    SupplySchedule public supplySchedule;
    RewardsDistribution public rewardsDistribution;
    IInflationMonitor public inflationMonitor;
    address public insuranceFund;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    /**
     * @notice pre-minted tokens will transfer to the contract creator
     * (contract creator will be admin, minter and pauser),
     * but mint() will transfer to the minter (because only minter can mint)
     * @notice openzeppelin doesn't support struct input
     * https://github.com/OpenZeppelin/openzeppelin-sdk/issues/1523
     */
    function initialize(address _perpToken) public initializer {
        __Ownable_init();

        perpToken = _perpToken;
    }

    //*************** ERC20 functions ***************//
    //
    // PUBLIC functions
    //

    // mintReward is open to everyone (keeper) as long as it meets the condition
    function mintReward() external override {
        uint256 mintableSupply = supplySchedule.mintableSupply().toUint();
        require(mintableSupply > 0, "no supply is mintable");

        IPerpToken(perpToken).mint(address(rewardsDistribution), mintableSupply);
        rewardsDistribution.distributeRewards(IERC20(perpToken), Decimal.decimal(mintableSupply));

        // record minting event before mutation to token supply
        supplySchedule.recordMintEvent();

        emit PerpMinted(mintableSupply);
    }

    // mint for covering unexpected loss, only insurance fund
    function mintForLoss(Decimal.decimal memory _amount) public override {
        require(insuranceFund == _msgSender(), "only insuranceFund");
        require(address(inflationMonitor) != address(0), "inflationMonitor not fount");

        // minter role checking is inside `mint`
        // mint to insuranceFund
        IPerpToken(perpToken).mint(insuranceFund, _amount.toUint());
        inflationMonitor.appendMintedTokenHistory(_amount);

        emit PerpMinted(_amount.toUint());
    }

    function setInsuranceFund(address _insuranceFund) external onlyOwner {
        insuranceFund = _insuranceFund;
    }

    function setRewardsDistribution(RewardsDistribution _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }

    function setSupplySchedule(SupplySchedule _supplySchedule) external onlyOwner {
        supplySchedule = _supplySchedule;
    }

    function setInflationMonitor(IInflationMonitor _inflationMonitor) external onlyOwner {
        inflationMonitor = _inflationMonitor;
    }

    function getPerpToken() external view override returns (IERC20) {
        return IERC20(perpToken);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "./utils/Decimal.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { DecimalERC20 } from "./utils/DecimalERC20.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { IRewardRecipient } from "./interface/IRewardRecipient.sol";

contract RewardsDistribution is PerpFiOwnableUpgrade, BlockContext, DecimalERC20 {
    using Decimal for Decimal.decimal;

    //
    // EVENTS
    //
    event RewardDistributed(uint256 reward, uint256 timestamp);

    //
    // STRUCT
    //
    /**
     * @notice Stores an address and amount
     * of the inflationary supply to sent to the address.
     */
    struct DistributionData {
        address destination;
        Decimal.decimal amount;
    }

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    address private rewardsController;
    IRewardRecipient private defaultRecipient;

    /**
     * @notice An array of addresses and amounts to send.
     * this provide the flexibility for owner (DAO) to add more incentive program.
     * eg. share 1000 PERP to another smart contract which will reward PERP/USDC Balancer LP
     */
    DistributionData[] public distributions;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //

    function initialize(address _rewardsController, IRewardRecipient _defaultRecipient) public initializer {
        __Ownable_init();

        rewardsController = _rewardsController;
        defaultRecipient = _defaultRecipient;
    }

    function distributeRewards(IERC20 _perpToken, Decimal.decimal memory _amount) public {
        require(_msgSender() == rewardsController, "!_rewardsController");

        require(_balanceOf(_perpToken, address(this)).toUint() >= _amount.toUint(), "not enough PERP");

        // Iterate the array of distributions sending the configured amounts
        // the size of the distributions array will be controlled by owner (dao)
        // owner should be aware of not making this array too large
        Decimal.decimal memory remainder = _amount;
        for (uint256 i = 0; i < distributions.length; i++) {
            if (distributions[i].destination != address(0) && distributions[i].amount.toUint() != 0) {
                remainder = remainder.subD(distributions[i].amount);

                // Transfer the PERP
                _transfer(_perpToken, distributions[i].destination, distributions[i].amount);

                bytes memory payload = abi.encodeWithSignature("notifyRewardAmount(uint256)", distributions[i].amount);

                // solhint-disable avoid-low-level-calls
                (bool success, ) = distributions[i].destination.call(payload);

                // solhint-disable no-empty-blocks
                if (!success) {
                    // we're ignoring the return value as
                    // it will fail for contracts that do not implement IRewardRecipient.sol
                }
            }
        }

        // staker will share all the remaining PERP reward
        _transfer(_perpToken, address(defaultRecipient), remainder);
        defaultRecipient.notifyRewardAmount(remainder);

        emit RewardDistributed(_amount.toUint(), _blockTimestamp());
    }

    function addRewardsDistribution(address _destination, Decimal.decimal memory _amount) public onlyOwner {
        require(_destination != address(0), "Cant add a zero address");
        require(_amount.toUint() != 0, "Cant add a zero amount");

        DistributionData memory rewardsDistribution = DistributionData(address(_destination), _amount);
        distributions.push(rewardsDistribution);
    }

    function removeRewardsDistribution(uint256 _index) external onlyOwner {
        require(distributions.length != 0 && _index <= distributions.length - 1, "index out of bounds");

        if (_index < distributions.length - 1) {
            distributions[_index] = distributions[distributions.length - 1];
        }
        distributions.pop();
    }

    function editRewardsDistribution(
        uint256 _index,
        address _destination,
        Decimal.decimal memory _amount
    ) public onlyOwner {
        require(distributions.length != 0 && _index <= distributions.length - 1, "index out of bounds");

        distributions[_index].destination = _destination;
        distributions[_index].amount = _amount;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

interface IPerpToken {
    function mint(address account, uint256 amount) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../SupplySchedule.sol";

contract SupplyScheduleFake is SupplySchedule {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { MerkleRedeemUpgradeSafe } from "./Balancer/MerkleRedeemUpgradeSafe.sol";
import { Decimal } from "../utils/Decimal.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";
import { BlockContext } from "../utils/BlockContext.sol";

contract PerpRewardVesting is MerkleRedeemUpgradeSafe, BlockContext {
    using Decimal for Decimal.decimal;
    using SafeMath for uint256;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//
    // {weekMerkleRootsIndex: timestamp}
    mapping(uint256 => uint256) public merkleRootTimestampMap;

    // array of weekMerkleRootsIndex
    uint256[] public merkleRootIndexes;

    uint256 public vestingPeriod;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variable, ables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    function initialize(IERC20 _token, uint256 _vestingPeriod) external initializer {
        require(address(_token) != address(0), "Invalid input");
        __MerkleRedeem_init(_token);
        vestingPeriod = _vestingPeriod;
    }

    function claimWeeks(address _account, Claim[] memory _claims) public virtual override {
        for (uint256 i; i < _claims.length; i++) {
            claimWeek(_account, _claims[i].week, _claims[i].balance, _claims[i].merkleProof);
        }
    }

    function claimWeek(
        address _account,
        uint256 _week,
        uint256 _claimedBalance,
        bytes32[] memory _merkleProof
    ) public virtual override {
        //
        //                      +----------------+
        //                      | vesting period |
        //           +----------------+----------+
        //           | vesting period |          |
        //  ---------+------+---+-----+------+---+
        //           |          |     |     now  |
        //           |        week2   |          merkleRootTimestampMap[week1]
        //           |                |
        //         week1              merkleRootTimestampMap[week1]
        //
        //  week1 -> claimable
        //  week2 -> non-claimable
        //
        require(
            _blockTimestamp() >= merkleRootTimestampMap[_week] && merkleRootTimestampMap[_week] > 0,
            "Invalid claim"
        );
        super.claimWeek(_account, _week, _claimedBalance, _merkleProof);
    }

    function seedAllocations(
        uint256 _week,
        bytes32 _merkleRoot,
        uint256 _totalAllocation
    ) public override onlyOwner {
        super.seedAllocations(_week, _merkleRoot, _totalAllocation);
        merkleRootTimestampMap[_week] = _blockTimestamp().add(vestingPeriod);
        merkleRootIndexes.push(_week);
    }

    //
    // INTERNAL
    //

    function getLengthOfMerkleRoots() external view returns (uint256) {
        return merkleRootIndexes.length;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IExchangeWrapper, Decimal, IERC20 } from "../../interface/IExchangeWrapper.sol";
import { DecimalERC20 } from "../../utils/DecimalERC20.sol";

contract ExchangeWrapperMock is IExchangeWrapper, DecimalERC20 {
    using Decimal for Decimal.decimal;

    Decimal.decimal private exchangeRatio = Decimal.zero();
    Decimal.decimal private spotPrice = Decimal.zero();
    bool bException = false;

    function mockSetSwapRatio(Decimal.decimal memory _ratio) public {
        exchangeRatio = _ratio;
    }

    function mockSpotPrice(Decimal.decimal memory _price) public {
        spotPrice = _price;
    }

    function mockSetException() public {
        bException = true;
    }

    function swapInput(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal calldata inputTokenSold,
        Decimal.decimal calldata,
        Decimal.decimal calldata
    ) external override returns (Decimal.decimal memory) {
        if (bException) {
            revert();
        }
        _transferFrom(inputToken, msg.sender, address(this), inputTokenSold);
        _transfer(outputToken, msg.sender, inputTokenSold.divD(exchangeRatio));
        return inputTokenSold.divD(exchangeRatio);
    }

    function swapOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        Decimal.decimal calldata outputTokenBought,
        Decimal.decimal calldata,
        Decimal.decimal calldata
    ) external override returns (Decimal.decimal memory) {
        if (bException) {
            revert();
        }
        _transferFrom(inputToken, msg.sender, address(this), outputTokenBought.mulD(exchangeRatio));
        _transfer(outputToken, msg.sender, outputTokenBought);
        return outputTokenBought.mulD(exchangeRatio);
    }

    function getInputPrice(
        IERC20,
        IERC20,
        Decimal.decimal calldata inputTokenSold
    ) external view override returns (Decimal.decimal memory) {
        return inputTokenSold.divD(exchangeRatio);
    }

    function getOutputPrice(
        IERC20,
        IERC20,
        Decimal.decimal calldata outputTokenBought
    ) external view override returns (Decimal.decimal memory) {
        return outputTokenBought.mulD(exchangeRatio);
    }

    function getSpotPrice(IERC20, IERC20) external view override returns (Decimal.decimal memory) {
        return spotPrice;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { PerpFiOwnableUpgrade } from "../utils/PerpFiOwnableUpgrade.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { CErc20 } from "./Compound/CTokenInterface.sol";
import { BPool } from "./Balancer/BPool.sol";
import { IExchangeWrapper, Decimal } from "../interface/IExchangeWrapper.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";
import { Decimal, SafeMath } from "../utils/Decimal.sol";

// USDC/USDT decimal 6
// cUSDC/cUSDT decimal 8
contract ExchangeWrapper is PerpFiOwnableUpgrade, IExchangeWrapper, DecimalERC20 {
    using Decimal for Decimal.decimal;
    using SafeMath for *;

    // default max price slippage is 20% of spot price. 12e17 = (1 + 20%) e18
    uint256 private constant DEFAULT_MAX_PRICE_SLIPPAGE = 12e17;

    //
    // EVENTS
    //
    event ExchangeSwap(uint256 perpTokenAmount, uint256 usdtAmount);
    // for debug purpose in the future
    event BalancerSwap(uint256 inAmount, uint256 out);
    event CompoundRedeem(uint256 underlyingAmount, uint256 cTokenAmount);
    event CompoundMint(uint256 underlyingAmount, uint256 cTokenAmount);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//
    BPool public balancerPool;
    CErc20 public compoundCUsdt;
    IERC20 private perpToken;
    IERC20 private usdtToken;
    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize(
        address _balancerPool,
        address _compoundCUsdt,
        address _perpToken
    ) external initializer {
        __Ownable_init();

        perpToken = IERC20(_perpToken);
        setBalancerPool(_balancerPool);
        setCompoundCUsdt(_compoundCUsdt);
    }

    function swapInput(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal calldata _inputTokenSold,
        Decimal.decimal calldata _minOutputTokenBought,
        Decimal.decimal calldata _maxPrice
    ) external override returns (Decimal.decimal memory) {
        return implSwapInput(_inputToken, _outputToken, _inputTokenSold, _minOutputTokenBought, _maxPrice);
    }

    function swapOutput(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal calldata _outputTokenBought,
        Decimal.decimal calldata _maxInputTokeSold,
        Decimal.decimal calldata _maxPrice
    ) external override returns (Decimal.decimal memory) {
        return implSwapOutput(_inputToken, _outputToken, _outputTokenBought, _maxInputTokeSold, _maxPrice);
    }

    function getInputPrice(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal calldata _inputTokenSold
    ) external view override returns (Decimal.decimal memory) {
        Decimal.decimal memory spotPrice = implGetSpotPrice(_inputToken, _outputToken);
        return _inputTokenSold.mulD(spotPrice);
    }

    function getOutputPrice(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal calldata _outputTokenBought
    ) external view override returns (Decimal.decimal memory) {
        Decimal.decimal memory spotPrice = implGetSpotPrice(_inputToken, _outputToken);
        return _outputTokenBought.divD(spotPrice);
    }

    function getSpotPrice(IERC20 _inputToken, IERC20 _outputToken)
        external
        view
        override
        returns (Decimal.decimal memory)
    {
        return implGetSpotPrice(_inputToken, _outputToken);
    }

    function approve(
        IERC20 _token,
        address _to,
        Decimal.decimal memory _amount
    ) public onlyOwner {
        _approve(_token, _to, _amount);
    }

    function setBalancerPool(address _balancerPool) public onlyOwner {
        balancerPool = BPool(_balancerPool);
    }

    function setCompoundCUsdt(address _compoundCUsdt) public onlyOwner {
        compoundCUsdt = CErc20(_compoundCUsdt);
        usdtToken = IERC20(compoundCUsdt.underlying());

        // approve cUSDT for redeem/redeemUnderlying
        approve(IERC20(address(compoundCUsdt)), address(compoundCUsdt), Decimal.decimal(uint256(-1)));
        // approve usdt for cUSDT to mint
        approve(usdtToken, address(compoundCUsdt), Decimal.decimal(uint256(-1)));
    }

    //
    // INTERNALS
    //

    function implSwapInput(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal memory _inputTokenSold,
        Decimal.decimal memory _minOutputTokenBought,
        Decimal.decimal memory _maxPrice
    ) internal returns (Decimal.decimal memory outTokenAmount) {
        address sender = _msgSender();
        Decimal.decimal memory inTokenAmount = _inputTokenSold;

        //___0. transfer input token to exchangeWrapper
        _transferFrom(_inputToken, sender, address(this), inTokenAmount);

        // mint cUSDT for Balancer if _inputToken is USDT
        if (isUSDT(_inputToken)) {
            inTokenAmount = compoundMint(inTokenAmount);
        }

        //___1. swap
        IERC20 inToken = balancerAcceptableToken(_inputToken);
        IERC20 outToken = balancerAcceptableToken(_outputToken);
        outTokenAmount = balancerSwapIn(inToken, outToken, inTokenAmount, _minOutputTokenBought, _maxPrice);

        // if _outputToken is USDT redeem cUSDT to USDT
        if (isUSDT(_outputToken)) {
            outTokenAmount = compoundRedeem(outTokenAmount);
        }
        emit ExchangeSwap(_inputTokenSold.toUint(), outTokenAmount.toUint());

        //___2. transfer back to sender
        _transfer(_outputToken, sender, outTokenAmount);
    }

    function implSwapOutput(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal memory _outputTokenBought,
        Decimal.decimal memory _maxInputTokenSold,
        Decimal.decimal memory _maxPrice
    ) internal returns (Decimal.decimal memory) {
        address sender = _msgSender();
        Decimal.decimal memory outTokenBought = _outputTokenBought;

        //___0. if _outputToken is USDT, get cUSDT amount for Balancer
        if (isUSDT(_outputToken)) {
            outTokenBought = compoundCTokenAmount(outTokenBought);
        }

        IERC20 inToken = balancerAcceptableToken(_inputToken);
        IERC20 outToken = balancerAcceptableToken(_outputToken);
        //___1. calc how much input tokens needed by given outTokenBought,
        Decimal.decimal memory expectedTokenInAmount =
            calcBalancerInGivenOut(address(inToken), address(outToken), outTokenBought);
        require(_maxInputTokenSold.cmp(expectedTokenInAmount) >= 0, "max input amount less than expected");

        //___2 transfer input tokens to exchangeWrapper
        // if _inputToken is USDT, mint cUSDT for Balancer
        if (isUSDT(_inputToken)) {
            Decimal.decimal memory underlyingAmount = compoundUnderlyingAmount(expectedTokenInAmount);
            _transferFrom(_inputToken, sender, address(this), underlyingAmount);
            compoundMint(underlyingAmount);
        } else {
            _transferFrom(_inputToken, sender, address(this), expectedTokenInAmount);
        }

        //___3. swap
        Decimal.decimal memory requiredInAmount =
            balancerSwapOut(inToken, outToken, outTokenBought, _maxInputTokenSold, _maxPrice);

        // if _outputToken is USDT, redeem cUSDT to USDT
        if (isUSDT(_outputToken)) {
            compoundRedeemUnderlying(_outputTokenBought);
        }
        emit ExchangeSwap(requiredInAmount.toUint(), _outputTokenBought.toUint());

        //___4. transfer back to sender
        _transfer(_outputToken, sender, _outputTokenBought);

        return requiredInAmount;
    }

    function balancerSwapIn(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal memory _inputTokenSold,
        Decimal.decimal memory _minOutputTokenBought,
        Decimal.decimal memory _maxPrice
    ) internal returns (Decimal.decimal memory) {
        // if max price is 0, set to (DEFAULT_MAX_PRICE_SLIPPAGE x spot price)
        if (_maxPrice.toUint() == 0) {
            uint256 spotPrice = balancerPool.getSpotPrice(address(_inputToken), address(_outputToken));
            _maxPrice = Decimal.decimal(spotPrice).mulD(Decimal.decimal(DEFAULT_MAX_PRICE_SLIPPAGE));
        }
        _approve(IERC20(_inputToken), address(balancerPool), _inputTokenSold);

        // swap
        uint256 tokeSold = _toUint(_inputToken, _inputTokenSold);
        (uint256 outAmountInSelfDecimals, ) =
            balancerPool.swapExactAmountIn(
                address(_inputToken),
                tokeSold,
                address(_outputToken),
                _toUint(_outputToken, _minOutputTokenBought),
                _maxPrice.toUint()
            );
        require(outAmountInSelfDecimals > 0, "Balancer exchange error");
        emit BalancerSwap(tokeSold, outAmountInSelfDecimals);

        return _toDecimal(_outputToken, outAmountInSelfDecimals);
    }

    function balancerSwapOut(
        IERC20 _inputToken,
        IERC20 _outputToken,
        Decimal.decimal memory _outputTokenBought,
        Decimal.decimal memory _maxInputTokenSold,
        Decimal.decimal memory _maxPrice
    ) internal returns (Decimal.decimal memory tokenAmountIn) {
        // if max price is 0, set to (DEFAULT_MAX_PRICE_SLIPPAGE x spot price)
        if (_maxPrice.toUint() == 0) {
            uint256 spotPrice = balancerPool.getSpotPrice(address(_inputToken), address(_outputToken));
            _maxPrice = Decimal.decimal(spotPrice).mulD(Decimal.decimal(DEFAULT_MAX_PRICE_SLIPPAGE));
        }
        _approve(IERC20(_inputToken), address(balancerPool), _maxInputTokenSold);

        // swap
        uint256 tokenBought = _toUint(_outputToken, _outputTokenBought);
        uint256 maxTokenSold = _toUint(_inputToken, _maxInputTokenSold);
        (uint256 inAmountInSelfDecimals, ) =
            balancerPool.swapExactAmountOut(
                address(_inputToken),
                maxTokenSold,
                address(_outputToken),
                tokenBought,
                _maxPrice.toUint()
            );
        require(inAmountInSelfDecimals > 0, "Balancer exchange error");
        emit BalancerSwap(inAmountInSelfDecimals, tokenBought);

        return _toDecimal(_inputToken, inAmountInSelfDecimals);
    }

    function compoundMint(Decimal.decimal memory _underlyingAmount)
        internal
        returns (Decimal.decimal memory mintedAmount)
    {
        // https://compound.finance/docs/ctokens#mint
        uint256 underlyingAmountInSelfDecimals = _toUint(usdtToken, _underlyingAmount);
        require(compoundCUsdt.mint(underlyingAmountInSelfDecimals) == 0, "Compound mint error");

        mintedAmount = compoundCTokenAmount(_underlyingAmount);
        uint256 cTokenAmountIn8Decimals = _toUint(IERC20(address(compoundCUsdt)), mintedAmount);
        emit CompoundMint(underlyingAmountInSelfDecimals, cTokenAmountIn8Decimals);
    }

    function compoundRedeem(Decimal.decimal memory _cTokenAmount)
        internal
        returns (Decimal.decimal memory outUnderlyingAmount)
    {
        // https://compound.finance/docs/ctokens#redeem
        uint256 cTokenAmountIn8Decimals = _toUint(IERC20(address(compoundCUsdt)), _cTokenAmount);
        require(compoundCUsdt.redeem(cTokenAmountIn8Decimals) == 0, "Compound redeem error");

        outUnderlyingAmount = compoundUnderlyingAmount(_cTokenAmount);
        uint256 underlyingAmountInSelfDecimals = _toUint(usdtToken, outUnderlyingAmount);
        emit CompoundRedeem(underlyingAmountInSelfDecimals, cTokenAmountIn8Decimals);
    }

    function compoundRedeemUnderlying(Decimal.decimal memory _underlyingAmount)
        internal
        returns (Decimal.decimal memory outCTokenAmount)
    {
        // https://compound.finance/docs/ctokens#redeem-underlying
        uint256 underlyingTokenIn6Decimals = _toUint(usdtToken, _underlyingAmount);
        require(compoundCUsdt.redeemUnderlying(underlyingTokenIn6Decimals) == 0, "Compound redeemUnderlying error");

        outCTokenAmount = compoundCTokenAmount(_underlyingAmount);
        uint256 cTokenAmountIn8Decimals = _toUint(IERC20(address(compoundCUsdt)), outCTokenAmount);
        emit CompoundRedeem(underlyingTokenIn6Decimals, cTokenAmountIn8Decimals);
    }

    function compoundUnderlyingAmount(Decimal.decimal memory _cTokenAmount)
        internal
        view
        returns (Decimal.decimal memory underlyingAmount)
    {
        // The current exchange rate as an unsigned integer, scaled by 1e18.
        // ** calculation of decimals between tokens is under exchangeRateStored()
        uint256 exchangeRate = compoundCUsdt.exchangeRateStored();
        uint256 cTokenIn8Decimals = _toUint(IERC20(address(compoundCUsdt)), _cTokenAmount);

        // The amount of underlying tokens received is equal to the quantity of cTokens,
        // multiplied by the current Exchange Rate
        Decimal.decimal memory underlyingTokenIn6Decimals =
            Decimal.decimal(cTokenIn8Decimals).mulD(Decimal.decimal(exchangeRate));
        underlyingAmount = _toDecimal(usdtToken, underlyingTokenIn6Decimals.toUint());
    }

    function compoundCTokenAmount(Decimal.decimal memory _underlyingAmount)
        internal
        view
        returns (Decimal.decimal memory cTokenAmount)
    {
        // The current exchange rate as an unsigned integer, scaled by 1e18.
        // ** calculation of decimals between tokens is under exchangeRateStored()
        uint256 exchangeRate = compoundCUsdt.exchangeRateStored();
        uint256 underlyingTokenIn6Decimals = _toUint(usdtToken, _underlyingAmount);

        // The amount of cTokens is equal to the quantity of underlying tokens received,
        // divided by the current Exchange Rate
        uint256 cTokenIn8Decimals =
            Decimal.decimal(underlyingTokenIn6Decimals).divD(Decimal.decimal(exchangeRate)).toUint();
        cTokenAmount = _toDecimal(IERC20(address(compoundCUsdt)), cTokenIn8Decimals);
    }

    function balancerAcceptableToken(IERC20 _token) internal view returns (IERC20) {
        if (isUSDT(_token)) {
            return IERC20(address(compoundCUsdt));
        }
        return _token;
    }

    function calcBalancerInGivenOut(
        address _inToken,
        address _outToken,
        Decimal.decimal memory _givenOutAmount
    ) internal view returns (Decimal.decimal memory) {
        uint256 givenOut = _toUint(IERC20(_outToken), _givenOutAmount);
        uint256 inWeight = balancerPool.getDenormalizedWeight(_inToken);
        uint256 outWeight = balancerPool.getDenormalizedWeight(_outToken);
        uint256 inBalance = balancerPool.getBalance(_inToken);
        uint256 outBalance = balancerPool.getBalance(_outToken);
        uint256 expectedTokenInAmount =
            balancerPool.calcInGivenOut(
                inBalance,
                inWeight,
                outBalance,
                outWeight,
                givenOut,
                balancerPool.getSwapFee()
            );
        return _toDecimal(IERC20(_inToken), expectedTokenInAmount);
    }

    function implGetSpotPrice(IERC20 _inputToken, IERC20 _outputToken) internal view returns (Decimal.decimal memory) {
        if (_inputToken == _outputToken) return Decimal.one();

        IERC20 inToken = balancerAcceptableToken(_inputToken);
        IERC20 outToken = balancerAcceptableToken(_outputToken);
        uint256 spotPrice = balancerPool.getSpotPrice(address(inToken), address(outToken));

        // the amount returned from getSpotPrice includes decimals difference between tokens.
        // for example, input/output token pair, USDC(8 decimals)/PERP(18 decimals) and 2 USDC buy 1 PERP,
        // it returns 0.5e-10*e18, in the other direction(PERP/USDC), it returns 2e10*e18
        Decimal.decimal memory price = Decimal.decimal(spotPrice);
        uint256 decimalsOfInput = _getTokenDecimals(address(inToken));
        uint256 decimalsOfOutput = _getTokenDecimals(address(outToken));
        if (decimalsOfInput < decimalsOfOutput) {
            price = _toDecimal(inToken, price.toUint());
        } else if (decimalsOfInput > decimalsOfOutput) {
            price = Decimal.decimal(_toUint(outToken, price));
        }

        // compoundUnderlyingAmount gets n underlying tokens by given m cTokens
        // if input token is USDT, spot price is 0.5(cUSDT/PERP). The price of USDT/PERP would be 0.5 x n
        // if output token is USDT, spot price is 2(PERP/cUSDT) then price is 2/n
        if (isUSDT(_inputToken)) {
            return price.mulD(compoundUnderlyingAmount(Decimal.one()));
        } else if (isUSDT(_outputToken)) {
            return price.divD(compoundUnderlyingAmount(Decimal.one()));
        }
        return price;
    }

    function isUSDT(IERC20 _token) internal view returns (bool) {
        if (usdtToken == _token) {
            return true;
        }
        return false;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

// copy from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol#L250

interface CErc20Interface {
    // contract CErc20Storage {
    // /**
    //  * @notice Underlying asset for this CToken
    //  */
    // address public underlying;
    // }
    // original definition is above, but change to a function for easier implementation
    function underlying() external view returns (address);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
}

// https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol#L119
interface CTokenInterface {
    function transfer(address dst, uint256 amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function totalBorrowsCurrent() external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getCash() external view returns (uint256);

    function accrueInterest() external returns (uint256);

    function seize(
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256);
}

interface CErc20 is CErc20Interface, CTokenInterface {}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

// copy from Balancer doc https://docs.balancer.finance/smart-contracts/interfaces
interface BPool {
    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 tokenAmountIn,
        uint256 tokenAmountOut
    );

    event LOG_JOIN(address indexed caller, address indexed tokenIn, uint256 tokenAmountIn);

    event LOG_EXIT(address indexed caller, address indexed tokenOut, uint256 tokenAmountOut);

    event LOG_CALL(bytes4 indexed sig, address indexed caller, bytes data);

    function isPublicSwap() external view returns (bool);

    function isFinalized() external view returns (bool);

    function isBound(address t) external view returns (bool);

    function getNumTokens() external view returns (uint256);

    function getCurrentTokens() external view returns (address[] memory tokens);

    function getFinalTokens() external view returns (address[] memory tokens);

    function getDenormalizedWeight(address token) external view returns (uint256);

    function getTotalDenormalizedWeight() external view returns (uint256);

    function getNormalizedWeight(address token) external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function getSwapFee() external view returns (uint256);

    function getController() external view returns (address);

    function setSwapFee(uint256 swapFee) external;

    function setController(address manager) external;

    function setPublicSwap(bool public_) external;

    function finalize() external;

    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external;

    function rebind(
        address token,
        uint256 balance,
        uint256 denorm
    ) external;

    function unbind(address token) external;

    function gulp(address token) external;

    function getSpotPrice(address tokenIn, address tokenOut) external view returns (uint256 spotPrice);

    function getSpotPriceSansFee(address tokenIn, address tokenOut) external view returns (uint256 spotPrice);

    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external;

    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);

    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external returns (uint256 poolAmountOut);

    function joinswapPoolAmountOut(
        address tokenIn,
        uint256 poolAmountOut,
        uint256 maxAmountIn
    ) external returns (uint256 tokenAmountIn);

    function exitswapPoolAmountIn(
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external returns (uint256 tokenAmountOut);

    function exitswapExternAmountOut(
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPoolAmountIn
    ) external returns (uint256 poolAmountIn);

    function totalSupply() external view returns (uint256);

    function balanceOf(address whom) external view returns (uint256);

    function allowance(address src, address dst) external view returns (uint256);

    function approve(address dst, uint256 amt) external returns (bool);

    function transfer(address dst, uint256 amt) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external returns (bool);

    function calcSpotPrice(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 swapFee
    ) external pure returns (uint256 spotPrice);

    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountOut);

    function calcInGivenOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 tokenAmountOut,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountIn);

    function calcPoolOutGivenSingleIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 poolAmountOut);

    function calcSingleInGivenPoolOut(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountOut,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountIn);

    function calcSingleOutGivenPoolIn(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 poolAmountIn,
        uint256 swapFee
    ) external pure returns (uint256 tokenAmountOut);

    function calcPoolInGivenSingleOut(
        uint256 tokenBalanceOut,
        uint256 tokenWeightOut,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountOut,
        uint256 swapFee
    ) external pure returns (uint256 poolAmountIn);
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { IERC20WithCheckpointing } from "./aragonone/IERC20WithCheckpointing.sol";
import { Checkpointing } from "./aragonone/Checkpointing.sol";
import { CheckpointingHelpers } from "./aragonone/CheckpointingHelpers.sol";
import { ERC20ViewOnly } from "../utils/ERC20ViewOnly.sol";
import { Decimal } from "../utils/Decimal.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";
import { BlockContext } from "../utils/BlockContext.sol";
import { PerpFiOwnableUpgrade } from "../utils/PerpFiOwnableUpgrade.sol";
import { AddressArray } from "../utils/AddressArray.sol";
import { IStakeModule } from "../interface/IStakeModule.sol";

contract StakedPerpToken is IERC20WithCheckpointing, ERC20ViewOnly, DecimalERC20, PerpFiOwnableUpgrade, BlockContext {
    using Checkpointing for Checkpointing.History;
    using CheckpointingHelpers for uint256;
    using SafeMath for uint256;
    using AddressArray for address[];

    uint256 public constant TOKEN_AMOUNT_LIMIT = 20;

    //
    // EVENTS
    //
    event Staked(address staker, uint256 amount);
    event Unstaked(address staker, uint256 amount);
    event Withdrawn(address staker, uint256 amount);
    event StakeModuleAdded(address stakedModule);
    event StakeModuleRemoved(address stakedModule);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    // ERC20 variables
    string public name;
    string public symbol;
    uint8 public decimals;
    // ERC20 variables

    // Checkpointing total supply of the deposited token
    Checkpointing.History internal totalSupplyHistory;

    // Checkpointing balances of the deposited token by staker
    mapping(address => Checkpointing.History) internal balancesHistory;

    // staker => the time staker can withdraw PERP
    mapping(address => uint256) public stakerCooldown;

    // staker => PERP staker can withdraw
    mapping(address => Decimal.decimal) public stakerWithdrawPendingBalance;

    address[] public stakeModules;
    IERC20 public perpToken;
    uint256 public cooldownPeriod;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize(IERC20 _perpToken, uint256 _cooldownPeriod) external initializer {
        require(address(_perpToken) != address(0), "Invalid input.");
        __Ownable_init();
        name = "Staked Perpetual";
        symbol = "sPERP";
        decimals = 18;
        perpToken = _perpToken;
        cooldownPeriod = _cooldownPeriod;
    }

    function stake(Decimal.decimal calldata _amount) external {
        requireNonZeroAmount(_amount);
        requireStakeModuleExisted();
        address msgSender = _msgSender();

        // copy calldata amount to memory
        Decimal.decimal memory amount = _amount;

        // stake after unstake is allowed, and the states mutated by unstake() will being undo
        if (stakerWithdrawPendingBalance[msgSender].toUint() != 0) {
            amount = amount.addD(stakerWithdrawPendingBalance[msgSender]);
            delete stakerWithdrawPendingBalance[msgSender];
            delete stakerCooldown[msgSender];
        }

        // if staking after unstaking, the amount to be transferred does not need to be updated
        _transferFrom(perpToken, msgSender, address(this), _amount);
        _mint(msgSender, amount);

        // Have to update balance first
        for (uint256 i; i < stakeModules.length; i++) {
            IStakeModule(stakeModules[i]).notifyStakeChanged(msgSender);
        }

        emit Staked(msgSender, amount.toUint());
    }

    // this function mutates stakerWithdrawPendingBalance, stakerCooldown, addTotalSupplyCheckPoint,
    // addPersonalBalanceCheckPoint, burn
    function unstake() external {
        address msgSender = _msgSender();
        requireStakeModuleExisted();
        require(stakerWithdrawPendingBalance[msgSender].toUint() == 0, "Need to withdraw first");

        Decimal.decimal memory balance = Decimal.decimal(balancesHistory[msgSender].latestValue());
        requireNonZeroAmount(balance);

        _burn(msgSender, balance);

        stakerCooldown[msgSender] = _blockTimestamp().add(cooldownPeriod);
        stakerWithdrawPendingBalance[msgSender] = balance;

        // Have to update balance first
        for (uint256 i; i < stakeModules.length; i++) {
            IStakeModule(stakeModules[i]).notifyStakeChanged(msgSender);
        }

        emit Unstaked(msgSender, balance.toUint());
    }

    function withdraw() external {
        address msgSender = _msgSender();
        Decimal.decimal memory balance = stakerWithdrawPendingBalance[msgSender];
        requireNonZeroAmount(balance);
        // there won't be a case that cooldown == 0 && balance == 0
        require(_blockTimestamp() >= stakerCooldown[msgSender], "Still in cooldown");

        delete stakerWithdrawPendingBalance[msgSender];
        delete stakerCooldown[msgSender];
        _transfer(perpToken, msgSender, balance);

        emit Withdrawn(msgSender, balance.toUint());
    }

    function addStakeModule(IStakeModule _stakeModule) external onlyOwner {
        require(stakeModules.length < TOKEN_AMOUNT_LIMIT, "exceed stakeModule amount limit");
        require(stakeModules.add(address(_stakeModule)), "invalid input");

        emit StakeModuleAdded(address(_stakeModule));
    }

    function removeStakeModule(IStakeModule _stakeModule) external onlyOwner {
        address removedAddr = stakeModules.remove(address(_stakeModule));
        require(removedAddr != address(0), "stakeModule does not exist");
        require(removedAddr == address(_stakeModule), "remove wrong stakeModule");

        emit StakeModuleRemoved(address(_stakeModule));
    }

    //
    // VIEW FUNCTIONS
    //

    //
    // override: ERC20
    //
    function balanceOf(address _owner) public view override returns (uint256) {
        return _balanceOfAt(_owner, _blockNumber()).toUint();
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupplyAt(_blockNumber()).toUint();
    }

    //
    // override: IERC20WithCheckpointing
    //
    function balanceOfAt(address _owner, uint256 __blockNumber) external view override returns (uint256) {
        return _balanceOfAt(_owner, __blockNumber).toUint();
    }

    function totalSupplyAt(uint256 __blockNumber) external view override returns (uint256) {
        return _totalSupplyAt(__blockNumber).toUint();
    }

    //
    // EXTERNAL FUNCTIONS
    //
    function getStakeModuleLength() external view returns (uint256) {
        return stakeModules.length;
    }

    //
    // INTERNAL FUNCTIONS
    //
    function isStakeModuleExisted(IStakeModule _stakeModule) public view returns (bool) {
        return stakeModules.isExisted(address(_stakeModule));
    }

    function _mint(address account, Decimal.decimal memory amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        Decimal.decimal memory balance = Decimal.decimal(balanceOf(account));
        Decimal.decimal memory newBalance = balance.addD(amount);
        Decimal.decimal memory currentTotalSupply = Decimal.decimal(totalSupply());
        Decimal.decimal memory newTotalSupply = currentTotalSupply.addD(amount);

        uint256 blockNumber = _blockNumber();
        addPersonalBalanceCheckPoint(account, blockNumber, newBalance);
        addTotalSupplyCheckPoint(blockNumber, newTotalSupply);

        emit Transfer(address(0), account, amount.toUint());
    }

    function _burn(address account, Decimal.decimal memory amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        Decimal.decimal memory balance = Decimal.decimal(balanceOf(account));
        Decimal.decimal memory newBalance = balance.subD(amount);
        Decimal.decimal memory currentTotalSupply = Decimal.decimal(totalSupply());
        Decimal.decimal memory newTotalSupply = currentTotalSupply.subD(amount);

        uint256 blockNumber = _blockNumber();
        addPersonalBalanceCheckPoint(account, blockNumber, newBalance);
        addTotalSupplyCheckPoint(blockNumber, newTotalSupply);

        emit Transfer(account, address(0), amount.toUint());
    }

    function addTotalSupplyCheckPoint(uint256 __blockNumber, Decimal.decimal memory _amount) internal {
        totalSupplyHistory.addCheckpoint(__blockNumber.toUint64Time(), _amount.toUint().toUint192Value());
    }

    function addPersonalBalanceCheckPoint(
        address _staker,
        uint256 __blockNumber,
        Decimal.decimal memory _amount
    ) internal {
        balancesHistory[_staker].addCheckpoint(__blockNumber.toUint64Time(), _amount.toUint().toUint192Value());
    }

    function _balanceOfAt(address _owner, uint256 __blockNumber) internal view returns (Decimal.decimal memory) {
        return Decimal.decimal(balancesHistory[_owner].getValueAt(__blockNumber.toUint64Time()));
    }

    function _totalSupplyAt(uint256 __blockNumber) internal view returns (Decimal.decimal memory) {
        return Decimal.decimal(totalSupplyHistory.getValueAt(__blockNumber.toUint64Time()));
    }

    //
    // REQUIRE FUNCTIONS
    //
    function requireNonZeroAmount(Decimal.decimal memory _amount) private pure {
        require(_amount.toUint() > 0, "Amount is 0");
    }

    function requireStakeModuleExisted() internal view {
        require(stakeModules.length > 0, "no stakeModule");
    }
}

// source: https://github.com/aragonone/voting-connectors/blob/master/shared/contract-utils/contracts/interfaces/IERC20WithCheckpointing.sol

/*
 * SPDX-License-Identitifer:    GPL-3.0-or-later
 */

pragma solidity 0.6.9;

interface IERC20WithCheckpointing {
    function balanceOfAt(address _owner, uint256 _blockNumber) external view returns (uint256);

    function totalSupplyAt(uint256 _blockNumber) external view returns (uint256);
}

// source: https://github.com/aragonone/voting-connectors/blob/master/shared/contract-utils/contracts/Checkpointing.sol

/*
 * SPDX-License-Identitifer:    GPL-3.0-or-later
 */

pragma solidity 0.6.9;

/**
 * @title Checkpointing
 * @notice Checkpointing library for keeping track of historical values based on an arbitrary time
 *         unit (e.g. seconds or block numbers).
 * @dev Inspired by:
 *   - MiniMe token (https://github.com/aragon/minime/blob/master/contracts/MiniMeToken.sol)
 *   - Staking (https://github.com/aragon/staking/blob/master/contracts/Checkpointing.sol)
 */
library Checkpointing {
    string private constant ERROR_PAST_CHECKPOINT = "CHECKPOINT_PAST_CHECKPOINT";

    struct Checkpoint {
        uint64 time;
        uint192 value;
    }

    struct History {
        Checkpoint[] history;
    }

    function addCheckpoint(
        History storage _self,
        uint64 _time,
        uint192 _value
    ) internal {
        uint256 length = _self.history.length;
        if (length == 0) {
            _self.history.push(Checkpoint(_time, _value));
        } else {
            Checkpoint storage currentCheckpoint = _self.history[length - 1];
            uint256 currentCheckpointTime = uint256(currentCheckpoint.time);

            if (_time > currentCheckpointTime) {
                _self.history.push(Checkpoint(_time, _value));
            } else if (_time == currentCheckpointTime) {
                currentCheckpoint.value = _value;
            } else {
                // ensure list ordering
                revert(ERROR_PAST_CHECKPOINT);
            }
        }
    }

    function getValueAt(History storage _self, uint64 _time) internal view returns (uint256) {
        return _getValueAt(_self, _time);
    }

    function lastUpdated(History storage _self) internal view returns (uint256) {
        uint256 length = _self.history.length;
        if (length > 0) {
            return uint256(_self.history[length - 1].time);
        }

        return 0;
    }

    function latestValue(History storage _self) internal view returns (uint256) {
        uint256 length = _self.history.length;
        if (length > 0) {
            return uint256(_self.history[length - 1].value);
        }

        return 0;
    }

    function _getValueAt(History storage _self, uint64 _time) private view returns (uint256) {
        uint256 length = _self.history.length;

        // Short circuit if there's no checkpoints yet
        // Note that this also lets us avoid using SafeMath later on, as we've established that
        // there must be at least one checkpoint
        if (length == 0) {
            return 0;
        }

        // Check last checkpoint
        uint256 lastIndex = length - 1;
        Checkpoint storage lastCheckpoint = _self.history[lastIndex];
        if (_time >= lastCheckpoint.time) {
            return uint256(lastCheckpoint.value);
        }

        // Check first checkpoint (if not already checked with the above check on last)
        if (length == 1 || _time < _self.history[0].time) {
            return 0;
        }

        // Do binary search
        // As we've already checked both ends, we don't need to check the last checkpoint again
        uint256 low = 0;
        uint256 high = lastIndex - 1;

        while (high > low) {
            uint256 mid = (high + low + 1) / 2; // average, ceil round
            Checkpoint storage checkpoint = _self.history[mid];
            uint64 midTime = checkpoint.time;

            if (_time > midTime) {
                low = mid;
            } else if (_time < midTime) {
                // Note that we don't need SafeMath here because mid must always be greater than 0
                // from the while condition
                high = mid - 1;
            } else {
                // _time == midTime
                return uint256(checkpoint.value);
            }
        }

        return uint256(_self.history[low].value);
    }
}

// source: https://github.com/aragonone/voting-connectors/blob/master/shared/contract-utils/contracts/CheckpointingHelpers.sol

pragma solidity 0.6.9;

library CheckpointingHelpers {
    uint256 private constant MAX_UINT64 = uint64(-1);
    uint256 private constant MAX_UINT192 = uint192(-1);

    string private constant ERROR_UINT64_TOO_BIG = "UINT64_NUMBER_TOO_BIG";
    string private constant ERROR_UINT192_TOO_BIG = "UINT192_NUMBER_TOO_BIG";

    function toUint64Time(uint256 _a) internal pure returns (uint64) {
        require(_a <= MAX_UINT64, ERROR_UINT64_TOO_BIG);
        return uint64(_a);
    }

    function toUint192Value(uint256 _a) internal pure returns (uint192) {
        require(_a <= MAX_UINT192, ERROR_UINT192_TOO_BIG);
        return uint192(_a);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

abstract contract ERC20ViewOnly is IERC20 {
    function transfer(address, uint256) public virtual override returns (bool) {
        revert("transfer() is not supported");
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public virtual override returns (bool) {
        revert("transferFrom() is not supported");
    }

    function approve(address, uint256) public virtual override returns (bool) {
        revert("approve() is not supported");
    }

    function allowance(address, address) public view virtual override returns (uint256) {
        return 0;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

interface IStakeModule {
    function notifyStakeChanged(address staker) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../staking/StakedPerpToken.sol";

contract StakedPerpTokenFake is StakedPerpToken {
    uint256 private timestamp = 1444004400;
    uint256 private number = 2444004400;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    function mock_getCurrentBlockNumber() public view returns (uint256) {
        return _blockNumber();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IStakeModule } from "../../interface/IStakeModule.sol";
import { IRewardRecipient } from "../../interface/IRewardRecipient.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Decimal } from "../../utils/Decimal.sol";

contract FeeRewardPoolMock is IStakeModule, IRewardRecipient {
    using Decimal for Decimal.decimal;
    event NotificationReceived(address staker);
    event FeeNotificationReceived(uint256 amount);

    IERC20 public override token;

    function notifyStakeChanged(address staker) external override {
        emit NotificationReceived(staker);
    }

    function notifyRewardAmount(Decimal.decimal calldata _amount) external override {
        emit FeeNotificationReceived(_amount.toUint());
    }

    function setToken(address _token) public {
        token = IERC20(_token);
    }
}

// source: https://github.com/k06a/Unipool/blob/master/contracts/Unipool.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { Math } from "@openzeppelin/contracts-ethereum-package/contracts/math/Math.sol";
import { PerpFiOwnableUpgrade } from "../utils/PerpFiOwnableUpgrade.sol";
import { Decimal } from "../utils/Decimal.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";
import { BlockContext } from "../utils/BlockContext.sol";
import { IRewardRecipient } from "../interface/IRewardRecipient.sol";
import { StakedPerpToken } from "../staking/StakedPerpToken.sol";
import { IStakeModule } from "../interface/IStakeModule.sol";

contract FeeRewardPoolL1 is IStakeModule, IRewardRecipient, PerpFiOwnableUpgrade, BlockContext, DecimalERC20 {
    using Decimal for Decimal.decimal;
    using SafeMath for uint256;

    uint256 public constant DURATION = 1 days;

    //
    // EVENTS
    //
    event RewardWithdrawn(address indexed staker, uint256 amount);
    event RewardTransferred(uint256 amount);

    //
    // MODIFIER
    //

    modifier onlyStakedPerpToken() virtual {
        require(_msgSender() == address(stakedPerpToken), "only sPerpToken");
        _;
    }

    modifier onlyFeeTokenPoolDispatcher() {
        require(_msgSender() == feeTokenPoolDispatcher, "only feeTokenPoolDispatcher");
        _;
    }

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    mapping(address => Decimal.decimal) public userRewardPerTokenPaid;
    // the actual amount of rewards a staker can get
    mapping(address => Decimal.decimal) public rewards;

    // the multiplier that implies how much rewards a staked token can get
    Decimal.decimal public rewardPerTokenStored;
    // reward rate per second
    Decimal.decimal public rewardRate;

    // last reward notified time
    uint256 public lastUpdateTime;
    uint256 public periodFinish;

    address public feeTokenPoolDispatcher;
    StakedPerpToken public stakedPerpToken;
    IERC20 public override token;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variable, ables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize(
        IERC20 _token,
        StakedPerpToken _stakedPerpToken,
        address _feeTokenPoolDispatcher
    ) external initializer {
        require(address(_stakedPerpToken) != address(0), "Invalid input");
        __Ownable_init();
        stakedPerpToken = _stakedPerpToken;
        feeTokenPoolDispatcher = _feeTokenPoolDispatcher;
        token = _token;
    }

    function notifyStakeChanged(address _staker) external override onlyStakedPerpToken {
        updateReward(_staker);
    }

    function withdrawReward() external {
        address msgSender = _msgSender();
        updateReward(msgSender);
        Decimal.decimal memory reward = rewards[msgSender];
        require(reward.toUint() > 0, "reward is 0");

        rewards[msgSender] = Decimal.zero();
        _transfer(token, msgSender, reward);
        emit RewardWithdrawn(msgSender, reward.toUint());
    }

    // assume DURATION = 1 day, (existing) rewardRate = 1, and new incoming _reward = 2
    function notifyRewardAmount(Decimal.decimal calldata _reward) external override onlyFeeTokenPoolDispatcher {
        require(_reward.toUint() > 0, "invalid input");

        updateReward(address(0));
        uint256 timestamp = _blockTimestamp();
        // there is no reward during the interval after the end of the previous period and before new rewards arrive
        if (timestamp >= periodFinish) {
            // rewardRate = 2/1 = 2
            rewardRate = _reward.divScalar(DURATION);
        } else {
            // assume half a day left in the current period, thus remainingTime = 0.5 days
            // leftover = 1 * 0.5 = 0.5
            // rewardRate = (2 + 0.5) / 1 ~= 2.5
            uint256 remainingTime = periodFinish.sub(timestamp);
            Decimal.decimal memory leftover = rewardRate.mulScalar(remainingTime);
            rewardRate = _reward.addD(leftover).divScalar(DURATION);
        }

        // new period starts from now
        lastUpdateTime = timestamp;
        periodFinish = lastUpdateTime.add(DURATION);
        emit RewardTransferred(_reward.toUint());
    }

    //
    // VIEW FUNCTIONS
    //

    function earned(address _staker) public view returns (Decimal.decimal memory) {
        return balanceOf(_staker).mulD(rewardPerToken().subD(userRewardPerTokenPaid[_staker])).addD(rewards[_staker]);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(_blockTimestamp(), periodFinish);
    }

    function rewardPerToken() public view returns (Decimal.decimal memory) {
        Decimal.decimal memory totalSupply = totalSupply();
        if (totalSupply.toUint() == 0) {
            return rewardPerTokenStored;
        }
        // lastUpdateTime = 100 (last time notifyRewardAmount())
        // lastTimeRewardApplicable() = min(timestamp = now, periodFinish = lastUpdateTime.add(DURATION)) = depends

        uint256 timeInterval = lastTimeRewardApplicable().sub(lastUpdateTime);
        return rewardPerTokenStored.addD(rewardRate.divD(totalSupply).mulScalar(timeInterval));
    }

    //
    // INTERNAL
    //

    function updateReward(address _staker) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_staker != address(0)) {
            rewards[_staker] = earned(_staker);
            userRewardPerTokenPaid[_staker] = rewardPerTokenStored;
        }
    }

    function balanceOf(address _staker) internal view returns (Decimal.decimal memory) {
        return Decimal.decimal(stakedPerpToken.balanceOf(_staker));
    }

    function totalSupply() internal view returns (Decimal.decimal memory) {
        return Decimal.decimal(stakedPerpToken.totalSupply());
    }
}

pragma solidity ^0.6.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { ContextUpgradeSafe } from "@openzeppelin/contracts-ethereum-package/contracts/GSN/Context.sol";
import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import { Address } from "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

// TODO rename to ERC20NoDecimal
contract ERC20MinimalFake is Initializable, ContextUpgradeSafe, IERC20 {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    function initializeERC20MinimalFake(uint256 initialSupply) public initializer {
        __Context_init_unchained();
        _mint(_msgSender(), initialSupply);
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */

    function balanceOf(address account) public view override returns (uint256) {
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
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
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
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
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
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
        );
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
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
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
     * Requirements
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
     * Requirements
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
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
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
        require(_allowances[owner][spender] == 0 || amount == 0, "ERC20: approve non zero amount");

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
     * will be to transferred to `to`.
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

    uint256[44] private __gap;
}

pragma solidity ^0.6.2;

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
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
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
}

pragma solidity ^0.6.0;

import "../../GSN/Context.sol";
import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";
import "../../Initializable.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20MinterPauser}.
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
contract ERC20UpgradeSafe is Initializable, ContextUpgradeSafe, IERC20 {
    using SafeMath for uint256;
    using Address for address;

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

    function __ERC20_init(string memory name, string memory symbol) internal initializer {
        __Context_init_unchained();
        __ERC20_init_unchained(name, symbol);
    }

    function __ERC20_init_unchained(string memory name, string memory symbol) internal initializer {


        _name = name;
        _symbol = symbol;
        _decimals = 18;

    }


    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
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
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
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
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
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
     * Requirements
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
     * Requirements
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
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
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
    function _setupDecimals(uint8 decimals_) internal {
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

    uint256[44] private __gap;
}

pragma solidity ^0.6.0;

import "./ERC20.sol";
import "../../utils/Pausable.sol";
import "../../Initializable.sol";

/**
 * @dev ERC20 token with pausable token transfers, minting and burning.
 *
 * Useful for scenarios such as preventing trades until the end of an evaluation
 * period, or having an emergency switch for freezing all token transfers in the
 * event of a large bug.
 */
abstract contract ERC20PausableUpgradeSafe is Initializable, ERC20UpgradeSafe, PausableUpgradeSafe {
    function __ERC20Pausable_init() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
        __ERC20Pausable_init_unchained();
    }

    function __ERC20Pausable_init_unchained() internal initializer {


    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - the contract must not be paused.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), "ERC20Pausable: token transfer while paused");
    }

    uint256[50] private __gap;
}

pragma solidity 0.6.9;

import { Initializable } from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract UpgradableContractV2 is Initializable {
    uint256 public version;
    address public owner;

    function initialize() public initializer {
        // won't execute because this contract has been already initialized in v1
        version = 2;
        owner = msg.sender;
    }

    function increaseVersion() external {
        version += 1;
    }
}

pragma solidity 0.6.9;

import { Initializable } from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract UpgradableContractV1 is Initializable {
    uint256 public version;
    address public owner;

    function initialize() public initializer {
        version = 1;
        owner = msg.sender;
    }
}

pragma solidity ^0.6.0;

import "../../GSN/Context.sol";
import "./ERC20.sol";
import "../../Initializable.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC20BurnableUpgradeSafe is Initializable, ContextUpgradeSafe, ERC20UpgradeSafe {
    function __ERC20Burnable_init() internal initializer {
        __Context_init_unchained();
        __ERC20Burnable_init_unchained();
    }

    function __ERC20Burnable_init_unchained() internal initializer {


    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual {
        uint256 decreasedAllowance = allowance(account, _msgSender()).sub(amount, "ERC20: burn amount exceeds allowance");

        _approve(account, _msgSender(), decreasedAllowance);
        _burn(account, amount);
    }

    uint256[50] private __gap;
}

pragma solidity ^0.6.0;

import "../utils/EnumerableSet.sol";
import "../utils/Address.sol";
import "../GSN/Context.sol";
import "../Initializable.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms.
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
 *     require(hasRole(MY_ROLE, _msgSender()));
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
 */
abstract contract AccessControlUpgradeSafe is Initializable, ContextUpgradeSafe {
    function __AccessControl_init() internal initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
    }

    function __AccessControl_init_unchained() internal initializer {


    }

    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    struct RoleData {
        EnumerableSet.AddressSet members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

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
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return _roles[role].members.length();
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
        return _roles[role].members.at(index);
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
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
    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to grant");

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
    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to revoke");

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
    function renounceRole(bytes32 role, address account) public virtual {
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
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (_roles[role].members.add(account)) {
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (_roles[role].members.remove(account)) {
            emit RoleRevoked(role, account, _msgSender());
        }
    }

    uint256[49] private __gap;
}

pragma solidity ^0.6.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.0.0, only sets of type `address` (`AddressSet`) and `uint256`
 * (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint256(_at(set._inner, index)));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

pragma solidity ^0.6.0;

import "../access/AccessControl.sol";
import "../GSN/Context.sol";
import "../token/ERC20/ERC20.sol";
import "../token/ERC20/ERC20Burnable.sol";
import "../token/ERC20/ERC20Pausable.sol";
import "../Initializable.sol";

/**
 * @dev {ERC20} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to aother accounts
 */
contract ERC20PresetMinterPauserUpgradeSafe is Initializable, ContextUpgradeSafe, AccessControlUpgradeSafe, ERC20BurnableUpgradeSafe, ERC20PausableUpgradeSafe {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     *
     * See {ERC20-constructor}.
     */

    function initialize(string memory name, string memory symbol) public {
        __ERC20PresetMinterPauser_init(name, symbol);
    }

    function __ERC20PresetMinterPauser_init(string memory name, string memory symbol) internal initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __ERC20_init_unchained(name, symbol);
        __ERC20Burnable_init_unchained();
        __Pausable_init_unchained();
        __ERC20Pausable_init_unchained();
        __ERC20PresetMinterPauser_init_unchained(name, symbol);
    }

    function __ERC20PresetMinterPauser_init_unchained(string memory name, string memory symbol) internal initializer {


        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());

    }


    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        _mint(to, amount);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have pauser role to pause");
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have pauser role to unpause");
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20UpgradeSafe, ERC20PausableUpgradeSafe) {
        super._beforeTokenTransfer(from, to, amount);
    }

    uint256[50] private __gap;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {
    ERC20PresetMinterPauserUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/presets/ERC20PresetMinterPauser.sol";

// TODO rename to UpgradableMintableERC20
contract ERC20Fake is ERC20PresetMinterPauserUpgradeSafe {
    function initializeERC20Fake(
        uint256 initialSupply,
        string memory name,
        string memory symbol,
        uint8 decimal
    ) public initializer {
        ERC20PresetMinterPauserUpgradeSafe.initialize(name, symbol);
        _setupDecimals(decimal);
        _mint(_msgSender(), initialSupply);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { ERC20Fake } from "../ERC20Fake.sol";

contract CUsdtMock is ERC20Fake {
    address underlyingAddr;

    function underlying() external view returns (address) {
        return underlyingAddr;
    }

    function mockSetUnderlying(address _underlying) external {
        underlyingAddr = _underlying;
    }

    uint256 exchangeRate = 1e16;

    function exchangeRateStored() external view returns (uint256) {
        return exchangeRate;
    }

    function mockSetExchangeRateStored(uint256 _exchangeRate) external {
        exchangeRate = _exchangeRate;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { LowLevelErrorMessage } from "./utils/LowLevelErrorMessage.sol";

// this is functionally identical to https://github.com/bcnmy/metatx-standard/blob/master/src/contracts/EIP712MetaTransaction.sol
// except it implements openzeppelin Initializable
contract MetaTxGateway is PerpFiOwnableUpgrade, LowLevelErrorMessage {
    using SafeMath for uint256;

    //
    // EVENTS
    //
    event MetaTransactionExecuted(address from, address to, address payable relayerAddress, bytes functionSignature);

    //
    // Struct and Enum
    //
    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    /*
     * Meta transaction structure.
     * No point of including value field here as if user is doing value transfer then he has the funds to pay for gas
     * He should call the desired function directly in that case.
     */
    struct MetaTransaction {
        uint256 nonce;
        address from;
        address to;
        bytes functionSignature;
    }

    //
    // Constant
    //
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));

    bytes32 private constant META_TRANSACTION_TYPEHASH =
        keccak256(bytes("MetaTransaction(uint256 nonce,address from,address to,bytes functionSignature)"));

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//

    bytes32 internal domainSeperatorL1;
    bytes32 internal domainSeperatorL2;
    mapping(address => uint256) private nonces;

    // whitelist of contracts this gateway can execute
    mapping(address => bool) private whitelistMap;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize(
        string memory _name,
        string memory _version,
        uint256 _chainIdL1
    ) public initializer {
        __Ownable_init();

        domainSeperatorL1 = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(_name)),
                keccak256(bytes(_version)),
                _chainIdL1,
                address(this)
            )
        );

        domainSeperatorL2 = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(_name)),
                keccak256(bytes(_version)),
                getChainID(),
                address(this)
            )
        );
    }

    /**
     * @notice add an address to the whitelist. Only contracts in the whitelist can be executed by this gateway.
     *         This prevents the gateway from being abused to execute arbitrary meta txs
     * @dev only owner can call
     * @param _addr an address
     */
    function addToWhitelists(address _addr) external onlyOwner {
        whitelistMap[_addr] = true;
    }

    function removeFromWhitelists(address _addr) external onlyOwner {
        delete whitelistMap[_addr];
    }

    function executeMetaTransaction(
        address from,
        address to,
        bytes calldata functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) external returns (bytes memory) {
        require(isInWhitelists(to), "!whitelisted");

        MetaTransaction memory metaTx =
            MetaTransaction({ nonce: nonces[from], from: from, to: to, functionSignature: functionSignature });

        require(
            verify(from, domainSeperatorL1, metaTx, sigR, sigS, sigV) ||
                verify(from, domainSeperatorL2, metaTx, sigR, sigS, sigV),
            "Meta tx Signer and signature do not match"
        );

        nonces[from] = nonces[from].add(1);
        // Append userAddress at the end to extract it from calling context
        // solhint-disable avoid-low-level-calls
        (bool success, bytes memory returnData) = address(to).call(abi.encodePacked(functionSignature, from));
        require(success, _getRevertMessage(returnData));
        emit MetaTransactionExecuted(from, to, msg.sender, functionSignature);
        return returnData;
    }

    //
    // VIEW FUNCTIONS
    //

    function getNonce(address user) external view returns (uint256 nonce) {
        nonce = nonces[user];
    }

    //
    // INTERNAL VIEW FUNCTIONS
    //

    function isInWhitelists(address _addr) public view returns (bool) {
        return whitelistMap[_addr];
    }

    function getChainID() internal pure returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    /**
     * Accept message hash and returns hash message in EIP712 compatible form
     * So that it can be used to recover signer from signature signed using EIP712 formatted data
     * https://eips.ethereum.org/EIPS/eip-712
     * "\\x19" makes the encoding deterministic
     * "\\x01" is the version byte to make it compatible to EIP-191
     */
    function toTypedMessageHash(bytes32 domainSeperator, bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeperator, messageHash));
    }

    function hashMetaTransaction(MetaTransaction memory metaTx) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    META_TRANSACTION_TYPEHASH,
                    metaTx.nonce,
                    metaTx.from,
                    metaTx.to,
                    keccak256(metaTx.functionSignature)
                )
            );
    }

    function verify(
        address user,
        bytes32 domainSeperator,
        MetaTransaction memory metaTx,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) internal pure returns (bool) {
        address signer = ecrecover(toTypedMessageHash(domainSeperator, hashMetaTransaction(metaTx)), sigV, sigR, sigS);
        require(signer != address(0), "invalid signature");
        return signer == user;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

abstract contract LowLevelErrorMessage {
    using BytesLib for bytes;

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    function _getRevertMessage(bytes memory _res) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_res.length < 68) return "Transaction reverted silently";
        bytes memory revertData = _res.slice(4, _res.length - 4); // Remove the selector which is the first 4 bytes
        return abi.decode(revertData, (string)); // All that remains is the revert string
    }
}

// SPDX-License-Identifier: Unlicense
/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <[email protected]>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */
pragma solidity >=0.5.0 <0.7.0;


library BytesLib {
    function concat(
        bytes memory _preBytes,
        bytes memory _postBytes
    )
        internal
        pure
        returns (bytes memory)
    {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(0x40, and(
              add(add(end, iszero(add(length, mload(_preBytes)))), 31),
              not(31) // Round down to the nearest 32 bytes.
            ))
        }

        return tempBytes;
    }

    function concatStorage(bytes storage _preBytes, bytes memory _postBytes) internal {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes_slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                // Since the new array still fits in the slot, we just need to
                // update the contents of the slot.
                // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                sstore(
                    _preBytes_slot,
                    // all the modifications to the slot are inside this
                    // next block
                    add(
                        // we can just add to the slot contents because the
                        // bytes we want to change are the LSBs
                        fslot,
                        add(
                            mul(
                                div(
                                    // load the bytes from memory
                                    mload(add(_postBytes, 0x20)),
                                    // zero all bytes to the right
                                    exp(0x100, sub(32, mlength))
                                ),
                                // and now shift left the number of bytes to
                                // leave space for the length in the slot
                                exp(0x100, sub(32, newlength))
                            ),
                            // increase length by the double of the memory
                            // bytes length
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                // The stored value fits in the slot, but the combined value
                // will exceed it.
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes_slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                // The contents of the _postBytes array start 32 bytes into
                // the structure. Our first read should obtain the `submod`
                // bytes that can fit into the unused space in the last word
                // of the stored array. To get this, we read 32 bytes starting
                // from `submod`, so the data we read overlaps with the array
                // contents by `submod` bytes. Masking the lowest-order
                // `submod` bytes allows us to add that value directly to the
                // stored value.

                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(
                    sc,
                    add(
                        and(
                            fslot,
                            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00
                        ),
                        and(mload(mc), mask)
                    )
                )

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes_slot)
                // Start copying to the last used word of the stored array.
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                // Copy over the first `submod` bytes of the new data as in
                // case 1 above.
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))

                for {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
    )
        internal
        pure
        returns (bytes memory)
    {
        require(_length + 31 >= _length, "slice_overflow");
        require(_start + _length >= _start, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, "toAddress_overflow");
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_start + 1 >= _start, "toUint8_overflow");
        require(_bytes.length >= _start + 1 , "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint256 _start) internal pure returns (uint16) {
        require(_start + 2 >= _start, "toUint16_overflow");
        require(_bytes.length >= _start + 2, "toUint16_outOfBounds");
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint256 _start) internal pure returns (uint32) {
        require(_start + 4 >= _start, "toUint32_overflow");
        require(_bytes.length >= _start + 4, "toUint32_outOfBounds");
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint64(bytes memory _bytes, uint256 _start) internal pure returns (uint64) {
        require(_start + 8 >= _start, "toUint64_overflow");
        require(_bytes.length >= _start + 8, "toUint64_outOfBounds");
        uint64 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x8), _start))
        }

        return tempUint;
    }

    function toUint96(bytes memory _bytes, uint256 _start) internal pure returns (uint96) {
        require(_start + 12 >= _start, "toUint96_overflow");
        require(_bytes.length >= _start + 12, "toUint96_outOfBounds");
        uint96 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xc), _start))
        }

        return tempUint;
    }

    function toUint128(bytes memory _bytes, uint256 _start) internal pure returns (uint128) {
        require(_start + 16 >= _start, "toUint128_overflow");
        require(_bytes.length >= _start + 16, "toUint128_outOfBounds");
        uint128 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x10), _start))
        }

        return tempUint;
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_start + 32 >= _start, "toUint256_overflow");
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint256 _start) internal pure returns (bytes32) {
        require(_start + 32 >= _start, "toBytes32_overflow");
        require(_bytes.length >= _start + 32, "toBytes32_outOfBounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            // if lengths don't match the arrays are not equal
            switch eq(length, mload(_postBytes))
            case 1 {
                // cb is a circuit breaker in the for loop since there's
                //  no said feature for inline assembly loops
                // cb = 1 - don't breaker
                // cb = 0 - break
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for {
                    let cc := add(_postBytes, 0x20)
                // the next line is the loop condition:
                // while(uint256(mc < end) + cb == 2)
                } eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // if any of these checks fails then arrays are not equal
                    if iszero(eq(mload(mc), mload(cc))) {
                        // unsuccess:
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }

    function equalStorage(
        bytes storage _preBytes,
        bytes memory _postBytes
    )
        internal
        view
        returns (bool)
    {
        bool success = true;

        assembly {
            // we know _preBytes_offset is 0
            let fslot := sload(_preBytes_slot)
            // Decode the length of the stored array like in concatStorage().
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)

            // if lengths don't match the arrays are not equal
            switch eq(slength, mlength)
            case 1 {
                // slength can contain both the length and contents of the array
                // if length < 32 bytes so let's prepare for that
                // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        // blank the last byte which is the length
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            // unsuccess:
                            success := 0
                        }
                    }
                    default {
                        // cb is a circuit breaker in the for loop since there's
                        //  no said feature for inline assembly loops
                        // cb = 1 - don't breaker
                        // cb = 0 - break
                        let cb := 1

                        // get the keccak hash to get the contents of the array
                        mstore(0x0, _preBytes_slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        // the next line is the loop condition:
                        // while(uint256(mc < end) + cb == 2)
                        for {} eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                // unsuccess:
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../staking/FeeRewardPoolL1.sol";

contract FeeRewardPoolL1Fake is FeeRewardPoolL1 {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    address public stakedPerpTokenAddr;

    modifier onlyStakedPerpToken() override {
        require(msg.sender == stakedPerpTokenAddr, "only FeeTokenPoolDispatcherL1");
        _;
    }

    function mock_setStakedPerpTokenAddr(address _stakedPerpTokenAddr) public {
        stakedPerpTokenAddr = _stakedPerpTokenAddr;
    }

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    function mock_getCurrentBlockNumber() public view returns (uint256) {
        return _blockNumber();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { DecimalERC20 } from "../utils/DecimalERC20.sol";
import { Decimal } from "../utils/Decimal.sol";

// a testing purpose container contract which used DecimalERC20 library
contract DecimalERC20Fake is DecimalERC20 {
    function transfer(
        IERC20 _token,
        address _receiver,
        Decimal.decimal calldata _amount
    ) external {
        _transfer(_token, _receiver, _amount);
    }

    function transferFrom(
        IERC20 _token,
        address _sender,
        address _receiver,
        Decimal.decimal calldata _amount
    ) external {
        _transferFrom(_token, _sender, _receiver, _amount);
    }

    function approve(
        IERC20 _token,
        address _spender,
        Decimal.decimal calldata _amount
    ) external {
        _approve(_token, _spender, _amount);
    }

    function allowance(
        IERC20 _token,
        address _owner,
        address _spender
    ) external view returns (Decimal.decimal memory) {
        return _allowance(_token, _owner, _spender);
    }

    function balanceOf(IERC20 _token, address _owner) external view returns (Decimal.decimal memory) {
        return _balanceOf(_token, _owner);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../RewardsDistribution.sol";

contract RewardsDistributionFake is RewardsDistribution {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import { KeeperRewardBase } from "./KeeperRewardBase.sol";
import { ChainlinkL1 } from "../ChainlinkL1.sol";

contract KeeperRewardL1 is KeeperRewardBase {
    function initialize(IERC20 _perpToken) external initializer {
        __BaseKeeperReward_init(_perpToken);
    }

    /**
     * @notice call this function to update price feed and get token reward
     */
    function updatePriceFeed(bytes32 _priceFeedKey) external {
        bytes4 selector = ChainlinkL1.updateLatestRoundData.selector;
        TaskInfo memory task = getTaskInfo(selector);

        ChainlinkL1(task.contractAddr).updateLatestRoundData(_priceFeedKey);
        postTaskAction(selector);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { Decimal, SafeMath } from "./utils/Decimal.sol";

contract ChainlinkL1 is IPriceFeed, PerpFiOwnableUpgrade, BlockContext {
    using SafeMath for uint256;
    using Decimal for Decimal.decimal;

    struct PriceData {
        uint256 roundId;
        uint256 price;
        uint256 timestamp;
    }

    struct PriceFeed {
        bool registered;
        PriceData[] priceData;
    }

    uint256 private constant TOKEN_DIGIT = 10**18;

    event PriceFeedDataSet(bytes32 key, uint256 price, uint256 timestamp, uint256 roundId);

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    // key by currency symbol, eg ETH
    mapping(bytes32 => AggregatorV3Interface) public priceFeedInterfaceMap;
    mapping(bytes32 => PriceFeed) public priceFeedMap;
    bytes32[] public priceFeedKeys;
    mapping(bytes32 => uint256) public prevTimestampMap;

    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize() public initializer {
        __Ownable_init();
    }

    function addAggregator(bytes32 _priceFeedKey, address _aggregator) external onlyOwner {
        requireNonEmptyAddress(_aggregator);
        if (address(priceFeedInterfaceMap[_priceFeedKey]) == address(0)) {
            priceFeedKeys.push(_priceFeedKey);
        }
        priceFeedMap[_priceFeedKey].registered = true;
        priceFeedInterfaceMap[_priceFeedKey] = AggregatorV3Interface(_aggregator);
    }

    function removeAggregator(bytes32 _priceFeedKey) external onlyOwner {
        requireNonEmptyAddress(address(getAggregator(_priceFeedKey)));
        delete priceFeedInterfaceMap[_priceFeedKey];
        delete priceFeedMap[_priceFeedKey];

        uint256 length = priceFeedKeys.length;
        for (uint256 i; i < length; i++) {
            if (priceFeedKeys[i] == _priceFeedKey) {
                // if the removal item is the last one, just `pop`
                if (i != length - 1) {
                    priceFeedKeys[i] = priceFeedKeys[length - 1];
                }
                priceFeedKeys.pop();
                break;
            }
        }
    }

    function getAggregator(bytes32 _priceFeedKey) public view returns (AggregatorV3Interface) {
        return priceFeedInterfaceMap[_priceFeedKey];
    }

    //
    // INTERFACE IMPLEMENTATION
    //

    function updateLatestRoundData(bytes32 _priceFeedKey) external {
        AggregatorV3Interface aggregator = getAggregator(_priceFeedKey);
        requireNonEmptyAddress(address(aggregator));

        (uint80 roundId, int256 price, , uint256 timestamp, ) = aggregator.latestRoundData();
        require(timestamp > prevTimestampMap[_priceFeedKey], "incorrect timestamp");
        require(price >= 0, "negative answer");

        uint8 decimals = aggregator.decimals();

        Decimal.decimal memory decimalPrice = Decimal.decimal(formatDecimals(uint256(price), decimals));

        uint256 _price = decimalPrice.toUint();

        requireKeyExisted(_priceFeedKey, true);

        PriceData memory data = PriceData({ price: _price, timestamp: timestamp, roundId: roundId });
        priceFeedMap[_priceFeedKey].priceData.push(data);

        emit PriceFeedDataSet(_priceFeedKey, _price, timestamp, roundId);

        prevTimestampMap[_priceFeedKey] = timestamp;
    }

    //
    // REQUIRE FUNCTIONS
    //

    function requireNonEmptyAddress(address _addr) internal pure {
        require(_addr != address(0), "empty address");
    }

    //
    // INTERNAL VIEW FUNCTIONS
    //
    function formatDecimals(uint256 _price, uint8 _decimals) internal pure returns (uint256) {
        return _price.mul(TOKEN_DIGIT).div(10**uint256(_decimals));
    }

    function getPrice(bytes32 _priceFeedKey) external view override returns (uint256) {
        require(isExistedKey(_priceFeedKey), "key not existed");
        uint256 len = getPriceFeedLength(_priceFeedKey);
        require(len > 0, "no price data");
        return priceFeedMap[_priceFeedKey].priceData[len - 1].price;
    }

    function getLatestTimestamp(bytes32 _priceFeedKey) public view override returns (uint256) {
        require(isExistedKey(_priceFeedKey), "key not existed");
        uint256 len = getPriceFeedLength(_priceFeedKey);
        if (len == 0) {
            return 0;
        }
        return priceFeedMap[_priceFeedKey].priceData[len - 1].timestamp;
    }

    function getTwapPrice(bytes32 _priceFeedKey, uint256 _interval) external view override returns (uint256) {
        require(isExistedKey(_priceFeedKey), "key not existed");
        require(_interval != 0, "interval can't be 0");

        // ** We assume L1 and L2 timestamp will be very similar here **
        // 3 different timestamps, `previous`, `current`, `target`
        // `base` = now - _interval
        // `current` = current round timestamp from aggregator
        // `previous` = previous round timestamp form aggregator
        // now >= previous > current > = < base
        //
        //  while loop i = 0
        //  --+------+-----+-----+-----+-----+-----+
        //         base                 current  now(previous)
        //
        //  while loop i = 1
        //  --+------+-----+-----+-----+-----+-----+
        //         base           current previous now

        uint256 len = getPriceFeedLength(_priceFeedKey);
        require(len > 0, "Not enough history");
        uint256 round = len - 1;
        PriceData memory priceRecord = priceFeedMap[_priceFeedKey].priceData[round];
        uint256 latestTimestamp = priceRecord.timestamp;
        uint256 baseTimestamp = _blockTimestamp().sub(_interval);
        // if latest updated timestamp is earlier than target timestamp, return the latest price.
        if (latestTimestamp < baseTimestamp || round == 0) {
            return priceRecord.price;
        }

        // rounds are like snapshots, latestRound means the latest price snapshot. follow chainlink naming
        uint256 cumulativeTime = _blockTimestamp().sub(latestTimestamp);
        uint256 previousTimestamp = latestTimestamp;
        uint256 weightedPrice = priceRecord.price.mul(cumulativeTime);
        while (true) {
            if (round == 0) {
                // if cumulative time is less than requested interval, return current twap price
                return weightedPrice.div(cumulativeTime);
            }

            round = round.sub(1);
            // get current round timestamp and price
            priceRecord = priceFeedMap[_priceFeedKey].priceData[round];
            uint256 currentTimestamp = priceRecord.timestamp;
            uint256 price = priceRecord.price;

            // check if current round timestamp is earlier than target timestamp
            if (currentTimestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice = weightedPrice.add(price.mul(previousTimestamp.sub(baseTimestamp)));
                break;
            }

            uint256 timeFraction = previousTimestamp.sub(currentTimestamp);
            weightedPrice = weightedPrice.add(price.mul(timeFraction));
            cumulativeTime = cumulativeTime.add(timeFraction);
            previousTimestamp = currentTimestamp;
        }
        return weightedPrice.div(_interval);
    }

    function getPreviousPrice(bytes32 _priceFeedKey, uint256 _numOfRoundBack) public view override returns (uint256) {
        require(isExistedKey(_priceFeedKey), "key not existed");

        uint256 len = getPriceFeedLength(_priceFeedKey);
        require(len > 0 && _numOfRoundBack < len, "Not enough history");
        return priceFeedMap[_priceFeedKey].priceData[len - _numOfRoundBack - 1].price;
    }

    function getPreviousTimestamp(bytes32 _priceFeedKey, uint256 _numOfRoundBack)
        public
        view
        override
        returns (uint256)
    {
        require(isExistedKey(_priceFeedKey), "key not existed");

        uint256 len = getPriceFeedLength(_priceFeedKey);
        require(len > 0 && _numOfRoundBack < len, "Not enough history");
        return priceFeedMap[_priceFeedKey].priceData[len - _numOfRoundBack - 1].timestamp;
    }

    //
    // END OF INTERFACE IMPLEMENTATION
    //

    // @dev there's no purpose for a registered priceFeed with 0 priceData so it will revert directly
    function getPriceFeedLength(bytes32 _priceFeedKey) public view returns (uint256 length) {
        return priceFeedMap[_priceFeedKey].priceData.length;
    }

    //
    // INTERNAL
    //

    function getLatestRoundId(bytes32 _priceFeedKey) internal view returns (uint256) {
        uint256 len = getPriceFeedLength(_priceFeedKey);
        if (len == 0) {
            return 0;
        }
        return priceFeedMap[_priceFeedKey].priceData[len - 1].roundId;
    }

    function isExistedKey(bytes32 _priceFeedKey) private view returns (bool) {
        return priceFeedMap[_priceFeedKey].registered;
    }

    function requireKeyExisted(bytes32 _key, bool _existed) private view {
        if (_existed) {
            require(isExistedKey(_key), "key not existed");
        } else {
            require(!isExistedKey(_key), "key existed");
        }
    }
}

pragma solidity >=0.6.0;

interface AggregatorV3Interface {

  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { ChainlinkL1 } from "../ChainlinkL1.sol";

contract ChainlinkL1Fake is ChainlinkL1 {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;

import "../../interface/IPriceFeed.sol";

contract PriceFeedMock {
    uint256 price;

    constructor(uint256 _price) public {
        price = _price;
    }

    function getPrice(bytes32) public view returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { Decimal, SafeMath } from "./utils/Decimal.sol";

contract ChainlinkPriceFeed is IPriceFeed, PerpFiOwnableUpgrade, BlockContext {
    using SafeMath for uint256;

    uint256 private constant TOKEN_DIGIT = 10**18;

    //**********************************************************//
    //    The below state variables can not change the order    //
    //**********************************************************//

    // key by currency symbol, eg ETH
    mapping(bytes32 => AggregatorV3Interface) public priceFeedMap;
    bytes32[] public priceFeedKeys;
    mapping(bytes32 => uint8) public priceFeedDecimalMap;
    //**********************************************************//
    //    The above state variables can not change the order    //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    //
    // FUNCTIONS
    //
    function initialize() public initializer {
        __Ownable_init();
    }

    function addAggregator(bytes32 _priceFeedKey, address _aggregator) external onlyOwner {
        requireNonEmptyAddress(_aggregator);
        if (address(priceFeedMap[_priceFeedKey]) == address(0)) {
            priceFeedKeys.push(_priceFeedKey);
        }
        priceFeedMap[_priceFeedKey] = AggregatorV3Interface(_aggregator);
        priceFeedDecimalMap[_priceFeedKey] = AggregatorV3Interface(_aggregator).decimals();
    }

    function removeAggregator(bytes32 _priceFeedKey) external onlyOwner {
        requireNonEmptyAddress(address(getAggregator(_priceFeedKey)));
        delete priceFeedMap[_priceFeedKey];
        delete priceFeedDecimalMap[_priceFeedKey];

        uint256 length = priceFeedKeys.length;
        for (uint256 i; i < length; i++) {
            if (priceFeedKeys[i] == _priceFeedKey) {
                // if the removal item is the last one, just `pop`
                if (i != length - 1) {
                    priceFeedKeys[i] = priceFeedKeys[length - 1];
                }
                priceFeedKeys.pop();
                break;
            }
        }
    }

    //
    // VIEW FUNCTIONS
    //

    function getAggregator(bytes32 _priceFeedKey) public view returns (AggregatorV3Interface) {
        return priceFeedMap[_priceFeedKey];
    }

    //
    // INTERFACE IMPLEMENTATION
    //

    function getPrice(bytes32 _priceFeedKey) external view override returns (uint256) {
        AggregatorV3Interface aggregator = getAggregator(_priceFeedKey);
        requireNonEmptyAddress(address(aggregator));

        (, uint256 latestPrice, ) = getLatestRoundData(aggregator);
        return formatDecimals(latestPrice, priceFeedDecimalMap[_priceFeedKey]);
    }

    function getLatestTimestamp(bytes32 _priceFeedKey) external view override returns (uint256) {
        AggregatorV3Interface aggregator = getAggregator(_priceFeedKey);
        requireNonEmptyAddress(address(aggregator));

        (, , uint256 latestTimestamp) = getLatestRoundData(aggregator);
        return latestTimestamp;
    }

    function getTwapPrice(bytes32 _priceFeedKey, uint256 _interval) external view override returns (uint256) {
        AggregatorV3Interface aggregator = getAggregator(_priceFeedKey);
        requireNonEmptyAddress(address(aggregator));
        require(_interval != 0, "interval can't be 0");

        // 3 different timestamps, `previous`, `current`, `target`
        // `base` = now - _interval
        // `current` = current round timestamp from aggregator
        // `previous` = previous round timestamp form aggregator
        // now >= previous > current > = < base
        //
        //  while loop i = 0
        //  --+------+-----+-----+-----+-----+-----+
        //         base                 current  now(previous)
        //
        //  while loop i = 1
        //  --+------+-----+-----+-----+-----+-----+
        //         base           current previous now

        uint8 decimal = priceFeedDecimalMap[_priceFeedKey];
        (uint80 round, uint256 latestPrice, uint256 latestTimestamp) = getLatestRoundData(aggregator);
        uint256 baseTimestamp = _blockTimestamp().sub(_interval);
        // if latest updated timestamp is earlier than target timestamp, return the latest price.
        if (latestTimestamp < baseTimestamp || round == 0) {
            return formatDecimals(latestPrice, decimal);
        }

        // rounds are like snapshots, latestRound means the latest price snapshot. follow chainlink naming
        uint256 previousTimestamp = latestTimestamp;
        uint256 cumulativeTime = _blockTimestamp().sub(previousTimestamp);
        uint256 weightedPrice = latestPrice.mul(cumulativeTime);
        while (true) {
            if (round == 0) {
                // if cumulative time is less than requested interval, return current twap price
                return formatDecimals(weightedPrice.div(cumulativeTime), decimal);
            }

            round = round - 1;
            (, uint256 currentPrice, uint256 currentTimestamp) = getRoundData(aggregator, round);

            // check if current round timestamp is earlier than target timestamp
            if (currentTimestamp <= baseTimestamp) {
                // weighted time period will be (target timestamp - previous timestamp). For example,
                // now is 1000, _interval is 100, then target timestamp is 900. If timestamp of current round is 970,
                // and timestamp of NEXT round is 880, then the weighted time period will be (970 - 900) = 70,
                // instead of (970 - 880)
                weightedPrice = weightedPrice.add(currentPrice.mul(previousTimestamp.sub(baseTimestamp)));
                break;
            }

            uint256 timeFraction = previousTimestamp.sub(currentTimestamp);
            weightedPrice = weightedPrice.add(currentPrice.mul(timeFraction));
            cumulativeTime = cumulativeTime.add(timeFraction);
            previousTimestamp = currentTimestamp;
        }
        return formatDecimals(weightedPrice.div(_interval), decimal);
    }

    function getPreviousPrice(bytes32 _priceFeedKey, uint256 _numOfRoundBack) external view override returns (uint256) {
        AggregatorV3Interface aggregator = getAggregator(_priceFeedKey);
        requireNonEmptyAddress(address(aggregator));

        (uint80 round, , , , ) = aggregator.latestRoundData();
        require(round > 0 && round >= _numOfRoundBack, "Not enough history");
        (, int256 previousPrice, , , ) = aggregator.getRoundData(round - uint80(_numOfRoundBack));
        requirePositivePrice(previousPrice);
        return formatDecimals(uint256(previousPrice), priceFeedDecimalMap[_priceFeedKey]);
    }

    function getPreviousTimestamp(bytes32 _priceFeedKey, uint256 _numOfRoundBack)
        external
        view
        override
        returns (uint256)
    {
        AggregatorV3Interface aggregator = getAggregator(_priceFeedKey);
        requireNonEmptyAddress(address(aggregator));

        (uint80 round, , , , ) = aggregator.latestRoundData();
        require(round > 0 && round >= _numOfRoundBack, "Not enough history");
        (, int256 previousPrice, , uint256 previousTimestamp, ) =
            aggregator.getRoundData(round - uint80(_numOfRoundBack));
        requirePositivePrice(previousPrice);
        return previousTimestamp;
    }

    //
    // INTERNAL VIEW FUNCTIONS
    //

    function getLatestRoundData(AggregatorV3Interface _aggregator)
        internal
        view
        returns (
            uint80,
            uint256 finalPrice,
            uint256
        )
    {
        (uint80 round, int256 latestPrice, , uint256 latestTimestamp, ) = _aggregator.latestRoundData();
        finalPrice = uint256(latestPrice);
        if (latestPrice < 0) {
            requireEnoughHistory(round);
            (round, finalPrice, latestTimestamp) = getRoundData(_aggregator, round - 1);
        }
        return (round, finalPrice, latestTimestamp);
    }

    function getRoundData(AggregatorV3Interface _aggregator, uint80 _round)
        internal
        view
        returns (
            uint80,
            uint256,
            uint256
        )
    {
        (uint80 round, int256 latestPrice, , uint256 latestTimestamp, ) = _aggregator.getRoundData(_round);
        while (latestPrice < 0) {
            requireEnoughHistory(round);
            round = round - 1;
            (, latestPrice, , latestTimestamp, ) = _aggregator.getRoundData(round);
        }
        return (round, uint256(latestPrice), latestTimestamp);
    }

    function formatDecimals(uint256 _price, uint8 _decimals) internal pure returns (uint256) {
        return _price.mul(TOKEN_DIGIT).div(10**uint256(_decimals));
    }

    //
    // REQUIRE FUNCTIONS
    //

    function requireNonEmptyAddress(address _addr) internal pure {
        require(_addr != address(0), "empty address");
    }

    function requireEnoughHistory(uint80 _round) internal pure {
        require(_round > 0, "Not enough history");
    }

    function requirePositivePrice(int256 _price) internal pure {
        // a negative price should be reverted to prevent an extremely large/small premiumFraction
        require(_price > 0, "Negative price");
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
import { ChainlinkPriceFeed } from "../ChainlinkPriceFeed.sol";

contract ChainlinkPriceFeedFake is ChainlinkPriceFeed {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    function mock_getCurrentBlockNumber() public view returns (uint256) {
        return _blockNumber();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract ChainlinkL1Mock is AggregatorV3Interface {
    uint80[] roundIdArray;
    int256[] answerArray;
    uint256[] decimalsArray;
    uint256[] timestampArray;
    uint80[] versionArray;

    event PriceUpdated(uint256 roundId, uint256 price, uint256 timestamp);

    function updateLatestRoundData(bytes32) external {
        emit PriceUpdated(100, 500, 1444004400);
    }

    function decimals() external view override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        return "";
    }

    function version() external view override returns (uint256) {
        return 0;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            roundIdArray[_roundId],
            answerArray[_roundId],
            decimalsArray[_roundId],
            timestampArray[_roundId],
            versionArray[_roundId]
        );
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint256 index = roundIdArray.length - 1;
        return (
            roundIdArray[index],
            answerArray[index],
            decimalsArray[index],
            timestampArray[index],
            versionArray[index]
        );
    }

    function mockAddAnswer(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        roundIdArray.push(_roundId);
        answerArray.push(_answer);
        decimalsArray.push(_startedAt);
        timestampArray.push(_updatedAt);
        versionArray.push(_answeredInRound);
    }
}

// SPDX-License-Identifier: BSD-3-CLAUSE
pragma solidity 0.6.9;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract ChainlinkAggregatorMock is AggregatorV3Interface {
    uint80[] roundIdArray;
    int256[] answerArray;
    uint256[] decimalsArray;
    uint256[] timestampArray;
    uint80[] versionArray;

    function decimals() external view override returns (uint8) {
        return 8;
    }

    function description() external view override returns (string memory) {
        return "";
    }

    function version() external view override returns (uint256) {
        return 0;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {}

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        uint256 index = roundIdArray.length - 1;
        return (
            roundIdArray[index],
            answerArray[index],
            decimalsArray[index],
            timestampArray[index],
            versionArray[index]
        );
    }

    function mockAddAnswer(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        roundIdArray.push(_roundId);
        answerArray.push(_answer);
        decimalsArray.push(_startedAt);
        timestampArray.push(_updatedAt);
        versionArray.push(_answeredInRound);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { PerpFiOwnableUpgrade } from "./utils/PerpFiOwnableUpgrade.sol";
import { Decimal, SafeMath } from "./utils/Decimal.sol";
import { DecimalERC20 } from "./utils/DecimalERC20.sol";
import { IMinter } from "./interface/IMinter.sol";
import { BlockContext } from "./utils/BlockContext.sol";
import { IInflationMonitor } from "./interface/IInflationMonitor.sol";

// record the extra inflation due to the unexpected loss
contract InflationMonitor is IInflationMonitor, PerpFiOwnableUpgrade, BlockContext, DecimalERC20 {
    using Decimal for Decimal.decimal;
    using SafeMath for uint256;

    /**
     * @notice Stores timestamp and cumulative amount of minted token
     */
    struct MintedTokenEntry {
        uint256 timestamp;
        Decimal.decimal cumulativeAmount;
    }

    uint256 public constant MINT_THRESHOLD_PERIOD = 1 weeks;

    //**********************************************************//
    //    Can not change the order of below state variables     //
    //**********************************************************//

    // An array of token mint timestamp and cumulative amount
    MintedTokenEntry[] private mintedTokenHistory;

    /**
     * @notice in percentage, if (minted token in a week) / (total supply) is less than `shutdownThreshold`,
     * it's ready to shutdown
     */
    Decimal.decimal public shutdownThreshold;

    IMinter private minter;

    //**********************************************************//
    //    Can not change the order of above state variables     //
    //**********************************************************//

    //◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤ add state variables below ◥◤◥◤◥◤◥◤◥◤◥◤◥◤◥◤//

    //◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣ add state variables above ◢◣◢◣◢◣◢◣◢◣◢◣◢◣◢◣//
    uint256[50] private __gap;

    function initialize(IMinter _minter) public initializer {
        __Ownable_init();

        minter = _minter;
        shutdownThreshold = Decimal.one().divScalar(10);
    }

    function setShutdownThreshold(Decimal.decimal memory _shutdownThreshold) public onlyOwner {
        shutdownThreshold = _shutdownThreshold;
    }

    function appendMintedTokenHistory(Decimal.decimal calldata _amount) external override {
        require(_msgSender() == address(minter), "!minter");
        Decimal.decimal memory cumulativeAmount;
        uint256 len = mintedTokenHistory.length;
        if (len == 0) {
            cumulativeAmount = _amount;
        } else {
            cumulativeAmount = mintedTokenHistory[len - 1].cumulativeAmount.addD(_amount);
        }
        mintedTokenHistory.push(MintedTokenEntry({ timestamp: _blockTimestamp(), cumulativeAmount: cumulativeAmount }));
    }

    function mintedAmountDuringMintThresholdPeriod() public view returns (Decimal.decimal memory) {
        uint256 len = mintedTokenHistory.length;
        if (len == 0) {
            return Decimal.zero();
        }

        uint256 durationSinceLastMinted = _blockTimestamp().sub(mintedTokenHistory[len - 1].timestamp);
        if (durationSinceLastMinted > MINT_THRESHOLD_PERIOD) {
            return Decimal.zero();
        }

        Decimal.decimal memory minted;
        for (uint256 i = len - 1; i > 0; i--) {
            Decimal.decimal memory amount =
                mintedTokenHistory[i].cumulativeAmount.subD(mintedTokenHistory[i - 1].cumulativeAmount);
            minted = minted.addD(amount);

            durationSinceLastMinted += mintedTokenHistory[i].timestamp.sub(mintedTokenHistory[i - 1].timestamp);
            if (durationSinceLastMinted > MINT_THRESHOLD_PERIOD) {
                break;
            }
        }
        return minted;
    }

    function isOverMintThreshold() external view override returns (bool) {
        if (shutdownThreshold.toUint() == 0) {
            return false;
        }
        Decimal.decimal memory totalSupply = _totalSupply(minter.getPerpToken());
        Decimal.decimal memory minted = mintedAmountDuringMintThresholdPeriod();
        return minted.divD(totalSupply).cmp(shutdownThreshold) >= 0;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../InflationMonitor.sol";

contract InflationMonitorFake is InflationMonitor {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../staking/PerpRewardVesting.sol";

contract PerpRewardVestingFake is PerpRewardVesting {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    function mock_getCurrentBlockNumber() public view returns (uint256) {
        return _blockNumber();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }

    function verifyClaim(
        address _liquidityProvider,
        uint256 _week,
        uint256 _claimedBalance,
        bytes32[] memory _merkleProof
    ) public view override returns (bool valid) {
        return true;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../utils/MixedDecimal.sol";

contract MixedDecimalFake {
    using MixedDecimal for SignedDecimal.signedDecimal;

    constructor() public {}

    function fromDecimal(Decimal.decimal memory x) public pure returns (SignedDecimal.signedDecimal memory z) {
        z = MixedDecimal.fromDecimal(x);
    }

    function toUint(SignedDecimal.signedDecimal memory x) public pure returns (uint256) {
        return x.toUint();
    }

    /// @dev multiple a SignedDecimal.signedDecimal by Decimal.decimal
    function mul(SignedDecimal.signedDecimal memory x, Decimal.decimal memory y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.mulD(y);
    }

    /// @dev multiple a SignedDecimal.signedDecimal by a uint256
    function mulScalar(SignedDecimal.signedDecimal memory x, uint256 y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.mulScalar(y);
    }

    /// @dev divide a SignedDecimal.signedDecimal by a Decimal.decimal
    function div(SignedDecimal.signedDecimal memory x, Decimal.decimal memory y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.divD(y);
    }

    /// @dev divide a SignedDecimal.signedDecimal by a uint256
    function divScalar(SignedDecimal.signedDecimal memory x, uint256 y)
        public
        pure
        returns (SignedDecimal.signedDecimal memory z)
    {
        z = x.divScalar(y);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { Amm } from "./Amm.sol";
import { Decimal } from "./utils/MixedDecimal.sol";

contract AmmReader {
    using Decimal for Decimal.decimal;
    struct AmmStates {
        uint256 quoteAssetReserve;
        uint256 baseAssetReserve;
        uint256 tradeLimitRatio;
        uint256 fundingPeriod;
        string quoteAssetSymbol;
        string baseAssetSymbol;
        bytes32 priceFeedKey;
        address priceFeed;
    }

    function getAmmStates(address _amm) external view returns (AmmStates memory) {
        Amm amm = Amm(_amm);
        (bool getSymbolSuccess, bytes memory quoteAssetSymbolData) =
            address(amm.quoteAsset()).staticcall(abi.encodeWithSignature("symbol()"));
        (Decimal.decimal memory quoteAssetReserve, Decimal.decimal memory baseAssetReserve) = amm.getReserve();

        bytes32 priceFeedKey = amm.priceFeedKey();
        return
            AmmStates({
                quoteAssetReserve: quoteAssetReserve.toUint(),
                baseAssetReserve: baseAssetReserve.toUint(),
                tradeLimitRatio: amm.tradeLimitRatio(),
                fundingPeriod: amm.fundingPeriod(),
                priceFeed: address(amm.priceFeed()),
                priceFeedKey: priceFeedKey,
                quoteAssetSymbol: getSymbolSuccess ? abi.decode(quoteAssetSymbolData, (string)) : "",
                baseAssetSymbol: bytes32ToString(priceFeedKey)
            });
    }

    // TODO: move to library
    function bytes32ToString(bytes32 _key) private pure returns (string memory) {
        uint8 length;
        while (length < 32 && _key[length] != 0) {
            length++;
        }
        bytes memory bytesArray = new bytes(length);
        for (uint256 i = 0; i < 32 && _key[i] != 0; i++) {
            bytesArray[i] = _key[i];
        }
        return string(bytesArray);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../StakingReserve.sol";

contract StakingReserveFake is StakingReserve {
    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

contract MultiTokenMediatorMock {
    function relayTokens(
        address token,
        address receiver,
        uint256 amount
    ) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../utils/PerpFiOwnableUpgrade.sol";

contract PerpFiOwnableUpgradeFake is PerpFiOwnableUpgrade {
    constructor() public {}

    function initialize() public {
        __Ownable_init();
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../utils/Decimal.sol";

contract DecimalFake {
    using Decimal for Decimal.decimal;

    constructor() public {}

    /// @dev multiple two decimals
    function mul(Decimal.decimal memory x, Decimal.decimal memory y) public pure returns (Decimal.decimal memory z) {
        z = x.mulD(y);
    }

    /// @dev multiple a Decimal.decimal by a uint256
    function mulScalar(Decimal.decimal memory x, uint256 y) public pure returns (Decimal.decimal memory z) {
        z = x.mulScalar(y);
    }

    /// @dev divide two decimals
    function div(Decimal.decimal memory x, Decimal.decimal memory y) public pure returns (Decimal.decimal memory z) {
        z = x.divD(y);
    }

    /// @dev divide a Decimal.decimal by a uint256
    function divScalar(Decimal.decimal memory x, uint256 y) public pure returns (Decimal.decimal memory z) {
        z = x.divScalar(y);
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import { Decimal } from "../utils/Decimal.sol";

interface IRewardsDistribution {
    function distributeRewards(Decimal.decimal calldata) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import "../Amm.sol";

contract AmmFake is Amm {
    constructor(
        uint256 _dcQuoteAssetReserve,
        uint256 _dcBaseAssetReserve,
        uint256 _dcTradeLimitRatio,
        uint256 _fundingPeriod,
        IPriceFeed _priceFeed,
        bytes32 _priceFeedKey,
        address _quoteAsset,
        uint256 _fluctuation,
        uint256 _tollRatio,
        uint256 _spreadRatio
    ) public {
        Amm.initialize(
            _dcQuoteAssetReserve,
            _dcBaseAssetReserve,
            _dcTradeLimitRatio,
            _fundingPeriod,
            _priceFeed,
            _priceFeedKey,
            _quoteAsset,
            _fluctuation,
            _tollRatio,
            _spreadRatio
        );
    }

    uint256 private timestamp = 1444004400;
    uint256 private number = 10001;

    function mock_setBlockTimestamp(uint256 _timestamp) public {
        timestamp = _timestamp;
    }

    function mock_setBlockNumber(uint256 _number) public {
        number = _number;
    }

    function mock_getCurrentTimestamp() public view returns (uint256) {
        return _blockTimestamp();
    }

    function mock_getCurrentBlockNumber() public view returns (uint256) {
        return _blockNumber();
    }

    // Override BlockContext here
    function _blockTimestamp() internal view override returns (uint256) {
        return timestamp;
    }

    function _blockNumber() internal view override returns (uint256) {
        return number;
    }

    function getInputPriceWithReservesPublic(
        Dir _dir,
        Decimal.decimal memory _quoteAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public view returns (Decimal.decimal memory) {
        return getInputPriceWithReserves(_dir, _quoteAssetAmount, _quoteAssetPoolAmount, _baseAssetPoolAmount);
    }

    function getOutputPriceWithReservesPublic(
        Dir _dir,
        Decimal.decimal memory _baseAssetAmount,
        Decimal.decimal memory _quoteAssetPoolAmount,
        Decimal.decimal memory _baseAssetPoolAmount
    ) public view returns (Decimal.decimal memory) {
        return getOutputPriceWithReserves(_dir, _baseAssetAmount, _quoteAssetPoolAmount, _baseAssetPoolAmount);
    }

    function mockSetReserve(Decimal.decimal memory _quoteReserve, Decimal.decimal memory _baseReserve) public {
        quoteAssetReserve = _quoteReserve;
        baseAssetReserve = _baseReserve;
    }
}

