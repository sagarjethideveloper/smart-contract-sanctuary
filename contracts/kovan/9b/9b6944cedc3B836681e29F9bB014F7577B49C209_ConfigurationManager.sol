// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ModuleStorage.sol";
import "../interfaces/IConfigurationManager.sol";

/**
 * @title ConfigurationManager
 * @author Pods Finance
 * @notice Allows contracts to read protocol-wide configuration modules
 */
contract ConfigurationManager is IConfigurationManager, ModuleStorage, Ownable {
    /* solhint-disable private-vars-leading-underscore */
    bytes32 private constant EMERGENCY_STOP = "EMERGENCY_STOP";
    bytes32 private constant PRICING_METHOD = "PRICING_METHOD";
    bytes32 private constant SIGMA_GUESSER = "SIGMA_GUESSER";
    bytes32 private constant PRICE_PROVIDER = "PRICE_PROVIDER";
    bytes32 private constant CAP_PROVIDER = "CAP_PROVIDER";
    bytes32 private constant AMM_FACTORY = "AMM_FACTORY";
    bytes32 private constant OPTION_FACTORY = "OPTION_FACTORY";
    bytes32 private constant OPTION_HELPER = "OPTION_HELPER";

    /* solhint-enable private-vars-leading-underscore */

    function setEmergencyStop(address emergencyStop) external override onlyOwner {
        _setModule(EMERGENCY_STOP, emergencyStop);
    }

    function setPricingMethod(address pricingMethod) external override onlyOwner {
        _setModule(PRICING_METHOD, pricingMethod);
    }

    function setSigmaGuesser(address sigmaGuesser) external override onlyOwner {
        _setModule(SIGMA_GUESSER, sigmaGuesser);
    }

    function setPriceProvider(address priceProvider) external override onlyOwner {
        _setModule(PRICE_PROVIDER, priceProvider);
    }

    function setCapProvider(address capProvider) external override onlyOwner {
        _setModule(CAP_PROVIDER, capProvider);
    }

    function setAMMFactory(address ammFactory) external override onlyOwner {
        _setModule(AMM_FACTORY, ammFactory);
    }

    function setOptionFactory(address optionFactory) external override onlyOwner {
        _setModule(OPTION_FACTORY, optionFactory);
    }

    function setOptionHelper(address optionHelper) external override onlyOwner {
        _setModule(OPTION_HELPER, optionHelper);
    }

    function getEmergencyStop() external override view returns (address) {
        return getModule(EMERGENCY_STOP);
    }

    function getPricingMethod() external override view returns (address) {
        return getModule(PRICING_METHOD);
    }

    function getSigmaGuesser() external override view returns (address) {
        return getModule(SIGMA_GUESSER);
    }

    function getPriceProvider() external override view returns (address) {
        return getModule(PRICE_PROVIDER);
    }

    function getCapProvider() external override view returns (address) {
        return getModule(CAP_PROVIDER);
    }

    function getAMMFactory() external override view returns (address) {
        return getModule(AMM_FACTORY);
    }

    function getOptionFactory() external override view returns (address) {
        return getModule(OPTION_FACTORY);
    }

    function getOptionHelper() external override view returns (address) {
        return getModule(OPTION_HELPER);
    }
}

pragma solidity ^0.6.0;

import "../GSN/Context.sol";
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

// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;

/**
 * @title ModuleStorage
 * @author Pods Finance
 * @notice Stores addresses from configuration modules
 */
contract ModuleStorage {
    mapping(bytes32 => address) private _addresses;

    event ModuleSet(bytes32 indexed name, address indexed newAddress);

    /**
     * @dev Get a configuration module address
     * @param name The name of a module
     */
    function getModule(bytes32 name) public view returns (address) {
        return _addresses[name];
    }

    /**
     * @dev Set a configuration module address
     * @param name The name of a module
     * @param module The module address
     */
    function _setModule(bytes32 name, address module) internal {
        require(module != address(0), "ModuleStorage: Invalid module");
        _addresses[name] = module;
        emit ModuleSet(name, module);
    }
}

// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;

interface IConfigurationManager {
    function setEmergencyStop(address emergencyStop) external;

    function setPricingMethod(address pricingMethod) external;

    function setSigmaGuesser(address sigmaGuesser) external;

    function setPriceProvider(address priceProvider) external;

    function setCapProvider(address capProvider) external;

    function setAMMFactory(address ammFactory) external;

    function setOptionFactory(address optionFactory) external;

    function setOptionHelper(address optionHelper) external;

    function getEmergencyStop() external view returns (address);

    function getPricingMethod() external view returns (address);

    function getSigmaGuesser() external view returns (address);

    function getPriceProvider() external view returns (address);

    function getCapProvider() external view returns (address);

    function getAMMFactory() external view returns (address);

    function getOptionFactory() external view returns (address);

    function getOptionHelper() external view returns (address);
}

pragma solidity ^0.6.0;

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
    constructor () internal { }

    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

