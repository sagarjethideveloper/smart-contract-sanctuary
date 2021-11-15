//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {BasePriceOracle} from "./BasePriceOracle.sol";
import {AggregatorV3Interface} from "../../interfaces/chainlink/AggregatorV3Interface.sol";
import "../../interfaces/uniswapV2/IUniswapV2ERC20.sol";
import "../../interfaces/uniswapV2/IUniswapV2Pair.sol";

/**
 * @title On-chain Price Oracle (Chainlink and Uniswap V2 (or equivalent))
 * @notice this computes the TVL (in USD) of FLURRY or rhoToken
 * for a specific intermediate currency.
 * WARNING - this reads the immediate price from the trading pair and is subject to flash loan attack
 * only use this as an indicative price, DO NOT use the price for any trading decisions
 * @dev this oracle is generic enough to handle different Uniswap pair order
 */
contract ChainlinkUniswapV2IndirectPrice is BasePriceOracle {
    uint8 public constant override decimals = 18;
    string public override description;

    // This price oracle assumes the price is computed in the order:
    // combined price = chainlink * base / intermediate
    //                = (intermediate / USD) * base / intermediate
    // Example:
    // (1) Chainlink: USDT / USD, (2) Uniswap: USDT / rhoUSDT
    //  => rhoUSDT / USD for USDT by (1)/(2)

    // Chainlink aggregator
    AggregatorV3Interface public aggregator; // intermediate / USD, for example "USDT / USD"
    uint8 private chainlinkDecimals;

    // Uniswap V2 token pair
    IUniswapV2Pair public uniswapV2Pair; // for example, "USDT / FLURRY"
    IUniswapV2ERC20 public baseToken;
    IUniswapV2ERC20 public intermediateToken;

    // oracle params
    bool public baseIsToken0;
    uint8 private baseDecimals;
    string public intermediateSymbol;
    address public intermediateAddr;
    uint8 private intermediateDecimals;

    function initialize(
        address aggregatorAddr,
        address uniswapV2PairAddr,
        address _baseAddr,
        address usdAddr
    ) public initializer {
        require(aggregatorAddr != address(0), "Chainlink aggregator address is 0");
        require(uniswapV2PairAddr != address(0), "Uniswap V2 pair address is 0");
        require(_baseAddr != address(0), "_baseAddr is 0");
        require(usdAddr != address(0), "usdAddr is 0");

        // Chainlink
        aggregator = AggregatorV3Interface(aggregatorAddr);
        chainlinkDecimals = aggregator.decimals();

        // Uniswap V2
        uniswapV2Pair = IUniswapV2Pair(uniswapV2PairAddr);
        address token0Addr = uniswapV2Pair.token0();
        address token1Addr = uniswapV2Pair.token1();
        require(token0Addr != address(0), "token0 address is 0");
        require(token1Addr != address(0), "token1 address is 0");

        // our setup
        require(_baseAddr == token0Addr || _baseAddr == token1Addr, "base address not in Uniswap V2 pair");
        // base currency
        baseAddr = _baseAddr;
        baseToken = IUniswapV2ERC20(baseAddr);
        baseSymbol = baseToken.symbol();
        baseDecimals = baseToken.decimals();
        // quote currency
        quoteSymbol = "USD";
        quoteAddr = usdAddr;
        // intermediate currency
        baseIsToken0 = baseAddr == token0Addr;
        intermediateAddr = baseIsToken0 ? token1Addr : token0Addr;
        intermediateToken = IUniswapV2ERC20(intermediateAddr);
        intermediateSymbol = intermediateToken.symbol();
        intermediateDecimals = intermediateToken.decimals();
        description = string(abi.encodePacked(baseSymbol, " / ", quoteSymbol));
    }

    function lastUpdate() external view override returns (uint256 updateAt) {
        (, , , uint256 chainlinkTime, ) = aggregator.latestRoundData();
        (, , uint32 blockTimestampLast) = uniswapV2Pair.getReserves();
        uint256 uniswapV2Time = uint256(blockTimestampLast);
        updateAt = chainlinkTime > uniswapV2Time ? chainlinkTime : uniswapV2Time; // use more recent `updateAt`
    }

    function priceInternal() internal view returns (uint256) {
        // Chainlink
        (, int256 answer, , , ) = aggregator.latestRoundData();
        if (answer <= 0) return type(uint256).max; // non-positive price feed is invalid
        // Uniswap V2
        (uint112 reserve0, uint112 reserve1, ) = uniswapV2Pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return type(uint256).max; // zero reserve is invalid
        uint256 baseReserve = baseIsToken0 ? uint256(reserve0) : uint256(reserve1);
        uint256 intermediateReserve = baseIsToken0 ? uint256(reserve1) : uint256(reserve0);
        // combined price = chainlink * base / intermediate
        //                = (intermediate / USD) * base / intermediate
        return
            (10**(decimals + baseDecimals) * uint256(answer) * intermediateReserve) /
            (10**(chainlinkDecimals + intermediateDecimals) * baseReserve);
    }

    function price(address _baseAddr) external view override isValidSymbol(_baseAddr) returns (uint256) {
        uint256 priceFeed = priceInternal();
        if (priceFeed == type(uint256).max) return priceFeed;
        if (baseAddr == _baseAddr) return priceFeed;
        return 1e36 / priceFeed;
    }

    function priceByQuoteSymbol(address _quoteAddr) external view override isValidSymbol(_quoteAddr) returns (uint256) {
        uint256 priceFeed = priceInternal();
        if (priceFeed == type(uint256).max) return priceFeed;
        if (quoteAddr == _quoteAddr) return priceFeed;
        return 1e36 / priceFeed;
    }

    /**
     * @return true if both reserves are positive, false otherwise
     * NOTE: this is to avoid multiplication and division by 0
     */
    function isValidUniswapReserve() external view returns (bool) {
        (uint112 reserve0, uint112 reserve1, ) = uniswapV2Pair.getReserves();
        return reserve0 > 0 && reserve1 > 0;
    }
}

//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title BasePriceOracle Abstract Contract
 * @notice Abstract Contract to implement variables and modifiers in common
 */
abstract contract BasePriceOracle is IPriceOracle, Initializable {
    string public override baseSymbol;
    string public override quoteSymbol;
    address public override baseAddr;
    address public override quoteAddr;

    function setSymbols(
        string memory _baseSymbol,
        string memory _quoteSymbol,
        address _baseAddr,
        address _quoteAddr
    ) internal {
        baseSymbol = _baseSymbol;
        quoteSymbol = _quoteSymbol;
        baseAddr = _baseAddr;
        quoteAddr = _quoteAddr;
    }

    modifier isValidSymbol(address addr) {
        require(addr == baseAddr || addr == quoteAddr, "Symbol not in this price oracle");
        _;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

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

//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IUniswapV2ERC20 {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IUniswapV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IPriceOracle {
    /**
     * @return decimals of the "baseSymbol / quoteSymbol" rate
     */
    function decimals() external view returns (uint8);

    /**
     * @return name of the token pair, in the form of "baseSymbol / quoteSymbol"
     */
    function description() external view returns (string memory);

    /**
     * @return name of the base symbol
     */
    function baseSymbol() external view returns (string memory);

    /**
     * @return name of the quote symbol
     */
    function quoteSymbol() external view returns (string memory);

    /**
     * @return address of the base symbol, zero address if `baseSymbol` is USD
     */
    function baseAddr() external view returns (address);

    /**
     * @return address of the quote symbol, zero address if `baseSymbol` is USD
     */
    function quoteAddr() external view returns (address);

    /**
     * @return updateAt timestamp of the last update as seconds since unix epoch
     */
    function lastUpdate() external view returns (uint256 updateAt);

    /**
     * @param _baseAddr address of the base symbol
     * @return the price feed in `decimals`, or type(uint256).max if the rate is invalid
     * Example: priceFeed() == 2e18
     *          => 1 baseSymbol = 2 quoteSymbol
     */
    function price(address _baseAddr) external view returns (uint256);

    /**
     * @param _quoteAddr address of the quote symbol
     * @return the price feed in `decimals`, or type(uint256).max if the rate is invalid
     */
    function priceByQuoteSymbol(address _quoteAddr) external view returns (uint256);
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

