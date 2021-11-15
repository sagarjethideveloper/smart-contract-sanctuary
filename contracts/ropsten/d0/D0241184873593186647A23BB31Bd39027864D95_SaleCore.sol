// SPDX-License-Identifier: MIT // TBC
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
 
contract A999Token is ERC20, Pausable, ReentrancyGuard, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    // ------------------- constants  -------------------

    uint256 private constant _initialSupply = 300000000 * 1e18;         // mint 300M of tokens on day-0
        
    // ------------------- managable attributes -------------------

    uint8 private _feeBurnPerMille = 10;                        // %% of a transfer thet gets burned until _minimumSupply is reached; e.g. 10 == 1%
    uint256 private _minimumSupply = 100000000 * 1e18;          // stop burning when supply reaches 100M
    
    uint8 private _feeRewardPerMille = 10;                       // %% of a transfer that goes to rewarding wallet (and eventually will be distributed among holders); e.g. 10 == 1%
    address private _walletReward = address(0);                  // the contract address has to be set for the rewarding to take place. [TBD: vs wallet adress - to be designed]
    
    uint8 private _whaleThresholdPerMille = 10;                 // %% of curent supply that makes sender of a transfer a whale

    EnumerableSet.AddressSet private _accountsExcludedFromFee;  // the set should be used to manage exchange liquidity pool wallets etc. ; contract owner is also added here during deployment.

    // ------------------- non-managable attributes -------------------

    EnumerableSet.AddressSet private _potentialHolders;
    address[] private _holders;

    // ------------------- generated events  -------------------

    event AccountAddedToFeeExclusionList(address indexed account);        
    event AccountRemovedFromFeeExclusionList(address indexed account);    
    event WalletRewardUpdatedTo(address indexed newWalletReward);
    event MinimumSupplyUpdatedTo (uint256 newMinimumSupply);
    event FeeBurnPerMilleUpdatedTo (uint8 newFeeBurnPerMille);
    event FeeRewardPerMilleUpdatedTo (uint8 newFeeRewardPerMille);
    event WhaleThresholdPerMilleUpdatedTo (uint8 newWhaleThresholdPerMille);

    // ------------------- deployment logic  -------------------

    constructor() ERC20("A999 Token", "A999") {
        _mint(address(this), _initialSupply);
        _approve(address(this), _msgSender(), _initialSupply);
        addAddressToFeeExclusionList (_msgSender());            // exclude owner from fees
        addAddressToFeeExclusionList (address(this));            // exclude contract from fees
    }

    // ------------------- getters and setters  -------------------

    // --- initial supply

    function initialSupply() public pure returns (uint256) {
        return _initialSupply;
    }

    // --- fee burn per mille

    function feeBurnPerMille() public view returns (uint8) {
        return _feeBurnPerMille;
    }
    function setFeeBurnPerMille(uint8 newFeeBurnPerMille) public onlyOwner {
        require (newFeeBurnPerMille >= 0 && newFeeBurnPerMille <= 1000, 'A999Token: fee burn per-mille outside of <0;1000> range');
        _feeBurnPerMille = newFeeBurnPerMille;
        emit FeeBurnPerMilleUpdatedTo(newFeeBurnPerMille);
    }

    // --- fee reward per mille

    function feeRewardPerMille() public view returns (uint8) {        
        return _feeRewardPerMille;
    }
    function setFeeRewardPerMille(uint8 newFeeRewardPerMille) public onlyOwner {
        require (newFeeRewardPerMille >= 0 && newFeeRewardPerMille <= 1000, 'A999Token: fee reward per-mille outside of <0;1000> range');
        _feeRewardPerMille = newFeeRewardPerMille;
        emit FeeRewardPerMilleUpdatedTo(newFeeRewardPerMille);
    }

    // --- whale threshold per mille

    function whaleThresholdPerMille() public view returns (uint8) {        
        return _whaleThresholdPerMille;
    }
    function setWhaleThresholdPerMille(uint8 newWhaleThresholdPerMille) public onlyOwner {
        require (newWhaleThresholdPerMille >= 0 && newWhaleThresholdPerMille <= 1000, 'A999Token: whale threshold per-mille outside of <0;1000> range');
        _whaleThresholdPerMille = newWhaleThresholdPerMille;
        emit WhaleThresholdPerMilleUpdatedTo(newWhaleThresholdPerMille);
    }    

    // --- minimum supply

    function minimumSupply() public view returns (uint256) {
        return _minimumSupply;
    }    
    function setMinimumSupply(uint256 newMinimumSupply) public onlyOwner {
        require (totalSupply() >= newMinimumSupply, "A999Token: minimum supply greater than total supply");
        _minimumSupply = newMinimumSupply;
        emit MinimumSupplyUpdatedTo(newMinimumSupply);
    }

    // --- wallet reward

    function walletReward() public view returns (address) {
        return _walletReward;
    }
    function setWalletReward(address newWalletReward) public onlyOwner {
        if (_walletReward != address(0)) {
            removeAddressFromFeeExclusionList (_walletReward);
        }
        if (newWalletReward != address(0)) {
            addAddressToFeeExclusionList (newWalletReward);
        }
        _walletReward = newWalletReward;        
        emit WalletRewardUpdatedTo(newWalletReward);
    }

    // ------------------- manage account exclusion list  -------------------

    function _isSenderOrRecipientExcludedFromTransferFee (address sender, address recipient) internal view returns (bool) {
        return _accountsExcludedFromFee.contains(sender) || _accountsExcludedFromFee.contains(recipient);
    }

    function isExcludedFromTransferFee (address account) public view returns (bool) {
        return _accountsExcludedFromFee.contains(account);
    }

    function addAddressToFeeExclusionList (address addressExcluded) public onlyOwner {
        bool added = _accountsExcludedFromFee.add (addressExcluded);
        if (added)
            emit AccountAddedToFeeExclusionList (addressExcluded);            
    }

    function removeAddressFromFeeExclusionList (address addressIncluded) public onlyOwner {
        bool removed = _accountsExcludedFromFee.remove (addressIncluded);
        if (removed)
            emit AccountRemovedFromFeeExclusionList (addressIncluded);            
    }

    // ------------------- transfer custom logic -------------------

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {        
        _potentialHolders.add(to);
        super._beforeTokenTransfer(from, to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override nonReentrant whenNotPaused {        
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(balanceOf(sender) >= amount, "ERC20: transfer amount exceeds balance");

        require(!isWhaleTransfer(sender, recipient, amount), "Whales are not welcome by 3TON community!");

        uint256 adjustedAmount = _processTransferFee(sender, recipient, amount);

        super._transfer(sender, recipient, adjustedAmount);

        // --- ensure that tokens booked in contract address will be available
        if (recipient == address(this)) {
            _approve(recipient, owner(), adjustedAmount);
        }
    }

    function _processTransferFee(address sender, address recipient, uint256 amount) internal whenNotPaused returns (uint256) {                
        // --- mind exclusion list
        if (_isSenderOrRecipientExcludedFromTransferFee (sender, recipient)) 
            return amount;

        uint256 burnAmount = amount * _feeBurnPerMille / 1000;
        uint256 rewardAmount = amount * _feeRewardPerMille / 1000;
        uint256 adjustedAmount = amount;

        // --- burn ---
        if (canBurn(burnAmount)) {
            _burn(sender, burnAmount);
            adjustedAmount -= burnAmount;
        }

        // --- reward ---
        if (_walletReward != address(0)) {                       // if the rewarding wallet is not set, the rewarding fee will not be taken from the transfer.
            super._transfer(sender, _walletReward, rewardAmount);
            adjustedAmount -= rewardAmount;
        }

        // --- amount left for the recipient
        return adjustedAmount;
    }

    function isWhaleTransfer(address sender, address recipient, uint256 amount) internal view returns (bool) {
        // accounts listed on exclusion list can't be considered as whales.
        if (_isSenderOrRecipientExcludedFromTransferFee (sender, recipient)) {
            return false;
        }         
        return amount >= totalSupply() * _whaleThresholdPerMille / 1000;
    }

    // ------------------- arsonist alley -------------------
    
    function burn(uint256 amount) external nonReentrant whenNotPaused {
        require (isBurningAllowed(), "A999Token: the total supply has already reached its minimum");
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public whenNotPaused {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "A999Token: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }

    function _burn(address account, uint256 amount) internal override whenNotPaused {        
        require (canBurn(amount), "A999Token: buring this amount would decrease the total supply below defined minimum");
        super._burn(account, amount);
    }

    function applyPhoenixProtocol (uint256 amount) public nonReentrant onlyOwner whenNotPaused {
        require (totalSupply() + amount > _initialSupply, "A999Token: cannot exceed initial supply");
        _mint(address(this), amount);
        _approve(address(this), owner(), amount);
    }

    function _maxBurningAmount() internal view returns (uint256){
        return totalSupply() - _minimumSupply;
    }

    function isBurningAllowed() public view returns (bool){
        return _maxBurningAmount() > 0;
    }

    function canBurn(uint256 amount) public view returns (bool){
        return _maxBurningAmount() >= amount;
    }
    
    // ------------------- emergency - pause / unpase the contract  -------------------

    // the pausing affects only methods with whenNotPaused / whenPaused modifiers:
    // transfers, burning, minting

    function emergencyPause() public onlyOwner {
        _pause();
    }

    function emergencyUnpause() public onlyOwner {
        _unpause();
    }

    // ------------------- bulk tokens distribution -------------------

    function distributeContractTokens(address[] memory receivers, uint256[] memory amounts) public onlyOwner whenNotPaused {
        _distribute (address(this), receivers, amounts);
    }

    function distributeMyTokens(address[] memory receivers, uint256[] memory amounts) public whenNotPaused {
        _distribute (_msgSender(), receivers, amounts);
    }

    function _distribute(address source, address[] memory receivers, uint256[] memory amounts) internal whenNotPaused {
        for(uint8 i = 0; i < receivers.length; i++) {
            super._transfer(source, receivers[i], amounts[i]);
        }
    }
    
    // ------------------- retrieve holders eligible for reward -------------------

    function getHolders (uint256 minimalHoldings) public returns (address[] memory) {
        delete _holders;
        for (uint256 i = 0; i < _potentialHolders.length(); i++) {
            address potentialHolder = _potentialHolders.at(i);
            if (balanceOf(potentialHolder) >= minimalHoldings) {
                _holders.push(potentialHolder);
            }
        }
        return _holders;
    }
}

// SPDX-License-Identifier: MIT // TBC
pragma solidity 0.8.4;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./A999Token.sol";

contract SaleCore is Pausable, ReentrancyGuard, Ownable{
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    // ------------------- constants  -------------------


    // ------------------- managable attributes -------------------

    EnumerableSet.AddressSet private _whitelistedAccounts;
    address payable private _ethBeneficiary;
    A999Token _token;

    // -------------------- non-managable storage --------------------

    mapping(address => uint256) private _balances;
    EnumerableSet.AddressSet private _buyers;

    uint256 private _saleAmount;

    address[] private _distributionBuyers;
    uint256[] private _distributionAmounts;

    // ------------------- generated events  -------------------

    event AccountAddedToWhiteList(address indexed account);
    event AccountRemovedFromWhiteList(address indexed account);
    event TokensPurchased(address indexed account, uint256 tokenAmount);
    
    constructor() {
        _ethBeneficiary = payable(_msgSender());                     
    }

    // ------------------- getters and setters  -------------------

    // --- eth beneficiary

    function getEthBeneficiary() public view returns(address payable) {
        return _ethBeneficiary;
    }

    function setEthBeneficiary(address payable newBeneficiary) public onlyOwner {   // TBC - if splitter set in constructor, then maybe we shouldn't be able to manage afterwards
        _ethBeneficiary = newBeneficiary;
    }

    // --- token reference

    function getTokenAddress() public view returns(address) {
        return address(_token);
    }

    function setToken(address tokenAddress) public onlyOwner {
        _token = A999Token(tokenAddress);
    }

    // --- total sale amount

    function getTotalSaleAmount() public view returns(uint256) {
        return _saleAmount;
    }

    // ------------------- manage account white list  -------------------

    function _isAccountWhitelisted (address account) internal view returns (bool) {
        return _whitelistedAccounts.contains(account);
    }

    function addAddressToWhiteList (address addressWhitelisted) public onlyOwner {
        bool added = _whitelistedAccounts.add (addressWhitelisted);
        if (added)
            emit AccountAddedToWhiteList (addressWhitelisted);            
    }

    function removeAddressFromFeeExclusionList (address addressNotWhitelisted) public onlyOwner {
        bool removed = _whitelistedAccounts.remove (addressNotWhitelisted);
        if (removed)
            emit AccountRemovedFromWhiteList (addressNotWhitelisted);        
    }

    // ------------------- purchase logic  -------------------

    receive() external payable {                                        // TBC: add buyTokens(n) -> returning surplus of ETH if any
        uint256 ethAmountSent = msg.value;
        uint256 currTime = block.timestamp;
        require (isSaleOpen(currTime), "The sale is currently closed");
        require (isEthAmountInCurrentlyAllowedRange(currTime, ethAmountSent), "The ETH amount is not within currently allowed range");
        require (isPurchaseCurrentlyAllowedForAccount(currTime, _msgSender()), "The purchase is currently not allowed for sender account");
        uint256 curr3TonEthRate = getCurrent3TonEthRate(currTime);
        uint256 purchasedTokens = curr3TonEthRate * ethAmountSent;      
        require (areTokensStillAvailable(currTime, purchasedTokens), "There aren't enough tokens left for the purchase");
        _purchase (currTime, _msgSender(), purchasedTokens);        
    }

    function _purchase (uint256 currTime, address account, uint256 tokenAmount) internal nonReentrant {
        _buyers.add (account);
        _balances [account] += tokenAmount;
        _saleAmount += tokenAmount;
        emit TokensPurchased (account, tokenAmount);
    }

    function isSaleOpen(uint256 currTime) public view returns(bool) {
        return true;                                            // TODO: IMPLEMENT!
    }

    function isEthAmountInCurrentlyAllowedRange(uint256 currTime, uint256 ethAmount) internal view returns(bool) {
        return true;                                            // TODO: IMPLEMENT!
    }

    function isPurchaseCurrentlyAllowedForAccount(uint256 currTime, address account) internal view returns(bool) {
        return (!isCurrentlyWhitelistingRequired(currTime) || 
                _isAccountWhitelisted (account));

    }

    function isCurrentlyWhitelistingRequired(uint256 currTime) internal view returns(bool) {
        return false;                                           // TODO: IMPLEMENT!
    }

    function getCurrent3TonEthRate (uint256 currTime) internal view returns (uint256) {
        return 10203;                                           // TODO: IMPLEMENT!
    }
    
    function getCurrent3TonEthRate() public view returns (uint256) {
        uint256 currTime = block.timestamp;
        return getCurrent3TonEthRate(currTime);
    }

    function areTokensStillAvailable(uint256 currTime, uint256 purchasedTokens) internal view returns(bool) {
        bool areTokensAvailable = purchasedTokens + _saleAmount <= _token.balanceOf(address(this));

        // TODO: IMPLEMENT further checks - sale stage caps;

        return areTokensAvailable;
    }

    // ------------------- finalization logic  -------------------

    function retriveETH(uint256 amount) public onlyOwner {
        // TBC: possible only after the sale is over?
        require(amount >= address(this).balance, "Requested amount exceeds available balance");

        _ethBeneficiary.transfer(address(this).balance);
    }

    function distributePurchasedTokens() external onlyOwner {
        require (_distributionBuyers.length == 0, "Tokens are already distributed");     

        for (uint256 i = 0; i < _buyers.length(); i++) {
            address buyer = _buyers.at(i);
            _distributionBuyers.push(buyer);
            _distributionAmounts.push(_balances[buyer]);
        }
        _token.distributeMyTokens(_distributionBuyers, _distributionAmounts);
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

import "../utils/Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor () {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
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

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

