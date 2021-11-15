// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IBridgeV1.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Bridge is IBridgeV1, Ownable {

    // token for the bridge
    address public token;
    mapping (bytes32 => bool) txHashes;


    constructor(address _tokenAddress) public {
        token = _tokenAddress;
    }

    /**
     * @dev Initiates a token transfer from the given ledger to another Ethereum-compliant ledger.
     * @param amount The amount of tokens getting locked and swapped from the ledger
     * @param swapInAddress The address (on another ledger) to which the tokens are swapped
     */
    function SwapOut(uint256 amount, address swapInAddress)
    external
    override
    returns (bool) {
        require(swapInAddress != address(0), "Bridge: swapInAddress");
        require(amount > 0, "Bridge: amount");
        // check user allowance
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= amount,
            "Bridge: allowance"
        );
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Bridge: transfer"
        );
        emit LogSwapOut(msg.sender, swapInAddress, amount);
        return true;
    }

    /**
     * @dev Initiates a token transfer from the given ledger to another Ethereum-compliant ledger.
     * @param txHash Transaction hash on the ledger where the swap has beed initiated.
     * @param to The address to which the tokens are swapped
     * @param amount The amount of tokens released
     */

    function SwapIn(
        bytes32 txHash,
        address to,
        uint256 amount
    )
    external
    override
    onlyOwner
    returns (bool) {
        require (txHash != bytes32(0), "Bridge: invalid tx");
        require (to != address(0), "Bridge: invalid addr");
        require (amount != 0, "Bridge: invalid amount");
        require (txHashes[txHash] == false, "Bridge: dup tx");
        require(
            IERC20(token).transfer(to, amount),
            "Bridge: transfer"
        );
        txHashes[txHash] = true;
        emit LogSwapIn(txHash, to, amount);
        return true;
    }

    /**
     * @dev Initiates a withdrawal transfer from the bridge contract to an address. Only call-able by the owner
     * @param to The address to which the tokens are swapped
     * @param amount The amount of tokens released
     */
    function withdraw(address to, uint256 amount) public onlyOwner {
        IERC20(token).transfer(to, amount);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the Equalizer Bridge smart contract.
 * Equalizer V1 bridge properties
 *   - Bridge for EQZ EIP-20 and BEP-20 tokens only
 *   - Swap between Ethereum (ETH) and Binance Smart Chain (BSC) blockchains
 *   - Min swap value: 100 EQZ
 *   - Max swap value: Amount available
 *   - Swap fee: 0.1%
 *   - Finality:
 *     - ETH: 7 blocks
 *     - BSC: 15 blocks (~75 sec.); https://docs.binance.org/smart-chain/guides/concepts/consensus.html#security-and-finality
 *   - Reference implementation: https://github.com/anyswap/mBTC/blob/master/contracts/ProxySwapAsset.sol
 * Important references:
 *   - https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/
 *   - https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol
 */

/**
 * @title IBridgeV1 - Bridge V1 interface
 * @notice Interface for the Equalizer Bridge V1
 * @author Equalizer
 * @dev Equalizer bridge interface
 **/

interface IBridgeV1 {
    /**
     * @dev Initiates a token transfer from the given ledger to another Ethereum-compliant ledger.
     * @param amount The amount of tokens getting locked and swapped from the ledger
     * @param swapInAddress The address (on another ledger) to which the tokens are swapped
     */
    function SwapOut(uint256 amount, address swapInAddress)
    external
    returns (bool);

    /**
     * @dev Initiates a token transfer from the given ledger to another Ethereum-compliant ledger.
     * @param txHash Transaction hash on the ledger where the swap has beed initiated.
     * @param to The address to which the tokens are swapped
     * @param amount The amount of tokens released
     */
    function SwapIn(
        bytes32 txHash,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emmits an event upon the swap out call.
     * @param swapOutAddress The address of the swap out initiator
     * @param swapInAddress The address (on another ledger) to which the tokens are swapped
     * @param amount The amount of tokens getting locked and swapped from the ledger
     */
    event LogSwapOut(
        address indexed swapOutAddress,
        address indexed swapInAddress,
        uint256 amount
    );

    /**
     * @dev Emmits an event upon the swap in call.
     * @dev Initiates a token transfer from the given ledger to another Ethereum-compliant ledger.
     * @param txHash Transaction hash on the ledger where the swap has beed initiated.
     * @param swapInAddress The address to which the tokens are swapped
     * @param amount The amount of tokens released
     */
    event LogSwapIn(
        bytes32 indexed txHash,
        address indexed swapInAddress,
        uint256 amount
    );
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

