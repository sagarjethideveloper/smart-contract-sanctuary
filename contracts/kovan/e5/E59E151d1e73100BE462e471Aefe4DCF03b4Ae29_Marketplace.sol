// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AthenaToken.sol";
import "./PriceConsumerV3.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";
//import "hardhat/console.sol";

contract Marketplace is PriceConsumerV3 {
    using SafeMath for uint256;

    AthenaToken public athenaToken;

    mapping (uint256 => uint256) public tokenPriceUSD;
    mapping (uint256 => bool) public tokenOnAuction;

    // Events
    event SetForSale(
        uint256 _tokenId,
        uint256 _priceUSD,
        bool _auction,
        address indexed _seller,
        uint256 _timestamp
    );
    event PurchaseWithUSD(
        uint256 _tokenId,
        address indexed _buyer,
        string _buyerId,
        bool _isW3user,
        address _w3owner,
        string _w2owner,
        uint256 _timestamp
    );
    event PurchaseWithETH(
        uint256 _tokenId,
        address indexed _buyer,
        bool _isW3user,
        address _w3owner,
        string _w2owner,
        uint256 _fee,
        uint256 _creatorReceives,
        uint256 _sellerReceives,
        uint256 _timestamp
    );
    event BiddingWithETH(
        uint256 _tokenId,
        address indexed _bidder,
        uint256 _fee,
        uint256 _creatorReceives,
        uint256 _sellerReceives,
        uint256 _timestamp
    );
    event ClaimAuctionWinner(
        uint256 _tokenId,
        address _receiver,
        string _receiverId,
        uint256 _timestamp
    );

    modifier isActive {
        require(!athenaToken.isMaintaining());
        _;
    }

    modifier onlyAthena() {
        require(
            msg.sender == athenaToken.owner() ||
            msg.sender == athenaToken.athenaTrust(),
            "caller is not one of athena accounts"
        );
        _;
    }

    constructor(address _tokenAddress) {
        athenaToken = AthenaToken(_tokenAddress);
    }

    /**
        SET FOR SALE FUNCTIONS
        - When w2 or w3user wants to put it up for sale
        - trigger getTokenOwnership() by passing in tokenId and find if it belongs to w2 or w3user
        - if w2 or w3user wants to pay in USD, they pay gas fee to Athena first
        - then Athena triggers setForSaleWithUSD for them
        - if w3user wants to pay in ETH they can trigger setForSaleWithETH,
        - but msg.sender must have the ownership of token
     */

  /**
    * w2, w3user selling a token in USD
    *
    * Preconditions
    * 1. before we make this contract go live,
    * 2. trigger setApprovalForAll() from Athena EOA to approve this contract
    * 3. seller pays gas fee in USD
    * 4. trigger getTokenOwnership() and if tokenId belongs to w3user,
    * 5. call isApprovedForAll() first to check whether w3user has approved the contract on his behalf
    * 6. if not, w3user has to trigger setApprovalForAll() with his ETH to trigger setForSaleWithUSD()
    *
    * @param _tokenId token id to sell
    * @param _priceUSD price in USD to sell
    * @param _auction on auction or not
    */
    function setForSaleWithUSD(uint256 _tokenId, uint256 _priceUSD, bool _auction) public isActive onlyAthena {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceUSD[_tokenId] == 0, "token has already been set for sale");
        require(_priceUSD > 0, "price is zero or lower");
        require(
            athenaToken.isApprovedForAll(athenaToken.athenaTrust(), address(this)),
            "Athena did not approve Marketplace contract"
        );
        tokenPriceUSD[_tokenId] = _priceUSD;
        tokenOnAuction[_tokenId] = _auction;
        emit SetForSale(_tokenId, _priceUSD, _auction, msg.sender, block.timestamp);
    }

  /**
    * w2, w3user removing a token in USD
    *
    * @param _tokenId token id to remove
    */
    function removeSetForSaleUSD(uint256 _tokenId) public isActive onlyAthena {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceUSD[_tokenId] > 0, "token has not set for sale");
        require(
            athenaToken.isApprovedForAll(athenaToken.athenaTrust(), address(this)),
            "Athena did not approve Marketplace contract"
        );
        tokenPriceUSD[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;
        emit SetForSale(_tokenId, 0, false, msg.sender, block.timestamp);
    }

    /**
    * w3user selling a token in ETH
    *
    * Preconditions
    * 1. call isApprovedForAll() to check w3user has approved the contract on his behalf
    * 2. if not, trigger setApprovalForAll() from w3user
    *
    * @param _tokenId token id to sell
    * @param _priceUSD price in USD to sell
    * @param _auction on auction or not
    */
    function setForSaleWithETH(uint256 _tokenId, uint256 _priceUSD, bool _auction) public isActive {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceUSD[_tokenId] == 0, "token has already been set for sale");
        require(_priceUSD > 0, "price is zero or lower");
        address owner = athenaToken.ownerOf(_tokenId);
        require(owner == msg.sender, "caller is not a token owner");
        require(athenaToken.isApprovedForAll(msg.sender, address(this)),
                "token owner did not approve Marketplace contract"
        );
        tokenPriceUSD[_tokenId] = _priceUSD;
        tokenOnAuction[_tokenId] = _auction;
        emit SetForSale(_tokenId, _priceUSD, _auction, msg.sender, block.timestamp);
    }

  /**
    * w3user removing a token in USD
    *
    * @param _tokenId token id to remove
    */
    function removeSetForSaleETH(uint256 _tokenId) public isActive {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceUSD[_tokenId] > 0, "token has not set for sale");
        address owner = athenaToken.ownerOf(_tokenId);
        require(owner == msg.sender, "caller is not a token owner");
        require(athenaToken.isApprovedForAll(msg.sender, address(this)),
                "token owner did not approve Marketplace contract"
        );
        tokenPriceUSD[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;
        emit SetForSale(_tokenId, 0, false, msg.sender, block.timestamp);
    }

  /**
    * w2user purchasing in USD
    * function triggered by Athena
    *
    * Preconditions
    * For NON-AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceUSD() to get the price of token
    * 4. buyer pays 2.5% fee
    * 5. buyer pays gas fee
    * 6. check buyer paid in correct amount of USD (NFT price + 2.5% fee + gas fee)
    *
    * After purchase
    * 1. increase the seller's internal USD wallet balance
    *    - seller receives = (tokenPriceUSD - seller 2.5% fee - royalty)
    *    - for royalty, use royaltyReceivers(tokenId)
    * 2. increase the royalty receiver's internal USD wallet balance
    *    - for royalty, use royaltyReceivers(tokenId)
    *
    * @param _tokenId token id to buy
    * @param _buyerId buyer's w2user internal id
    */
    function purchaseWithUSDw2user(uint256 _tokenId, string memory _buyerId)
        public
        isActive
        onlyAthena
    {
        require(tokenPriceUSD[_tokenId] > 0, "seller is not selling this token");
        require(bytes(_buyerId).length > 0, "buyerId Id is empty");

        address owner = athenaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = athenaToken.getTokenOwnership(_tokenId);

        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            athenaToken.safeTransferFrom(w3owner, athenaToken.athenaTrust(), _tokenId);
            athenaToken.changeTokenOwnership(_tokenId, address(0), _buyerId);
            tokenPriceUSD[_tokenId] = 0;
            tokenOnAuction[_tokenId] = false;
        } else {
            require(owner == athenaToken.athenaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            athenaToken.changeTokenOwnership(_tokenId, address(0), _buyerId);
            tokenPriceUSD[_tokenId] = 0;
            tokenOnAuction[_tokenId] = false;
        }

        emit PurchaseWithUSD(
            _tokenId,
            address(0),
            _buyerId,
            isW3user,
            w3owner,
            w2owner,
            block.timestamp
        );
    }

  /**
    * w3user purchasing in USD
    * function triggered by Athena
    *
    * Preconditions
    * For NON-AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceUSD() to get the price of token
    * 4. buyer pays 2.5% fee
    * 5. buyer pays gas fee
    * 6. check buyer paid in correct amount of USD (NFT price + 2.5% fee + gas fee)
    *
    * After purchase
    * 1. increase the seller's internal USD wallet balance
    *    - seller receives = (tokenPriceUSD - seller 2.5% fee - royalty)
    *    - for royalty, use royaltyReceivers(tokenId)
    * 2. increase the royalty receiver's internal USD wallet balance
    *    - for royalty, use royaltyReceivers(tokenId)
    *
    * @param _tokenId token id to buy
    * @param _buyer buyer's w3user id
    */
    function purchaseWithUSDw3user(uint256 _tokenId, address _buyer)
        public
        isActive
        onlyAthena
    {
        require(tokenPriceUSD[_tokenId] > 0, "seller is not selling this token");
        require(_buyer != address(0), "buyer address is empty");

        address owner = athenaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = athenaToken.getTokenOwnership(_tokenId);

        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            athenaToken.safeTransferFrom(w3owner, _buyer, _tokenId);
            athenaToken.changeTokenOwnership(_tokenId, _buyer, "");
            tokenPriceUSD[_tokenId] = 0;
            tokenOnAuction[_tokenId] = false;
        } else {
            require(owner == athenaToken.athenaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            athenaToken.safeTransferFrom(athenaToken.athenaTrust(), _buyer, _tokenId);
            athenaToken.changeTokenOwnership(_tokenId, _buyer, "");
            tokenPriceUSD[_tokenId] = 0;
            tokenOnAuction[_tokenId] = false;
        }

        emit PurchaseWithUSD(
            _tokenId,
            _buyer,
            "",
            isW3user,
            w3owner,
            w2owner,
            block.timestamp
        );
    }

    /**
    * w3user purchasing in ETH
    * function triggered by w3user
    *
    * Preconditions
    * For NON-AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceUSD() to get the price of token
    * 4. do conversion and calculate how much buyer needs to pay in ETH
    * 5. add up buyer fee 2.5% in msg.value
    *
    * After purchase
    * 1. check if seller is a w2user from getTokenOwnership(tokenId)
    * 2. if w2user, increase the seller's internal ETH wallet balance
    *    - use sellerReceiveAmount from the event
    * 3. increase the royalty receiver's internal ETH wallet balance
    *    - use royaltyReceivers(tokenId) to get the in-app address
    *    - use royaltyAmount from the event
    *
    * @param _tokenId token id to buy
    */
    function purchaseWithETHw3user(uint256 _tokenId) public payable isActive {
        require(tokenPriceUSD[_tokenId] > 0, "seller is not selling this token");
        // only non-auction items can be purchased from w3user
        require(tokenOnAuction[_tokenId] == false, "this token is on auction");

        _validateAmount(_tokenId);

        address owner = athenaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = athenaToken.getTokenOwnership(_tokenId);

        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            athenaToken.safeTransferFrom(w3owner, msg.sender, _tokenId);
        } else {
            require(owner == athenaToken.athenaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            athenaToken.safeTransferFrom(athenaToken.athenaTrust(), msg.sender, _tokenId);
        }

        athenaToken.changeTokenOwnership(_tokenId, msg.sender, "");
        tokenPriceUSD[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;

        uint256 fee = _payBuyerSellerFee();
        uint256 royaltyAmount = _sendRoyalty(_tokenId);
        uint256 sellerReceiveAmount = msg.value.sub(fee.add(royaltyAmount));

        _sendToSeller(sellerReceiveAmount, isW3user, w3owner);

        emit PurchaseWithETH(
            _tokenId,
            msg.sender,
            isW3user,
            w3owner,
            w2owner,
            fee,
            royaltyAmount,
            sellerReceiveAmount,
            block.timestamp
        );
    }

  /**
    * w3user bidding in ETH
    * function triggered by w3user
    *
    * Preconditions
    * For AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceUSD() to get the price of token
    * 4. buyer pays 2.5% fee
    * 5. buyer pays gas fee
    * 6. check buyer paid in correct amount of USD (NFT price + 2.5% fee + gas fee)
    *
    * After bidding
    * 1. auction history records bidAmount, creatorReceives and sellerReceives
    *
    * @param _tokenId token id to buy
    * @param _bidPriceUSD bid amount in USD
    */
    function placeBidWithETHw3user(uint256 _tokenId, uint256 _bidPriceUSD) public payable isActive {
        require(tokenPriceUSD[_tokenId] > 0, "seller is not selling this token");
        // only non-auction items can be purchased from w3user
        require(tokenOnAuction[_tokenId] == true, "this token is not on auction");

        _validateBidAmount(_bidPriceUSD);

        uint256 fee = _payBuyerSellerFee();
        uint256 royaltyAmount = _sendRoyalty(_tokenId);
        uint256 sellerReceiveAmount = msg.value.sub(fee.add(royaltyAmount));

        _send(sellerReceiveAmount, athenaToken.athenaTrust());

        emit BiddingWithETH(
            _tokenId,
            msg.sender,
            fee,
            royaltyAmount,
            sellerReceiveAmount,
            block.timestamp
        );
    }

  /**
    * send token to auction winner
    * function triggered by Athena
    *
    * Preconditions
    * For AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    *
    * After purchase
    * 1. increase the seller's internal wallet balance either in USD or ETH
    * 2. increase the royalty receiver's internal wallet balance either in USD or ETH
    *
    * @param _tokenId token id to buy
    * @param _receiver receiver address
    * @param _receiverId receiver's w2user internal id
    */
    function claimAuctionWinner(
        uint256 _tokenId,
        address _receiver,
        string memory _receiverId
    )
        public
        isActive
        onlyAthena
    {
        require(tokenPriceUSD[_tokenId] > 0, "seller is not selling this token");
        // only non-auction items can be purchased from w3user
        require(tokenOnAuction[_tokenId] == true, "this token is not on auction");
        require(
            _receiver != address(0) ||
            bytes(_receiverId).length > 0,
            "either one of receivers should be passed in"
        );
        require(
            !(_receiver != address(0) &&
            bytes(_receiverId).length > 0),
            "cannot pass in both receiver info"
        );

        address owner = athenaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = athenaToken.getTokenOwnership(_tokenId);
        bool w3user = _receiver != address(0) ? true : false; // check token buyer is w3user
        // token seller is a w3user
        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            athenaToken.safeTransferFrom(w3owner, w3user ? _receiver : athenaToken.athenaTrust(), _tokenId);
        // w2user
        } else {
            require(owner == athenaToken.athenaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            if (w3user) {
                athenaToken.safeTransferFrom(athenaToken.athenaTrust(), _receiver, _tokenId);
            }
        }

        athenaToken.changeTokenOwnership(_tokenId, w3user ? _receiver : address(0), w3user ? "" : _receiverId);
        tokenPriceUSD[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;

        emit ClaimAuctionWinner(
            _tokenId,
            _receiver,
            _receiverId,
            block.timestamp
        );
    }

  /**
    * Validate user purchasing in ETH matches with USD conversion using chainlink
    * checks buyer fee of the token price as well (i.e. 2.5%)
    *
    * @param _tokenId token id
    */
    function _validateAmount(uint256 _tokenId) private {
        uint256 tokenPrice = tokenPriceUSD[_tokenId];
        int256 currentPriceOfETHtoUSD = getCurrentPriceOfETHtoUSD();
        uint256 buyerFee = tokenPrice.mul(athenaToken.feePercent()).div(1000);
        uint256 buyerTotal = tokenPrice.add(buyerFee) * 10**18;
        uint256 buyerTotalToWei = buyerTotal.div(uint256(currentPriceOfETHtoUSD));
        require(msg.value >= buyerTotalToWei, "not enough of ETH being sent");
    }

  /**
    * Validate user bidding in ETH matches with USD conversion using chainlink
    * checks buyer fee of the token price as well (i.e. 2.5%)
    *
    * @param _bidPriceUSD bidding price in usd
    */
    function _validateBidAmount(uint256 _bidPriceUSD) private {
        int256 currentPriceOfETHtoUSD = getCurrentPriceOfETHtoUSD();
        uint256 buyerFee = _bidPriceUSD.mul(athenaToken.feePercent()).div(1000);
        uint256 buyerTotal = _bidPriceUSD.add(buyerFee) * 10**18;
        uint256 buyerTotalToWei = buyerTotal.div(uint256(currentPriceOfETHtoUSD));
        require(msg.value >= buyerTotalToWei, "not enough of ETH being sent");
    }

    /**
    * Pay flat fees to Athena
    * i.e. buyer fee + seller fee = 5%
    */
    function _payBuyerSellerFee() private returns (uint256) {
        uint256 feePercent = athenaToken.feePercent();
        uint256 fee = msg.value.mul(feePercent.mul(2)).div(feePercent.add(1000));
        _send(fee, athenaToken.athenaTrust());
        return fee;
    }

  /**
    * Pay royalty to creator
    * Athena receives on creator's behalf
    *
    * @param _tokenId token id
    */
    function _sendRoyalty(uint256 _tokenId) private returns (uint256) {
        uint256 feePercent = athenaToken.feePercent();
        (, uint16 percentage) = athenaToken.getRoyaltyReceiver(_tokenId);
        uint256 firstFee = msg.value.mul(feePercent).div(feePercent + 1000);
        uint256 royalty = msg.value.sub(firstFee).mul(percentage).div(1000);
        _send(royalty, athenaToken.athenaTrust());
        return royalty;
    }

  /**
    * Send money to seller
    * Athena keeps it if seller is w2user
    *
    * @param sellerReceiveAmount total - (fee + royalty)
    * @param _isW3user w3user or w3user
    * @param _w3owner w3user EOA
    */
    function _sendToSeller(
        uint256 sellerReceiveAmount,
        bool _isW3user,
        address _w3owner
    )
        private
    {
        _send(sellerReceiveAmount, _isW3user ? _w3owner : athenaToken.athenaTrust());
    }

  /**
    * Low-level call methods instead of using transfer()
    *
    * @param _amount amount in ETH
    * @param _to receiver
    */
    function _send(uint256 _amount, address _to) private {
        (bool success, ) = _to.call{value:_amount}("");
        require(success, "Transfer failed.");
    }

  /**
    * Get current price of ETH to USD
    *
    */
    function getCurrentPriceOfETHtoUSD() public view returns (int256) {
        return getThePrice() / 10 ** 8;
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "openzeppelin-solidity/contracts/utils/Counters.sol";
import "./AccessControl.sol";
//import "hardhat/console.sol";

contract AthenaToken is ERC721URIStorage, AccessControl {
  using Counters for Counters.Counter;

  struct RoyaltyReceiver {
    string receiverId;
    uint8 percentage;
  }
  struct TokenOwner {
    bool isW3user;
    address w3owner;
    string w2owner;
  }

  Counters.Counter private _tokenIds;
  uint8 public constant ROYALTY_MAX = type(uint8).max;
  uint32 public constant EDITION_MAX = type(uint32).max;
  uint8 public feePercent;

  // Track royalty receiving address and percentage
  mapping (uint256 => RoyaltyReceiver) public royaltyReceivers;
  // Track w2user's token ownership
  mapping(uint256 => TokenOwner) public tokenOwners;
  // Make sure no duplicate is created per product/edition
  mapping (string => mapping(uint32 => uint256)) public productEditions;

  // Events
  event MintWithUSDw2user(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint8 _royaltyPercentage,
    string _minterId,
    string _productId,
    uint32 _edition,
    uint256 _timestamp
  );
  event MintWithUSDw3user(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint8 _royaltyPercentage,
    address indexed _minter,
    string _productId,
    uint32 _edition,
    uint256 _timestamp
  );
  event MintWithETH(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint8 _royaltyPercentage,
    address indexed _minterAddress,
    string _productId,
    uint32 _edition,
    uint256 _timestamp
  );
  event ChangeTokenOwnership(
    uint256 _tokenId,
    string _newOwnerId,
    address indexed _newOwner,
    uint256 _timestamp
  );
  /**
    * Constructor
    *
    * Define the owner of the contract
    * Set Athena token name and symbol
    * Set initial fee percentage which is 2.5%
    *
    * @param _name Athena token name
    * @param _symbol Athena token symbol
    * @param _feePercent fee percentage Athena account will receive
    */
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _feePercent
  )
    ERC721(_name, _symbol)
    {
      feePercent = _feePercent;
    }

  /**
    * Minting paid with USD from w2user
    * Athena keeps the token on w2user's behalf

    * Precondition
    * 1. user pays gas fee to Athena in USD
    *
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _minterId minter's internal id
    * @param _productId product id
    * @param _edition edition number
    * @param _tokenURI token uri stored in IPFS
    */
  function mintWithUSDw2user(
    string memory _royaltyReceiverId,
    uint8 _royaltyPercentage,
    string memory _minterId,
    string memory _productId,
    uint32 _edition,
    string memory _tokenURI
  )
    public
    isActive
    onlyAthena
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded uint8 max"
    );
    require(bytes(_minterId).length > 0, "minter id is empty");
    require(bytes(_productId).length > 0, "product id is empty");
    require(
      _edition >= 0 && _edition <= EDITION_MAX,
      "edition number is empty or exceeded uint32 max"
    );
    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId].receiverId = _royaltyReceiverId;
    royaltyReceivers[newTokenId].percentage = _royaltyPercentage;
    // Track the owner of token
    tokenOwners[newTokenId].isW3user = false;
    tokenOwners[newTokenId].w2owner = _minterId;
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;
    // Athena keeps the token on minter's behalf
    _mint(msg.sender, newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithUSDw2user(newTokenId, _royaltyReceiverId, _royaltyPercentage, _minterId, _productId, _edition, block.timestamp);
  }

/**
    * Minting paid with USD from w3user
    * token is sent to w3user's EOA

    * Precondition
    * 1. user pays gas fee to Athena in USD
    *
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _minter minter's address
    * @param _productId product id
    * @param _edition edition number
    * @param _tokenURI token uri stored in IPFS
    */
  function mintWithUSDw3user(
    string memory _royaltyReceiverId,
    uint8 _royaltyPercentage,
    address _minter,
    string memory _productId,
    uint32 _edition,
    string memory _tokenURI
  )
    public
    isActive
    onlyAthena
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded uint8 max"
    );
    require(_minter != address(0x0), "minter address is empty");
    require(bytes(_productId).length > 0, "product id is empty");
    require(
      _edition >= 0 && _edition <= EDITION_MAX,
      "edition number is empty or exceeded uint32 max"
    );
    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId].receiverId = _royaltyReceiverId;
    royaltyReceivers[newTokenId].percentage = _royaltyPercentage;
    // Track the owner of token
    tokenOwners[newTokenId].isW3user = true;
    tokenOwners[newTokenId].w3owner = _minter;
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;

    _mint(_minter, newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithUSDw3user(newTokenId, _royaltyReceiverId, _royaltyPercentage, _minter, _productId, _edition, block.timestamp);
  }

  function mintWithETH(
    string memory _royaltyReceiverId,
    uint8 _royaltyPercentage,
    string memory _productId,
    uint32 _edition,
    string memory _tokenURI
  )
    public
    isActive
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded uint8 max"
    );
    require(bytes(_productId).length > 0, "product id is empty");
    require(
      _edition >= 0 && _edition <= EDITION_MAX,
      "edition number is empty or exceeded uint32 max"
    );
    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId].receiverId = _royaltyReceiverId;
    royaltyReceivers[newTokenId].percentage = _royaltyPercentage;
    // Track the owner of token
    tokenOwners[newTokenId].isW3user = true;
    tokenOwners[newTokenId].w3owner = msg.sender;
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;

    _mint(msg.sender, newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithETH(newTokenId, _royaltyReceiverId, _royaltyPercentage, msg.sender, _productId, _edition, block.timestamp);
  }

  function setFlatFee(uint8 _feePercent)
    public
    onlyCEO
    returns (bool)
  {
    feePercent = _feePercent;
    return true;
  }

  function changeTokenOwnership(
    uint256 _tokenId,
    address _newOwner,
    string memory _newOwnerId
  )
    public
    isActive
    onlyAthena
  {
    require(
      _newOwner != address(0) ||
      bytes(_newOwnerId).length > 0,
      "either one of new owner should be passed in"
    );
    require(
      !(_newOwner != address(0) &&
      bytes(_newOwnerId).length > 0),
      "cannot pass in both new owner info"
    );

    if (_newOwner != address(0)) {
      tokenOwners[_tokenId].isW3user = true;
      tokenOwners[_tokenId].w2owner = "";
      tokenOwners[_tokenId].w3owner = _newOwner;
    } else {
      tokenOwners[_tokenId].isW3user = false;
      tokenOwners[_tokenId].w2owner = _newOwnerId;
      tokenOwners[_tokenId].w3owner = address(0);
    }

    emit ChangeTokenOwnership(_tokenId, _newOwnerId, _newOwner, block.timestamp);
  }

  function claimToken(uint256[] memory _tokenIDs, address _w3user) public onlyAthena {
    for (uint i = 0; i < _tokenIDs.length; i++) {
      uint256 tokenId = _tokenIDs[i];
      require(!tokenOwners[tokenId].isW3user, "Only web2 users token can be claimed");
      require(ownerOf(tokenId) == athenaTrust, "Athena wallet does not own this token");
      if (_w3user != address(0)) {
        _transfer(athenaTrust, _w3user, tokenId);
        tokenOwners[tokenId].isW3user = true;
        tokenOwners[tokenId].w2owner = "";
        tokenOwners[tokenId].w3owner = _w3user;
      }
    }
  }

  function isProductEditionMinted(string memory _productId, uint32 _edition) public view returns (bool) {
    if (productEditions[_productId][_edition] > 0) {
      return true;
    }
    return false;
  }

  function getTokenOwnership(uint256 _tokenId) public view returns (bool, address, string memory) {
    return (
      tokenOwners[_tokenId].isW3user,
      tokenOwners[_tokenId].w3owner,
      tokenOwners[_tokenId].w2owner
    );
  }

  function getRoyaltyReceiver(uint256 _tokenId) public view returns (string memory, uint8) {
    return (
      royaltyReceivers[_tokenId].receiverId,
      royaltyReceivers[_tokenId].percentage
    );
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract PriceConsumerV3 {

    AggregatorV3Interface internal priceFeed;

    /**
     * Network: Kovan
     * Aggregator: ETH/USD
     * Address: 0x9326BFA02ADD2366b30bacB125260Af641031331
     */
    constructor() {
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    }

    /**
     * Returns the latest price
     */
    function getThePrice() public view returns (int) {
        (, int price, , ,) = priceFeed.latestRoundData();
        return price;
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

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
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
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
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
     * implement alternative mechanisms to perform token transfer, such as signature-based.
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
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
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
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
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
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
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

        _balances[to] += 1;
        _owners[tokenId] = to;

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
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

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
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
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
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
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
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC721.sol";

/**
 * @dev ERC721 token with storage based token URI management.
 */
abstract contract ERC721URIStorage is ERC721 {
    using Strings for uint256;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
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
    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
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

contract AccessControl {
    address public owner;
    address public athenaTrust;
    address public marketplace;
    bool public isMaintaining = false;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyCEO {
        require(msg.sender == owner, "caller is not CEO");
        _;
    }

    modifier isActive {
        require(!isMaintaining, "it's currently maintaining");
        _;
    }

    modifier onlyAthena() {
        require(msg.sender == owner || msg.sender == athenaTrust || msg.sender == marketplace, "caller is not one of Athena accounts");
        _;
    }

    function changeOwner(address _newOwner) onlyCEO public {
        if (_newOwner != address(0)) {
            owner = _newOwner;
        }
    }

    function changeAthenaTrust(address _newAthenaTrust) onlyCEO public {
        if (_newAthenaTrust != address(0)) {
            athenaTrust = _newAthenaTrust;
        }
    }

    function changeMarketplace(address _newMarketplace) onlyCEO public {
        if (_newMarketplace != address(0)) {
            marketplace = _newMarketplace;
        }
    }

    function updateMaintaining(bool _isMaintaining) onlyCEO public {
        isMaintaining = _isMaintaining;
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

import "../IERC721.sol";

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
        return _verifyCallResult(success, returndata, errorMessage);
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
        return _verifyCallResult(success, returndata, errorMessage);
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
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
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

/*
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

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
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
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
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
pragma solidity >=0.6.0;

interface AggregatorV3Interface {

  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

}

