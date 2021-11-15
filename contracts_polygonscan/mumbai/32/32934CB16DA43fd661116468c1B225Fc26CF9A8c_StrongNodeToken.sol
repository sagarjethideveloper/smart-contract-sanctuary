// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IBEP20.sol";
import "./IPancakePair.sol";

contract StrongNodeToken is Context, IBEP20, Ownable {
  using SafeMath for uint256;
  using Address for address;

  address public presaleWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public stakingWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public operationsWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public teamWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public treasuryWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public marketingWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public advisorWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;
  address public publicsaleWallet = 0x25849726fFB602Bd654e70B6A3A3801A1Ef11239;

  uint256 public redistributionFee = 37;
  uint256 public safuFee = 20;
  uint256 public strong4goodFee = 20;

  address public safuWallet;
  address public strong4goodWallet;
  address public tokenPairAddress;

  mapping (address => uint256) private _reserveTokenBalance;
  mapping (address => uint256) private _circulatingTokenBalance;
  mapping (address => mapping (address => uint256)) private _allowances;

  mapping (address => bool) private _isExcluded;
  address[] private _excluded;

  // The highest possible number.
  uint256 private constant MAX = ~uint256(0);

  // For the purpose of the bank analogy, this is the circulating supply as opposed to the reserve supply.
  // This value never changes. Burning tokens don't reduce this supply, they just get sent to a burn address. Minting doesn't exist.
  uint256 private constant _totalSupply = 10**10 * 10**18;

  // Total reserve amount. The amount must be divisible by the circulating supply to reduce rounding errors in calculations,
  // hence the calculation of a remainder
  uint256 private _totalReserve = (MAX - (MAX % _totalSupply));

  // Total accumulated transaction fees.
  uint256 private _transactionFeeTotal;

  // Duration of initial sell tax.
  bool private initialSellTaxActive = false;

  // Once the initial sell tax is set once, it cannot be set again.
  bool private initialSellTaxSet = false;

  uint8 private _decimals = 18;
  string private _symbol = "SNE";
  string private _name = "StrongNodeEdge Token";

  // Struct for storing calculated transaction reserve values, fixes the error of too many local variables.
  struct ReserveValues {
    uint256 reserveAmount;
    uint256 reserveFee;
    uint256 reserveTransferAmount;
    uint256 reserveTransferAmountSafu;
    uint256 reserveTransferAmountStrong4Good; 
  }

  // Struct for storing calculated transaction values, fixes the error of too many local variables.
  struct TransactionValues {
    uint256 transactionFee;
    uint256 transferAmount;
    uint256 netTransferAmount;
    uint256 sneSafu;
    uint256 sneStrong4Good;
  }

  constructor() {
    // 19% presale tokens
    uint256 presaleTokens = _totalSupply.mul(19).div(100);

    // 15% staking rewards
    uint256 stakingTokens = _totalSupply.mul(15).div(100);

    // 15% operations tokens
    uint256 operationTokens = _totalSupply.mul(15).div(100);

    // 14% team tokens
    uint256 teamTokens = _totalSupply.mul(14).div(100);

    // 10% treasury reserves
    uint256 treasuryTokens = _totalSupply.mul(10).div(100);

    // 7% marketing tokens
    uint256 marketingTokens = _totalSupply.mul(7).div(100);

    // 4% advisors tokens
    uint256 advisorTokens = _totalSupply.mul(4).div(100);

    // 2% public sale tokens
    uint256 publicsaleTokens = _totalSupply.mul(2).div(100);

    // remaining 14% for the liquidity pool
    uint256 liquidity = _totalSupply.sub(presaleTokens).sub(stakingTokens).sub(operationTokens).sub(teamTokens);
                          
    liquidity = liquidity.sub(treasuryTokens).sub(marketingTokens).sub(advisorTokens).sub(publicsaleTokens);
    // ratio of reserve to total supply
    uint256 rate = getRate();
    
    _reserveTokenBalance[presaleWallet] = presaleTokens.mul(rate);
    _reserveTokenBalance[stakingWallet] = stakingTokens.mul(rate);
    _reserveTokenBalance[operationsWallet] = operationTokens.mul(rate);
    _reserveTokenBalance[teamWallet] = teamTokens.mul(rate);
    _reserveTokenBalance[treasuryWallet] = treasuryTokens.mul(rate);
    _reserveTokenBalance[marketingWallet] = marketingTokens.mul(rate);
    _reserveTokenBalance[advisorWallet] = advisorTokens.mul(rate);
    _reserveTokenBalance[publicsaleWallet] = publicsaleTokens.mul(rate);
    _reserveTokenBalance[_msgSender()] = liquidity.mul(rate);
    
    emit Transfer(
      address(0),
      presaleWallet,
      presaleTokens
    );

    emit Transfer(
      address(0),
      stakingWallet,
      stakingTokens
    );

    emit Transfer(
      address(0),
      operationsWallet,
      operationTokens
    );

    emit Transfer(
      address(0),
      teamWallet,
      teamTokens
    );

    emit Transfer(
      address(0),
      treasuryWallet,
      treasuryTokens
    );

    emit Transfer(
      address(0),
      advisorWallet,
      advisorTokens
    );

    emit Transfer(
      address(0),
      marketingWallet,
      marketingTokens
    );

    emit Transfer(
      address(0),
      publicsaleWallet,
      publicsaleTokens
    );
  }

  /// @notice Applies anti-bot sell tax. To be called by the deployer directly before launching the liquidity pool. Can only be called once.
  function applyInitialSellTax() public onlyOwner() {
    require(!initialSellTaxSet, "Initial sell tax has already been set.");
    initialSellTaxSet = true;
    initialSellTaxActive = true;
  }

  /// @notice Removes anti-bot sell tax. To be called by the deployer after a few hours of calling applyInitialSellTax().
  function removeInitialSellTax() public onlyOwner() {
    initialSellTaxActive = false;
  }

  /// @notice Set Safu wallet address.
  function setSafuAddress(address safuAddress) public onlyOwner() {
    safuWallet = safuAddress;
  }

  /// @notice Set Storng4Good address.
  function setStrong4GoodAddress(address strong4goodAddress) public onlyOwner() {
    strong4goodWallet = strong4goodAddress;
  }

  /// @notice Store reference to the current liquidity pool contract.
  function setTokenPairAddress(address tokenPair) public onlyOwner() {
    tokenPairAddress = tokenPair;

    //exclude token pair address from reflection.
    if(!_isExcluded[tokenPairAddress]){
      _isExcluded[tokenPairAddress] = true;
      _excluded.push(tokenPairAddress);
    }    
  }

  /// @notice Gets the token's name
  /// @return Name
  function name() public view override returns (string memory) {
    return _name;
  }

  /// @notice Gets the token's symbol
  /// @return Symbol
  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  /// @notice Gets the token's decimals
  /// @return Decimals
  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  /// @notice Gets the total token supply (circulating supply from the reserve)
  /// @return Total token supply
  function totalSupply() public pure override returns (uint256) {
    return _totalSupply;
  }

  /// @notice Gets the token balance of given account
  /// @param account - Address to get the balance of
  /// @return Account's token balance
  function balanceOf(address account) public view override returns (uint256) {
    if (_isExcluded[account]) return _circulatingTokenBalance[account];
    return tokenBalanceFromReserveAmount(_reserveTokenBalance[account]);
  }

  /// @notice Transfers tokens from msg.sender to recipient
  /// @param recipient - Recipient of tokens
  /// @param amount - Amount of tokens to send
  /// @return true
  function transfer(
    address recipient,
    uint256 amount
  ) public override returns (bool) {
    _transfer(
      _msgSender(),
      recipient,
      amount
    );
    return true;
  }

  /// @notice Gets the token spend allowance for spender of owner
  /// @param owner - Owner of the tokens
  /// @param spender - Account with allowance to spend owner's tokens
  /// @return allowance amount
  function allowance(
    address owner,
    address spender
  ) public view override returns (uint256) {
    return _allowances[owner][spender];
  }

  /// @notice Approve token transfers from a 3rd party
  /// @param spender - The account to approve for spending funds on behalf of msg.senderds
  /// @param amount - The amount of tokens to approve
  /// @return true
  function approve(
    address spender,
    uint256 amount
  ) public override returns (bool) {
    _approve(
      _msgSender(),
      spender,
      amount
    );
    return true;
  }

  /// @notice Transfer tokens from a 3rd party
  /// @param sender - The account sending the funds
  /// @param recipient - The account receiving the funds
  /// @param amount - The amount of tokens to send
  /// @return true
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public override returns (bool) {
    _transfer(
      sender,
      recipient,
      amount
    );
    _approve(
      sender,
      _msgSender(),
      _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance")
    );
    return true;
  }

  /// @notice Increase 3rd party allowance to spend funds
  /// @param spender - The account being approved to spend on behalf of msg.sender
  /// @param addedValue - The amount to add to spending approval
  /// @return true
  function increaseAllowance(
    address spender,
    uint256 addedValue
  ) public virtual returns (bool) {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].add(addedValue)
    );
    return true;
  }

  /// @notice Decrease 3rd party allowance to spend funds
  /// @param spender - The account having approval revoked to spend on behalf of msg.sender
  /// @param subtractedValue - The amount to remove from spending approval
  /// @return true
  function decreaseAllowance(
    address spender,
    uint256 subtractedValue
  ) public virtual returns (bool) {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
    );
    return true;
  }

  /// @notice Gets the contract owner
  /// @return contract owner's address
  function getOwner() external override view returns (address) {
    return owner();
  }

  /// @notice Tells whether or not the address is excluded from owning reserve balance
  /// @param account - The account to test
  /// @return true or false
  function isExcluded(
    address account
  ) public view returns (bool) {
    return _isExcluded[account];
  }

  /// @notice Gets the total amount of fees spent
  /// @return Total amount of transaction fees
  function totalFees() public view returns (uint256) {
    return _transactionFeeTotal;
  }

  /// @notice Distribute tokens from the msg.sender's balance amongst all holders
  /// @param transferAmount - The amount of tokens to distribute
  function distributeToAllHolders(
    uint256 transferAmount
  ) public {
    address sender = _msgSender();
    require(!_isExcluded[sender], "Excluded addresses cannot call this function");
    (
      ,
      ReserveValues memory reserveValues
      ,
    ) = _getValues(transferAmount);
    _reserveTokenBalance[sender] = _reserveTokenBalance[sender].sub(reserveValues.reserveAmount);
    _totalReserve = _totalReserve.sub(reserveValues.reserveAmount);
    _transactionFeeTotal = _transactionFeeTotal.add(transferAmount);
  }

  /// @notice Gets the reserve balance based on amount of tokens 
  /// @param transferAmount - The amount of tokens to distribute
  /// @param deductTransferReserveFee - Whether or not to deduct the transfer fee
  /// @return Reserve balance
  function reserveBalanceFromTokenAmount(
    uint256 transferAmount,
    bool deductTransferReserveFee
  ) public view returns(uint256) {
    (
      ,
      ReserveValues memory reserveValues
      ,
    ) = _getValues(transferAmount);
    require(transferAmount <= _totalSupply, "Amount must be less than supply");
    if (!deductTransferReserveFee) {       
      return reserveValues.reserveAmount;
    } else {
      return reserveValues.reserveTransferAmount;
    }
  }

  /// @notice Gets the token balance based on the reserve amount
  /// @param reserveAmount - The amount of reserve tokens owned
  /// @dev Dividing the reserveAmount by the currentRate is identical to multiplying the reserve amount by the ratio of totalSupply to totalReserve, which will be much less than 100% 
  /// @return Token balance
  function tokenBalanceFromReserveAmount(
    uint256 reserveAmount
  ) public view returns(uint256) {
    require(reserveAmount <= _totalReserve, "Amount must be less than total reflections");
    uint256 currentRate =  getRate();
    return reserveAmount.div(currentRate);
  }

  /// @notice Excludes an account from owning reserve balance. Useful for exchange and pool addresses.
  /// @notice Do not exclude the StrongNode Safu and Strong4Good wallets.
  /// @param account - The account to exclude
  function excludeAccount(
    address account
  ) external onlyOwner() {
    require(!_isExcluded[account], "Account is already excluded");
    if(_reserveTokenBalance[account] > 0) {
        _circulatingTokenBalance[account] = tokenBalanceFromReserveAmount(_reserveTokenBalance[account]);
    }
    _isExcluded[account] = true;
    _excluded.push(account);
  }

  /// @notice Includes an excluded account from owning reserve balance
  /// @param account - The account to include
  function includeAccount(
    address account
  ) external onlyOwner() {
    require(_isExcluded[account], "Account is already excluded");
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_excluded[i] == account) {
        _excluded[i] = _excluded[_excluded.length - 1];
        _circulatingTokenBalance[account] = 0;
        _isExcluded[account] = false;
        _excluded.pop();
        break;
      }
    }
  }

  /// @notice Approves spender to spend owner's tokens
  /// @param owner - The account approving spender to spend tokens
  /// @param spender - The account to spend the tokens
  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) private {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  /// @notice Transfers 0.2% of every transaction to the StrongNode Safu wallet
  /// @notice Transfers 0.2% of every transaction to the Strong4Good wallet.
  /// @dev These addresses will never be excluded from receiving reflect, so we only increase their reserve balances
  function applyExternalTransactionTax(
    ReserveValues memory reserveValues,
    TransactionValues memory transactionValues,
    address sender
  ) private {
    _reserveTokenBalance[safuWallet] = _reserveTokenBalance[safuWallet].add(reserveValues.reserveTransferAmountSafu);
    emit Transfer(
      sender,
      safuWallet,
      transactionValues.sneSafu
    );  
    _reserveTokenBalance[strong4goodWallet] = _reserveTokenBalance[strong4goodWallet].add(reserveValues.reserveTransferAmountStrong4Good);
    emit Transfer(
      sender,
      strong4goodWallet,
      transactionValues.sneStrong4Good
    );     
  }

  /// @notice Transfers tokens from sender to recipient differently based on inclusivity and exclusivity to reserve balance holding
  /// @param sender - The account sending tokens
  /// @param recipient - The account receiving tokens
  /// @param amount = The amount of tokens to send
  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) private {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");
    if (_isExcluded[sender] && !_isExcluded[recipient]) {
        _transferFromExcluded(
          sender,
          recipient,
          amount
        );
    } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
        _transferToExcluded(
          sender,
          recipient,
          amount
        );
    } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
        _transferStandard(
          sender,
          recipient,
          amount
        );
    } else if (_isExcluded[sender] && _isExcluded[recipient]) {
        _transferBothExcluded(
          sender,
          recipient,
          amount
        );
    } else {
        _transferStandard(
          sender,
          recipient,
          amount
        );
    }
  }

  /// @notice Transfers tokens from included sender to included recipient 
  /// @param sender - The account sending tokens
  /// @param recipient - The account receiving tokens
  /// @param transferAmount = The amount of tokens to send
  /// @dev Transferring tokens changes the reserve balances of the sender and recipient + reduces the totalReserve. It doesn't directly change the circulatingTokenBalance 
  function _transferStandard(
    address sender,
    address recipient,
    uint256 transferAmount
  ) private {
    (
      TransactionValues memory transactionValues,
      ReserveValues memory reserveValues
      ,
    ) = _getValues(transferAmount);
    _reserveTokenBalance[sender] = _reserveTokenBalance[sender].sub(reserveValues.reserveAmount);
    _reserveTokenBalance[recipient] = _reserveTokenBalance[recipient].add(reserveValues.reserveTransferAmount);
    emit Transfer(
      sender,
      recipient,
      transactionValues.netTransferAmount
    );
    applyExternalTransactionTax(
      reserveValues,
      transactionValues,
      sender
    );
    _applyFees(
      reserveValues.reserveFee,
      transactionValues.transactionFee
    );
  }

  /// @notice Transfers tokens from included sender to excluded recipient 
  /// @param sender - The account sending tokens
  /// @param recipient - The account receiving tokens
  /// @param transferAmount = The amount of tokens to send
  /// @dev Transferring tokens to an excluded address directly increases the circulatingTokenBalance of the recipient, because excluded accounts only use that metric to calculate balances
  /// @dev Reserve balance is also transferred, in case the receiving address becomes included again
  function _transferToExcluded(
    address sender,
    address recipient,
    uint256 transferAmount
  ) private {
    (
      TransactionValues memory transactionValues,
      ReserveValues memory reserveValues
      ,
    ) = _getValues(transferAmount);

    _reserveTokenBalance[sender] = _reserveTokenBalance[sender].sub(reserveValues.reserveAmount);

    // No tx fees for funding initial Token Pair contract. Only for transferToExcluded, all pools will be excluded from receiving reflect.
    if (recipient == tokenPairAddress) {
      _reserveTokenBalance[recipient] = _reserveTokenBalance[recipient].add(reserveValues.reserveAmount);   
      _circulatingTokenBalance[recipient] = _circulatingTokenBalance[recipient].add(transferAmount);

      emit Transfer(
        sender,
        recipient,
        transferAmount
      );

    } else {
      _reserveTokenBalance[recipient] = _reserveTokenBalance[recipient].add(reserveValues.reserveTransferAmount); 
      _circulatingTokenBalance[recipient] = _circulatingTokenBalance[recipient].add(transactionValues.netTransferAmount);
      emit Transfer(
        sender,
        recipient,
        transactionValues.netTransferAmount
      );
      applyExternalTransactionTax(
        reserveValues,
        transactionValues,
        sender
      );
      _applyFees(
        reserveValues.reserveFee,
        transactionValues.transactionFee
      );
    }
  }

  /// @notice Transfers tokens from excluded sender to included recipient
  /// @param sender - The account sending tokens
  /// @param recipient - The account receiving tokens
  /// @param transferAmount = The amount of tokens to send
  /// @dev Transferring tokens from an excluded address reduces the circulatingTokenBalance directly but adds only reserve balance to the included recipient
  function _transferFromExcluded(
    address sender,
    address recipient,
    uint256 transferAmount
  ) private {
    (
      TransactionValues memory transactionValues,
      ReserveValues memory reserveValues
      ,
    ) = _getValues(transferAmount);
    _circulatingTokenBalance[sender] = _circulatingTokenBalance[sender].sub(transferAmount);
    _reserveTokenBalance[sender] = _reserveTokenBalance[sender].sub(reserveValues.reserveAmount);

    // only matters when transferring from the Pair contract (which is excluded)
    if (!initialSellTaxActive) {
      _reserveTokenBalance[recipient] = _reserveTokenBalance[recipient].add(reserveValues.reserveTransferAmount);
      emit Transfer(
        sender,
        recipient,
        transactionValues.netTransferAmount
      );
      applyExternalTransactionTax(
        reserveValues,
        transactionValues,
        sender
      );
      _applyFees(
        reserveValues.reserveFee,
        transactionValues.transactionFee
      );
    } else {
      // Sell tax of 90% to prevent bots from sniping the liquidity pool. Should be active for a few hours after liquidity pool launch.
      _reserveTokenBalance[recipient] = _reserveTokenBalance[recipient].add(reserveValues.reserveAmount.div(10));
      emit Transfer(
        sender,
        recipient,
        transferAmount.div(10)
      );
    }
  }

  /// @notice Transfers tokens from excluded sender to excluded recipient 
  /// @param sender - The account sending tokens
  /// @param recipient - The account receiving tokens
  /// @param transferAmount = The amount of tokens to send
  /// @dev Transferring tokens from and to excluded addresses modify both the circulatingTokenBalance & reserveTokenBalance on both sides, in case one address is included in the future
  function _transferBothExcluded(
    address sender,
    address recipient,
    uint256 transferAmount
  ) private {
    (
      TransactionValues memory transactionValues,
      ReserveValues memory reserveValues
      ,
    ) = _getValues(transferAmount);
    _circulatingTokenBalance[sender] = _circulatingTokenBalance[sender].sub(transferAmount);
    _reserveTokenBalance[sender] = _reserveTokenBalance[sender].sub(reserveValues.reserveAmount);
    _reserveTokenBalance[recipient] = _reserveTokenBalance[recipient].add(reserveValues.reserveTransferAmount);   
    _circulatingTokenBalance[recipient] = _circulatingTokenBalance[recipient].add(transactionValues.netTransferAmount); 

    emit Transfer(
      sender,
      recipient,
      transactionValues.netTransferAmount
    );
    applyExternalTransactionTax(
      reserveValues,
      transactionValues,
      sender
    );
    _applyFees(
      reserveValues.reserveFee,
      transactionValues.transactionFee
    );
  }

  /// @notice Distributes the fee accordingly by reducing the total reserve supply. Increases the total transaction fees
  /// @param reserveFee - The amount to deduct from totalReserve, derived from transactionFee
  /// @param transactionFee - The actual token transaction fee
  function _applyFees(
    uint256 reserveFee,
    uint256 transactionFee
  ) private {
    _totalReserve = _totalReserve.sub(reserveFee);
    _transactionFeeTotal = _transactionFeeTotal.add(transactionFee);
  }

  /// @notice Utility function - gets values necessary to facilitate a token transaction
  /// @param transferAmount - The transfer amount specified by the sender
  /// @return values for a token transaction
  function _getValues(
    uint256 transferAmount
  ) private view returns (TransactionValues memory, ReserveValues memory, uint256) {
    TransactionValues memory transactionValues = _getTValues(transferAmount);
    uint256 currentRate = getRate();
    ReserveValues memory reserveValues = _getRValues(
      transferAmount,
      transactionValues,
      currentRate
    );

    return (
      transactionValues,
      reserveValues,
      currentRate
    );
  }

  /// @notice Utility function - gets transaction values
  /// @param transferAmount - The transfer amount specified by the sender
  /// @return Net transfer amount for the recipient and the transaction fee
  function _getTValues(
    uint256 transferAmount
  ) private view returns (TransactionValues memory) {
    TransactionValues memory transactionValues;

    // 0.37% fee to all StrongNode Token holders.
    transactionValues.transactionFee = transferAmount.mul(redistributionFee).div(10000);

    // 0.2% fee to StrongNode Safu address.
    transactionValues.sneSafu = transferAmount.mul(safuFee).div(10000);

    // 0.2% fee to Strong4Good Address.
    transactionValues.sneStrong4Good = transferAmount.mul(strong4goodFee).div(10000);

    // Net transfer amount to recipient
    transactionValues.netTransferAmount = transferAmount.sub(transactionValues.transactionFee).sub(transactionValues.sneSafu).sub(transactionValues.sneStrong4Good);
    
    return transactionValues;
  }

  /// @notice Utility function - gets reserve transaction values
  /// @param transferAmount - The transfer amount specified by the sender
  /// @param currentRate - The current rate - ratio of reserveSupply to totalSupply
  /// @return Net transfer amount for the recipient
  function _getRValues(
    uint256 transferAmount,
    TransactionValues memory transactionValues,
    uint256 currentRate
  ) private pure returns (ReserveValues memory) {
    ReserveValues memory reserveValues;
    reserveValues.reserveAmount = transferAmount.mul(currentRate);
    reserveValues.reserveFee = transactionValues.transactionFee.mul(currentRate);
    reserveValues.reserveTransferAmountSafu = transactionValues.sneSafu.mul(currentRate);
    reserveValues.reserveTransferAmountStrong4Good = transactionValues.sneStrong4Good.mul(currentRate);
    reserveValues.reserveTransferAmount = reserveValues.reserveAmount.sub(
      reserveValues.reserveFee
      ).sub(
        reserveValues.reserveTransferAmountSafu
        ).sub(
          reserveValues.reserveTransferAmountStrong4Good
        );

    return reserveValues;
  }

  /// @notice Utility function - gets the current reserve rate - totalReserve / totalSupply
  /// @return Reserve rate
  function getRate() public view returns(uint256) {
    (
      uint256 reserveSupply,
      uint256 totalTokenSupply
    ) = getCurrentSupply();
    return reserveSupply.div(totalTokenSupply);
  }

  /// @notice Utility function - gets total reserve and circulating supply
  /// @return Reserve supply, total token supply
  function getCurrentSupply() public view returns(uint256, uint256) {
    uint256 reserveSupply = _totalReserve;
    uint256 totalTokenSupply = _totalSupply;      
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_reserveTokenBalance[_excluded[i]] > reserveSupply || _circulatingTokenBalance[_excluded[i]] > totalTokenSupply) return (_totalReserve, _totalSupply);
      reserveSupply = reserveSupply.sub(_reserveTokenBalance[_excluded[i]]);
      totalTokenSupply = totalTokenSupply.sub(_circulatingTokenBalance[_excluded[i]]);
    }
    if (reserveSupply < _totalReserve.div(_totalSupply)) return (_totalReserve, _totalSupply);
    return (reserveSupply, totalTokenSupply);
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
        assembly {
            size := extcodesize(account)
        }
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

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
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
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
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
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
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
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
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
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

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

interface IBEP20 {
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  function totalSupply() external view returns (uint256);
  function decimals() external view returns (uint8);
  function symbol() external view returns (string memory);
  function name() external view returns (string memory);
  function getOwner() external view returns (address);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address _owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPancakePair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

