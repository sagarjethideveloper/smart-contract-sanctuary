/**
 *Submitted for verification at BscScan.com on 2021-11-15
*/

pragma solidity ^0.4.25;
// SPDX-License-Identifier: Unlicensed
import './Libraries/SafeMath.sol';
contract Token {
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function approveAndCall(address spender, uint tokens, bytes data) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


contract owned {
        address public owner;

        constructor() public {
            owner = msg.sender;
        }

        modifier onlyOwner {
            require(msg.sender == owner);
            _;
        }

        function transferOwnership(address newOwner) onlyOwner public {
            owner = newOwner;
        }
}

contract Hyperlock is owned{
    using SafeMath for uint256;

    /*
     * deposit vars
    */
    struct Items {
        address tokenAddress;
        address withdrawalAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
    }

    address public DevAdd;
    uint256 public DevFee;  //Fee% * 10000
    uint256 public depositId;
    uint256[] public allDepositIds;
    mapping (address => uint256[]) public depositsByWithdrawalAddress;
    mapping (uint256 => Items) public lockedToken;
    mapping (address => mapping(address => uint256)) public walletTokenBalance;

    event LogWithdrawal(address SentToAddress, uint256 AmountTransferred);

    /**
     * Constrctor function
    */
    constructor() public {
      DevAdd=msg.sender;
      DevFee= 500;
    }

    /**
     *lock tokens
    */



    function lockTokens(address _tokenAddress, uint256 _amount, uint256 _unlockTime) public returns (uint256 _id) {
        require(_amount > 0, 'token amount is Zero');
        require(_unlockTime < 10000000000, 'Enter an unix timestamp in seconds, not miliseconds');
        require(Token(_tokenAddress).approve(this, _amount), 'Approve tokens failed');

        uint256 FeeValue = _amount.mul(DevFee).div(1000000);
        uint256 LockValue = _amount.sub(FeeValue);
        require(Token(_tokenAddress).transferFrom(msg.sender, this, LockValue), 'Transfer of tokens failed');
        require(Token(_tokenAddress).transferFrom(msg.sender, DevAdd, FeeValue), 'Transfer of tokens failed');

        //update balance in address
        walletTokenBalance[_tokenAddress][msg.sender] = walletTokenBalance[_tokenAddress][msg.sender].add(LockValue);

        address _withdrawalAddress = msg.sender;
        _id = ++depositId;
        lockedToken[_id].tokenAddress = _tokenAddress;
        lockedToken[_id].withdrawalAddress = _withdrawalAddress;
        lockedToken[_id].tokenAmount = LockValue;
        lockedToken[_id].unlockTime = _unlockTime;
        lockedToken[_id].withdrawn = false;

        allDepositIds.push(_id);
        depositsByWithdrawalAddress[_withdrawalAddress].push(_id);
    }

    /**
     *withdraw tokens
    */
    function withdrawTokens(uint256 _id) public {
        require(block.timestamp >= lockedToken[_id].unlockTime, 'Tokens are locked');
        require(msg.sender == lockedToken[_id].withdrawalAddress, 'Can withdraw by withdrawal Address only');
        require(!lockedToken[_id].withdrawn, 'Tokens already withdrawn');
        require(Token(lockedToken[_id].tokenAddress).transfer(msg.sender, lockedToken[_id].tokenAmount), 'Transfer of tokens failed');

        lockedToken[_id].withdrawn = true;

        //update balance in address
        walletTokenBalance[lockedToken[_id].tokenAddress][msg.sender] = walletTokenBalance[lockedToken[_id].tokenAddress][msg.sender].sub(lockedToken[_id].tokenAmount);

        //remove this id from this address
        uint256 i; uint256 j;
        for(j=0; j<depositsByWithdrawalAddress[lockedToken[_id].withdrawalAddress].length; j++){
            if(depositsByWithdrawalAddress[lockedToken[_id].withdrawalAddress][j] == _id){
                for (i = j; i<depositsByWithdrawalAddress[lockedToken[_id].withdrawalAddress].length-1; i++){
                    depositsByWithdrawalAddress[lockedToken[_id].withdrawalAddress][i] = depositsByWithdrawalAddress[lockedToken[_id].withdrawalAddress][i+1];
                }
                depositsByWithdrawalAddress[lockedToken[_id].withdrawalAddress].length--;
                break;
            }
        }
        emit LogWithdrawal(msg.sender, lockedToken[_id].tokenAmount);
    }

     /*get total token balance in contract*/
    function getTotalTokenBalance(address _tokenAddress) view public returns (uint256)
    {
       return Token(_tokenAddress).balanceOf(this);
    }

    /*get total token balance by address*/
    function getTokenBalanceByAddress(address _tokenAddress, address _walletAddress) view public returns (uint256)
    {
       return walletTokenBalance[_tokenAddress][_walletAddress];
    }

    /*get allDepositIds*/
    function getAllDepositIds() view public returns (uint256[])
    {
        return allDepositIds;
    }

    /*get getDepositDetails*/
    function getDepositDetails(uint256 _id) view public returns (address, address, uint256, uint256, bool)
    {
        return(lockedToken[_id].tokenAddress,lockedToken[_id].withdrawalAddress,lockedToken[_id].tokenAmount,
        lockedToken[_id].unlockTime,lockedToken[_id].withdrawn);
    }

    /*get DepositsByWithdrawalAddress*/
    function getDepositsByWithdrawalAddress(address _withdrawalAddress) view public returns (uint256[])
    {
        return depositsByWithdrawalAddress[_withdrawalAddress];
    }

    /// Set Dev Address to Collect lock Fee
    function setDevAddress(address _DevAdd)
      external
      onlyOwner
    {
      DevAdd = _DevAdd;
    }

    /// Set Dev Lock Fee
    function setLockFee(uint256 _DevFee)
      external
    onlyOwner
    {
      DevFee = _DevFee;
    }

}

pragma solidity ^0.4.25;
//SPDX-License-Identifier: MIT

library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    require(c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a);
    return c;
  }

  function ceil(uint256 a, uint256 m) internal pure returns (uint256) {
    uint256 c = add(a,m);
    uint256 d = sub(c,1);
    return mul(div(d,m),m);
  }
}

