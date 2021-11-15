pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./Token.sol";

contract Presale is Ownable {
    using SafeMath for uint256;
    event Purchase(address indexed _address, uint256 _bnbAmount, uint256 _tokensAmount);
    event TransferBnb(address indexed _address, uint256 _bnbAmount);
    event Paused();
    event Started();

    uint256 public totalBnb;
    uint256 public totalToken;

    Token public token;
    uint256 public rate;
    address payable public transferAddress;

    bool public mintable = false;
    bool public paused = false;

    uint256 public minPurchase;
    uint256 public maxPurchasePerWallet = 20 ether;

    mapping(address => uint256) private balances;
    address[] private investers;

    constructor(Token _token, uint256 _rate) public {
        token = _token;
        rate = _rate;
        transferAddress = msg.sender;

        minPurchase = _rate;
    }

    receive() external payable {
        purchase();
    }

    function purchase() public payable {
        require(!paused, "Presale: paused");
        require(minPurchase <= msg.value && balances[msg.sender] + msg.value <= maxPurchasePerWallet, "Presale: purchase amount limit");

        uint256 tokensAmount = calculateTokensAmount(msg.value);

        deliverTokens(msg.sender, tokensAmount);

        totalBnb = totalBnb.add(msg.value);
        totalToken = totalToken.add(tokensAmount);

        balances[msg.sender] = balances[msg.sender].add(msg.value);

        emit Purchase(msg.sender, msg.value, tokensAmount);
    }

    function calculateTokensAmount(uint256 _amount) public view returns (uint256)  {
        return _amount.div(rate.div(10000)).mul(10 ** 18).div(10000);
    }

    function tokensBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function balanceOf(address _address) external view returns (uint256) {
        return balances[_address];
    }

    function bnbBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function transferBnb() external onlyOwner {
        uint256 balance = address(this).balance;

        require(balance > 0, "Presale: balance must be greater than zero");

        transferAddress.transfer(balance);

        emit TransferBnb(transferAddress, balance);
    }

    function updateMinPurchase(uint256 _minPurchase) external onlyOwner {
        require(_minPurchase >= rate, "Presale: the minimum purchase amount must be no less than the rate");
        require(maxPurchasePerWallet >= _minPurchase, "Presale: the minimum purchase amount cannot be more than the maximum amount");

        minPurchase = _minPurchase;
    }

    function updateMaxPurchase(uint256 _maxPurchasePerWallet) external onlyOwner {
        require(_maxPurchasePerWallet >= minPurchase, "Presale: the maximum purchase amount cannot be less than the minimum amount");

        maxPurchasePerWallet = _maxPurchasePerWallet;
    }

    function updateRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function updateTransferAddress(address payable _transferAddress) external onlyOwner {
        transferAddress = _transferAddress;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function start() external onlyOwner {
        paused = false;
        emit Started();
    }

    function updateMintable(bool _mintable) external onlyOwner {
        if (_mintable) {
            require(token.isIMinter(), "Presale: the contract has no right to mint");
        }
        mintable = _mintable;
    }

    function deliverTokens(address _to, uint256 _amount) internal {
        if (mintable) {
            token.mint(_to, _amount);
        } else {
            token.transfer(_to, _amount);
        }
    }
}

pragma solidity ^0.6.12;

import "./lib/BEP20.sol";

contract Token is BEP20 {

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) public BEP20(_name, _symbol) {
        _mint(msg.sender, _initialSupply * 10 ** uint256(decimals));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./roles/OwnerRole.sol";
import "./roles/MinterRole.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";

abstract contract BEP20 is OwnerRole, MinterRole {
    using SafeMath for uint256;

    uint256 public totalSupply;
    uint256 public totalBurned;

    string public name;
    string public symbol;
    uint8 public decimals = 18;

    uint16 public burnFee;
    uint16 public devFee;

    mapping(address => uint256) private balances;

    mapping(address => mapping(address => uint256)) private allowances;

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
    }

    function balanceOf(address _account) external view virtual returns (uint256) {
        return balances[_account];
    }

    function allowance(address _from, address _to) external view virtual returns (uint256) {
        return allowances[_from][_to];
    }

    function mint(address _to, uint256 _amount) external virtual onlyMinter {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount) external virtual {
        _burn(msg.sender, _amount);
    }

    function approve(address _to, uint256 _amount) external virtual returns (bool) {
        require(_amount > 0, "BEP20: amount must be greater than zero");

        _approve(msg.sender, _to, _amount);
        return true;
    }

    function transfer(address _to, uint256 _amount) external virtual returns (bool) {
        require(msg.sender != _to, "BEP20: can't transfer to own address");

        _transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) external virtual returns (bool) {
        require(_from != _to, "BEP20: can't transfer to own address");
        require(allowances[_from][msg.sender] >= _amount, "BEP20: transfer amount exceeds allowance");

        _transfer(_from, _to, _amount);
        _approve(_from, msg.sender, allowances[_from][msg.sender] - _amount);

        return true;
    }

    function increaseAllowance(address _to, uint256 _amount) external virtual returns (bool) {
        require(_amount > 0, "BEP20: amount must be greater than zero");

        uint256 total = allowances[msg.sender][_to].add(_amount);
        _approve(msg.sender, _to, total);
        return true;
    }

    function decreaseAllowance(address _to, uint256 _amount) external virtual returns (bool) {
        require(allowances[msg.sender][_to] >= _amount, "BEP20: decreased allowance below zero");
        require(_amount > 0, "BEP20: amount must be greater than zero");

        uint256 total = allowances[msg.sender][_to].sub(_amount);
        _approve(msg.sender, _to, total);
        return true;
    }

    function addMinter(address _minter) public onlyOwner override(MinterRole) {
        super.addMinter(_minter);
    }

    function removeMinter(address _minter) public onlyOwner override(MinterRole) {
        super.removeMinter(_minter);
    }

    function updateBurnFee(uint16 _percent) external onlyOwner {
        require(_percent >= 0 && _percent <= 10000, "BEP20: incorrect percentage");
        require(_percent + devFee <= 10000, "BEP20: the sum of all commissions cannot exceed 10000 percent");

        burnFee = _percent;
    }

    function updateDevFee(uint16 _percent) external onlyOwner {
        require(_percent >= 0 && _percent <= 10000, "BEP20: incorrect percentage");
        require(_percent + burnFee <= 10000, "BEP20: the sum of all commissions cannot exceed 10000 percent");

        devFee = _percent;
    }

    function calcFee(uint256 _amount, uint16 _percent) public pure returns (uint256) {
        require(_percent >= 0 && _percent <= 10000, "BEP20: incorrect percentage");

        return _amount.mul(_percent).div(10000);
    }

    function _mint(address _to, uint256 _amount) internal virtual {
        require(_to != address(0), "BEP20: mint to the zero address");
        require(_amount > 0, "BEP20: amount must be greater than zero");

        totalSupply = totalSupply.add(_amount);
        balances[_to] = balances[_to].add(_amount);

        emit Transfer(address(0), _to, _amount);
    }

    function _burn(address _from, uint256 _amount) internal virtual {
        require(_from != address(0), "BEP20: burn from the zero address");
        require(_amount > 0, "BEP20: amount must be greater than zero");
        require(balances[_from] >= _amount, "BEP20: burn amount exceeds balance");

        balances[_from] = balances[_from].sub(_amount);
        totalSupply = totalSupply.sub(_amount);
        totalBurned = totalBurned.add(_amount);

        emit Transfer(_from, address(0), _amount);
    }

    function _approve(address _from, address _to, uint256 _amount) internal virtual {
        require(_from != address(0), "BEP20: approve from the zero address");
        require(_to != address(0), "BEP20: approve to the zero address");

        allowances[_from][_to] = _amount;
        emit Approval(_from, _to, _amount);
    }

    function _transfer(address _from, address _to, uint256 _amount) internal virtual {
        require(_from != address(0), "BEP20: transfer from the zero address");
        require(_to != address(0), "BEP20: transfer to the zero address");
        require(balances[_from] >= _amount, "BEP20: transfer amount exceeds balance");
        require(_amount > 0, "BEP20: amount must be greater than zero");

        uint256 burnFeeValue = calcFee(_amount, burnFee);
        uint256 devFeeValue = calcFee(_amount, devFee);
        uint256 calculatedAmount = _amount.sub(burnFeeValue).sub(devFeeValue);

        balances[_from] = balances[_from].sub(calculatedAmount).sub(devFeeValue);

        if (calculatedAmount > 0) {
            balances[_to] = balances[_to].add(calculatedAmount);
            emit Transfer(_from, _to, calculatedAmount);
        }

        if (devFeeValue > 0) {
            balances[owner] = balances[owner].add(devFeeValue);
            emit Transfer(_from, owner, devFeeValue);
        }

        if (burnFeeValue > 0) {
            _burn(_from, burnFeeValue);
        }
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

abstract contract MinterRole {
    mapping(address => bool) private minters;

    event MinterAdded(address indexed _minter);
    event MinterRemoved(address indexed _minter);

    constructor () public {
        addMinter(msg.sender);
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "Minterable: caller is not the minter");
        _;
    }

    function isIMinter() external view returns (bool) {
        return minters[msg.sender];
    }

    function isMinter(address _minter) external view virtual returns (bool) {
        return minters[_minter];
    }

    function addMinter(address _minter) public virtual {
        minters[_minter] = true;
        emit MinterAdded(_minter);
    }

    function removeMinter(address _minter) public virtual {
        minters[_minter] = false;
        emit MinterRemoved(_minter);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

abstract contract OwnerRole {
    address public owner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor () public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) external virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.4.0;

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
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor() internal {}

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.4.0;

import '../GSN/Context.sol';

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
    constructor() internal {
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
        require(_owner == _msgSender(), 'Ownable: caller is not the owner');
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), 'Ownable: new owner is the zero address');
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.4.0;

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
        require(c >= a, 'SafeMath: addition overflow');

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
        return sub(a, b, 'SafeMath: subtraction overflow');
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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
        require(c / a == b, 'SafeMath: multiplication overflow');

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
        return div(a, b, 'SafeMath: division by zero');
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
        return mod(a, b, 'SafeMath: modulo by zero');
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

