pragma solidity ^0.8.0;

import "./IBridge.sol";
import "./ISyntFabric.sol";
import "./RelayRecipient.sol";

contract Synthesis is RelayRecipient {

    uint256 requestCount;
    bool public paused;
    uint public nativeTokenPrice;
    address public fabric;
    mapping(bytes32 => TxState) public requests;
    mapping(bytes32 => SynthesizeState) public synthesizeStates;
    address public bridge;
    enum RequestState {Default, Sent, Reverted}
    enum SynthesizeState {Default, Synthesized, RevertRequest}


    event BurnRequest(bytes32 indexed _id, address indexed _from, address indexed _to, uint _amount, address _token);
    event RevertSynthesizeRequest(bytes32 indexed _id, address indexed _to);
    event SynthesizeCompleted(bytes32 indexed _id, address indexed _to, uint _amount, address _token);
    event RevertBurnCompleted(bytes32 indexed _id, address indexed _to, uint _amount, address _token);


    /**
     * init
     */

    function initialize(
        address _bridge, address _trustedForwarder
    ) public virtual initializer {
        __RelayRecipient_init(_trustedForwarder);
        bridge = _bridge;
        nativeTokenPrice = 10000000000000000;
        // 0.01 of native token
    }


    modifier onlyBridge {
        require(bridge == msg.sender);
        _;
    }

    struct TxState {
        address recipient;
        address chain2address;
        uint256 amount;
        address token;
        address stoken;
        RequestState state;
    }

    // can called only by bridge after initiation on a second chain
    function mintSyntheticToken(bytes32 _txID, address _tokenReal, uint256 _chainID, uint256 _amount, address _to) onlyBridge whenNotPaused external {
        require(synthesizeStates[_txID] == SynthesizeState.Default, "Symb: emergencyUnsynthesizedRequest called or tokens has been already synthesized");
        ISyntFabric(fabric).synthesize(_to, _amount, ISyntFabric(fabric).getSyntRepresentation(_tokenReal, _chainID));
        synthesizeStates[_txID] = SynthesizeState.Synthesized;
        emit SynthesizeCompleted(_txID, _to, _amount, _tokenReal);
    }

    // Revert synthesize() operation, can be called several times
    function emergencyUnsyntesizeRequest(bytes32 _txID, address _receiveSide, address _oppositeBridge, uint _chainID) whenNotPaused payable external {

        require(synthesizeStates[_txID] != SynthesizeState.Synthesized, "Symb: syntatic tokens already minted");
        synthesizeStates[_txID] = SynthesizeState.RevertRequest;
        // close
        bytes memory out = abi.encodeWithSelector(bytes4(keccak256(bytes('emergencyUnsynthesize(bytes32)'))), _txID);
        require(msg.value == nativeTokenPrice, "Symb: Not enough money");
        IBridge(bridge).transmitRequestV2(out, _receiveSide, _oppositeBridge, _chainID);

        emit RevertSynthesizeRequest(_txID, _msgSender());
    }

    // sToken -> Token on a second chain
    function burnSyntheticToken(address _stoken, uint256 _amount, address _chain2address, address _receiveSide, address _oppositeBridge, uint256 _chainID) external whenNotPaused payable returns (bytes32 txID) {
        ISyntFabric(fabric).unsynthesize(_msgSender(), _amount, _stoken);

        txID = keccak256(abi.encodePacked(this, requestCount));

        bytes memory out = abi.encodeWithSelector(bytes4(keccak256(bytes('unsynthesize(bytes32,address,uint256,address)'))), txID, ISyntFabric(fabric).getRealRepresentation(_stoken), _amount, _chain2address);
        require(msg.value == nativeTokenPrice, "Symb: Not enough money");
        IBridge(bridge).transmitRequestV2(out, _receiveSide, _oppositeBridge, _chainID);
        TxState storage txState = requests[txID];
        txState.recipient = _msgSender();
        txState.chain2address = _chain2address;
        txState.stoken = _stoken;
        txState.amount = _amount;
        txState.state = RequestState.Sent;

        requestCount += 1;

        emit BurnRequest(txID, _msgSender(), _chain2address, _amount, _stoken);
    }

    // can called only by bridge after initiation on a second chain
    function emergencyUnburn(bytes32 _txID) onlyBridge whenNotPaused external {
        TxState storage txState = requests[_txID];
        require(txState.state == RequestState.Sent, 'Symb: state not open or tx does not exist');
        txState.state = RequestState.Reverted;
        // close
        ISyntFabric(fabric).synthesize(txState.recipient, txState.amount, txState.stoken);
        emit RevertBurnCompleted(_txID, txState.recipient, txState.amount, txState.stoken);
    }



    // should be restricted in mainnets
    function changeBridge(address _bridge) onlyOwner external {
        bridge = _bridge;
    }

    function pause() onlyOwner external {
        paused = true;
    }

    function unpause() onlyOwner external {
        paused = false;
    }

    function changeBridgePrice(uint256 _newPrice) onlyOwner external {
        nativeTokenPrice = _newPrice;
    }

    function withdrawBridgeFee(address payable _to) external onlyOwner {
        _to.transfer((address(this).balance));
    }

    function versionRecipient() view public returns (string memory){
        return "2.0.1";
    }
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    function setFabric(address _fabric) external onlyOwner {
        // todo add require to one set
        fabric = _fabric;
    }

    // todo remove in prod
    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }
}

pragma solidity ^0.8.0;

interface IBridge {
     function transmitRequestV2(bytes memory owner, address receiveSide, address oppositeBridge, uint chainID) external  returns (bytes32);
}

pragma solidity ^0.8.0;

interface ISyntFabric {
    function getRealRepresentation(address _syntTokenAdr) external view returns (address);
    function getSyntRepresentation(address _realTokenAdr, uint256 _chainID) external view returns (address);
    function synthesize(address _to, uint256 _amount, address _stoken) external;
    function unsynthesize(address _to, uint256 _amount, address _stoken) external;
}

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract RelayRecipient is  OwnableUpgradeable {
    address private _trustedForwarder;

    function __RelayRecipient_init(address trustedForwarder) internal initializer {
        __Ownable_init();
        _trustedForwarder = trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        return forwarder == _trustedForwarder;
    }

    function _msgSender() internal view virtual override returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            assembly {sender := shr(96, calldataload(sub(calldatasize(), 20)))}
        } else {
            return super._msgSender();
        }
    }

    function _msgData() internal view virtual override returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[: msg.data.length - 20];
        } else {
            return super._msgData();
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";
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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
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

