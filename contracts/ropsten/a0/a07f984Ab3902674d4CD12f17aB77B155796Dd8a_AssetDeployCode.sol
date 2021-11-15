// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./pancake-swap/interfaces/IPancakeRouter02.sol";
import "./pancake-swap/interfaces/IWETH.sol";

import "./interfaces/IAsset.sol";
import "./interfaces/IStaking.sol";

import "./InitialAsset.sol";
import "./lib/AssetLib.sol";
import "./lib/AssetLib2.sol";

contract Asset is InitialAsset, IAsset {
    /* STATE VARIABLES */

    // public data
    address public dexRouter;
    address public zVault;

    address[] public tokensInAsset;
    mapping(address => uint256) public tokensDistribution;
    mapping(address => uint256) public xVaultAmount;
    mapping(address => uint256) public yVaultAmount;
    mapping(address => uint256) public yVaultAmountInStaking;
    mapping(address => uint256) public totalTokenAmount;

    bool public isAllowedAutoXYRebalace = true;

    uint256 public feeLimitForAuto = 10 ether;
    uint256 public feeLimitForAutoInAssetToken = 10 ether;
    uint256 public feeAmountToZ;
    uint256 public feeAmountInAssetToken;

    // private data
    uint256 private constant INITIAL_ASSET_AMOUNT = 1e6 * 1e18;
    mapping(address => uint256) private _allowanceToDexInfo;
    bool private isRedeemingFee;

    /* MODIFIERS */

    modifier onlyAfterIme {
        require(isImeHelded == true, "Ime is not ended");
        _;
    }

    /* EVENTS */
    /* FUNCTIONS */

    constructor() {}

    receive() external payable {
        require(_msgSender() == _weth, "Now allowed");
    }

    /* EXTERNAL FUNCTIONS */

    function __Asset_init(
        string memory name,
        string memory symbol,
        address[3] memory oracleDexRouterAndZVault,
        uint256[2] memory imeTimeInfo,
        address[] calldata _tokenWhitelist,
        address[] calldata _tokensInAsset,
        uint256[] calldata _tokensDistribution
    ) external override initializer {
        address weth_ = IPancakeRouter02(oracleDexRouterAndZVault[1]).WETH();
        InitialAsset.__InitialAsset_init(
            name,
            symbol,
            oracleDexRouterAndZVault[0],
            imeTimeInfo[0],
            imeTimeInfo[1],
            _tokenWhitelist,
            weth_
        );

        dexRouter = oracleDexRouterAndZVault[1];
        zVault = oracleDexRouterAndZVault[2];

        tokensInAsset = _tokensInAsset;

        AssetLib.checkAndWriteDistribution(
            _tokensInAsset,
            _tokensDistribution,
            _tokensInAsset,
            tokensDistribution
        );
    }

    function mint(address tokenToPay, uint256 amount) external payable override onlyAfterIme {
        address sender = _msgSender();
        // recieve senders funds
        uint256 totalWeth;
        address weth_ = _weth;
        address _dexRouter = dexRouter;
        (tokenToPay, totalWeth) = AssetLib.transferTokenAndSwapToWeth(
            tokenToPay,
            amount,
            sender,
            weth_,
            _dexRouter,
            _allowanceToDexInfo
        );
        require(isTokenWhitelisted[tokenToPay] == true, "Not allowed token to pay");

        {
            // 0.5%
            uint256 feeAmount = (totalWeth * 50) / 1e4;
            feeAmountToZ += feeAmount;
            totalWeth -= feeAmount;
        }

        // buy tokens in asset
        address[] memory _tokensInAsset = tokensInAsset;
        (uint256[] memory buyAmounts, uint256[] memory oldDistribution) =
            AssetLib.buyTokensMint(
                totalWeth,
                _tokensInAsset,
                [weth_, _dexRouter],
                tokensDistribution,
                totalTokenAmount,
                _allowanceToDexInfo
            );

        AssetLib2.xyDistributionAfterMint(
            _tokensInAsset,
            buyAmounts,
            oldDistribution,
            xVaultAmount,
            yVaultAmount
        );

        // get mint amount
        uint256 mintAmount =
            AssetLib.getMintAmount(
                _tokensInAsset,
                buyAmounts,
                oldDistribution,
                totalSupply(),
                decimals(),
                oracle
            );
        _mint(sender, mintAmount);

        _autoTransferFee(false);
    }

    function redeem(uint256 amount, address currencyToPay) public override returns (uint256) {
        bool _isRedeemingFee = isRedeemingFee;
        address sender;
        if (_isRedeemingFee == true) {
            sender = address(this);
        } else {
            sender = _msgSender();
        }
        address weth_ = _weth;
        {
            address currencyToCheck;
            if (currencyToPay == address(0)) {
                currencyToCheck = weth_;
            } else {
                currencyToCheck = currencyToPay;
            }
            require(isTokenWhitelisted[currencyToCheck], "Not allowed currency");
        }

        uint256 _totalSupply = totalSupply();
        _burn(sender, amount);

        address[] memory _tokensInAsset = tokensInAsset;
        uint256[] memory feePercentages;
        if (_isRedeemingFee == true) {
            feePercentages = new uint256[](_tokensInAsset.length);
        } else {
            feePercentages = AssetLib.getFeePercentagesRedeem(
                _tokensInAsset,
                totalTokenAmount,
                xVaultAmount
            );
        }

        (uint256 feeTotal, uint256[] memory inputAmounts, uint256 outputAmountTotal) =
            AssetLib.redeemAndTransfer(
                [amount, _totalSupply],
                [sender, currencyToPay, weth_, dexRouter],
                totalTokenAmount,
                _allowanceToDexInfo,
                _tokensInAsset,
                feePercentages
            );

        if (feeTotal > 0 && currencyToPay != address(0) && currencyToPay != weth_) {
            feeAmountToZ += AssetLib.safeSwap(
                [currencyToPay, weth_],
                feeTotal,
                dexRouter,
                _allowanceToDexInfo
            );
        } else if (feeTotal > 0) {
            feeAmountToZ += feeTotal;
        }

        AssetLib2.xyDistributionAfterRedeem(
            totalTokenAmount,
            isAllowedAutoXYRebalace,
            xVaultAmount,
            yVaultAmount,
            _tokensInAsset,
            inputAmounts
        );

        if (_isRedeemingFee == false) {
            _autoTransferFee(false);
        }

        return outputAmountTotal;
    }

    function makeIme() external nonReentrant onlyManagerOrAdmin {
        _proceedIme(INITIAL_ASSET_AMOUNT);

        {
            uint256 totalWeightIme_ = _totalWeightIme;
            if (totalWeightIme_ == 0) {
                return;
            }

            address[] memory _tokenWhitelist = tokenWhitelist;
            uint256[][3] memory tokensIncomeAmounts =
                AssetLib.initTokenInfoFromWhitelist(_tokenWhitelist, tokenEntersIme);

            _rebase(_tokenWhitelist, tokensIncomeAmounts, totalWeightIme_, tokensInAsset, true);
        }

        AssetLib.calculateXYAfterIme(tokensInAsset, totalTokenAmount, xVaultAmount, yVaultAmount);
    }

    function rebase(address[] calldata newTokensInAsset, uint256[] calldata distribution)
        external
        onlyManagerOrAdmin
        onlyAfterIme
        nonReentrant
    {
        require(newTokensInAsset.length == distribution.length, "Input error");

        address[] memory _tokensOld = tokensInAsset;
        // fill information about tokens that already in asset and calculate weight of tokens in asset now
        (uint256[][3] memory _tokensOldInfo, uint256 oldWeight) =
            AssetLib.initTokenToSellInfo(_tokensOld, oracle, totalTokenAmount);

        // check new distribution
        AssetLib.checkAndWriteDistribution(
            newTokensInAsset,
            distribution,
            _tokensOld,
            tokensDistribution
        );

        tokensInAsset = newTokensInAsset;

        _rebase(_tokensOld, _tokensOldInfo, oldWeight, newTokensInAsset, false);
    }

    function withdrawTokensForStaking(uint256[] memory tokenAmounts)
        external
        nonReentrant
        onlyManagerOrAdmin
    {
        AssetLib.withdrawFromYForOwner(
            tokensInAsset,
            tokenAmounts,
            _msgSender(),
            yVaultAmount,
            yVaultAmountInStaking
        );
    }

    function xyRebalance(uint256 xPercentage) external nonReentrant onlyManagerOrAdmin {
        require(xPercentage <= 2000, "Wrong X percentage");

        AssetLib2.xyRebalance(
            xPercentage,
            tokensInAsset,
            xVaultAmount,
            yVaultAmount,
            totalTokenAmount
        );
    }

    function depositToIndex(
        uint256[] memory tokenAmountsOfY,
        address[] memory tokensOfDividends,
        uint256[] memory amountOfDividends
    ) external payable nonReentrant onlyManagerOrAdmin {
        address weth_ = _weth;
        feeAmountToZ += AssetLib.depositToY(
            tokensInAsset,
            tokenAmountsOfY,
            tokensOfDividends,
            amountOfDividends,
            _msgSender(),
            dexRouter,
            weth_,
            _allowanceToDexInfo,
            yVaultAmountInStaking,
            yVaultAmount
        );

        if (msg.value > 0) {
            IWETH(weth_).deposit{ value: msg.value }();
            feeAmountToZ += msg.value;
        }

        _autoTransferFee(false);
    }

    function forceFeesAutosend() external nonReentrant onlyManagerOrAdmin {
        _autoTransferFee(true);
    }

    function setIsAllowedAutoXYRebalace(bool value) external onlyManagerOrAdmin {
        isAllowedAutoXYRebalace = value;
    }

    function setFeeLimits(uint256 _feeLimitForAuto, uint256 _feeLimitForAutoInAssetToken)
        external
        onlyManagerOrAdmin
    {
        feeLimitForAuto = _feeLimitForAuto;
        feeLimitForAutoInAssetToken = _feeLimitForAutoInAssetToken;
    }

    function getBuyAmountOut(address currencyIn, uint256 amountIn) external view returns (uint256) {
        return
            AssetLib2.calculateBuyAmountOut(
                amountIn,
                currencyIn,
                tokensInAsset,
                [_weth, dexRouter, address(oracle)],
                totalSupply(),
                decimals(),
                tokensDistribution,
                totalTokenAmount
            );
    }

    function getSellAmountOut(address currencyOut, uint256 amountIn)
        external
        view
        returns (uint256)
    {
        return
            AssetLib2.calculateSellAmountOut(
                [amountIn, totalSupply()],
                currencyOut,
                tokensInAsset,
                [_weth, dexRouter],
                totalTokenAmount,
                xVaultAmount
            );
    }

    function tokensInAssetLen() external view returns (uint256) {
        return tokensInAsset.length;
    }

    /* PUBLIC FUNCTIONS */
    /* INTERNAL FUNCTIONS */

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        address _zVault = zVault;
        if (sender != _zVault && recipient != _zVault) {
            uint256 feeAmount = (amount * 25) / 1e4;
            feeAmountInAssetToken += feeAmount;
            super._transfer(sender, address(this), feeAmount);
            super._transfer(sender, recipient, amount - feeAmount);
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    /* PRIVATE FUNCTIONS */

    function _autoTransferFee(bool isForce) private {
        uint256 _feeLimitForAuto = feeLimitForAuto;
        uint256 _feeLimitForAutoInAssetToken = feeLimitForAutoInAssetToken;
        uint256 _feeAmountToZ = feeAmountToZ;
        uint256 _feeAmountInAssetToken = feeAmountInAssetToken;

        uint256 totalAmountFee;
        if (_feeAmountToZ > 0 && (isForce || _feeAmountToZ >= _feeLimitForAuto)) {
            IWETH(_weth).withdraw(_feeAmountToZ);
            totalAmountFee += _feeAmountToZ;
            feeAmountToZ = 0;
        }

        if (
            _feeAmountInAssetToken > 0 &&
            (isForce || _feeAmountInAssetToken >= _feeLimitForAutoInAssetToken)
        ) {
            isRedeemingFee = true;
            //require(balanceOf(address(this)) >= _feeAmountInAssetToken,  "Internal error 11");
            totalAmountFee += redeem(_feeAmountInAssetToken, address(0));
            isRedeemingFee = false;
            feeAmountInAssetToken = 0;
        }

        if (totalAmountFee > 0) {
            IStaking(zVault).inputBnb{value: totalAmountFee}();
        }
    }

    /*
    tokensInAssetNowInfo
    0 - tokens in assets amounts
    1 - with zero values (in function used for number to sell)
    2 - tokens decimals
    */
    function _rebase(
        address[] memory tokensInAssetNow,
        uint256[][3] memory tokensInAssetNowInfo,
        uint256 totalWeightNow,
        address[] memory tokensToBuy,
        bool isIme
    ) private {
        //address[] memory tokensToBuy = tokensInAsset;
        /*
        tokenToBuyInfo
        0 - tokens to buy amounts
        1 - actual number to buy (tokens to buy amounts - tokensInAssetNow)
        2 - actual weight to buy
        3 - tokens decimals
        4 - is in asset already
         */
        (uint256[][5] memory tokenToBuyInfo, uint256[] memory tokensPrices) =
            AssetLib.initTokenToBuyInfo(tokensToBuy, totalWeightNow, tokensDistribution, oracle);

        // we can assume that here we don't need to check isValidValue array

        // here we calculate actual number of assets to buy
        // considering that some tokens may be in asset already
        // and also calculate how many tokens we need to sell that are in asset already
        // after that we calculate weight (to buy) of tokens that are not in asset yet

        // tokenToBuyInfoGlobals info
        // 0 - total weight to buy
        // 1 - number of true tokens to buy
        uint256[2] memory tokenToBuyInfoGlobals;
        (tokensInAssetNowInfo, tokenToBuyInfo, tokenToBuyInfoGlobals) = AssetLib
            .fillInformationInSellAndBuyTokens(
            tokensInAssetNow,
            tokensInAssetNowInfo,
            tokensToBuy,
            tokenToBuyInfo,
            tokensPrices
        );

        // here we sell tokens that are needed to be sold
        address weth_ = _weth;
        address _dexRouter = dexRouter;
        uint256 availableWeth =
            AssetLib.sellTokensInAssetNow(
                tokensInAssetNow,
                tokensInAssetNowInfo,
                weth_,
                _dexRouter,
                totalTokenAmount,
                _allowanceToDexInfo
            );

        // here we buy tokens that are needed to be bought
        uint256[] memory outputAmounts =
            AssetLib.buyTokensInAssetRebase(
                tokensToBuy,
                tokenToBuyInfo,
                tokenToBuyInfoGlobals,
                weth_,
                _dexRouter,
                availableWeth,
                totalTokenAmount,
                _allowanceToDexInfo
            );

        if (isIme == false) {
            AssetLib2.xyDistributionAfterRebase(
                tokensInAssetNow,
                tokensInAssetNowInfo[1],
                tokensToBuy,
                outputAmounts,
                xVaultAmount,
                yVaultAmount,
                totalTokenAmount
            );
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IAssetDeployCode.sol";

import "./Asset.sol";

contract AssetDeployCode is IAssetDeployCode {
    function newAsset(bytes32 salt) external override returns (address) {
        return address(new Asset{ salt: salt }());
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IOracle.sol";
import "./pancake-swap/interfaces/IWETH.sol";

import "./lib/AssetLib.sol";

contract InitialAsset is ERC20Upgradeable, ReentrancyGuard {
    // whitelist info
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => bool) public isTokenWhitelisted;
    address[] public tokenWhitelist;

    // users info
    mapping(address => bool) public isUserEnteredIme;
    mapping(address => mapping(address => uint256)) public userEnters;
    mapping(address => uint256) public tokenEntersIme;

    // ime constants
    uint256 public imeStartTimestamp;
    uint256 public imeEndTimestamp;
    bool public isImeHelded;

    // external contracts
    IOracle public oracle;
    address public factory;

    // internal data
    uint256 internal _totalWeightIme;
    address internal _weth;

    // private data
    address[] private _tokensInIme;
    uint256[] private _tokenPricesInIme;
    uint256 private _totalAssetMintFromIme;
    uint256 private _alreadyMintedAssetsFromIme;
    mapping(address => uint256) private _whitelistIndexes;

    event UserClaimedIme(address user, uint256 userWeight, uint256 tokenAmount);
    event ImeProceeded(uint256 totalWeight, uint256 totalAssetMintFromIme);

    modifier onlyManagerOrAdmin virtual {
        address sender = _msgSender();
        require(
            AccessControl(factory).hasRole(MANAGER_ROLE, sender) ||
                AccessControl(factory).hasRole(0x00, sender),
            "Access error"
        );
        _;
    }

    constructor() {
        factory = _msgSender();
    }

    // solhint-disable-next-line func-name-mixedcase
    function __InitialAsset_init(
        string memory name,
        string memory symbol,
        address _oracle,
        uint256 _imeStartTimestamp,
        uint256 _imeEndTimestamp,
        address[] calldata _tokenWhitelist,
        address weth_
    ) internal initializer {
        __ERC20_init(name, symbol);

        oracle = IOracle(_oracle);

        _weth = weth_;

        imeStartTimestamp = _imeStartTimestamp;
        imeEndTimestamp = _imeEndTimestamp;

        AssetLib.checkAndWriteWhitelist(_tokenWhitelist, _whitelistIndexes, isTokenWhitelisted);
        tokenWhitelist = _tokenWhitelist;
    }

    function enterImeNative() external payable nonReentrant {
        _enterIme(_msgSender(), address(0), msg.value);
    }

    function enterImeToken(address token, uint256 amount) external nonReentrant {
        _enterIme(_msgSender(), token, amount);
    }

    function changeOracle(address newOracle) external onlyManagerOrAdmin nonReentrant {
        oracle = IOracle(newOracle);
    }

    function changeIsTokenWhitelisted(address token, bool value)
        external
        onlyManagerOrAdmin
        nonReentrant
    {
        require(
            // solhint-disable-next-line not-rely-on-time
            block.timestamp < imeStartTimestamp || isImeHelded == true,
            "Time error"
        );

        AssetLib.changeWhitelist(
            token,
            value,
            tokenWhitelist,
            isTokenWhitelisted,
            _whitelistIndexes
        );
    }

    function tokenWhitelistLen() external view returns (uint256) {
        return tokenWhitelist.length;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 initialBalance = ERC20Upgradeable.balanceOf(account);

        uint256 userWeight = _calculateUserWeight(account);
        uint256 additionalBalance = _calculateBalanceFromIme(userWeight);

        return initialBalance + additionalBalance;
    }

    function totalSupply() public view override returns (uint256) {
        uint256 initialTotalSupply = ERC20Upgradeable.totalSupply();
        uint256 additionalTotalSupply = _totalAssetMintFromIme - _alreadyMintedAssetsFromIme;

        return initialTotalSupply + additionalTotalSupply;
    }

    /* INTERNAL FUNCTIONS */

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (isImeHelded == true && isUserEnteredIme[from] == true) {
            uint256 userWeight = _calculateUserWeight(from);
            uint256 amountToMint = _calculateBalanceFromIme(userWeight);
            _mint(from, amountToMint);
            _alreadyMintedAssetsFromIme += amountToMint;

            delete isUserEnteredIme[from];

            emit UserClaimedIme(from, userWeight, amountToMint);
        }
    }

    function _proceedIme(uint256 assetMintFromIme_) internal {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp >= imeEndTimestamp, "Time error");
        require(isImeHelded == false, "Ime has already helded");

        address[] memory _tokens = tokenWhitelist;

        (uint256 totalWeight_, uint256[] memory tokensPrices) =
            AssetLib.proceedIme(_tokens, oracle, tokenEntersIme);
        _totalWeightIme = totalWeight_;
        if (totalWeight_ != 0) {
            _tokenPricesInIme = tokensPrices;
            _tokensInIme = _tokens;
            _totalAssetMintFromIme = assetMintFromIme_;
        } else {
            _totalAssetMintFromIme = 0;
        }

        isImeHelded = true;

        emit ImeProceeded(totalWeight_, assetMintFromIme_);
    }

    /* PRIVATE FUNCTIONS */

    function _enterIme(
        address user,
        address token,
        uint256 amount
    ) private {
        require(_isImeOpened() == true, "Ime is not opened");
        require(amount != 0, "Wrong value");

        token = AssetLib.transferFromToGoodToken(token, user, amount, _weth);
        require(isTokenWhitelisted[token] == true, "This currency is not allowed");

        isUserEnteredIme[user] = true;
        userEnters[user][token] += amount;
        tokenEntersIme[token] += amount;
    }

    function _calculateUserWeight(address user) private view returns (uint256) {
        if (isImeHelded == false || isUserEnteredIme[user] == false) {
            return 0;
        }

        address[] memory _tokens = _tokensInIme;
        uint256 len = _tokens.length;

        uint256 totalUserWeight;
        for (uint256 i = 0; i < len; ++i) {
            uint256 decimals_;
            if (_tokens[i] == address(0)) {
                decimals_ = 18;
            } else {
                decimals_ = IERC20Metadata(_tokens[i]).decimals();
            }
            totalUserWeight +=
                (userEnters[user][_tokens[i]] * _tokenPricesInIme[i]) /
                (10**decimals_);
        }

        return totalUserWeight;
    }

    function _calculateBalanceFromIme(uint256 weight) private view returns (uint256) {
        uint256 totalWeight_ = _totalWeightIme;
        if (isImeHelded == false || totalWeight_ == 0) {
            return 0;
        } else {
            return (weight * _totalAssetMintFromIme) / totalWeight_;
        }
    }

    function _isImeOpened() private view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp >= imeStartTimestamp && block.timestamp < imeEndTimestamp;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAsset {
    function __Asset_init(
        string memory name,
        string memory symbol,
        address[3] memory oracleDexRouterAndZVault,
        uint256[2] memory imeTimeInfo,
        address[] calldata _tokenWhitelist,
        address[] calldata _tokensInAsset,
        uint256[] calldata _tokensDistribution
    ) external;

    function mint(address tokenToPay, uint256 amount) external payable;

    function redeem(uint256 amount, address currencyToPay) external returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAssetDeployCode {
    function newAsset(bytes32 salt) external returns (address);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOracle {
    function getData(address[] calldata tokens)
        external
        view
        returns (bool[] memory isValidValue, uint256[] memory tokensPrices);

    function uploadData(address[] calldata tokens, uint256[] calldata values) external;

    function getTimestampsOfLastUploads(address[] calldata tokens)
        external
        view
        returns (uint256[] memory timestamps);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStaking {
    function stakeStart(
        address token,
        uint256 amount,
        uint8 timeIntervalIndex
    ) external;

    function stakeEnd(uint256 stakeIndex) external;

    function claimDividends(uint256 stakeIndex, uint256 maxDepth) external;

    function createPool(address token) external;

    function inputBnb() external payable;

    function treasuryWithdraw() external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../pancake-swap/interfaces/IPancakeRouter02.sol";
import "../pancake-swap/interfaces/IWETH.sol";

import "../interfaces/IOracle.sol";

library AssetLib {
    function initTokenToBuyInfo(
        address[] memory tokensToBuy,
        uint256 totalWeight,
        mapping(address => uint256) storage tokensDistribution,
        IOracle oracle
    ) external view returns (uint256[][5] memory, uint256[] memory) {
        /*
        tokenToBuyInfo
        0 - tokens to buy amounts
        1 - actual number to buy (tokens to buy amounts - tokensInAssetNow)
        2 - actual weight to buy
        3 - tokens decimals
        4 - is in asset already
         */
        uint256[][5] memory tokenToBuyInfo;
        for (uint256 i = 0; i < tokenToBuyInfo.length; ++i) {
            tokenToBuyInfo[i] = new uint256[](tokensToBuy.length);
        }

        (bool[] memory isValidValue, uint256[] memory tokensPrices) = oracle.getData(tokensToBuy);
        for (uint256 i = 0; i < tokensToBuy.length; ++i) {
            require(isValidValue[i] == true, "Oracle price error");

            tokenToBuyInfo[3][i] = IERC20Metadata(tokensToBuy[i]).decimals();

            uint256 tokenWeight = (tokensDistribution[tokensToBuy[i]] * totalWeight) / 1e4;
            tokenToBuyInfo[0][i] = (tokenWeight * (10**tokenToBuyInfo[3][i])) / tokensPrices[i];
        }

        return (tokenToBuyInfo, tokensPrices);
    }

    function initTokenToSellInfo(
        address[] memory tokensOld,
        IOracle oracle,
        mapping(address => uint256) storage totalTokenAmount
    ) external view returns (uint256[][3] memory, uint256) {
        uint256[][3] memory tokensOldInfo;
        for (uint256 i = 0; i < tokensOldInfo.length; ++i) {
            tokensOldInfo[i] = new uint256[](tokensOld.length);
        }

        (bool[] memory isValidValue, uint256[] memory tokensPrices) = oracle.getData(tokensOld);
        uint256 oldWeight;
        for (uint256 i = 0; i < tokensOld.length; ++i) {
            tokensOldInfo[0][i] = totalTokenAmount[tokensOld[i]];
            tokensOldInfo[2][i] = IERC20Metadata(tokensOld[i]).decimals();
            require(isValidValue[i] == true, "Oracle error");
            oldWeight += (tokensOldInfo[0][i] * tokensPrices[i]) / (10**tokensOldInfo[2][i]);
        }
        require(oldWeight != 0, "No value in asset");

        return (tokensOldInfo, oldWeight);
    }

    function checkAndWriteDistribution(
        address[] memory newTokensInAsset,
        uint256[] memory distribution,
        address[] memory oldTokens,
        mapping(address => uint256) storage tokensDistribution
    ) external {
        uint256 totalPerc;
        for (uint256 i = 0; i < newTokensInAsset.length; ++i) {
            require(newTokensInAsset[i] != address(0), "Wrong token");
            require(distribution[i] > 0, "Zero distribution");
            for (uint256 j = i + 1; j < newTokensInAsset.length; ++j) {
                require(newTokensInAsset[i] != newTokensInAsset[j], "Input error");
            }
            tokensDistribution[newTokensInAsset[i]] = distribution[i];
            totalPerc += distribution[i];
        }
        require(totalPerc == 1e4, "Perc error");

        for (uint256 i = 0; i < oldTokens.length; ++i) {
            bool isFound = false;
            for (uint256 j = 0; j < newTokensInAsset.length && isFound == false; ++j) {
                if (newTokensInAsset[j] == oldTokens[i]) {
                    isFound = true;
                }
            }

            if (isFound == false) {
                tokensDistribution[oldTokens[i]] = 0;
            }
        }
    }

    function withdrawFromYForOwner(
        address[] memory tokensInAsset,
        uint256[] memory tokenAmounts,
        address sender,
        mapping(address => uint256) storage yVaultAmount,
        mapping(address => uint256) storage yVaultAmountInStaking
    ) external {
        require(tokenAmounts.length == tokensInAsset.length, "Invalid input");
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 yAmount = yVaultAmount[tokensInAsset[i]];
            require(yAmount >= tokenAmounts[i], "Not enough y balance");
            yAmount -= tokenAmounts[i];
            yVaultAmount[tokensInAsset[i]] = yAmount;
            yVaultAmountInStaking[tokensInAsset[i]] += tokenAmounts[i];

            safeTransfer(tokensInAsset[i], sender, tokenAmounts[i]);
        }
    }

    function checkAndWriteWhitelist(
        address[] memory tokenWhitelist,
        mapping(address => uint256) storage _whitelistIndexes,
        mapping(address => bool) storage isTokenWhitelisted
    ) external {
        for (uint256 i = 0; i < tokenWhitelist.length; ++i) {
            require(tokenWhitelist[i] != address(0), "No zero address");
            for (uint256 j = 0; j < i; ++j) {
                require(tokenWhitelist[i] != tokenWhitelist[j], "Whitelist error");
            }
            _whitelistIndexes[tokenWhitelist[i]] = i;
            isTokenWhitelisted[tokenWhitelist[i]] = true;
        }
    }

    function changeWhitelist(
        address token,
        bool value,
        address[] storage tokenWhitelist,
        mapping(address => bool) storage isTokenWhitelisted,
        mapping(address => uint256) storage whitelistIndexes
    ) external {
        require(token != address(0), "Token error");

        bool oldValue = isTokenWhitelisted[token];
        if (value == false && oldValue == true) {
            uint256 index = whitelistIndexes[token];
            uint256 len = tokenWhitelist.length;
            if (index < len - 1) {
                address newToken = tokenWhitelist[len - 1];
                tokenWhitelist[index] = newToken;
                whitelistIndexes[newToken] = index;
            }
            tokenWhitelist.pop();
        } else if (value == true && oldValue == false) {
            whitelistIndexes[token] = tokenWhitelist.length;
            tokenWhitelist.push(token);
        } else {
            revert("Wrong value");
        }

        isTokenWhitelisted[token] = value;
    }

    function fillInformationInSellAndBuyTokens(
        address[] memory tokensInAssetNow,
        uint256[][3] memory tokensInAssetNowInfo,
        address[] memory tokensToBuy,
        uint256[][5] memory tokenToBuyInfo,
        uint256[] memory tokensPrices
    )
        external
        pure
        returns (
            uint256[][3] memory,
            uint256[][5] memory,
            uint256[2] memory
        )
    {
        for (uint256 i = 0; i < tokensInAssetNow.length; ++i) {
            bool isFound = false;
            for (uint256 j = 0; j < tokensToBuy.length && isFound == false; ++j) {
                if (tokensInAssetNow[i] == tokensToBuy[j]) {
                    isFound = true;
                    // mark that we found that token in asset already
                    tokenToBuyInfo[4][j] = 1;

                    if (tokenToBuyInfo[0][j] >= tokensInAssetNowInfo[0][i]) {
                        // if need to buy more than asset already have

                        // amount to sell = 0 (already 0)
                        //tokensInAssetNowInfo[1][i] = 0;

                        // actual amount to buy = (total amount to buy) - (amount in asset already)
                        tokenToBuyInfo[1][j] = tokenToBuyInfo[0][j] - tokensInAssetNowInfo[0][i];
                    } else {
                        // if need to buy less than asset already have

                        // amount to sell = (amount in asset already) - (total amount to buy)
                        tokensInAssetNowInfo[1][i] =
                            tokensInAssetNowInfo[0][i] -
                            tokenToBuyInfo[0][j];

                        // actual amount to buy = 0 (already 0)
                        //tokenToBuyInfo[1][j] = 0;
                    }
                }
            }

            // if we don't find token in _tokensToBuy than we need to sell it all
            if (isFound == false) {
                tokensInAssetNowInfo[1][i] = tokensInAssetNowInfo[0][i];
            }
        }

        // tokenToBuyInfoGlobals info
        // 0 - total weight to buy
        // 1 - number of true tokens to buy
        uint256[2] memory tokenToBuyInfoGlobals;
        for (uint256 i = 0; i < tokensToBuy.length; ++i) {
            if (tokenToBuyInfo[4][i] == 0) {
                // if no found in asset yet

                // actual weight to buy = (amount to buy) * (token price) / decimals
                tokenToBuyInfo[2][i] =
                    (tokenToBuyInfo[0][i] * tokensPrices[i]) /
                    (10**tokenToBuyInfo[3][i]);
            } else if (tokenToBuyInfo[1][i] != 0) {
                // if found in asset and amount to buy != 0

                // actual weight to buy = (actual amount to buy) * (token price) / decimals
                tokenToBuyInfo[2][i] =
                    (tokenToBuyInfo[1][i] * tokensPrices[i]) /
                    (10**tokenToBuyInfo[3][i]);
            } else {
                // if found in asset and amount to buy = 0
                continue;
            }
            // increase total weight
            tokenToBuyInfoGlobals[0] += tokenToBuyInfo[2][i];
            // increase number of true tokens to buy
            ++tokenToBuyInfoGlobals[1];
        }

        return (tokensInAssetNowInfo, tokenToBuyInfo, tokenToBuyInfoGlobals);
    }

    function sellTokensInAssetNow(
        address[] memory tokensInAssetNow,
        uint256[][3] memory tokensInAssetNowInfo,
        address weth,
        address dexRouter,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage allowanceToDexInfo
    ) external returns (uint256 availableWeth) {
        for (uint256 i = 0; i < tokensInAssetNow.length; ++i) {
            {
                address temp = tokensInAssetNow[i];
                if (totalTokenAmount[temp] == 0) {
                    totalTokenAmount[temp] = tokensInAssetNowInfo[0][i];
                }
            }

            if (tokensInAssetNowInfo[1][i] == 0) continue;

            if (tokensInAssetNow[i] == address(0)) {
                IWETH(weth).deposit{value: tokensInAssetNowInfo[1][i]}();
                availableWeth += tokensInAssetNowInfo[1][i];
            } else if (tokensInAssetNow[i] == address(weth)) {
                availableWeth += tokensInAssetNowInfo[1][i];
            } else if (tokensInAssetNow[i] != address(weth)) {
                availableWeth += safeSwap(
                    [tokensInAssetNow[i], weth],
                    tokensInAssetNowInfo[1][i],
                    dexRouter,
                    allowanceToDexInfo
                );
            }
            {
                address temp = tokensInAssetNow[i];
                totalTokenAmount[temp] -= tokensInAssetNowInfo[1][i];
            }
        }
    }

    function buyTokensInAssetRebase(
        address[] memory tokensToBuy,
        uint256[][5] memory tokenToBuyInfo,
        uint256[2] memory tokenToBuyInfoGlobals,
        address weth,
        address dexRouter,
        uint256 availableWeth,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage allowanceToDexInfo
    ) external returns (uint256[] memory outputAmounts) {
        outputAmounts = new uint256[](tokensToBuy.length);
        if (tokenToBuyInfoGlobals[0] == 0 || availableWeth == 0) {
            return outputAmounts;
        }
        uint256 restWeth = availableWeth;
        for (uint256 i = 0; i < tokensToBuy.length && tokenToBuyInfoGlobals[1] > 0; ++i) {
            uint256 wethToSpend;
            // if actual weight to buy = 0
            if (tokenToBuyInfo[2][i] == 0) {
                continue;
            }
            if (tokenToBuyInfoGlobals[1] > 1) {
                wethToSpend = (availableWeth * tokenToBuyInfo[2][i]) / tokenToBuyInfoGlobals[0];
            } else {
                wethToSpend = restWeth;
            }
            require(wethToSpend > 0 && wethToSpend <= restWeth, "Internal error");

            restWeth -= wethToSpend;
            --tokenToBuyInfoGlobals[1];

            outputAmounts[i] = safeSwap(
                [weth, tokensToBuy[i]],
                wethToSpend,
                dexRouter,
                allowanceToDexInfo
            );

            {
                address temp = tokensToBuy[i];
                totalTokenAmount[temp] += outputAmounts[i];
            }
        }

        require(restWeth == 0, "Internal error");

        return outputAmounts;
    }

    function transferTokenAndSwapToWeth(
        address tokenToPay,
        uint256 amount,
        address sender,
        address weth,
        address dexRouter,
        mapping(address => uint256) storage allowanceToDexInfo
    ) external returns (address, uint256) {
        tokenToPay = transferFromToGoodToken(tokenToPay, sender, amount, weth);
        uint256 totalWeth;
        if (tokenToPay == weth) {
            totalWeth = amount;
        } else {
            totalWeth = safeSwap([tokenToPay, weth], amount, dexRouter, allowanceToDexInfo);
        }

        return (tokenToPay, totalWeth);
    }

    function transferFromToGoodToken(
        address token,
        address user,
        uint256 amount,
        address weth
    ) public returns (address) {
        if (token == address(0)) {
            require(msg.value == amount, "Value error");
            token = weth;
            IWETH(weth).deposit{value: amount}();
        } else {
            require(msg.value == 0, "Value error");
            AssetLib.safeTransferFrom(token, user, amount);
        }
        return token;
    }

    function buyTokensMint(
        uint256 totalWeth,
        address[] memory tokensInAsset,
        address[2] memory wethAndDexRouter,
        mapping(address => uint256) storage tokensDistribution,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage allowanceToDexInfo
    ) external returns (uint256[] memory buyAmounts, uint256[] memory oldDistribution) {
        buyAmounts = new uint256[](tokensInAsset.length);
        oldDistribution = new uint256[](tokensInAsset.length);
        uint256 restWeth = totalWeth;
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 wethToThisToken;
            if (i < tokensInAsset.length - 1) {
                wethToThisToken = (totalWeth * tokensDistribution[tokensInAsset[i]]) / 1e4;
            } else {
                wethToThisToken = restWeth;
            }
            require(wethToThisToken > 0 && wethToThisToken <= restWeth, "Internal error");

            restWeth -= wethToThisToken;

            oldDistribution[i] = totalTokenAmount[tokensInAsset[i]];

            buyAmounts[i] = safeSwap(
                [wethAndDexRouter[0], tokensInAsset[i]],
                wethToThisToken,
                wethAndDexRouter[1],
                allowanceToDexInfo
            );

            totalTokenAmount[tokensInAsset[i]] = oldDistribution[i] + buyAmounts[i];
        }
    }

    function getMintAmount(
        address[] memory tokensInAsset,
        uint256[] memory buyAmounts,
        uint256[] memory oldDistribution,
        uint256 totalSupply,
        uint256 decimals,
        IOracle oracle
    ) public view returns (uint256 mintAmount) {
        uint256 totalPriceInAsset;
        uint256 totalPriceUser;
        (bool[] memory isValidValue, uint256[] memory tokensPrices) = oracle.getData(tokensInAsset);
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            require(isValidValue[i] == true, "Oracle error");
            uint256 decimalsToken = IERC20Metadata(tokensInAsset[i]).decimals();
            totalPriceInAsset += (oldDistribution[i] * tokensPrices[i]) / (10**decimalsToken);
            totalPriceUser += (buyAmounts[i] * tokensPrices[i]) / (10**decimalsToken);
        }

        if (totalPriceInAsset == 0 || totalSupply == 0) {
            return 10**decimals;
        } else {
            return (totalSupply * totalPriceUser) / totalPriceInAsset;
        }
    }

    function safeSwap(
        address[2] memory path,
        uint256 amount,
        address dexRouter,
        mapping(address => uint256) storage allowanceToDexInfo
    ) public returns (uint256) {
        if (path[0] == path[1]) {
            return amount;
        }

        if (allowanceToDexInfo[path[0]] < amount) {
            IERC20(path[0]).approve(address(dexRouter), type(uint256).max);
            allowanceToDexInfo[path[0]] = type(uint256).max - amount;
        }

        address[] memory _path = new address[](2);
        _path[0] = path[0];
        _path[1] = path[1];
        uint256[] memory amounts = IPancakeRouter02(dexRouter).swapExactTokensForTokens(
            amount,
            0,
            _path,
            address(this),
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        );

        return amounts[1];
    }

    function redeemAndTransfer(
        uint256[2] memory amountAndTotalSupply,
        address[4] memory userCurrencyToPayWethDexRouter,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage allowanceToDexInfo,
        address[] memory tokensInAsset,
        uint256[] memory feePercentages
    )
        public
        returns (
            uint256 feeTotal,
            uint256[] memory inputAmounts,
            uint256 outputAmountTotal
        )
    {
        inputAmounts = new uint256[](tokensInAsset.length);
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            inputAmounts[i] =
                (totalTokenAmount[tokensInAsset[i]] * amountAndTotalSupply[0]) /
                amountAndTotalSupply[1];

            uint256 outputAmount = swapToCurrency(
                tokensInAsset[i],
                userCurrencyToPayWethDexRouter[1],
                inputAmounts[i],
                [userCurrencyToPayWethDexRouter[2], userCurrencyToPayWethDexRouter[3]],
                allowanceToDexInfo
            );

            uint256 fee = (outputAmount * feePercentages[i]) / 1e4;
            outputAmountTotal += outputAmount - fee;
            feeTotal += fee;

            totalTokenAmount[tokensInAsset[i]] -= inputAmounts[i];
        }

        if (userCurrencyToPayWethDexRouter[1] == address(0)) {
            IWETH(userCurrencyToPayWethDexRouter[2]).withdraw(outputAmountTotal);
            safeTransfer(address(0), userCurrencyToPayWethDexRouter[0], outputAmountTotal);
        } else {
            safeTransfer(
                userCurrencyToPayWethDexRouter[1],
                userCurrencyToPayWethDexRouter[0],
                outputAmountTotal
            );
        }
    }

    function initTokenInfoFromWhitelist(
        address[] memory tokensWhitelist,
        mapping(address => uint256) storage tokenEntersIme
    ) external view returns (uint256[][3] memory tokensIncomeAmounts) {
        tokensIncomeAmounts[0] = new uint256[](tokensWhitelist.length);
        tokensIncomeAmounts[1] = new uint256[](tokensWhitelist.length);
        tokensIncomeAmounts[2] = new uint256[](tokensWhitelist.length);
        for (uint256 i = 0; i < tokensWhitelist.length; ++i) {
            tokensIncomeAmounts[0][i] = tokenEntersIme[tokensWhitelist[i]];
            tokensIncomeAmounts[2][i] = IERC20Metadata(tokensWhitelist[i]).decimals();
        }
    }

    function calculateXYAfterIme(
        address[] memory tokensInAsset,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage xVaultAmount,
        mapping(address => uint256) storage yVaultAmount
    ) external {
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 amountTotal = totalTokenAmount[tokensInAsset[i]];
            uint256 amountToX = (amountTotal * 2000) / 1e4;

            xVaultAmount[tokensInAsset[i]] = amountToX;
            yVaultAmount[tokensInAsset[i]] = amountTotal - amountToX;
        }
    }

    function depositToY(
        address[] memory tokensInAsset,
        uint256[] memory tokenAmountsOfY,
        address[] memory tokensOfDividends,
        uint256[] memory amountOfDividends,
        address sender,
        address dexRouter,
        address weth,
        mapping(address => uint256) storage allowanceToDexInfo,
        mapping(address => uint256) storage yVaultAmountInStaking,
        mapping(address => uint256) storage yVaultAmount
    ) external returns (uint256) {
        require(tokensInAsset.length == tokenAmountsOfY.length, "Input error 1");
        require(tokensOfDividends.length == amountOfDividends.length, "Input error 2");

        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 amountInStaking = yVaultAmountInStaking[tokensInAsset[i]];
            require(amountInStaking >= tokenAmountsOfY[i], "Trying to send more");
            amountInStaking -= tokenAmountsOfY[i];
            yVaultAmountInStaking[tokensInAsset[i]] = amountInStaking;
            yVaultAmount[tokensInAsset[i]] += tokenAmountsOfY[i];

            safeTransferFrom(tokensInAsset[i], sender, tokenAmountsOfY[i]);
        }

        uint256 totalWeth;
        for (uint256 i = 0; i < tokensOfDividends.length; ++i) {
            safeTransferFrom(tokensOfDividends[i], sender, amountOfDividends[i]);
            totalWeth += safeSwap(
                [tokensOfDividends[i], weth],
                amountOfDividends[i],
                dexRouter,
                allowanceToDexInfo
            );
        }
        return totalWeth;
    }

    function proceedIme(
        address[] memory tokens,
        IOracle oracle,
        mapping(address => uint256) storage tokenEntersIme
    ) external view returns (uint256, uint256[] memory) {
        (bool[] memory isValidValue, uint256[] memory tokensPrices) = oracle.getData(tokens);

        uint256 totalWeight;
        for (uint256 i = 0; i < tokens.length; ++i) {
            require(isValidValue[i] == true, "Not valid oracle values");
            uint256 decimals_ = IERC20Metadata(tokens[i]).decimals();
            totalWeight += (tokenEntersIme[tokens[i]] * tokensPrices[i]) / (10**decimals_);
        }

        return (totalWeight, tokensPrices);
    }

    function getFeePercentagesRedeem(
        address[] memory tokensInAsset,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage xVaultAmount
    ) external view returns (uint256[] memory feePercentages) {
        feePercentages = new uint256[](tokensInAsset.length);

        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 totalAmount = totalTokenAmount[tokensInAsset[i]];
            uint256 xAmount = xVaultAmount[tokensInAsset[i]];

            if (xAmount >= (1500 * totalAmount) / 1e4) {
                feePercentages[i] = 200;
            } else if (
                xAmount < (1500 * totalAmount) / 1e4 && xAmount >= (500 * totalAmount) / 1e4
            ) {
                uint256 xAmountPertcentage = (xAmount * 1e4) / totalAmount;
                feePercentages[i] = 600 - (400 * (xAmountPertcentage - 500)) / 1000;
            } else {
                revert("xAmount percentage error");
            }
        }
    }

    function swapToCurrency(
        address inputCurrency,
        address outputCurrency,
        uint256 amount,
        address[2] memory wethAndDexRouter,
        mapping(address => uint256) storage allowanceToDexInfo
    ) internal returns (uint256) {
        require(inputCurrency != address(0), "Internal error");
        if (inputCurrency != outputCurrency) {
            uint256 outputAmount;
            if (outputCurrency == wethAndDexRouter[0] || outputCurrency == address(0)) {
                outputAmount = safeSwap(
                    [inputCurrency, wethAndDexRouter[0]],
                    amount,
                    wethAndDexRouter[1],
                    allowanceToDexInfo
                );
            } else {
                outputAmount = safeSwap(
                    [inputCurrency, wethAndDexRouter[0]],
                    amount,
                    wethAndDexRouter[1],
                    allowanceToDexInfo
                );
                outputAmount = safeSwap(
                    [wethAndDexRouter[0], outputCurrency],
                    outputAmount,
                    wethAndDexRouter[1],
                    allowanceToDexInfo
                );
            }
            return outputAmount;
        } else {
            return amount;
        }
    }

    function safeTransferFrom(
        address token,
        address from,
        uint256 amount
    ) internal {
        if (token == address(0)) {
            require(msg.value == amount, "Value error");
        } else {
            require(IERC20(token).transferFrom(from, address(this), amount), "TransferFrom failed");
        }
    }

    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) public {
        if (to == address(this)) {
            return;
        }
        if (token == address(0)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = to.call{value: amount}(new bytes(0));
            require(success, "Transfer eth failed");
        } else {
            require(IERC20(token).transfer(to, amount), "Transfer token failed");
        }
    }

    function checkAllowance(
        address token,
        address to,
        uint256 amount
    ) external {
        uint256 allowance = IERC20(token).allowance(address(this), to);

        if (amount > allowance) {
            IERC20(token).approve(to, type(uint256).max);
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../pancake-swap/interfaces/IPancakeRouter02.sol";
import "../pancake-swap/interfaces/IWETH.sol";

import "../interfaces/IOracle.sol";

import "./AssetLib.sol";

library AssetLib2 {
    function calculateBuyAmountOut(
        uint256 amount,
        address currencyIn,
        address[] memory tokensInAsset,
        address[3] memory wethDexRouterAndOracle,
        uint256 totalSupply,
        uint256 decimals,
        mapping(address => uint256) storage tokensDistribution,
        mapping(address => uint256) storage totalTokenAmount
    ) external view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        address[] memory path = new address[](2);
        if (currencyIn == address(0)) {
            currencyIn = wethDexRouterAndOracle[0];
        }
        if (currencyIn != wethDexRouterAndOracle[0]) {
            path[0] = currencyIn;
            path[1] = wethDexRouterAndOracle[0];
            try IPancakeRouter02(wethDexRouterAndOracle[1]).getAmountsOut(amount, path) returns (
                uint256[] memory amounts
            ) {
                amount = amounts[1];
            } catch (bytes memory) {
                amount = 0;
            }
            /* uint256[] memory amounts =
                IPancakeRouter02(wethDexRouterAndOracle[1]).getAmountsOut(amount, path);
            amount = amounts[1]; */
        }
        if (amount == 0) {
            return 0;
        }
        amount -= (amount * 50) / 1e4;
        uint256 restAmount = amount;
        uint256[][2] memory buyAmountsAndDistribution;
        buyAmountsAndDistribution[0] = new uint256[](tokensInAsset.length);
        buyAmountsAndDistribution[1] = new uint256[](tokensInAsset.length);
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 wethToThisToken;
            buyAmountsAndDistribution[1][i] = totalTokenAmount[tokensInAsset[i]];
            if (i < tokensInAsset.length - 1) {
                wethToThisToken = (amount * tokensDistribution[tokensInAsset[i]]) / 1e4;
            } else {
                wethToThisToken = restAmount;
            }
            restAmount -= wethToThisToken;

            if (tokensInAsset[i] != wethDexRouterAndOracle[0]) {
                path[0] = wethDexRouterAndOracle[0];
                path[1] = tokensInAsset[i];
                try
                    IPancakeRouter02(wethDexRouterAndOracle[1]).getAmountsOut(wethToThisToken, path)
                returns (uint256[] memory amounts) {
                    buyAmountsAndDistribution[0][i] = amounts[1];
                } catch (bytes memory) {
                    buyAmountsAndDistribution[0][i] = 0;
                }
                /* uint256[] memory amounts =
                    IPancakeRouter02(wethDexRouterAndOracle[1]).getAmountsOut(
                        wethToThisToken,
                        path
                    );
                buyAmountsAndDistribution[0][i] = amounts[1]; */
            } else {
                buyAmountsAndDistribution[0][i] = wethToThisToken;
            }
        }

        return
            AssetLib.getMintAmount(
                tokensInAsset,
                buyAmountsAndDistribution[0],
                buyAmountsAndDistribution[1],
                totalSupply,
                decimals,
                IOracle(wethDexRouterAndOracle[2])
            );
    }

    function calculateSellAmountOut(
        uint256[2] memory amountAndTotalSupply,
        address currencyToPay,
        address[] memory tokensInAsset,
        address[2] memory wethAndDexRouter,
        mapping(address => uint256) storage totalTokenAmount,
        mapping(address => uint256) storage xVaultAmount
    ) external view returns (uint256) {
        if (amountAndTotalSupply[0] == 0) {
            return 0;
        }
        if (currencyToPay == address(0)) {
            currencyToPay = wethAndDexRouter[0];
        }
        uint256[] memory feePercentages = AssetLib.getFeePercentagesRedeem(
            tokensInAsset,
            totalTokenAmount,
            xVaultAmount
        );

        address[] memory path2 = new address[](2);
        address[] memory path3 = new address[](3);
        path2[1] = currencyToPay;
        path3[1] = wethAndDexRouter[0];
        path3[2] = currencyToPay;
        uint256 outputAmountTotal;
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 inputAmount = (totalTokenAmount[tokensInAsset[i]] * amountAndTotalSupply[0]) /
                amountAndTotalSupply[1];

            if (inputAmount == 0) {
                continue;
            }

            uint256 outputAmount;
            if (tokensInAsset[i] != currencyToPay) {
                if (
                    currencyToPay == wethAndDexRouter[0] || tokensInAsset[i] == wethAndDexRouter[0]
                ) {
                    path2[0] = tokensInAsset[i];
                    try
                        IPancakeRouter02(wethAndDexRouter[1]).getAmountsOut(inputAmount, path2)
                    returns (uint256[] memory amounts) {
                        outputAmount = amounts[1];
                    } catch (bytes memory) {
                        outputAmount = 0;
                    }
                    /* uint256[] memory amounts =
                        IPancakeRouter02(wethAndDexRouter[1]).getAmountsOut(inputAmount, path2);
                    outputAmount = amounts[1]; */
                } else {
                    path3[0] = tokensInAsset[i];
                    try
                        IPancakeRouter02(wethAndDexRouter[1]).getAmountsOut(inputAmount, path3)
                    returns (uint256[] memory amounts) {
                        outputAmount = amounts[2];
                    } catch (bytes memory) {
                        outputAmount = 0;
                    }
                    /* uint256[] memory amounts = IPancakeRouter02(wethAndDexRouter[1]).getAmountsOut(
                        inputAmount,
                        path3
                    );
                    outputAmount = amounts[2]; */
                }
            } else {
                outputAmount = inputAmount;
            }

            uint256 fee = (outputAmount * feePercentages[i]) / 1e4;
            outputAmountTotal += outputAmount - fee;
        }

        return outputAmountTotal;
    }

    function xyDistributionAfterMint(
        address[] memory tokensInAsset,
        uint256[] memory buyAmounts,
        uint256[] memory oldDistribution,
        mapping(address => uint256) storage xVaultAmount,
        mapping(address => uint256) storage yVaultAmount
    ) external {
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 totalAmount = buyAmounts[i] + oldDistribution[i];
            uint256 maxAmountInX = (totalAmount * 2000) / 1e4;

            uint256 amountInXOld = xVaultAmount[tokensInAsset[i]];
            uint256 restAmountToDistribute = buyAmounts[i];
            if (amountInXOld < maxAmountInX) {
                amountInXOld += restAmountToDistribute;
                if (amountInXOld > maxAmountInX) {
                    uint256 delta = amountInXOld - maxAmountInX;
                    amountInXOld = maxAmountInX;
                    restAmountToDistribute = delta;
                } else {
                    restAmountToDistribute = 0;
                }
            }

            if (restAmountToDistribute > 0) {
                yVaultAmount[tokensInAsset[i]] += restAmountToDistribute;
            }

            xVaultAmount[tokensInAsset[i]] = amountInXOld;
        }
    }

    function xyDistributionAfterRedeem(
        mapping(address => uint256) storage totalTokenAmount,
        bool isAllowedAutoXYRebalace,
        mapping(address => uint256) storage xVaultAmount,
        mapping(address => uint256) storage yVaultAmount,
        address[] memory tokensInAsset,
        uint256[] memory sellAmounts
    ) public {
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 totalAmount = totalTokenAmount[tokensInAsset[i]];
            uint256 xStopAmount = (totalAmount * 500) / 1e4;
            uint256 xAmountMax = (totalAmount * 2000) / 1e4;

            uint256 xAmount = xVaultAmount[tokensInAsset[i]];
            if (isAllowedAutoXYRebalace == true) {
                uint256 yAmount = yVaultAmount[tokensInAsset[i]];
                require(
                    xAmount + yAmount >= sellAmounts[i] &&
                        xAmount + yAmount - sellAmounts[i] >= xStopAmount,
                    "Not enough XY"
                );
                if (xAmount >= sellAmounts[i] && xAmount - sellAmounts[i] >= xStopAmount) {
                    xAmount -= sellAmounts[i];
                } else {
                    xAmount += yAmount;
                    xAmount -= sellAmounts[i];
                    if (xAmount > xAmountMax) {
                        uint256 delta = xAmount - xAmountMax;
                        yAmount = delta;
                        xAmount = xAmountMax;

                        yVaultAmount[tokensInAsset[i]] = yAmount;
                    }
                }
            } else {
                require(
                    xAmount >= sellAmounts[i] && xAmount - sellAmounts[i] >= xStopAmount,
                    "Not enough X"
                );
                xAmount -= sellAmounts[i];
            }
            xVaultAmount[tokensInAsset[i]] = xAmount;
        }
    }

    function xyDistributionAfterRebase(
        address[] memory tokensInAssetNow,
        uint256[] memory tokensInAssetNowSellAmounts,
        address[] memory tokensToBuy,
        uint256[] memory tokenToBuyAmounts,
        mapping(address => uint256) storage xVaultAmount,
        mapping(address => uint256) storage yVaultAmount,
        mapping(address => uint256) storage totalTokenAmount
    ) external {
        for (uint256 i = 0; i < tokensInAssetNow.length; ++i) {
            uint256 xAmount = xVaultAmount[tokensInAssetNow[i]];
            uint256 yAmount = yVaultAmount[tokensInAssetNow[i]];

            require(
                xAmount + yAmount >= tokensInAssetNowSellAmounts[i],
                "Not enought value in asset"
            );
            if (tokensInAssetNowSellAmounts[i] > yAmount) {
                xAmount -= tokensInAssetNowSellAmounts[i] - yAmount;
                yAmount = 0;
                xVaultAmount[tokensInAssetNow[i]] = xAmount;
                yVaultAmount[tokensInAssetNow[i]] = yAmount;
            } else {
                yAmount -= tokensInAssetNowSellAmounts[i];
                yVaultAmount[tokensInAssetNow[i]] = yAmount;
            }
        }

        for (uint256 i = 0; i < tokensToBuy.length; ++i) {
            uint256 xAmount = xVaultAmount[tokensToBuy[i]];
            uint256 yAmount = yVaultAmount[tokensToBuy[i]];
            uint256 xMaxAmount = (totalTokenAmount[tokensToBuy[i]] * 2000) / 1e4;

            xAmount += tokenToBuyAmounts[i];
            if (xAmount > xMaxAmount) {
                yAmount += xAmount - xMaxAmount;
                xAmount = xMaxAmount;
                xVaultAmount[tokensToBuy[i]] = xAmount;
                yVaultAmount[tokensToBuy[i]] = yAmount;
            } else {
                xVaultAmount[tokensToBuy[i]] = xAmount;
            }
        }
    }

    function xyRebalance(
        uint256 xPercentage,
        address[] memory tokensInAsset,
        mapping(address => uint256) storage xVaultAmount,
        mapping(address => uint256) storage yVaultAmount,
        mapping(address => uint256) storage totalTokenAmount
    ) external {
        for (uint256 i = 0; i < tokensInAsset.length; ++i) {
            uint256 totalAmount = totalTokenAmount[tokensInAsset[i]];
            uint256 xAmount = xVaultAmount[tokensInAsset[i]];
            uint256 yAmount = yVaultAmount[tokensInAsset[i]];
            uint256 xAmountDesired = (totalAmount * xPercentage) / 1e4;

            if (xAmount > xAmountDesired) {
                yAmount += xAmount - xAmountDesired;
                xAmount = xAmountDesired;
                xVaultAmount[tokensInAsset[i]] = xAmount;
                yVaultAmount[tokensInAsset[i]] = yAmount;
            } else if (xAmount < xAmountDesired) {
                uint256 delta = xAmountDesired - xAmount;
                require(yAmount >= delta, "Not enough value in Y");
                xAmount += delta;
                yAmount -= delta;
            } else {
                continue;
            }
            xVaultAmount[tokensInAsset[i]] = xAmount;
            yVaultAmount[tokensInAsset[i]] = yAmount;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPancakeRouter01 {
    function factory() external view returns (address);

    function WETH() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IPancakeRouter01.sol";

interface IPancakeRouter02 is IPancakeRouter01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./extensions/IERC20MetadataUpgradeable.sol";
import "../../utils/ContextUpgradeable.sol";
import "../../proxy/utils/Initializable.sol";

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
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal initializer {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal initializer {
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
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

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
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

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

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

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

        _totalSupply += amount;
        _balances[account] += amount;
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

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

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
    uint256[45] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
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
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
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

    constructor () {
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

