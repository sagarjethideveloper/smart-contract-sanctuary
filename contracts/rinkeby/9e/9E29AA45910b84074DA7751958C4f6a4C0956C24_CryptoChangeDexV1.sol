// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import './interfaces/ICryptoChangeDexV1.sol';
import './libraries/CryptoChangeV1Library.sol';
import './libraries/CryptoChangeV1PriceFeeds.sol';
import './libraries/CryptoChangeV1Validator.sol';
import './libraries/TransferHelper.sol';
import './libraries/Util.sol';
import '../price-feeds/PriceFeeds.sol';

contract CryptoChangeDexV1 is ICryptoChangeDexV1, PriceFeeds {
    /**
     * @dev The user can send Ether and get tokens in exchange.
     *
     * The ETH balance of the contract is auto-updated.
     */
    function swapExactEthForTokens(address[] calldata path) public payable returns (uint256[2] memory amounts) {
        PriceFeed[2] memory priceFeeds =
            CryptoChangeV1PriceFeeds.getPriceFeeds(
                ethPriceFeed,
                tokenPriceFeeds,
                path,
                Util.SwapType.ExactEthForTokens
            );
        amounts = CryptoChangeV1Library.getAmounts(0, Util.SwapType.ExactEthForTokens, priceFeeds);
        CryptoChangeV1Validator.validateSwapExactEthForTokens(amounts, path);

        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        TransferHelper.safeTransfer(path[0], msg.sender, amountOut);

        emit ExactEthForTokensSwapped(amountIn, amountOut);
    }

    /**
     * @dev The user swap tokens and get Ether in exchange.
     */
    function swapExactTokensForEth(uint256 amount, address[] calldata path) public returns (uint256[2] memory amounts) {
        PriceFeed[2] memory priceFeeds =
            CryptoChangeV1PriceFeeds.getPriceFeeds(
                ethPriceFeed,
                tokenPriceFeeds,
                path,
                Util.SwapType.ExactTokensForEth
            );
        amounts = CryptoChangeV1Library.getAmounts(amount, Util.SwapType.ExactTokensForEth, priceFeeds);
        CryptoChangeV1Validator.validateSwapExactTokensForEth(amounts, path);

        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(this), amountIn);
        TransferHelper.safeTransferEth(msg.sender, amountOut);

        emit ExactTokensForEthSwapped(amountIn, amountOut);
    }

    /**
     * @dev The user swaps a token for another.
     */
    function swapExactTokensForTokens(uint256 amount, address[] calldata path)
        public
        returns (uint256[2] memory amounts)
    {
        PriceFeed[2] memory priceFeeds =
            CryptoChangeV1PriceFeeds.getPriceFeeds(
                ethPriceFeed,
                tokenPriceFeeds,
                path,
                Util.SwapType.ExactTokensForTokens
            );
        amounts = CryptoChangeV1Library.getAmounts(amount, Util.SwapType.ExactTokensForTokens, priceFeeds);
        CryptoChangeV1Validator.validateSwapExactTokensForTokens(amounts, path);

        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(this), amountIn);
        TransferHelper.safeTransfer(path[1], msg.sender, amountOut);

        emit ExactTokensForTokensSwapped(msg.sender, amountIn, amountOut);
    }

    function depositETH() external payable {
        emit EthDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Any user can call this.
     */
    function isAdminAccount() public view returns (bool) {
        return admins[msg.sender] != 0 || owner() == msg.sender;
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

interface ICryptoChangeDexV1 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    event ExactEthForTokensSwapped(uint256 amountIn, uint256 amountOut);
    event ExactTokensForEthSwapped(uint256 amountIn, uint256 amountOut);
    event ExactTokensForTokensSwapped(address indexed from, uint256 amountIn, uint256 amountOut);

    event EthDeposited(address indexed from, uint256 amount);

    //    function token() external view returns (address);
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import './ABDKMathQuad.sol';
import './CryptoChangeV1PriceFeeds.sol';
import './Util.sol';

library CryptoChangeV1Library {
    /**
     * @dev Other internal validations would have been executed by now, and the priceFeeds will already be populated
     * accordingly, so this code does no further validations and just use the values for calculations.
     */
    function getAmounts(
        uint256 amount,
        Util.SwapType swapType,
        PriceFeed[2] memory priceFeeds
    ) internal returns (uint256[2] memory amounts) {
        int256[2] memory dollarPrices = CryptoChangeV1PriceFeeds.getDollarPrices(priceFeeds);

        if (swapType == Util.SwapType.ExactEthForTokens) {
            amounts[0] = msg.value;
        }
        if (swapType == Util.SwapType.ExactTokensForEth || swapType == Util.SwapType.ExactTokensForTokens) {
            amounts[0] = amount;
        }
        amounts[1] = ABDKMathQuad.toUInt(
            ABDKMathQuad.mul(
                ABDKMathQuad.div(ABDKMathQuad.fromInt(dollarPrices[0]), ABDKMathQuad.fromInt(dollarPrices[1])),
                ABDKMathQuad.fromUInt(amounts[0])
            )
        );
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './Util.sol';
import '../../price-feeds/PriceFeed.sol';

library CryptoChangeV1PriceFeeds {
    /**
     * @dev Retrieves and validates configured `Price Feeds`.
     *
     * Reverts the transaction if the `Price Feeds` are not configured.
     *
     * Returns the two `Price Feeds` configured in the order of the type of the swap, that is:
     *  - ExactEthForTokens:    [ethPriceFeed, tokenPriceFeed]
     *  - ExactTokensForEth:    [tokenPriceFeed, ethPriceFeed]
     *  - ExactTokensForTokens: [token0PriceFeed, token1PriceFeed]
     */
    function getPriceFeeds(
        PriceFeed memory ethPriceFeed,
        mapping(IERC20 => PriceFeed) storage tokenPriceFeeds,
        address[] memory path,
        Util.SwapType swapType
    ) internal view returns (PriceFeed[2] memory priceFeeds) {
        require(path.length > 0, 'CryptoChangeV1PriceFeeds: ONE_PATH_REQUIRED');
        if (swapType == Util.SwapType.ExactEthForTokens) {
            require(ethPriceFeed.configured, 'CryptoChangeV1PriceFeeds: ETH_PRICE_FEED_REQUIRED');
            require(tokenPriceFeeds[IERC20(path[0])].configured, 'CryptoChangeV1PriceFeeds: TOKEN_PRICE_FEED_REQUIRED');
            priceFeeds = [ethPriceFeed, tokenPriceFeeds[IERC20(path[0])]];
        }

        if (swapType == Util.SwapType.ExactTokensForEth) {
            require(tokenPriceFeeds[IERC20(path[0])].configured, 'CryptoChangeV1PriceFeeds: TOKEN_PRICE_FEED_REQUIRED');
            require(ethPriceFeed.configured, 'CryptoChangeV1PriceFeeds: ETH_PRICE_FEED_REQUIRED');
            priceFeeds = [tokenPriceFeeds[IERC20(path[0])], ethPriceFeed];
        }

        if (swapType == Util.SwapType.ExactTokensForTokens) {
            require(path.length == 2, 'CryptoChangeV1PriceFeeds: TWO_PATHS_REQUIRED');
            require(
                tokenPriceFeeds[IERC20(path[0])].configured,
                'CryptoChangeV1PriceFeeds: TOKEN0_PRICE_FEED_REQUIRED'
            );
            require(
                tokenPriceFeeds[IERC20(path[1])].configured,
                'CryptoChangeV1PriceFeeds: TOKEN1_PRICE_FEED_REQUIRED'
            );
            priceFeeds = [tokenPriceFeeds[IERC20(path[0])], tokenPriceFeeds[IERC20(path[1])]];
        }
        return priceFeeds;
    }

    function getDollarPrices(PriceFeed[2] memory priceFeeds) internal view returns (int256[2] memory dollarPrices) {
        (, int256 price1, , , ) = AggregatorV3Interface(priceFeeds[0].feed).latestRoundData();
        dollarPrices[0] = price1;

        (, int256 price2, , , ) = AggregatorV3Interface(priceFeeds[1].feed).latestRoundData();
        dollarPrices[1] = price2;
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

library CryptoChangeV1Validator {
    function validateSwapExactEthForTokens(uint256[2] memory amounts, address[] memory path) internal view {
        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        // Input amount must be specified
        require(amountIn > 0, 'CryptoChangeV1Validator: INPUT_ETHER_REQUIRED');
        // 1 token must be present in the path
        require(path.length == 1, 'CryptoChangeV1Validator: INVALID_PATH');

        uint256 dexBalanceForToken = IERC20(path[0]).balanceOf(address(this));
        require(amountOut <= dexBalanceForToken, 'CryptoChangeV1Validator: RESERVE_INSUFFICIENT_TOKEN');
    }

    function validateSwapExactTokensForEth(uint256[2] memory amounts, address[] memory path) internal view {
        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        // Input amount must be specified
        require(amountIn > 0, 'CryptoChangeV1Validator: INPUT_TOKENS_REQUIRED');
        // 1 token must be present in the path
        require(path.length == 1, 'CryptoChangeV1Validator: INVALID_PATH');

        uint256 allowance = IERC20(path[0]).allowance(msg.sender, address(this));
        // The CryptoChange DEX must be allowed to spend the user's tokens
        require(allowance >= amountIn, 'CryptoChangeV1Validator: CHECK_TOKEN_ALLOWANCE');

        // The CryptoChange DEX must have enough ETH in its reserves
        require(address(this).balance >= amountOut, 'CryptoChangeV1Validator: RESERVE_INSUFFICIENT_ETHER');
    }

    function validateSwapExactTokensForTokens(uint256[2] memory amounts, address[] memory path) internal view {
        uint256 amountIn = amounts[0];
        uint256 amountOut = amounts[1];

        // Input amount must be specified
        require(amountIn > 0, 'CryptoChangeV1Validator: INPUT_TOKENS_REQUIRED');
        // 2 tokens must be present in the path
        require(path.length == 2, 'CryptoChangeV1Validator: INVALID_PATH');

        address token0 = path[0];
        address token1 = path[1];

        uint256 allowance = IERC20(token0).allowance(msg.sender, address(this));
        // The CryptoChange DEX must be allowed to spend the user's tokens
        require(allowance >= amountIn, 'CryptoChangeV1Validator: CHECK_TOKEN0_ALLOWANCE');

        // The CryptoChange DEX must have enough token1 in its reserves
        require(
            IERC20(token1).balanceOf(address(this)) >= amountOut,
            'CryptoChangeV1Validator: RESERVE_INSUFFICIENT_TOKEN1'
        );
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0 <0.8.5;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        SafeERC20.safeApprove(IERC20(token), spender, value);
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        SafeERC20.safeTransfer(IERC20(token), to, value);
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        SafeERC20.safeTransferFrom(IERC20(token), from, to, value);
    }

    function safeTransferEth(address to, uint256 value) internal {
        (bool success, ) = to.call{ value: value }(new bytes(0));
        require(success, 'TransferHelper::safeTransferEth: ETH transfer failed');
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

library Util {
    enum SwapType { ExactEthForTokens, ExactTokensForEth, ExactTokensForTokens }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import './PriceFeed.sol';
import '../admin-keys/AdminKeys.sol';

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
abstract contract PriceFeeds is AdminKeys {
    event TokenPriceFeedAdded(address indexed from, address token, address priceFeed);
    event TokenPriceFeedRemoved(address indexed from, address token);
    event EthPriceFeedAdded(address indexed from, address priceFeed);
    event EthPriceFeedRemoved(address indexed from);

    mapping(IERC20 => PriceFeed) internal tokenPriceFeeds;
    PriceFeed internal ethPriceFeed;

    /**
     * @dev Only admin+ level users can call this.
     */
    function addTokenPriceFeed(address token, address priceFeed) public onlyAdminOrOwner validatePriceFeed(priceFeed) {
        tokenPriceFeeds[IERC20(token)] = PriceFeed(true, AggregatorV3Interface(priceFeed));

        emit TokenPriceFeedAdded(msg.sender, token, priceFeed);
    }

    /**
     * @dev Only admin+ level users can call this.
     */
    function removeTokenPriceFeed(address token) public onlyAdminOrOwner {
        tokenPriceFeeds[IERC20(token)] = PriceFeed(false, AggregatorV3Interface(address(0)));

        emit TokenPriceFeedRemoved(msg.sender, token);
    }

    /**
     * @dev Any user can call this.
     */
    function getTokenPriceFeed(address token) public view returns (address) {
        return address(tokenPriceFeeds[IERC20(token)].feed);
    }

    /**
     * @dev Only admin+ level users can call this.
     */
    function addEthPriceFeed(address priceFeed) public onlyAdminOrOwner validatePriceFeed(priceFeed) {
        ethPriceFeed = PriceFeed(true, AggregatorV3Interface(priceFeed));

        emit EthPriceFeedAdded(msg.sender, priceFeed);
    }

    /**
     * @dev Only admin+ level users can call this.
     */
    function removeEthPriceFeed() public onlyAdminOrOwner {
        ethPriceFeed = PriceFeed(false, AggregatorV3Interface(address(0)));

        emit EthPriceFeedRemoved(msg.sender);
    }

    /**
     * @dev Any user can call this.
     */
    function getEthPriceFeed() public view returns (address) {
        return address(ethPriceFeed.feed);
    }

    /**
     * Returns the latest round data for a Price Feed.
     *
     * Any user can call this.
     */
    function getPriceFeedLatestRoundData(address priceFeed)
        public
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return AggregatorV3Interface(priceFeed).latestRoundData();
    }

    ///////////////
    // Modifiers //
    ///////////////

    modifier validatePriceFeed(address priceFeed) {
        (, int256 price, , , ) = AggregatorV3Interface(priceFeed).latestRoundData();
        require(price > 0, 'PriceFeeds: PRICE_FEED_INVALID');
        _;
    }
}

// SPDX-License-Identifier: BSD-4-Clause
/*
 * ABDK Math Quad Smart Contract Library.  Copyright © 2019 by ABDK Consulting.
 * Author: Mikhail Vladimirov <[email protected]>
 */
pragma solidity ^0.8.0;

/**
 * Smart contract library of mathematical functions operating with IEEE 754
 * quadruple-precision binary floating-point numbers (quadruple precision
 * numbers).  As long as quadruple precision numbers are 16-bytes long, they are
 * represented by bytes16 type.
 */
library ABDKMathQuad {
    /*
     * 0.
     */
    bytes16 private constant POSITIVE_ZERO = 0x00000000000000000000000000000000;

    /*
     * -0.
     */
    bytes16 private constant NEGATIVE_ZERO = 0x80000000000000000000000000000000;

    /*
     * +Infinity.
     */
    bytes16 private constant POSITIVE_INFINITY = 0x7FFF0000000000000000000000000000;

    /*
     * -Infinity.
     */
    bytes16 private constant NEGATIVE_INFINITY = 0xFFFF0000000000000000000000000000;

    /*
     * Canonical NaN value.
     */
    bytes16 private constant NaN = 0x7FFF8000000000000000000000000000;

    /**
     * Convert signed 256-bit integer number into quadruple precision number.
     *
     * @param x signed 256-bit integer number
     * @return quadruple precision number
     */
    function fromInt(int256 x) internal pure returns (bytes16) {
        unchecked {
            if (x == 0) return bytes16(0);
            else {
                // We rely on overflow behavior here
                uint256 result = uint256(x > 0 ? x : -x);

                uint256 msb = mostSignificantBit(result);
                if (msb < 112) result <<= 112 - msb;
                else if (msb > 112) result >>= msb - 112;

                result = (result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | ((16383 + msb) << 112);
                if (x < 0) result |= 0x80000000000000000000000000000000;

                return bytes16(uint128(result));
            }
        }
    }

    /**
     * Convert quadruple precision number into signed 256-bit integer number
     * rounding towards zero.  Revert on overflow.
     *
     * @param x quadruple precision number
     * @return signed 256-bit integer number
     */
    function toInt(bytes16 x) internal pure returns (int256) {
        unchecked {
            uint256 exponent = (uint128(x) >> 112) & 0x7FFF;

            require(exponent <= 16638); // Overflow
            if (exponent < 16383) return 0; // Underflow

            uint256 result = (uint256(uint128(x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | 0x10000000000000000000000000000;

            if (exponent < 16495) result >>= 16495 - exponent;
            else if (exponent > 16495) result <<= exponent - 16495;

            if (uint128(x) >= 0x80000000000000000000000000000000) {
                // Negative
                require(result <= 0x8000000000000000000000000000000000000000000000000000000000000000);
                return -int256(result); // We rely on overflow behavior here
            } else {
                require(result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return int256(result);
            }
        }
    }

    /**
     * Convert unsigned 256-bit integer number into quadruple precision number.
     *
     * @param x unsigned 256-bit integer number
     * @return quadruple precision number
     */
    function fromUInt(uint256 x) internal pure returns (bytes16) {
        unchecked {
            if (x == 0) return bytes16(0);
            else {
                uint256 result = x;

                uint256 msb = mostSignificantBit(result);
                if (msb < 112) result <<= 112 - msb;
                else if (msb > 112) result >>= msb - 112;

                result = (result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | ((16383 + msb) << 112);

                return bytes16(uint128(result));
            }
        }
    }

    /**
     * Convert quadruple precision number into unsigned 256-bit integer number
     * rounding towards zero.  Revert on underflow.  Note, that negative floating
     * point numbers in range (-1.0 .. 0.0) may be converted to unsigned integer
     * without error, because they are rounded to zero.
     *
     * @param x quadruple precision number
     * @return unsigned 256-bit integer number
     */
    function toUInt(bytes16 x) internal pure returns (uint256) {
        unchecked {
            uint256 exponent = (uint128(x) >> 112) & 0x7FFF;

            if (exponent < 16383) return 0; // Underflow

            require(uint128(x) < 0x80000000000000000000000000000000); // Negative

            require(exponent <= 16638); // Overflow
            uint256 result = (uint256(uint128(x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | 0x10000000000000000000000000000;

            if (exponent < 16495) result >>= 16495 - exponent;
            else if (exponent > 16495) result <<= exponent - 16495;

            return result;
        }
    }

    /**
     * Convert signed 128.128 bit fixed point number into quadruple precision
     * number.
     *
     * @param x signed 128.128 bit fixed point number
     * @return quadruple precision number
     */
    function from128x128(int256 x) internal pure returns (bytes16) {
        unchecked {
            if (x == 0) return bytes16(0);
            else {
                // We rely on overflow behavior here
                uint256 result = uint256(x > 0 ? x : -x);

                uint256 msb = mostSignificantBit(result);
                if (msb < 112) result <<= 112 - msb;
                else if (msb > 112) result >>= msb - 112;

                result = (result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | ((16255 + msb) << 112);
                if (x < 0) result |= 0x80000000000000000000000000000000;

                return bytes16(uint128(result));
            }
        }
    }

    /**
     * Convert quadruple precision number into signed 128.128 bit fixed point
     * number.  Revert on overflow.
     *
     * @param x quadruple precision number
     * @return signed 128.128 bit fixed point number
     */
    function to128x128(bytes16 x) internal pure returns (int256) {
        unchecked {
            uint256 exponent = (uint128(x) >> 112) & 0x7FFF;

            require(exponent <= 16510); // Overflow
            if (exponent < 16255) return 0; // Underflow

            uint256 result = (uint256(uint128(x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | 0x10000000000000000000000000000;

            if (exponent < 16367) result >>= 16367 - exponent;
            else if (exponent > 16367) result <<= exponent - 16367;

            if (uint128(x) >= 0x80000000000000000000000000000000) {
                // Negative
                require(result <= 0x8000000000000000000000000000000000000000000000000000000000000000);
                return -int256(result); // We rely on overflow behavior here
            } else {
                require(result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return int256(result);
            }
        }
    }

    /**
     * Convert signed 64.64 bit fixed point number into quadruple precision
     * number.
     *
     * @param x signed 64.64 bit fixed point number
     * @return quadruple precision number
     */
    function from64x64(int128 x) internal pure returns (bytes16) {
        unchecked {
            if (x == 0) return bytes16(0);
            else {
                // We rely on overflow behavior here
                uint256 result = uint128(x > 0 ? x : -x);

                uint256 msb = mostSignificantBit(result);
                if (msb < 112) result <<= 112 - msb;
                else if (msb > 112) result >>= msb - 112;

                result = (result & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | ((16319 + msb) << 112);
                if (x < 0) result |= 0x80000000000000000000000000000000;

                return bytes16(uint128(result));
            }
        }
    }

    /**
     * Convert quadruple precision number into signed 64.64 bit fixed point
     * number.  Revert on overflow.
     *
     * @param x quadruple precision number
     * @return signed 64.64 bit fixed point number
     */
    function to64x64(bytes16 x) internal pure returns (int128) {
        unchecked {
            uint256 exponent = (uint128(x) >> 112) & 0x7FFF;

            require(exponent <= 16446); // Overflow
            if (exponent < 16319) return 0; // Underflow

            uint256 result = (uint256(uint128(x)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF) | 0x10000000000000000000000000000;

            if (exponent < 16431) result >>= 16431 - exponent;
            else if (exponent > 16431) result <<= exponent - 16431;

            if (uint128(x) >= 0x80000000000000000000000000000000) {
                // Negative
                require(result <= 0x80000000000000000000000000000000);
                return -int128(int256(result)); // We rely on overflow behavior here
            } else {
                require(result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
                return int128(int256(result));
            }
        }
    }

    /**
     * Convert octuple precision number into quadruple precision number.
     *
     * @param x octuple precision number
     * @return quadruple precision number
     */
    function fromOctuple(bytes32 x) internal pure returns (bytes16) {
        unchecked {
            bool negative = x & 0x8000000000000000000000000000000000000000000000000000000000000000 > 0;

            uint256 exponent = (uint256(x) >> 236) & 0x7FFFF;
            uint256 significand = uint256(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            if (exponent == 0x7FFFF) {
                if (significand > 0) return NaN;
                else return negative ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
            }

            if (exponent > 278526) return negative ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
            else if (exponent < 245649) return negative ? NEGATIVE_ZERO : POSITIVE_ZERO;
            else if (exponent < 245761) {
                significand =
                    (significand | 0x100000000000000000000000000000000000000000000000000000000000) >>
                    (245885 - exponent);
                exponent = 0;
            } else {
                significand >>= 124;
                exponent -= 245760;
            }

            uint128 result = uint128(significand | (exponent << 112));
            if (negative) result |= 0x80000000000000000000000000000000;

            return bytes16(result);
        }
    }

    /**
     * Convert quadruple precision number into octuple precision number.
     *
     * @param x quadruple precision number
     * @return octuple precision number
     */
    function toOctuple(bytes16 x) internal pure returns (bytes32) {
        unchecked {
            uint256 exponent = (uint128(x) >> 112) & 0x7FFF;

            uint256 result = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            if (exponent == 0x7FFF)
                exponent = 0x7FFFF; // Infinity or NaN
            else if (exponent == 0) {
                if (result > 0) {
                    uint256 msb = mostSignificantBit(result);
                    result = (result << (236 - msb)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                    exponent = 245649 + msb;
                }
            } else {
                result <<= 124;
                exponent += 245760;
            }

            result |= exponent << 236;
            if (uint128(x) >= 0x80000000000000000000000000000000)
                result |= 0x8000000000000000000000000000000000000000000000000000000000000000;

            return bytes32(result);
        }
    }

    /**
     * Convert double precision number into quadruple precision number.
     *
     * @param x double precision number
     * @return quadruple precision number
     */
    function fromDouble(bytes8 x) internal pure returns (bytes16) {
        unchecked {
            uint256 exponent = (uint64(x) >> 52) & 0x7FF;

            uint256 result = uint64(x) & 0xFFFFFFFFFFFFF;

            if (exponent == 0x7FF)
                exponent = 0x7FFF; // Infinity or NaN
            else if (exponent == 0) {
                if (result > 0) {
                    uint256 msb = mostSignificantBit(result);
                    result = (result << (112 - msb)) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                    exponent = 15309 + msb;
                }
            } else {
                result <<= 60;
                exponent += 15360;
            }

            result |= exponent << 112;
            if (x & 0x8000000000000000 > 0) result |= 0x80000000000000000000000000000000;

            return bytes16(uint128(result));
        }
    }

    /**
     * Convert quadruple precision number into double precision number.
     *
     * @param x quadruple precision number
     * @return double precision number
     */
    function toDouble(bytes16 x) internal pure returns (bytes8) {
        unchecked {
            bool negative = uint128(x) >= 0x80000000000000000000000000000000;

            uint256 exponent = (uint128(x) >> 112) & 0x7FFF;
            uint256 significand = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            if (exponent == 0x7FFF) {
                if (significand > 0) return 0x7FF8000000000000;
                // NaN
                else
                    return
                        negative
                            ? bytes8(0xFFF0000000000000) // -Infinity
                            : bytes8(0x7FF0000000000000); // Infinity
            }

            if (exponent > 17406)
                return
                    negative
                        ? bytes8(0xFFF0000000000000) // -Infinity
                        : bytes8(0x7FF0000000000000);
            // Infinity
            else if (exponent < 15309)
                return
                    negative
                        ? bytes8(0x8000000000000000) // -0
                        : bytes8(0x0000000000000000);
            // 0
            else if (exponent < 15361) {
                significand = (significand | 0x10000000000000000000000000000) >> (15421 - exponent);
                exponent = 0;
            } else {
                significand >>= 60;
                exponent -= 15360;
            }

            uint64 result = uint64(significand | (exponent << 52));
            if (negative) result |= 0x8000000000000000;

            return bytes8(result);
        }
    }

    /**
     * Test whether given quadruple precision number is NaN.
     *
     * @param x quadruple precision number
     * @return true if x is NaN, false otherwise
     */
    function isNaN(bytes16 x) internal pure returns (bool) {
        unchecked {
            return uint128(x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF > 0x7FFF0000000000000000000000000000;
        }
    }

    /**
     * Test whether given quadruple precision number is positive or negative
     * infinity.
     *
     * @param x quadruple precision number
     * @return true if x is positive or negative infinity, false otherwise
     */
    function isInfinity(bytes16 x) internal pure returns (bool) {
        unchecked {
            return uint128(x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0x7FFF0000000000000000000000000000;
        }
    }

    /**
     * Calculate sign of x, i.e. -1 if x is negative, 0 if x if zero, and 1 if x
     * is positive.  Note that sign (-0) is zero.  Revert if x is NaN.
     *
     * @param x quadruple precision number
     * @return sign of x
     */
    function sign(bytes16 x) internal pure returns (int8) {
        unchecked {
            uint128 absoluteX = uint128(x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            require(absoluteX <= 0x7FFF0000000000000000000000000000); // Not NaN

            if (absoluteX == 0) return 0;
            else if (uint128(x) >= 0x80000000000000000000000000000000) return -1;
            else return 1;
        }
    }

    /**
     * Calculate sign (x - y).  Revert if either argument is NaN, or both
     * arguments are infinities of the same sign.
     *
     * @param x quadruple precision number
     * @param y quadruple precision number
     * @return sign (x - y)
     */
    function cmp(bytes16 x, bytes16 y) internal pure returns (int8) {
        unchecked {
            uint128 absoluteX = uint128(x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            require(absoluteX <= 0x7FFF0000000000000000000000000000); // Not NaN

            uint128 absoluteY = uint128(y) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            require(absoluteY <= 0x7FFF0000000000000000000000000000); // Not NaN

            // Not infinities of the same sign
            require(x != y || absoluteX < 0x7FFF0000000000000000000000000000);

            if (x == y) return 0;
            else {
                bool negativeX = uint128(x) >= 0x80000000000000000000000000000000;
                bool negativeY = uint128(y) >= 0x80000000000000000000000000000000;

                if (negativeX) {
                    if (negativeY) return absoluteX > absoluteY ? -1 : int8(1);
                    else return -1;
                } else {
                    if (negativeY) return 1;
                    else return absoluteX > absoluteY ? int8(1) : -1;
                }
            }
        }
    }

    /**
     * Test whether x equals y.  NaN, infinity, and -infinity are not equal to
     * anything.
     *
     * @param x quadruple precision number
     * @param y quadruple precision number
     * @return true if x equals to y, false otherwise
     */
    function eq(bytes16 x, bytes16 y) internal pure returns (bool) {
        unchecked {
            if (x == y) {
                return uint128(x) & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF < 0x7FFF0000000000000000000000000000;
            } else return false;
        }
    }

    /**
     * Calculate x + y.  Special values behave in the following way:
     *
     * NaN + x = NaN for any x.
     * Infinity + x = Infinity for any finite x.
     * -Infinity + x = -Infinity for any finite x.
     * Infinity + Infinity = Infinity.
     * -Infinity + -Infinity = -Infinity.
     * Infinity + -Infinity = -Infinity + Infinity = NaN.
     *
     * @param x quadruple precision number
     * @param y quadruple precision number
     * @return quadruple precision number
     */
    function add(bytes16 x, bytes16 y) internal pure returns (bytes16) {
        unchecked {
            uint256 xExponent = (uint128(x) >> 112) & 0x7FFF;
            uint256 yExponent = (uint128(y) >> 112) & 0x7FFF;

            if (xExponent == 0x7FFF) {
                if (yExponent == 0x7FFF) {
                    if (x == y) return x;
                    else return NaN;
                } else return x;
            } else if (yExponent == 0x7FFF) return y;
            else {
                bool xSign = uint128(x) >= 0x80000000000000000000000000000000;
                uint256 xSignifier = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (xExponent == 0) xExponent = 1;
                else xSignifier |= 0x10000000000000000000000000000;

                bool ySign = uint128(y) >= 0x80000000000000000000000000000000;
                uint256 ySignifier = uint128(y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (yExponent == 0) yExponent = 1;
                else ySignifier |= 0x10000000000000000000000000000;

                if (xSignifier == 0) return y == NEGATIVE_ZERO ? POSITIVE_ZERO : y;
                else if (ySignifier == 0) return x == NEGATIVE_ZERO ? POSITIVE_ZERO : x;
                else {
                    int256 delta = int256(xExponent) - int256(yExponent);

                    if (xSign == ySign) {
                        if (delta > 112) return x;
                        else if (delta > 0) ySignifier >>= uint256(delta);
                        else if (delta < -112) return y;
                        else if (delta < 0) {
                            xSignifier >>= uint256(-delta);
                            xExponent = yExponent;
                        }

                        xSignifier += ySignifier;

                        if (xSignifier >= 0x20000000000000000000000000000) {
                            xSignifier >>= 1;
                            xExponent += 1;
                        }

                        if (xExponent == 0x7FFF) return xSign ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
                        else {
                            if (xSignifier < 0x10000000000000000000000000000) xExponent = 0;
                            else xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

                            return
                                bytes16(
                                    uint128(
                                        (xSign ? 0x80000000000000000000000000000000 : 0) |
                                            (xExponent << 112) |
                                            xSignifier
                                    )
                                );
                        }
                    } else {
                        if (delta > 0) {
                            xSignifier <<= 1;
                            xExponent -= 1;
                        } else if (delta < 0) {
                            ySignifier <<= 1;
                            xExponent = yExponent - 1;
                        }

                        if (delta > 112) ySignifier = 1;
                        else if (delta > 1) ySignifier = ((ySignifier - 1) >> uint256(delta - 1)) + 1;
                        else if (delta < -112) xSignifier = 1;
                        else if (delta < -1) xSignifier = ((xSignifier - 1) >> uint256(-delta - 1)) + 1;

                        if (xSignifier >= ySignifier) xSignifier -= ySignifier;
                        else {
                            xSignifier = ySignifier - xSignifier;
                            xSign = ySign;
                        }

                        if (xSignifier == 0) return POSITIVE_ZERO;

                        uint256 msb = mostSignificantBit(xSignifier);

                        if (msb == 113) {
                            xSignifier = (xSignifier >> 1) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                            xExponent += 1;
                        } else if (msb < 112) {
                            uint256 shift = 112 - msb;
                            if (xExponent > shift) {
                                xSignifier = (xSignifier << shift) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                                xExponent -= shift;
                            } else {
                                xSignifier <<= xExponent - 1;
                                xExponent = 0;
                            }
                        } else xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

                        if (xExponent == 0x7FFF) return xSign ? NEGATIVE_INFINITY : POSITIVE_INFINITY;
                        else
                            return
                                bytes16(
                                    uint128(
                                        (xSign ? 0x80000000000000000000000000000000 : 0) |
                                            (xExponent << 112) |
                                            xSignifier
                                    )
                                );
                    }
                }
            }
        }
    }

    /**
     * Calculate x - y.  Special values behave in the following way:
     *
     * NaN - x = NaN for any x.
     * Infinity - x = Infinity for any finite x.
     * -Infinity - x = -Infinity for any finite x.
     * Infinity - -Infinity = Infinity.
     * -Infinity - Infinity = -Infinity.
     * Infinity - Infinity = -Infinity - -Infinity = NaN.
     *
     * @param x quadruple precision number
     * @param y quadruple precision number
     * @return quadruple precision number
     */
    function sub(bytes16 x, bytes16 y) internal pure returns (bytes16) {
        unchecked {
            return add(x, y ^ 0x80000000000000000000000000000000);
        }
    }

    /**
     * Calculate x * y.  Special values behave in the following way:
     *
     * NaN * x = NaN for any x.
     * Infinity * x = Infinity for any finite positive x.
     * Infinity * x = -Infinity for any finite negative x.
     * -Infinity * x = -Infinity for any finite positive x.
     * -Infinity * x = Infinity for any finite negative x.
     * Infinity * 0 = NaN.
     * -Infinity * 0 = NaN.
     * Infinity * Infinity = Infinity.
     * Infinity * -Infinity = -Infinity.
     * -Infinity * Infinity = -Infinity.
     * -Infinity * -Infinity = Infinity.
     *
     * @param x quadruple precision number
     * @param y quadruple precision number
     * @return quadruple precision number
     */
    function mul(bytes16 x, bytes16 y) internal pure returns (bytes16) {
        unchecked {
            uint256 xExponent = (uint128(x) >> 112) & 0x7FFF;
            uint256 yExponent = (uint128(y) >> 112) & 0x7FFF;

            if (xExponent == 0x7FFF) {
                if (yExponent == 0x7FFF) {
                    if (x == y) return x ^ (y & 0x80000000000000000000000000000000);
                    else if (x ^ y == 0x80000000000000000000000000000000) return x | y;
                    else return NaN;
                } else {
                    if (y & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) return NaN;
                    else return x ^ (y & 0x80000000000000000000000000000000);
                }
            } else if (yExponent == 0x7FFF) {
                if (x & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) return NaN;
                else return y ^ (x & 0x80000000000000000000000000000000);
            } else {
                uint256 xSignifier = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (xExponent == 0) xExponent = 1;
                else xSignifier |= 0x10000000000000000000000000000;

                uint256 ySignifier = uint128(y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (yExponent == 0) yExponent = 1;
                else ySignifier |= 0x10000000000000000000000000000;

                xSignifier *= ySignifier;
                if (xSignifier == 0)
                    return (x ^ y) & 0x80000000000000000000000000000000 > 0 ? NEGATIVE_ZERO : POSITIVE_ZERO;

                xExponent += yExponent;

                uint256 msb =
                    xSignifier >= 0x200000000000000000000000000000000000000000000000000000000
                        ? 225
                        : xSignifier >= 0x100000000000000000000000000000000000000000000000000000000
                        ? 224
                        : mostSignificantBit(xSignifier);

                if (xExponent + msb < 16496) {
                    // Underflow
                    xExponent = 0;
                    xSignifier = 0;
                } else if (xExponent + msb < 16608) {
                    // Subnormal
                    if (xExponent < 16496) xSignifier >>= 16496 - xExponent;
                    else if (xExponent > 16496) xSignifier <<= xExponent - 16496;
                    xExponent = 0;
                } else if (xExponent + msb > 49373) {
                    xExponent = 0x7FFF;
                    xSignifier = 0;
                } else {
                    if (msb > 112) xSignifier >>= msb - 112;
                    else if (msb < 112) xSignifier <<= 112 - msb;

                    xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

                    xExponent = xExponent + msb - 16607;
                }

                return
                    bytes16(
                        uint128(uint128((x ^ y) & 0x80000000000000000000000000000000) | (xExponent << 112) | xSignifier)
                    );
            }
        }
    }

    /**
     * Calculate x / y.  Special values behave in the following way:
     *
     * NaN / x = NaN for any x.
     * x / NaN = NaN for any x.
     * Infinity / x = Infinity for any finite non-negative x.
     * Infinity / x = -Infinity for any finite negative x including -0.
     * -Infinity / x = -Infinity for any finite non-negative x.
     * -Infinity / x = Infinity for any finite negative x including -0.
     * x / Infinity = 0 for any finite non-negative x.
     * x / -Infinity = -0 for any finite non-negative x.
     * x / Infinity = -0 for any finite non-negative x including -0.
     * x / -Infinity = 0 for any finite non-negative x including -0.
     *
     * Infinity / Infinity = NaN.
     * Infinity / -Infinity = -NaN.
     * -Infinity / Infinity = -NaN.
     * -Infinity / -Infinity = NaN.
     *
     * Division by zero behaves in the following way:
     *
     * x / 0 = Infinity for any finite positive x.
     * x / -0 = -Infinity for any finite positive x.
     * x / 0 = -Infinity for any finite negative x.
     * x / -0 = Infinity for any finite negative x.
     * 0 / 0 = NaN.
     * 0 / -0 = NaN.
     * -0 / 0 = NaN.
     * -0 / -0 = NaN.
     *
     * @param x quadruple precision number
     * @param y quadruple precision number
     * @return quadruple precision number
     */
    function div(bytes16 x, bytes16 y) internal pure returns (bytes16) {
        unchecked {
            uint256 xExponent = (uint128(x) >> 112) & 0x7FFF;
            uint256 yExponent = (uint128(y) >> 112) & 0x7FFF;

            if (xExponent == 0x7FFF) {
                if (yExponent == 0x7FFF) return NaN;
                else return x ^ (y & 0x80000000000000000000000000000000);
            } else if (yExponent == 0x7FFF) {
                if (y & 0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFF != 0) return NaN;
                else return POSITIVE_ZERO | ((x ^ y) & 0x80000000000000000000000000000000);
            } else if (y & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) {
                if (x & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0) return NaN;
                else return POSITIVE_INFINITY | ((x ^ y) & 0x80000000000000000000000000000000);
            } else {
                uint256 ySignifier = uint128(y) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (yExponent == 0) yExponent = 1;
                else ySignifier |= 0x10000000000000000000000000000;

                uint256 xSignifier = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (xExponent == 0) {
                    if (xSignifier != 0) {
                        uint256 shift = 226 - mostSignificantBit(xSignifier);

                        xSignifier <<= shift;

                        xExponent = 1;
                        yExponent += shift - 114;
                    }
                } else {
                    xSignifier = (xSignifier | 0x10000000000000000000000000000) << 114;
                }

                xSignifier = xSignifier / ySignifier;
                if (xSignifier == 0)
                    return (x ^ y) & 0x80000000000000000000000000000000 > 0 ? NEGATIVE_ZERO : POSITIVE_ZERO;

                assert(xSignifier >= 0x1000000000000000000000000000);

                uint256 msb =
                    xSignifier >= 0x80000000000000000000000000000
                        ? mostSignificantBit(xSignifier)
                        : xSignifier >= 0x40000000000000000000000000000
                        ? 114
                        : xSignifier >= 0x20000000000000000000000000000
                        ? 113
                        : 112;

                if (xExponent + msb > yExponent + 16497) {
                    // Overflow
                    xExponent = 0x7FFF;
                    xSignifier = 0;
                } else if (xExponent + msb + 16380 < yExponent) {
                    // Underflow
                    xExponent = 0;
                    xSignifier = 0;
                } else if (xExponent + msb + 16268 < yExponent) {
                    // Subnormal
                    if (xExponent + 16380 > yExponent) xSignifier <<= xExponent + 16380 - yExponent;
                    else if (xExponent + 16380 < yExponent) xSignifier >>= yExponent - xExponent - 16380;

                    xExponent = 0;
                } else {
                    // Normal
                    if (msb > 112) xSignifier >>= msb - 112;

                    xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

                    xExponent = xExponent + msb + 16269 - yExponent;
                }

                return
                    bytes16(
                        uint128(uint128((x ^ y) & 0x80000000000000000000000000000000) | (xExponent << 112) | xSignifier)
                    );
            }
        }
    }

    /**
     * Calculate -x.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function neg(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            return x ^ 0x80000000000000000000000000000000;
        }
    }

    /**
     * Calculate |x|.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function abs(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            return x & 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        }
    }

    /**
     * Calculate square root of x.  Return NaN on negative x excluding -0.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function sqrt(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            if (uint128(x) > 0x80000000000000000000000000000000) return NaN;
            else {
                uint256 xExponent = (uint128(x) >> 112) & 0x7FFF;
                if (xExponent == 0x7FFF) return x;
                else {
                    uint256 xSignifier = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                    if (xExponent == 0) xExponent = 1;
                    else xSignifier |= 0x10000000000000000000000000000;

                    if (xSignifier == 0) return POSITIVE_ZERO;

                    bool oddExponent = xExponent & 0x1 == 0;
                    xExponent = (xExponent + 16383) >> 1;

                    if (oddExponent) {
                        if (xSignifier >= 0x10000000000000000000000000000) xSignifier <<= 113;
                        else {
                            uint256 msb = mostSignificantBit(xSignifier);
                            uint256 shift = (226 - msb) & 0xFE;
                            xSignifier <<= shift;
                            xExponent -= (shift - 112) >> 1;
                        }
                    } else {
                        if (xSignifier >= 0x10000000000000000000000000000) xSignifier <<= 112;
                        else {
                            uint256 msb = mostSignificantBit(xSignifier);
                            uint256 shift = (225 - msb) & 0xFE;
                            xSignifier <<= shift;
                            xExponent -= (shift - 112) >> 1;
                        }
                    }

                    uint256 r = 0x10000000000000000000000000000;
                    r = (r + xSignifier / r) >> 1;
                    r = (r + xSignifier / r) >> 1;
                    r = (r + xSignifier / r) >> 1;
                    r = (r + xSignifier / r) >> 1;
                    r = (r + xSignifier / r) >> 1;
                    r = (r + xSignifier / r) >> 1;
                    r = (r + xSignifier / r) >> 1; // Seven iterations should be enough
                    uint256 r1 = xSignifier / r;
                    if (r1 < r) r = r1;

                    return bytes16(uint128((xExponent << 112) | (r & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)));
                }
            }
        }
    }

    /**
     * Calculate binary logarithm of x.  Return NaN on negative x excluding -0.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function log_2(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            if (uint128(x) > 0x80000000000000000000000000000000) return NaN;
            else if (x == 0x3FFF0000000000000000000000000000) return POSITIVE_ZERO;
            else {
                uint256 xExponent = (uint128(x) >> 112) & 0x7FFF;
                if (xExponent == 0x7FFF) return x;
                else {
                    uint256 xSignifier = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                    if (xExponent == 0) xExponent = 1;
                    else xSignifier |= 0x10000000000000000000000000000;

                    if (xSignifier == 0) return NEGATIVE_INFINITY;

                    bool resultNegative;
                    uint256 resultExponent = 16495;
                    uint256 resultSignifier;

                    if (xExponent >= 0x3FFF) {
                        resultNegative = false;
                        resultSignifier = xExponent - 0x3FFF;
                        xSignifier <<= 15;
                    } else {
                        resultNegative = true;
                        if (xSignifier >= 0x10000000000000000000000000000) {
                            resultSignifier = 0x3FFE - xExponent;
                            xSignifier <<= 15;
                        } else {
                            uint256 msb = mostSignificantBit(xSignifier);
                            resultSignifier = 16493 - msb;
                            xSignifier <<= 127 - msb;
                        }
                    }

                    if (xSignifier == 0x80000000000000000000000000000000) {
                        if (resultNegative) resultSignifier += 1;
                        uint256 shift = 112 - mostSignificantBit(resultSignifier);
                        resultSignifier <<= shift;
                        resultExponent -= shift;
                    } else {
                        uint256 bb = resultNegative ? 1 : 0;
                        while (resultSignifier < 0x10000000000000000000000000000) {
                            resultSignifier <<= 1;
                            resultExponent -= 1;

                            xSignifier *= xSignifier;
                            uint256 b = xSignifier >> 255;
                            resultSignifier += b ^ bb;
                            xSignifier >>= 127 + b;
                        }
                    }

                    return
                        bytes16(
                            uint128(
                                (resultNegative ? 0x80000000000000000000000000000000 : 0) |
                                    (resultExponent << 112) |
                                    (resultSignifier & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                            )
                        );
                }
            }
        }
    }

    /**
     * Calculate natural logarithm of x.  Return NaN on negative x excluding -0.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function ln(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            return mul(log_2(x), 0x3FFE62E42FEFA39EF35793C7673007E5);
        }
    }

    /**
     * Calculate 2^x.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function pow_2(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            bool xNegative = uint128(x) > 0x80000000000000000000000000000000;
            uint256 xExponent = (uint128(x) >> 112) & 0x7FFF;
            uint256 xSignifier = uint128(x) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

            if (xExponent == 0x7FFF && xSignifier != 0) return NaN;
            else if (xExponent > 16397) return xNegative ? POSITIVE_ZERO : POSITIVE_INFINITY;
            else if (xExponent < 16255) return 0x3FFF0000000000000000000000000000;
            else {
                if (xExponent == 0) xExponent = 1;
                else xSignifier |= 0x10000000000000000000000000000;

                if (xExponent > 16367) xSignifier <<= xExponent - 16367;
                else if (xExponent < 16367) xSignifier >>= 16367 - xExponent;

                if (xNegative && xSignifier > 0x406E00000000000000000000000000000000) return POSITIVE_ZERO;

                if (!xNegative && xSignifier > 0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) return POSITIVE_INFINITY;

                uint256 resultExponent = xSignifier >> 128;
                xSignifier &= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                if (xNegative && xSignifier != 0) {
                    xSignifier = ~xSignifier;
                    resultExponent += 1;
                }

                uint256 resultSignifier = 0x80000000000000000000000000000000;
                if (xSignifier & 0x80000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x16A09E667F3BCC908B2FB1366EA957D3E) >> 128;
                if (xSignifier & 0x40000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1306FE0A31B7152DE8D5A46305C85EDEC) >> 128;
                if (xSignifier & 0x20000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1172B83C7D517ADCDF7C8C50EB14A791F) >> 128;
                if (xSignifier & 0x10000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10B5586CF9890F6298B92B71842A98363) >> 128;
                if (xSignifier & 0x8000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1059B0D31585743AE7C548EB68CA417FD) >> 128;
                if (xSignifier & 0x4000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x102C9A3E778060EE6F7CACA4F7A29BDE8) >> 128;
                if (xSignifier & 0x2000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10163DA9FB33356D84A66AE336DCDFA3F) >> 128;
                if (xSignifier & 0x1000000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100B1AFA5ABCBED6129AB13EC11DC9543) >> 128;
                if (xSignifier & 0x800000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10058C86DA1C09EA1FF19D294CF2F679B) >> 128;
                if (xSignifier & 0x400000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1002C605E2E8CEC506D21BFC89A23A00F) >> 128;
                if (xSignifier & 0x200000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100162F3904051FA128BCA9C55C31E5DF) >> 128;
                if (xSignifier & 0x100000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000B175EFFDC76BA38E31671CA939725) >> 128;
                if (xSignifier & 0x80000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100058BA01FB9F96D6CACD4B180917C3D) >> 128;
                if (xSignifier & 0x40000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10002C5CC37DA9491D0985C348C68E7B3) >> 128;
                if (xSignifier & 0x20000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000162E525EE054754457D5995292026) >> 128;
                if (xSignifier & 0x10000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000B17255775C040618BF4A4ADE83FC) >> 128;
                if (xSignifier & 0x8000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB) >> 128;
                if (xSignifier & 0x4000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9) >> 128;
                if (xSignifier & 0x2000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000162E43F4F831060E02D839A9D16D) >> 128;
                if (xSignifier & 0x1000000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000B1721BCFC99D9F890EA06911763) >> 128;
                if (xSignifier & 0x800000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000058B90CF1E6D97F9CA14DBCC1628) >> 128;
                if (xSignifier & 0x400000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000002C5C863B73F016468F6BAC5CA2B) >> 128;
                if (xSignifier & 0x200000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000162E430E5A18F6119E3C02282A5) >> 128;
                if (xSignifier & 0x100000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000B1721835514B86E6D96EFD1BFE) >> 128;
                if (xSignifier & 0x80000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000058B90C0B48C6BE5DF846C5B2EF) >> 128;
                if (xSignifier & 0x40000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000002C5C8601CC6B9E94213C72737A) >> 128;
                if (xSignifier & 0x20000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000162E42FFF037DF38AA2B219F06) >> 128;
                if (xSignifier & 0x10000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000B17217FBA9C739AA5819F44F9) >> 128;
                if (xSignifier & 0x8000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000058B90BFCDEE5ACD3C1CEDC823) >> 128;
                if (xSignifier & 0x4000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000002C5C85FE31F35A6A30DA1BE50) >> 128;
                if (xSignifier & 0x2000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000162E42FF0999CE3541B9FFFCF) >> 128;
                if (xSignifier & 0x1000000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000B17217F80F4EF5AADDA45554) >> 128;
                if (xSignifier & 0x800000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000058B90BFBF8479BD5A81B51AD) >> 128;
                if (xSignifier & 0x400000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000002C5C85FDF84BD62AE30A74CC) >> 128;
                if (xSignifier & 0x200000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000162E42FEFB2FED257559BDAA) >> 128;
                if (xSignifier & 0x100000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000B17217F7D5A7716BBA4A9AE) >> 128;
                if (xSignifier & 0x80000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000058B90BFBE9DDBAC5E109CCE) >> 128;
                if (xSignifier & 0x40000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000002C5C85FDF4B15DE6F17EB0D) >> 128;
                if (xSignifier & 0x20000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000162E42FEFA494F1478FDE05) >> 128;
                if (xSignifier & 0x10000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000B17217F7D20CF927C8E94C) >> 128;
                if (xSignifier & 0x8000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000058B90BFBE8F71CB4E4B33D) >> 128;
                if (xSignifier & 0x4000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000002C5C85FDF477B662B26945) >> 128;
                if (xSignifier & 0x2000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000162E42FEFA3AE53369388C) >> 128;
                if (xSignifier & 0x1000000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000B17217F7D1D351A389D40) >> 128;
                if (xSignifier & 0x800000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000058B90BFBE8E8B2D3D4EDE) >> 128;
                if (xSignifier & 0x400000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000002C5C85FDF4741BEA6E77E) >> 128;
                if (xSignifier & 0x200000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000162E42FEFA39FE95583C2) >> 128;
                if (xSignifier & 0x100000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000B17217F7D1CFB72B45E1) >> 128;
                if (xSignifier & 0x80000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000058B90BFBE8E7CC35C3F0) >> 128;
                if (xSignifier & 0x40000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000002C5C85FDF473E242EA38) >> 128;
                if (xSignifier & 0x20000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000162E42FEFA39F02B772C) >> 128;
                if (xSignifier & 0x10000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000B17217F7D1CF7D83C1A) >> 128;
                if (xSignifier & 0x8000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000058B90BFBE8E7BDCBE2E) >> 128;
                if (xSignifier & 0x4000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000002C5C85FDF473DEA871F) >> 128;
                if (xSignifier & 0x2000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000162E42FEFA39EF44D91) >> 128;
                if (xSignifier & 0x1000000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000B17217F7D1CF79E949) >> 128;
                if (xSignifier & 0x800000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000058B90BFBE8E7BCE544) >> 128;
                if (xSignifier & 0x400000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000002C5C85FDF473DE6ECA) >> 128;
                if (xSignifier & 0x200000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000162E42FEFA39EF366F) >> 128;
                if (xSignifier & 0x100000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000B17217F7D1CF79AFA) >> 128;
                if (xSignifier & 0x80000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000058B90BFBE8E7BCD6D) >> 128;
                if (xSignifier & 0x40000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000002C5C85FDF473DE6B2) >> 128;
                if (xSignifier & 0x20000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000162E42FEFA39EF358) >> 128;
                if (xSignifier & 0x10000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000B17217F7D1CF79AB) >> 128;
                if (xSignifier & 0x8000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000058B90BFBE8E7BCD5) >> 128;
                if (xSignifier & 0x4000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000002C5C85FDF473DE6A) >> 128;
                if (xSignifier & 0x2000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000162E42FEFA39EF34) >> 128;
                if (xSignifier & 0x1000000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000B17217F7D1CF799) >> 128;
                if (xSignifier & 0x800000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000058B90BFBE8E7BCC) >> 128;
                if (xSignifier & 0x400000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000002C5C85FDF473DE5) >> 128;
                if (xSignifier & 0x200000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000162E42FEFA39EF2) >> 128;
                if (xSignifier & 0x100000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000B17217F7D1CF78) >> 128;
                if (xSignifier & 0x80000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000058B90BFBE8E7BB) >> 128;
                if (xSignifier & 0x40000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000002C5C85FDF473DD) >> 128;
                if (xSignifier & 0x20000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000162E42FEFA39EE) >> 128;
                if (xSignifier & 0x10000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000B17217F7D1CF6) >> 128;
                if (xSignifier & 0x8000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000058B90BFBE8E7A) >> 128;
                if (xSignifier & 0x4000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000002C5C85FDF473C) >> 128;
                if (xSignifier & 0x2000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000162E42FEFA39D) >> 128;
                if (xSignifier & 0x1000000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000B17217F7D1CE) >> 128;
                if (xSignifier & 0x800000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000058B90BFBE8E6) >> 128;
                if (xSignifier & 0x400000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000002C5C85FDF472) >> 128;
                if (xSignifier & 0x200000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000162E42FEFA38) >> 128;
                if (xSignifier & 0x100000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000B17217F7D1B) >> 128;
                if (xSignifier & 0x80000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000058B90BFBE8D) >> 128;
                if (xSignifier & 0x40000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000002C5C85FDF46) >> 128;
                if (xSignifier & 0x20000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000162E42FEFA2) >> 128;
                if (xSignifier & 0x10000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000B17217F7D0) >> 128;
                if (xSignifier & 0x8000000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000058B90BFBE7) >> 128;
                if (xSignifier & 0x4000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000002C5C85FDF3) >> 128;
                if (xSignifier & 0x2000000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000162E42FEF9) >> 128;
                if (xSignifier & 0x1000000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000B17217F7C) >> 128;
                if (xSignifier & 0x800000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000058B90BFBD) >> 128;
                if (xSignifier & 0x400000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000002C5C85FDE) >> 128;
                if (xSignifier & 0x200000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000162E42FEE) >> 128;
                if (xSignifier & 0x100000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000B17217F6) >> 128;
                if (xSignifier & 0x80000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000058B90BFA) >> 128;
                if (xSignifier & 0x40000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000002C5C85FC) >> 128;
                if (xSignifier & 0x20000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000162E42FD) >> 128;
                if (xSignifier & 0x10000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000B17217E) >> 128;
                if (xSignifier & 0x8000000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000058B90BE) >> 128;
                if (xSignifier & 0x4000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000002C5C85E) >> 128;
                if (xSignifier & 0x2000000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000162E42E) >> 128;
                if (xSignifier & 0x1000000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000B17216) >> 128;
                if (xSignifier & 0x800000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000058B90A) >> 128;
                if (xSignifier & 0x400000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000002C5C84) >> 128;
                if (xSignifier & 0x200000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000162E41) >> 128;
                if (xSignifier & 0x100000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000000B1720) >> 128;
                if (xSignifier & 0x80000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000058B8F) >> 128;
                if (xSignifier & 0x40000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000002C5C7) >> 128;
                if (xSignifier & 0x20000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000000162E3) >> 128;
                if (xSignifier & 0x10000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000000B171) >> 128;
                if (xSignifier & 0x8000 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000000058B8) >> 128;
                if (xSignifier & 0x4000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000002C5B) >> 128;
                if (xSignifier & 0x2000 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000000162D) >> 128;
                if (xSignifier & 0x1000 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000000B16) >> 128;
                if (xSignifier & 0x800 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000000058A) >> 128;
                if (xSignifier & 0x400 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000000002C4) >> 128;
                if (xSignifier & 0x200 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000000161) >> 128;
                if (xSignifier & 0x100 > 0)
                    resultSignifier = (resultSignifier * 0x1000000000000000000000000000000B0) >> 128;
                if (xSignifier & 0x80 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000000057) >> 128;
                if (xSignifier & 0x40 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000000002B) >> 128;
                if (xSignifier & 0x20 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000000015) >> 128;
                if (xSignifier & 0x10 > 0)
                    resultSignifier = (resultSignifier * 0x10000000000000000000000000000000A) >> 128;
                if (xSignifier & 0x8 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000000004) >> 128;
                if (xSignifier & 0x4 > 0)
                    resultSignifier = (resultSignifier * 0x100000000000000000000000000000001) >> 128;

                if (!xNegative) {
                    resultSignifier = (resultSignifier >> 15) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                    resultExponent += 0x3FFF;
                } else if (resultExponent <= 0x3FFE) {
                    resultSignifier = (resultSignifier >> 15) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                    resultExponent = 0x3FFF - resultExponent;
                } else {
                    resultSignifier = resultSignifier >> (resultExponent - 16367);
                    resultExponent = 0;
                }

                return bytes16(uint128((resultExponent << 112) | resultSignifier));
            }
        }
    }

    /**
     * Calculate e^x.
     *
     * @param x quadruple precision number
     * @return quadruple precision number
     */
    function exp(bytes16 x) internal pure returns (bytes16) {
        unchecked {
            return pow_2(mul(x, 0x3FFF71547652B82FE1777D0FFDA0D23A));
        }
    }

    /**
     * Get index of the most significant non-zero bit in binary representation of
     * x.  Reverts if x is zero.
     *
     * @return index of the most significant non-zero bit in binary representation
     *         of x
     */
    function mostSignificantBit(uint256 x) private pure returns (uint256) {
        unchecked {
            require(x > 0);

            uint256 result = 0;

            if (x >= 0x100000000000000000000000000000000) {
                x >>= 128;
                result += 128;
            }
            if (x >= 0x10000000000000000) {
                x >>= 64;
                result += 64;
            }
            if (x >= 0x100000000) {
                x >>= 32;
                result += 32;
            }
            if (x >= 0x10000) {
                x >>= 16;
                result += 16;
            }
            if (x >= 0x100) {
                x >>= 8;
                result += 8;
            }
            if (x >= 0x10) {
                x >>= 4;
                result += 4;
            }
            if (x >= 0x4) {
                x >>= 2;
                result += 2;
            }
            if (x >= 0x2) result += 1; // No need to shift x anymore

            return result;
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

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

struct PriceFeed {
    bool configured;
    AggregatorV3Interface feed;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface AggregatorV3Interface {

  function decimals()
    external
    view
    returns (
      uint8
    );

  function description()
    external
    view
    returns (
      string memory
    );

  function version()
    external
    view
    returns (
      uint256
    );

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(
    uint80 _roundId
  )
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

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.8.5;

import '@openzeppelin/contracts/access/Ownable.sol';

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
abstract contract AdminKeys is Ownable {
    event AdminKeyAdded(address indexed from, address addressAdded);
    event AdminKeyRemoved(address indexed from, address addressRemoved);

    mapping(address => uint256) internal admins;

    /**
     * @dev Only admin+ level users can call this.
     */
    function isAdminKey(address addy) public view onlyAdminOrOwner returns (bool) {
        return admins[addy] != 0;
    }

    /**
     * @dev Only admin+ level users can call this.
     */
    function addAdminKey(address addy) public onlyAdminOrOwner {
        require(addy != owner(), 'AdminKeys: OWNER_IS_ADMIN_BY_DEFAULT');
        admins[addy] = 1;

        emit AdminKeyAdded(msg.sender, addy);
    }

    /**
     * @dev Only admin+ level users can call this.
     */
    function removeAdminKey(address addy) public onlyAdminOrOwner {
        require(addy != owner(), 'AdminKeys: OWNER_NOT_ALLOWED');
        admins[addy] = 0;

        emit AdminKeyRemoved(msg.sender, addy);
    }

    modifier onlyAdminOrOwner() {
        require(
            owner() == _msgSender() || admins[_msgSender()] != 0, //
            'AdminKeys: CALLER_NOT_OWNER_NOR_ADMIN'
        );
        _;
    }
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

