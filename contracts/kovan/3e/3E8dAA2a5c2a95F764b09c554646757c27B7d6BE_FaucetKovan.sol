// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;

import "../interfaces/IERC20Mintable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface LendingPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
}

contract FaucetKovan {
    using SafeMath for uint256;
    LendingPool private _lendingPool = LendingPool(0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe);
    IERC20Mintable private _usdc = IERC20Mintable(0xe22da380ee6B445bb8273C81944ADEB6E8450422);
    IERC20Mintable private _dai = IERC20Mintable(0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD);
    IERC20Mintable private _wbtc = IERC20Mintable(0x351a448d49C8011D293e81fD53ce5ED09F433E4c);
    IERC20Mintable private _link = IERC20Mintable(0xbA74882beEe5482EbBA7475A0C5A51589d4ed5De);

    function getFaucet() external {
        uint256 askedAmount = 5000;

        // Mint USDC and aUSDC
        uint8 usdcDecimals = _usdc.decimals();
        uint256 mintedUsdcAmount = askedAmount.mul(10**uint256(usdcDecimals));
        _usdc.mint(mintedUsdcAmount);
        _usdc.transfer(msg.sender, mintedUsdcAmount.div(2));
        _usdc.approve(address(_lendingPool), mintedUsdcAmount.div(2));
        _lendingPool.deposit(address(_usdc), mintedUsdcAmount.div(2), msg.sender, 0);

        // Mint DAI and aDAI
        uint8 daiDecimals = _dai.decimals();
        uint256 mintedDaiAmount = askedAmount.mul(10**uint256(daiDecimals));
        _dai.mint(mintedDaiAmount);
        _dai.transfer(msg.sender, mintedDaiAmount.div(2));
        _dai.approve(address(_lendingPool), mintedDaiAmount.div(2));
        _lendingPool.deposit(address(_dai), mintedDaiAmount.div(2), msg.sender, 0);

        // Mint WBTC
        uint256 askedWbtcAmount = 5;
        uint8 wbtcDecimals = _wbtc.decimals();
        uint256 mintedWbtcAmount = askedWbtcAmount.mul(10**uint256(wbtcDecimals));

        _wbtc.mint(mintedWbtcAmount);
        _wbtc.transfer(msg.sender, mintedWbtcAmount);

        // Mint LINK
        uint256 askedLinkAmount = 100;
        uint8 linkDecimals = _link.decimals();
        uint256 mintedLinkAmount = askedLinkAmount.mul(10**uint256(linkDecimals));

        _link.mint(mintedLinkAmount);
        _link.transfer(msg.sender, mintedLinkAmount);
    }
}

// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;

interface IERC20Mintable {
    function mint(uint256 amount) external returns (bool);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function decimals() external returns (uint8);
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

