pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IDeathRoadNFT.sol";
import "../interfaces/INFTFactory.sol";
import "../interfaces/IMint.sol";
import "../interfaces/INFTCountdown.sol";
import "../lib/SignerRecover.sol";
import "../interfaces/ITokenVesting.sol";
import "../interfaces/IxDraceDistributor.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../lib/BlackholePrevention.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract GameControl is
    Ownable,
    SignerRecover,
    Initializable,
    BlackholePrevention,
    IERC721Receiver
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct DepositInfo {
        address depositor;
        uint256 timestamp;
        uint256 tokenId;
    }

    struct TokenUse {
        uint256 timestamp;
        address user;
        uint256 tokenId;
    }

    struct GameIdInfo {
        bool isRewardPaid;
        address player;
        uint256 gameId;
    }
    address public feeTo;

    mapping(uint256 => TokenUse) public tokenLastUseTimestamp; //used for prevent from playing more than token frequency
    IDeathRoadNFT public draceNFT;
    IERC20 public drace;
    IERC20 public xdrace;
    mapping(uint256 => DepositInfo) public tokenDeposits;
    mapping(address => uint256[]) public depositTokenList;

    //approvers will verify whether:
    //1. Game is in maintenance or not
    //2. Users are using at least one car and one gun in the token id list
    mapping(address => bool) public mappingApprover;
    ITokenVesting public tokenVesting;
    IxDraceDistributor public xDraceVesting;
    uint256 public gameCount;
    mapping(address => uint256) public cumulativeRewards;
    mapping(address => uint256[]) public gameIdList; //list of game id users play
    mapping(uint256 => GameIdInfo) public gameIdToPlayer;
    mapping(address => uint256) public playerGameCounts; //game count for each user

    mapping(uint256 => uint256) public tokenPlayingTurns;
    mapping(uint256 => bool) public isFreePlayingTurnsAdded;

    uint256 public constant FREE_PLAYING_TURNS = 20;

    uint256 public xDracePercent = 70;

    INFTFactory public factory;

    event TokenDeposit(address depositor, uint256 tokenId, uint256 timestamp);
    event TokenWithdraw(address withdrawer, uint256 tokenId, uint256 timestamp);
    event GameStart(
        address player,
        bytes tokenIds,
        uint256 timestamp,
        uint256 playerGameCount,
        uint256 globalGameCount
    );

    event TurnBuying(
        address payer,
        uint256 tokenId,
        uint256 price,
        uint256 timestamp
    );
    event RewardDistribution(
        address player,
        bytes gameIds,
        uint256 draceReward,
        uint256 xdraceReward,
        uint256 timestamp
    );

    function initialize(
        address _drace,
        address _draceNFT,
        address _approver,
        address _tokenVesting,
        address _countdownPeriod,
        address _factory,
        address _xdrace,
        address _feeTo,
        address _xDraceVesting
    ) external initializer {
        drace = IERC20(_drace);
        draceNFT = IDeathRoadNFT(_draceNFT);
        tokenVesting = ITokenVesting(_tokenVesting);
        countdownPeriod = INFTCountdown(_countdownPeriod);
        factory = INFTFactory(_factory);
        xdrace = IERC20(_xdrace);
        feeTo = _feeTo;
        if (_approver != address(0)) {
            mappingApprover[_approver] = true;
        }
        xDraceVesting = IxDraceDistributor(_xDraceVesting);
    }

    function setTokenVesting(address _vesting) external onlyOwner {
        tokenVesting = ITokenVesting(_vesting);
    }

    function setXDraceVesting(address _vesting) external onlyOwner {
        xDraceVesting = IxDraceDistributor(_vesting);
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }

    function setXDracePercent(uint256 _p) external onlyOwner {
        xDracePercent = _p;
    }

    function setFactory(address _factory) external onlyOwner {
        factory = INFTFactory(_factory);
    }

    function addApprover(address _approver, bool _val) public onlyOwner {
        mappingApprover[_approver] = _val;
    }

    function depositNFTsToPlay(uint256[] memory _tokenIds) external {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            draceNFT.transferFrom(msg.sender, address(this), _tokenIds[i]);
            tokenDeposits[_tokenIds[i]].depositor = msg.sender;
            tokenDeposits[_tokenIds[i]].timestamp = block.timestamp;
            tokenDeposits[_tokenIds[i]].tokenId = _tokenIds[i];
            depositTokenList[msg.sender].push(_tokenIds[i]);
            emit TokenDeposit(msg.sender, _tokenIds[i], block.timestamp);
        }
    }

    function startGame(
        uint256[] memory _tokenIds,
        uint256 _validTimestamp,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        require(
            _validTimestamp > block.timestamp,
            "signature timestamp too late"
        );
        bytes32 message = keccak256(
            abi.encode(msg.sender, _tokenIds, _validTimestamp)
        );
        address signer = recoverSigner(r, s, v, message);
        require(mappingApprover[signer], "invalid operator");

        _startGame(_tokenIds);
    }

    function _checkOrAddFreePlayingTurns(uint256 _tokenId) internal {
        if (!isFreePlayingTurnsAdded[_tokenId]) {
            isFreePlayingTurnsAdded[_tokenId] = true;
            tokenPlayingTurns[_tokenId] = tokenPlayingTurns[_tokenId].add(
                FREE_PLAYING_TURNS
            );
        }
    }

    function _startGame(uint256[] memory _tokenIds) internal {
        //verify token ids deposited and not used period a go
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            //check token deposited, if not, deposit it
            if (tokenDeposits[_tokenIds[i]].depositor != msg.sender) {
                //not deposit yet
                draceNFT.transferFrom(msg.sender, address(this), _tokenIds[i]);
                tokenDeposits[_tokenIds[i]].depositor = msg.sender;
                tokenDeposits[_tokenIds[i]].timestamp = block.timestamp;
                tokenDeposits[_tokenIds[i]].tokenId = _tokenIds[i];
                depositTokenList[msg.sender].push(_tokenIds[i]);
                emit TokenDeposit(msg.sender, _tokenIds[i], block.timestamp);
            }
            require(
                tokenLastUseTimestamp[_tokenIds[i]].timestamp.add(
                    getCountdownPeriod(_tokenIds[i])
                ) < block.timestamp,
                "NFT tokens used too frequently"
            );
            _checkOrAddFreePlayingTurns(_tokenIds[i]);
            require(
                tokenPlayingTurns[_tokenIds[i]] > 0,
                "No playing turn left"
            );

            //mark last time used
            tokenLastUseTimestamp[_tokenIds[i]].timestamp = block.timestamp;
            tokenLastUseTimestamp[_tokenIds[i]].user = msg.sender;
            tokenLastUseTimestamp[_tokenIds[i]].tokenId = _tokenIds[i];
            tokenPlayingTurns[_tokenIds[i]] = tokenPlayingTurns[_tokenIds[i]]
                .sub(1);
        }

        emit GameStart(
            msg.sender,
            abi.encode(_tokenIds),
            block.timestamp,
            playerGameCounts[msg.sender],
            gameCount
        );

        gameIdList[msg.sender].push(gameCount);
        gameIdToPlayer[gameCount] = GameIdInfo({
            isRewardPaid: false,
            player: msg.sender,
            gameId: gameCount
        });
        playerGameCounts[msg.sender]++;
        gameCount++;
    }

    function distributeRewards(
        address _recipient,
        uint256 _draceAmount,
        uint256 _xdraceAmount,
        uint256 _cumulativeReward,
        uint256[] memory _gameIds,
        bytes32 r,
        bytes32 s,
        uint8 v,
        bool _withdrawNFTs
    ) external {
        //verify signature
        bytes32 message = keccak256(
            abi.encode(
                _recipient,
                _draceAmount,
                _xdraceAmount,
                _cumulativeReward,
                _gameIds
            )
        );
        address signer = recoverSigner(r, s, v, message);
        require(mappingApprover[signer], "distributeRewards::invalid operator");

        _distribute(
            _recipient,
            _draceAmount,
            _xdraceAmount,
            _cumulativeReward,
            _gameIds,
            _withdrawNFTs
        );
    }

    function withdrawAllNFTs() public {
        uint256[] memory _tokenIds = depositTokenList[msg.sender];
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (tokenDeposits[_tokenIds[i]].depositor == msg.sender) {
                require(
                    tokenLastUseTimestamp[_tokenIds[i]].timestamp.add(600) <
                        block.timestamp,
                    "game is in play"
                );

                draceNFT.transferFrom(address(this), msg.sender, _tokenIds[i]);
                delete tokenDeposits[_tokenIds[i]];
                emit TokenWithdraw(msg.sender, _tokenIds[i], block.timestamp);
            }
        }
        delete depositTokenList[msg.sender];
    }

    function withdrawNFT(uint256 _tokenId) external {
        require(
            tokenDeposits[_tokenId].depositor == msg.sender,
            "withdrawNFT: NFT not yours"
        );

        uint256[] memory _tokenIds = depositTokenList[msg.sender];
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (_tokenId == _tokenIds[i]) {
                require(
                    tokenLastUseTimestamp[_tokenIds[i]].timestamp.add(600) <
                        block.timestamp,
                    "game is in play"
                );
                draceNFT.transferFrom(address(this), msg.sender, _tokenIds[i]);
                delete tokenDeposits[_tokenIds[i]];
                emit TokenWithdraw(msg.sender, _tokenIds[i], block.timestamp);
                depositTokenList[msg.sender][i] = depositTokenList[msg.sender][
                    _tokenIds.length - 1
                ];
                depositTokenList[msg.sender].pop();
                return;
            }
        }
    }

    //to save gas, we allow to claim rewards fro a range of game ids
    function _distribute(
        address _recipient,
        uint256 _draceAmount,
        uint256 _xdraceAmount,
        uint256 _cumulativeReward,
        uint256[] memory _gameIds,
        bool _withdrawNFTs
    ) internal {
        for (uint256 i = 0; i < _gameIds.length; i++) {
            require(
                !gameIdToPlayer[_gameIds[i]].isRewardPaid,
                "rewards already paid"
            );
            require(gameIdToPlayer[_gameIds[i]].player == _recipient, "No game id for this recipient");
            gameIdToPlayer[_gameIds[i]].isRewardPaid = true;
        }
        require(
            cumulativeRewards[_recipient].add(_draceAmount) <=
                _cumulativeReward,
            "reward exceed cumulative rewards"
        );
        cumulativeRewards[_recipient] = cumulativeRewards[_recipient].add(
            _draceAmount
        );

        //distribute rewards
        //xDRACE% released immediately, drace vested
        drace.safeApprove(address(tokenVesting), _draceAmount);
        tokenVesting.lock(_recipient, _draceAmount);

        IMint(address(xdrace)).mint(address(this), _xdraceAmount);
        IERC20(address(xdrace)).approve(address(xDraceVesting), _xdraceAmount);
        xDraceVesting.lock(_recipient, _xdraceAmount);

        emit RewardDistribution(
            _recipient,
            abi.encode(_gameIds),
            _draceAmount,
            _xdraceAmount,
            block.timestamp
        );

        if (_withdrawNFTs) {
            withdrawAllNFTs();
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        //do nothing
        return bytes4("");
    }

    INFTCountdown public countdownPeriod;

    function setCountdownHook(address _addr) external onlyOwner {
        countdownPeriod = INFTCountdown(_addr);
    }

    function buyPlayingTurn(
        uint256 _tokenId,
        uint256 _price, //price per turn
        uint256 _turnCount,
        bool _usexDrace,
        uint256 _expiry,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        bytes32 message = keccak256(
            abi.encode(
                "buyPlayingTurn",
                _tokenId,
                _price,
                _turnCount,
                _usexDrace,
                _expiry
            )
        );
        address signer = recoverSigner(r, s, v, message);
        require(mappingApprover[signer], "buyPlayingTurn::invalid operator");

        _buyPlayingTurn(_tokenId, _price, _turnCount, _usexDrace);
    }

    function _buyPlayingTurn(
        uint256 _tokenId,
        uint256 _price, //price per turn
        uint256 _turnCount,
        bool _usexDrace
    ) internal {
        uint256 _totalFee = _turnCount * _price;
        if (_usexDrace) {
            uint256 xDraceNeeded = _totalFee.mul(xDracePercent).div(100);

            drace.safeTransferFrom(
                msg.sender,
                feeTo,
                _totalFee.sub(xDraceNeeded)
            );
            ERC20Burnable(address(xdrace)).burnFrom(msg.sender, xDraceNeeded); //burn xDrace immediately
        } else {
            drace.safeTransferFrom(msg.sender, feeTo, _totalFee);
        }

        _checkOrAddFreePlayingTurns(_tokenId);
        tokenPlayingTurns[_tokenId] = tokenPlayingTurns[_tokenId].add(
            _turnCount
        );
        //reset timestamp
        tokenLastUseTimestamp[_tokenId].timestamp = 0;
        emit TurnBuying(msg.sender, _tokenId, _price, block.timestamp);
    }

    //each NFT has a period that it can only be used for playing if it was not used for playing more than period ago
    function getCountdownPeriod(uint256 _tokenId)
        public
        view
        returns (uint256)
    {
        //the higher level the token id is, the shorter period => users can play more times
        return countdownPeriod.getCountdownPeriod(_tokenId, address(draceNFT));
    }

    function getDepositTokenList(address _addr) external view returns (uint256[] memory) {
        return depositTokenList[_addr];
    }

    function withdrawEther(address payable receiver, uint256 amount)
        external
        virtual
        onlyOwner
    {
        _withdrawEther(receiver, amount);
    }

    function withdrawERC20(
        address payable receiver,
        address tokenAddress,
        uint256 amount
    ) external virtual onlyOwner {
        _withdrawERC20(receiver, tokenAddress, amount);
    }

    function withdrawERC721(
        address payable receiver,
        address tokenAddress,
        uint256 tokenId
    ) external virtual onlyOwner {
        _withdrawERC721(receiver, tokenAddress, tokenId);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
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

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IDeathRoadNFT is IERC721 {
    struct Box {
        bool isOpen;
        address owner;
        bytes box; // car, gun, rocket, other,...
        bytes pack; // 1star, 2star, 3star, 4star, 5star, legend,...
    }

    function getBoxes() external view returns (bytes[] memory);

    function getPacks() external view returns (bytes[] memory);

    function addBox(bytes memory _box) external;
    function addBoxes(bytes[] memory _boxes) external;

    function addPack(bytes memory _pack) external;
    function addPacks(bytes[] memory _packs) external;

//    function addFeature(bytes memory _box, bytes memory _feature) external;

    function buyBox(
        address _recipient,
        bytes memory _box,
        bytes memory _pack
    ) external returns (uint256);

    function buyCharm(address _recipient) external;

    function isBoxOwner(address _addr, uint256 _boxId)
        external
        view
        returns (bool);

    function isBoxOpen(uint256 _boxId) external view returns (bool);

    function mint(
        address _recipient,
        bytes[] memory _featureNames,
        bytes[] memory _featureValues
    ) external returns (uint256 _tokenId);

    function setBoxOpen(uint256 _boxId, bool _val) external;

    function getTokenFeatures(uint256 tokenId)
        external
        view
        returns (bytes[] memory _featureNames, bytes[] memory);

    function existTokenFeatures(uint256 tokenId) external view returns (bool);
    function mappingLuckyCharm(address) external view returns (uint256);
    function burn(uint256 tokenId) external;
    function decreaseCharm(address _addr) external;
    function latestTokenMinted(address _addr) external view returns (uint256);

    function updateFeature(address _owner, uint256 tokenId, bytes memory featureName, bytes memory featureValue) external;
}

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface INFTFactory {
    function getTokenFeatures(uint256 tokenId)
        external
        view
        returns (bytes[] memory, bytes[] memory);

    function existTokenFeatures(uint256 tokenId) external view returns (bool);

    struct UpgradeInfo {
        address user;
        bool useCharm;
        bool settled;
        bool upgradeStatus;
        uint256 failureRate; //percentX10
        uint256[3] tokenIds;
        bytes[] targetFeatureNames;
        bytes[][] targetFeatureValuesSet;
        bytes32 previousBlockHash;
    }

    struct OpenBoxInfo {
        address user;
        uint256 boxIdFrom;
        uint256 boxCount;
        bool settled;
        bool openBoxStatus;
        uint16[] featureValuesSet;
        bytes32 previousBlockHash;
        uint256 blockNumber;
    }

    function upgradesInfo(bytes32) external view returns (UpgradeInfo memory);

    function openBoxInfo(bytes32) external view returns (OpenBoxInfo memory);

    function addBoxReward(address addr, uint256 reward) external;

    function decreaseBoxReward(address addr, uint256 reduced) external;

    function boxRewards(address) external view returns (uint256);
}

pragma solidity ^0.8.0;

interface IMint {
    function mint(address _to, uint256 _amount) external;
}

pragma solidity ^0.8.0;
interface INFTCountdown {
    function getCountdownPeriod(uint256 _tokenId, address _nftFactory) external view returns (uint256);
}

pragma solidity ^0.8.0;

contract SignerRecover {
    function recoverSigner(bytes32 r, bytes32 s, uint8 v, bytes32 signedData) internal view returns (address) {
        address signer = ecrecover(keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", signedData)
            ), v, r, s);

        return signer;
    }
}

pragma solidity ^0.8.0;

interface ITokenVesting {
    function lock(address _addr, uint256 _amount) external;
}

pragma solidity ^0.8.0;

interface IxDraceDistributor {
    function lock(address _addr, uint256 _amount) external;
    function getLockedInfo(address _addr) external view returns (uint256 _locked, uint256 _releasable);
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

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @notice Prevents ETH or Tokens from getting stuck in a contract by allowing
 *  the Owner/DAO to pull them out on behalf of a user
 * This is only meant to contracts that are not expected to hold tokens, but do handle transferring them.
 */
contract BlackholePrevention {
  using Address for address payable;
  using SafeERC20 for IERC20;

  event WithdrawStuckEther(address indexed receiver, uint256 amount);
  event WithdrawStuckERC20(address indexed receiver, address indexed tokenAddress, uint256 amount);
  event WithdrawStuckERC721(address indexed receiver, address indexed tokenAddress, uint256 indexed tokenId);

  function _withdrawEther(address payable receiver, uint256 amount) internal virtual {
    require(receiver != address(0x0), "BHP:E-403");
    if (address(this).balance >= amount) {
      receiver.sendValue(amount);
      emit WithdrawStuckEther(receiver, amount);
    }
  }

  function _withdrawERC20(address payable receiver, address tokenAddress, uint256 amount) internal virtual {
    require(receiver != address(0x0), "BHP:E-403");
    if (IERC20(tokenAddress).balanceOf(address(this)) >= amount) {
      IERC20(tokenAddress).safeTransfer(receiver, amount);
      emit WithdrawStuckERC20(receiver, tokenAddress, amount);
    }
  }

  function _withdrawERC721(address payable receiver, address tokenAddress, uint256 tokenId) internal virtual {
    require(receiver != address(0x0), "BHP:E-403");
    if (IERC721(tokenAddress).ownerOf(tokenId) == address(this)) {
      IERC721(tokenAddress).transferFrom(address(this), receiver, tokenId);
      emit WithdrawStuckERC721(receiver, tokenAddress, tokenId);
    }
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC20.sol";
import "../../../utils/Context.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC20Burnable is Context, ERC20 {
    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
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
    function burnFrom(address account, uint256 amount) public virtual {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _burn(account, amount);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
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
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
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
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

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
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
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
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
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
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
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
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
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
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
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

