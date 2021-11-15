// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../tokens/interfaces/INUSD.sol";
import "../tokens/interfaces/IRewardToken.sol";
import "../tokens/interfaces/IDistributor.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultPriceFeed.sol";

contract Vault is ReentrancyGuard, IVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    uint256 public constant override BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;
    uint256 public constant PRICE_PRECISION = 10**30;
    uint256 public constant NUSD_DECIMALS = 18;
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5%
    uint256 public constant MAX_LIQUIDATION_FEE_USD = 100 * PRICE_PRECISION; // 100 USD
    uint256 public constant MIN_FUNDING_RATE_INTERVAL = 1 hours;
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 10000; // 1%

    bool public isInitialized;
    bool public isMintingEnabled = false;
    bool public isSwapEnabled = true;

    address public router;
    address public override priceFeed;

    address public nusd;
    address public gov;
    address public override rewardDistributor;

    uint256 public maxNUSDBatchSize;
    uint256 public maxNUSDBuffer;
    uint256 public whitelistedTokenCount;

    uint256 public maxLeverage = 50 * 10000; // 50x

    uint256 public liquidationFeeUsd;
    uint256 public override swapFeeBasisPoints = 30; // 0.3%
    uint256 public override stableSwapFeeBasisPoints = 4; // 0.04%
    uint256 public override rewardRedemptionBasisPoints = 5000; // 50%
    uint256 public marginFeeBasisPoints = 10; // 0.1%
    uint256 public minProfitTime = 1800; // 30 minutes

    uint256 public fundingInterval = 8 hours;
    uint256 public override fundingRateFactor;

    uint256 public maxDebtBasisPoints;

    bool public includeAmmPrice = true;

    mapping(address => mapping(address => bool)) public approvedRouters;

    mapping(address => bool) public whitelistedTokens;
    mapping(address => uint256) public override tokenDecimals;
    mapping(address => uint256) public redemptionBasisPoints;
    mapping(address => uint256) public minProfitBasisPoints;
    mapping(address => bool) public override stableTokens;
    mapping(address => bool) public shortableTokens;

    // tokenBalances is used only to determine _transferIn values
    mapping(address => uint256) public tokenBalances;

    // nusdAmounts tracks the amount of NUSD debt for each whitelisted token
    mapping(address => uint256) public override nusdAmounts;

    // poolAmounts tracks the number of received tokens that can be used for leverage
    // this is tracked separately from tokenBalances to exclude funds that are deposited as margin collateral
    mapping(address => uint256) public override poolAmounts;

    // reservedAmounts tracks the number of tokens reserved for open leverage positions
    mapping(address => uint256) public override reservedAmounts;

    // guaranteedUsd tracks the amount of USD that is "guaranteed" by opened leverage positions
    // this value is used to calculate the redemption values for selling of NUSD
    // this is an estimated amount, it is possible for the actual guaranteed value to be lower
    // in the case of sudden price decreases, the guaranteed value should be corrected
    // after liquidations are carried out
    mapping(address => uint256) public override guaranteedUsd;

    mapping(address => uint256) public override cumulativeFundingRates;
    mapping(address => uint256) public lastFundingTimes;

    mapping(bytes32 => Position) public positions;

    mapping(address => uint256) public override feeReserves;

    event BuyNUSD(
        address account,
        address token,
        uint256 tokenAmount,
        uint256 nusdAmount
    );
    event SellNUSD(
        address account,
        address token,
        uint256 nusdAmount,
        uint256 tokenAmount
    );
    event Swap(
        address account,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event IncreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );
    event DecreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );
    event LiquidatePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 reserveAmount,
        int256 realisedPnl,
        uint256 markPrice
    );
    event UpdatePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryFundingRate,
        uint256 reserveAmount,
        int256 realisedPnl
    );
    event ClosePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryFundingRate,
        uint256 reserveAmount,
        int256 realisedPnl
    );

    event UpdateFundingRate(address token, uint256 fundingRate);
    event UpdatePnl(bytes32 key, bool hasProfit, uint256 delta);

    event CollectSwapFees(address token, uint256 feeUsd, uint256 feeTokens);
    event CollectMarginFees(address token, uint256 feeUsd, uint256 feeTokens);

    event DirectPoolDeposit(address token, uint256 amount);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event IncreaseNUSDAmount(address token, uint256 amount);
    event DecreaseNUSDAmount(address token, uint256 amount);
    event IncreaseReservedAmount(address token, uint256 amount);
    event DecreaseReservedAmount(address token, uint256 amount);
    event IncreaseGuaranteedUsd(address token, uint256 amount);
    event DecreaseGuaranteedUsd(address token, uint256 amount);
    event RedeemReward(uint256 amount, address receiver);

    // once the parameters are verified to be working correctly,
    // gov should be set to a timelock contract or a governance contract
    constructor() {
        gov = msg.sender;
    }

    function initialize(
        address _router,
        address _nusd,
        address _priceFeed,
        uint256 _maxNUSDBatchSize,
        uint256 _maxNUSDBuffer,
        uint256 _liquidationFeeUsd,
        uint256 _fundingRateFactor,
        uint256 _maxDebtBasisPoints
    ) external {
        _onlyGov();
        require(!isInitialized, "Vault: already initialized");
        isInitialized = true;

        router = _router;
        nusd = _nusd;
        priceFeed = _priceFeed;
        maxNUSDBatchSize = _maxNUSDBatchSize;
        maxNUSDBuffer = _maxNUSDBuffer;
        liquidationFeeUsd = _liquidationFeeUsd;
        fundingRateFactor = _fundingRateFactor;
        maxDebtBasisPoints = _maxDebtBasisPoints;
    }

    function setIsMintingEnabled(bool _isMintingEnabled) external override {
        _onlyGov();
        isMintingEnabled = _isMintingEnabled;
    }

    function setIsSwapEnabled(bool _isSwapEnabled) external override {
        _onlyGov();
        isSwapEnabled = _isSwapEnabled;
    }

    function setGov(address _gov) external {
        _onlyGov();
        gov = _gov;
    }

    function setPriceFeed(address _priceFeed) external override {
        _onlyGov();
        priceFeed = _priceFeed;
    }

    function setRewardDistributor(address _rewardDistributor) external {
        _onlyGov();
        rewardDistributor = _rewardDistributor;
    }

    function setRewardRedemptionBasisPoints(
        uint256 _rewardRedemptionBasisPoints
    ) external override {
        _onlyGov();
        rewardRedemptionBasisPoints = _rewardRedemptionBasisPoints;
    }

    function setMaxNUSD(uint256 _maxNUSDBatchSize, uint256 _maxNUSDBuffer)
        external
        override
    {
        _onlyGov();
        maxNUSDBatchSize = _maxNUSDBatchSize;
        maxNUSDBuffer = _maxNUSDBuffer;
    }

    function setMaxDebtBasisPoints(uint256 _maxDebtBasisPoints) external {
        _onlyGov();
        require(_maxDebtBasisPoints > 0, "Vault: invalid _maxDebtBasisPoints");
        maxDebtBasisPoints = _maxDebtBasisPoints;
    }

    function setFees(
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd
    ) external override {
        _onlyGov();
        require(
            _swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS,
            "Vault: invalid _swapFeeBasisPoints"
        );
        require(
            _stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS,
            "Vault: invalid _stableSwapFeeBasisPoints"
        );
        require(
            _marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS,
            "Vault: invalid _marginFeeBasisPoints"
        );
        require(
            _liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD,
            "Vault: invalid _liquidationFeeUsd"
        );
        swapFeeBasisPoints = _swapFeeBasisPoints;
        stableSwapFeeBasisPoints = _stableSwapFeeBasisPoints;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
    }

    function setFundingRate(
        uint256 _fundingInterval,
        uint256 _fundingRateFactor
    ) external {
        _onlyGov();
        require(
            _fundingInterval >= MIN_FUNDING_RATE_INTERVAL,
            "Vault: invalid _fundingInterval"
        );
        require(
            _fundingRateFactor <= MAX_FUNDING_RATE_FACTOR,
            "Vault: invalid _fundingRateFactor"
        );
        fundingInterval = _fundingInterval;
        fundingRateFactor = _fundingRateFactor;
    }

    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _redemptionBps,
        uint256 _minProfitBps,
        bool _isStable,
        bool _isShortable
    ) external {
        _onlyGov();
        // increment token count for the first time
        if (!whitelistedTokens[_token]) {
            whitelistedTokenCount = whitelistedTokenCount.add(1);
        }
        whitelistedTokens[_token] = true;
        tokenDecimals[_token] = _tokenDecimals;
        redemptionBasisPoints[_token] = _redemptionBps;
        minProfitBasisPoints[_token] = _minProfitBps;
        stableTokens[_token] = _isStable;
        shortableTokens[_token] = _isShortable;

        // validate price feed
        getMaxPrice(_token);
    }

    function clearTokenConfig(address _token) external {
        _onlyGov();
        require(whitelistedTokens[_token], "Vault: token not whitelisted");
        delete whitelistedTokens[_token];
        delete tokenDecimals[_token];
        delete redemptionBasisPoints[_token];
        delete minProfitBasisPoints[_token];
        delete stableTokens[_token];
        delete shortableTokens[_token];
        whitelistedTokenCount = whitelistedTokenCount.sub(1);
    }

    function addRouter(address _router) external {
        approvedRouters[msg.sender][_router] = true;
    }

    function removeRouter(address _router) external {
        approvedRouters[msg.sender][_router] = false;
    }

    // deposit into the pool without minting NUSD tokens
    // useful in allowing the pool to become over-collaterised
    function directPoolDeposit(address _token) external override nonReentrant {
        require(whitelistedTokens[_token], "Vault: _token not whitelisted");
        uint256 tokenAmount = _transferIn(_token);
        require(tokenAmount > 0, "Vault: invalid tokenAmount");
        _increasePoolAmount(_token, tokenAmount);
        emit DirectPoolDeposit(_token, tokenAmount);
    }

    function redeemReward(uint256 _amount, address _receiver)
        external
        override
        nonReentrant
        returns (uint256[] memory)
    {
        require(
            rewardDistributor != address(0),
            "Vault: no reward distributor"
        );
        address _rewardToken = IDistributor(rewardDistributor).getRewardToken();
        require(
            _amount <= IERC20(_rewardToken).balanceOf(msg.sender),
            "Vault: not enough reward balance"
        );
        address[] memory _collaterals = IDistributor(rewardDistributor)
            .getCollaterals();
        uint256[] memory _amounts = new uint256[](_collaterals.length);

        uint256 _rewardTokenCirculatingSupply = IRewardToken(_rewardToken)
            .circulatingSupply();
        IRewardToken(_rewardToken).burn(msg.sender, _amount);
        for (uint256 i = 0; i < _collaterals.length; i++) {
            if (feeReserves[_collaterals[i]] == 0) {
                _amounts[i] = 0;
                continue;
            }

            uint256 _shareAmount = feeReserves[_collaterals[i]]
                .mul(rewardRedemptionBasisPoints)
                .div(BASIS_POINTS_DIVISOR)
                .mul(_amount)
                .div(_rewardTokenCirculatingSupply);

            _transferOut(_collaterals[i], _shareAmount, _receiver);

            feeReserves[_collaterals[i]] = feeReserves[_collaterals[i]].sub(
                _shareAmount
            );
            _amounts[i] = _shareAmount;
        }

        emit RedeemReward(_amount, _receiver);

        return _amounts;
    }

    function withdrawFees(address _token, address _receiver)
        external
        override
        returns (uint256)
    {
        _onlyGov();
        uint256 amount = feeReserves[_token];
        if (amount == 0) {
            return 0;
        }
        feeReserves[_token] = 0;
        _transferOut(_token, amount, _receiver);
        return amount;
    }

    function buyNUSD(address _token, address _receiver)
        external
        override
        nonReentrant
        returns (uint256)
    {
        if (_receiver != gov) {
            require(isMintingEnabled, "Vault: minting not enabled");
        }
        require(whitelistedTokens[_token], "Vault: _token not whitelisted");

        uint256 tokenAmount = _transferIn(_token);
        require(tokenAmount > 0, "Vault: invalid tokenAmount");

        updateCumulativeFundingRate(_token);

        uint256 price = getMinPrice(_token);

        uint256 amountAfterFees = _collectSwapFees(
            _token,
            tokenAmount,
            stableTokens[_token]
        );
        uint256 nusdAmount = amountAfterFees.mul(price).div(PRICE_PRECISION);
        nusdAmount = adjustForDecimals(nusdAmount, _token, nusd);
        require(nusdAmount > 0, "Vault: invalid nusdAmount");

        _increaseNUSDAmount(_token, nusdAmount);
        _increasePoolAmount(_token, amountAfterFees);

        INUSD(nusd).mint(_receiver, nusdAmount);

        emit BuyNUSD(_receiver, _token, tokenAmount, nusdAmount);

        return nusdAmount;
    }

    function sellNUSD(address _token, address _receiver)
        external
        override
        nonReentrant
        returns (uint256)
    {
        require(whitelistedTokens[_token], "Vault: _token not whitelisted");

        uint256 nusdAmount = _transferIn(nusd);
        require(nusdAmount > 0, "Vault: invalid nusdAmount");

        updateCumulativeFundingRate(_token);

        uint256 redemptionAmount = getRedemptionAmount(_token, nusdAmount);
        require(redemptionAmount > 0, "Vault: invalid redemptionAmount");

        _decreaseNUSDAmount(_token, nusdAmount);
        _decreasePoolAmount(_token, redemptionAmount);

        INUSD(nusd).burn(address(this), nusdAmount);

        // the _transferIn call increased the value of tokenBalances[nusd]
        // usually decreases in token balances are synced by calling _transferOut
        // however, for nusd, the tokens are burnt, so _updateTokenBalance should
        // be manually called to record the decrease in tokens
        _updateTokenBalance(nusd);

        uint256 tokenAmount = _collectSwapFees(
            _token,
            redemptionAmount,
            stableTokens[_token]
        );
        require(tokenAmount > 0, "Vault: invalid tokenAmount");
        _transferOut(_token, tokenAmount, _receiver);

        emit SellNUSD(_receiver, _token, nusdAmount, tokenAmount);

        return tokenAmount;
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        require(isSwapEnabled, "Vault: swaps not enabled");
        require(whitelistedTokens[_tokenIn], "Vault: _tokenIn not whitelisted");
        require(
            whitelistedTokens[_tokenOut],
            "Vault: _tokenOut not whitelisted"
        );
        require(_tokenIn != _tokenOut, "Vault: invalid tokens");
        updateCumulativeFundingRate(_tokenIn);
        updateCumulativeFundingRate(_tokenOut);

        uint256 amountIn = _transferIn(_tokenIn);
        require(amountIn > 0, "Vault: invalid amountIn");

        uint256 priceIn = getMinPrice(_tokenIn);
        uint256 priceOut = getMaxPrice(_tokenOut);

        uint256 amountOut = amountIn.mul(priceIn).div(priceOut);
        amountOut = adjustForDecimals(amountOut, _tokenIn, _tokenOut);
        uint256 amountOutAfterFees = _collectSwapFees(
            _tokenOut,
            amountOut,
            stableTokens[_tokenIn] && stableTokens[_tokenOut]
        );

        // adjust nusdAmounts by the same nusdAmount as debt is shifted between the assets
        uint256 nusdAmount = amountIn.mul(priceIn).div(PRICE_PRECISION);
        nusdAmount = adjustForDecimals(nusdAmount, _tokenIn, nusd);

        _increaseNUSDAmount(_tokenIn, nusdAmount);
        _decreaseNUSDAmount(_tokenOut, nusdAmount);

        _increasePoolAmount(_tokenIn, amountIn);
        _decreasePoolAmount(_tokenOut, amountOut);

        uint256 nusdDebt = nusdAmounts[_tokenOut].mul(PRICE_PRECISION).div(
            10**NUSD_DECIMALS
        );
        if (
            !stableTokens[_tokenOut] &&
            getRedemptionCollateralUsd(_tokenOut).mul(maxDebtBasisPoints) <
            nusdDebt.mul(BASIS_POINTS_DIVISOR)
        ) {
            revert("Vault: max debt exceeded");
        }

        _transferOut(_tokenOut, amountOutAfterFees, _receiver);

        emit Swap(_receiver, _tokenIn, _tokenOut, amountIn, amountOutAfterFees);

        return amountOutAfterFees;
    }

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external override nonReentrant {
        _validateRouter(_account);
        _validateTokens(_collateralToken, _indexToken, _isLong);
        updateCumulativeFundingRate(_collateralToken);

        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position storage position = positions[key];

        uint256 price = _isLong
            ? getMaxPrice(_indexToken)
            : getMinPrice(_indexToken);

        if (position.size == 0) {
            position.averagePrice = price;
        }

        if (position.size > 0 && _sizeDelta > 0) {
            position.averagePrice = getNextAveragePrice(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong,
                price,
                _sizeDelta,
                position.lastIncreasedTime
            );
        }

        uint256 fee = _collectMarginFees(
            _collateralToken,
            _sizeDelta,
            position.size,
            position.entryFundingRate
        );
        uint256 collateralDelta = _transferIn(_collateralToken);
        uint256 collateralDeltaUsd = tokenToUsdMin(
            _collateralToken,
            collateralDelta
        );

        position.collateral = position.collateral.add(collateralDeltaUsd);
        require(
            position.collateral >= fee,
            "Vault: insufficient collateral for fees"
        );

        position.collateral = position.collateral.sub(fee);
        position.entryFundingRate = cumulativeFundingRates[_collateralToken];
        position.size = position.size.add(_sizeDelta);
        position.lastIncreasedTime = block.timestamp;

        require(position.size > 0, "Vault: invalid position.size");
        _validatePosition(position.size, position.collateral);
        validateLiquidation(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            true
        );

        // reserve tokens to pay profits on the position
        uint256 reserveDelta = usdToTokenMax(_collateralToken, _sizeDelta);
        position.reserveAmount = position.reserveAmount.add(reserveDelta);
        _increaseReservedAmount(_collateralToken, reserveDelta);

        if (_isLong) {
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            _increaseGuaranteedUsd(_collateralToken, _sizeDelta.add(fee));
            _decreaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            _increasePoolAmount(_collateralToken, collateralDelta);
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            _decreasePoolAmount(
                _collateralToken,
                usdToTokenMin(_collateralToken, fee)
            );
        }

        emit IncreasePosition(
            key,
            _account,
            _collateralToken,
            _indexToken,
            collateralDeltaUsd,
            _sizeDelta,
            _isLong,
            price,
            fee
        );
        emit UpdatePosition(
            key,
            position.size,
            position.collateral,
            position.averagePrice,
            position.entryFundingRate,
            position.reserveAmount,
            position.realisedPnl
        );
    }

    function decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateRouter(_account);
        _validateTokens(_collateralToken, _indexToken, _isLong);

        return
            _decreasePosition(
                _account,
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                _receiver
            );
    }

    function _decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) private returns (uint256) {
        updateCumulativeFundingRate(_collateralToken);

        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position storage position = positions[key];
        require(position.size > 0, "Vault: empty position");
        require(position.size >= _sizeDelta, "Vault: position size exceeded");
        require(
            position.collateral >= _collateralDelta,
            "Vault: position collateral exceeded"
        );

        uint256 collateral = position.collateral;
        // scrop variables to avoid stack too deep errors
        {
            uint256 reserveDelta = position.reserveAmount.mul(_sizeDelta).div(
                position.size
            );
            position.reserveAmount = position.reserveAmount.sub(reserveDelta);
            _decreaseReservedAmount(_collateralToken, reserveDelta);
        }

        (uint256 usdOut, uint256 usdOutAfterFee) = _reduceCollateral(
            _account,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong
        );

        if (position.size != _sizeDelta) {
            position.entryFundingRate = cumulativeFundingRates[
                _collateralToken
            ];
            position.size = position.size.sub(_sizeDelta);

            _validatePosition(position.size, position.collateral);
            validateLiquidation(
                _account,
                _collateralToken,
                _indexToken,
                _isLong,
                true
            );

            if (_isLong) {
                _increaseGuaranteedUsd(
                    _collateralToken,
                    collateral.sub(position.collateral)
                );
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong
                ? getMinPrice(_indexToken)
                : getMaxPrice(_indexToken);
            emit DecreasePosition(
                key,
                _account,
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                price,
                usdOut.sub(usdOutAfterFee)
            );
            emit UpdatePosition(
                key,
                position.size,
                position.collateral,
                position.averagePrice,
                position.entryFundingRate,
                position.reserveAmount,
                position.realisedPnl
            );
        } else {
            if (_isLong) {
                _increaseGuaranteedUsd(_collateralToken, collateral);
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong
                ? getMinPrice(_indexToken)
                : getMaxPrice(_indexToken);
            emit DecreasePosition(
                key,
                _account,
                _collateralToken,
                _indexToken,
                _collateralDelta,
                _sizeDelta,
                _isLong,
                price,
                usdOut.sub(usdOutAfterFee)
            );
            emit ClosePosition(
                key,
                position.size,
                position.collateral,
                position.averagePrice,
                position.entryFundingRate,
                position.reserveAmount,
                position.realisedPnl
            );

            delete positions[key];
        }

        if (usdOut > 0) {
            if (_isLong) {
                _decreasePoolAmount(
                    _collateralToken,
                    usdToTokenMin(_collateralToken, usdOut)
                );
            }
            uint256 amountOutAfterFees = usdToTokenMin(
                _collateralToken,
                usdOutAfterFee
            );
            _transferOut(_collateralToken, amountOutAfterFees, _receiver);
            return amountOutAfterFees;
        }

        return 0;
    }

    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external nonReentrant {
        // set includeAmmPrice to false prevent manipulated liquidations
        includeAmmPrice = false;

        _validateTokens(_collateralToken, _indexToken, _isLong);
        updateCumulativeFundingRate(_collateralToken);

        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];
        require(position.size > 0, "Vault: empty position");

        (uint256 liquidationState, uint256 marginFees) = validateLiquidation(
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            false
        );
        require(liquidationState != 0, "Vault: position cannot be liquidated");
        // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
        if (liquidationState == 2) {
            _decreasePosition(
                _account,
                _collateralToken,
                _indexToken,
                0,
                position.size,
                _isLong,
                _account
            );
            return;
        }

        feeReserves[_collateralToken] = feeReserves[_collateralToken].add(
            usdToTokenMin(_collateralToken, marginFees)
        );

        _decreaseReservedAmount(_collateralToken, position.reserveAmount);
        if (_isLong) {
            _decreaseGuaranteedUsd(
                _collateralToken,
                position.size.sub(position.collateral)
            );
        }

        uint256 markPrice = _isLong
            ? getMinPrice(_indexToken)
            : getMaxPrice(_indexToken);
        emit LiquidatePosition(
            key,
            _account,
            _collateralToken,
            _indexToken,
            _isLong,
            position.size,
            position.collateral,
            position.reserveAmount,
            position.realisedPnl,
            markPrice
        );

        if (!_isLong && marginFees < position.collateral) {
            uint256 remainingCollateral = position.collateral.sub(marginFees);
            _increasePoolAmount(
                _collateralToken,
                usdToTokenMin(_collateralToken, remainingCollateral)
            );
        }

        delete positions[key];

        // pay the fee receiver using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
        _decreasePoolAmount(
            _collateralToken,
            usdToTokenMin(_collateralToken, liquidationFeeUsd)
        );
        _transferOut(
            _collateralToken,
            usdToTokenMin(_collateralToken, liquidationFeeUsd),
            _feeReceiver
        );

        includeAmmPrice = true;
    }

    function validateLiquidation(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        bool _raise
    )
        public
        view
        returns (
            // returns (state, fees)
            uint256,
            uint256
        )
    {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];

        (bool hasProfit, uint256 delta) = getDelta(
            _indexToken,
            position.size,
            position.averagePrice,
            _isLong,
            position.lastIncreasedTime
        );
        uint256 marginFees = getFundingFee(
            _collateralToken,
            position.size,
            position.entryFundingRate
        );
        marginFees = marginFees.add(getPositionFee(position.size));

        if (!hasProfit && position.collateral < delta) {
            if (_raise) {
                revert("Vault: losses exceed collateral");
            }
            return (1, marginFees);
        }

        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral.sub(delta);
        }

        if (remainingCollateral < marginFees) {
            if (_raise) {
                revert("Vault: fees exceed collateral");
            }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral);
        }

        if (remainingCollateral < marginFees.add(liquidationFeeUsd)) {
            if (_raise) {
                revert("Vault: liquidation fees exceed collateral");
            }
            return (1, marginFees);
        }

        if (
            remainingCollateral.mul(maxLeverage) <
            position.size.mul(BASIS_POINTS_DIVISOR)
        ) {
            if (_raise) {
                revert("Vault: maxLeverage exceeded");
            }
            return (2, marginFees);
        }

        return (0, marginFees);
    }

    function getMaxPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        return
            IVaultPriceFeed(priceFeed).getPrice(_token, true, includeAmmPrice);
    }

    function getMinPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        return
            IVaultPriceFeed(priceFeed).getPrice(_token, false, includeAmmPrice);
    }

    function getRedemptionAmount(address _token, uint256 _nusdAmount)
        public
        view
        override
        returns (uint256)
    {
        uint256 price = getMaxPrice(_token);
        uint256 priceBasedAmount = _nusdAmount.mul(PRICE_PRECISION).div(price);
        priceBasedAmount = adjustForDecimals(priceBasedAmount, nusd, _token);

        if (stableTokens[_token]) {
            return priceBasedAmount;
        }

        uint256 redemptionCollateral = getRedemptionCollateral(_token);
        if (redemptionCollateral == 0) {
            return 0;
        }

        uint256 totalNUSDAmount = nusdAmounts[_token];

        // if there is no NUSD debt then the redemption amount based just on price can be supported
        if (totalNUSDAmount == 0) {
            return priceBasedAmount;
        }

        // calculate the collateralBasedAmount from the amount of backing collateral and the
        // total debt in NUSD tokens for the asset
        uint256 collateralBasedAmount = _nusdAmount
            .mul(redemptionCollateral)
            .div(totalNUSDAmount);
        uint256 basisPoints = getRedemptionBasisPoints(_token);
        collateralBasedAmount = collateralBasedAmount.mul(basisPoints).div(
            BASIS_POINTS_DIVISOR
        );

        return
            collateralBasedAmount < priceBasedAmount
                ? collateralBasedAmount
                : priceBasedAmount;
    }

    function getRedemptionCollateral(address _token)
        public
        view
        returns (uint256)
    {
        if (stableTokens[_token]) {
            return poolAmounts[_token];
        }
        uint256 collateral = usdToTokenMin(_token, guaranteedUsd[_token]);
        return collateral.add(poolAmounts[_token]).sub(reservedAmounts[_token]);
    }

    function getRedemptionCollateralUsd(address _token)
        public
        view
        override
        returns (uint256)
    {
        return tokenToUsdMin(_token, getRedemptionCollateral(_token));
    }

    function getRedemptionBasisPoints(address _token)
        public
        view
        returns (uint256)
    {
        return redemptionBasisPoints[_token];
    }

    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) public view override returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == nusd
            ? NUSD_DECIMALS
            : tokenDecimals[_tokenDiv];
        uint256 decimalsMul = _tokenMul == nusd
            ? NUSD_DECIMALS
            : tokenDecimals[_tokenMul];
        return _amount.mul(10**decimalsMul).div(10**decimalsDiv);
    }

    function availableReserve(address _token) public view returns (uint256) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        return balance.sub(reservedAmounts[_token]);
    }

    function tokenToUsdMax(address _token, uint256 _tokenAmount)
        public
        view
        returns (uint256)
    {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getMaxPrice(_token);
        uint256 decimals = tokenDecimals[_token];
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function tokenToUsdMin(address _token, uint256 _tokenAmount)
        public
        view
        returns (uint256)
    {
        if (_tokenAmount == 0) {
            return 0;
        }
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenDecimals[_token];
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function usdToTokenMax(address _token, uint256 _usdAmount)
        public
        view
        returns (uint256)
    {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    function usdToTokenMin(address _token, uint256 _usdAmount)
        public
        view
        returns (uint256)
    {
        if (_usdAmount == 0) {
            return 0;
        }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    function usdToToken(
        address _token,
        uint256 _usdAmount,
        uint256 _price
    ) public view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }
        uint256 decimals = tokenDecimals[_token];
        return _usdAmount.mul(10**decimals).div(_price);
    }

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    )
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        )
    {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];
        uint256 realisedPnl = position.realisedPnl > 0
            ? uint256(position.realisedPnl)
            : uint256(-position.realisedPnl);
        return (
            position.size, // 0
            position.collateral, // 1
            position.averagePrice, // 2
            position.entryFundingRate, // 3
            position.reserveAmount, // 4
            realisedPnl, // 5
            position.realisedPnl >= 0, // 6
            position.lastIncreasedTime // 7
        );
    }

    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _account,
                    _collateralToken,
                    _indexToken,
                    _isLong
                )
            );
    }

    function updateCumulativeFundingRate(address _token) public {
        if (lastFundingTimes[_token] == 0) {
            lastFundingTimes[_token] = block.timestamp.div(fundingInterval).mul(
                fundingInterval
            );
            return;
        }

        if (lastFundingTimes[_token].add(fundingInterval) > block.timestamp) {
            return;
        }

        uint256 fundingRate = getNextFundingRate(_token);
        cumulativeFundingRates[_token] = cumulativeFundingRates[_token].add(
            fundingRate
        );
        lastFundingTimes[_token] = block.timestamp.div(fundingInterval).mul(
            fundingInterval
        );

        emit UpdateFundingRate(_token, cumulativeFundingRates[_token]);
    }

    function getNextFundingRate(address _token)
        public
        view
        override
        returns (uint256)
    {
        if (lastFundingTimes[_token].add(fundingInterval) > block.timestamp) {
            return 0;
        }

        uint256 intervals = block.timestamp.sub(lastFundingTimes[_token]).div(
            fundingInterval
        );
        uint256 poolAmount = poolAmounts[_token];
        if (poolAmount == 0) {
            return 0;
        }

        return
            fundingRateFactor.mul(reservedAmounts[_token]).mul(intervals).div(
                poolAmount
            );
    }

    function getUtilisation(address _token)
        public
        view
        override
        returns (uint256)
    {
        uint256 poolAmount = poolAmounts[_token];
        if (poolAmount == 0) {
            return 0;
        }

        return
            reservedAmounts[_token].mul(FUNDING_RATE_PRECISION).div(poolAmount);
    }

    function getPositionLeverage(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (uint256) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];
        require(position.collateral > 0, "Vault: invalid position");
        return position.size.mul(BASIS_POINTS_DIVISOR).div(position.collateral);
    }

    // for longs: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    // for shorts: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        uint256 _lastIncreasedTime
    ) public view returns (uint256) {
        (bool hasProfit, uint256 delta) = getDelta(
            _indexToken,
            _size,
            _averagePrice,
            _isLong,
            _lastIncreasedTime
        );
        uint256 nextSize = _size.add(_sizeDelta);
        uint256 divisor;
        if (_isLong) {
            divisor = hasProfit ? nextSize.add(delta) : nextSize.sub(delta);
        } else {
            divisor = hasProfit ? nextSize.sub(delta) : nextSize.add(delta);
        }
        return _nextPrice.mul(nextSize).div(divisor);
    }

    function getPositionDelta(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public view returns (bool, uint256) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position memory position = positions[key];
        return
            getDelta(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong,
                position.lastIncreasedTime
            );
    }

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) public view override returns (bool, uint256) {
        require(_averagePrice > 0, "Vault: invalid _averagePrice");
        uint256 price = _isLong
            ? getMinPrice(_indexToken)
            : getMaxPrice(_indexToken);
        uint256 priceDelta = _averagePrice > price
            ? _averagePrice.sub(price)
            : price.sub(_averagePrice);
        uint256 delta = _size.mul(priceDelta).div(_averagePrice);

        bool hasProfit;

        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        uint256 minBps = block.timestamp > _lastIncreasedTime.add(minProfitTime)
            ? 0
            : minProfitBasisPoints[_indexToken];
        if (hasProfit && delta.mul(BASIS_POINTS_DIVISOR) <= _size.mul(minBps)) {
            delta = 0;
        }

        return (hasProfit, delta);
    }

    function getFundingFee(
        address _token,
        uint256 _size,
        uint256 _entryFundingRate
    ) public view returns (uint256) {
        if (_size == 0) {
            return 0;
        }

        uint256 fundingRate = cumulativeFundingRates[_token].sub(
            _entryFundingRate
        );
        if (fundingRate == 0) {
            return 0;
        }

        return _size.mul(fundingRate).div(FUNDING_RATE_PRECISION);
    }

    function getPositionFee(uint256 _sizeDelta) public view returns (uint256) {
        if (_sizeDelta == 0) {
            return 0;
        }
        uint256 afterFeeUsd = _sizeDelta
            .mul(BASIS_POINTS_DIVISOR.sub(marginFeeBasisPoints))
            .div(BASIS_POINTS_DIVISOR);
        return _sizeDelta.sub(afterFeeUsd);
    }

    function getMaxNUSDAmount() public view returns (uint256) {
        uint256 supply = IERC20(nusd).totalSupply();
        uint256 bufferredSupply = supply.add(maxNUSDBuffer);
        uint256 max = bufferredSupply.div(maxNUSDBatchSize).mul(
            maxNUSDBatchSize
        );
        max = max.add(maxNUSDBatchSize);
        return max.div(whitelistedTokenCount);
    }

    function _reduceCollateral(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong
    ) private returns (uint256, uint256) {
        bytes32 key = getPositionKey(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );
        Position storage position = positions[key];

        uint256 fee = _collectMarginFees(
            _collateralToken,
            _sizeDelta,
            position.size,
            position.entryFundingRate
        );
        bool hasProfit;
        uint256 adjustedDelta;

        // scope variables to avoid stack too deep errors
        {
            (bool _hasProfit, uint256 delta) = getDelta(
                _indexToken,
                position.size,
                position.averagePrice,
                _isLong,
                position.lastIncreasedTime
            );
            hasProfit = _hasProfit;
            // get the proportional change in pnl
            adjustedDelta = _sizeDelta.mul(delta).div(position.size);
        }

        uint256 usdOut;
        // transfer profits out
        if (hasProfit && adjustedDelta > 0) {
            usdOut = adjustedDelta;
            position.realisedPnl = position.realisedPnl + int256(adjustedDelta);

            // pay out realised profits from the pool amount for short positions
            if (!_isLong) {
                uint256 tokenAmount = usdToTokenMin(
                    _collateralToken,
                    adjustedDelta
                );
                _decreasePoolAmount(_collateralToken, tokenAmount);
            }
        }

        if (!hasProfit && adjustedDelta > 0) {
            position.collateral = position.collateral.sub(adjustedDelta);

            // transfer realised losses to the pool for short positions
            // realised losses for long positions are not transferred here as
            // _increasePoolAmount was already called in increasePosition for longs
            if (!_isLong) {
                uint256 tokenAmount = usdToTokenMin(
                    _collateralToken,
                    adjustedDelta
                );
                _increasePoolAmount(_collateralToken, tokenAmount);
            }

            position.realisedPnl = position.realisedPnl - int256(adjustedDelta);
        }

        // reduce the position's collateral by _collateralDelta
        // transfer _collateralDelta out
        if (_collateralDelta > 0) {
            usdOut = usdOut.add(_collateralDelta);
            position.collateral = position.collateral.sub(_collateralDelta);
        }

        // if the position will be closed, then transfer the remaining collateral out
        if (position.size == _sizeDelta) {
            usdOut = usdOut.add(position.collateral);
            position.collateral = 0;
        }

        // if the usdOut is more than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        uint256 usdOutAfterFee = usdOut;
        if (usdOut > fee) {
            usdOutAfterFee = usdOut.sub(fee);
        } else {
            position.collateral = position.collateral.sub(fee);
            if (_isLong) {
                uint256 feeTokens = usdToTokenMin(_collateralToken, fee);
                _decreasePoolAmount(_collateralToken, feeTokens);
            }
        }

        emit UpdatePnl(key, hasProfit, adjustedDelta);

        return (usdOut, usdOutAfterFee);
    }

    function _validatePosition(uint256 _size, uint256 _collateral)
        private
        pure
    {
        if (_size == 0) {
            require(_collateral == 0, "Vault: collateral should be withdrawn");
            return;
        }
        require(
            _size >= _collateral,
            "Vault: _size must be more than _collateral"
        );
    }

    function _validateRouter(address _account) private view {
        if (msg.sender == _account) {
            return;
        }
        if (msg.sender == router) {
            return;
        }
        require(
            approvedRouters[_account][msg.sender],
            "Vault: invalid msg.sender"
        );
    }

    function _validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) private view {
        if (_isLong) {
            require(
                _collateralToken == _indexToken,
                "Vault: mismatched tokens"
            );
            require(
                whitelistedTokens[_collateralToken],
                "Vault: _collateralToken not whitelisted"
            );
            require(
                !stableTokens[_collateralToken],
                "Vault: _collateralToken must not be a stableToken"
            );
            return;
        }

        require(
            whitelistedTokens[_collateralToken],
            "Vault: _collateralToken not whitelisted"
        );
        require(
            stableTokens[_collateralToken],
            "Vault: _collateralToken must be a stableToken"
        );
        require(
            !stableTokens[_indexToken],
            "Vault: _indexToken must not be a stableToken"
        );
        require(
            shortableTokens[_indexToken],
            "Vault: _indexToken not shortable"
        );
    }

    function _collectSwapFees(
        address _token,
        uint256 _amount,
        bool _isStableSwap
    ) private returns (uint256) {
        uint256 feeBasisPoints = _isStableSwap
            ? stableSwapFeeBasisPoints
            : swapFeeBasisPoints;
        uint256 afterFeeAmount = _amount
            .mul(BASIS_POINTS_DIVISOR.sub(feeBasisPoints))
            .div(BASIS_POINTS_DIVISOR);
        uint256 feeAmount = _amount.sub(afterFeeAmount);
        feeReserves[_token] = feeReserves[_token].add(feeAmount);
        emit CollectSwapFees(
            _token,
            feeAmount,
            tokenToUsdMin(_token, feeAmount)
        );
        return afterFeeAmount;
    }

    function _collectMarginFees(
        address _token,
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryFundingRate
    ) private returns (uint256) {
        uint256 feeUsd = getPositionFee(_sizeDelta);

        uint256 fundingFee = getFundingFee(_token, _size, _entryFundingRate);
        feeUsd = feeUsd.add(fundingFee);

        uint256 feeTokens = usdToTokenMin(_token, feeUsd);
        feeReserves[_token] = feeReserves[_token].add(feeTokens);

        emit CollectMarginFees(_token, feeUsd, feeTokens);
        return feeUsd;
    }

    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;

        return nextBalance.sub(prevBalance);
    }

    function _transferOut(
        address _token,
        uint256 _amount,
        address _receiver
    ) private {
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    function _updateTokenBalance(address _token) private {
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
    }

    function _increasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] = poolAmounts[_token].add(_amount);
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(poolAmounts[_token] <= balance, "Vault: invalid increase");
        emit IncreasePoolAmount(_token, _amount);
    }

    function _decreasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] = poolAmounts[_token].sub(
            _amount,
            "Vault: poolAmount exceeded"
        );
        require(
            reservedAmounts[_token] <= poolAmounts[_token],
            "Vault: reserve exceeds pool"
        );
        emit DecreasePoolAmount(_token, _amount);
    }

    function _increaseNUSDAmount(address _token, uint256 _amount) private {
        nusdAmounts[_token] = nusdAmounts[_token].add(_amount);
        require(
            nusdAmounts[_token] <= getMaxNUSDAmount(),
            "Vault: max NUSD exceeded"
        );
        emit IncreaseNUSDAmount(_token, _amount);
    }

    function _decreaseNUSDAmount(address _token, uint256 _amount) private {
        uint256 value = nusdAmounts[_token];
        // since NUSD can be minted using multiple assets
        // it is possible for the NUSD debt for a single asset to be less than zero
        // the NUSD debt is capped to zero for this case
        if (value <= _amount) {
            nusdAmounts[_token] = 0;
            emit DecreaseNUSDAmount(_token, value);
            return;
        }
        nusdAmounts[_token] = value.sub(_amount);
        emit DecreaseNUSDAmount(_token, _amount);
    }

    function _increaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] = reservedAmounts[_token].add(_amount);
        require(
            reservedAmounts[_token] <= poolAmounts[_token],
            "Vault: reserve exceeds pool"
        );
        emit IncreaseReservedAmount(_token, _amount);
    }

    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] = reservedAmounts[_token].sub(
            _amount,
            "Vault: insufficient reserve"
        );
        emit DecreaseReservedAmount(_token, _amount);
    }

    function _increaseGuaranteedUsd(address _token, uint256 _usdAmount)
        private
    {
        guaranteedUsd[_token] = guaranteedUsd[_token].add(_usdAmount);
        emit IncreaseGuaranteedUsd(_token, _usdAmount);
    }

    function _decreaseGuaranteedUsd(address _token, uint256 _usdAmount)
        private
    {
        guaranteedUsd[_token] = guaranteedUsd[_token].sub(_usdAmount);
        emit DecreaseGuaranteedUsd(_token, _usdAmount);
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    function _onlyGov() private view {
        require(msg.sender == gov, "Vault: forbidden");
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

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
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
        return a + b;
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
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface INUSD {
    function mint(address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IRewardToken {
    function addAdmin(address _account) external;

    function setVault(address _vault) external;

    function circulatingSupply() external view returns (uint256);

    function setDeltaYieldTracker(address _deltaYieldTracker) external;

    function setDistributor(address _Distributor) external;

    function removeAdmin(address _account) external;

    function increaseCirculatingSupply(uint256 _amount) external;

    function getRedemptionPrice() external view returns (uint256);

    function burn(address _account, uint256 _amount) external returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IDistributor {
    function getCollaterals() external view returns (address[] memory);

    function receiver() external view returns (address);

    function getRewardToken() external view returns (address);

    function setRebalancer(address _rebalancer) external;

    function distribute(address _collateralToken) external returns (uint256);

    function getDistributionAmount(address _collateralToken)
        external
        view
        returns (uint256);

    function getTokensPerIntervalPerCollateral(address _collateralToken)
        external
        view
        returns (uint256);

    function setTokensPerIntervalPerCollateral(
        address _collateralToken,
        uint256 _amount
    ) external;

    function setDistribution(
        address[] calldata _collaterals,
        uint256[] calldata _amountPerCollateral
    ) external;

    function getLastDistributionTime() external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IVault {
    function getRedemptionCollateralUsd(address _token)
        external
        view
        returns (uint256);

    function setIsMintingEnabled(bool _isMintingEnabled) external;

    function setIsSwapEnabled(bool _isSwapEnabled) external;

    function setFees(
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd
    ) external;

    function setPriceFeed(address _priceFeed) external;

    function setRewardRedemptionBasisPoints(
        uint256 _rewardRedemptionBasisPoints
    ) external;

    function setMaxNUSD(uint256 _maxNUSDBatchSize, uint256 _maxNUSDBuffer)
        external;

    function directPoolDeposit(address _token) external;

    function redeemReward(uint256 _amount, address _receiver)
        external
        returns (uint256[] memory);

    function buyNUSD(address _token, address _receiver)
        external
        returns (uint256);

    function sellNUSD(address _token, address _receiver)
        external
        returns (uint256);

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    ) external returns (uint256);

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external;

    function decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external returns (uint256);

    function priceFeed() external view returns (address);

    function fundingRateFactor() external view returns (uint256);

    function cumulativeFundingRates(address _token)
        external
        view
        returns (uint256);

    function getNextFundingRate(address _token) external view returns (uint256);

    function BASIS_POINTS_DIVISOR() external view returns (uint256);

    function rewardRedemptionBasisPoints() external view returns (uint256);

    function rewardDistributor() external view returns (address);

    function swapFeeBasisPoints() external view returns (uint256);

    function stableSwapFeeBasisPoints() external view returns (uint256);

    function stableTokens(address _token) external view returns (bool);

    function feeReserves(address _token) external view returns (uint256);

    function tokenDecimals(address _token) external view returns (uint256);

    function guaranteedUsd(address _token) external view returns (uint256);

    function poolAmounts(address _token) external view returns (uint256);

    function reservedAmounts(address _token) external view returns (uint256);

    function nusdAmounts(address _token) external view returns (uint256);

    function getRedemptionAmount(address _token, uint256 _nusdAmount)
        external
        view
        returns (uint256);

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function getUtilisation(address _token) external view returns (uint256);

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) external view returns (bool, uint256);

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            uint256
        );

    function adjustForDecimals(
        uint256 _amount,
        address _tokenDiv,
        address _tokenMul
    ) external view returns (uint256);

    function withdrawFees(address _token, address _receiver)
        external
        returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IVaultPriceFeed {
    function setIsAmmEnabled(bool _isEnabled) external;

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external;

    function setIsSecondaryPriceEnabled(bool _isEnabled) external;

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints)
        external;

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints)
        external;

    function setPriceSampleSpace(uint256 _priceSampleSpace) external;

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation)
        external;

    function getPrice(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) external view returns (uint256);

    function getAmmPrice(address _token) external view returns (uint256);
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

