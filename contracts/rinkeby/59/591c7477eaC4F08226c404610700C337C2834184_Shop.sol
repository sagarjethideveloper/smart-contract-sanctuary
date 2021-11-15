pragma solidity ^0.4.26;
import "./ERC20Interface.sol";
import "./SafeMath.sol";

contract ERC20 is SafeMath, ERC20Interface {
    string public name;
    string public symbol;
    uint8 public decimals; // 18 decimals is the strongly suggested default, avoid changing it
    uint256 public _totalSupply;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    function totalSupply() public view returns (uint256) {
        return _totalSupply - balances[address(0)];
    }

    function balanceOf(address tokenOwner)
        public
        view
        returns (uint256 balance)
    {
        return balances[tokenOwner];
    }

    function allowance(address tokenOwner, address spender)
        public
        view
        returns (uint256 remaining)
    {
        return allowed[tokenOwner][spender];
    }

    function approve(address spender, uint256 tokens)
        public
        returns (bool success)
    {
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    function transfer(address to, uint256 tokens)
        public
        returns (bool success)
    {
        balances[msg.sender] = safeSub(balances[msg.sender], tokens);
        balances[to] = safeAdd(balances[to], tokens);
        emit Transfer(msg.sender, to, tokens);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) public returns (bool success) {
        balances[from] = safeSub(balances[from], tokens);
        allowed[from][msg.sender] = safeSub(allowed[from][msg.sender], tokens);
        balances[to] = safeAdd(balances[to], tokens);
        emit Transfer(from, to, tokens);
        return true;
    }
}

pragma solidity ^0.4.26;

// ----------------------------------------------------------------------------
// ERC Token Standard #20 Interface
//
// ----------------------------------------------------------------------------
contract ERC20Interface {
    function totalSupply() public view returns (uint256);

    function balanceOf(address tokenOwner)
        public
        view
        returns (uint256 balance);

    function allowance(address tokenOwner, address spender)
        public
        view
        returns (uint256 remaining);

    function transfer(address to, uint256 tokens) public returns (bool success);

    function approve(address spender, uint256 tokens)
        public
        returns (bool success);

    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(
        address indexed tokenOwner,
        address indexed spender,
        uint256 tokens
    );
}

pragma solidity ^0.4.26;

// ----------------------------------------------------------------------------
// Safe Math Library
// ----------------------------------------------------------------------------
contract SafeMath {
    function safeAdd(uint256 a, uint256 b) public pure returns (uint256 c) {
        c = a + b;
        require(c >= a);
    }

    function safeSub(uint256 a, uint256 b) public pure returns (uint256 c) {
        require(b <= a);
        c = a - b;
    }

    function safeMul(uint256 a, uint256 b) public pure returns (uint256 c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }

    function safeDiv(uint256 a, uint256 b) public pure returns (uint256 c) {
        require(b > 0);
        c = a / b;
    }
}

pragma solidity ^0.4.26;
pragma experimental ABIEncoderV2;

import "./ERC20.sol";

contract Shop is ERC20 {
    int256 uuid = 0;
    address owner;
    Item[] public Items;
    mapping(address => string[]) public UserInvntory;
    mapping(address => Order[]) public Orders;
    mapping(address => bool) public whitelist;
    mapping(address => int256) public UserBonus;
    mapping(uint256 => RepairItem) public RepairItems;
    mapping(uint256 => Item) public ItemDetails;
    mapping(uint256 => RepairDetail[]) public RepairDetails;

    struct Item {
        address sender;
        string itemName;
        int256 itemPrice;
        int256 itemRepairPrice;
        int256 itemQuantity;
        uint256 id;
        string itemDescription;
        string originalImageHash;
        string thumbnailImageHash;
        uint256 createAt;
    }

    struct RepairItem {
        address vendorAddress;
        address customerAddress;
        address sender;
        string itemName;
        string imageHash;
        uint256 createAt;
    }

    struct RepairDetail {
        string itemProblem;
        string itemDescription;
        int256 itemPrice;
        uint256 createAt;
    }

    struct Order {
        address sellerAddress;
        address buyerAddress;
        string itemName;
        int256 orderPrice;
        uint256 index;
        bool state;
        uint256 createAt;
    }

    struct UserInventory {
        string imagesHash;
    }

    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    constructor() public {
        owner = msg.sender;
        name = "WSShop";
        symbol = "WSS";
        decimals = 18;
        _totalSupply = 100000000000000000000000000;

        balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    modifier onlyOwner() {
        //檢查發送者是不是owner 不是的話就回傳Not Owner
        require(msg.sender == owner, "Not Owner!!!");
        _;
    }

    modifier checkEnoughBonus(address _address, int256 price) {
        require(UserBonus[_address] >= price, "User not have enough bonus");
        _;
    }

    modifier checkWhitelist(address _address) {
        require(
            whitelist[_address] == true,
            "The address does not exist in the whitelist"
        );
        _;
    }

    function addToWhitelist(address _address) public onlyOwner {
        whitelist[_address] = true;
    }

    function createItem(
        string _itemName,
        int256 _itemPrice,
        int256 _itemRepairPrice,
        int256 _itemQuantity,
        string _itemDescription,
        string _originalImageHash,
        string _thumbnailImageHash,
        uint256 _index
    ) public {
        Item memory newItem =
            Item({
                id: _index,
                itemName: _itemName,
                itemPrice: _itemPrice,
                itemRepairPrice: _itemRepairPrice,
                itemQuantity: _itemQuantity,
                itemDescription: _itemDescription,
                sender: msg.sender,
                originalImageHash: _originalImageHash,
                thumbnailImageHash: _thumbnailImageHash,
                createAt: now
            });
        Items.push(newItem);
        ItemDetails[_index] = Item({
            id: _index,
            itemName: _itemName,
            itemPrice: _itemPrice,
            itemRepairPrice: _itemRepairPrice,
            itemQuantity: _itemQuantity,
            itemDescription: _itemDescription,
            sender: msg.sender,
            originalImageHash: _originalImageHash,
            thumbnailImageHash: _thumbnailImageHash,
            createAt: now
        });
    }

    function buy(
        address _address,
        int256 _bonus,
        string _imagesHash
    ) public returns (bool) {
        UserBonus[_address] += _bonus;
        UserInvntory[_address].push(_imagesHash);
        return true;
    }

    function repair(
        address _vendorAddress,
        address _customerAddress,
        string _itemName,
        string _itemDescription,
        string _itemProblem,
        string _imageHash,
        int256 _itemRepairPrice,
        uint256 _index
    ) public checkWhitelist(_vendorAddress) {
        RepairItems[_index] = RepairItem({
            vendorAddress: _vendorAddress,
            customerAddress: _customerAddress,
            sender: msg.sender,
            itemName: _itemName,
            imageHash: _imageHash,
            createAt: now
        });
        RepairDetails[_index].push(
            RepairDetail(_itemProblem, _itemDescription, _itemRepairPrice, now)
        );
    }

    function order(
        address _sellerAddress,
        address _buyerAddress,
        string _itemName,
        int256 _itemPrice,
        uint256 _index
    ) public {
        Orders[_sellerAddress].push(
            Order(
                _sellerAddress,
                _buyerAddress,
                _itemName,
                _itemPrice,
                _index,
                false,
                now
            )
        );
        Orders[_buyerAddress].push(
            Order(
                _sellerAddress,
                _buyerAddress,
                _itemName,
                _itemPrice,
                _index,
                false,
                now
            )
        );
    }

    function checkOrderState(
        address _sellerAddress,
        address _buyerAddress,
        uint256 _index
    ) public {
        Orders[_sellerAddress][_index].state = true;
        Orders[_buyerAddress][_index].state = true;
    }

    function exchangeGift(address _address, int256 price)
        public
        checkEnoughBonus(_address, price)
        returns (bool)
    {
        UserBonus[_address] -= price;
        return true;
    }

    function getAllItemsData() public view returns (Item[] memory) {
        return Items;
    }

    function getOrder(address _address) public view returns (Order[] memory) {
        return Orders[_address];
    }

    function getRepairDetail(uint256 _index)
        public
        view
        returns (RepairDetail[] memory)
    {
        return RepairDetails[_index];
    }

    function getUserInventory(address _address) public view returns (string[]) {
        return UserInvntory[_address];
    }
}

