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
contract MyERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) public view returns (uint256 balance);    
    function tokenTransfer(address from, address to, uint256 tokenId) public;
    function _mint(address to, uint256 tokenId, string memory uri) public;
    function setApprovalForAll(address to, bool approved, uint256 tokenId) public ;
}
contract DigitalERC1155{
   
     event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _value);
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);
    event URI(string _value, uint256 indexed _id);

    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value) public;

    function balanceOf(address _owner, uint256 _id) external view returns (uint256);

    function setApprovalForAll(address _operator, bool _approved) public;
    function isApprovedForAll(address _owner, address _operator) public view returns (bool);
    function mint(address from, uint256 _id, uint256 _supply, string memory _uri) public;
}
contract ERC20 {
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
contract Sale{
    event CancelOrder(address indexed from, uint256 indexed tokenId);
    event ChangePrice(address indexed from, uint256 indexed tokenId, uint256 indexed value);
    event OrderPlace(address indexed from, uint256 indexed tokenId, uint256 indexed value);
    using SafeMath for uint256;
    struct Order{
        uint256 tokenId;
        uint256 price;
    }
    mapping (address => mapping (uint256 => Order)) public order_place;
    mapping (uint256 => mapping (address => bool)) public checkOrder;
    //mapping (address => mapping (uint256 => Bid)) public bid_place;
    mapping (uint256 =>  bool) public _operatorApprovals;
    mapping (uint256 => address) public _creator;
    mapping (uint256 => uint256) public _royal; 
    //mapping (uint256 => address) private _owners;
    mapping (uint256 => mapping(address => uint256)) public balances;
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
    function _acceptBId(address token,address from, address admin, uint256 amount, uint256 tokenId) internal{
        require(_operatorApprovals[tokenId], "Token Not approved");
        require(balances[tokenId][msg.sender] > 0, "Is Not a Owner");
        uint256 fee = amount.mul(5).div(100);
        uint256 ser=fee.div(2);
        uint256 or_am = amount.sub(ser);
        uint256 roy = or_am.mul(_royal[tokenId]).div(100);
        uint256 serfee = ser.add(roy);
        uint256 netamount = or_am.sub(serfee);
        ERC20 t = ERC20(token);
        t.transferFrom(from,admin,fee);
        t.transferFrom(from,_creator[tokenId],roy);
        t.transferFrom(from,msg.sender,netamount);
    }
    function checkTokenApproval(uint256 tokenId, address from) internal view returns (bool result){
        require(checkOrder[tokenId][from], "This Token Not for Sale");
        require(_operatorApprovals[tokenId], "Token Not approved");
        return true;
    }
    function _saleToken(address payable from, address payable admin,uint256 tokenId, uint256 amount) internal{
        require(amount> order_place[from][tokenId].price , "Insufficent found");
        require(checkTokenApproval(tokenId, from));
        address payable create = address(uint160(_creator[tokenId]));
        uint256 fee = amount.mul(5).div(100);
        uint256 ser=fee.div(2);
        uint256 or_am = amount.sub(ser);
        uint256 roy = or_am.mul(_royal[tokenId]).div(100);
        uint256 serfee = ser.add(roy);
        uint256 netamount = or_am.sub(serfee);
        admin.transfer(fee);
        create.transfer(roy);
        from.transfer(netamount);
    }
    

}
contract ExchangeContract is Sale{
    uint256 public tokenCount;
    constructor() public{}
    function mint(address token ,string memory tokenuri, uint256 value, uint256 tokenId, uint256 royal, uint256 _type, uint256 supply) public{
       require(_creator[tokenId] == address(0), "Token Already Minted");
       if(_type == 721){
           MyERC721 tok= MyERC721(token);
           _creator[tokenId]=msg.sender;
           _royal[tokenId]=royal;
           tok._mint(msg.sender, tokenId, tokenuri);
           balances[tokenId][msg.sender] = supply;
           if(value != 0){
                _orderPlace(msg.sender, tokenId, value);
            }
        }
        else{
            DigitalERC1155 tok = DigitalERC1155(token);
            tok.mint(msg.sender, tokenId, supply, tokenuri);
            _creator[tokenId]=msg.sender;
            _royal[tokenId]=royal;
            balances[tokenId][msg.sender] = supply;
            if(value != 0){
                _orderPlace(msg.sender, tokenId, value);
            }
       }
       tokenCount++;
       
    }
    function setApprovalForAll(address token, uint256 _type, address to, bool approved, uint256 tokenId) public {
        _operatorApprovals[tokenId] = true;
        if(_type == 721){
            MyERC721 tok= MyERC721(token);
            tok.setApprovalForAll(to,approved,tokenId);
        }
        else{
            DigitalERC1155 tok = DigitalERC1155(token);
            tok.setApprovalForAll(to, approved);
        }
    }
    function saleToken(address payable from, address payable admin,uint256 tokenId, uint256 amount, address token, uint256 _type, uint256 NOFToken) public payable{
       _saleToken(from, admin, tokenId, amount);
       if(_type == 721){
           MyERC721 tok= MyERC721(token);
            if(checkOrder[tokenId][from]==true){
                delete order_place[from][tokenId];
                checkOrder[tokenId][from] = false;
            }
           tok.tokenTransfer(from, msg.sender, tokenId);
           balances[tokenId][msg.sender] = NOFToken;
       }
       else{
            DigitalERC1155 tok= DigitalERC1155(token);
            tok.safeTransferFrom(from, msg.sender, tokenId, NOFToken);
            balances[tokenId][from] = balances[tokenId][from] - NOFToken;
            balances[tokenId][msg.sender] = balances[tokenId][from] + NOFToken;
            if(checkOrder[tokenId][from] == true){
                if(balances[tokenId][from] == 0){
                    delete order_place[from][tokenId];
                    checkOrder[tokenId][from] = false;
                }
            }
            
       }
        

    }
    function acceptBId(address btoken,address from, address admin, uint256 amount, uint256 tokenId, address token, uint256 _type, uint256 NOFToken) public{
        _acceptBId(btoken, from, admin, amount, tokenId);
        if(_type == 721){
           MyERC721 tok= MyERC721(token);
           if(checkOrder[tokenId][from]==true){
                delete order_place[from][tokenId];
                checkOrder[tokenId][from] = false;
           }
           tok.tokenTransfer(from, msg.sender, tokenId);
           balances[tokenId][msg.sender] = NOFToken;
        }
        else{
            DigitalERC1155 tok= DigitalERC1155(token);
            tok.safeTransferFrom(msg.sender, from, tokenId, NOFToken);
            balances[tokenId][from] = balances[tokenId][from] - NOFToken;
            balances[tokenId][msg.sender] = balances[tokenId][from] + NOFToken;
            if(checkOrder[tokenId][msg.sender] == true){
                if(balances[tokenId][msg.sender] == 0){   
                    delete order_place[msg.sender][tokenId];
                    checkOrder[tokenId][msg.sender] = false;
                }
            }

        }
    }
    function orderPlace(address from, uint256 tokenId, uint256 _price) public{
        _orderPlace(from, tokenId, _price);
    }
    function cancelOrder(address from, uint256 tokenId) public{
        _cancelOrder(from, tokenId);
    }
    function changePrice(uint256 value, uint256 tokenId) public{
        _changePrice(value, tokenId);
    }

}

