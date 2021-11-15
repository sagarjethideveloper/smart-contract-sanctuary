// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;

import "../interfaces/IPool.sol";
import "./Pool.sol";
import "../libraries/Ownable.sol";
import "../libraries/Pausable.sol";
import "../libraries/Initializable.sol";

contract PoolFactory is Ownable, Pausable, Initializable {
    // SotaTier contract
    address private tier;

	// Max tier
	uint constant MAX_NUM_TIERS = 10;

    // Array of created Pools Address
    address[] public allPools;
    address[3] allowedPayment;
    // Mapping from User token. From tokens to array of created Pools for token
    mapping(address => mapping(address => address[])) public getPools;

    event PoolCreated(
        address registedBy,
        address indexed token,
        address indexed pool,
        uint256 poolId
    );

    function initialize(address _tier, address _usdt, address _usdc) external initializer {
        require(_tier != address(0), "POOL::ZERO_TIER_ADDRESS");

        paused = false;
        owner = msg.sender;
        tier = _tier;

        allowedPayment = [address(0), _usdt, _usdc];
    }

    /**
     * @notice Get the address of Tier contract
     * @return Return address of Tier contract
     */
    function getTier() public view returns (address) {
        return tier;
    }

    /**
     * @notice Get the number of all created pools
     * @return Return number of created pools
     */
    function allPoolsLength() public view returns (uint256) {
        return allPools.length;
    }

    /**
     * @notice Get the created pools by token address
     * @dev User can retrieve their created pool by address of tokens
     * @param _creator Address of created pool user
     * @param _token Address of token want to query
     * @return Created Pool Address
     */
    function getCreatedPoolsByToken(address _creator, address _token)
        public
        view
        returns (address[] memory)
    {
        return getPools[_creator][_token];
    }

    /**
     * @notice Retrieve number of pools created for specific token
     * @param _creator Address of created pool user
     * @param _token Address of token want to query
     * @return Return number of created pool
     */
    function getCreatedPoolsLengthByToken(address _creator, address _token)
        public
        view
        returns (uint256)
    {
        return getPools[_creator][_token].length;
    }

    /**
     * @notice Register ICO Pool for tokens
     * @dev To register, you MUST have an ERC20 token
     * @param _name String name of new pool
     * @param _token address of ERC20 token
     * @param _duration Number of ICO time in seconds
     * @param _openTime Number of start ICO time in seconds
     * @param _ethRate Conversion rate for buy token. tokens = value * rate
     * @param _ethRateDecimals Decimals of token eth rate
     * @param _tierLimitBuy Array of max token user can buy each tiers
     * @param _wallet Address of funding ICO wallets. Sold tokens in eth will transfer to this address
     */
    function registerPool(
        string memory _name,
        address _token,
        uint256 _duration,
        uint256 _openTime,
        uint256 _ethRate,
        uint256 _ethRateDecimals,
        uint256[MAX_NUM_TIERS] memory _tierLimitBuy,
        address _wallet
    ) external whenNotPaused returns (address pool) {
        require(_token != address(0), "ICOFactory::ZERO_ADDRESS");
        require(_duration != 0, "ICOFactory::ZERO_DURATION");
        require(_wallet != address(0), "ICOFactory::ZERO_ADDRESS");
        require(_ethRate != 0, "ICOFactory::ZERO_ETH_RATE");
        require(_tierLimitBuy[0] != 0, "POOL::ZERO_TIER_LIMIT_BUY");
        bytes memory bytecode = type(Pool).creationCode;
        uint256 tokenIndex = getCreatedPoolsLengthByToken(msg.sender, _token);
        bytes32 salt =
            keccak256(abi.encodePacked(msg.sender, _token, tokenIndex));
        assembly {
            pool := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IPool(pool).initialize(
            _name,
            _token,
            _duration,
            _openTime,
            _ethRate,
            _ethRateDecimals,
            _tierLimitBuy,
            _wallet
        );
        getPools[msg.sender][_token].push(pool);
        allPools.push(pool);

        emit PoolCreated(msg.sender, _token, pool, allPools.length - 1);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.1;

interface IPool {
    function initialize(string memory _name, address _token, uint256 _duration, uint256 _openTime, uint256 _ethRate, uint256 _ethRateDecimals, uint256[10] memory _tierLimitBuy, address _walletAddress) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;

import "../interfaces/IERC20.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/ISotaTier.sol";
import "../libraries/Ownable.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Pausable.sol";
import "../extensions/SotaWhitelist.sol";

contract Pool is Ownable, ReentrancyGuard, Pausable, SotaWhitelist {
    using SafeMath for uint256;

    uint constant MAX_NUM_TIERS = 10;

    // The token being sold
    IERC20 public token;

    // The address of factory contract
    address public factory;

    // Address where funds are collected
    address public fundingWallet;

    // Timestamps when token started to sell
    uint256 public openTime = block.timestamp;

    // Timestamps when token stopped to sell
    uint256 public closeTime;

    // Amount of wei raised
    uint256 public weiRaised = 0;

    // Amount of token sold
    uint256 public tokenSold = 0;

    // Name of ICO Pool
    string public name;

    // Ether to token conversion rate
    uint256 private etherConversionRate;

    // Ether to token conversion rate decimals
    uint256 private etherConversionRateDecimals = 0;

    // Token limit amount user can buy each tier
    uint[MAX_NUM_TIERS] public tierLimitBuy;

    // Number of token user purchased
    mapping(address => uint256) public userPurchased;

    // Pool extensions
    bool public useWhitelist;

    // Token to token conversion rate
    mapping(address => uint256) private erc20TokenConversionRate;

    modifier tokenRateSetted(address _token) {
        require(erc20TokenConversionRate[_token] != 0, "POOL::TOKEN_NOT_ALLOWED");
        _;
    }

    // -----------------------------------------
    // Lauchpad Starter's event
    // -----------------------------------------
    event PoolCreated(string name, address token, uint256 openTime, uint256 closeTime, uint256 ethRate, uint256 ethRateDecimals, address wallet, address owner);
    event AllowTokenToTradeWithRate(address token, uint256 rate);
    event TokenPurchaseByEther(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event TokenPurchaseByToken(address indexed purchaser, address indexed beneficiary, address token, uint256 value, uint256 amount);
    event RefundedIcoToken(address wallet, uint256 amount);
    event PoolStatsChanged();
    // -----------------------------------------
    // Constructor
    // -----------------------------------------
    constructor () {
        factory = msg.sender;
    }

    // -----------------------------------------
    // Lauchpad Starter external interface
    // -----------------------------------------

    /**
    * @dev fallback function
    */
    fallback () external {
        revert();
    }

    /**
    * @dev fallback function
    */
    receive () external payable {
        revert();
    }

    /**
     * @param _name Name of ICO Pool
     * @param _token Address of the token being sold
     * @param _duration Duration of ICO Pool
     * @param _openTime When ICO Started
     * @param _ethRate Number of token units a buyer gets per wei
     * @param _tierLimitBuy Array of max token user can buy each tiers
     * @param _wallet Address where collected funds will be forwarded to
     */
    function initialize(string calldata _name, address _token, uint256 _duration, uint256 _openTime, uint256 _ethRate, uint256 _ethRateDecimals, uint[MAX_NUM_TIERS] calldata _tierLimitBuy, address _wallet) external {
        require(msg.sender == factory, "POOL::UNAUTHORIZED");
        require(_tierLimitBuy[0] != 0, "POOL::ZERO_TIER_LIMIT_BUY");

        name = _name;
        token = IERC20(_token);
        openTime = _openTime;
        closeTime = _openTime.add(_duration);
        etherConversionRate = _ethRate;
        etherConversionRateDecimals = _ethRateDecimals;
        tierLimitBuy = _tierLimitBuy;
        fundingWallet = _wallet;
        owner = tx.origin;
        paused = false;

        emit PoolCreated(_name, _token, _openTime, closeTime, _ethRate, _ethRateDecimals, _wallet, owner);
    }

    /**
     * @notice Returns the conversion rate when user buy by eth
     * @return Returns only a fixed number of rate.
     */
    function getEtherConversionRate() public view returns (uint256) {
        return etherConversionRate;
    }

    /**
     * @notice Returns the conversion rate decimals when user buy by eth
     * @return Returns only a fixed number of decimals.
     */
    function getEtherConversionRateDecimals() public view returns (uint256) {
        return etherConversionRateDecimals;
    }

    /**
     * @notice Returns the conversion rate when user buy by eth
     * @return Returns only a fixed number of token rate.
     * @param _token address of token to query token exchange rate
     */
    function getErc20TokenConversionRate(address _token) public view returns (uint256) {
        return erc20TokenConversionRate[_token];
    }

    /**
     * @notice Owner can set the eth conversion rate. Receiver tokens = wei * etherConversionRate / 10 ** etherConversionRateDecimals
     * @param _rate Fixed number of ether rate
     * @param _rateDecimals Fixed number of ether rate decimals
     */
    function setEtherConversionRateAndDecimals(uint256 _rate, uint256 _rateDecimals) public onlyOwner {
        etherConversionRate = _rate;
        etherConversionRateDecimals = _rateDecimals;
        emit PoolStatsChanged();
    }
    /**
     * @notice Owner can set the eth conversion rate. Receiver tokens = wei * etherConversionRate / 10 ** etherConversionRateDecimals
     * @param _rate Fixed number of ether rate
     */
    function setEtherConversionRate(uint256 _rate) public onlyOwner {
        require(etherConversionRate != _rate, "POOL::RATE_INVALID");
        etherConversionRate = _rate;
        emit PoolStatsChanged();
    }

    /**
     * @notice Owner can set the eth conversion rate decimals. Receiver tokens = wei * etherConversionRate / 10 ** etherConversionRateDecimals
     * @param _rateDecimals Fixed number of ether rate decimals
     */
    function setEtherConversionRateDecimals(uint256 _rateDecimals) public onlyOwner {
        etherConversionRateDecimals = _rateDecimals;
        emit PoolStatsChanged();
    }

    /**
     * @notice Owner can set the token conversion rate. Receiver tokens = tradeTokens * tokenRate
     * @param _token address of token to query token exchange rate
     */
    function setErc20TokenConversionRate(address _token, uint256 _rate) public onlyOwner {
        require(erc20TokenConversionRate[_token] != _rate, "POOL::RATE_INVALID");
        erc20TokenConversionRate[_token] = _rate;
        emit AllowTokenToTradeWithRate(_token, _rate);
        emit PoolStatsChanged();
    }

    /**
     * @notice Owner can set the limit token amount each tiers can buy.
     * @param _tierLimitBuy array of ascending limit token buy-able amount
     */
    function setTierLimitBuy(uint[MAX_NUM_TIERS] calldata _tierLimitBuy)
        public
        onlyOwner
    {
        require(_tierLimitBuy[0] != 0, "POOL::ZERO_TIER_LIMIT_BUY");
        tierLimitBuy = _tierLimitBuy;
        emit PoolStatsChanged();
    }

    /**
    * @notice Owner can set the close time (time in seconds). User can buy before close time.
    * @param _closeTime Value in uint256 determine when we stop user to by tokens
    */
    function setCloseTime(uint256 _closeTime) public onlyOwner () {
        require(_closeTime >= block.timestamp, "POOL::INVALID_TIME");
        closeTime = _closeTime;
        emit PoolStatsChanged();
    }

    /**
    * @notice Owner can set the open time (time in seconds). User can buy after open time.
    * @param _openTime Value in uint256 determine when we allow user to by tokens
    */
    function setOpenTime(uint256 _openTime) public onlyOwner () {
        openTime = _openTime;
        emit PoolStatsChanged();
    }

    /**
    * @notice Owner can set the open time (time in seconds). User can buy after open time.
    * @param _whitelist Value in bool. True if using whitelist
    */
    function setPoolExtentions(bool _whitelist) public onlyOwner () {
        useWhitelist = _whitelist;
        emit PoolStatsChanged();
    }

    function buyTokenByEtherWithPermission(
        address _beneficiary,
        address _candidate,
        uint256 _maxAmount,
        uint256 _deadline,
        bytes memory _signature
    )
        public
        payable
        whenNotPaused
        nonReentrant
    {
        uint256 weiAmount = msg.value;
        _preValidatePurchase(_beneficiary, weiAmount);
        require(_validPurchase(), "POOL::ENDED");
        require(_verifyWhitelist(_candidate, _maxAmount, _deadline, _signature));

        // calculate token amount to be created
        uint256 tokens = _getEtherToTokenAmount(weiAmount);
        _verifyTierLimitBuy(_beneficiary, tokens);

        _deliverTokens(_beneficiary, tokens);

        _forwardFunds(weiAmount);

        _updatePurchasingState(weiAmount, tokens);
        emit TokenPurchaseByEther(msg.sender, _beneficiary, weiAmount, tokens);
    }

    /**
    * @notice Calculate the tokens user can receive. Receive User's trade tokens and transfer tokens
    * @dev tokens = _token * token Conversion Rate Of _token
    * @param _beneficiary Address performing the token purchase
    * @param _token Address of willing to exchange to ke performing the token purchase
    * @param _amount Value of amount will exchange of tokens
    */
    function buyTokenByTokenWithPermission(
        address _beneficiary,
        address _token,
        uint256 _amount,
        address _candidate,
        uint256 _maxAmount,
        uint256 _deadline,
        bytes memory _signature
    )
        public
        whenNotPaused
        nonReentrant
        tokenRateSetted(_token)
    {
        require(_token != address(token), "POOL::TOKEN_INVALID");
        require(_validPurchase(), "POOL::ENDED");
        require(_verifyWhitelist(_candidate, _maxAmount, _deadline, _signature));

        _verifyAllowance(msg.sender, _token, _amount);

        _preValidatePurchase(_beneficiary, _amount);

        require(
            getErc20TokenConversionRate(_token) != 0,
            "POOL::TOKEN_NOT_ALLOWED"
        );

        uint256 tokens = _getTokenToTokenAmount(_token, _amount);
        _verifyTierLimitBuy(_beneficiary, tokens);

        _deliverTokens(_beneficiary, tokens);

        _forwardTokenFunds(_token, _amount);

        _updatePurchasingState(0, tokens);

        emit TokenPurchaseByToken(
            msg.sender,
            _beneficiary,
            _token,
            _amount,
            tokens
        );
    }
    /**
    * @notice Return true if pool has ended
    * @dev User cannot purchase / trade tokens when isFinalized == true
    * @return true if the ICO Ended.
    */
    function isFinalized() public view returns (bool) {
        return block.timestamp >= closeTime;
    }

    /**
    * @notice Owner can receive their remaining tokens when ICO Ended
    * @dev  Can refund remainning token if the ico ended
    * @param _wallet Address wallet who receive the remainning tokens when Ico end
    * @param _amount Value of amount will exchange of tokens
    */
    function refundRemainingTokens(address _wallet, uint _amount) external onlyOwner {
        require(isFinalized(), "POOL::ICO_NOT_ENDED");
        require(token.balanceOf(address(this)) > 0, "POOL::EMPTY_BALANCE");
        _deliverTokens(_wallet, _amount);
        emit RefundedIcoToken(_wallet, _amount);
    }

    /**
    * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use super to concatenate validations.
    * @param _beneficiary Address performing the token purchase
    * @param _weiAmount Value in wei involved in the purchase
    */
    function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) internal pure {
        require(_beneficiary != address(0), "POOL::INVALID_BENEFICIARY");
        require(_weiAmount != 0, "POOL::INVALID_WEI_AMOUNT");
    }

    /**
    * @dev Override to extend the way in which ether is converted to tokens.
    * @param _weiAmount Value in wei to be converted into tokens
    * @return Number of tokens that can be purchased with the specified _weiAmount
    */
    function _getEtherToTokenAmount(uint256 _weiAmount) internal view returns (uint256) {
        uint256 rate = getEtherConversionRate();
        return _weiAmount.mul(rate).div(10 ** etherConversionRateDecimals);
    }

    /**
    * @dev Override to extend the way in which ether is converted to tokens.
    * @param _token Address of exchange token
    * @param _amount Value of exchange tokens
    * @return Number of tokens that can be purchased with the specified _weiAmount
    */
    function _getTokenToTokenAmount(address _token, uint256 _amount) internal view returns (uint256) {
        uint256 rate = getErc20TokenConversionRate(_token);
        return _amount.mul(rate);
    }

    /**
    * @dev Source of tokens. Transfer / mint
    * @param _beneficiary Address performing the token purchase
    * @param _tokenAmount Number of tokens to be emitted
    */
    function _deliverTokens(
        address _beneficiary,
        uint256 _tokenAmount
    )
      internal
    {
      token.transfer(_beneficiary, _tokenAmount);
      userPurchased[_beneficiary] = userPurchased[_beneficiary].add(_tokenAmount);
    }

    /**
    * @dev Determines how ETH is stored/forwarded on purchases.
    */
    function _forwardFunds(uint256 _value) internal {
        address payable wallet = address(uint160(fundingWallet));
        (bool success, ) = wallet.call{value: _value}("");
        require(success, "POOL::WALLET_TRANSFER_FAILED");
    }

    /**
    * @dev Determines how Token is stored/forwarded on purchases.
    */
    function _forwardTokenFunds(address _token, uint _amount) internal {
        IERC20(_token).transferFrom(msg.sender, fundingWallet, _amount);
    }

    /**
    * @param _tokens Value of sold tokens
    * @param _weiAmount Value in wei involved in the purchase
    */
    function _updatePurchasingState(
        uint256 _weiAmount,
        uint256 _tokens
    )
      internal
    {
      weiRaised = weiRaised.add(_weiAmount);
      tokenSold = tokenSold.add(_tokens);
    }

    // @return true if the transaction can buy tokens
    function _validPurchase() internal view returns (bool) {
        bool withinPeriod = block.timestamp >= openTime && block.timestamp <= closeTime;
        return withinPeriod;
    }

    /**
   * @dev Transfer eth to an address
   * @param _to Address receiving the eth
   * @param _amount Amount of wei to transfer
   */
    function _transfer(address _to, uint256 _amount) private {
        address payable payableAddress = address(uint160(_to));
        (bool success, ) = payableAddress.call{value: _amount}("");
        require(success, "POOL::TRANSFER_FEE_FAILED");
    }

    /**
   * @dev Transfer token to an address
   * @param _to Address receiving the eth
   * @param _amount Amount of wei to transfer
   */
    function _transferToken(address _token, address _to, uint256 _amount) private {
        IERC20(_token).transferFrom(msg.sender, _to, _amount);
    }

    function _verifyAllowance(address _user, address _token, uint256 _amount) private view {
        IERC20 tradeToken = IERC20(_token);
        uint256 allowance = tradeToken.allowance(_user, address(this));
        require(allowance >= _amount, "POOL::TOKEN_NOT_APPROVED");
    }

    function _verifyTierLimitBuy(address _user, uint256 _amount) private view {
		address tier = IPoolFactory(factory).getTier();
        uint userTier = ISotaTier(tier).getUserTier(_user);
        require(userPurchased[_user].add(_amount) <= tierLimitBuy[userTier], "POOL::LIMIT_BUY_EXCEED");
    }

    function _verifyWhitelist(address _candidate, uint256 _maxAmount, uint256 _deadline, bytes memory _signature) private view returns (bool) {
        if (useWhitelist) {
            return (verify(owner, _candidate, _maxAmount, _deadline, _signature));
        }
        return true;
    }
}

//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;

  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function transferOwnership(address _newOwner) public onlyOwner {
    _transferOwnership(_newOwner);
  }

  /**
   * @dev Transfers control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function _transferOwnership(address _newOwner) internal {
    require(_newOwner != address(0));
    emit OwnershipTransferred(owner, _newOwner);
    owner = _newOwner;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.7.1;


import "./Ownable.sol";


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused;


  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   */
  modifier whenNotPaused() {
    require(!paused, "CONTRACT_PAUSED");
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   */
  modifier whenPaused() {
    require(paused, "CONTRACT_NOT_PAUSED");
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner whenNotPaused public {
    paused = true;
    emit Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner whenPaused public {
    paused = false;
    emit Unpause();
  }
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity >=0.7.1 <0.8.0;


/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 * 
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
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
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

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

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        // extcodesize checks the size of the code stored in an address, and
        // address returns the current address. Since the code is still not
        // deployed when running a constructor, any checks on its code size will
        // yield zero, making it an effective way to detect if a contract is
        // under construction or not.
        address self = address(this);
        uint256 cs;
        // solhint-disable-next-line no-inline-assembly
        assembly { cs := extcodesize(self) }
        return cs == 0;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.1;

interface IPoolFactory {
    function getTier() external view returns (address);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

interface ISotaTier {
  function deposit(uint _amount) external;
  function withdraw(uint _amount) external;
  function updateEmergencyWithdrawStatus(bool _status) external;
  function emergencyWithdraw() external;
  function updateTier(uint8 _tierId, uint _amount) external;
  function updateWithdrawFee(uint _key, uint _percent) external;
  function getUserTier(address _userAddress) external view returns (uint8 res);
  function calculateWithdrawFee(address _userAddress, uint _amount) external view returns (uint);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
pragma solidity ^0.7.0;

// From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/Math.sol
// Subject to the MIT license.

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
     * @dev Returns the addition of two unsigned integers, reverting on overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting with custom message on overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on underflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot underflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction underflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on underflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot underflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
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
     * @dev Returns the multiplication of two unsigned integers, reverting on overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, errorMessage);

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers.
     * Reverts on division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers.
     * Reverts with custom message on division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
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
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";

// Signature Verification
/// @title Sota Whitelists - Implement off-chain whitelist and on-chain verification
/// @author Thang Nguyen Quy <[email protected]>

contract SotaWhitelist {
    // Using Openzeppelin ECDSA cryptography library
    function getMessageHash(
        address _candidate,
        uint256 _maxAmount,
        uint256 _deadline
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_candidate, _maxAmount, _deadline));
    }

    // Verify signature function
    function verify(
        address _signer,
        address _candidate,
        uint256 _maxAmount,
        uint256 _deadline,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 messageHash = getMessageHash(_candidate, _maxAmount, _deadline);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        
        return getSignerAddress(ethSignedMessageHash, signature) == _signer;
    }
    
    function getSignerAddress(bytes32 _messageHash, bytes memory _signature) public pure returns(address signer) {
        return ECDSA.recover(_messageHash, _signature);
    }
    
    // Split signature to r, s, v
    function splitSignature(bytes memory _signature)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(_signature.length == 65, "invalid signature length");

        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }
    }

    function getEthSignedMessageHash(bytes32 _messageHash)
        public
        pure
        returns (bytes32)
    {
        return ECDSA.toEthSignedMessageHash(_messageHash);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Check the signature length
        if (signature.length != 65) {
            revert("ECDSA: invalid signature length");
        }

        // Divide the signature in r, s and v variables
        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        return recover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover-bytes32-bytes-} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "ECDSA: invalid signature 's' value");
        require(v == 27 || v == 28, "ECDSA: invalid signature 'v' value");

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "ECDSA: invalid signature");

        return signer;
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from a `hash`. This
     * replicates the behavior of the
     * https://github.com/ethereum/wiki/wiki/JSON-RPC#eth_sign[`eth_sign`]
     * JSON-RPC method.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}

