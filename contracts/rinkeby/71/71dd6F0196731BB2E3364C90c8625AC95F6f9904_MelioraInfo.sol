// SPDX-License-Identifier: MIT

//** Meliora Crowfunding Contract*/
//** Author Alex Hong : Meliora Finance 2021.5 */

pragma solidity 0.6.6;
pragma experimental ABIEncoderV2;

import "./libraries/Ownable.sol";

contract MelioraInfo is Ownable {
    uint256 private devFeePercentage = 1;
    uint256 private minDevFeeInWei = 1 ether;
    address[] private launchpadAddresses;

    /**
     *
     * @dev add launchpage adress to the pool
     *
     */
    function addLaunchpadAddress(address _launchapd)
        external
        returns (uint256)
    {
        launchpadAddresses.push(_launchapd);
        return launchpadAddresses.length - 1;
    }

    /**
     *
     * @dev get launchpad count
     *
     */
    function getLaunchpadCount() external view returns (uint256) {
        return launchpadAddresses.length;
    }

    /**
     *
     * @dev get launchpad address
     *
     */
    function getLaunchpadAddress(uint256 launchId)
        external
        view
        returns (address)
    {
        return launchpadAddresses[launchId];
    }

    /**
     *
     * @dev get allocated percentage
     *
     */
    function getDevFeePercentage() external view returns (uint256) {
        return devFeePercentage;
    }

    /**
     *
     * @dev set custom fee percent
     *
     */
    function setDevFeePercentage(uint256 _devFeePercentage) external onlyOwner {
        devFeePercentage = _devFeePercentage;
    }

    /**
     *
     * @dev get minimum dev fee
     *
     */
    function getMinDevFeeInWei() external view returns (uint256) {
        return minDevFeeInWei;
    }

    /**
     *
     * @dev set minimum dev fee
     *
     */
    function setMinDevFeeInWei(uint256 _minDevFeeInWei) external onlyOwner {
        minDevFeeInWei = _minDevFeeInWei;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./Context.sol";

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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

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
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

