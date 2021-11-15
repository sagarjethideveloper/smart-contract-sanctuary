// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/SafeERC20.sol";
import "./access/Ownable.sol";
import "./utils/Pausable.sol";
import "./utils/ReentrancyGuard.sol";
import "./IStdReference.sol";
import "./math/SafeMath.sol";

// @dev use this interface for burning systhetic asset.
// @notic burnFrom() need to call approve() before call this function.
interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function mint(address account, uint256 amount) external;
}

/**
 * @dev Synthetic contract is the contract that minting systhetic asset by given amount of collateral
 * Minter can mint, redeem (some or all all them), add more collateral (to avoid liquidation),
 * remove some collateral (to withdraw the backed asset). If the ratio between collateral and synthetic value
 * goes lower than liquidation ratio, anyone can call the liquidate function to get the reward and close that contract.
 * @notice the requirement of this contract are
 * Contract address of Dolly (constuctor parameter).
 * Contract address of referrence of orale Band protocol (constuctor parameter).
 * Contract address of synthetic token contracts.
 * Set the ownership of synthetic token contract (e.g. TSLA) to this contract.
 * Set the pairsToQuote of supported synthetic asset (e.g. pairsToQuote["TSLA/USD"] = ["TSLA", "USD"]).
 * Set the pairsToAddress of supported synthetic asset (e.g. pairsToAddress["TSLA/USD"] = 0x65cAC0F09EFdB88195a002E8DD4CBF6Ec9BC7f60).
 * Set the pairsToAddress of supported synthetic asset (e.g. pairsToAddress["TSLA/USD"] = 0x65cAC0F09EFdB88195a002E8DD4CBF6Ec9BC7f60).
 * Set the addressToPairs of supported synthetic asset (e.g.) addressToPairs[0x65cAC0F09EFdB88195a002E8DD4CBF6Ec9BC7f60] = "TSLA/USD".
 */
contract Synthetic is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public dolly;
    IStdReference public bandOracle;

    mapping(string => string[2]) public pairsToQuote;
    mapping(string => address) public pairsToAddress;
    mapping(address => string) public addressToPairs;

    uint256 public constant denominator = 1e18; // 1 scaled by 1e18
    uint256 public collateralRatio = 1e18 + 5e17; // 1.5 scaled by 1e18 (> 1.5 is good)
    uint256 public liquidationRatio = 1e18 + 25e16; // 1.25 scaled by 1e18

    // allocation of liquidating gap between closing contract and remainning backedAsset
    uint256 public liquidatorRewardRatio = 5e16; // 0.05 scaled by 1e18
    uint256 public platfromFeeRatio = 5e16; // 0.05 scaled by 1e18
    uint256 public remainingToMinterRatio = 9e17; // 0.9 scaled by 1e18
    address public devAddress; // dev address to collect liquidation fee

    // struct of minting the synthetic asset
    struct MintingNote {
        address minter; // address of minter
        IERC20Burnable asset; // synthetic asset address
        IERC20 assetBacked; // dolly address
        uint256 assetAmount; // amount of synthetic asset to be minted
        uint256 assetBackedAmount; // amount of Dolly
        uint256 currentRatio; // the current ratio between collateral value and minted systhetic value
        uint256 willLiquidateAtPrice; // the price that will liquidate this contract
        uint256 canMintRemainning; // amount of this synthetic asset that can be minted
        uint256 canWithdrawRemainning; // amount of Dolly that can be withdraw
        uint256 updatedAt;
        uint256 updatedBlock;
        uint256 exchangeRateAtMinted; // exchange rate at minted
        uint256 currentExchangeRate; // last exchage rate
    }

    mapping(address => mapping(address => MintingNote)) public contracts; // minter => asset => MintingNote

    event MintAsset(
        address minter,
        address indexed syntheticAddress,
        uint256 amount
    );
    event RedeemAsset(address indexed syntheticAddress, uint256 amount);
    event AddCollateral(address indexed user, uint256 amount);
    event RemoveCollateral(address indexed user, uint256 amount);
    event AddSynthetic(address indexed user, uint256 amount);
    event RemoveSynthetic(address indexed user, uint256 amount);
    event Liquidated(
        address indexed liquidated,
        address indexed liquidator,
        address indexed syntheticAddress,
        uint256 amount,
        uint256 timestamp
    );

    event SetDevAddress(address oldDevAddress, address newDevAddress);
    event SetCollateralRatio(
        uint256 oldCollateralRatio,
        uint256 newCollateralRatio
    );
    event SetLiquidationRatio(
        uint256 oldLiquidationRatio,
        uint256 newLiquidationRatio
    );
    event SetLiquidatorRewardRatio(
        uint256 oldLiquidatorRewardRatio,
        uint256 newLiquidatorRewardRatio
    );
    event SetPlatfromFeeRatio(
        uint256 oldPlatfromFeeRatio,
        uint256 newPlatfromFeeRatio
    );
    event SetRemainingToMinterRatio(
        uint256 oldRemainingToMinterRatio,
        uint256 newRemainingToMinterRatio
    );

    /**
     * @dev the constructor requires an address of Dolly and referrence of oracle Band Protocol
     * @param _dolly smartcontract address of Dolly
     * @param _ref referrence of oracle Band Protocol
     */
    constructor(IERC20 _dolly, IStdReference _ref) public {
        dolly = _dolly; // use Dolly as collateral
        bandOracle = _ref;
        devAddress = _msgSender();
    }

    /**
     * @dev user need to approve for deducting $DOLLY at Dolly contract first.
     * @param _synthetic name
     * @param _amount amount of synthetic that want to mint
     * @param _backedAmount amount of Dolly that you want to collateral
     */
    function mintSynthetic(
        IERC20Burnable _synthetic,
        uint256 _amount,
        uint256 _backedAmount
    ) external whenNotPaused nonReentrant {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];

        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        uint256 assetBackedAtRateAmount = getProductOf(_amount, exchangeRate);
        uint256 requiredAmount =
            getProductOf(assetBackedAtRateAmount, collateralRatio);
        require(
            _backedAmount >= requiredAmount,
            "Synthetic::mintSynthetic: under collateral"
        );
        _synthetic.mint(_msgSender(), _amount);
        dolly.safeTransferFrom(_msgSender(), address(this), _backedAmount);
        mn.minter = _msgSender();
        mn.asset = _synthetic;
        mn.assetBacked = dolly;
        mn.assetAmount = _amount;
        mn.assetBackedAmount = _backedAmount;
        mn.exchangeRateAtMinted = exchangeRate;
        mn.currentExchangeRate = exchangeRate;
        mn.currentRatio = getRatioOf(_backedAmount, assetBackedAtRateAmount);
        mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
            exchangeRate,
            mn.currentRatio
        );
        mn.canWithdrawRemainning = _backedAmount.sub(requiredAmount);
        mn.canMintRemainning = getRatioOf(
            mn.canWithdrawRemainning,
            assetBackedAtRateAmount
        );
        mn.updatedAt = block.timestamp;
        mn.updatedBlock = block.number;
        emit MintAsset(_msgSender(), address(_synthetic), _amount);
    }

    /**
     * @dev minter needs to approve for burn at SyntheticAsset before call this function.
     * @param _synthetic amount of synthetic that want to mint
     * @param _amount amount of Dolly that you want to collateral
     */
    function redeemSynthetic(IERC20Burnable _synthetic, uint256 _amount)
        external
        whenNotPaused
        nonReentrant
    {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];
        require(
            mn.assetAmount >= _amount,
            "Synthetic::redeemSynthetic: amount exceeds collateral"
        );

        if (_amount == mn.assetAmount) {
            // redeem and exit
            _synthetic.burnFrom(_msgSender(), _amount);
            dolly.safeTransfer(_msgSender(), mn.assetBackedAmount);
            delete contracts[_msgSender()][address(_synthetic)];
            emit RedeemAsset(address(_synthetic), _amount);
        } else {
            // patial redeeming
            uint256 percent = getRatioOf(_amount, mn.assetAmount);
            uint256 assetToBeBurned = getProductOf(mn.assetAmount, percent);
            uint256 assetBackedToBeRedeemed =
                getProductOf(mn.assetBackedAmount, percent);
            uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
            uint256 assetBackedAmountAfterRedeem =
                mn.assetBackedAmount.sub(assetBackedToBeRedeemed);

            uint256 assetRemainningAfterBurned =
                mn.assetAmount.sub(assetToBeBurned);
            uint256 assetBackedAtRateAmount =
                (assetRemainningAfterBurned.mul(exchangeRate)).div(denominator);

            uint256 requiredAmount =
                (assetBackedAtRateAmount.mul(collateralRatio)).div(denominator);
            require(
                assetBackedAmountAfterRedeem >= requiredAmount,
                "Synthetic::redeemSynthetic: under collateral ratio"
            );
            _synthetic.burnFrom(_msgSender(), assetToBeBurned);
            dolly.safeTransfer(_msgSender(), assetBackedToBeRedeemed);

            mn.assetAmount = assetRemainningAfterBurned;
            mn.assetBackedAmount = assetBackedAmountAfterRedeem;
            mn.currentRatio = getRatioOf(
                mn.assetBackedAmount,
                assetBackedAtRateAmount
            );
            mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
                exchangeRate,
                mn.currentRatio
            );
            mn.canWithdrawRemainning = assetBackedAmountAfterRedeem.sub(
                requiredAmount
            );
            mn.canMintRemainning = getRatioOf(
                mn.canWithdrawRemainning,
                assetBackedAtRateAmount
            );
            mn.currentExchangeRate = exchangeRate;
            mn.updatedAt = block.timestamp;
            mn.updatedBlock = block.number;
            emit RedeemAsset(address(_synthetic), _amount);
        }
    }

    /**
     * @dev add more collateral for minted contract
     * @param _synthetic the address of synthetic asset
     * @param _addAmount amount of Dolly which want to add
     */
    function addCollateral(IERC20Burnable _synthetic, uint256 _addAmount)
        external
        whenNotPaused
        nonReentrant
    {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];
        require(
            mn.assetAmount > 0,
            "Synthetic::addCollateral: cannot add collateral to empty contract"
        );
        mn.assetBackedAmount = mn.assetBackedAmount.add(_addAmount);
        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        uint256 assetBackedAtRateAmount =
            (mn.assetAmount.mul(exchangeRate)).div(denominator);
        uint256 requiredAmount =
            (assetBackedAtRateAmount.mul(collateralRatio)).div(denominator);
        dolly.safeTransferFrom(_msgSender(), address(this), _addAmount);
        mn.currentRatio = getRatioOf(
            mn.assetBackedAmount,
            assetBackedAtRateAmount
        );
        mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
            exchangeRate,
            mn.currentRatio
        );
        mn.canWithdrawRemainning = mn.assetBackedAmount.sub(requiredAmount);
        mn.canMintRemainning = getRatioOf(
            mn.canWithdrawRemainning,
            assetBackedAtRateAmount
        );
        mn.currentExchangeRate = exchangeRate;
        mn.updatedAt = block.timestamp;
        mn.updatedBlock = block.number;
        emit AddCollateral(_msgSender(), _addAmount);
    }

    /**
     * @dev remove some collateral for minted contract
     * @param _synthetic the address of synthetic asset
     * @param _removeBackedAmount amount of collateral which want to remove
     */
    function removeCollateral(
        IERC20Burnable _synthetic,
        uint256 _removeBackedAmount
    ) external whenNotPaused nonReentrant {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];
        require(
            mn.assetAmount > 0,
            "Synthetic::removeCollateral: cannot remove collateral to empty contract"
        );
        mn.assetBackedAmount = mn.assetBackedAmount.sub(_removeBackedAmount);
        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        uint256 assetBackedAtRateAmount =
            getProductOf(mn.assetAmount, exchangeRate);
        uint256 requiredAmount =
            getProductOf(assetBackedAtRateAmount, collateralRatio);
        uint256 canWithdrawRemainning =
            mn.assetBackedAmount.sub(requiredAmount);
        require(
            canWithdrawRemainning >= _removeBackedAmount,
            "Synthetic::removeCollateral: amount exceeds required collateral"
        );
        dolly.safeTransfer(_msgSender(), _removeBackedAmount);
        mn.currentRatio = getRatioOf(
            mn.assetBackedAmount,
            assetBackedAtRateAmount
        );
        mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
            exchangeRate,
            mn.currentRatio
        );
        mn.canWithdrawRemainning = canWithdrawRemainning;
        mn.canMintRemainning = getRatioOf(
            canWithdrawRemainning,
            assetBackedAtRateAmount
        );
        mn.currentExchangeRate = exchangeRate;
        mn.updatedAt = block.timestamp;
        mn.updatedBlock = block.number;
        emit RemoveCollateral(_msgSender(), _removeBackedAmount);
    }

    /**
     * @dev for testing purpose.
     * @notice this function will remove some collateral to simulate under collateral and need to be liquidated in the future.
     * @param _synthetic: the address of synthetic asset.
     * @param _removeAmount: amount of collateral which want to remove.
     */
    function removeLowerCollateral(
        IERC20Burnable _synthetic,
        uint256 _removeAmount
    ) external onlyOwner whenNotPaused nonReentrant {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];
        require(
            mn.assetAmount > 0,
            "Synthetic::removeCollateral: cannot remove collateral to empty contract"
        );
        mn.assetBackedAmount = mn.assetBackedAmount.sub(_removeAmount);
        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        uint256 assetBackedAtRateAmount =
            (mn.assetAmount.mul(exchangeRate)).div(denominator);
        dolly.safeTransfer(_msgSender(), _removeAmount);
        mn.currentRatio = getRatioOf(
            mn.assetBackedAmount,
            assetBackedAtRateAmount
        );
        mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
            exchangeRate,
            mn.currentRatio
        );
        mn.canWithdrawRemainning = 0;
        mn.canMintRemainning = 0;
        mn.currentExchangeRate = exchangeRate;
        mn.updatedAt = block.timestamp;
        mn.updatedBlock = block.number;
        emit RemoveCollateral(_msgSender(), _removeAmount);
    }

    /**
     * @dev if minter have a lot of collateral, minter can get more synthetic asset while the collateral ratio is sastisfy
     * @param _synthetic the address of synthetic asset.
     * @param _addAmount the amount of synthetic asset that want to mint more.
     */
    function addSynthetic(IERC20Burnable _synthetic, uint256 _addAmount)
        external
        whenNotPaused
        nonReentrant
    {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];
        require(
            mn.assetAmount > 0,
            "Synthetic::addCollateral: cannot add synthetic to empty contract"
        );
        mn.assetAmount = mn.assetAmount.add(_addAmount);
        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        uint256 assetBackedAtRateAmount =
            getProductOf(mn.assetAmount, exchangeRate);
        uint256 requiredAmount =
            getProductOf(assetBackedAtRateAmount, collateralRatio);
        require(
            mn.assetBackedAmount > requiredAmount,
            "Synthetic::addSynthetic: under collateral"
        );
        _synthetic.mint(_msgSender(), _addAmount);
        mn.currentRatio = getRatioOf(
            mn.assetBackedAmount,
            assetBackedAtRateAmount
        );
        mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
            exchangeRate,
            mn.currentRatio
        );
        mn.canWithdrawRemainning = mn.assetBackedAmount.sub(requiredAmount);
        mn.canMintRemainning = getRatioOf(
            mn.canWithdrawRemainning,
            assetBackedAtRateAmount
        );
        mn.currentExchangeRate = exchangeRate;
        mn.updatedAt = block.timestamp;
        mn.updatedBlock = block.number;
        emit AddSynthetic(_msgSender(), _addAmount);
    }

    /**
     * @dev if minter have a lot of synthetic asset, minter can remove synthetic asset to increase the collateral ratio
     * @param _synthetic: the address of synthetic asset.
     * @param _removeAmount: amount of synthetic asset that want to remove.
     */
    function removeSynthetic(IERC20Burnable _synthetic, uint256 _removeAmount)
        external
        whenNotPaused
        nonReentrant
    {
        MintingNote storage mn = contracts[_msgSender()][address(_synthetic)];
        require(
            mn.assetAmount > 0,
            "Synthetic::removeSynthetic: cannot add synthetic to empty contract"
        );
        mn.assetAmount = mn.assetAmount.sub(_removeAmount);
        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        uint256 assetBackedAtRateAmount =
            getProductOf(mn.assetAmount, exchangeRate);
        uint256 requiredAmount =
            getProductOf(assetBackedAtRateAmount, collateralRatio);
        _synthetic.burnFrom(_msgSender(), _removeAmount);
        mn.currentRatio = getRatioOf(
            mn.assetBackedAmount,
            assetBackedAtRateAmount
        );
        mn.willLiquidateAtPrice = getWillLiquidateAtPrice(
            exchangeRate,
            mn.currentRatio
        );
        mn.canWithdrawRemainning = mn.assetBackedAmount.sub(requiredAmount);
        mn.canMintRemainning = getRatioOf(
            mn.canWithdrawRemainning,
            assetBackedAtRateAmount
        );
        mn.currentExchangeRate = exchangeRate;
        mn.updatedAt = block.timestamp;
        mn.updatedBlock = block.number;
        emit RemoveSynthetic(_msgSender(), _removeAmount);
    }

    /**
     * @dev liquidator must approve Synthetic asset to spending Dolly
     * @param _synthetic the address of synthetic asset.
     * @param _minter address of minter.
     */
    function liquidate(IERC20Burnable _synthetic, address _minter)
        external
        whenNotPaused
        nonReentrant
    {
        (
            uint256 assetBackedAtRateAmount,
            uint256 remainingGapAmount,
            uint256 minterReceiveAmount,
            uint256 liquidatorReceiveAmount,
            uint256 platformReceiveAmount
        ) = getRewardFromLiquidate(_synthetic, _minter);

        if (remainingGapAmount > 0) {
            // collateral ratio is between 1.0 - 1.25, so liquidator will get the reward.
            dolly.safeTransferFrom(
                _msgSender(),
                address(this),
                assetBackedAtRateAmount
            ); // deduct Doly from liquidator.
            dolly.safeTransfer(_minter, minterReceiveAmount); // transfer remainning to minter (90%).
            dolly.safeTransfer(
                _msgSender(),
                assetBackedAtRateAmount.add(liquidatorReceiveAmount)
            ); // transfer reward to to liquidator (5%) + original amount.
            dolly.safeTransfer(devAddress, platformReceiveAmount); // transfer liquidating fee to dev address (5%).
        } else {
            // collateral ratio is less than 1.0.
            dolly.safeTransferFrom(
                _msgSender(),
                address(this),
                assetBackedAtRateAmount
            ); // deduct Doly from liquidator.
        }
        delete contracts[_minter][address(_synthetic)];
    }

    /**
     * @dev set the pairs and quotes to calling the oracle.
     * @param _pairs string of pairs e.g. "TSLA/USD".
     * @param baseAndQuote 2 elements array e.g. ["TSLA"]["USD"].
     */
    function setPairsToQuote(
        string memory _pairs,
        string[2] memory baseAndQuote
    ) external onlyOwner {
        pairsToQuote[_pairs] = baseAndQuote;
    }

    /**
     * @dev use this function to get the synthetic token address by given string pairs.
     * @param _pairs string of pairs e.g. "TSLA/USD".
     * @param _syntheticAddress address of synthetic asset.
     */
    function setPairsToAddress(string memory _pairs, address _syntheticAddress)
        external
        onlyOwner
    {
        pairsToAddress[_pairs] = _syntheticAddress;
    }

    /**
     * @dev map synthetic token address to string of pairs. Used for getRate() function
     * @param _pairs string of pairs e.g. "TSLA/USD".
     * @param _syntheticAddress address of synthetic asset.
     */
    function setAddressToPairs(address _syntheticAddress, string memory _pairs)
        external
        onlyOwner
    {
        addressToPairs[_syntheticAddress] = _pairs;
    }

    /**
     * @dev set dev address to receive liquidation fee.
     * @param _devAddress new developer address.
     */
    function setDevAddress(address _devAddress) external onlyOwner {
        address oldDevAddress = devAddress;
        devAddress = _devAddress;
        emit SetDevAddress(oldDevAddress, _devAddress);
    }

    /**
     * @dev set collateral ratio.
     * @param _collateralRatio: new collateral ratio.
     */
    function setCollateralRatio(uint256 _collateralRatio) external onlyOwner {
        uint256 oldCollateralRatio = collateralRatio;
        collateralRatio = _collateralRatio;
        emit SetCollateralRatio(oldCollateralRatio, _collateralRatio);
    }

    /**
     * @dev set liquidation ratio.
     * @param _liquidationRatio new liquidation ratio.
     */
    function setLiquidationRatio(uint256 _liquidationRatio) external onlyOwner {
        uint256 oldLiquidationRatio = liquidationRatio;
        liquidationRatio = _liquidationRatio;
        emit SetLiquidationRatio(oldLiquidationRatio, _liquidationRatio);
    }

    /**
     * @dev set liquidator reward ratio.
     * @param _liquidatorRewardRatio new liquidator reward ratio.
     */
    function setLiquidatorRewardRatio(uint256 _liquidatorRewardRatio)
        external
        onlyOwner
    {
        uint256 oldLiquidatorRewardRatio = liquidatorRewardRatio;
        liquidatorRewardRatio = _liquidatorRewardRatio;
        emit SetLiquidatorRewardRatio(
            oldLiquidatorRewardRatio,
            _liquidatorRewardRatio
        );
    }

    /**
     * @dev set platfrom fee ratio.
     * @param _platfromFeeRatio new platfrom fee ratio.
     */
    function setPlatfromFeeRatio(uint256 _platfromFeeRatio) external onlyOwner {
        uint256 oldPlatfromFeeRatio = platfromFeeRatio;
        platfromFeeRatio = _platfromFeeRatio;
        emit SetPlatfromFeeRatio(oldPlatfromFeeRatio, _platfromFeeRatio);
    }

    /**
     * @dev set remaining of backed asset to minter ratio.
     * @param _remainingToMinterRatio new remaining to minter ratio.
     */
    function setRemainingToMinterRatio(uint256 _remainingToMinterRatio)
        external
        onlyOwner
    {
        uint256 oldRemainingToMinterRatio = remainingToMinterRatio;
        remainingToMinterRatio = _remainingToMinterRatio;
        emit SetRemainingToMinterRatio(
            oldRemainingToMinterRatio,
            _remainingToMinterRatio
        );
    }

    /**
     * @dev for simulate all relevant amount of liqiodation
     * @notice both liquidate bot and this contract can call this function to estimate the profit.
     * @param _synthetic a contract address of synthetic asset.
     * @param _minter an address of minter.
     */
    function getRewardFromLiquidate(IERC20Burnable _synthetic, address _minter)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        MintingNote storage mn = contracts[_minter][address(_synthetic)];
        require(
            mn.minter != address(0),
            "Synthetic::liquidate: empty contract"
        );

        // if less than 1.25, will be liquidated
        require(
            mn.currentRatio < liquidationRatio,
            "Synthetic::liquidate: ratio is sastisfy"
        );
        uint256 exchangeRate = getRate(addressToPairs[address(_synthetic)]);
        require(
            mn.willLiquidateAtPrice < exchangeRate,
            "Synthetic::liquidate: asset price is sastisfy"
        );

        uint256 assetBackedAtRateAmount =
            getProductOf(mn.assetAmount, exchangeRate);

        uint256 remainingGapAmount;
        uint256 minterReceiveAmount;
        uint256 liquidatorReceiveAmount;
        uint256 platformReceiveAmount;

        if (mn.assetBackedAmount > assetBackedAtRateAmount) {
            // liquidator will receive the reward because liquidation ratio is more than 1.0 (and less than 1.25)
            remainingGapAmount = mn.assetBackedAmount - assetBackedAtRateAmount; // no need to check overflow
            minterReceiveAmount = getProductOf(
                remainingGapAmount,
                remainingToMinterRatio
            );

            liquidatorReceiveAmount = getProductOf(
                remainingGapAmount,
                liquidatorRewardRatio
            );

            platformReceiveAmount = getProductOf(
                remainingGapAmount,
                platfromFeeRatio
            );
        }
        // ELSE
        // Too late to liquidate, liquidator need to pay extra amount because
        // the current collateral value is less than minted synthetic value (collateral ratio < 1)
        // to close this contract, liquidator must pay off 100% of collateral value

        return (
            assetBackedAtRateAmount,
            remainingGapAmount,
            minterReceiveAmount,
            liquidatorReceiveAmount,
            platformReceiveAmount
        );
    }

    /**
     * @dev for pause this smart contract to prevent mint, redeem, add collateral, remove collateral, liquidate process.
     */
    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    /**
     * @dev for unpause this smart contract to prevent mint, redeem, add collateral, remove collateral, liquidate process.
     */
    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    /**
     * @dev get current rate of given asset by Oracle
     * @param _pairs the pairs of asset.
     */
    function getRate(string memory _pairs) public view returns (uint256) {
        require(isSupported(_pairs));
        IStdReference.ReferenceData memory data =
            bandOracle.getReferenceData(
                pairsToQuote[_pairs][0],
                pairsToQuote[_pairs][1]
            );
        return data.rate;
    }

    /**
     * @dev get liquidate price at current ratio
     * @param exchangeRate the current exchange rate
     * @param currentRatio the current ratio
     */
    function getWillLiquidateAtPrice(uint256 exchangeRate, uint256 currentRatio)
        internal
        view
        returns (uint256)
    {
        return
            (exchangeRate.mul(currentRatio.sub(liquidationRatio - denominator)))
                .div(denominator);
    }

    /**
     * @dev using for get supported asset before do the operation.
     * @param _pairs the string of pairs e.g. "TSLA/USD"
     */
    function isSupported(string memory _pairs) public view returns (bool) {
        return pairsToAddress[_pairs] != address(0);
    }

    /**
     * @dev using for get supported asset before do the operation.
     * @notice this function cal calculate multi purposes e.g.
     * 1. get assetBackedAtRateAmount
     * 2. get requiredAmount
     * 3. get assetToBeBurned
     * 4. get assetBackedToBeRedeemed
     * @param _amount amount of base
     * @param _multiplier amount of multiplier
     */
    function getProductOf(uint256 _amount, uint256 _multiplier)
        internal
        pure
        returns (uint256)
    {
        return (_amount.mul(_multiplier)).div(denominator);
    }

    /**
     * @dev this function cal calculate multi purposes e.g.
     * @notice this function cal calculate multi purposes e.g.
     * 1. get currentRatio: current ratio between collateral and minted synthetic asset
     * 2. get canMintRemainning: the maximum amount of asset that can be minted depends on current collateral ratio.
     * 3. get percent: the percent of redeeming (in partial redeeming function).
     * @param _amount amount of base
     * @param _divider amount of divider
     */
    function getRatioOf(uint256 _amount, uint256 _divider)
        internal
        pure
        returns (uint256)
    {
        return
            (((_amount.mul(denominator)).div(_divider)).mul(denominator)).div(
                denominator
            );
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

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

pragma solidity 0.6.12;

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

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
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
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance =
            token.allowance(address(this), spender).add(value);
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance =
            token.allowance(address(this), spender).sub(
                value,
                "SafeERC20: decreased allowance below zero"
            );
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
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

        bytes memory returndata =
            address(token).functionCall(
                data,
                "SafeERC20: low-level call failed"
            );
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

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
contract Ownable is Context {
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
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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

pragma solidity 0.6.12;

import "./Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
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
    constructor() internal {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

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

    constructor() internal {
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

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IStdReference {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string memory _base, string memory _quote)
        external
        view
        returns (ReferenceData memory);

    /// Similar to getReferenceData, but with multiple base/quote pairs at once.
    function getReferenceDataBulk(
        string[] memory _bases,
        string[] memory _quotes
    ) external view returns (ReferenceData[] memory);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

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
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
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
     *
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
     *
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
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
     *
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
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

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
        bytes32 accountHash =
            0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }
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
        require(
            address(this).balance >= amount,
            "Address: insufficient balance"
        );

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
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
    function functionCall(address target, bytes memory data)
        internal
        returns (bytes memory)
    {
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
        return _functionCallWithValue(target, data, 0, errorMessage);
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
        return
            functionCallWithValue(
                target,
                data,
                value,
                "Address: low-level call with value failed"
            );
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
        require(
            address(this).balance >= value,
            "Address: insufficient balance for call"
        );
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) =
            target.call{value: weiValue}(data);
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

pragma solidity 0.6.12;

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

