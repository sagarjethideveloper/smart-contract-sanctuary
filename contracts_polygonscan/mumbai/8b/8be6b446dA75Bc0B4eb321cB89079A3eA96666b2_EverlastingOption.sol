// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';
import '../interface/ILTokenOption.sol';
import '../interface/IPTokenOption.sol';
import '../interface/IEverlastingOptionPricing.sol';
import '../interface/IOracleViewer.sol';
import '../interface/IVolatilityOracle.sol';
import '../interface/ILiquidatorQualifier.sol';
import "../interface/IEverlastingOption.sol";
import "../interface/IEverlastingOptionOld.sol";
import '../library/SafeMath.sol';
import '../library/SafeERC20.sol';
import '../utils/Migratable.sol';

contract EverlastingOption is IEverlastingOption, Migratable {

    using SafeMath for uint256;
    using SafeMath for int256;
    using SafeERC20 for IERC20;

    int256 constant ONE = 1e18;
    int256 constant MIN_INITIAL_MARGIN_RATIO = 1e16;       // 0.01
    int256 constant FUNDING_PERIOD = ONE / 365;            // funding period = 1 day
    int256 constant FUNDING_COEFFICIENT = ONE / 24 / 3600; // funding rate per second

    uint256 immutable _decimals;
    int256  immutable _initialMarginRatio;
    int256  immutable _maintenanceMarginRatio;
    int256  immutable _minLiquidationReward;
    int256  immutable _maxLiquidationReward;
    int256  immutable _liquidationCutRatio;
    int256  immutable _protocolFeeCollectRatio;

    address immutable _bTokenAddress;
    address immutable _lTokenAddress;
    address immutable _pTokenAddress;
    address immutable _liquidatorQualifierAddress;
    address immutable _protocolFeeCollector;
    address immutable _optionPricerAddress;

    int256  _poolMarginMultiplier = 10;

    int256  _liquidity;
    uint256 _lastTimestamp;
    int256  _protocolFeeAccrued;

    // symbolId => SymbolInfo
    mapping (uint256 => SymbolInfo) _symbols;

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    constructor (uint256[6] memory parameters, address[6] memory addresses) {
        _initialMarginRatio = int256(parameters[0]);
        _maintenanceMarginRatio = int256(parameters[1]);
        _minLiquidationReward = int256(parameters[2]);
        _maxLiquidationReward = int256(parameters[3]);
        _liquidationCutRatio = int256(parameters[4]);
        _protocolFeeCollectRatio = int256(parameters[5]);

        _bTokenAddress = addresses[0];
        _lTokenAddress = addresses[1];
        _pTokenAddress = addresses[2];
        _liquidatorQualifierAddress = addresses[3];
        _protocolFeeCollector = addresses[4];
        _optionPricerAddress = addresses[5];

        _decimals = IERC20(addresses[0]).decimals();

        _controller = msg.sender;
    }

    // during a migration, this function is intended to be called in the source pool
    function approveMigration() external override _controller_ {
        require(_migrationTimestamp != 0 && block.timestamp >= _migrationTimestamp, 'time inv');
        // approve new pool to pull all base tokens from this pool
        IERC20(_bTokenAddress).safeApprove(_migrationDestination, type(uint256).max);
        // set lToken/pToken to new pool, after redirecting pToken/lToken to new pool, this pool will stop functioning
        ILTokenOption(_lTokenAddress).setPool(_migrationDestination);
        IPTokenOption(_pTokenAddress).setPool(_migrationDestination);
    }

    // during a migration, this function is intended to be called in the target pool
    function executeMigration(address source) external override _controller_ {
        uint256 migrationTimestamp_ = IEverlastingOptionOld(source).migrationTimestamp();
        address migrationDestination_ = IEverlastingOptionOld(source).migrationDestination();
        require(migrationTimestamp_ != 0 && block.timestamp >= migrationTimestamp_, 'time inv');
        require(migrationDestination_ == address(this), 'not dest');

        // transfer bToken to this address
        IERC20(_bTokenAddress).safeTransferFrom(source, address(this), IERC20(_bTokenAddress).balanceOf(source));

        // transfer symbol infos
        uint256[] memory symbolIds = IPTokenOption(_pTokenAddress).getActiveSymbolIds();
        for (uint256 i = 0; i < symbolIds.length; i++) {
            uint256 symbolId = symbolIds[i];
            IEverlastingOptionOld.SymbolInfo memory pre = IEverlastingOptionOld(source).getSymbol(symbolId);
            SymbolInfo storage cur = _symbols[symbolId];
            cur.symbolId = pre.symbolId;
            cur.symbol = pre.symbol;
            cur.oracleAddress = pre.oracleAddress;
            cur.volatilityAddress = pre.volatilityAddress;
            cur.isCall = pre.isCall;
            cur.strikePrice = pre.strikePrice;
            cur.multiplier = pre.multiplier;
            cur.feeRatioITM = ONE * 15 / 10000;
            cur.feeRatioOTM = ONE * 4 / 100;
            cur.alpha = pre.alpha;
            cur.tradersNetVolume = pre.tradersNetVolume;
            cur.tradersNetCost = pre.tradersNetCost;
            cur.cumulativeFundingRate = pre.cumulativeFundingRate;
        }

        // transfer state values
        (_liquidity, _lastTimestamp, _protocolFeeAccrued) = IEverlastingOptionOld(source).getPoolStateValues();

        emit ExecuteMigration(migrationTimestamp_, source, migrationDestination_);
    }

    function getParameters() external view override returns (
        int256 initialMarginRatio,
        int256 maintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    ) {
        return (
            _initialMarginRatio,
            _maintenanceMarginRatio,
            _minLiquidationReward,
            _maxLiquidationReward,
            _liquidationCutRatio,
            _protocolFeeCollectRatio
        );
    }

    function getAddresses() external view override returns (
        address bTokenAddress,
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolFeeCollector,
        address optionPricerAddress
    ) {
        return (
            _bTokenAddress,
            _lTokenAddress,
            _pTokenAddress,
            _liquidatorQualifierAddress,
            _protocolFeeCollector,
            _optionPricerAddress
        );
    }

    function getSymbol(uint256 symbolId) external view override returns (SymbolInfo memory) {
        return _symbols[symbolId];
    }

    function getPoolStateValues() external view override returns (int256 liquidity, uint256 lastTimestamp, int256 protocolFeeAccrued) {
        return (_liquidity, _lastTimestamp, _protocolFeeAccrued);
    }

    function collectProtocolFee() external override {
        uint256 balance = IERC20(_bTokenAddress).balanceOf(address(this)).rescale(_decimals, 18);
        uint256 amount = _protocolFeeAccrued.itou();
        if (amount > balance) amount = balance;
        _protocolFeeAccrued -= amount.utoi();
        _transferOut(_protocolFeeCollector, amount);
        emit ProtocolFeeCollection(_protocolFeeCollector, amount);
    }

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        address volatilityAddress,
        bool    isCall,
        uint256 strikePrice,
        uint256 multiplier,
        uint256 feeRatioITM,
        uint256 feeRatioOTM,
        uint256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.symbolId = symbolId;
        s.symbol = symbol;
        s.oracleAddress = oracleAddress;
        s.volatilityAddress = volatilityAddress;
        s.isCall = isCall;
        s.strikePrice = int256(strikePrice);
        s.multiplier = int256(multiplier);
        s.feeRatioITM = int256(feeRatioITM);
        s.feeRatioOTM = int256(feeRatioOTM);
        s.alpha = int256(alpha);
        IPTokenOption(_pTokenAddress).addSymbolId(symbolId);
    }

    function removeSymbol(uint256 symbolId) external override _controller_ {
        delete _symbols[symbolId];
        IPTokenOption(_pTokenAddress).removeSymbolId(symbolId);
    }

    function toggleCloseOnly(uint256 symbolId) external override _controller_ {
        IPTokenOption(_pTokenAddress).toggleCloseOnly(symbolId);
    }

    function getPoolMarginMultiplier() external override view returns (int256) {
        return _poolMarginMultiplier;
    }

    function setPoolMarginMulitplier(uint256 multiplier) external override _controller_ {
        _poolMarginMultiplier = int256(multiplier);
    }

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatioITM,
        uint256 feeRatioOTM,
        uint256 alpha
    ) external override _controller_ {
        SymbolInfo storage s = _symbols[symbolId];
        s.oracleAddress = oracleAddress;
        s.volatilityAddress = volatilityAddress;
        s.feeRatioITM = int256(feeRatioITM);
        s.feeRatioOTM = int256(feeRatioOTM);
        s.alpha = int256(alpha);
    }


    //================================================================================
    // Interactions with offchain volatility
    //================================================================================

    function addLiquidity(uint256 bAmount, SignedValue[] memory volatilities) external override {
        _updateSymbolVolatilities(volatilities);
        _addLiquidity(msg.sender, bAmount);
    }

    function removeLiquidity(uint256 lShares, SignedValue[] memory volatilities) external override {
        require(lShares > 0, '0 lShares');
        _updateSymbolVolatilities(volatilities);
        _removeLiquidity(msg.sender, lShares);
    }

    function addMargin(uint256 bAmount) external override {
        _addMargin(msg.sender, bAmount);
    }

    function removeMargin(uint256 bAmount, SignedValue[] memory volatilities) external override {
        address account = msg.sender;
        require(bAmount > 0, '0 bAmount');
        require(IPTokenOption(_pTokenAddress).exists(account), 'no pToken');
        _updateSymbolVolatilities(volatilities);
        _removeMargin(account, bAmount);
    }

    function trade(uint256 symbolId, int256 tradeVolume, SignedValue[] memory volatilities) external override {
        address account = msg.sender;
        require(IPTokenOption(_pTokenAddress).isActiveSymbolId(symbolId), 'inv symbolId');
        require(IPTokenOption(_pTokenAddress).exists(account), 'no pToken');
        require(tradeVolume != 0 && tradeVolume / ONE * ONE == tradeVolume, 'inv volume');
        _updateSymbolVolatilities(volatilities);
        _trade(account, symbolId, tradeVolume);
    }

    function liquidate(address account, SignedValue[] memory volatilities) external override {
        address liquidator = msg.sender;
        require(
            _liquidatorQualifierAddress == address(0) || ILiquidatorQualifier(_liquidatorQualifierAddress).isQualifiedLiquidator(liquidator),
            'unqualified'
        );
        require(IPTokenOption(_pTokenAddress).exists(account), 'no pToken');
        _updateSymbolVolatilities(volatilities);
        _liquidate(liquidator, account);
    }


    //================================================================================
    // Core logics
    //================================================================================

    function _addLiquidity(address account, uint256 bAmount) internal _lock_ {
        bAmount = _transferIn(account, bAmount);
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);

        int256 poolDynamicEquity = _getPoolPnl(symbols) + _liquidity;
        uint256 totalSupply = lToken.totalSupply();
        uint256 lShares;
        if (totalSupply == 0) {
            lShares = bAmount;
        } else {
            lShares = bAmount * totalSupply / poolDynamicEquity.itou();
        }

        lToken.mint(account, lShares);
        _liquidity += bAmount.utoi();

        emit AddLiquidity(account, lShares, bAmount);
    }

    function _removeLiquidity(address account, uint256 lShares) internal _lock_ {
        ILTokenOption lToken = ILTokenOption(_lTokenAddress);
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);

        int256 liquidity = _liquidity;
        int256 poolPnlBefore = _getPoolPnl(symbols);
        uint256 totalSupply = lToken.totalSupply();
        uint256 bAmount = lShares * (liquidity + poolPnlBefore).itou() / totalSupply;

        liquidity -= bAmount.utoi();
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            (s.K, s.dpmmPrice) = _calculateDpmmPrice(
                s.spotPrice, s.theoreticalPrice, s.delta, s.alpha, s.tradersNetPosition, liquidity
            );
        }
        int256 poolPnlAfter = _getPoolPnl(symbols);

        uint256 compensation = (poolPnlBefore - poolPnlAfter).itou() * lShares / totalSupply;
        bAmount -= compensation;

        int256 poolRequiredMargin = _getPoolRequiredMargin(symbols);
        require(liquidity + poolPnlAfter >= poolRequiredMargin, 'pool insuf liq');

        _liquidity -= bAmount.utoi();
        lToken.burn(account, lShares);
        _transferOut(account, bAmount);

        emit RemoveLiquidity(account, lShares, bAmount);
    }

    function _addMargin(address account, uint256 bAmount) internal _lock_ {
        bAmount = _transferIn(account, bAmount);
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        if (!pToken.exists(account)) pToken.mint(account);

        pToken.addMargin(account, bAmount.utoi());
        emit AddMargin(account, bAmount);
    }

    function _removeMargin(address account, uint256 bAmount) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);
        (IPTokenOption.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        int256 amount = bAmount.utoi();
        if (amount > margin) {
            amount = margin;
            bAmount = amount.itou();
        }
        margin -= amount;

        (bool initialMarginSafe, ) = _getTraderMarginStatus(symbols, positions, margin);
        require(initialMarginSafe, 'insuf margin');

        _updateTraderPortfolio(account, symbols, positions, margin);
        _transferOut(account, bAmount);

        emit RemoveMargin(account, bAmount);
    }

    function _trade(address account, uint256 symbolId, int256 tradeVolume) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(symbolId);
        (IPTokenOption.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        // get pool pnl before trading
        int256 poolPnl = _getPoolPnl(symbols);

        DataSymbol memory s = symbols[0];
        IPTokenOption.Position memory p = positions[0];

        int256 curCost = _queryTradeDpmm(
            s.tradersNetPosition,
            s.theoreticalPrice,
            tradeVolume * s.multiplier / ONE,
            s.K
        );

        emit Trade(account, symbolId, tradeVolume, curCost, _liquidity, s.tradersNetVolume, s.spotPrice, s.volatility);

        int256 fee;
        if (s.intrinsicValue > 0) {
            fee = s.spotPrice * tradeVolume.abs() / ONE * s.multiplier / ONE * s.feeRatioITM / ONE;
        } else {
            fee = curCost.abs() * s.feeRatioOTM / ONE;
        }

        int256 realizedCost;
        if (!(p.volume >= 0 && tradeVolume >= 0) && !(p.volume <= 0 && tradeVolume <= 0)) {
            int256 absVolume = p.volume.abs();
            int256 absTradeVolume = tradeVolume.abs();
            if (absVolume <= absTradeVolume) {
                // previous position is totally closed
                realizedCost = curCost * absVolume / absTradeVolume + p.cost;
            } else {
                // previous position is partially closed
                realizedCost = p.cost * absTradeVolume / absVolume + curCost;
            }
        }
        int256 toAddCost = curCost - realizedCost;

        p.volume += tradeVolume;
        p.cost += toAddCost;
        p.lastCumulativeFundingRate = s.cumulativeFundingRate;

        margin -= fee + realizedCost;

        s.positionUpdated = true;
        s.tradersNetVolume += tradeVolume;
        s.tradersNetCost += toAddCost;
        s.tradersNetPosition = s.tradersNetVolume * s.multiplier / ONE;

        _symbols[symbolId].tradersNetVolume += tradeVolume;
        _symbols[symbolId].tradersNetCost += toAddCost;

        int256 protocolFee = fee * _protocolFeeCollectRatio / ONE;
        _protocolFeeAccrued += protocolFee;
        _liquidity += fee - protocolFee + realizedCost;

        require(_liquidity + poolPnl >= _getPoolRequiredMargin(symbols), 'insuf liquidity');
        (bool initialMarginSafe, ) = _getTraderMarginStatus(symbols, positions, margin);
        require(initialMarginSafe, 'insuf margin');

        _updateTraderPortfolio(account, symbols, positions, margin);

    }

    function _liquidate(address liquidator, address account) internal _lock_ {
        DataSymbol[] memory symbols = _updateFundingRates(type(uint256).max);
        (IPTokenOption.Position[] memory positions, int256 margin) = _settleTraderFundingFee(account, symbols);

        (, bool maintenanceMarginSafe) = _getTraderMarginStatus(symbols, positions, margin);
        require(!maintenanceMarginSafe, 'cant liq');

        int256 netEquity = margin;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            IPTokenOption.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 curCost = _queryTradeDpmm(
                    s.tradersNetPosition,
                    s.theoreticalPrice,
                    -p.volume * s.multiplier / ONE,
                    s.K
                );
                netEquity -= curCost + p.cost;
                _symbols[s.symbolId].tradersNetVolume -= p.volume;
                _symbols[s.symbolId].tradersNetCost -= p.cost;
            }
        }

        int256 reward;
        if (netEquity <= _minLiquidationReward) {
            reward = _minLiquidationReward;
        } else if (netEquity >= _maxLiquidationReward) {
            reward = _maxLiquidationReward;
        } else {
            reward = (netEquity - _minLiquidationReward) * _liquidationCutRatio / ONE + _minLiquidationReward;
        }

        _liquidity += margin - reward;
        IPTokenOption(_pTokenAddress).burn(account);
        _transferOut(liquidator, reward.itou());

        emit Liquidate(account, liquidator, reward.itou());
    }


    //================================================================================
    // Helpers
    //================================================================================

    function _updateSymbolVolatilities(SignedValue[] memory volatilities) internal {
        for (uint256 i = 0; i < volatilities.length; i++) {
            uint256 symbolId = volatilities[i].symbolId;
            IVolatilityOracle(_symbols[symbolId].volatilityAddress).updateVolatility(
                volatilities[i].timestamp,
                volatilities[i].value,
                volatilities[i].v,
                volatilities[i].r,
                volatilities[i].s
            );
        }
    }

    struct DataSymbol {
        uint256 symbolId;
        bool    isCall;
        int256  multiplier;
        int256  feeRatioITM;
        int256  feeRatioOTM;
        int256  strikePrice;
        int256  spotPrice;
        int256  volatility;
        int256  intrinsicValue;
        int256  timeValue;
        int256  theoreticalPrice;
        int256  dpmmPrice;
        int256  delta;
        int256  alpha;
        int256  K;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
        int256  tradersNetPosition; // volume * multiplier
        int256  dynamicInitialMarginRatio;
        bool    positionUpdated;
    }

    // Gether data for valid symbols for later use
    // Calculate those symbol parameters that will not change during this transaction
    // Symbols with no position holders are excluded
    function _getSymbols(uint256 tradeSymbolId) internal view returns (DataSymbol[] memory symbols) {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        uint256[] memory activeSymbolIds = pToken.getActiveSymbolIds();
        uint256[] memory symbolIds = new uint256[](activeSymbolIds.length);
        uint256 count;
        if (tradeSymbolId != type(uint256).max) {
            symbolIds[0] = tradeSymbolId;
            count = 1;
        }
        for (uint256 i = 0; i < activeSymbolIds.length; i++) {
            if (activeSymbolIds[i] != tradeSymbolId && pToken.getNumPositionHolders(activeSymbolIds[i]) != 0) {
                symbolIds[count++] = activeSymbolIds[i];
            }
        }

        symbols = new DataSymbol[](count);
        int256 liquidity = _liquidity;
        for (uint256 i = 0; i < count; i++) {
            SymbolInfo storage ss = _symbols[symbolIds[i]];
            DataSymbol memory s = symbols[i];
            s.symbolId = symbolIds[i];
            s.isCall = ss.isCall;
            s.multiplier = ss.multiplier;
            s.feeRatioITM = ss.feeRatioITM;
            s.feeRatioOTM = ss.feeRatioOTM;
            s.strikePrice = ss.strikePrice;
            s.spotPrice = IOracleViewer(ss.oracleAddress).getPrice().utoi();
            s.volatility = IVolatilityOracle(ss.volatilityAddress).getVolatility().utoi();
            s.intrinsicValue = s.isCall ? (s.spotPrice - s.strikePrice).max(0) : (s.strikePrice - s.spotPrice).max(0);
            (s.timeValue, s.delta) = IEverlastingOptionPricing(_optionPricerAddress).getEverlastingTimeValueAndDelta(
                s.spotPrice, s.strikePrice, s.volatility, FUNDING_PERIOD
            );
            s.theoreticalPrice = s.intrinsicValue + s.timeValue;
            if (s.intrinsicValue > 0) {
                if (s.isCall) s.delta += ONE;
                else s.delta -= ONE;
            }
            else if (s.spotPrice == s.strikePrice) {
                if (s.isCall) s.delta = ONE / 2;
                else s.delta = -ONE / 2;
            }
            s.alpha = ss.alpha;
            s.tradersNetVolume = ss.tradersNetVolume;
            s.tradersNetCost = ss.tradersNetCost;
            s.cumulativeFundingRate = ss.cumulativeFundingRate;
            s.tradersNetPosition = s.tradersNetVolume * s.multiplier / ONE;
            (s.K, s.dpmmPrice) = _calculateDpmmPrice(s.spotPrice, s.theoreticalPrice, s.delta, s.alpha, s.tradersNetPosition, liquidity);
            if (s.intrinsicValue > 0 || s.spotPrice == s.strikePrice) {
                s.dynamicInitialMarginRatio = _initialMarginRatio;
            } else {
                int256 otmRatio = (s.spotPrice - s.strikePrice).abs() * ONE / s.strikePrice;
                s.dynamicInitialMarginRatio = ((ONE - otmRatio * 3) * _initialMarginRatio / ONE).max(MIN_INITIAL_MARGIN_RATIO);
            }
        }
    }

    function _calculateDpmmPrice(
        int256 spotPrice,
        int256 theoreticalPrice,
        int256 delta,
        int256 alpha,
        int256 tradersNetPosition,
        int256 liquidity
    ) internal pure returns (int256 K, int256 dpmmPrice) {
        K = spotPrice ** 2 / theoreticalPrice * delta.abs() * alpha / liquidity / ONE;
        dpmmPrice = theoreticalPrice * (ONE + K * tradersNetPosition / ONE) / ONE;
    }

    function _updateFundingRates(uint256 tradeSymbolId) internal returns (DataSymbol[] memory symbols) {
        uint256 preTimestamp = _lastTimestamp;
        uint256 curTimestamp = block.timestamp;
        symbols = _getSymbols(tradeSymbolId);
        if (curTimestamp > preTimestamp) {
            for (uint256 i = 0; i < symbols.length; i++) {
                DataSymbol memory s = symbols[i];
                int256 ratePerSecond = (s.dpmmPrice - s.intrinsicValue) * s.multiplier / ONE * FUNDING_COEFFICIENT / ONE;
                int256 diff = ratePerSecond * int256(curTimestamp - preTimestamp);
                unchecked { s.cumulativeFundingRate += diff; }
                _symbols[s.symbolId].cumulativeFundingRate = s.cumulativeFundingRate;
            }
        }
        _lastTimestamp = curTimestamp;
    }

    function _getPoolPnl(DataSymbol[] memory symbols) internal pure returns (int256 poolPnl) {
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            int256 cost = s.tradersNetPosition * s.dpmmPrice / ONE;
            poolPnl -= cost - s.tradersNetCost;
        }
    }

    function _getPoolRequiredMargin(DataSymbol[] memory symbols) internal view returns (int256 poolRequiredMargin) {
        int256 poolMarginMultiplier = _poolMarginMultiplier;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            int256 notional = s.tradersNetPosition * s.spotPrice / ONE;
            // pool margin requirement is 10x trader margin requirement
            poolRequiredMargin += notional.abs() * s.dynamicInitialMarginRatio * poolMarginMultiplier / ONE;
        }
    }

    function _settleTraderFundingFee(address account, DataSymbol[] memory symbols)
    internal returns (IPTokenOption.Position[] memory positions, int256 margin)
    {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        positions = new IPTokenOption.Position[](symbols.length);
        margin = pToken.getMargin(account);

        int256 funding;
        for (uint256 i = 0; i < symbols.length; i++) {
            IPTokenOption.Position memory p = pToken.getPosition(account, symbols[i].symbolId);
            if (p.volume != 0) {
                int256 diff;
                unchecked { diff = symbols[i].cumulativeFundingRate - p.lastCumulativeFundingRate; }
                funding += p.volume * diff / ONE;
                p.lastCumulativeFundingRate = symbols[i].cumulativeFundingRate;
                symbols[i].positionUpdated = true;
                positions[i] = p;
            }
        }

        margin -= funding;
        _liquidity += funding;
    }

    function _getTraderMarginStatus(
        DataSymbol[] memory symbols,
        IPTokenOption.Position[] memory positions,
        int256 margin
    ) internal view returns (bool initialMarginSafe, bool maintenanceMarginSafe)
    {
        int256 dynamicMargin = margin;
        int256 requiredInitialMargin;
        for (uint256 i = 0; i < symbols.length; i++) {
            DataSymbol memory s = symbols[i];
            IPTokenOption.Position memory p = positions[i];
            if (p.volume != 0) {
                int256 cost = p.volume * s.dpmmPrice / ONE * s.multiplier / ONE;
                dynamicMargin += cost - p.cost;
                int256 notional = p.volume * s.spotPrice / ONE * s.multiplier / ONE;
                requiredInitialMargin += notional.abs() * s.dynamicInitialMarginRatio / ONE;
            }
        }
        int256 requiredMaintenanceMargin = requiredInitialMargin * _maintenanceMarginRatio / _initialMarginRatio;
        return (
            dynamicMargin >= requiredInitialMargin,
            dynamicMargin >= requiredMaintenanceMargin
        );
    }

    function _updateTraderPortfolio(
        address account,
        DataSymbol[] memory symbols,
        IPTokenOption.Position[] memory positions,
        int256 margin
    ) internal {
        IPTokenOption pToken = IPTokenOption(_pTokenAddress);
        for (uint256 i = 0; i < symbols.length; i++) {
            if (symbols[i].positionUpdated) {
                pToken.updatePosition(account, symbols[i].symbolId, positions[i]);
            }
        }
        pToken.updateMargin(account, margin);
    }

    function _queryTradeDpmm(
        int256 tradersNetPosition,
        int256 theoreticalPrice,
        int256 tradePosition,
        int256 K
    ) internal pure returns (int256 cost) {
        int256 r = ((tradersNetPosition + tradePosition) ** 2 - tradersNetPosition ** 2) / ONE * K / ONE / 2 + tradePosition;
        cost = theoreticalPrice * r / ONE;
    }

    function _transferIn(address from, uint256 bAmount) internal returns (uint256) {
        uint256 amount = bAmount.rescale(18, _decimals);
        require(amount > 0, '0 bAmount');
        IERC20 bToken = IERC20(_bTokenAddress);
        uint256 balance1 = bToken.balanceOf(address(this));
        bToken.safeTransferFrom(from, address(this), amount);
        uint256 balance2 = bToken.balanceOf(address(this));
        return (balance2 - balance1).rescale(_decimals, 18);
    }

    function _transferOut(address to, uint256 bAmount) internal {
        uint256 amount = bAmount.rescale(18, _decimals);
        uint256 leftover = bAmount - amount.rescale(_decimals, 18);
        // leftover due to decimal precision is accrued to _protocolFeeAccrued
        _protocolFeeAccrued += leftover.utoi();
        IERC20(_bTokenAddress).safeTransfer(to, amount);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IERC20 {

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC20.sol';

interface ILTokenOption is IERC20 {

    function pool() external view returns (address);

    function setPool(address newPool) external;

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IERC721.sol';

interface IPTokenOption is IERC721 {

    struct Position {
        // position volume, long is positive and short is negative
        int256 volume;
        // the cost the establish this position
        int256 cost;
        // the last cumulativeFundingRate since last funding settlement for this position
        // the overflow for this value in intended
        int256 lastCumulativeFundingRate;
    }

    event UpdateMargin(address indexed owner, int256 amount);

    event UpdatePosition(address indexed owner, uint256 indexed symbolId, int256 volume, int256 cost, int256 lastCumulativeFundingRate);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function pool() external view returns (address);

    function totalMinted() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function setPool(address newPool) external;

    function getActiveSymbolIds() external view returns (uint256[] memory);

    function isActiveSymbolId(uint256 symbolId) external view returns (bool);

    function getNumPositionHolders(uint256 symbolId) external view returns (uint256);

    function addSymbolId(uint256 symbolId) external;

    function removeSymbolId(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function exists(address owner) external view returns (bool);

    function getMargin(address owner) external view returns (int256);

    function updateMargin(address owner, int256 margin) external;

    function addMargin(address owner, int256 delta) external;

    function getPosition(address owner, uint256 symbolId) external view returns (Position memory);

    function updatePosition(address owner, uint256 symbolId, Position memory position) external;

    function mint(address owner) external;

    function burn(address owner) external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IEverlastingOptionPricing {

    function getEverlastingTimeValue(int256 S, int256 K, int256 V, int256 T) external pure returns (int256);

    function getEverlastingTimeValueAndDelta(int256 S, int256 K, int256 V, int256 T) external pure returns (int256, int256);

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IOracleViewer {

    function getPrice() external view returns (uint256);

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IVolatilityOracle {

    function getVolatility() external view returns (uint256);

    function updateVolatility(uint256 timestamp_, uint256 volatility_, uint8 v_, bytes32 r_, bytes32 s_) external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ILiquidatorQualifier {

    function isQualifiedLiquidator(address liquidator) external view returns (bool);

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';

interface IEverlastingOption is IMigratable {

    struct SymbolInfo {
        uint256 symbolId;
        string  symbol;
        address oracleAddress;
        address volatilityAddress;
        bool    isCall;
        int256  strikePrice;
        int256  multiplier;
        int256  feeRatioITM;
        int256  feeRatioOTM;
        int256  alpha;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
    }

    struct SignedValue {
        uint256 symbolId;
        uint256 timestamp;
        uint256 value;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    event AddLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event AddMargin(address indexed account, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, int256 tradeCost,
                int256 liquidity, int256 tradersNetVolume, int256 spotPrice, int256 volatility);

    event Liquidate(address indexed account, address indexed liquidator, uint256 reward);

    event ProtocolFeeCollection(address indexed collector, uint256 amount);

    function getParameters() external view returns (
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    );

    function getAddresses() external view returns (
        address bTokenAddress,
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolFeeCollector,
        address optionPricerAddress
    );

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getPoolStateValues() external view returns (int256 liquidity, uint256 lastTimestamp, int256 protocolFeeAccrued);

    function collectProtocolFee() external;

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        address volatilityAddress,
        bool    isCall,
        uint256 strikePrice,
        uint256 multiplier,
        uint256 feeRatioITM,
        uint256 feeRatioOTM,
        uint256 alpha
    ) external;

    function removeSymbol(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function getPoolMarginMultiplier() external view returns (int256);

    function setPoolMarginMulitplier(uint256 multiplier) external;

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatioITM,
        uint256 feeRatioOTM,
        uint256 alpha
    ) external;

    function addLiquidity(uint256 bAmount, SignedValue[] memory volatilities) external;

    function removeLiquidity(uint256 lShares, SignedValue[] memory volatilities) external;

    function addMargin(uint256 bAmount) external;

    function removeMargin(uint256 bAmount, SignedValue[] memory volatilities) external;

    function trade(uint256 symbolId, int256 tradeVolume, SignedValue[] memory volatilities) external;

    function liquidate(address account, SignedValue[] memory volatilities) external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';

interface IEverlastingOptionOld is IMigratable {

    struct SymbolInfo {
        uint256 symbolId;
        string  symbol;
        address oracleAddress;
        address volatilityAddress;
        bool    isCall;
        int256  strikePrice;
        int256  multiplier;
        int256  feeRatio;
        int256  alpha;
        int256  tradersNetVolume;
        int256  tradersNetCost;
        int256  cumulativeFundingRate;
    }

    struct SignedValue {
        uint256 symbolId;
        uint256 timestamp;
        uint256 value;
        uint8   v;
        bytes32 r;
        bytes32 s;
    }

    event AddLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event RemoveLiquidity(address indexed account, uint256 lShares, uint256 bAmount);

    event AddMargin(address indexed account, uint256 bAmount);

    event RemoveMargin(address indexed account, uint256 bAmount);

    event Trade(address indexed account, uint256 indexed symbolId, int256 tradeVolume, int256 tradeCost);

    event Liquidate(address indexed account, address indexed liquidator, uint256 reward);

    event ProtocolFeeCollection(address indexed collector, uint256 amount);

    function getParameters() external view returns (
        int256 minInitialMarginRatio,
        int256 minMaintenanceMarginRatio,
        int256 minLiquidationReward,
        int256 maxLiquidationReward,
        int256 liquidationCutRatio,
        int256 protocolFeeCollectRatio
    );

    function getAddresses() external view returns (
        address bTokenAddress,
        address lTokenAddress,
        address pTokenAddress,
        address liquidatorQualifierAddress,
        address protocolFeeCollector,
        address optionPricerAddress
    );

    function getSymbol(uint256 symbolId) external view returns (SymbolInfo memory);

    function getPoolStateValues() external view returns (int256 liquidity, uint256 lastTimestamp, int256 protocolFeeAccrued);

    function collectProtocolFee() external;

    function addSymbol(
        uint256 symbolId,
        string  memory symbol,
        address oracleAddress,
        address volatilityAddress,
        bool    isCall,
        uint256 strikePrice,
        uint256 multiplier,
        uint256 feeRatio,
        uint256 alpha
    ) external;

    function removeSymbol(uint256 symbolId) external;

    function toggleCloseOnly(uint256 symbolId) external;

    function getPoolMarginMultiplier() external view returns (int256);

    function setPoolMarginMulitplier(uint256 multiplier) external;

    function setSymbolParameters(
        uint256 symbolId,
        address oracleAddress,
        address volatilityAddress,
        uint256 feeRatio,
        uint256 alpha
    ) external;

    function addLiquidity(uint256 bAmount, SignedValue[] memory volatilities) external;

    function removeLiquidity(uint256 lShares, SignedValue[] memory volatilities) external;

    function addMargin(uint256 bAmount) external;

    function removeMargin(uint256 bAmount, SignedValue[] memory volatilities) external;

    function trade(uint256 symbolId, int256 tradeVolume, SignedValue[] memory volatilities) external;

    function liquidate(address account, SignedValue[] memory volatilities) external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library SafeMath {

    uint256 constant UMAX = 2**255 - 1;
    int256  constant IMIN = -2**255;

    /// convert uint256 to int256
    function utoi(uint256 a) internal pure returns (int256) {
        require(a <= UMAX, 'UIO');
        return int256(a);
    }

    /// convert int256 to uint256
    function itou(int256 a) internal pure returns (uint256) {
        require(a >= 0, 'IUO');
        return uint256(a);
    }

    /// take abs of int256
    function abs(int256 a) internal pure returns (int256) {
        require(a != IMIN, 'AO');
        return a >= 0 ? a : -a;
    }


    /// rescale a uint256 from base 10**decimals1 to 10**decimals2
    function rescale(uint256 a, uint256 decimals1, uint256 decimals2) internal pure returns (uint256) {
        return decimals1 == decimals2 ? a : a * (10 ** decimals2) / (10 ** decimals1);
    }

    /// rescale a int256 from base 10**decimals1 to 10**decimals2
    function rescale(int256 a, uint256 decimals1, uint256 decimals2) internal pure returns (int256) {
        return decimals1 == decimals2 ? a : a * utoi(10 ** decimals2) / utoi(10 ** decimals1);
    }

    /// reformat a uint256 to be a valid 10**decimals base value
    /// the reformatted value is still in 10**18 base
    function reformat(uint256 a, uint256 decimals) internal pure returns (uint256) {
        return decimals == 18 ? a : rescale(rescale(a, 18, decimals), decimals, 18);
    }

    /// reformat a int256 to be a valid 10**decimals base value
    /// the reformatted value is still in 10**18 base
    function reformat(int256 a, uint256 decimals) internal pure returns (int256) {
        return decimals == 18 ? a : rescale(rescale(a, 18, decimals), decimals, 18);
    }

    /// ceiling value away from zero, return a valid 10**decimals base value, but still in 10**18 based
    function ceil(int256 a, uint256 decimals) internal pure returns (int256) {
        if (reformat(a, decimals) == a) {
            return a;
        } else {
            int256 b = rescale(a, 18, decimals);
            b += a > 0 ? int256(1) : int256(-1);
            return rescale(b, decimals, 18);
        }
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 quotient = a / b;
        uint256 remainder = a - quotient * b;
        if (remainder > 0) {
            return quotient + 1;
        } else {
            return quotient;
        }
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = x / 2 + 1;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function max(int256 a, int256 b) internal pure returns (int256) {
        return a >= b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function min(int256 a, int256 b) internal pure returns (int256) {
        return a <= b ? a : b;
    }

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../interface/IERC20.sol";
import "./Address.sol";

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
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) - value;
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

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IMigratable.sol';
import './Ownable.sol';

abstract contract Migratable is IMigratable, Ownable {

    // migration timestamp, zero means not set
    // migration timestamp can only be set with a grace period, e.x. 3-365 days, and the
    // migration destination must also be set when setting migration timestamp
    // users can use this grace period to verify the desination contract code
    uint256 _migrationTimestamp;

    // the destination address the source contract will migrate to, after the grace period
    address _migrationDestination;

    function migrationTimestamp() public override view returns (uint256) {
        return _migrationTimestamp;
    }

    function migrationDestination() public override view returns (address) {
        return _migrationDestination;
    }

    // prepare a migration process, the timestamp and desination will be set at this stage
    // and the migration grace period starts
    function prepareMigration(address target, uint256 graceDays) public override _controller_ {
        require(target != address(0), 'Migratable: target 0');
        require(graceDays >= 3 && graceDays <= 365, 'Migratable: graceDays must be 3-365');

        _migrationTimestamp = block.timestamp + graceDays * 1 days;
        _migrationDestination = target;

        emit PrepareMigration(_migrationTimestamp, address(this), _migrationDestination);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `operator` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed operator, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in `owner`'s account.
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev Returns the 'tokenId' owned by 'owner'
     *
     * Requirements:
     *
     *  - `owner` must exist
     */
    function getTokenId(address owner) external view returns (uint256);

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @dev Gives permission to `operator` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address
     * clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address operator, uint256 tokenId) external;

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
    function setApprovalForAll(address operator, bool approved) external;

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
     * - If the caller is not `from`, it must be approved to move this token
     *   by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first
     * that contract recipients are aware of the ERC721 protocol to prevent
     * tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token
     *   by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement
     *   {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token
     *   by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement
     *   {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

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

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './IOwnable.sol';

interface IMigratable is IOwnable {

    event PrepareMigration(uint256 migrationTimestamp, address source, address target);

    event ExecuteMigration(uint256 migrationTimestamp, address source, address target);

    function migrationTimestamp() external view returns (uint256);

    function migrationDestination() external view returns (address);

    function prepareMigration(address target, uint256 graceDays) external;

    function approveMigration() external;

    function executeMigration(address source) external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface IOwnable {

    event ChangeController(address oldController, address newController);

    function controller() external view returns (address);

    function setNewController(address newController) external;

    function claimNewController() external;

}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

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

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IOwnable.sol';

abstract contract Ownable is IOwnable {

    address _controller;

    address _newController;

    modifier _controller_() {
        require(msg.sender == _controller, 'Ownable: only controller');
        _;
    }

    function controller() public override view returns (address) {
        return _controller;
    }

    function setNewController(address newController) public override _controller_ {
        _newController = newController;
    }

    // a claim step is needed to prevent set controller to a wrong address and forever lost control
    function claimNewController() public override {
        require(msg.sender == _newController, 'Ownable: not allowed');
        emit ChangeController(_controller, _newController);
        _controller = _newController;
        delete _newController;
    }

}

