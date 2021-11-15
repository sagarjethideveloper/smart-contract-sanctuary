// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./interfaces/ICurrencyRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CurrencyRegistry is ICurrencyRegistry, Ownable {
    mapping(string => address) private _addressOf;
    mapping(address => string) private _tickerOf;

    // tesnet address
    constructor() {
        _addressOf["DAI"] = 0xEC5dCb5Dbf4B114C9d0F65BcCAb49EC54F6A0867;
        _tickerOf[0xEC5dCb5Dbf4B114C9d0F65BcCAb49EC54F6A0867] = "DAI";

        _addressOf["USDC"] = 0x64544969ed7EBf5f083679233325356EbE738930;
        _tickerOf[0x64544969ed7EBf5f083679233325356EbE738930] = "USDC";

        _addressOf["USDT"] = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd;
        _tickerOf[0x337610d27c682E347C9cD60BD4b3b107C9d34dDd] = "USDT";

        _addressOf["BUSD"] = 0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee;
        _tickerOf[0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee] = "BUSD";
    }

    function addUpdateCurrency(string memory ticker, address addr)
        external
        override
        onlyOwner
    {
        _addressOf[ticker] = addr;
        _tickerOf[addr] = ticker;
    }

    function deleteCurrency(string memory ticker) external override onlyOwner {
        address addr = _addressOf[ticker];
        delete _tickerOf[addr];

        delete _addressOf[ticker];
    }

    function deleteCurrency(address addr) external override onlyOwner {
        string memory ticker = _tickerOf[addr];
        delete _addressOf[ticker];

        delete _tickerOf[addr];
    }

    function addCurrencies(string[] memory tickers, address[] memory addrs)
        external
        override
        onlyOwner
    {
        require(tickers.length == addrs.length, "Arrays length issue");
        for (uint256 i = 0; i < tickers.length; i++) {
            _addressOf[tickers[i]] = addrs[i];
            _tickerOf[addrs[i]] = tickers[i];
        }
    }

    function deleteCurrencies(string[] memory tickers)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < tickers.length; i++) {
            address addr = _addressOf[tickers[i]];
            delete _tickerOf[addr];

            delete _addressOf[tickers[i]];
        }
    }

    function deleteCurrencies(address[] memory addrs)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < addrs.length; i++) {
            string memory ticker = _tickerOf[addrs[i]];
            delete _addressOf[ticker];

            delete _tickerOf[addrs[i]];
        }
    }

    function isSupported(string memory ticker)
        public
        view
        override
        returns (bool)
    {
        return _addressOf[ticker] != address(0);
    }

    function isSupported(address addr) public view override returns (bool) {
        return keccak256(bytes(_tickerOf[addr])) != keccak256(bytes(""));
    }

    function addressOf(string memory ticker)
        external
        view
        override
        returns (address)
    {
        require(isSupported(ticker), "Currency not supported");
        return _addressOf[ticker];
    }

    function tickerOf(address addr)
        external
        view
        override
        returns (string memory)
    {
        require(isSupported(addr), "Currency not supported");
        return _tickerOf[addr];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

interface ICurrencyRegistry {
    function addUpdateCurrency(string memory, address) external;

    function deleteCurrency(string memory) external;

    function deleteCurrency(address) external;

    function addCurrencies(string[] memory, address[] memory) external;

    function deleteCurrencies(string[] memory) external;

    function deleteCurrencies(address[] memory) external;

    function isSupported(string memory) external returns (bool);

    function isSupported(address) external returns (bool);

    function addressOf(string memory) external view returns (address);

    function tickerOf(address) external view returns (string memory);
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
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
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

