pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUniswapExchange.sol";
import "./interfaces/IUniswapFactory.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./interfaces/ICurveFi.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IPermanentStorage.sol";

contract AMMQuoter {
    using SafeMath for uint256;
    /* Constants */
    string public constant version = "5.2.0";
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant ZERO_ADDRESS = address(0);
    address public constant UNISWAP_V2_ROUTER_02_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER_ADDRESS = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public immutable weth;
    IPermanentStorage public immutable permStorage;

    struct GroupedVars {
        address makerAddr;
        address takerAssetAddr;
        address makerAssetAddr;
        uint256 takerAssetAmount;
        uint256 makerAssetAmount;
        address[] path;
    }

    event CurveTokenAdded(
        address indexed makerAddress,
        address indexed assetAddress,
        int128 index
    );

    constructor (IPermanentStorage _permStorage, address _weth) public {
        permStorage = _permStorage;
        weth = _weth;
    }

    function isETH(address assetAddress) public pure returns (bool) {
        return (assetAddress == ZERO_ADDRESS || assetAddress == ETH_ADDRESS);
    }

    function getMakerOutAmountWithPath(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount,
        address[] calldata _path
    )
        public
        view
        returns (uint256 makerAssetAmount)
    {
        GroupedVars memory vars;
        vars.makerAddr = _makerAddr;
        vars.takerAssetAddr = _takerAssetAddr;
        vars.makerAssetAddr = _makerAssetAddr;
        vars.takerAssetAmount = _takerAssetAmount;
        vars.path = _path;
        if (vars.makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS ||
            vars.makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            IUniswapRouterV2 router = IUniswapRouterV2(vars.makerAddr);
            uint256[] memory amounts = router.getAmountsOut(vars.takerAssetAmount, vars.path);
            makerAssetAmount = amounts[amounts.length-1];
        } else {
            address curveTakerIntenalAsset = isETH(vars.takerAssetAddr) ? ETH_ADDRESS : vars.takerAssetAddr;
            address curveMakerIntenalAsset = isETH(vars.makerAssetAddr) ? ETH_ADDRESS : vars.makerAssetAddr;
            (int128 fromTokenCurveIndex, int128 toTokenCurveIndex, uint16 swapMethod,) = permStorage.getCurvePoolInfo(vars.makerAddr, curveTakerIntenalAsset, curveMakerIntenalAsset);
            if (fromTokenCurveIndex > 0 && toTokenCurveIndex > 0) {
                require(swapMethod != 0, "AMMQuoter: swap method not registered");
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                fromTokenCurveIndex = fromTokenCurveIndex - 1;
                toTokenCurveIndex = toTokenCurveIndex - 1;
                ICurveFi curve = ICurveFi(vars.makerAddr);
                if (swapMethod == 1) {
                    makerAssetAmount = curve.get_dy(fromTokenCurveIndex, toTokenCurveIndex, vars.takerAssetAmount).sub(1);
                } else if (swapMethod == 2) {
                    makerAssetAmount = curve.get_dy_underlying(fromTokenCurveIndex, toTokenCurveIndex, vars.takerAssetAmount).sub(1);
                }
            } else {
                revert("AMMQuoter: Unsupported makerAddr");
            }
        }
        return makerAssetAmount;
    }

    function getMakerOutAmount(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount
    )
        public
        view
        returns (uint256)
    {
        uint256 makerAssetAmount;
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS ||
            _makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
            address[] memory path = new address[](2);
            if (isETH(_takerAssetAddr)) {
                path[0] = weth;
                path[1] = _makerAssetAddr;
            } else if (isETH(_makerAssetAddr)) {
                path[0] = _takerAssetAddr;
                path[1] = weth;
            } else {
                path[0] = _takerAssetAddr;
                path[1] = _makerAssetAddr;
            }
            uint256[] memory amounts = router.getAmountsOut(_takerAssetAmount, path);
            makerAssetAmount = amounts[1];
        } else {
            address curveTakerIntenalAsset = isETH(_takerAssetAddr) ? ETH_ADDRESS : _takerAssetAddr;
            address curveMakerIntenalAsset = isETH(_makerAssetAddr) ? ETH_ADDRESS : _makerAssetAddr;
            (int128 fromTokenCurveIndex, int128 toTokenCurveIndex, uint16 swapMethod,) = permStorage.getCurvePoolInfo(_makerAddr, curveTakerIntenalAsset, curveMakerIntenalAsset);
            if (fromTokenCurveIndex > 0 && toTokenCurveIndex > 0) {
                require(swapMethod != 0, "AMMQuoter: swap method not registered");
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                fromTokenCurveIndex = fromTokenCurveIndex - 1;
                toTokenCurveIndex = toTokenCurveIndex - 1;
                ICurveFi curve = ICurveFi(_makerAddr);
                if (swapMethod == 1) {
                    makerAssetAmount = curve.get_dy(fromTokenCurveIndex, toTokenCurveIndex, _takerAssetAmount).sub(1);
                } else if (swapMethod == 2) {
                    makerAssetAmount = curve.get_dy_underlying(fromTokenCurveIndex, toTokenCurveIndex, _takerAssetAmount).sub(1);
                }
            } else {
                revert("AMMQuoter: Unsupported makerAddr");
            }
        }
        return makerAssetAmount;
    }

    function getBestOutAmount(
        address[] calldata _makerAddresses,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount
    )
        external
        view
        returns (address bestMaker, uint256 bestAmount)
    {
        bestAmount = 0;
        uint256 poolLength = _makerAddresses.length;
        for (uint256 i = 0; i < poolLength; i++) {
            address makerAddress = _makerAddresses[i];
            uint256 makerAssetAmount = getMakerOutAmount(makerAddress, _takerAssetAddr, _makerAssetAddr, _takerAssetAmount);
            if (makerAssetAmount > bestAmount) {
                bestAmount = makerAssetAmount;
                bestMaker = makerAddress;
            }
        }
        return (bestMaker, bestAmount);
    }

    function getTakerInAmountWithPath(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _makerAssetAmount,
        address[] calldata _path
    )
        public
        view
        returns (uint256 takerAssetAmount)
    {
        GroupedVars memory vars;
        vars.makerAddr = _makerAddr;
        vars.takerAssetAddr = _takerAssetAddr;
        vars.makerAssetAddr = _makerAssetAddr;
        vars.makerAssetAmount = _makerAssetAmount;
        vars.path = _path;
        if (vars.makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS ||
            vars.makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            IUniswapRouterV2 router = IUniswapRouterV2(vars.makerAddr);
            uint256[] memory amounts = router.getAmountsIn(vars.makerAssetAmount, _path);
            takerAssetAmount = amounts[0];
        } else {
            address curveTakerIntenalAsset = isETH(vars.takerAssetAddr) ? ETH_ADDRESS : vars.takerAssetAddr;
            address curveMakerIntenalAsset = isETH(vars.makerAssetAddr) ? ETH_ADDRESS : vars.makerAssetAddr;
            (int128 fromTokenCurveIndex, int128 toTokenCurveIndex, uint16 swapMethod, bool supportGetDx) = permStorage.getCurvePoolInfo(vars.makerAddr, curveTakerIntenalAsset, curveMakerIntenalAsset);
            if (fromTokenCurveIndex > 0 && toTokenCurveIndex > 0) {
                require(swapMethod != 0, "AMMQuoter: swap method not registered");
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                fromTokenCurveIndex = fromTokenCurveIndex - 1;
                toTokenCurveIndex = toTokenCurveIndex - 1;
                ICurveFi curve = ICurveFi(vars.makerAddr);
                if (supportGetDx) {
                    if (swapMethod == 1) {
                        takerAssetAmount = curve.get_dx(fromTokenCurveIndex, toTokenCurveIndex, vars.makerAssetAmount);
                    } else if (swapMethod == 2) {
                        takerAssetAmount = curve.get_dx_underlying(fromTokenCurveIndex, toTokenCurveIndex, vars.makerAssetAmount);
                    }
                } else {
                    if (swapMethod == 1) {
                        // does not support get_dx_underlying, try to get an estimated rate here
                        takerAssetAmount = curve.get_dy(toTokenCurveIndex, fromTokenCurveIndex, vars.makerAssetAmount);
                    } else if (swapMethod == 2) {
                        takerAssetAmount = curve.get_dy_underlying(toTokenCurveIndex, fromTokenCurveIndex, vars.makerAssetAmount);
                    }
                }
            } else {
                revert("AMMQuoter: Unsupported makerAddr");
            }
        }
        return takerAssetAmount;
    }

    function getTakerInAmount(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _makerAssetAmount
    )
        public
        view
        returns (uint256)
    {
        uint256 takerAssetAmount;
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS ||
            _makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
            address[] memory path = new address[](2);
            if (isETH(_takerAssetAddr)) {
                path[0] = weth;
                path[1] = _makerAssetAddr;
            } else if (isETH(_makerAssetAddr)) {
                path[0] = _takerAssetAddr;
                path[1] = weth;
            } else {
                path[0] = _takerAssetAddr;
                path[1] = _makerAssetAddr;
            }
            uint256[] memory amounts = router.getAmountsIn(_makerAssetAmount, path);
            takerAssetAmount = amounts[0];
        } else {
            address curveTakerIntenalAsset = isETH(_takerAssetAddr) ? ETH_ADDRESS : _takerAssetAddr;
            address curveMakerIntenalAsset = isETH(_makerAssetAddr) ? ETH_ADDRESS : _makerAssetAddr;
            (int128 fromTokenCurveIndex, int128 toTokenCurveIndex, uint16 swapMethod, bool supportGetDx) = permStorage.getCurvePoolInfo(_makerAddr, curveTakerIntenalAsset, curveMakerIntenalAsset);
            if (fromTokenCurveIndex > 0 && toTokenCurveIndex > 0) {
                require(swapMethod != 0, "AMMQuoter: swap method not registered");
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                fromTokenCurveIndex = fromTokenCurveIndex - 1;
                toTokenCurveIndex = toTokenCurveIndex - 1;
                ICurveFi curve = ICurveFi(_makerAddr);
                if (supportGetDx) {
                    if (swapMethod == 1) {
                        takerAssetAmount = curve.get_dx(fromTokenCurveIndex, toTokenCurveIndex, _makerAssetAmount);
                    } else if (swapMethod == 2) {
                        takerAssetAmount = curve.get_dx_underlying(fromTokenCurveIndex, toTokenCurveIndex, _makerAssetAmount);
                    }
                } else {
                    if (swapMethod == 1) {
                        // does not support get_dx_underlying, try to get an estimated rate here
                        takerAssetAmount = curve.get_dy(toTokenCurveIndex, fromTokenCurveIndex, _makerAssetAmount);
                    } else if (swapMethod == 2) {
                        takerAssetAmount = curve.get_dy_underlying(toTokenCurveIndex, fromTokenCurveIndex, _makerAssetAmount);
                    }
                }
            } else {
                revert("AMMQuoter: Unsupported makerAddr");
            }
        }
        return takerAssetAmount;
    }

    function getBestInAmount(
        address[] calldata _makerAddresses,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _makerAssetAmount
    )
        external
        view
        returns (address bestMaker, uint256 bestAmount)
    {
        bestAmount = 2**256 - 1;
        uint256 poolLength = _makerAddresses.length;
        for (uint256 i = 0; i < poolLength; i++) {
            address makerAddress = _makerAddresses[i];
            uint256 takerAssetAmount = getTakerInAmount(makerAddress, _takerAssetAddr, _makerAssetAddr, _makerAssetAmount);
            if (takerAssetAmount < bestAmount) {
                bestAmount = takerAssetAmount;
                bestMaker = makerAddress;
            }
        }
        return (bestMaker, bestAmount);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

pragma solidity >=0.5.0 <0.8.0;

interface IUniswapExchange {
    // Address of ERC20 token sold on this exchange
    function tokenAddress() external view returns (address token);
    // Address of Uniswap Factory
    function factoryAddress() external view returns (address factory);
    // Provide Liquidity
    function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline) external payable returns (uint256);
    function removeLiquidity(uint256 amount, uint256 min_eth, uint256 min_tokens, uint256 deadline) external returns (uint256, uint256);
    // Get Prices
    function getEthToTokenInputPrice(uint256 eth_sold) external view returns (uint256 tokens_bought);
    function getEthToTokenOutputPrice(uint256 tokens_bought) external view returns (uint256 eth_sold);
    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256 eth_bought);
    function getTokenToEthOutputPrice(uint256 eth_bought) external view returns (uint256 tokens_sold);
    // Trade ETH to ERC20
    function ethToTokenSwapInput(uint256 min_tokens, uint256 deadline) external payable returns (uint256 tokens_bought);
    function ethToTokenTransferInput(uint256 min_tokens, uint256 deadline, address recipient) external payable returns (uint256  tokens_bought);
    function ethToTokenSwapOutput(uint256 tokens_bought, uint256 deadline) external payable returns (uint256  eth_sold);
    function ethToTokenTransferOutput(uint256 tokens_bought, uint256 deadline, address recipient) external payable returns (uint256  eth_sold);
    // Trade ERC20 to ETH
    function tokenToEthSwapInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline) external returns (uint256  eth_bought);
    function tokenToEthTransferInput(uint256 tokens_sold, uint256 min_eth, uint256 deadline, address recipient) external returns (uint256  eth_bought);
    function tokenToEthSwapOutput(uint256 eth_bought, uint256 max_tokens, uint256 deadline) external returns (uint256  tokens_sold);
    function tokenToEthTransferOutput(uint256 eth_bought, uint256 max_tokens, uint256 deadline, address recipient) external returns (uint256  tokens_sold);
    // Trade ERC20 to ERC20
    function tokenToTokenSwapInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address token_addr) external returns (uint256  tokens_bought);
    function tokenToTokenTransferInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address recipient, address token_addr) external returns (uint256  tokens_bought);
    function tokenToTokenSwapOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address token_addr) external returns (uint256  tokens_sold);
    function tokenToTokenTransferOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address recipient, address token_addr) external returns (uint256  tokens_sold);
    // Trade ERC20 to Custom Pool
    function tokenToExchangeSwapInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address exchange_addr) external returns (uint256  tokens_bought);
    function tokenToExchangeTransferInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address recipient, address exchange_addr) external returns (uint256  tokens_bought);
    function tokenToExchangeSwapOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address exchange_addr) external returns (uint256  tokens_sold);
    function tokenToExchangeTransferOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address recipient, address exchange_addr) external returns (uint256  tokens_sold);
    // ERC20 comaptibility for liquidity tokens
    function name() external view returns (bytes32);
    function symbol() external view returns (bytes32);
    function decimals() external view returns (uint256);
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
    function allowance(address _owner, address _spender) external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    // Never use
    function setup(address token_addr) external;
}

pragma solidity >=0.5.0 <0.8.0;

interface IUniswapFactory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    // Create Exchange
    function createExchange(address token) external returns (address exchange);
    // Get Exchange and Token Info
    function getExchange(address token) external view returns (address exchange);
    function getToken(address exchange) external view returns (address token);
    function getTokenWithId(uint256 tokenId) external view returns (address token);
    // Never use
    function initializeFactory(address template) external;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

interface IUniswapRouterV2 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

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

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

pragma solidity >=0.5.0 <0.8.0;

interface ICurveFi {
    function get_virtual_price() external returns (uint256 out);
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 deadline
    ) external;

    function add_liquidity(
        // sBTC pool
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
        // bUSD pool
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function get_dx(
        int128 i,
        int128 j,
        uint256 dy
    ) external view returns (uint256 out);

    function get_dx_underlying(
        int128 i,
        int128 j,
        uint256 dy
    ) external view returns (uint256 out);

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256 out);

    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256 out);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable;

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy,
        uint256 deadline
    ) external payable;

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable;

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy,
        uint256 deadline
    ) external payable;

    function remove_liquidity(
        uint256 _amount,
        uint256 deadline,
        uint256[2] calldata min_amounts
    ) external;

    function remove_liquidity_imbalance(
        uint256[2] calldata amounts,
        uint256 deadline
    ) external;

    function remove_liquidity_imbalance(
        uint256[3] calldata amounts,
        uint256 max_burn_amount
    ) external;

    function remove_liquidity(uint256 _amount, uint256[3] calldata amounts)
        external;

    function remove_liquidity_imbalance(
        uint256[4] calldata amounts,
        uint256 max_burn_amount
    ) external;

    function remove_liquidity(uint256 _amount, uint256[4] calldata amounts)
        external;

    function commit_new_parameters(
        int128 amplification,
        int128 new_fee,
        int128 new_admin_fee
    ) external;

    function apply_new_parameters() external;

    function revert_new_parameters() external;

    function commit_transfer_ownership(address _owner) external;

    function apply_transfer_ownership() external;

    function revert_transfer_ownership() external;

    function withdraw_admin_fees() external;

    function coins(int128 arg0) external returns (address out);

    function underlying_coins(int128 arg0) external returns (address out);

    function balances(int128 arg0) external returns (uint256 out);

    function A() external returns (int128 out);

    function fee() external returns (int128 out);

    function admin_fee() external returns (int128 out);

    function owner() external returns (address out);

    function admin_actions_deadline() external returns (uint256 out);

    function transfer_ownership_deadline() external returns (uint256 out);

    function future_A() external returns (int128 out);

    function future_fee() external returns (int128 out);

    function future_admin_fee() external returns (int128 out);

    function future_owner() external returns (address out);
}

pragma solidity ^0.6.0;

interface IWETH {
    function balanceOf(address account) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transferFrom(address src, address dst, uint wad) external returns (bool);
}

pragma solidity ^0.6.0;

interface IPermanentStorage {
    function wethAddr() external view returns (address);
    function getCurvePoolInfo(address _makerAddr, address _takerAssetAddr, address _makerAssetAddr) external view returns (int128 takerAssetIndex, int128 makerAssetIndex, uint16 swapMethod, bool supportGetDx);
    function setCurvePoolInfo(address _makerAddr, address[] calldata _underlyingCoins, address[] calldata _coins, bool _supportGetDx) external;
    function isTransactionSeen(bytes32 _transactionHash) external view returns (bool);  // Kept for backward compatability. Should be removed from AMM 5.2.1 upward
    function isAMMTransactionSeen(bytes32 _transactionHash) external view returns (bool);
    function isRFQTransactionSeen(bytes32 _transactionHash) external view returns (bool);
    function isRelayerValid(address _relayer) external view returns (bool);
    function setTransactionSeen(bytes32 _transactionHash) external;  // Kept for backward compatability. Should be removed from AMM 5.2.1 upward
    function setAMMTransactionSeen(bytes32 _transactionHash) external;
    function setRFQTransactionSeen(bytes32 _transactionHash) external;
    function setRelayersValid(address[] memory _relayers, bool[] memory _isValids) external;
}

