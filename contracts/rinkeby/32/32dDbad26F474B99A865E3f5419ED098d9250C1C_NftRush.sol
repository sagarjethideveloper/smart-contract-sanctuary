// contracts/Crowns.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.6.7;

import "./../../../../openzeppelin/contracts/access/Ownable.sol";
import "./../../../../openzeppelin/contracts/GSN/Context.sol";
import "./../../../../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../../../../openzeppelin/contracts/math/SafeMath.sol";
import "./../../../../openzeppelin/contracts/utils/Address.sol";

/// @title Official token of the Seascape ecosystem.
/// @author Medet Ahmetson
/// @notice Crowns (CWS) is an ERC-20 token with a PayWave feature.
/// PayWave is a distribution of spent tokens among all current token holders.
/// In order to appear in balance, the paywaved tokens need
/// to be claimed by users by triggering any transaction in the ERC-20 contract.
/// @dev Implementation of the {IERC20} interface.
contract CrownsToken is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    struct Account {
        uint256 balance;
        uint256 lastPayWave;
    }

    mapping (address => Account) private _accounts;
    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private constant _name = "Crowns";
    string private constant _symbol = "CWS";
    uint8 private immutable _decimals = 18;

    uint256 private constant MIN_SPEND = 10 ** 6;
    uint256 private constant SCALER = 10 ** 18;
    uint256 private constant TEN_MILLION = SCALER * 1e7;


    /// @notice Total amount of tokens that have yet to be transferred to token holders as part of the PayWave.
    /// @dev Used Variable tracking unclaimed PayWave token amounts.
    uint256 public unclaimedPayWave = 0;
    /// @notice Amount of tokens spent by users that have not been paywaved yet.
    /// @dev Calling the payWave function will move the amount to {totalPayWave}
    uint256 public unconfirmedPayWave = 0;
    /// @notice Total amount of tokens that were paywaved overall.
    /// @dev Total paywaved tokens amount that is always increasing.
    uint256 public totalPayWave = 0;

    /// @notice Maximum possible supply of this token.
    uint256 public limitSupply = 0;

    /// @notice Set to false to stop mint/burn of token. Set to true to allow minting.
    bool public bridgeAllowed = false;

    /// @notice the list of bridge addresses allowed to mint tokens.
    mapping(address => bool) public bridges;

    // Mint and Burn
    modifier onlyBridge {
        require(bridgeAllowed && bridges[msg.sender]);
        _;
    }

    /**
     * @dev Emitted when `spent` tokens are moved
     * from `unconfirmedPayWave` to `totalPayWave`.
     */
    event PayWave(
        uint256 spent,
        uint256 totalPayWave
    );

    event AddBridge(address indexed bridge);
    event RemoveBridge(address indexed bridge);

    /**
     * @dev Sets the {name} and {symbol} of token.
     * Initializes {decimals} with a default value of 18.
     * Mints all tokens.
     * Transfers ownership to another account. So, the token creator will not be counted as an owner.
     * @param _type o minting:
     *      0 - ETH primary version of Token. Mints each pool to its dedicated multi-sig wallet account.
     *      1 - Test version to develop on local network. Mints all supply to one address.
     *      2 - Sidechain version of Token. Allows minting/burning of token to be done by third parties.
     */
    constructor (uint8 _type) public {
        if (_type == 1) {
            _mint(msg.sender,             10e6 * SCALER);
            return;
        } else if (_type == 0) {
            // Multi-sig wallet accounts to hold the pools and ownership.
            address gameIncentivesHolder = 0x94E169Be9037561aC37D8bb3471c7e35B81708A7;
            address liquidityHolder      = 0xf409fDF4069c825656ba3e1f931FCde8525F1bEE;
            address teamHolder           = 0x2Ff42929f444e496D7e856591764E00ee13b7077;
            address investHolder         = 0x2cfca4ccd9ef6d9420ae1ff26306d179DABAEdC2;
            address communityHolder      = 0x2C25ba4DB75D43e655647F24fB0cB2e896116dbD;
    	    address newOwner             = 0xbfdadB9a06C90B6625aF3C6DAc0Bb7f56a852886;

	        // 5 million tokens
            uint256 gameIncentives       = 5e6 * SCALER;
            // 1,5 million tokens
            uint256 reserve              = 15e5 * SCALER; // reserve for the next 5 years.
	        // 1 million tokens
	        uint256 community            = 1e6 * SCALER;
            uint256 team                 = 1e6 * SCALER;
            uint256 investment           = 1e6 * SCALER;
            // 500,000 tokens
            uint256 liquidity            = 5e5 * SCALER;

            _mint(gameIncentivesHolder,  gameIncentives);
            _mint(liquidityHolder,       liquidity);
            _mint(teamHolder,            team);
            _mint(investHolder,          investment);
            _mint(communityHolder,       community);
            _mint(newOwner,              reserve);

            transferOwnership(newOwner);
        } else {
            bridgeAllowed = true;
            limitSupply = 5e5 * SCALER;     // Initially it allows 500k tokens to mint
        }
   }

   function addBridge(address _bridge) external onlyOwner returns(bool) {
       require(_bridge != address(0), "Crowns: zero address");
       require(bridges[_bridge] == false, "Crowns: already added bridge");

       bridges[_bridge] = true;

       emit AddBridge(_bridge);
   }

    function removeBridge(address _bridge) external onlyOwner returns(bool) {
       require(_bridge != address(0), "Crowns: zero address");
       require(bridges[_bridge], "Crowns: not added bridge");

       bridges[_bridge] = false;

       emit RemoveBridge(_bridge);
   }

   function setLimitSupply(uint256 _newLimit) external onlyOwner returns(bool) {
       require(_newLimit > 0 && _newLimit <= TEN_MILLION, "Crowns: invalid supply limit");

       limitSupply = _newLimit;
   }

   /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) external onlyBridge {
        require(_totalSupply.add(amount) <= limitSupply, "Crowns: exceeds mint limit");
        _mint(to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     *
     * Included just to follow the standard of OpenZeppelin.
     */
    function burn(uint256 amount) public onlyBridge {
        require(false, "Only burnFrom is allowed");
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public onlyBridge {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");

        _approve(account, _msgSender(), currentAllowance.sub(amount, "ERC20: transfer amount exceeds allowance"));
        _burn(account, amount);
    }

    function toggleBridgeAllowance() external onlyOwner {
        bridgeAllowed = !bridgeAllowed;
    }

    /**
     * @notice Return amount of tokens that {account} gets during the PayWave
     * @dev Used both internally and externally to calculate the PayWave amount
     * @param account is an address of token holder to calculate for
     * @return amount of tokens that player could get
     */
    function payWaveOwing (address account) public view returns(uint256) {
        Account memory _account = _accounts[account];

        uint256 newPayWave = totalPayWave.sub(_account.lastPayWave);
        uint256 proportion = _account.balance.mul(newPayWave);

        // The PayWave is not a part of total supply, since it was moved out of balances
        uint256 supply = _totalSupply.sub(newPayWave);

        // PayWave owed proportional to current balance of the account.
        // The decimal factor is used to avoid floating issue.
        uint256 payWave = proportion.mul(SCALER).div(supply).div(SCALER);

        return payWave;
    }

    /**
     * @dev Called before any edit of {account} balance.
     * Modifier moves the belonging PayWave amount to its balance.
     * @param account is an address of Token holder.
     */
    modifier updateAccount(address account) {
        uint256 owing = payWaveOwing(account);
        _accounts[account].lastPayWave = totalPayWave;

        if (owing > 0) {
            _accounts[account].balance    = _accounts[account].balance.add(owing);
            unclaimedPayWave     = unclaimedPayWave.sub(owing);

            emit Transfer(
                address(0),
                account,
                owing
            );
        }

        _;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public pure returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _getBalance(account);
    }

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

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
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
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
    function _transfer(address sender, address recipient, uint256 amount) internal updateAccount(sender) updateAccount(recipient) virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Can not send 0 token");
        require(_getBalance(sender) >= amount, "ERC20: Not enough token to send");

        _beforeTokenTransfer(sender, recipient, amount);

        _accounts[sender].balance =  _accounts[sender].balance.sub(amount);
        _accounts[recipient].balance = _accounts[recipient].balance.add(amount);

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _accounts[account].balance = _accounts[account].balance.add(amount);
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
    function _burn(address account, uint256 amount) internal updateAccount(account) virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _accounts[account].balance;
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _accounts[account].balance = accountBalance.sub(amount);
        _totalSupply = _totalSupply.sub(amount);

        emit Transfer(account, address(0), amount);
    }

    function _spend(address account, uint256 amount) internal updateAccount(account) {
        require(account != address(0), "ERC20: burn from the zero address");
        require(_getBalance(account) >= amount, "ERC20: Not enough token to burn");

        _beforeTokenTransfer(account, address(0), amount);

        _accounts[account].balance = _accounts[account].balance.sub(amount);

        unconfirmedPayWave = unconfirmedPayWave.add(amount);

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
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

    /**
     * @notice Spend some token from caller's balance in the game.
     * @dev Moves `amount` of token from caller to `unconfirmedPayWave`.
     * @param amount Amount of token used to spend
     */
    function spend(uint256 amount) public returns(bool) {
        require(amount > MIN_SPEND, "Crowns: trying to spend less than expected");
        require(_getBalance(msg.sender) >= amount, "Crowns: Not enough balance");

        _spend(msg.sender, amount);

	return true;
    }

    function spendFrom(address sender, uint256 amount) public returns(bool) {
        require(amount > MIN_SPEND, "Crowns: trying to spend less than expected");
        require(_getBalance(sender) >= amount, "Crowns: not enough balance");

        _spend(sender, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));

        return true;
    }

    /**
     * @notice Return the PayWave amount, when `account` balance was updated.
     */
    function getLastPayWave(address account) public view returns (uint256) {
        return _accounts[account].lastPayWave;
    }

    /**
     * @dev Returns actual balance of account as a sum of owned divends and current balance.
     * @param account Address of Token holder.
     * @return Token amount
     */
    function _getBalance(address account) private view returns (uint256) {
        uint256 balance = _accounts[account].balance;
    	if (balance == 0) {
    		return 0;
    	}
    	uint256 owing = payWaveOwing(account);

    	return balance.add(owing);
    }

    /**
     * @notice Pay Wave is a unique feature of Crowns (CWS) token. It redistributes tokens spenth within game among all token holders.
     * @dev Moves tokens from {unconfirmedPayWave} to {totalPayWave}.
     * Any account balance related functions will use {totalPayWave} to calculate the dividend shares for each account.
     *
     * Emits a {PayWave} event.
     */
    function payWave() public onlyOwner() returns (bool) {
    	totalPayWave = totalPayWave.add(unconfirmedPayWave);
    	unclaimedPayWave = unclaimedPayWave.add(unconfirmedPayWave);
        uint256 payWaved = unconfirmedPayWave;
        unconfirmedPayWave = 0;

        emit PayWave (
            payWaved,
            totalPayWave
        );

        return true;
    }
}

pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./../openzeppelin/contracts/utils/Counters.sol";
import "./../seascape_nft/NftTypes.sol";
import "./../seascape_nft/NftFactory.sol";
import "./NftRushCrowns.sol";
import "./NftRushLeaderboard.sol";
import "./NftRushGameSession.sol";

/// @title Nft Rush a game on seascape platform allowing to earn Nft by spending crowns
/// @notice Game comes with Leaderboard located on it's on Solidity file.
/// @author Medet Ahmetson
contract NftRush is Ownable, GameSession, Crowns, Leaderboard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using NftTypes for NftTypes;

    /// @notice nft factory is a contract that mints nfts
    NftFactory nftFactory;    

    /// @notice minimum CWS amount to spend in game.
    /// @dev in WEI format.
    uint256 public minSpend;
    /// @notice maximum CWS amount to spend in game.
    /// @dev in WEI format.
    uint256 public maxSpend;

    address public signer; 
    
    struct Balance {
	    uint256 amount;
	    uint256 mintedTime;
    }

    mapping(address => uint256) public nonces;

    /// @notice Tracking player balance within a game session.
    /// @dev session id =>(wallet address => (Balance struct))
    mapping(uint256 => mapping(address => Balance)) public balances;

    event SessionStarted(uint256 indexed sessionId, uint256 interval, uint256 period, uint256 generation);
    event Spent(address indexed owner, uint256 sessionId, uint256 balanceAmount, uint256 prevMintedTime, uint256 amount);
    event Minted(address indexed owner, uint256 sessionId, uint256 nftId);
    event NftFactorySet(address factory);
    event MinSpendUpdated(uint256 amount);
    event MaxSpendUpdated(uint256 amount);

    constructor(address _crowns, address _factory, uint256 _minSpend, uint256 _maxSpend) public {
        require(_crowns != address(0), "Crowns can't be zero address");
        require(_factory != address(0), "Nft Factory can't be zero address");
        require(_minSpend > 0, "Min spend can't be 0");
        require(_maxSpend > _minSpend, "Max spend should be greater than min limit");
        nftFactory = NftFactory(_factory);

        /// @dev set crowns is defined in Crowns.sol
        setCrowns(_crowns);		

        signer = msg.sender;

        minSpend = _minSpend;
        maxSpend = _maxSpend;
    }
    
    //--------------------------------------------------
    // Only owner
    //--------------------------------------------------

    /** 
     *  @notice Starts a staking session for a finite period of time.
     *  And activated in certain period.
     *
     *  @param _interval duration between claims of Nft
     *  @param _period session duration
     *  @param _startTime session start time in unix timestamp
     *  @param _generation Seascape Nft generation that is given as a reward
     *
     *  Emits an {SessionStarted} event.  
     *
     *  Requirements:
     *
     *  - if some other session was launched before, that session should be ended.
     */
    function startSession(uint256 _interval, uint256 _period, uint256 _startTime, uint256 _generation) external onlyOwner {
        if (lastSessionId() > 0) {
            require(!isActive(lastSessionId()), "NFT Rush: Can't start when session is active");
        }

        uint256 _sessionId = _startSession(_interval, _period, _startTime, _generation);
        
        announceLeaderboard(_sessionId, _startTime);

        emit SessionStarted(_sessionId, _interval, _period, _generation);
    }

    
    /** 
     *  @notice Sets NFT factory that will mint a token for stakers
     *
     *  @param _address a new Address of Nft Factory
     */
    function setNftFactory(address _address) external onlyOwner {
        require(_address != address(0), "Nft Factory can't be zero address");

	    nftFactory = NftFactory(_address);

        emit NftFactorySet(_address);
    }

    
    /** 
     *  @notice set signer
     *
     *  @param _signer a new Address of signer
     */
    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "Signer can't be zero address");
        require(_signer != signer, "Can't be previous signer");
        signer = _signer;
    }

    /**
     *  @notice minimum amount of Crowns that players could spend
     *
     *  @param _amount a new minimal spending amount in WEI
     */
    function setMinSpendAmount(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Min amount should be greater than 0");
	    minSpend = _amount;

        emit MinSpendUpdated(_amount);
    }
        
    /**
     *  @notice minimum amount of Crowns that players could spend
     *
     *  @param _amount a new minimal spending amount in WEI
     */
    function setMaxSpendAmount(uint256 _amount) external onlyOwner {
	    require(_amount > minSpend, "Max amount should be greater than min amount");
        maxSpend = _amount;

        MaxSpendUpdated(_amount);
    }

    //--------------------------------------------------
    // Only game user
    //--------------------------------------------------

    /**
     *  @notice Spend some crowns in the game, to get higher quality NFTs.
     *  The more spending, higher the chance of getting high quality NFT.
     *
     *  Note, that player should approve Crowns to use by this game contract.
     *
     *  Emits a {Spent} event.
     *
     *  @param _sessionId a session id
     *  @param _amount amount of CWS to spend
     *
     *  Requirements:
     *
     *  - `_amount` must be atleast equal to `minSpend`
     *  - `_sessionId` must be greater than 0
     *  - session of `_sessionId` must be active
     *  - The spender should have `amount` of Crowns
     *  - Spending of Crowns must be successfull. Fails, if not granted a permission
     */
    function spend(uint256 _sessionId, uint256 _amount) external {
        require(_amount >= minSpend,
            "NFT Rush: Amount of CWS to spend should be greater or equal to min deposit");
        require(_amount <= maxSpend,
            "Nft Rush: Amount of CWS to spend should be less or equal to max deposit");
        require(_sessionId > 0,
            "NFT Rush: Session is not started yet!");
        require(isActive(_sessionId),
            "NFT Rush: Game session is already finished");
        require(crowns.balanceOf(msg.sender) >= _amount,
            "NFT Rush: Not enough CWS, please check your CWS balance");
        require(crowns.spendFrom(msg.sender, _amount),
            "NFT Rush: Failed to spend CWS");

        Balance storage _balance  = balances[_sessionId][msg.sender];

        require(_balance.amount == 0,
            "NFT Rush: Can not spent more than one time");

        _balance.amount = _balance.amount.add(_amount);
	
        emit Spent(msg.sender, _sessionId, _balance.amount, _balance.mintedTime, _amount);
    }


    /**
     *  @notice mints Nft of {_quality}.
     *  @dev The Quality of Nft is determined by centralized server. 
     *  As a proof centrlized server returns a signature
     *  to validate the quality
     *
     *  Emits a {Minted} event.
     *
     *  @param _sessionId a game session
     *  @param _v part of signature of message
     *  @param _r part of signature of message
     *  @param _s part of signature of message
     *  @param _quality a quality of minted token
     *
     *  Requirements:
     *
     *  - `balances[_sessionId][msg.sender].amount` must ge greater than 0.
     *  - Quality signer's address should match to this contract' owner's address
     *  - Player should mint it first time, or if not, then locking interval should be passed
     *  - Nft Factory should return Nft id of successfully minted token
     */
    function mint(uint256 _sessionId, uint8 _v, bytes32 _r, bytes32 _s, uint8 _quality) external {
        Session storage _session = sessions[_sessionId];
	    Balance storage _balance = balances[_sessionId][msg.sender];

	    require(_balance.amount > 0,
		    "NFT Rush: No deposit was found");
	    require(_balance.mintedTime == 0 ||
		    (_balance.mintedTime.add(_session.interval) < block.timestamp),
		    "NFT Rush: Still in locking period, please try again after locking interval passes");
	
	    /// Validation of quality
	    /// message is generated as owner + amount + last time stamp + quality
	    bytes memory _prefix = "\x19Ethereum Signed Message:\n32";
	    bytes32 _messageNoPrefix =
	    keccak256(abi.encodePacked(msg.sender,
				       _balance.amount,
				       _balance.mintedTime,
				       _quality,
                       nonces[msg.sender])
		      );
	    bytes32 _message = keccak256(abi.encodePacked(_prefix, _messageNoPrefix));
	    address _recover = ecrecover(_message, _v, _r, _s);

	    require(_recover == signer,
		    "NFT Rush: Failed to verify quality signature");
	
        uint256 _tokenId = nftFactory.mintQuality(msg.sender, _session.generation, _quality);
	    require(_tokenId > 0,
		    "NFT Rush: failed to mint a token");
	
	    _balance.mintedTime = block.timestamp;
	    _balance.amount = 0;
        nonces[msg.sender]++;

	    emit Minted(msg.sender, _sessionId, _tokenId);
    }
}

pragma solidity 0.6.7;

import "./../crowns/erc-20/contracts/CrownsToken/CrownsToken.sol";

/// @notice Nft Rush and Leaderboard contracts both manipulates with Crowns.
/// So, making Crowns available for both Contracts
///
/// @author Medet Ahmetson
contract Crowns {
    CrownsToken public crowns;

   function setCrowns(address _crowns) internal {
        require(_crowns != address(0), "Crowns can't be zero address");
       	crowns = CrownsToken(_crowns);	
   }   
}

pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./../openzeppelin/contracts/utils/Counters.sol";

/// @dev Nft Rush and Leaderboard contracts both requires Game Session data
/// So, making Game Session separated.
/// @notice Game session indicates activity of Game for certain period of time.
/// Only, during the game session period, players can spend crowns to mint tokens.
/// @author Medet Ahmetson
contract GameSession is Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter private sessionId;

    struct Session {
        uint256 interval;      // period between intervals
        uint256 period;        // duration of session
        uint256 startTime;     // unix timestamp when session starts
        uint256 generation;    // nft generation
    }

    /// @notice Game session. Smartcontract is active during the game session.
    /// Game session is active for a certain period of time only
    mapping(uint256 => Session) public sessions;

    event SessionStarted(uint256 id, uint256 startTime, uint256 endTime, uint256 generation);
    
    //--------------------------------------------------
    // Only owner
    //--------------------------------------------------
    
    /**
     *  @notice Starts a staking session for a finite _period of
     *  time, starting from _startTime. It allows to claim a
     *  a _generation Seascape NFT.
     *
     *  Emits a {SessionStarted} event.
     *
     *  @param _interval duration between claims
     *  @param _period session duration
     *  @param _startTime session start time in unix timestamp
     *  @param _generation Seascape Nft generation that is given as a reward
     */
    function _startSession(uint256 _interval, uint256 _period, uint256 _startTime, uint256 _generation) internal onlyOwner returns(uint256) {
	    require(_period >= 86400, "NFT Rush: session duration could be minimum for 1 days");
        require(_startTime >= block.timestamp, "NFT Rush: game time should start in the future");

        uint256 _lastSessionId = lastSessionId();
	    if (_lastSessionId > 0) {
	        require(!isActive(_lastSessionId), "NFT Rush: previous session should be expired");	
	    }
	
        sessionId.increment();		
        uint256 _sessionId = sessionId.current();
        
        sessions[_sessionId] = Session(_interval, _period, _startTime, _generation);

        emit SessionStarted(_sessionId, _startTime, _startTime.add(_period), _generation);
        
        return _sessionId;
    }

    //--------------------------------------------------
    // Public methods
    //--------------------------------------------------


    /**
     *  @notice Whether the given session is active or not
     */
    function isActive(uint256 _sessionId) public view returns(bool) {
        if (now > sessions[_sessionId].startTime + sessions[_sessionId].period) {
            return false;
        }

        return true;
    }


    /**
     * @notice The last created session's id
     *
     * NOTE!!! It returns 0, if no session was started yet.
     */
    function lastSessionId() public view returns(uint256) {
	    return sessionId.current();
    }
}

pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./NftRushGameSession.sol";
import "./NftRushCrowns.sol";

/// @notice There are four types of leaderboards in the game:
///
/// - all time spenders
/// - top daily minters
/// 
/// @author Medet Ahmetson
contract Leaderboard is Ownable, GameSession, Crowns {
    using SafeMath for uint256;

    struct Announcement {
        bool    minted;             // was all time winners announced
        uint256 dailySpentTime;     // time when last day was announced
    }

    /// @notice tracks whether the game session's all-time
    /// winners were announced or not. And the last time when
    /// daily leaderboards were announced.
    /// @dev be careful, if the daily winners setting doesn't set all 10 winners,
    /// you wouldn't be able to set missed winners when settings next day winners.
    mapping(uint256 => Announcement) public announcement;    

    /**
     *  @dev Amounts of CWS that winners will claim.
     *  The values should be set after launching the session
     *  
     *  Example values:
     *
     *  - 1st place gets 100K, 
     *  - 2nd place gets 50K...
     */
    uint256[10] public spentDailyPrizes;
    uint256[10] public mintedAllTimePrizes;

    /** 
     *  @notice tracks amount of claimable CWS tokens collected from leaderboards.
     *
     *  Structure:
     *  
     *  - wallet address => prizes sum
     */
    mapping(address => uint256) public spentDailyClaimables;
    mapping(address => uint256) public mintedAllTimeClaimables;

    
    event Rewarded(address indexed owner, string rewardType, uint256 amount);
    event PrizeSet(uint256[10] _spentDaily, uint256[10] _mintedAllTime);
    event AnnounceDailyWinners(uint256 indexed sessionId, address[10] spentWinners);
    event AnnounceAllTimeWinners(uint256 indexed sessionId, address[10] mintedWinners);

    //----------------------------------------------------------------------
    // Pre-game. Following methods executed once before game session begins
    //----------------------------------------------------------------------

    /**
     *  @notice Starts a leaderboard for the game session. This method
     *  should be invoked, once when game session started. otherwise,
     *  would be impossible to track winners for the new session.
     *  @dev it sets the start time of the leaderboard,
     *  So that, daily leaderboard could be announced once for each day.
     *
     *  NOTE!!! This method should be called from Primary Smartcontract.
     *
     *  @param _sessionId a session Id, that leaderboard is attached to.
     *  @param _startTime the first day of leaderboard, to track daily winners announcement
     */
    function announceLeaderboard(uint256 _sessionId, uint256 _startTime) internal {      
	    // this variables are part of leaderboard,
	    // therefore located in leaderboard contract
        announcement[_sessionId] = Announcement(false, _startTime);    
    }


    /**
     *  @notice Sets all prizes at once. Prizes in CWS token that winners would get.
     *
     *  @param _spentDaily list of prizes for daily top spenders
     *  @param _mintedAllTime list of prizes for all time top minters
     */
    function setPrizes(uint256[10] calldata _spentDaily, uint256[10] calldata _mintedAllTime) external onlyOwner {
        spentDailyPrizes = _spentDaily;
	    mintedAllTimePrizes = _mintedAllTime;    

        emit PrizeSet(_spentDaily, _mintedAllTime);   
    }


    //---------------------------------------------------------------------
    // Announcements
    //---------------------------------------------------------------------


    /**
     *  @notice Announce winners list for daily top spenders leaderboard
     *  
     *  @param _sessionId a session of the game
     *  @param _winners list of wallet addresses
     *  @param _winnersAmount number of winners. Some day would not have 10 winners
     *
     *  Requirements:
     *
     *  - Daily spenders leaderboard should be announcable
     *  - `_winnersAmount` must be atmost equal to 10.
     *  - if there are winners, then contract owner should transfer enough CWS to contract to payout players
     */
    function announceDailySpentWinners(uint256 _sessionId, address[10] calldata _winners, uint8 _winnersAmount) external onlyOwner {
        require(dailySpentWinnersAnnouncable(_sessionId), "NFT Rush: already set or too early");
        require(_winnersAmount <= 10, "NFT Rush: exceeded possible amount of winners");

        if (_winnersAmount > 0) {
            uint256 _prizeSum = prizeSum(spentDailyPrizes, _winnersAmount);

            require(crowns.transferFrom(owner(), address(this), _prizeSum), "NFT Rush: not enough CWS to give as a reward");	

            for (uint i=0; i<_winnersAmount; i++) {		
                address _winner = _winners[i];
            
                spentDailyClaimables[_winner] = spentDailyClaimables[_winner].add(spentDailyPrizes[i]);		
            }
        }
	
        setDailySpentWinnersTime(_sessionId);
        emit AnnounceDailyWinners(_sessionId, _winners);
    }

    /**
     *  @notice Announce winners list for all time top minters leaderboard
     *  
     *  @param _sessionId a session of the game
     *  @param _winners list of wallet addresses
     *  @param _winnersAmount number of winners. Some day would not have 10 winners
     *
     *  Requirements:
     *
     *  - All time minters leaderboard should be announcable
     *  - `_winnersAmount` must be atmost equal to 10.
     *  - if there are winners, then contract owner should transfer enough CWS to contract to payout players
     */
    function announceAllTimeMintedWinners(uint256 _sessionId, address[10] calldata _winners, uint8 _winnersAmount) external onlyOwner {
        require(allTimeMintedWinnersAnnouncable(_sessionId), "NFT Rush: all time winners set already");
        require(_winnersAmount <= 10, "NFT Rush: too many winners");

        if (_winnersAmount > 0) {
            uint256 _prizeSum = prizeSum(mintedAllTimePrizes, _winnersAmount);
            require(crowns.transferFrom(owner(), address(this), _prizeSum), "NFT Rush: not enough CWS to give as a reward");

            for (uint i=0; i<_winnersAmount; i++) {
                address _winner = _winners[i];
            
                // increase amount of daily rewards that msg.sender could claim
                mintedAllTimeClaimables[_winner] = mintedAllTimeClaimables[_winner].add(mintedAllTimePrizes[i]);
            }
        }

        setAllTimeMintedWinnersTime(_sessionId);

        emit AnnounceAllTimeWinners(_sessionId, _winners);
    }


    //--------------------------------------------------
    // Player's methods to claim leaderboard prizes
    //--------------------------------------------------


    /**
     *  @notice Player can claim leaderboard rewards.
     *
     *  Emits a {Rewarded} event.
     *
     *  Requirements:
     * 
     *  - `spentDailyClaimables` for player should be greater than 0
     *  - transfer of Crowns from contract balance to player must be successful.
     */
    function claimDailySpent() external {
        require(spentDailyClaimables[_msgSender()] > 0, "NFT Rush: no claimable CWS for leaderboard");

        uint256 _amount = spentDailyClaimables[_msgSender()];

        require(crowns.transfer(_msgSender(), _amount), "NFT Rush: failed to transfer CWS to winner");

        spentDailyClaimables[_msgSender()] = 0;
        
        emit Rewarded(_msgSender(), "DAILY_SPENT", _amount);
    }

    /**
     *  @notice Player can claim leaderboard rewards.
     *
     *  Emits a {Rewarded} event.
     *
     *  Requirements:
     * 
     *  - `mintedAllTimeClaimables` for player should be greater than 0
     *  - transfer of Crowns from contract balance to player must be successful.
     */
    function claimAllTimeMinted() external {
        require(mintedAllTimeClaimables[_msgSender()] > 0, "NFT Rush: no claimable CWS for leaderboard");

        uint256 _amount = mintedAllTimeClaimables[_msgSender()];

        require(crowns.transfer(_msgSender(), _amount), "NFT Rush: failed to transfer CWS to winner");

        mintedAllTimeClaimables[_msgSender()] = 0;
        
        emit Rewarded(_msgSender(), "ALL_TIME_MINTED", _amount);
    }

    //--------------------------------------------------
    // Checking announcability of leaderboards
    // It should be announced, when session period for that leaderboard is passed.
    //--------------------------------------------------

    /**
     *  @dev Check whether the winners list is announcable or not.
     *  It is announcable if:
     *
     *  - since last daily winners list announcement passed more than 1 day.
     */
    function dailySpentWinnersAnnouncable(uint256 _sessionId) internal view returns(bool) {
        Session storage _session = sessions[_sessionId];

        uint256 dayAfterSession = _session.startTime.add(_session.period).add(1 days);

        uint256 today = announcement[_sessionId].dailySpentTime.add(1 days);
	    
        // time should be 24 hours later than last announcement.
        // as we announce leaders for the previous 24 hours.
        //
        // time should be no more than 1 day after session end,
        // so we could annnounce leaders for the last day of session.
        // remember, we always announce after 24 hours pass since the last session.
        return block.timestamp > today && today < dayAfterSession;
    }


    /**
     *  @dev Check whether the winners list is announcable or not.
     *  It is announcable if:
     *
     *  - game session is not active anymore
     *  - but game session was once alive.
     *  - and winners list were not announced yet.
     */
    function allTimeMintedWinnersAnnouncable(uint256 _sessionId) internal view returns(bool) {
        Session storage _session = sessions[_sessionId];
        return !isActive(_sessionId)
            && _session.startTime > 0
            && !announcement[_sessionId].minted;		    
    }


    //--------------------------------------------------
    // Track announcability. So that each session period (whether it's for day
    // or for whole session) would have one announcement only
    //--------------------------------------------------

    /**
     *  @dev update the timer for tracking daily winner list announcement,
     *  that one more day's winners were announced.
     */
    function setDailySpentWinnersTime(uint256 _sessionId) internal {
	    announcement[_sessionId].dailySpentTime = announcement[_sessionId].dailySpentTime.add(1 days);
    }

    /**
     *  @dev set flag of all time minters leaderboard announcement to TRUE
     */
    function setAllTimeMintedWinnersTime(uint256 _sessionId) internal {
        announcement[_sessionId].minted = true;
    }

    //--------------------------------------------------
    // Internal methods used by other methods as a utility.
    //--------------------------------------------------

    /**
     *  @dev Calculates sum of {_winnersAmount} amount of elements in array {_prizes}
     */
    function prizeSum(uint256[10] storage _prizes, uint256 _winnersAmount) internal view returns (uint256) {
        uint256 _sum = 0;

        for (uint i=0; i<_winnersAmount; i++) {
            _sum = _sum.add(_prizes[i]);
        }

        return _sum;
    }
}

// SPDX-License-Identifier: MIT

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

pragma solidity ^0.6.0;

import "../utils/EnumerableSet.sol";
import "../utils/Address.sol";
import "../GSN/Context.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControl is Context {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    struct RoleData {
        EnumerableSet.AddressSet members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return _roles[role].members.length();
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
        return _roles[role].members.at(index);
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to grant");

        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to revoke");

        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, _roles[role].adminRole, adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (_roles[role].members.add(account)) {
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (_roles[role].members.remove(account)) {
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

// SPDX-License-Identifier: MIT

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts may inherit from this and call {_registerInterface} to declare
 * their support of an interface.
 */
contract ERC165 is IERC165 {
    /*
     * bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
     */
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    /**
     * @dev Mapping of interface ids to whether or not it's supported.
     */
    mapping(bytes4 => bool) private _supportedInterfaces;

    constructor () internal {
        // Derived contracts need only register support for their own interfaces,
        // we register support for ERC165 itself here
        _registerInterface(_INTERFACE_ID_ERC165);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     *
     * Time complexity O(1), guaranteed to always use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return _supportedInterfaces[interfaceId];
    }

    /**
     * @dev Registers the contract as an implementer of the interface defined by
     * `interfaceId`. Support of the actual ERC165 interface is automatic and
     * registering its interface id is not required.
     *
     * See {IERC165-supportsInterface}.
     *
     * Requirements:
     *
     * - `interfaceId` cannot be the ERC165 invalid interface (`0xffffffff`).
     */
    function _registerInterface(bytes4 interfaceId) internal virtual {
        require(interfaceId != 0xffffffff, "ERC165: invalid interface id");
        _supportedInterfaces[interfaceId] = true;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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
        require(c >= a, "SafeMath: addition overflow");

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
        return sub(a, b, "SafeMath: subtraction overflow");
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
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
        require(c / a == b, "SafeMath: multiplication overflow");

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
        return div(a, b, "SafeMath: division by zero");
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
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
        return mod(a, b, "SafeMath: modulo by zero");
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
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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

pragma solidity ^0.6.0;

import "../../GSN/Context.sol";
import "./IERC721.sol";
import "./IERC721Metadata.sol";
import "./IERC721Enumerable.sol";
import "./IERC721Receiver.sol";
import "../../introspection/ERC165.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";
import "../../utils/EnumerableSet.sol";
import "../../utils/EnumerableMap.sol";
import "../../utils/Strings.sol";

/**
 * @title ERC721 Non-Fungible Token Standard basic implementation
 * @dev see https://eips.ethereum.org/EIPS/eip-721
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata, IERC721Enumerable {
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using Strings for uint256;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping (address => EnumerableSet.UintSet) private _holderTokens;

    // Enumerable mapping from token ids to their owners
    EnumerableMap.UintToAddressMap private _tokenOwners;

    // Mapping from token ID to approved address
    mapping (uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    // Base URI
    string private _baseURI;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *     bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
     *
     *     => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
     */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;

    /*
     *     bytes4(keccak256('totalSupply()')) == 0x18160ddd
     *     bytes4(keccak256('tokenOfOwnerByIndex(address,uint256)')) == 0x2f745c59
     *     bytes4(keccak256('tokenByIndex(uint256)')) == 0x4f6ccce7
     *
     *     => 0x18160ddd ^ 0x2f745c59 ^ 0x4f6ccce7 == 0x780e9d63
     */
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor (string memory name, string memory symbol) public {
        _name = name;
        _symbol = symbol;

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");

        return _holderTokens[owner].length();
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view override returns (address) {
        return _tokenOwners.get(tokenId, "ERC721: owner query for nonexistent token");
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];

        // If there is no base URI, return the token URI.
        if (bytes(_baseURI).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(_baseURI, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(_baseURI, tokenId.toString()));
    }

    /**
    * @dev Returns the base URI set via {_setBaseURI}. This will be
    * automatically added as a prefix in {tokenURI} to each token's URI, or
    * to the token ID if no specific URI is set for that token ID.
    */
    function baseURI() public view returns (string memory) {
        return _baseURI;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view override returns (uint256) {
        return _holderTokens[owner].at(index);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        // _tokenOwners are indexed by tokenIds, so .length() returns the number of tokenIds
        return _tokenOwners.length();
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view override returns (uint256) {
        (uint256 tokenId, ) = _tokenOwners.at(index);
        return tokenId;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mecanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _tokenOwners.contains(tokenId);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     d*
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        // Clear metadata (if any)
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }

        _holderTokens[owner].remove(tokenId);

        _tokenOwners.remove(tokenId);

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _holderTokens[from].remove(tokenId);
        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev Internal function to set the base URI for all token IDs. It is
     * automatically added as a prefix to the value returned in {tokenURI},
     * or to the token ID if {tokenURI} is empty.
     */
    function _setBaseURI(string memory baseURI_) internal virtual {
        _baseURI = baseURI_;
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
        private returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(abi.encodeWithSelector(
            IERC721Receiver(to).onERC721Received.selector,
            _msgSender(),
            from,
            tokenId,
            _data
        ), "ERC721: transfer to non ERC721Receiver implementer");
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }

    function _approve(address to, uint256 tokenId) private {
        _tokenApprovals[tokenId] = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual { }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../../GSN/Context.sol";
import "./ERC721.sol";

/**
 * @title ERC721 Burnable Token
 * @dev ERC721 Token that can be irreversibly burned (destroyed).
 */
abstract contract ERC721Burnable is Context, ERC721 {
    /**
     * @dev Burns `tokenId`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenId` or be an approved operator.
     */
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721Burnable: caller is not owner nor approved");
        _burn(tokenId);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "../../introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transfered from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
      * @dev Safely transfers `tokenId` token from `from` to `to`.
      *
      * Requirements:
      *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
      * - `tokenId` token must exist and be owned by `from`.
      * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
      * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
      *
      * Emits a {Transfer} event.
      */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "./IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Enumerable is IERC721 {

    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "./IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {

    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

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
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != accountHash && codehash != 0x0);
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
        return _functionCallWithValue(target, data, 0, errorMessage);
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
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
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

pragma solidity ^0.6.0;

import "../math/SafeMath.sol";

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented or decremented by one. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 * Since it is not possible to overflow a 256 bit integer with increments of one, `increment` can skip the {SafeMath}
 * overflow check, thereby saving gas. This does assume however correct usage, in that the underlying `_value` is never
 * directly accessed.
 */
library Counters {
    using SafeMath for uint256;

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
        // The {SafeMath} overflow check can be skipped here, see the comment at the top
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev Library for managing an enumerable variant of Solidity's
 * https://solidity.readthedocs.io/en/latest/types.html#mapping-types[`mapping`]
 * type.
 *
 * Maps have the following properties:
 *
 * - Entries are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Entries are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableMap for EnumerableMap.UintToAddressMap;
 *
 *     // Declare a set state variable
 *     EnumerableMap.UintToAddressMap private myMap;
 * }
 * ```
 *
 * As of v3.0.0, only maps of type `uint256 -> address` (`UintToAddressMap`) are
 * supported.
 */
library EnumerableMap {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Map type with
    // bytes32 keys and values.
    // The Map implementation uses private functions, and user-facing
    // implementations (such as Uint256ToAddressMap) are just wrappers around
    // the underlying Map.
    // This means that we can only create new EnumerableMaps for types that fit
    // in bytes32.

    struct MapEntry {
        bytes32 _key;
        bytes32 _value;
    }

    struct Map {
        // Storage of map keys and values
        MapEntry[] _entries;

        // Position of the entry defined by a key in the `entries` array, plus 1
        // because index 0 means a key is not in the map.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function _set(Map storage map, bytes32 key, bytes32 value) private returns (bool) {
        // We read and store the key's index to prevent multiple reads from the same storage slot
        uint256 keyIndex = map._indexes[key];

        if (keyIndex == 0) { // Equivalent to !contains(map, key)
            map._entries.push(MapEntry({ _key: key, _value: value }));
            // The entry is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            map._indexes[key] = map._entries.length;
            return true;
        } else {
            map._entries[keyIndex - 1]._value = value;
            return false;
        }
    }

    /**
     * @dev Removes a key-value pair from a map. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function _remove(Map storage map, bytes32 key) private returns (bool) {
        // We read and store the key's index to prevent multiple reads from the same storage slot
        uint256 keyIndex = map._indexes[key];

        if (keyIndex != 0) { // Equivalent to contains(map, key)
            // To delete a key-value pair from the _entries array in O(1), we swap the entry to delete with the last one
            // in the array, and then remove the last entry (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = keyIndex - 1;
            uint256 lastIndex = map._entries.length - 1;

            // When the entry to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            MapEntry storage lastEntry = map._entries[lastIndex];

            // Move the last entry to the index where the entry to delete is
            map._entries[toDeleteIndex] = lastEntry;
            // Update the index for the moved entry
            map._indexes[lastEntry._key] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved entry was stored
            map._entries.pop();

            // Delete the index for the deleted slot
            delete map._indexes[key];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function _contains(Map storage map, bytes32 key) private view returns (bool) {
        return map._indexes[key] != 0;
    }

    /**
     * @dev Returns the number of key-value pairs in the map. O(1).
     */
    function _length(Map storage map) private view returns (uint256) {
        return map._entries.length;
    }

   /**
    * @dev Returns the key-value pair stored at position `index` in the map. O(1).
    *
    * Note that there are no guarantees on the ordering of entries inside the
    * array, and it may change when more entries are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Map storage map, uint256 index) private view returns (bytes32, bytes32) {
        require(map._entries.length > index, "EnumerableMap: index out of bounds");

        MapEntry storage entry = map._entries[index];
        return (entry._key, entry._value);
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function _get(Map storage map, bytes32 key) private view returns (bytes32) {
        return _get(map, key, "EnumerableMap: nonexistent key");
    }

    /**
     * @dev Same as {_get}, with a custom error message when `key` is not in the map.
     */
    function _get(Map storage map, bytes32 key, string memory errorMessage) private view returns (bytes32) {
        uint256 keyIndex = map._indexes[key];
        require(keyIndex != 0, errorMessage); // Equivalent to contains(map, key)
        return map._entries[keyIndex - 1]._value; // All indexes are 1-based
    }

    // UintToAddressMap

    struct UintToAddressMap {
        Map _inner;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function set(UintToAddressMap storage map, uint256 key, address value) internal returns (bool) {
        return _set(map._inner, bytes32(key), bytes32(uint256(value)));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function remove(UintToAddressMap storage map, uint256 key) internal returns (bool) {
        return _remove(map._inner, bytes32(key));
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function contains(UintToAddressMap storage map, uint256 key) internal view returns (bool) {
        return _contains(map._inner, bytes32(key));
    }

    /**
     * @dev Returns the number of elements in the map. O(1).
     */
    function length(UintToAddressMap storage map) internal view returns (uint256) {
        return _length(map._inner);
    }

   /**
    * @dev Returns the element stored at position `index` in the set. O(1).
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintToAddressMap storage map, uint256 index) internal view returns (uint256, address) {
        (bytes32 key, bytes32 value) = _at(map._inner, index);
        return (uint256(key), address(uint256(value)));
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function get(UintToAddressMap storage map, uint256 key) internal view returns (address) {
        return address(uint256(_get(map._inner, bytes32(key))));
    }

    /**
     * @dev Same as {get}, with a custom error message when `key` is not in the map.
     */
    function get(UintToAddressMap storage map, uint256 key, string memory errorMessage) internal view returns (address) {
        return address(uint256(_get(map._inner, bytes32(key), errorMessage)));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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
 * As of v3.0.0, only sets of type `address` (`AddressSet`) and `uint256`
 * (`UintSet`) are supported.
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
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

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
        return _add(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(value)));
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
        return address(uint256(_at(set._inner, index)));
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev String operations.
 */
library Strings {
    /**
     * @dev Converts a `uint256` to its ASCII `string` representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = byte(uint8(48 + temp % 10));
            temp /= 10;
        }
        return string(buffer);
    }
}

pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/AccessControl.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./NftTypes.sol";
import "./SeascapeNft.sol";

/// @title Nft Factory mints Seascape NFTs
/// @notice Nft factory has gives to other contracts or wallet addresses permission
/// to mint NFTs. It gives two type of permission set as roles:
///
///   Static role - allows to mint only Common quality NFTs
///   Generator role - allows to mint NFT of any quality.
///
/// Nft Factory can revoke the role, or give it to any number of contracts.
contract NftFactory is AccessControl {
    using SafeMath for uint256;
    using NftTypes for NftTypes;

    bytes32 public constant STATIC_ROLE = keccak256("STATIC");
    bytes32 public constant GENERATOR_ROLE = keccak256("GENERATOR");

    SeascapeNft private nft;
    
    constructor(address _nft) public {
	    nft = SeascapeNft(_nft);
	    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    //--------------------------------------------------
    // Only Seascape Staking contract
    //--------------------------------------------------
    function mint(address _owner, uint256 _generation) public onlyStaticUser returns(uint256) {
	    return nft.mint(_owner, _generation, NftTypes.NORMAL);
    }

    function mintQuality(address _owner, uint256 _generation, uint8 _quality) public onlyGenerator returns(uint256) {
	    require (_quality > 0 && _quality < 6, "NFT Factory: invalid quality");
	    return nft.mint(_owner, _generation, _quality);
    }
    
    
    //--------------------------------------------------
    // Only owner
    //--------------------------------------------------
    function setNft(address _nft) public onlyAdmin {
	   nft = SeascapeNft(_nft);
    }

    /// @dev Add an account to the admin role. Restricted to admins.
    function addAdmin(address account) public virtual onlyAdmin
    {
        grantRole(DEFAULT_ADMIN_ROLE, account);
    }

     /// @dev Remove oneself from the admin role.
     function renounceAdmin() public virtual
     {
	 renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
     }

     /// @dev Return `true` if the account belongs to the admin role.
     function isAdmin(address account) public virtual view returns (bool)
     {
	 return hasRole(DEFAULT_ADMIN_ROLE, account);
     }

     /// @dev Restricted to members of the admin role.
     modifier onlyAdmin()
     {
	 require(isAdmin(msg.sender), "Restricted to admins.");
	 _;
     }


     /// @dev Restricted to members of the user role.
     modifier onlyStaticUser()
     {
        require(isStaticUser(msg.sender), "Restricted to minters.");
        _;
     }

     /// @dev Return `true` if the account belongs to the user role.
     function isStaticUser(address account) public virtual view returns (bool)
     {
        return hasRole(STATIC_ROLE, account);
     }
     
     /// @dev Add an account to the user role. Restricted to admins.
     function addStaticUser(address account) public virtual onlyAdmin
     {
	    grantRole(STATIC_ROLE, account);
     }

     /// @dev Remove an account from the user role. Restricted to admins.
     function removeStaticUser(address account) public virtual onlyAdmin
     {
	    revokeRole(STATIC_ROLE, account);
     }
  

     /// @dev Restricted to members of the user role.
     modifier onlyGenerator()
     {
	    require(isGenerator(msg.sender), "Restricted to random generator.");
	    _;
     }

     /// @dev Return `true` if the account belongs to the user role.
     function isGenerator(address account) public virtual view returns (bool)
     {
        return hasRole(GENERATOR_ROLE, account);
     }
     
     /// @dev Add an account to the user role. Restricted to admins.
     function addGenerator(address account) public virtual onlyAdmin
     {
	    grantRole(GENERATOR_ROLE, account);
     }

     /// @dev Remove an account from the user role. Restricted to admins.
     function removeGenerator(address account) public virtual onlyAdmin
     {
	    revokeRole(GENERATOR_ROLE, account);
     }
}

pragma solidity 0.6.7;

/// @dev id of Seascape NFT quality.
library NftTypes {
    uint8 public constant NORMAL = 1;
    uint8 public constant SPECIAL = 2;
    uint8 public constant RARE = 3;
    uint8 public constant EPIC = 4;
    uint8 public constant LEGENDARY = 5;
}

// Seascape NFT
// SPDX-License-Identifier: MIT
pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/utils/Counters.sol";
import "./../openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./../openzeppelin/contracts/token/ERC721/ERC721Burnable.sol";

/// @title Seascape NFT based on ERC721 standard.
/// @notice Seascape NFT is the NFT used in Seascape Network platform.
/// Nothing special about it except that it has two more additional parameters to
/// for quality and generation to use in Seascape Platform.
/// @author Medet Ahmetson
contract SeascapeNft is ERC721, ERC721Burnable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private tokenId;

    struct Params {
	    uint256 quality;   // seascape points
	    uint8 generation;	
    }

    /// @dev minting of seascape nfts are done by factory contract only.
    address private factory;

    /// @dev returns parameters of Seascape NFT by token id.
    mapping(uint256 => Params) public paramsOf;

    event Minted(address indexed owner, uint256 indexed id, uint256 generation, uint8 quality);
    
    /**
     * @dev Sets the {name} and {symbol} of token.
     * Initializes {decimals} with a default value of 18.
     * Mints all tokens.
     * Transfers ownership to another account. So, the token creator will not be counted as an owner.
     */
    constructor() public ERC721("Seascape NFT", "SCAPES") {
	tokenId.increment(); // set to 1 the incrementor, so first token will be with id 1.
    }

    modifier onlyFactory() {
        require(factory == _msgSender(), "Seascape NFT: Only NFT Factory can call the method");
        _;
    }

    function mint(address _to, uint256 _generation, uint8 _quality) public onlyFactory returns(uint256) {
	    uint256 _tokenId = tokenId.current();

        _safeMint(_to, _tokenId);

        paramsOf[_tokenId] = Params(_generation, _quality);

        tokenId.increment();

        emit Minted(_to, _tokenId, _generation, _quality);
        return _tokenId;
    }

    function setOwner(address _owner) public onlyOwner {
	    transferOwnership(_owner);
    }

    function setFactory(address _factory) public onlyOwner {
	    factory = _factory;
    }

    function setBaseUri(string memory _uri) public onlyOwner {
	    _setBaseURI(_uri);
    }
}

