pragma solidity =0.6.6;


interface IBiswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeApprove: approve failed'
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }
}
interface IBiswapRouter02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapFeeReward() external pure returns (address);

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
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint swapFee) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint swapFee) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

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
interface IBiswapPair {
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
    function swapFee() external view returns (uint32);
    function devFee() external view returns (uint32);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external returns(uint amount0In,uint amount1In);
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
    function setSwapFee(uint32) external;
    function setDevFee(uint32) external;
}


library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
}

library BiswapLibrary {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'BiswapLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'BiswapLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'60e6aace37aefb611ef723e170ee15cf5649505cdb66f8006012810225bf73b7' // init code hash
            ))));
    }

    function getSwapFee(address factory, address tokenA, address tokenB) internal view returns (uint swapFee) {
        swapFee = IBiswapPair(pairFor(factory, tokenA, tokenB)).swapFee();
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IBiswapPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'BiswapLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'BiswapLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint swapFee) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'BiswapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'BiswapLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(uint(1000).sub(swapFee));
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint swapFee) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'BiswapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'BiswapLibrary: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(uint(1000).sub(swapFee));
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'BiswapLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, getSwapFee(factory, path[i], path[i + 1]));
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'BiswapLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, getSwapFee(factory, path[i - 1], path[i]));
        }
    }
    
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
library Babylonian {
    // credit for this implementation goes to
    // https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        // this block is equivalent to r = uint256(1) << (BitMath.mostSignificantBit(x) / 2);
        // however that code costs significantly more gas
        uint256 xx = x;
        uint256 r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }
}
library FullMath {
    function fullMul(uint256 x, uint256 y) internal pure returns (uint256 l, uint256 h) {
        uint256 mm = mulmod(x, y, uint256(-1));
        l = x * y;
        h = mm - l;
        if (mm < l) h -= 1;
    }

    function fullDiv(
        uint256 l,
        uint256 h,
        uint256 d
    ) private pure returns (uint256) {
        uint256 pow2 = d & -d;
        d /= pow2;
        l /= pow2;
        l += h * ((-pow2) / pow2 + 1);
        uint256 r = 1;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        return l * r;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        (uint256 l, uint256 h) = fullMul(x, y);

        uint256 mm = mulmod(x, y, d);
        if (mm > l) h -= 1;
        l -= mm;

        if (h == 0) return l / d;

        require(h < d, 'FullMath: FULLDIV_OVERFLOW');
        return fullDiv(l, h, d);
    }
}

contract Ownable {
    address private _owner;

    constructor () internal {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function isOwner(address account) public view returns (bool) {
        return account == _owner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }


    modifier onlyOwner() {
        require(isOwner(msg.sender), "Ownable: caller is not the owner");
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}

interface ISwapFeeReward {
    function swap(address account, address input, address output, uint256 amount) external returns (bool);
}

contract BiswapRouter02 is IBiswapRouter02, Ownable {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;
    address public override swapFeeReward;
    event SafeTransferETH(address indexed to,uint amount);
    event RouterSwap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to,
        address indexed pair
    );
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'BiswapV2Router: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function setSwapFeeReward(address _swapFeeReward) public onlyOwner {
        swapFeeReward = _swapFeeReward;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IBiswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IBiswapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = BiswapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = BiswapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'BiswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = BiswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'BiswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = BiswapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IBiswapPair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = BiswapLibrary.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IBiswapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) 
        {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
            emit SafeTransferETH(msg.sender,msg.value-amountETH);
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = BiswapLibrary.pairFor(factory, tokenA, tokenB);
        IBiswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IBiswapPair(pair).burn(to);
        (address token0,) = BiswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'BiswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'BiswapV2Router: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
        emit SafeTransferETH(to,amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = BiswapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IBiswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = BiswapLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IBiswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
        emit SafeTransferETH(to,amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = BiswapLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IBiswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair                                                                                                                                      
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = BiswapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            if (swapFeeReward != address(0)) {
                ISwapFeeReward(swapFeeReward).swap(msg.sender, input, output, amountOut);
            }
            address to = i < path.length - 2 ? BiswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            (uint amount0In,uint amount1In)= (IBiswapPair(BiswapLibrary.pairFor(factory, input, output)).swap(
                                                     amount0Out, amount1Out, to, new bytes(0)));
            emit RouterSwap(msg.sender,amount0In,amount1In, amount0Out, amount1Out, to,BiswapLibrary.pairFor(factory, input, output));
            
        }
        
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = BiswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BiswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
        
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = BiswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'BiswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'BiswapV2Router: INVALID_PATH');
        amounts = BiswapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BiswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(BiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'BiswapV2Router: INVALID_PATH');
        amounts = BiswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'BiswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
        emit SafeTransferETH(to,amounts[amounts.length-1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WETH, 'BiswapV2Router: INVALID_PATH');
        amounts = BiswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BiswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
        emit SafeTransferETH(to,amounts[amounts.length-1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WETH, 'BiswapV2Router: INVALID_PATH');
        amounts = BiswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'BiswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(BiswapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) 
        {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
            emit SafeTransferETH(msg.sender,msg.value-amounts[0]);
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = BiswapLibrary.sortTokens(input, output);
            IBiswapPair pair = IBiswapPair(BiswapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = BiswapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput, pair.swapFee());
            }
            if (swapFeeReward != address(0)) {
                ISwapFeeReward(swapFeeReward).swap(msg.sender, input, output, amountOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? BiswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            (uint amount0In,uint amount1In)=pair.swap(amount0Out, amount1Out, to, new bytes(0));
            emit RouterSwap(msg.sender,amount0In,amount1In, amount0Out, amount1Out,to,BiswapLibrary.pairFor(factory, input, output));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BiswapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'BiswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH, 'BiswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(BiswapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'BiswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH, 'BiswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BiswapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'BiswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
        emit SafeTransferETH(to,amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return BiswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint swapFee)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return BiswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut, swapFee);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint swapFee)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return BiswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut, swapFee);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return BiswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return BiswapLibrary.getAmountsIn(factory, amountOut, path);
    }
}







contract pool {
    using SafeMath for uint256;

    // Tokens declaration

    IERC20 public BUST ;
    IERC20 public BUSD ;
    IERC20 public WBNB ;
    
    uint public snum=990;
    uint public sden =1000;
    uint public rnum=992;
    uint public rden=1000;
    
    uint public a;
    uint public b;
    uint public c;
    uint public d;
    
    address payable public dao ;
    address public reward;
    address public lock;
    
    // owner's address 
    address public owner;
    
    
    
    

    // LP Tokens
    IBiswapPair public BUSD_BUST ;
        

    IBiswapPair public BUST_BNB ;
       

    // Router Address
    IBiswapRouter02 public router ;
    
    // paths

 // change while deployment ??
     address[]  public p20 = [0x637F61C18Cd7259f7c5EA50591C7Befe6A2E0BfE, 0x6e03884333a30eE91AFda92E429fF4FD95Dc2850];
      address[]  public pETH = [0x44Bc761E0B58Aa6727202eBd2B636DC924dA9f1a, 0x6e03884333a30eE91AFda92E429fF4FD95Dc2850];


        
        
    // Read function
    
     function BUST_Bal() public view returns (uint256) {
        return BUST.balanceOf(address(this));
    }

    function BUSD_Bal() public view returns (uint256) {
        return BUSD.balanceOf(address(this));
    }

    function BNB_Bal() public view returns (uint256) {
        return address(this).balance;
    }
    
    function BUST_BUSD_Bal() public view returns (uint256) {
        return BUSD_BUST.balanceOf(address(this));
    }

    function BUST_BNB_Bal() public view returns (uint256) {
        return BUST_BNB.balanceOf(address(this));
    }
    // modifier
    
    modifier restricted() {
        require(msg.sender==owner);
        _;
    }
    
    // Write function
    // constructor
    constructor(address _bust, address _busd, address _wbnb,address _busd_lp, address _bnb_lp, address _router, address _reward,address _lock,address payable _dao) public {
        owner = msg.sender;
        reward = _reward;
         router = IBiswapRouter02(_router);
         BUST  = IERC20(_bust);
         BUSD  = IERC20(_busd);
         WBNB  = IERC20(_wbnb);
         BUSD_BUST =
        IBiswapPair(_busd_lp);

     BUST_BNB =
        IBiswapPair(_bnb_lp);
        lock = _lock;
        dao = _dao;
        
    }
    
    // set percentage
    
    function setPercent(uint _a,uint _b, uint _c, uint _d) public restricted(){
        require(_a+_b+_c+_d == 10000, "sum of percent should be eqqual to 10000");
        
        a=_a;
        b=_b;
        c=_c;
        d=_d;
    }
    
    // transfer ownership
    
    function transferOwnership(address _newOwner) public restricted(){
        require(_newOwner != address(0));
        owner = _newOwner;
    }
    
    //setter 
    function setFraction(uint _snum, uint _sden, uint _rnum, uint _rden) public restricted(){
        snum= _snum;
        sden = _sden;
        rnum = _rnum;
        rden = _rden;
    }
    
    function setRewardAddress(address _reward) public restricted(){
        reward = _reward;
    }
    
     function setRouterAddress(address _router) public restricted(){
         router = IBiswapRouter02(_router);
    }
    
    function setTokenAddress(address _bust, address _busd, address _wbnb) public restricted(){
         BUST  = IERC20(_bust);
         BUSD  = IERC20(_busd);
         WBNB  = IERC20(_wbnb);
    }
    
    function setLPAddress(address _busd, address _bnb) public restricted(){
          BUSD_BUST =
        IBiswapPair(_busd);

     BUST_BNB =
        IBiswapPair(_bnb);
    }
    
    function setLockAddress(address _lock) public restricted(){
        lock = _lock;
    }
    
    function setDAO(address payable _dao) public restricted(){
        dao = _dao;
    }
    
    // setting distribution percent
    
    // BUSD LP function 
    function distribution() public payable restricted(){
        
        uint256 BUSD_LP_Bal = BUSD_BUST.balanceOf(address(this));
        
        uint c1 = BUSD_LP_Bal.mul(a).div(10000);
        uint c2 = BUSD_LP_Bal.mul(b).div(10000);
        uint c3 = BUSD_LP_Bal.mul(c).div(10000);
        uint c4 = BUSD_LP_Bal.mul(d).div(10000);
        
       
         BUSD_BUST.approve(address(router), BUSD_LP_Bal);
         BUST_BNB.approve(address(router), BUST_BNB.balanceOf(address(this)));
        
       getBUST_BUSDLP(c1, reward);
          lock_BUSD_LP(c2);
          getBUST_BUSDLP(c3, 0x000000000000000000000000000000000000dEaD);
         BUSD_DAO(c4, dao);
        
        
        
        uint256 BNB_LP_Bal = BUST_BNB.balanceOf(address(this));
        
        
          c1 = BNB_LP_Bal.mul(a).div(10000);
         c2 = BNB_LP_Bal.mul(b).div(10000);
         c3 = BNB_LP_Bal.mul(c).div(10000);
         c4 = BNB_LP_Bal.mul(d).div(10000);
        
        
         getBUST_BNBLP(c1, reward);
        lock_BNB_LP(c2);
        getBUST_BNBLP(c3, 0x000000000000000000000000000000000000dEaD);
        BNB_DAO(c4, dao);
        
        
        
    }
    
    // case 1 and case 3 part 1
    
    function getBUST_BUSDLP(uint _amount, address addr) internal {
        (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) = BUSD_BUST.getReserves();
        uint tSupply = BUSD_BUST.totalSupply();
        
        // change while deployment ??
        
        uint tok0min = _reserve0.mul(_amount).mul(rnum).div(rden).div(tSupply);
        uint tok1min = _reserve1.mul(_amount).mul(rnum).div(rden).div(tSupply);
         uint256 time = block.timestamp + 1120;
        
        router.removeLiquidity(
            address(BUSD),
            address(BUST),
            _amount,
            tok0min,
            tok1min,
            address(this),
            time);
            
        // convert the BUSD to BUST
       (uint256 _rev0, uint256 _rev1, uint256 _bts) = BUSD_BUST.getReserves();
        
        //uint256 bust_rec = _rev1.mul(tok0min).div(_rev0); ?
       // uint256 bust_rec = _rev1.mul(BUSD.balanceOf(address(this))).div(_rev0); ?
       
       
         uint256 bust_rec = router.getAmountsOut(BUSD.balanceOf(address(this)),p20)[1];
        uint256 bust_rec_min = bust_rec.mul(rnum).div(rden);
        
        BUSD.approve(address(router), BUSD.balanceOf(address(this)));
        
        router.swapExactTokensForTokens(
            BUSD.balanceOf(address(this)),
            bust_rec_min,
            p20,
            address(this),
            time
        );
        
        // send the received amount to referal contract
        TransferHelper.safeTransfer(
            address(BUST),
            addr,
            BUST.balanceOf(address(this))
        );
        
    }
    
   
    // case 2 part 1
    function lock_BUSD_LP(uint _amount) internal{
        TransferHelper.safeTransfer(
            address(BUSD_BUST),
            lock,
            _amount
        );
    }
    // case 4 part 1 
    
    function BUSD_DAO(uint _amount, address addr) internal{
        (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) = BUSD_BUST.getReserves();
        uint tSupply = BUSD_BUST.totalSupply();
        
         // change while deployment ??
        
        uint tok0min = _reserve0.div(tSupply).mul(_amount).mul(rnum).div(rden);
        uint tok1min = _reserve1.div(tSupply).mul(_amount).mul(rnum).div(rden);
        uint256 time = block.timestamp + 1120;
        
        router.removeLiquidity(
            address(BUSD),
            address(BUST),
            _amount,
            tok0min,
            tok1min,
            address(this),
            time);
            
         TransferHelper.safeTransfer(
            address(BUST),
            addr,
            BUST.balanceOf(address(this))
        );
        TransferHelper.safeTransfer(
            address(BUSD),
            addr,
            BUSD.balanceOf(address(this))
        );
        
    }
   
    
     // BNB LP function
     // case 1 and case 3 part 2 
     
      function getBUST_BNBLP(uint _amount, address addr) internal{
        (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) =
            BUST_BNB.getReserves();
        uint tSupply = BUST_BNB.totalSupply();
        uint rmAmount = _amount;
        
        // change while deployment ??
        
         uint tok0min = _reserve0.mul(rmAmount).mul(rnum).div(rden).div(tSupply);
        uint tok1min = _reserve1.mul(rmAmount).mul(rnum).div(rden).div(tSupply);
        uint256 time = block.timestamp + 1120;
        
        router.removeLiquidityETH(address(BUST),
            rmAmount,
            tok1min,
            tok0min,
            address(this),
            time);
            
            
            
        // convert the BNB to BUST
        ( _reserve0,  _reserve1,  _blockTimestampLast) = BUST_BNB.getReserves();

        //uint256 bust = _reserve1.mul(address(this).balance).div(_reserve0);
        uint256 bust = router.getAmountsOut(address(this).balance,pETH)[1];
        uint256 bustmin = bust.mul(snum).div(sden);
        
       
        router.swapExactETHForTokens.value(address(this).balance)(
            bustmin,
            pETH,
            address(this),
            time
        );
    
        
        
       // send the received amount to referal contract
        TransferHelper.safeTransfer(
            address(BUST),
            addr,
            BUST.balanceOf(address(this))
            
        );
        
    }
    
    
    // case 2 part 1
    function lock_BNB_LP(uint _amount) internal{
        TransferHelper.safeTransfer(
            address(BUST_BNB),
            lock,
            _amount
        );
    }
    
    
    // case 4 part 1 
    
    function BNB_DAO(uint _amount, address payable addr) internal{
        
            
            (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast) =
            BUST_BNB.getReserves();
            
        uint tSupply = BUST_BNB.totalSupply();
        uint rmAmount = _amount;
        
         // change while deployment ??
        
        uint tok0min = _reserve0.mul(rmAmount).mul(rnum).div(rden).div(tSupply);
        uint tok1min = _reserve1.mul(rmAmount).mul(rnum).div(rden).div(tSupply);
        uint256 time = block.timestamp + 1120;
        
        router.removeLiquidityETH(address(BUST),
            rmAmount,
            tok1min,
            tok0min,
            address(this),
            time);
            
            
            
         TransferHelper.safeTransfer(
            address(BUST),
            addr,
            BUST.balanceOf(address(this))
        );
         addr.transfer(address(this).balance);
      
        
    }
    

    // fallback function 
    
   fallback() external payable {}
        
    }

