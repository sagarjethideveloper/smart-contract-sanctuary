pragma solidity ^0.6.6;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./SignatureVerifyer.sol";

contract DAOPrivate is Ownable, ReentrancyGuard, SignatureVerifyer {
    using SafeMath for uint256;

    uint256 public currentUserID;

    struct User {
        bool exists;
        address wallet;
        uint256 referrer;
        // Uplines in different rounds
        mapping (uint256 => uint256) uplines;
        // Referrals in different rounds
        mapping (uint256 => uint256[]) referrals;
        uint256 level;
    }

    // Direct referrals count [userID -> count]
    mapping(uint256 => uint256) public selfRefsCount;
    // Claimed bonus refs count [userID -> count]
    mapping(uint256 => uint256) public claimedRefBonus;

    // Prepayed money amount [userID -> amount]
    mapping(uint256 => uint256) public prepayment;

    //Users [userID -> User]
    mapping (uint256 => User) public users;
    // Users [wallet -> userID]
    mapping (address => uint256) public userWallets;


    address feeReceiver;
    uint256 public rounds = 21;
    uint256[] public levelBase = [0.05 ether, 0.06 ether, 0.08 ether];
    uint256 private refBonusBaseAmount = 0.009 ether;
    mapping (uint256 => bool) bonusAutoClaimUser;

    event RegisterUser(
      address indexed user,
      uint256 userID,
      address indexed referrer,
      uint256 referrerID
    );
    event LevelUp(
      address indexed user,
      uint256 userID, uint256
      indexed levelID
    );
    event Transfer(
      address recipient,
      address sender,
      uint256 indexed recipientID,
      uint256 indexed senderID,
      uint256 amount,
      bool indexed superprofit
    );
    event LostProfit(
      address recipient,
      address sender,
      uint256 indexed recipientID,
      uint256 indexed senderID,
      uint256 amount
    );
    event ReferralFee(
      address recipient,
      address sender,
      address referral,
      uint256 indexed recipientID,
      uint256 indexed senderID,
      uint256 referralID,
      uint256 amount
    );

    constructor(address _owner, address _feeReceiver, address _signer) public {
      require(_owner != address(0), 'ownerIsZero');
      require(_feeReceiver != address(0), 'feeReceiverIsZero');

      _setSigner(_signer);

      feeReceiver = _feeReceiver;
      transferOwnership(_owner);

      currentUserID++;

      users[currentUserID] =  User({ exists: true, wallet: _owner, referrer: 1, level: 0 });
      userWallets[_owner] = currentUserID;
      bonusAutoClaimUser[currentUserID] = true;
      emit RegisterUser(_owner, currentUserID, _owner, currentUserID);

      users[currentUserID].level = rounds * levelBase.length;
      
      for (uint256 i = 0; i < rounds; i++) {
          users[currentUserID].uplines[i] = 1;
          // users[currentUserID].referrals[i] = new uint256[](0);
      }
    }

    fallback () external payable {
        revert('Not Allowed!');
    }

    receive () external payable {
        revert('Not Allowed');
    }

    function registerUser(
      uint256 _referrer,
      bytes memory signature
    )
      public
      payable
      nonReentrant
      verifySignature(signature)
    {
        require(_referrer > 0 && _referrer <= currentUserID, 'Invalid referrer ID');
        require(userWallets[msg.sender] == 0, 'User already registered');
        require(msg.value == levelBase[0], 'Wrong amount');

        currentUserID++;

        // Create user
        users[currentUserID] = User({
            exists: true,
            wallet: msg.sender,
            referrer: _referrer,
            level: 0
        });
        userWallets[msg.sender] = currentUserID;

        selfRefsCount[_referrer]++;

        emit RegisterUser(msg.sender,currentUserID, users[_referrer].wallet, _referrer);

        payForLevel(currentUserID, 1);
        
    }

    function buyLevel(uint256 levelID) public payable nonReentrant {
      uint256 userID = userWallets[msg.sender];
      require (userID > 0, '!userRegistered');
      require (users[userID].level < levelID, 'levelAlreadyActive');
      require (users[userID].level == levelID - 1, '!prevLevel');

      payForLevel(userID, levelID);
    }

    // Check amount and get level info
    function payForLevel(
      uint256 userID,
      uint256 levelID
    ) private {
      uint256 amount = lvlAmount(levelID);
      amount = amount.sub(prepayment[userID]);
      require(msg.value == amount, '!amount');

      (uint256 round, uint256 level) = getLevelInfo(levelID);
      payForLevel(userID, levelID, round, level, amount);
    }

    // up level, take fees and proceed payment
    function payForLevel(
      uint256 userID,
      uint256 levelID,
      uint256 round,
      uint256 level,
      uint256 amount
    ) private {

      levelUp(userID, levelID);

      uint256 upline = getUserUpline(userID, round, level + 1);

      // take fees
      // If first level in round -> take 1% fee to owner
      // Hold 19% fee on contract for direct ref bonuses
      uint256 fee = amount.div(100).mul(20);
      amount = amount.sub(fee);
      if(level == 0){
        if(bonusAutoClaimUser[users[userID].referrer]){
          sendETH(
            users[userID].wallet,
            fee.mul(90).div(100)
          );
          
        } else {
          sendETH(feeReceiver, fee.div(10));
        }
      }else{
      // Else send referral fee to origin referrer
        acceptReferralFee(
          userID,
          upline,
          users[userID].referrer,
          fee,
          levelID
        );
      }
      // Proceed payment
      acceptPaymentForLevel(userID, upline, levelID, round, level, amount, false);
      prepayment[userID] = 0;
    }

    function acceptReferralFee(
      uint256 senderID,
      uint256 referralID,
      uint256 userID,
      uint256 feeAmount,
      uint256 levelID
    ) private {
      if(users[userID].level >= levelID) {
        emit ReferralFee(
          users[userID].wallet,
          users[senderID].wallet,
          users[referralID].wallet,
          userID,
          senderID,
          referralID,
          feeAmount
        );
        sendETH(users[userID].wallet, feeAmount);
      } else {
        acceptReferralFee(
          senderID,
          referralID,
          users[userID].referrer,
          feeAmount,
          levelID
        );
      }
    }

    function acceptPaymentForLevel(
      uint256 senderID,
      uint256 userID,
      uint256 levelID,
      uint256 round,
      uint256 level,
      uint256 amount,
      bool superprofit
    ) private {
 
      // recepient don't have previous level -> pass payment to upline
      if(users[userID].level < levelID){
        userID = getUserUpline(userID, round, level + 1);
        emit LostProfit(
          users[userID].wallet,
          users[senderID].wallet,
          userID,
          senderID,
          amount
        );
        acceptPaymentForLevel(senderID, userID, levelID, round, level, amount, true);
        return;
      }

      // Is autopayment needed?
      // recipient doesn't have next level and it's not next round -> take prepayment for level
      if(
        users[userID].level < levelID + 1
        && level < levelBase.length - 1
      ){

        uint256 nextLevelPrice = lvlAmount(levelID + 1);
        uint256 prepaymentShare = nextLevelPrice.div(2 ** (level + 1));
        amount = amount.sub(prepaymentShare);

        // is enough to levelup? => levelup
        if(prepayment[userID] + prepaymentShare < nextLevelPrice){
          prepayment[userID] = prepayment[userID].add(prepaymentShare);
        }else{
          prepayment[userID] = 0;
          levelUp(userID, levelID + 1);
        }

        uint256 upline = getUserUpline(userID, round, level + 1);

        // Take referral fees
        uint256 fee = amount.div(100).mul(20);
        prepaymentShare = prepaymentShare.sub(fee);
        acceptReferralFee(
          userID,
          upline,
          users[userID].referrer,
          fee,
          levelID + 1
        );

        acceptPaymentForLevel(userID, upline, levelID + 1, round, level + 1, prepaymentShare, false);
      }
      if(amount > 0) {
        sendETH(users[userID].wallet, amount);

        emit Transfer(
          users[userID].wallet,
          users[senderID].wallet,
          userID,
          senderID,
          amount,
          superprofit
        );
      }
    }

    function levelUp(
      uint256 userID,
      uint256 levelID
    ) private {
      (uint256 round, uint256 level) = getLevelInfo(levelID);

      // if new round started -> find and set upline
      if(level == 0) { 
        uint256 upline = users[userID].referrer;
        if (round > 0) upline = findUplineUp(upline, round);
        upline = findUplineDown(upline, round);
        users[userID].uplines[round] = upline;
        users[upline].referrals[round].push(userID);
      }

      users[userID].level++;
      emit LevelUp(users[userID].wallet, userID, users[userID].level);

    }

    function sendETH(address wallet, uint256 amount) private {
      require(
        payable(wallet).send(amount),
        "!successTransfer"
      );
    }

    function getUserUpline(uint256 userID, uint256 round, uint256 height) public view returns (uint256) {
        while (height > 0) {
            userID = users[userID].uplines[round];
            height--;
        }
        return userID;
    }

    function findUplineUp(uint256 _user, uint256 _round) public view returns (uint256) {
        while (users[_user].uplines[_round] == 0) {
            _user = users[_user].uplines[0];
        }
        return _user;
    }

    function findUplineDown(uint256 userID, uint256 round) public view returns (uint256) {
      if (users[userID].referrals[round].length < 2) {
        return userID;
      }

      uint256[1024] memory referrals;
      referrals[0] = users[userID].referrals[round][0];
      referrals[1] = users[userID].referrals[round][1];

      uint256 referrer;

      for (uint256 i = 0; i < 1024; i++) {
        if (users[referrals[i]].referrals[round].length < 2) {
          referrer = referrals[i];
          break;
        }

        if (i >= 512) {
          continue;
        }

        referrals[(i+1)*2] = users[referrals[i]].referrals[round][0];
        referrals[(i+1)*2+1] = users[referrals[i]].referrals[round][1];
      }

      require(referrer != 0, 'Referrer not found');
      return referrer;
    }

    function lvlAmount (uint256 levelID) public view returns(uint256) {
      (uint256 round, uint256 level) = getLevelInfo(levelID);
      uint256 price = (levelBase[level] * (round + 1)**2 );
      return price;
    }

    function getLevelsInRound() public view returns (uint256) {
        return levelBase.length;
    }

    /// @notice Use for get round and level number by levelID
    /// @param levelID: levelID, starts from 1
    /// @return (round, level), starts from 0
    function getLevelInfo(uint256 levelID) public view returns(uint256, uint256){
      levelID--;
      require(levelID < rounds * levelBase.length, '!levelID');
      uint256 level = levelID % levelBase.length;
      uint256 round = (levelID - level) / levelBase.length;
      return(round, level);
    }

    function getReferralTree(uint256 _user, uint256 _treeLevel, uint256 _round) external view returns (uint256[] memory, uint256[] memory, uint256) {

        uint256 tmp = 2 ** (_treeLevel + 1) - 2;
        uint256[] memory ids = new uint256[](tmp);
        uint256[] memory lvl = new uint256[](tmp);

        ids[0] = (users[_user].referrals[_round].length > 0)? users[_user].referrals[_round][0]: 0;
        ids[1] = (users[_user].referrals[_round].length > 1)? users[_user].referrals[_round][1]: 0;
        lvl[0] = getMaxLevel(ids[0], _round);
        lvl[1] = getMaxLevel(ids[1], _round);

        for (uint256 i = 0; i < (2 ** _treeLevel - 2); i++) {
            tmp = i * 2 + 2;
            ids[tmp] = (users[ids[i]].referrals[_round].length > 0)? users[ids[i]].referrals[_round][0]: 0;
            ids[tmp + 1] = (users[ids[i]].referrals[_round].length > 1)? users[ids[i]].referrals[_round][1]: 0;
            lvl[tmp] = getMaxLevel(ids[tmp], _round);
            lvl[tmp + 1] = getMaxLevel(ids[tmp + 1], _round);
        }
        
        uint256 curMax = getMaxLevel(_user, _round);

        return(ids, lvl, curMax);
    }

    function getMaxLevel(uint256 userID, uint256 _round) private view returns (uint256){
        if (userID == 0) return 0;
        if (!users[userID].exists) return 0;
        (uint256 round, uint256 level) = getLevelInfo(users[userID].level);
        if(round > _round) return levelBase.length - 1;
        if(round < _round) return 0;
        if(round == _round) return level;
    }
    
    function getUplines(uint256 _user, uint256 _round) public view returns (uint256[] memory, address[] memory) {
        uint256[] memory uplines = new uint256[](levelBase.length);
        address[] memory uplinesWallets = new address[](levelBase.length);

        for(uint256 i = 0; i < levelBase.length; i++) {
            _user = users[_user].uplines[_round];
            uplines[i] = _user;
            uplinesWallets[i] = users[_user].wallet;
        }

        return (uplines, uplinesWallets);
    }

    function claimRefBonus() external nonReentrant {
      uint256 userID = userWallets[msg.sender];
      require(users[userID].exists, '!registered');
      require(bonusAutoClaimUser[userID] == false, '!allowed');

      uint256 amount = selfRefsCount[userID].sub(claimedRefBonus[userID]).mul(refBonusBaseAmount);
      claimedRefBonus[userID] = selfRefsCount[userID];

      require(amount > 0, 'nothingToClaim');
      require(address(this).balance >= amount, '!money');

      sendETH(msg.sender, amount);
    }

    function setSigner(address _signer) external onlyOwner {
      _setSigner(_signer);
    }

    function setMustVerifySignature(bool _mustVerifySignature) external onlyOwner {
      _setMustVerifySignature(_mustVerifySignature);
    }

}

pragma solidity ^0.6.6;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract SignatureVerifyer {
  address public signer;
  bool public mustVerifySignature = true;

  function _setSigner(address _signer) internal {
    require(_signer != address(0), 'signerIsZero');
    signer = _signer;
  }

  function _setMustVerifySignature(bool _mustVerifySignature) internal {
    mustVerifySignature = _mustVerifySignature;
  }

  modifier verifySignature(bytes memory signature) {
    if(mustVerifySignature) {
      bytes memory encoded = abi.encodePacked(msg.sender);
      bytes32 keccak = keccak256(encoded);
      bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(keccak);

      address recoveredSigner = ECDSA.recover(signedMessageHash, signature);
      require(recoveredSigner == signer, '!signature');
    }

    _;
  }

  // function getMessageSigner(bytes memory signature) public view returns (address) {
  //   bytes memory encoded = abi.encodePacked(msg.sender);
  //   bytes32 keccak = keccak256(encoded);
  //   bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
  //     keccak
  //   );

  //   address recoveredSigner = ECDSA.recover(signedMessageHash, signature);
  //   return recoveredSigner;
  // }

  // function getSenderAddressHash() public view returns (
  //   address sender,
  //   bytes memory encoded,
  //   bytes32 messageHash
  // ) {
  //   encoded = abi.encodePacked(msg.sender);
  //   bytes32 keccak = keccak256(encoded);
  //   bytes32 signedMessageHash = ECDSA.toEthSignedMessageHash(
  //     keccak
  //   );
  //   return (msg.sender, encoded, signedMessageHash);
  // }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
    constructor () internal {
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

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
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
        require(b <= a, "SafeMath: subtraction overflow");
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
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
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
        require(b > 0, "SafeMath: division by zero");
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
        require(b > 0, "SafeMath: modulo by zero");
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
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
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
        return a / b;
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
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

    constructor () internal {
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

