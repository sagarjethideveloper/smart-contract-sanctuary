pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IRewards.sol";
import "../../interfaces/IRandomNumberGenerator.sol";
import "../../interfaces/IMemeXNFT.sol";

/// SSS TODO: Add more events maybe??
contract Lottery is Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private lotteryCounter;

    bytes32 internal requestId_;

    // Address of the randomness generator
    IRandomNumberGenerator internal randomGenerator;
    IRewards public softStakeContract;

    mapping(uint256 => LotteryInfo) internal lotteryHistory;

    //lotteryid => prizeIds[]
    mapping(uint256 => uint256[]) internal prizes;

    //lotteryid => address => participantInfo
    mapping(uint256 => mapping(address => ParticipantInfo))
        internal participants;

    //this maps the number a person received when buying a ticket or boost to their address
    //lotteryId => number => address
    mapping(uint256 => mapping(uint256 => address)) participantEntries;

    enum Status {
        Planned, // The lottery is only planned, cant buy tickets yet
        Canceled, // A lottery that got canceled
        Open, // Entries are open
        Closed, // Entries are closed. Must be closed to draw numbers
        Completed // The lottery has been completed and the numbers drawn
    }

    struct ParticipantInfo {
        address participantAddress;
        bool isBooster;
        uint256 prizeId;
        bool prizeClaimed;
        uint32 entries;
    }

    // Information about lotteries
    struct LotteryInfo {
        uint256 lotteryID; // ID for lotto
        Status status; // Status for lotto
        uint256 ticketCostPinas; // Cost per ticket in points/tokens
        uint256 ticketCostCoins; // Cost per ticket in FTM
        uint256 boostCost; // cost to boost the odds
        uint256 startingTime; // Timestamp to start the lottery
        uint256 closingTime; // Timestamp for end of entries
        IMemeXNFT nftContract; // reference to the NFT Contract
        Counters.Counter entries; // count the number of entries (each ticket + boost bought)
        Counters.Counter participantsCount; // number of participants
        uint32 maxParticipants; // max number of participants
    }

    event ResponseReceived(bytes32 _requestId);
    event PrizesChanged(uint256 _lotteryId, uint256 numberOfPrizes);
    event LotteryStatusChanged(uint256 _lotteryId, Status _status);
    event RequestNumbers(uint256 lotteryId, bytes32 requestId);
    event NewParticipant(
        uint256 lotteryId,
        address participantAddress,
        uint16 amountOfNumbers
    );
    event TicketCostChanged(
        address operator,
        uint256 lotteryId,
        uint256 priceOfTicket
    );
    event NumberAssignedToParticipant(
        uint256 lotteryId,
        uint256 number,
        address participantAddress
    );

    constructor(address _stakeContract) public {
        softStakeContract = IRewards(_stakeContract);
    }

    function setTicketCostPinas(uint256 _price, uint256 _lotteryId)
        public
        onlyOwner
    {
        lotteryHistory[_lotteryId].ticketCostPinas = _price;
        emit TicketCostChanged(msg.sender, _lotteryId, _price);
    }

    function _burnPinasToken(
        address _user,
        IRewards rewardsToken,
        uint256 _amount
    ) internal {
        require(
            rewardsToken.balanceOf(_user) >= _amount,
            "Not enough PINA tokens to enter the lottery"
        );
        rewardsToken.burnPinas(_user, _amount);
    }

    function _burnUserPoints(address _user, uint256 _amount) internal {
        require(
            softStakeContract.earned(_user) >= _amount,
            "Not enough PINA points to enter the lottery"
        );
        softStakeContract.burnUserPoints(_user, _amount);
    }

    function setRandomGenerator(address _IRandomNumberGenerator)
        external
        onlyOwner
    {
        require(
            _IRandomNumberGenerator != address(0),
            "Contracts cannot be 0 address"
        );
        randomGenerator = IRandomNumberGenerator(_IRandomNumberGenerator);
    }

    function getLotteryInfo(uint256 _lotteryId)
        public
        view
        returns (LotteryInfo memory)
    {
        return (lotteryHistory[_lotteryId]);
    }

    function getNumberOfParticipants(uint256 _lotteryId)
        public
        view
        returns (uint256)
    {
        return lotteryHistory[_lotteryId].participantsCount.current();
    }

    modifier onlyRandomGenerator() {
        require(msg.sender == address(randomGenerator), "Only RNG address");
        _;
    }

    function setPrizes(uint256 _lotteryId, uint256[] calldata _prizeIds)
        public
        onlyOwner
    {
        require(
            _lotteryId <= lotteryCounter.current(),
            "Lottery id does not exist"
        );
        require(_prizeIds.length > 0, "No prize ids");
        prizes[_lotteryId] = _prizeIds;
        emit PrizesChanged(_lotteryId, prizes[_lotteryId].length);
    }

    function createNewLottery(
        uint256 _costPerTicketPinas,
        uint256 _costPerTicketCoins,
        uint256 _startingTime,
        uint256 _closingTime,
        IMemeXNFT _nftContract,
        uint256[] calldata _prizeIds,
        uint256 _boostCost,
        uint32 _maxParticipants
    ) public onlyOwner returns (uint256 lotteryId) {
        require(
            _startingTime != 0 && _startingTime < _closingTime,
            "Timestamps for lottery invalid"
        );
        // Incrementing lottery ID
        lotteryCounter.increment();
        lotteryId = lotteryCounter.current();
        Status lotteryStatus;
        if (_startingTime >= getCurrentTime()) {
            lotteryStatus = Status.Open;
        } else {
            lotteryStatus = Status.Planned;
        }
        // Saving data in struct
        LotteryInfo memory newLottery = LotteryInfo(
            lotteryId,
            lotteryStatus,
            _costPerTicketPinas,
            _costPerTicketCoins,
            _boostCost,
            _startingTime,
            _closingTime,
            _nftContract,
            Counters.Counter(0),
            Counters.Counter(0),
            _maxParticipants
        );
        prizes[lotteryId] = _prizeIds;
        emit PrizesChanged(lotteryId, _prizeIds.length);
        lotteryHistory[lotteryId] = newLottery;
    }

    function getCurrentLotteryId() public view returns (uint256) {
        return (lotteryCounter.current());
    }

    function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }

    function drawWinningNumbers(uint256 _lotteryId) external onlyOwner {
        require(
            _lotteryId <= lotteryCounter.current(),
            "Lottery id does not exist"
        );
        LotteryInfo storage lottery = lotteryHistory[_lotteryId];
        require(prizes[_lotteryId].length != 0, "No prizes for this lottery");
        // DISABLED FOR TESTS require(lottery.closingTime < block.timestamp);
        if (lottery.status == Status.Open) {
            lottery.status = Status.Closed;
        }
        require(
            lottery.status == Status.Closed,
            "Must be closed prior to draw"
        );
        requestId_ = randomGenerator.getRandomNumber(_lotteryId);
        // Emits that random number has been requested
        emit RequestNumbers(_lotteryId, requestId_);
    }

    function numbersDrawn(
        uint256 _lotteryId,
        bytes32 _requestId,
        uint256 _randomNumber
    ) external onlyRandomGenerator {
        emit ResponseReceived(_requestId);
        require(
            _lotteryId <= lotteryCounter.current(),
            "Lottery id does not exist"
        );
        LotteryInfo storage lottery = lotteryHistory[_lotteryId];
        require(lottery.status == Status.Closed, "Lottery must be closed");

        uint16 numberOfPrizes_ = uint16(prizes[_lotteryId].length);
        uint256 totalParticipants_ = lottery.participantsCount.current();
        uint256 totalEntries = lottery.entries.current();

        // if there are less participants than prizes, reduce the number of prizes
        if (totalParticipants_ < numberOfPrizes_) {
            numberOfPrizes_ = uint16(totalParticipants_);
        }
        // Loops through each prize assigning to a position on the entries array
        for (uint16 i = 0; i < numberOfPrizes_; i++) {
            // Encodes the random number with its position in loop
            bytes32 hashOfRandom = keccak256(
                abi.encodePacked(_randomNumber, i)
            );
            // Casts random number hash into uint256
            uint256 numberRepresentation = uint256(hashOfRandom);
            // Sets the winning number position to a uint16 of random hash number
            uint256 winningNumber = uint256(
                numberRepresentation.mod(totalEntries)
            );
            // defines the winner
            bool winnerFound = false;
            do {
                address winnerAddress = participantEntries[_lotteryId][
                    winningNumber
                ];
                ParticipantInfo storage participant = participants[_lotteryId][
                    winnerAddress
                ];
                if (participant.prizeId != 0) {
                    // If address is already a winner pick the next number until a new winner is found
                    winningNumber++;
                    winningNumber = winningNumber.mod(totalEntries);
                } else {
                    participant.prizeId = prizes[_lotteryId][i];
                    winnerFound = true;
                }
            } while (winnerFound == false);
        }
        lottery.status = Status.Completed;
        emit LotteryStatusChanged(_lotteryId, lottery.status);
    }

    function cancelLottery(uint256 _lotteryId) public onlyOwner {
        LotteryInfo storage lottery = lotteryHistory[_lotteryId];
        require(
            lottery.status != Status.Completed,
            "Lottery already completed"
        );
        lottery.status = Status.Canceled;
        emit LotteryStatusChanged(_lotteryId, lottery.status);
    }

    function buyTickets(uint256 _lotteryId, uint8 numberOfTickets)
        public
        payable
    {
        LotteryInfo storage lottery = lotteryHistory[_lotteryId];
        if (
            lottery.status == Status.Planned &&
            lottery.startingTime < block.timestamp
        ) {
            lottery.status = Status.Open;
            emit LotteryStatusChanged(_lotteryId, lottery.status);
        }
        if (
            lottery.status == Status.Open &&
            lottery.closingTime < block.timestamp
        ) {
            lottery.status = Status.Closed;
            emit LotteryStatusChanged(_lotteryId, lottery.status);
        }
        require(lottery.status == Status.Open, "Lottery not open");

        IRewards rewardsToken = softStakeContract.getRewardToken();

        uint256 totalCostInPoints = numberOfTickets * lottery.ticketCostPinas;
        if (totalCostInPoints > 0) {
            // if the pool in use is rewarding ERC-20 tokens we burn the ticket cost
            if (address(rewardsToken) != address(0)) {
                _burnPinasToken(msg.sender, rewardsToken, totalCostInPoints);
            } else {
                // if the pool is not using tokens we just handle the reward as points
                _burnUserPoints(msg.sender, totalCostInPoints);
            }
        }
        uint256 totalCostInCoins = numberOfTickets * lottery.ticketCostCoins;
        if (totalCostInCoins > 0) {
            require(
                msg.value >= totalCostInCoins,
                "Didn't transfer enough funds to buy tickets"
            );
        }
        ParticipantInfo memory participantStored = participants[_lotteryId][
            msg.sender
        ];
        if (participantStored.participantAddress == address(0)) {
            ParticipantInfo memory newParticipant = ParticipantInfo(
                msg.sender,
                false,
                0,
                false,
                numberOfTickets
            );
            lottery.participantsCount.increment();
            participants[_lotteryId][msg.sender] = newParticipant;
        } else {
            participantStored.entries += numberOfTickets;
        }
        for (uint8 i = 0; i < numberOfTickets; i++) {
            assignNewEntryToParticipant(_lotteryId, msg.sender);
        }
    }

    function assignNewEntryToParticipant(
        uint256 _lotteryId,
        address _participantAddress
    ) private {
        require(
            _lotteryId <= lotteryCounter.current(),
            "Lottery id does not exist"
        );
        ParticipantInfo storage participant = participants[_lotteryId][
            _participantAddress
        ];
        require(
            participant.participantAddress != address(0),
            "Participant not found"
        );
        LotteryInfo storage lottery = lotteryHistory[_lotteryId];
        participantEntries[_lotteryId][
            lottery.entries.current()
        ] = _participantAddress;
        emit NumberAssignedToParticipant(
            _lotteryId,
            lottery.entries.current(),
            _participantAddress
        );
        lottery.entries.increment();
    }

    function isBooster(uint256 _lotteryId, address _participantAddress)
        public
        view
        returns (bool)
    {
        require(
            _lotteryId <= lotteryCounter.current(),
            "Lottery id does not exist"
        );
        ParticipantInfo memory participant = participants[_lotteryId][
            _participantAddress
        ];
        return participant.isBooster;
    }

    function boostParticipant(uint256 _lotteryId, address _participantAddress)
        public
        payable
    {
        require(
            _lotteryId <= lotteryCounter.current(),
            "Lottery id does not exist"
        );
        ParticipantInfo storage participant = participants[_lotteryId][
            _participantAddress
        ];
        require(
            participant.participantAddress != address(0),
            "Participant not found"
        );
        require(
            participant.isBooster == false,
            "Participant already a booster"
        );
        // check if the transaction contains the boost cost
        require(
            msg.value >= lotteryHistory[_lotteryId].boostCost,
            "Not enough tokens to boost"
        );

        participant.isBooster = true;
        assignNewEntryToParticipant(_lotteryId, _participantAddress);
    }

    function isAddressWinner(uint256 _lotteryId, address _address)
        public
        view
        returns (
            bool,
            uint256,
            bool
        )
    {
        LotteryInfo memory lottery = lotteryHistory[_lotteryId];
        require(lottery.status == Status.Completed, "Lottery not completed");
        ParticipantInfo memory participant = participants[_lotteryId][_address];
        return (
            participant.prizeId != 0,
            participant.prizeId,
            participant.prizeClaimed
        );
    }

    function isCallerWinner(uint256 _lotteryId)
        public
        view
        returns (
            bool,
            uint256,
            bool
        )
    {
        return isAddressWinner(_lotteryId, msg.sender);
    }

    function redeemNFT(uint256 _lotteryId) public {
        require(
            lotteryHistory[_lotteryId].status == Status.Completed,
            "Status Not Completed"
        );
        ParticipantInfo storage participant = participants[_lotteryId][
            msg.sender
        ];
        require(!participant.prizeClaimed, "Participant already claimed prize");
        require(participant.prizeId != 0, "Participant is not a winner");
        participant.prizeClaimed = true;
        IMemeXNFT nftContract = lotteryHistory[_lotteryId].nftContract;
        nftContract.mint(msg.sender, participant.prizeId, 1, "", _lotteryId);
    }

    function withdraw(address payable _to, uint256 _amount) external onlyOwner {
        require(_amount <= address(this).balance);
        _to.transfer(_amount);
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewards {
    /**
     * Pina points earned by the player.
     */
    function earned(address account) external returns (uint256);

    function burnUserPoints(address account, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function burnPinas(address account, uint256 amount) external;

    function mintPinas(address recipient, uint256 amount) external;

    function getRewardToken() external view returns (IRewards);
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRandomNumberGenerator {
    /**
     * Requests randomness for a given lottery id
     */
    function getRandomNumber(uint256 lotteryId)
        external
        returns (bytes32 requestId);
}

pragma solidity >=0.6.0;

//SPDX-License-Identifier: MIT

interface IMemeXNFT {
    function mint(
        address _to,
        uint256 _id,
        uint256 _quantity,
        bytes calldata _data,
        uint256 _lotteryId
    ) external;

    function setBaseMetadataURI(string memory _newBaseMetadataURI) external;
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

