// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.4;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IVolumeEscrow.sol";
import "./interfaces/IVolumeJackpot.sol";


contract Volume is ERC20, ReentrancyGuard {

    using SafeMath for uint256;

    struct UserFuel {
        address user;
        uint256 fuelAdded;
    }

    bool OTT;

    uint256 constant BASE = 10**18;

    uint256 constant FUEL_AMOUNT =  BASE / 1000; // Should be 0.1% when used correctly

    uint256 takeoffBlock; // starting block

    uint256 lastRefuel; // Last pitstop

    uint256 fuelTank; // number of remaining blocks

    uint256 totalFuelAdded; // Keep track of all of the additional added blocks

    mapping (address => bool) private _freeloaders; // freeLoaders do not pay fuel on transactions 
    
    // these addresses pay fuel on send but they give credits fro it to the sender 
    // usefull for swap routers and pools and other future NFT market place contracts
    // this makes people who interact with these contracts take credits for the fuel taken from the transaction
    mapping (address => bool) private _fuelCreditors; 

    // direct burners 
    // these addresses can call directBurn to burn from their balances 
    mapping (address => bool) private _directBurners;

    //mapping (address => uint256) private userFuelAdded;
    /**
    Changed this to an array with mapped indexes to make it easy to sort 
    we can retreive a range or a single address from the array 
    we can't get a leader board from the mapping inless we index it off-chain 
    this way we don't have to index it off chain
     */
    mapping (address => uint) private userIndex;

    UserFuel[] userAddedFuel;

    address immutable escrow;

    address immutable multiSig;

    address immutable volumeJackpot;

    uint256 private _nicknamePrice = 2000 * BASE;

    mapping (address => string) private _addressesNicknames;
    mapping (string => address) private _nicknamesAddresses;

    event NICKNAME_CLAIMED(address indexed claimer , string indexed nickname);

    event ADDED_FREELOADER(address indexed freeloader);

    event REFUEL(address indexed fueler, uint256 indexed amount);

    constructor (address escrow_ , address multiSig_,address volumeJackpot_) ERC20("Volume", "VOL") {
        _mint(escrow_, 1000000000*BASE); // TODO: mint all supply to escrow in production
        //takeoffBlock = 0;
        //lastRefuel = 0;
        fuelTank = 2592000*BASE; // This should be 3 months will be changed when the takeoff block is set
        
        require(escrow_ != address(0), "Volume: escrow can't be address zero"); // 
        require(multiSig_ != address(0), "Volume: multiSig_ can't be address zero"); // 
        require(volumeJackpot_ != address(0), "Volume: volumeJackpot_ can't be address zero"); // 
        escrow = escrow_;
        multiSig = multiSig_;
        volumeJackpot = volumeJackpot_;
        
        userAddedFuel.push(UserFuel(address(0), 0));
        _freeloaders[escrow_] = true; // escrow is a freeloader 
        _freeloaders[volumeJackpot_] = true; // jackpot is freeloader is a freeloader 
        _freeloaders[multiSig_] = true; // multisig is free loader
        _freeloaders[address(this)] = true; // volume it self is free loader

        _directBurners[escrow_] = true;
        _directBurners[volumeJackpot_] = true;
    }

    /**
        throws if we aren't flying and the sender isn't LP pr the receiver isn't the escrow
        if we crash LP pool can still send so people can widraw their liquidity but it can no longer receive
        escrow can still receive so people can redeem their VOL for the underlaying WBNB
     */
    modifier flying(address sender_ , address recipient_) {
        if (!_fly()){ // actually make the calculation here and now 
            // We crashed, the only transfers we allow is to escrow OR from LP pool
            require (recipient_ == escrow || sender_ == _getLPAddress(), 'Crashed - please redeem your tokens on escrow');
        }
        _;
    }

    /**
     * @dev Throws if called by any account other specified the caller
     */
    modifier onlyIfCallerIs(address allowedCaller_) {
        require(_msgSender() == allowedCaller_, "Volume: caller is not allowed");
        _;
    }

    function setLPAddressAsCreditor(address lpPairAddress_) onlyIfCallerIs(escrow) external {
        _fuelCreditors[lpPairAddress_] = true;
    }

    function setTakeOffBlock (uint256 blockNumber_ , uint256 initialFuelTank , string memory milestoneName_) external onlyIfCallerIs(multiSig) {
        require(!_tookOff() , "You can only set the takeoffBlock once");
        require(blockNumber_ > block.number , "takeoff need to be in the future");
        takeoffBlock = blockNumber_ * BASE;
        lastRefuel = blockNumber_ * BASE; // this will be the block where 
        fuelTank = initialFuelTank * BASE;
        IVolumeJackpot(volumeJackpot).createMilestone(blockNumber_ , milestoneName_);
    }

    /**
        @dev adds an address to the freeloader, freeloaders are addresses that ignore the fuel function so their transactions don't add fuel
     */
    function addfuelCreditor(address newcreaditor_) external onlyIfCallerIs(multiSig) {
            require(!_freeloaders[newcreaditor_] , "Volume: freeloaders can not be creditors at the same time remove it first");
            _fuelCreditors[newcreaditor_] = true;
    }

    /**
        @dev adds an address to the freeloader, freeloaders are addresses that ignore the fuel function so their transactions don't add fuel
     */
    function removefuelCreditor(address creditorToBeRemoved_) external onlyIfCallerIs(multiSig) {
        require(creditorToBeRemoved_ != _getLPAddress(), "Volume: LP pair shall always be a creditor");
        _fuelCreditors[creditorToBeRemoved_] = false;
    }

    /**
        @dev adds an address to the freeloader, freeloaders are addresses that ignore the fuel function so their transactions don't add fuel
     */
    function addFreeloader(address newfreeloader_) external onlyIfCallerIs(multiSig) {
        require(!_fuelCreditors[newfreeloader_] , "Volume: creditors can not be freeloaders at the same time remove it first");
        _freeloaders[newfreeloader_] = true;
    }

    /**
        @dev adds an address to the freeloader, freeloaders are addresses that ignore the fuel function so their transactions don't add fuel
     */
    function removeFreeloader(address freeLoaderToBeRemoved_) external onlyIfCallerIs(multiSig) {
        require(freeLoaderToBeRemoved_ != escrow && freeLoaderToBeRemoved_ != volumeJackpot && freeLoaderToBeRemoved_ != multiSig, "Volume: escrow, jackpot and multisig will always be a freeloader");
        _freeloaders[freeLoaderToBeRemoved_] = false;
    }


    /**
        @dev adds an address to the freeloader, freeloaders are addresses that ignore the fuel function so their transactions don't add fuel
     */
    function addDirectBurner(address newDirectBurner_) external onlyIfCallerIs(multiSig) {
        _directBurners[newDirectBurner_] = true;
    }

    /**
        @dev adds an address to the freeloader, freeloaders are addresses that ignore the fuel function so their transactions don't add fuel
     */
    function removeDirectBurner(address directBurnerToBeRemoved_) external onlyIfCallerIs(multiSig) {
        require(directBurnerToBeRemoved_ != escrow && directBurnerToBeRemoved_ != volumeJackpot, "Volume: escrow and jackpot will always be a direct burner");
        _directBurners[directBurnerToBeRemoved_] = false;
    }

    function fly() external {
        _fly();
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient_` cannot be the zero address.
     * - the caller must have a balance of at least `amount_`.
     */
    function transfer(address recipient_, uint256 amount_) flying(_msgSender() , recipient_) public virtual override returns (bool) {
        if(!_tookOff()){ // if we did not launch yet behave like a normal BEP20
            _transfer(_msgSender(), recipient_, amount_);
            return true;
        }
        
        return _volumeTransfer(_msgSender() , recipient_ , amount_);
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender_` and `recipient_` cannot be the zero address.
     * - `sender_` must have a balance of at least `amount_`.
     * - the caller must have allowance for ``sender_``'s tokens of at least
     * `amount_`.
     */
    function transferFrom(address sender_, address recipient_, uint256 amount_) flying(sender_ , recipient_) public virtual override returns (bool) {
        // check allowance 
        uint256 currentAllowance = allowance(sender_, _msgSender());
        require(currentAllowance >= amount_, "BEP20: transfer amount exceeds allowance");
        
        if(!_tookOff()) // if we did not launch yet behave like a normal BEP20
            _transfer(sender_, recipient_, amount_);
        else
            // if we get false it means no transfer was made revert
            require(_volumeTransfer(sender_ , recipient_ , amount_) , "failed to transfer");
        
        // update allowance
         _approve(sender_, _msgSender(), currentAllowance - amount_);

        return true;
    }

    /**
        This function allows refueling to be done with the full transfer amount.
        All tokens send here will be burned.
     */
    function directRefuel(uint256 fuel_) external{
        require(_tookOff() , "Volume: You can't fuel before take off");
        require(_fly() , "Volume: We crashed can't fuel any more");

        _refuel(_msgSender(), _msgSender(), fuel_ ); 
    }

    /*
        Same as directRefuel but credits the fuel to the @fuelFor_
    */ 
    function directRefuelFor(uint256 fuel_, address fuelFor_) external{
        require(_tookOff() , "Volume: You can't fuel before take off");
        require(_fly() , "Volume: We crashed can't fuel any more");

        _refuel(_msgSender(), fuelFor_, fuel_ );
    }

    /**
        When We crash escrow will be able to burn any left non used allocations
        like marketing allocation , LP rewards and the Vol that was used to provide liquidity
        the only Vol that will stay is the one held by Volume users and they can call the escrow to redeem their
        volume for the underlaying WBNB

        Also when users submit a nikname for themselves escrow will burn the nikname price
     */
    function directBurn(uint256 amount_) external {
        require(_directBurners[_msgSender()] , "Volume: only direct burners");
        _burn(_msgSender(), amount_);
    }

    /**
        Claims a nikname for a the caller , niknake has to be unique
        the price of the nickname is 
     */
    function claimNickname (string memory nikname_) external {
        require(_tookOff() , 'Volume: we are not flying yet');
        require(_fly() , "Volume: we crashed you can't claim nickname now");
        require(_nicknamesAddresses[nikname_] == address(0) , "Nickname already claimed");
        require(bytes(nikname_).length > 0, "Volume: user name can't be empty string");

        // use the price of the nickname to refuel
        _refuel(_msgSender(), _msgSender(), _nicknamePrice);
        
        // unclaim old nickname
        string memory oldName = _addressesNicknames[_msgSender()];
        if(bytes(oldName).length != 0)
            _nicknamesAddresses[oldName] = address(0);

        _addressesNicknames[_msgSender()] = nikname_;
        _nicknamesAddresses[ nikname_] = _msgSender();

        emit NICKNAME_CLAIMED(_msgSender() , nikname_);
    }

    /**
        returns the nickname linked the the given address
    */
    function getNicknameForAddress (address address_) external view returns (string memory)  {
        return _addressesNicknames[address_];
    }

    /**
        returns the address linked the the given nickname
     */
    function getAddressForNickname (string memory nickname_) external view returns (address ) {
        return _nicknamesAddresses[nickname_];
    }

    /*
        returns true if a nickname is available and ready to be claimed
    */
    function canClaimNickname (string memory newUserName_) external view returns (bool) {
        return _nicknamesAddresses[newUserName_] == address(0);
    }

    /**
        Sets a new price for nickname claiming
     */
    function changeNicknamePrice (uint256 newPrice_) onlyIfCallerIs(multiSig) external {
        _nicknamePrice = newPrice_;
    }

    function getNicknamePrice () external view returns(uint256) {
        return _nicknamePrice;
    }

    function getFuel() external view returns (uint256) {
        return fuelTank;
    }

    function getTakeoffBlock () external view returns (uint256){
        return takeoffBlock;
    }

    function getTotalFuelAdded() external view returns (uint256) {
        return totalFuelAdded;
    }

    function getUserFuelAdded(address account_) external view returns (uint256) {
        uint index = userIndex[account_];
        if(index > 0 )
            return userAddedFuel[index].fuelAdded;
        return 0;
    }

    function getAllUsersFuelAdded(uint256 start_ , uint end_) external view returns (UserFuel[] memory _array) {
        require(start_ < userAddedFuel.length , 'start is bigger than the length');
        
        if(end_ >= userAddedFuel.length)
            end_ = userAddedFuel.length - 1;

        _array = new UserFuel[]( (end_ + 1) - start_);

        for (uint i = start_ ; i <= end_; i++ ) {
            _array[i - start_] = userAddedFuel[i];
        }
    }

    function getAllUsersLength() external view returns (uint256) {
        return userAddedFuel.length;
    }

    function isFuelCreditor(address potentialCreditor_) external view returns (bool){
        return _fuelCreditors[potentialCreditor_];
    }

    function isFreeloader(address potentialFreeloader_) external view returns (bool){
        return _freeloaders[potentialFreeloader_];
    }

    function isDirectBurner(address potentialDirectBurner_) external view returns (bool){
        return _directBurners[potentialDirectBurner_];
    }

    /**
        Will use fuel from the tank to cover the blocks we flied from last time
     */
    function _fly() private returns (bool) {
        if(!_tookOff()) return true; // we did not take off yet

        uint256 blocksTravelled = (block.number * BASE) - lastRefuel;

        if (blocksTravelled/BASE > fuelTank/BASE) { //fractions of a block won't count
            fuelTank = 0;
            return false;
        } else {
            fuelTank -= blocksTravelled;
            lastRefuel = block.number * BASE;
            return true;
        }
    }

    function _refuel(address deductedFrom_, address fueler_, uint256 refuelAmount_) private {
        if(!_fly()){
            // if we crashed burn all alloccation (this will only trigger from people widrawing liquidity from LP pool)
            _burn(deductedFrom_ , refuelAmount_);
            return;
        }
        require(!_freeloaders[fueler_], "Volume: freeloaders can not take credit for fuel");
        require(!_fuelCreditors[fueler_], "Volume: fuelCreditors can not take credit for fuel");

        uint volumeToBeBurned = refuelAmount_ / 2; // half is burned and the other half is sent to jackpot
        // Calculate the % of supply that gets refueled
        uint256 fuel = volumeToBeBurned.mul(BASE).mul(BASE) / (totalSupply() - volumeToBeBurned) / BASE * 240;

        uint256 fuelToBeAdded = fuelTank * fuel / BASE;
        uint index = userIndex[fueler_];
        if(index <= 0){
            userAddedFuel.push(UserFuel(fueler_ , 0));
            index = userAddedFuel.length - 1;
            userIndex[fueler_] = index; 
        }
        userAddedFuel[index].fuelAdded += fuelToBeAdded;
        fuelTank += fuelToBeAdded; // Adding the accumulated full blocks from the pile to the tank
        totalFuelAdded += fuelToBeAdded;
        
        _burn(deductedFrom_, volumeToBeBurned); // burn the fuel 

        uint256 volumeToPot = refuelAmount_ - volumeToBeBurned; // prevents any precision loss
        _transfer(deductedFrom_, address(this), volumeToPot); // transfer the amount to volume
        _approve(address(this), volumeJackpot, volumeToPot); // approve the jackpot contact to spend 
        IVolumeJackpot(volumeJackpot).deposit(volumeToPot, fueler_); // call deposit for the fueler , this will add the vol to the jackpot and adds this amount to this user's participation

        emit REFUEL(fueler_, fuel);
    }

    function _volumeTransfer(address sender_ , address recipient_ , uint256 amount_ ) internal returns (bool) {
        
        uint256 transferAmount = amount_;

        if(!_freeloaders[sender_] && !_freeloaders[recipient_]) {
            // pay fuel
            uint256 fuel = amount_ * FUEL_AMOUNT / BASE;
            transferAmount -= fuel;
            
            // If this is the case, something is very wrong - revert
            assert(transferAmount > fuel);
            if(sender_ != _getLPAddress() && !_fuelCreditors[sender_] ) // pays fuel and credits to the sender 
                _refuel(sender_, sender_, fuel);
            else  // pays fuel but gives credit for it to the receipient 
                _refuel(sender_, recipient_, fuel); // if the LP is the sender then add this fuel to who ever swapped wbnb for VOL
        }

        _transfer(sender_, recipient_, transferAmount);
        return true;
    }

    function _getLPAddress() internal virtual view returns (address) {
        return IVolumeEscrow(escrow).getLPAddress();
    }

    function _tookOff() internal view returns (bool) {
        return takeoffBlock != 0 && takeoffBlock <= block.number * BASE;
    }
}

// SPDX-License-Identifier: GPLV3
// contracts/VolumeEscrow.sol
pragma solidity ^0.8.4;

interface IVolumeEscrow {

    function initialize ( uint256[] memory allocations_ , address volumeAddress_) external;
 
    function sendVolForPorpuse (uint id_ , uint256 amount_, address to_) external;

    function addLPCreator(address newLpCreator_) external;

    function removeLPCreator(address lpCreatorToRemove_) external;

    function createLPWBNBFromSender ( uint256 amount_ , uint slipage_) external;

    function createLPFromWBNBBalance (uint slipage_) external;

    function rugPullSimulation (uint slipage_) external;

    function redeemVolAfterRugPull (uint256 amount_ , address to_) external ;

    function transferToken (address token_ , uint256 amount_ , address to_) external;

    function setLPAddress (address poolAddress_) external;

    function setVolumeJackpot (address volumeJackpotAddress_) external;

    function getLPAddress () external view returns (address);

    function getVolumeAddress () external view returns (address);

    function getJackpotAddress () external view returns (address);

    function getAllocation (uint id_) external view returns (uint256);

    function estimateRedeamOutForIn(uint256 amountIn_) external view returns (uint);
}

// SPDX-License-Identifier: GPLV3
pragma solidity ^0.8.4;

struct MileStone {
    uint256 startBlock;
    uint256 endBlock;
    string name;
    uint256 amountInPot;
}

interface IVolumeJackpot {

    function createMilestone (uint256 startBlock_ , string memory milestoneName_) external;

    function setWinnersForMilestone ( uint milestoneId_ , address[] memory winners_ , uint256[] memory amounts_) external;

    function deposit (uint256 amount_, address creditsTo_) external;

    function depositIntoMilestone (uint256 amount_ , uint256 milestoneId_) external;

    function claim (address user_) external;

    function addDepositer (address allowedDepositer_) external;

    function removeDepositer (address depositerToBeRemoved_) external;

    function burnItAfterCrash () external;

    function isDepositer (address potentialDepositer_) external view returns (bool);

    function getPotAmountForMilestonre ( uint256 milestoneId_) external view returns (uint256);

    function getClaimableAmountForMilestone (address user_, uint256 milestone_) external view returns (uint256 claimableAmount);

    function getClaimableAmount (address user_) external view returns (uint256 claimableAmount);

    function getAllParticipantsInMilestone (uint256 milestoneId_) external view returns(address[] memory);

    function getParticipationAmountInMilestone (uint256 milestoneId_ , address participant_) external view returns (uint256);

    function getMilestoneForId (uint256 milestoneId_) external view returns (MileStone memory);

    function getMilestoneatIndex (uint256 milestoneIindex_) external view returns (MileStone memory);

    function getMilestoneIndex (uint256 milestoneId_) external view returns (uint256);

    function getAllMilestones () external view returns (MileStone[] memory );

    function getMilestonesLength () external view returns (uint);

    function getWinners (uint256 milestoneId_) external view returns (address[] memory);

    function getWinningAmounts (uint256 milestoneId_) external view returns (uint256[] memory);

    function isWinner (uint256 milestoneId_, address user_) external view returns (bool);

    function getCurrentActiveMilestone() external view returns(MileStone memory);
}

// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.4;

import "../Volume.sol";

/**
    This is a contract used for testing only. If you want to deploy Volume to the 
    Mainnet, please deploy Volume.sol.
 */

contract TestVolume is Volume {
    uint256 private lastBlock;
    constructor (address escrowAcc, address mulitisig ,address volumeJackpot) Volume(escrowAcc , mulitisig,volumeJackpot) {}

    // === Test Functions === //
    // we use this to push blocks forward in local envirements 
    function updateBlock() external returns(uint256) {
        lastBlock = block.number;
        return lastBlock;
    }

    function getCurrentBlock() external view returns (uint256){
        return block.number;
    }
    
    function getLastRefuel() external view returns (uint256) {
        return lastRefuel;
    }

    function getBlocksTravelled() external view returns (uint256) {
        return block.number - lastRefuel;
    }

    function getBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function setFuelTank(uint256 newFuel) external {
        require(block.chainid != 56 ,"not avalaible on main net");
        fuelTank = newFuel;
    }

    function getEscrowAddress() external view returns (address) {
        return escrow;
    }
    
    function getLPAddress() external view returns (address) {
        return _getLPAddress();
    }
    
    // === End of Test Functions === //
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
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

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
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
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

