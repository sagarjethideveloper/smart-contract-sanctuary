// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import '@openzeppelin/contracts/access/Ownable.sol';

// MINTER
import "./CryptoPageMinter.sol";

// NFT MARKETS
import "./CryptoPageNFTBank.sol";
import "./CryptoPageNFTMarket.sol";
import "./CryptoPageProfile.sol";

// TOKEN
// import "./CryptoPageToken.sol";

import "./interfaces/INFTMINT.sol";



contract PageAdmin is Ownable {

    PageMinter public PAGE_MINTER;
    address public PAGE_TOKEN;
    // PageNFTBank public PAGE_NFT_BANK;
    PageNFTMarket public PAGE_NFT_MARKET;
    PageProfile public PAGE_PROFILE;
    INFTMINT public PAGE_NFT;

    address public TreasuryAddress;

    constructor(address _TreasuryAddress) {
        TreasuryAddress = _TreasuryAddress;
        // LAUNCH ADMIN
        PAGE_MINTER = new PageMinter(address(this),_TreasuryAddress);
        // PAGE_TOKEN = new PageToken();
        // OTHERS

        // FOR TEST: -> transfer ownership
    }

    // INIT
    bool one_time = true;
    address[] private safeAddresses;
    function init( address _PAGE_NFT, address _PAGE_TOKEN ) public onlyOwner() {
        require(one_time, "CAN BE CALL ONLY ONCE");
        PAGE_NFT = INFTMINT(_PAGE_NFT);
        PAGE_TOKEN = _PAGE_TOKEN;

        // address _PAGE_MINTER = address(PAGE_MINTER);
        // PAGE_PROFILE = new PageProfile(_PAGE_MINTER);
        // PAGE_NFT_BANK = new PageNFTBank(_PAGE_NFT,_PAGE_MINTER);
        // PAGE_NFT_MARKET = new PageNFTMarket(_PAGE_NFT,_PAGE_MINTER);
        // SETUP PAGE_TOKEN
        // STOP INIT ...

        PAGE_MINTER.init(_PAGE_TOKEN,_PAGE_NFT);

        /*
        PAGE_MINTER.setMinter("NFT_CREATE", _PAGE_NFT, 10 ** 18, false);
        PAGE_MINTER.setMinter("NFT_CREATE_WITH_COMMENT", _PAGE_NFT, 50 ** 18, false);
        PAGE_MINTER.setMinter("NFT_CREATE_ADD_COMMENT", _PAGE_NFT, 40 ** 18, false);
        PAGE_MINTER.setMinter("NFT_ADD_COMMENT", _PAGE_NFT, 10 ** 18, false);
        */

        // transferOwnership(0x73837Fd1188B7200f2c116cf475aC3D71928D26B);

        // SET SAFE ADDRESSES
        // safeAddresses.push(address(PAGE_NFT_BANK));
        // safeAddresses.push(address(PAGE_NFT_MARKET));        
        // PAGE_MINTER.addSafe(safeAddresses);

        /*
        PAGE_MINTER.addSafe(address(PAGE_MINTER));
        PAGE_MINTER.addSafe(address(PAGE_NFT_BANK));
        PAGE_MINTER.addSafe(address(PAGE_NFT_MARKET));
        PAGE_MINTER.addSafe(address(PAGE_PROFILE));
        */

        /*
        PAGE_TOKEN = IERCMINT(_PAGE_TOKEN);
        PAGE_NFT = INFTMINT(_PAGE_NFT);

        // PAGE
        PAGE_MINTER.setMinter("NFT_CREATE", address(PAGE_NFT), 20 ** 18, false);
        PAGE_MINTER.setMinter("NFT_CREATE_WITH_COMMENT", address(PAGE_NFT), 100 ** 18, false);
        PAGE_MINTER.setMinter("NFT_CREATE_ADD_COMMENT", address(PAGE_NFT), 80 ** 18, false); // if create without comments, it can be add by this function
        PAGE_MINTER.setMinter("NFT_FIRST_COMMENT", address(PAGE_NFT), 10 ** 18, false);
        PAGE_MINTER.setMinter("NFT_SECOND_COMMENT", address(PAGE_NFT), 3 ** 18, false);
        // PAGE_MINTER.setMinter("BANK_SELL", PAGE_NFT.BANK_ADDRESS, 1 ** 18, true); // On the price effect amount of comments
        // PAGE_MINTER.setMinter("PROFILE_UPDATE", address(PAGE_NFT), 3 ** 18, false);
        */
        one_time = false;
    }

    // ONLY ADMIN
    function removeMinter(string memory _key) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.removeMinter(_key);
    }
    function setMinter(string memory _key, address _account, uint256 _pageamount) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.setMinter(_key, _account, _pageamount, false);
    }
    function setTreasuryFee(uint256 _percent) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.setTreasuryFee(_percent);
    }
    function setTreasuryAddress(address _treasury) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.setTreasuryAddress(_treasury);
    }

    // ++++
    function addSafe( address[] memory _safe ) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.addSafe(_safe); // memory
    }
    function removeSafe( address _safe ) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.removeSafe(_safe);
    }
    function changeSafe( address _from, address _to ) public onlyOwner() {
        require(!one_time, "INIT FUNCTION NOT CALLED");
        PAGE_MINTER.changeSafe(_from, _to);
    }

    function setBurnNFTcost( uint256 _pageamount ) public onlyOwner() {
        PAGE_MINTER.setBurnNFT(_pageamount);
    }
    function setNftBaseURL( string memory _url ) public onlyOwner() {
        PAGE_NFT.setBaseURL( _url );
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
pragma solidity ^0.8.4;

import "./interfaces/IMINTER.sol";
import "./interfaces/IERCMINT.sol";
// import "./interfaces/INFTMINT.sol";
import "./interfaces/ISAFE.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract PageMinter is IMINTER, ISAFE {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    IERCMINT private PAGE;

    address public TreasuryAddress = address(0);
    address private AdminAddress = address(0);
    uint256 public TreasuryFee = 1000; // 100 is 1% || 10000 is 100%

    // MINTERS
    Counters.Counter public _totalMinters;
    Counters.Counter public _minterId;
    // string[] public _listMinters;

    struct Minters {
        uint256 id;
        address author;
        uint256 amount;
        bool xmint;
    }
    mapping(string => Minters) public _minters;
    mapping(string => bool) private _keytank;

    /* INIT */
    constructor(address _admin, address _treasury) {   
        AdminAddress = _admin;     
        TreasuryAddress = _treasury; // setTreasuryAddress
    }

    bool private is_init = false;
    function init(address _page, address _nft) public onlyAdmin() {
        require(!is_init, "can be call only once");
        PAGE = IERCMINT(_page); // PAGE ADDRESS

        /* 
        PAGE_MINTER.addSafe(address(PAGE_MINTER));
        PAGE_MINTER.addSafe(address(PAGE_NFT_BANK));
        PAGE_MINTER.addSafe(address(PAGE_NFT_MARKET));
        PAGE_MINTER.addSafe(address(PAGE_PROFILE));
        */

        // setMinter("NFTBANK", address(_nft), 1 ** 18, true);

        /*** ***/
        setMinter("NFT_CREATE", _nft, 10 ** 18, false);
        setMinter("NFT_CREATE_WITH_COMMENT", _nft, 50 ** 18, false);
        setMinter("NFT_CREATE_ADD_COMMENT", _nft, 40 ** 18, false);
        setMinter("NFT_ADD_COMMENT", _nft, 10 ** 18, false);

        /*
        PAGE_TOKEN = IERCMINT(_PAGE_TOKEN);
        PAGE_NFT = INFTMINT(_PAGE_NFT);
        
        // PAGE
        PAGE_MINTER.setMinter("NFT_CREATE", address(PAGE_NFT), 20 ** 18, false);
        PAGE_MINTER.setMinter("NFT_CREATE_WITH_COMMENT", address(PAGE_NFT), 100 ** 18, false);
        PAGE_MINTER.setMinter("NFT_CREATE_ADD_COMMENT", address(PAGE_NFT), 80 ** 18, false); // if create without comments, it can be add by this function
        PAGE_MINTER.setMinter("NFT_FIRST_COMMENT", address(PAGE_NFT), 10 ** 18, false);
        PAGE_MINTER.setMinter("NFT_SECOND_COMMENT", address(PAGE_NFT), 3 ** 18, false);
        // PAGE_MINTER.setMinter("BANK_SELL", PAGE_NFT.BANK_ADDRESS, 1 ** 18, true); // On the price effect amount of comments
        // PAGE_MINTER.setMinter("PROFILE_UPDATE", address(PAGE_NFT), 3 ** 18, false);
        */
        is_init = true;
    }

    function _amount_mint(string memory _key, uint256 _address_count) public view override returns (uint256 amount_each, uint256 fee) {
        require(_keytank[_key], "_amount_mint: _key doesn't exists");        
        require(_address_count < 5, "address count > 4");
        require(_address_count > 0, "address count is zero");
        // (address author, uint256 amount) = _minters[_key];
        Minters storage minter = _minters[_key];
        fee = minter.amount.mul(TreasuryFee).div(10000);
        amount_each = (minter.amount - fee).div(_address_count);
    }
    function mint(string memory _key, address [] memory _to) public override{        
        require(is_init, "need to be init by admin");
        require(_keytank[_key], "mint: _key doesn't exists");

        // MINTER ONLY
        Minters storage minter =  _minters[_key];        
        require(minter.amount > 0, "mint: minter.amount can't be 0");
        require(minter.author == msg.sender, "mint: not minter");        

        uint256 address_count = _to.length;
        // require(_addresses[_key] != 0, "Address Amount is 0");
        require(address_count < 5, "address count > 4");
        require(address_count > 0, "address count is zero");

        (uint256 amount_each, uint256 fee) = _amount_mint(_key, address_count);

        // MINT TO ADDRESS
        for(uint256 i; i < address_count; i++){
            PAGE.mint(_to[i], amount_each);
        }

        // FEE TO ADDRESS
        PAGE.mint(TreasuryAddress, fee);
    }

    function mint1(string memory _key, address _to) public override{        
        require(is_init, "need to be init by admin");
        require(_keytank[_key], "mint: _key doesn't exists");

        // MINTER ONLY
        Minters storage minter =  _minters[_key];        
        require(minter.amount > 0, "mint: minter.amount can't be 0");
        require(minter.author == msg.sender, "mint: not minter");

        (uint256 amount_each, uint256 fee) = _amount_mint(_key, 1);

        // MINT TO ADDRESS
        PAGE.mint(_to, amount_each);

        // FEE TO ADDRESS
        PAGE.mint(TreasuryAddress, fee);
    }

    function mint2(string memory _key, address _to1, address _to2) public override{ 
        require(is_init, "need to be init by admin");
        require(_keytank[_key], "mint: _key doesn't exists");

        // MINTER ONLY
        Minters storage minter =  _minters[_key];        
        require(minter.amount > 0, "mint: minter.amount can't be 0");
        require(minter.author == msg.sender, "mint: not minter");

        (uint256 amount_each, uint256 fee) = _amount_mint(_key, 2);

        // MINT TO ADDRESS
        PAGE.mint(_to1, amount_each);
        PAGE.mint(_to2, amount_each);

        // FEE TO ADDRESS
        PAGE.mint(TreasuryAddress, fee);
    }
    function mint3(string memory _key, address _to1, address _to2, address _to3) public override{ 
        require(is_init, "need to be init by admin");
        require(_keytank[_key], "mint: _key doesn't exists");

        // MINTER ONLY
        Minters storage minter =  _minters[_key];        
        require(minter.amount > 0, "mint: minter.amount can't be 0");
        require(minter.author == msg.sender, "mint: not minter");

        (uint256 amount_each, uint256 fee) = _amount_mint(_key, 3);

        // MINT TO ADDRESS
        PAGE.mint(_to1, amount_each);
        PAGE.mint(_to2, amount_each);
        PAGE.mint(_to3, amount_each);

        // FEE TO ADDRESS
        PAGE.mint(TreasuryAddress, fee);
    } 

    function mintX(string memory _key, address [] memory _to, uint _multiplier) public override{
        require(is_init, "need to be init by admin");
        require(_keytank[_key], "mintX: _key doesn't exists");

        // MINTER ONLY
        Minters storage minter =  _minters[_key];        
        require(minter.amount > 0, "mint: minter.amount can't be 0");
        require(minter.author == msg.sender, "mint: not minter");
        require(minter.xmint, "xmint: not active");

        uint256 address_count = _to.length;
        // require(_addresses[_key] != 0, "Address Amount is 0");
        require(address_count < 5, "address count > 4");
        require(address_count > 0, "address count is zero");

        (uint256 amount_each, uint256 fee) = _amount_mint(_key, address_count);

        // MINT TO ADDRESS
        for(uint256 i; i < address_count; i++){
            PAGE.mint(_to[i], amount_each.mul(_multiplier));
        }

        // FEE TO ADDRESS
        PAGE.mint(TreasuryAddress, fee.mul(_multiplier));
    }

    // > > > onlyAdmin < < <  
    modifier onlyAdmin() {        
        require(msg.sender == AdminAddress, "onlyAdmin: caller is not the admin");
        _;
    }
    function removeMinter(string memory _key) public onlyAdmin() override {
        require(_keytank[_key], "removeMinter: _key doesn't exists");
        _keytank[_key] = false;
        // Minters memory toRemove = _minters[_key];
        // delete _listMinters[toRemove.id];
        delete _minters[_key];
        _totalMinters.decrement();
    }
    function setMinter(string memory _key, address _account, uint256 _pageamount, bool _xmint) public  onlyAdmin() override {
        if (_keytank[_key]) {
            Minters memory update = _minters[_key];
            update.amount = _pageamount;
            update.author = _account;
            update.xmint = _xmint;
        } else {
            _keytank[_key] = true;
            _minters[_key] = Minters({
                author: _account,
                amount: _pageamount,
                id: _minterId.current(),
                xmint: _xmint
            });
            // _listMinters[_minterId.current()] = _key;
            _minterId.increment();
            _totalMinters.increment();
        }
    }



    function testLastinterID() public view returns (uint256) {
        return _minterId.current();
    }
    function setTreasuryFee(uint256 _percent) public onlyAdmin() {
        require(_percent >= 10, "setTreasuryFee: minimum treasury fee percent is 0.1%");
        require(_percent <= 3000, "setTreasuryFee: maximum treasury fee percent is 30%");
        TreasuryFee = _percent;
    }
    function setTreasuryAddress(address _treasury) public onlyAdmin() {
        require(_treasury != address(0), "setTreasuryAddress: is zero address");
        TreasuryAddress = _treasury;
    }

    // GET FUNCTIONS
    function getMinter(string memory _key) public view override returns (
        uint256 id,
        address author,
        uint256 amount,
        bool xmint) {
        require(_keytank[_key], "getMinter: _key doesn't exists");
        Minters memory minter = _minters[_key];
        id = minter.id;
        author = minter.author;
        amount = minter.amount;
        xmint = minter.xmint;
    }

    // PROXY
    function burn( address from, uint256 amount ) public override onlySafe() {
        require(is_init, "need to be init by admin");

        // burn 100% PAGE
        PAGE.xburn(from, amount);

        // recover 10% to Treasury address
        PAGE.mint(TreasuryAddress, amount.mul(TreasuryFee).div(10000));
    }

    // ISAFE
    mapping(address => bool) private safeList;
    function isSafe( address _safe ) public override view returns (bool) {
        return safeList[_safe];
    }
    function addSafe( address[] memory _safe ) public override onlyAdmin() {        
        for(uint256 i; i < _safe.length; i++){
            safeList[_safe[i]] = true;
        }        
    }
    function removeSafe( address _safe ) public override onlyAdmin() {
        safeList[_safe] = false;        
    }
    function changeSafe( address _from, address _to ) public override onlyAdmin() {
        safeList[_from] = false;
        safeList[_to] = true;       
    }
    modifier onlySafe() {        
        require(isSafe(msg.sender), "onlySafe: caller is not in safe list");
        _;
    }

    // DESTROY NFT
    uint256 private CostBurnNFT;
    function setBurnNFT(uint256 _cost) public override onlyAdmin() {
        CostBurnNFT = _cost;
    }
    // VIEW FUNCTIONS
    function getBurnNFT() public override view returns (uint256) {
        return CostBurnNFT;
    }
    function getAdmin() public override view returns (address) {
        return AdminAddress;
    }
    function getPageToken() public override view returns (address) {
        return address(PAGE);
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// import "./interfaces/INFTMINT.sol";
import "./interfaces/IMINTER.sol";
import "./interfaces/IERCMINT.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract PageNFTBank {
    IERC721 public PAGE_NFT;
    IMINTER public PAGE_MINTER;
    IERCMINT public PAGE_TOKEN;
    constructor (address _PAGE_NFT, address _PAGE_MINTER) {
        PAGE_NFT = IERC721(_PAGE_NFT);
        PAGE_MINTER = IMINTER(_PAGE_MINTER);
        PAGE_TOKEN = IERCMINT(PAGE_MINTER.getPageToken());
    }

    function Buy(uint256 tokenId) public {
        require(PAGE_TOKEN.isEnoughOn(msg.sender, _buy), "Not enough tokens");
        require(address(this) == PAGE_NFT.ownerOf(tokenId), "only owner can call this function");
        PAGE_TOKEN.safeDeposit(msg.sender, address(this), _buy);
        PAGE_NFT.safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
    }
    function Sell(uint256 tokenId) public {
        // require(msg.sender == PAGE_MINTER.getAdmin(), "onlyAdmin: caller is not the admin");
        require(msg.sender == PAGE_NFT.ownerOf(tokenId), "only owner can call this function");
        PAGE_NFT.safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );
        
        // MINT
    }

    modifier onlyAdmin() {        
        require(msg.sender == PAGE_MINTER.getAdmin(), "onlyAdmin: caller is not the admin");
        _;
    }

    uint256 private _sell = 1 ether;
    uint256 private _buy = 1 ether;
    function setBuyPrice(uint256 _price) public onlyAdmin() {
        _buy = _price;
    }
    function setSellPrice(uint256 _price) public onlyAdmin() {
        _sell = _price;
    }
    function getPrice() public view returns(uint256 sell, uint256 buy ) {
        /**********
        (uint256 id,
         address author,
         uint256 amount,
         bool xmint) = PAGE_NFT.getMinter("NFTBANK");
         **********/

         // setMinter("NFTBANK", address(PAGE_NFT), 1 ** 18, true);

        sell = _sell;
        buy = _buy;
    }
    
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces/INFTMINT.sol";
import "./interfaces/IMINTER.sol";
import "./interfaces/IERCMINT.sol";

contract PageNFTMarket {
    INFTMINT public PAGE_NFT;
    IMINTER public PAGE_MINTER; 
    IERCMINT public PAGE_TOKEN;
    constructor (address _PAGE_NFT, address _PAGE_MINTER) {
        PAGE_NFT = INFTMINT(_PAGE_NFT);
        PAGE_MINTER = IMINTER(_PAGE_MINTER);
    }
    // DEPOSIT
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./interfaces/IMINTER.sol";
import "./interfaces/IERCMINT.sol";

contract PageProfile {
    IMINTER public PAGE_MINTER;
    constructor (address _PAGE_MINTER) {
        PAGE_MINTER = IMINTER(_PAGE_MINTER);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface INFTMINT {  
    function burn( uint256 amount ) external ;
    function setBaseURL( string memory url ) external ;
    function getBaseURL() external view returns (string memory);
    function creatorOf( uint256 tokenId ) external view returns (address);
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
pragma solidity ^0.8.4;

interface IMINTER {
    function _amount_mint(string memory _key, uint256 _address_count) external view returns (uint256 amount_each, uint256 fee);
    function mint(string memory _key, address [] memory _to) external;
    function mint1(string memory _key, address _to) external;
    function mint2(string memory _key, address _to1, address _to2) external;
    function mint3(string memory _key, address _to1, address _to2, address _to3) external;
    function mintX(string memory _key, address [] memory _to, uint _multiplier) external;
    function burn( address from, uint256 amount  ) external ;
    function removeMinter(string memory _key) external;
    function setMinter(string memory _key, address _account, uint256 _pageamount, bool _xmint) external;
    function getMinter(string memory _key) external view returns (
        uint256 id,
        address author,
        uint256 amount,
        bool xmint);
    // Burn NFT PRICE
    function setBurnNFT(uint256 _cost) external;
    function getBurnNFT() external view returns (uint256);
    function getAdmin() external view returns (address);
    function getPageToken() external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// IERC20

interface IERCMINT {
    function mint( address to, uint256 amount ) external ;
    function xburn(address from, uint256 amount) external ;
    function burn( uint256 amount ) external ;

    function safeDeposit(address from, address to, uint256 amount) external ;
    function safeWithdraw(address from, address to, uint256 amount) external ;

    // IF ENOUGH TOKENS ON BALANCE ??
    function isEnoughOn(address account, uint256 amount) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ISAFE {
    // function mint( address to, uint256 amount ) external ;    
    // function burn( uint256 amount ) external ;

    /*
    // is contains address[]
    address[] public safeMiners;
    mapping (address => bool) public Wallets;
    */
    // address[] public safeMiners;

    function isSafe( address _safe ) external view returns (bool) ;
    function addSafe( address[] calldata _safe ) external ;
    function removeSafe( address _safe ) external ;
    function changeSafe( address _from, address _to ) external ;

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

