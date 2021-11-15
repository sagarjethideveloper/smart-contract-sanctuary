pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import './interfaces/Evolable.sol';
import './interfaces/ICellRepository.sol';
import "./interfaces/ISeed.sol";
import './interfaces/ILaboratory.sol';
import './interfaces/ICellToken.sol';

import '@openzeppelin/contracts/utils/Counters.sol';

contract NFTCell is Evolable, Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint8 constant MAX_LEVEL_OF_EVOLUTION = 100;
    uint256 constant BASE_PRICE_ETH = 1 wei; // TODO: change to real price
    // Db that stores token info
    address private repository;

    address private laboratory;
    address private nftToken;

    modifier isAllowedToBoost(uint256 _tokenID) {
        CellData.Cell memory cell = ICellRepository(repository).get(_tokenID);
        // TBD maybe we should allow boosting non-owner's cells
        require(cell.user == msg.sender, "You are not an owner of token");
        // TBD may be we should allow to change class as a boost option
        require(cell.class != CellData.Class.FINISHED, "You are not able to evolve more");
        require(cell.nextEvolutionBlock != type(uint256).max, "You have the highest level");
        require(cell.nextEvolutionBlock > block.number + 1, "You are ready to evolve");
        _;
    }

    /**
     *  At deploy should be minted 100k tokens
     *  with id = 0 (Class.INIT).
     *  On unpack for each token should be
     *  generated unique id by _tokenIds.increment()
     */
    constructor(address _owner) {
        require(_owner != address(0), "Address should not be empty");

        transferOwnership(_owner);
    }

    function changeOwner(address _newOwner) external onlyOwner {
        transferOwnership(_newOwner);
    }

    function setRepository(address _repository) public onlyOwner {
        require(_repository != address(0), "Address should not be empty");

        repository = _repository;
    }

    function setLaboratory(address _laboratory) external onlyOwner {
        require(_laboratory != address(0), "Address should not be empty");
        laboratory = _laboratory;
    }

    function setRandom(address _random) external onlyOwner {
        require(_random != address(0), "Address should not be empty");

        ILaboratory(laboratory).setRandom(_random);
    }

    function create() external payable override {
        require(msg.value >= BASE_PRICE_ETH, 'Insufficient amount');
        CellData.Cell memory newCell = ILaboratory(laboratory).create(msg.sender);
        ICellRepository(repository).add(newCell);
        ICellToken(nftToken).mint(msg.sender, 0);

        emit NewEvolutionCompleted(
            "Create",
            newCell.tokenId,
            uint8(newCell.class),
            newCell.stage,
            newCell.nextEvolutionBlock
        );
    }

    function evolve(uint256 _tokenID) external override {
        CellData.Cell memory cell = ICellRepository(repository).get(_tokenID);        
        //TDB: discuss this as it's not the best soultion
        if (CellData.Class(cell.class) == CellData.Class.SPLITTABLE) {
            CellData.Cell memory splitted = ILaboratory(laboratory).split(msg.sender, cell.stage);
            ICellRepository(repository).add(splitted);
            ICellToken(nftToken).mint(msg.sender, 0);
            emit NewEvolutionCompleted(
                "Split", 
                splitted.tokenId, 
                uint8(splitted.class), 
                splitted.stage, 
                splitted.nextEvolutionBlock
            );
        }

        cell = ILaboratory(laboratory).evolve(msg.sender, cell);
        ICellRepository(repository).update(cell, msg.sender);
 

        emit NewEvolutionCompleted("Evolve", _tokenID, uint8(cell.class), cell.stage, cell.nextEvolutionBlock);
    }

    function boostCell(uint256 _tokenID) external payable override isAllowedToBoost(_tokenID) {
        // Currently it is unclear on how many blocks should decrease evolution with boosting
        // Set it to the next block
        //ICellRepository(repository).updateEvolutionTime(_tokenID, block.number + 1);
        CellData.Cell memory cell = ICellRepository(repository).get(_tokenID);
        cell = ILaboratory(laboratory).boost(cell);
        ICellRepository(repository).update(cell, msg.sender);

        emit EvolutionTimeReduced(_tokenID);
    }

    function merge(uint256 _tokenA, uint256 _tokenB) override external {
        CellData.Cell memory cellA = ICellRepository(repository).get(_tokenA);
        CellData.Cell memory cellB = ICellRepository(repository).get(_tokenB);
        CellData.Cell memory newCell = ILaboratory(laboratory).merge(msg.sender, cellA, cellB);

        ICellRepository(repository).remove(_tokenA, msg.sender);
        ICellRepository(repository).remove(_tokenB, msg.sender);
        ICellRepository(repository).add(newCell);
        // TBD if we will not have unique properties for every nft => only _burn() should be
        // called without mint
        ICellToken(nftToken).burnBatch(msg.sender, 0, 2);
        ICellToken(nftToken).mint(msg.sender, 0);
        emit NewEvolutionCompleted(
            "Merge",
            newCell.tokenId,
            uint8(newCell.class),
            newCell.stage,
            newCell.nextEvolutionBlock
        );
    }

    function setToken(address _token) external {
        nftToken = _token;
    }

    function getSeed() external view onlyOwner returns (uint256) {
        return ISeed(laboratory).getSeed();
    }

    function setSeed(uint256 seed) external onlyOwner {
        ISeed(laboratory).setSeed(seed);
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

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
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
        return a + b;
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
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

pragma solidity >=0.7.0 <0.9.0;

/**
 * @title Interface initial generating of cel
 */
interface Evolable {
    /**
     *  Event to show that new token
     *  was generated
     *  @dev has to be emited in `unpack` and evolve
     */
    event NewEvolutionCompleted(
        string methodName,
        uint256 _tokenID,
        uint8 _class,
        uint8 _stage,
        uint256 _nextEvolutionTime
    );

    /**
     *  Event to show the amount
     *  of blocks for next evolution
     *  @dev has to be emited in `boostCell`
     */
    event EvolutionTimeReduced(uint256 newTokenID);

    /**
     *  user can unpack a lootBox
     *  and receive new token
     *  @dev can be called by any user
     *  @dev NewEvoutionCompleted has to be emmited
     */
    function create() external payable;

    /**
     *  user can evolve his token
     *  to a new stage
     *  @dev can be called by any user
     *  @dev NewEvoutionCompleted has to be emmited
     */
    function evolve(uint256 _tokenID) external;

    /**
     *  user can boost his
     *  awaiting time
     *  @dev can be called by any user
     *  @dev EvolutionTimeReduced has to be emmited
     */
    function boostCell(uint256 _tokenID) external payable;

    /**
     *  user can merge two tokens into one
     *  @dev can be called by any user
     *  @dev NewEvolutionCompleted has to be emmited
     */
    function merge(uint256 _tokenA, uint256 _tokenB) external;
}

pragma solidity ^0.8.0;

import '../libraries/CellData.sol';

/**
 * @title Interface for interaction with particular cell
 */
abstract contract ICellRepository {
    /**
     *  Adding a new cell to storage
     */
    function add(CellData.Cell memory cell) external virtual;

    /**
     *  Removing a cell from storage
     */
    function remove(uint256 id, address owner) external virtual;

    /**
     * Update existing cell
     * @dev possible to call only for owner of cell
     */
    function update(CellData.Cell memory cell, address owner) external virtual;

    /**
     *  getting full info about cell
     */
    function get(uint256 id) external view virtual returns (CellData.Cell memory cell);
}

pragma solidity ^0.8.0;

interface ISeed {
    function getSeed() external view returns (uint256);

    function setSeed(uint256 seed) external;
}

pragma solidity ^0.8.0;
import '../libraries/CellData.sol';
import './ISeed.sol';

interface ILaboratory is ISeed {
    function setRandom(address randomAddress) external;

    /**
     *  creates a new cell
     **/
    function create(address tokenOwner) external returns (CellData.Cell memory);

    /**
     *  starts evelution process
     **/
    function evolve(address tokenOwner, CellData.Cell memory cell)
        external
        view
        returns (CellData.Cell memory);

    /**
     *  merges two tokens into one
     **/
    function merge(
        address tokenOwner,
        CellData.Cell memory cellA,
        CellData.Cell memory cellB
    ) external returns (CellData.Cell memory);

    function split(address owner, uint8 _stage) external returns (CellData.Cell memory);

    function boost(CellData.Cell memory cell) external view returns (CellData.Cell memory);
}

pragma solidity ^0.8.0;

interface ICellToken {
    function mint(address _tokenOwner, uint256 _id) external;

    function burnBatch(
        address _tokenOwner,
        uint256 _id,
        uint8 _amount
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
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

pragma solidity ^0.8.0;

/**
 * @title Representation of cell with it fields
 */
library CellData {
    /**
     *  Represents the standart roles
     *  on which cell can be divided
     */
    enum Class {
        INIT,
        COMMON,
        SPLITTABLE,
        FINISHED
    }

    /**
     *  Represents the basic
     *  parametrs that describes cell
     */
    struct Cell {
        // token id
        uint256 tokenId;
        // user address that owns current cell
        address user;
        // current class
        Class class;
        // evolution level
        uint8 stage;
        // block number on which evolution is enabled
        uint256 nextEvolutionBlock;
        // token metadata URI
        string tokenUri;
    }
}

