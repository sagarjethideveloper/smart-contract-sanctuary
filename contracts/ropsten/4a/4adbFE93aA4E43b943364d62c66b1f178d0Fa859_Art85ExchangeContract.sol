/**
 *Submitted for verification at BscScan.com on 2021-07-29
*/

pragma solidity ^0.5.0;
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

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

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }


    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}
contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () public{
        address msgSender = msg.sender;
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
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
contract FTS721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) public view returns (uint256 balance);    
    function tokenTransfer(address from, address to, uint256 tokenId) public;
    function _mint(address to, uint256 tokenId, string memory uri) public;
    function setApprovalForAll(address from, bool approved, uint256 tokenId) public ;
    function _burn(uint256 tokenId, address from) public;
    function _transferOwnership(address newOwner) public;
}
contract FTS1155{
    event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _value);
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
    event URI(string _value, uint256 indexed _id);

    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value) public;

    function balanceOf(address _owner, uint256 _id) public view returns (uint256);

    function setApprovalForAll(address from, address _operator, bool _approved) public;
    function isApprovedForAll(address _owner, address _operator) public view returns (bool);
    function mint(address from, uint256 _id, uint256 _supply, string memory _uri) public;
    function burn(address from, uint256 _id, uint256 _value) public ;
    function _transferOwnership(address newOwner) public;
}
contract BEP20 {
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
contract Sale is Ownable{
    event CancelOrder(address indexed from, uint256 indexed tokenId);
    event ChangePrice(address indexed from, uint256 indexed tokenId, uint256 indexed value);
    event OrderPlace(address indexed from, uint256 indexed tokenId, uint256 indexed value);
    event FeeDetails(uint256 indexed owner, uint256 indexed admin, uint256 indexed admin2);
    event Calcu(uint256 indexed owner, uint256 indexed admin, uint256 indexed admin2);
    event FeeDiv(uint256 indexed owner, uint256 indexed admin, uint256 indexed admin2);
    using SafeMath for uint256;
    struct Order{
        uint256 tokenId;
        uint256 price;
    }
    struct Royalty{    
        uint256 tokenId;    
        address[] royaltyaddress;   
        uint[] percentage;  
        uint royaltypercentage; 
    }
    mapping (uint => Royalty) public RoyaltyInfo;
    
    uint public totalroyalty = 0;
    uint public minroyalty = 0;
    uint public maxroyalty = 0;
    struct Swaped{
        address swapto;
    }
    uint256 private serviceValue;
    mapping (address => mapping (uint256 => Swaped)) public swapmap;
    mapping (address => mapping (uint256 => Order)) public order_place;
    mapping (uint256 => mapping (address => bool)) public checkOrder;
    mapping (uint256 =>  bool) public _operatorApprovals;
    mapping (uint256 => address) public _creator;
    mapping (uint256 => uint256) public _royal; 
    mapping (uint256 => mapping(address => uint256)) public balances;
    mapping (uint256 => uint256) public totalQuantity;
    mapping(string => address) private tokentype;
    uint256 public _tid;
    constructor(uint256 _serviceValue, uint256 id) public{
        serviceValue = _serviceValue;
        _tid = id;
    }
    function getTokenAddress(string memory _type) public view returns(address){
        return tokentype[_type];
    }
    function _addTokenType(string memory _type,address tokenAddress) internal onlyOwner{
        tokentype[_type] = tokenAddress;
    }
    function getServiceFee() public view returns(uint256){
        return (serviceValue.div(2)).mul(1e17);
    }
    function _orderPlace(address from, uint256 tokenId, uint256 _price) internal{
        require( balances[tokenId][from] > 0, "Is Not a Owner");
        Order memory order;
        order.tokenId = tokenId;
        order.price = _price;
        order_place[from][tokenId] = order;
        checkOrder[tokenId][from] = true;
        emit OrderPlace(from, tokenId, _price);
    }
    function _cancelOrder(address from, uint256 tokenId) internal{
        require(balances[tokenId][msg.sender] > 0, "Is Not a Owner");
        delete order_place[msg.sender][tokenId];
        checkOrder[tokenId][from] = false;
        emit CancelOrder(msg.sender, tokenId);
    }
    function _changePrice(uint256 value, uint256 tokenId) internal{
        require( balances[tokenId][msg.sender] > 0, "Is Not a Owner");
        require( value < order_place[msg.sender][tokenId].price);
        order_place[msg.sender][tokenId].price = value;
        emit ChangePrice(msg.sender, tokenId, value);
    }
    function _acceptBId(string memory tokenAss,address from, address admin, uint256 amount, uint256 tokenId) internal{
        require(_operatorApprovals[tokenId], "Token Not approved");
        require(balances[tokenId][msg.sender] > 0, "Is Not a Owner");
        (uint256 _adminfee, uint256 roy, uint256 netamount) = calc(amount, _royal[tokenId], serviceValue);
        BEP20 t = BEP20(tokentype[tokenAss]);
        t.transferFrom(from,admin,_adminfee);
        t.transferFrom(from,_creator[tokenId],roy);
        t.transferFrom(from,msg.sender,netamount);
    }
    function checkTokenApproval(uint256 tokenId, address from) internal view returns (bool result){
        require(checkOrder[tokenId][from], "This Token Not for Sale");
        require(_operatorApprovals[tokenId], "Token Not approved");
        return true;
    }
    function _saleToken(address payable from, uint256 tokenId, uint256 amount, string memory bidtoken) internal{
      require(amount == order_place[from][tokenId].price , "Insufficent found");
      require(checkTokenApproval(tokenId, from));    
      if(keccak256(abi.encodePacked((bidtoken))) == keccak256(abi.encodePacked(("BNB")))){   
        address payable admin = address(uint160(owner()));
        address payable create = address(uint160(_creator[tokenId]));
        (uint256 _adminfee, uint256 roy, uint256 netamount) = calc(amount, _royal[tokenId], serviceValue);
        admin.transfer(_adminfee);
        //create.transfer(roy);
        payforRoyalty(amount, tokenId);
        from.transfer(netamount);
      }
      else{
        (uint256 _adminfee, uint256 roy, uint256 netamount) = calc(amount, _royal[tokenId], serviceValue);
        BEP20 t = BEP20(tokentype[bidtoken]);
        address admin = owner();
        t.transferFrom(msg.sender,admin,_adminfee);
        //t.transferFrom(msg.sender,_creator[tokenId],roy);
        payforRoyaltyToken(amount, tokenId,from, tokentype[bidtoken]);
        t.transferFrom(msg.sender,from,netamount);
      }
        
    }
    function payforRoyalty(uint originalamount, uint tokenId) internal {   
            
        for(uint i=0;i<RoyaltyInfo[tokenId].royaltyaddress.length;i++){ 
             address payable payAddress = address(uint160(RoyaltyInfo[tokenId].royaltyaddress[i])); 
             uint256 roy = originalamount.mul(RoyaltyInfo[tokenId].percentage[i]).div(100); 
             payAddress.transfer(roy);  
        }   
            
    }
     function payforRoyaltyToken(uint originalamount, uint tokenId, address from, address token) internal {   
        
        BEP20 trnasferToken = BEP20(token);

        for(uint i=0;i<RoyaltyInfo[tokenId].royaltyaddress.length;i++){ 
             address payable payAddress = address(uint160(RoyaltyInfo[tokenId].royaltyaddress[i])); 
             uint256 roy = originalamount.mul(RoyaltyInfo[tokenId].percentage[i]).div(100); 
             trnasferToken.transferFrom(from,payAddress,roy);
        }   
            
    }
    function calc(uint256 amount, uint256 royal, uint256 _serviceValue) internal pure returns(uint256, uint256, uint256){
        uint256 fee = percent(amount, _serviceValue.div(1e8));
        uint256 roy = percent(amount, royal);
        uint256 netamount = amount.sub(fee.add(roy));
        fee = fee.add(fee);
        return (fee, roy, netamount);
    }
    function percent(uint256 value1, uint256 value2) internal pure returns(uint256){
        uint256 result = value1.mul(value2).div(100);
        return(result);
    }
    function setServiceValue(uint256 _serviceValue) internal{
        serviceValue = _serviceValue;
    }
    function swapfee(uint256 amount, string memory tokenAss) internal{
        BEP20 t = BEP20(tokentype[tokenAss]);
        address admin = owner();
        t.transferFrom(msg.sender,admin,amount);
        
    }
}
contract Art85ExchangeContract is Sale{
    event Approve(address indexed owner, uint256 indexed token_id,bool approved);
    event Swap(address indexed from, address indexed to,  uint256 token_id,uint256 fromToken_id);
    uint256 public tokenCount;
    mapping (uint256 => uint256) private _sfee;
    mapping (uint256 => mapping (address => bool)) public swapApp;
    constructor(uint256 _serviceValue, uint256 id) Sale(_serviceValue, id) public{
        
    }
    function getSfee(uint256 tokenId)public view returns(uint256){
        return _sfee[tokenId];
    }
    function addTokenType(string memory _type,address tokenAddress) public onlyOwner{
        _addTokenType(_type, tokenAddress);
    }
    function serviceFunction(uint256 _serviceValue) public onlyOwner{
        setServiceValue(_serviceValue);
    }
    function transferOwnershipForColle(address newOwner, address token721, address token1155) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        FTS721 tok= FTS721(token721);
        FTS1155 tok1155= FTS1155(token1155);
        tok._transferOwnership(newOwner);
        tok1155._transferOwnership(newOwner);
    }
    //mint function
    function mint(address token ,string memory tokenuri, uint256 value, uint256 tokenId, uint256 royal, uint256 _type, uint256 supply, uint256 sfee) public onlyOwner{
       require(_creator[tokenId] == address(0), "Token Already Minted");
       if(_type == 721){
           FTS721 tok= FTS721(token);
           _creator[tokenId]=msg.sender;
           _royal[tokenId]=royal;
           tok._mint(msg.sender, tokenId, tokenuri);
           balances[tokenId][msg.sender] = supply;
           if(value != 0){
                _orderPlace(msg.sender, tokenId, value);
            }
        }
        else{
            FTS1155 tok = FTS1155(token);
            tok.mint(msg.sender, tokenId, supply, tokenuri);
            _creator[tokenId]=msg.sender;
            _royal[tokenId]=royal;
            balances[tokenId][msg.sender] = supply;
            if(value != 0){
                _orderPlace(msg.sender, tokenId, value);
            }
       }
       totalQuantity[tokenId] = supply;
       _sfee[tokenId] = sfee;
       tokenCount++;
       
    }
    function addID(uint256 value) public onlyOwner returns(uint256){
        _tid = _tid + value;
        return _tid;
    }
    function setApprovalForAll(address token, uint256 _type, bool approved) public onlyOwner returns(uint256){
        uint256 id_ = addID(1);
        _operatorApprovals[id_] = true;
        if(_type == 721){
            FTS721 tok= FTS721(token);
            tok.setApprovalForAll(msg.sender, approved, id_);
        }
        else{
            FTS1155 tok = FTS1155(token);
            tok.setApprovalForAll(msg.sender, address(this), approved);
        }
        emit Approve(msg.sender, id_, approved);
        return id_;
    }
    function saleTokenTransfer(address payable from, uint256 tokenId, address token, uint256 _type, uint256 NOFToken) internal{
        if(_type == 721){
            if(checkOrder[tokenId][from]==true){
                delete order_place[from][tokenId];
                checkOrder[tokenId][from] = false;
            }
           tokenTrans(tokenId, from, msg.sender, NOFToken, _type, token);

       }
       else{
            tokenTrans(tokenId, from, msg.sender, NOFToken, _type, token);
            if(checkOrder[tokenId][from] == true){
                if(balances[tokenId][from] == 0){
                    delete order_place[from][tokenId];
                    checkOrder[tokenId][from] = false;
                }
            }
            
       }
    }
    function saleTokenTransfer(address payable from, uint256 tokenId, uint256 amount, address token, uint256 _type, uint256 NOFToken) public payable{
       _saleToken(from, tokenId, amount, "BNB");
       saleTokenTransfer(from, tokenId, token, _type, NOFToken);
    }
    function saleToken(address payable from, uint256 tokenId, uint256 amount, address token, uint256 _type, uint256 NOFToken, string memory tokenAss) public{
        _saleToken(from, tokenId, amount, tokenAss);
        saleTokenTransfer(from, tokenId, token, _type, NOFToken);
    }
    function acceptBId(string memory bidtoken,address bidaddr, uint256 amount, uint256 tokenId, address token, uint256 _type, uint256 NOFToken) public{
        _acceptBId(bidtoken, bidaddr, owner(), amount, tokenId);
        if(_type == 721){
           if(checkOrder[tokenId][msg.sender]==true){
                delete order_place[msg.sender][tokenId];
                checkOrder[tokenId][msg.sender] = false;
           }
           tokenTrans(tokenId, msg.sender, bidaddr, NOFToken, _type, token);        }
        else{
            tokenTrans(tokenId, msg.sender, bidaddr, NOFToken, _type, token);
            if(checkOrder[tokenId][msg.sender] == true){
                if(balances[tokenId][msg.sender] == 0){   
                    delete order_place[msg.sender][tokenId];
                    checkOrder[tokenId][msg.sender] = false;
                }
            }

        }
    }
    function orderPlace(uint256 tokenId, uint256 _price) public{
        _orderPlace(msg.sender, tokenId, _price);
    }
    function cancelOrder(uint256 tokenId) public{
        _cancelOrder(msg.sender, tokenId);
    }
    function changePrice(uint256 value, uint256 tokenId) public{
        _changePrice(value, tokenId);
    }
    function tokenTransfer(address to,uint256 tokenId, address token, string memory tokenAss, uint256 _type, uint256 NOFToken) public{
        require(checkTokenApproval(tokenId, msg.sender));
        if(_type == 721){
            if(checkOrder[tokenId][msg.sender]==true){
                delete order_place[msg.sender][tokenId];
                checkOrder[tokenId][msg.sender] = false;
            }
           tokenTrans(tokenId, msg.sender, to, NOFToken, _type, token);
       }
       else{
            tokenTrans(tokenId, msg.sender, to, NOFToken, _type, token);
            if(checkOrder[tokenId][msg.sender] == true){
                if(balances[tokenId][msg.sender] == 0){
                    delete order_place[msg.sender][tokenId];
                    checkOrder[tokenId][msg.sender] = false;
                }
            }
       }
       swapfee(_sfee[tokenId], tokenAss);
    }
    function tokenTrans(uint256 tokenId,address from, address to, uint256 NOFToken, uint256 _type, address token) internal{
        if(_type == 721){
           FTS721 tok= FTS721(token);
           tok.tokenTransfer(from, to, tokenId);
           balances[tokenId][from] = balances[tokenId][from] - NOFToken;
           balances[tokenId][to] = NOFToken;
           
        }
         else{
            FTS1155 tok= FTS1155(token);
            tok.safeTransferFrom(from, to, tokenId, NOFToken);
            balances[tokenId][from] = balances[tokenId][from] - NOFToken;
            balances[tokenId][to] = balances[tokenId][to] + NOFToken;
         }
         
    }
    function swapApprove(address from, uint256 tokenId) public{
        Swaped memory swap;
        swap.swapto = from;
        swapmap[msg.sender][tokenId] = swap;
    }
    function swap(address from, uint256 fromTokenId, uint256 tokenId, string memory tokenAss, address token, uint256 _type, uint256 NOFToken) public{
        require( swapmap[from][fromTokenId].swapto == msg.sender, "You need Approve from another User");
        require( balances[tokenId][msg.sender] >= NOFToken, "Your Not a Token Owner or insuficient Token Balance");
        require( balances[fromTokenId][from] >= NOFToken, "swap user Not a Token Owner or insuficient Token Balance");
        require( _operatorApprovals[tokenId] && _operatorApprovals[fromTokenId], "Token Not approved");
        //emit
        if(_type == 721){
            if(checkOrder[tokenId][msg.sender]==true){
                delete order_place[msg.sender][tokenId];
                checkOrder[tokenId][msg.sender] = false;
            }
            if(checkOrder[fromTokenId][from]==true){
                delete order_place[from][fromTokenId];
                checkOrder[fromTokenId][from] = false;
            }
           tokenTrans(tokenId, msg.sender, from, NOFToken, _type, token);
           tokenTrans(fromTokenId, from, msg.sender,NOFToken, _type, token);
       }
       else{
            tokenTrans(tokenId, msg.sender, from, NOFToken, _type, token);
            tokenTrans(fromTokenId, from, msg.sender,NOFToken, _type, token);
            if(checkOrder[tokenId][msg.sender] == true){
                if(balances[tokenId][msg.sender] == 0){
                    delete order_place[msg.sender][tokenId];
                    checkOrder[tokenId][msg.sender] = false;
                }
            }
            if(checkOrder[fromTokenId][from] == true){
                if(balances[fromTokenId][from] == 0){
                    delete order_place[from][fromTokenId];
                    checkOrder[fromTokenId][from] = false;
                }
            }
       }
       swapfee(_sfee[tokenId], tokenAss);    
     emit Swap(msg.sender, from, tokenId, fromTokenId);    
    }
    function burn(address from, uint256 tokenId, address token, uint256 _type, uint256 NOFToken ) public{
        require( balances[tokenId][msg.sender] >= NOFToken || msg.sender == owner(), "Your Not a Token Owner or insuficient Token Balance");
        require( balances[tokenId][from] >= NOFToken, "Your Not a Token Owner or insuficient Token Balance");
        require( _operatorApprovals[tokenId], "Token Not approved");
        if(_type == 721){
            FTS721 tok= FTS721(token);
            tok._burn(tokenId, from);
            balances[tokenId][from] = balances[tokenId][from].sub(NOFToken);
            if(checkOrder[tokenId][from]==true){
                delete order_place[from][tokenId];
                checkOrder[tokenId][from] = false;
            }
        }
        else{
            FTS1155 tok= FTS1155(token);
            tok.burn(from, tokenId, NOFToken);
            if(balances[tokenId][from] == NOFToken){
                if(checkOrder[tokenId][from]==true){
                    delete order_place[from][tokenId];
                    checkOrder[tokenId][from] = false;
                }
               
            }
            balances[tokenId][from] = balances[tokenId][from].sub(NOFToken);

        }
        tokenCount--;
        if(totalQuantity[tokenId] == NOFToken){
             _operatorApprovals[tokenId] = false;
             delete _creator[tokenId];
             delete _royal[tokenId];
        }
        totalQuantity[tokenId] = totalQuantity[tokenId].sub(NOFToken);

    }
    
    function changeroyaltypercentage(uint256 min, uint256 max) external onlyOwner { 
        minroyalty =min;
        maxroyalty =max;
    }
    function Royaltyaddress(uint tokenId) public view returns(address[5] memory List) { 
         for (uint i = 0; i<RoyaltyInfo[tokenId].royaltyaddress.length; i++) {  
            List[i] =RoyaltyInfo[tokenId].royaltyaddress[i];    
         }  
    }   
    function Royaltypercentage(uint tokenId) public view returns(uint[5] memory List) { 
         for (uint i = 0; i<RoyaltyInfo[tokenId].royaltyaddress.length; i++) {  
            List[i] =RoyaltyInfo[tokenId].percentage[i];    
         }  
    }

}

