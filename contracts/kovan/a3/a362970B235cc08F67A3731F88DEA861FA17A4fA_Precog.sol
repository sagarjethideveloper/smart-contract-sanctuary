pragma solidity ^0.8.0;
import "./IERC20Metadata.sol";

interface IERC20 is IERC20Metadata {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

pragma solidity ^0.8.0;

interface IERC20Metadata {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

pragma solidity ^0.8.0;

interface IOwnable {
    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;
}

pragma solidity ^0.8.0;

interface IFutureExchangeRouter {
    
    function futureTokenFactory() external view returns (address);
    
    function getListFutureContractsInPair(address token) external view returns(address[] memory);
    
    function getAmountsOutFuture(uint256 amountIn, address tokenIn, address tokenOut, uint256 expiryDate) external view returns (uint256);
    
    function getAmountsInFuture(uint256 amountOut, address tokenIn, address tokenOut, uint256 expiryDate) external view returns (uint256);
    
    function addLiquidityFuture(address tokenA, address tokenB, uint256 amountA, uint256 amountB, uint256 expiryDate, string memory symbol) external;
    
    function withdrawLiquidityFuture(address tokenA, address tokenB, uint256 expiryDate, address to, uint256 amount) external;
    
    function swapFuture(address tokenA, address tokenB, uint expiryDate, address to, uint amount) external;
    
    function closeFuture(address tokenA, address tokenB, uint expiryDate, address to, uint amount) external;
}

pragma solidity ^0.8.0;

interface IFutureContract {
    
    function token0() external view returns (address);
    
    function token1() external view returns (address);
    
    function expiryDate() external view returns (uint256);
}

pragma solidity ^0.8.0;

interface IFutureToken {
    
    function initialize(string memory symbol) external;
    
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}

pragma solidity ^0.8.0;

interface IFutureTokenFactory {
    
    function exchange() external view returns (address);
    
    event futureTokenCreated(
        address indexed token0,
        address indexed token1,
        address futureTokenAddress,
        uint256 i
    );
    
    function getFutureContract(address tokenA, address tokenB, uint expiryDate) external view returns (address);

    function getFutureToken(address tokenIn, address tokenOut, uint expiryDate) external view returns (address);

    function createFuture(address tokenA, address tokenB, uint expiryDate, string memory symbol) external returns (address);

    function mintFuture(address tokenIn, address tokenOut, uint expiryDate, address to, uint amount) external;

    function burnFuture(address tokenIn, address tokenOut, uint expiryDate, uint amount) external;
}

pragma solidity ^0.8.0;

library DataTypes {
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //stores the reserve configuration
    ReserveConfigurationMap configuration;
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    //the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    //tokens addresses
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    address interestRateStrategyAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }

  struct UserConfigurationMap {
    uint256 data;
  }
  
  struct BorrowInfo{
    uint256 platformIndex;
    uint256 borrowedAmount;
    uint256 interestRate;
  }

  enum InterestRateMode {NONE, STABLE, VARIABLE}
}

pragma solidity ^0.8.0;

interface ILending {
    function sendCollateral(uint platformIndex, address borrowToken, uint256 amount) external;
    function withdrawCollateral(uint platformIndex, address borrowToken, uint256 amount) external;
    function getLendingPlatformCollateral(uint platformIndex, address borrowToken) external returns (uint, uint);
    function getLendingPlatformBorrow(uint platformIndex, address borrowToken) external view returns (uint);
    function getLendingPlatforms(uint platformIndex) external view returns (address);
    function lendingPlatformsCount() external view returns (uint);
    
    function getBorrowableAmount(uint platformIndex, address borrowToken) external view returns (uint);
    function getDebtAmount(
        uint256 platformIndex, 
        address borrowToken,
        uint256 borrowAmount,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external view returns(uint);
    
    function createLoan(uint platformIndex, address borrowToken, uint borrowAmount) external;
    function repayLoan(uint platformIndex, address borrowToken, uint repayAmount) external;
}

pragma solidity ^0.8.0;
import "./interfaces/IExchangeRouter.sol";
import "./interfaces/IPrecog.sol";
import "../future-exchange/interfaces/IFutureExchangeRouter.sol";
import "../future-token/interfaces/IFutureToken.sol";
import "../future-token/interfaces/IFutureTokenFactory.sol";
import "../future-token/interfaces/IFutureContract.sol";
import "../lending-platform/interfaces/ILending.sol";
import "../common/interfaces/IERC20.sol";
import "../common/interfaces/IOwnable.sol";
import "../future-token/interfaces/IFutureContract.sol";
import "../lending-platform/interfaces/ILending.sol";
import "../lending-platform/interfaces/DataTypes.sol";

contract Precog is IPrecog {

    struct BorrowInfo {
        uint platformIndex;
        uint borrowAmount;
    }
    
    struct TradeInfo {
        address exchange;
        address futureExchange;
        address futureContract;
    }
    
    struct Fee {
        uint feeTrading;
        uint feeLending;
    }

    address public usdc;
    address public weth;
    address public tradingService;
    address public adminAddress;
    address public lendingContract;
    
    uint256 public feeWithdrawByUSDC = 2e6; // 2 USDC
    uint256 public feeTradingByEth = 5e15; // 0.005 ETH
    uint256 public feeLendingByEth = 5e15; // 0.005 ETH
    uint256 public borrowRateLimit = 70; // 70%
    
    address[] futureExchanges;
    address[] exchanges;
    mapping(address => uint256) futureExchangeIndex;
    mapping(address => uint256) exchangeIndex;
    
    mapping(address => uint256) availableAmount;
    mapping(address => uint256) investAmount;
    mapping(address => uint256) tradingAmount;
    mapping(address => uint256) profitAmount;
    mapping(address => mapping(address => uint256)) tradingAmountOnFutureContract;
    mapping(address => mapping(address => uint256)) profitAmountOnFutureContract;
    mapping(address => mapping(address => uint256)) liquidatedAmount;
    
    address[] tradeUsers;
    mapping(address => uint256) tradeUserIndex;
    mapping(address => mapping(address => BorrowInfo[])) userBorrowInfo;
    
    event Deposit(address indexed user, uint256 amount, uint256 indexed timestamp);
    event Withdraw(address indexed user, uint256 amount, uint256 fee, uint256 indexed timestamp);
    event Trade(
        address indexed user, 
        address indexed futureContract, 
        uint256 deadline, 
        uint256 amount, 
        uint256 profit, 
        uint256 fee, 
        uint256 indexed timestamp,
        uint256 platformIndex
    );
    
    event Liquidate(address indexed user, address indexed futureToken, uint256 indexed timestamp);
    
    modifier onlyAdminAddress() {
        require(msg.sender == adminAddress, "PrecogV2: NOT_ADMIN_ADDRESS");
        _;
    }

    constructor(address _usdc, address _weth, address _tradingService, address _adminAddress) {
        usdc = _usdc;
        weth = _weth;
        tradingService = _tradingService;
        adminAddress = _adminAddress;
    }
    
    function setFeeWithdrawByUSDC(uint256 fee) external onlyAdminAddress {
        feeWithdrawByUSDC = fee;
    }

    function setFeeTradingByETH(uint256 fee) external onlyAdminAddress {
        feeTradingByEth = fee;
    }
    
    function setFeeLendingByEth(uint256 fee) external onlyAdminAddress {
        feeLendingByEth = fee;
    }
       
    function setBorrowRateLimit(uint256 borrowRate) external onlyAdminAddress {
        borrowRateLimit = borrowRate;
    }
    
    
    function setLending(address lending) external onlyAdminAddress {
        lendingContract = lending;
        IERC20(usdc).approve(address(lending), type(uint256).max);
    }
    
    function tradeAvailableUsers() external view returns(address[] memory) {
        return tradeUsers;
    }
    
    function getFutureExchanges(uint256 index) external view override returns (address) {
        return futureExchanges[index];
    }
    
    function getExchanges(uint256 index) external view override returns (address) {
        return exchanges[index];
    }
    
    function getLendingFeeByEth() external view returns (uint256) {
        return feeLendingByEth;
    }
    
    function getBorrowingRateLimit() external view returns(uint256) {
        return borrowRateLimit;
    }
    
    function getLending() external view returns(address) {
        return lendingContract;
    }
    
    function getLiquidatedAmount(address user, address futureContract) external view override returns (uint256){
        return liquidatedAmount[user][futureContract];
    }
    
    function getAvailableAmount(address user) external view override returns (uint256){
        return availableAmount[user];
    }
    
    function getInvestAmount(address user) external view override returns (uint256){
        return investAmount[user];
    }

    function getTradingAmount(address user) external view override returns (uint256){
        return tradingAmount[user];
    }
    
    function getProfitAmount(address user) external view override returns (uint256){
        return profitAmount[user];
    }
    
    function getTradingAmountOnFutureContract(address user, address futureContract) external view override returns (uint256){
        return tradingAmountOnFutureContract[user][futureContract];
    }
    
    function getProfitAmountOnFutureContract(address user, address futureContract) external view override returns (uint256){
        return profitAmountOnFutureContract[user][futureContract];
    }

    function getTradeUserIndex(address user) external view override returns (uint256){
        return tradeUserIndex[user];
    }
    
    function getUserBorrowInfo(address user, address futureContract) external view returns(BorrowInfo[] memory){
        return userBorrowInfo[user][futureContract];
    }

    function addFutureExchange(address exchange) external {
        require(!isFutureExchange(exchange), "PrecogV2: FUTURE_EXCHANGE_ADDED");
        futureExchanges.push(exchange);
        futureExchangeIndex[exchange] = futureExchanges.length;
    }

    function addExchange(address exchange) external {
        require(!isExchange(exchange), "PrecogV2: EXCHANGE_ADDED");
        exchanges.push(exchange);
        exchangeIndex[exchange] = exchanges.length;
        IERC20(usdc).approve(address(exchange), type(uint256).max);
    }

    function removeFutureExchange(address exchange) external {
        require(isFutureExchange(exchange), "PrecogV2: FUTURE_EXCHANGE_NOT_ADDED");
        if (futureExchanges.length > 1) {
            uint256 index = futureExchangeIndex[exchange] - 1;
            futureExchanges[index] = futureExchanges[futureExchanges.length - 1];
        }
        futureExchanges.pop();
        futureExchangeIndex[exchange] = 0;
        IERC20(usdc).approve(address(exchange), 0);
    }

    function removeExchange(address exchange) external {
        require(isExchange(exchange), "PrecogV2: EXCHANGE_NOT_ADDED");
        if (exchanges.length > 1) {
            uint256 index = exchangeIndex[exchange] - 1;
            exchanges[index] = exchanges[exchanges.length - 1];
        }
        exchanges.pop();
        exchangeIndex[exchange] = 0;
        IERC20(usdc).approve(address(exchange), 0);
    }
    
    function isFutureExchange(address exchange) public view returns (bool) {
        return futureExchangeIndex[exchange] > 0;
    }
    
    function isExchange(address exchange) public view returns (bool) {
        return exchangeIndex[exchange] > 0;
    }

    function futureExchangesCount() external view returns (uint256) {
        return futureExchanges.length;
    }

    function exchangesCount() external view returns (uint256) {
        return exchanges.length;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "PrecogV2: AMOUNT_LOWER_EQUAL_FEE");
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
        _deposit(amount);
        _addTradingUser();
    }
    
    function _deposit(uint256 amount) internal {
        availableAmount[msg.sender] += amount;
        emit Deposit(msg.sender, amount, block.timestamp);
    }
    
    function _addTradingUser() internal {
        if (tradeUserIndex[msg.sender] == 0) {
            tradeUsers.push(msg.sender);
            tradeUserIndex[msg.sender] = tradeUsers.length;
        }
    }
    
    function withdraw(uint256 amount, address to) external {
        require(availableAmount[msg.sender] >= amount + feeWithdrawByUSDC , "PrecogV2: AVAILABLE_AMOUNT_NOT_ENOUGH");
        IERC20(usdc).transfer(to, amount);
        _wthdraw(amount);
        IERC20(usdc).transfer(adminAddress, feeWithdrawByUSDC);
        _removeTradingUser(msg.sender);
    }
    
    function _wthdraw(uint256 amount) internal {
        availableAmount[msg.sender] -= amount + feeWithdrawByUSDC;
        emit Withdraw(msg.sender, amount, feeWithdrawByUSDC, block.timestamp);
    }
    
    function _removeTradingUser(address user) internal {
        if (availableAmount[user] == 0) {
            if (tradeUsers.length > 0) {
                uint256 index = tradeUserIndex[user] - 1;
                uint256 lastUserIndex = tradeUsers.length - 1;
                address lastUser = tradeUsers[lastUserIndex];
                tradeUserIndex[lastUser] = tradeUserIndex[user];
                tradeUsers[index] = lastUser;
            }
            tradeUserIndex[user] = 0;
            tradeUsers.pop();
        }
    }

    function withdrawLiquidate(address futureContract, address to, address user) external {
        uint amount = liquidatedAmount[user][futureContract] == 0
            ? this.liquidate(futureContract, user) - feeWithdrawByUSDC
            : liquidatedAmount[user][futureContract] - feeWithdrawByUSDC;
        IERC20(usdc).transfer(to, amount);
        IERC20(usdc).transfer(adminAddress, feeWithdrawByUSDC);
        emit Withdraw(user, amount, feeWithdrawByUSDC, block.timestamp);
    }
    
    function reinvest(address futureContract, address user) external {
        uint amount = liquidatedAmount[user][futureContract] == 0
            ? this.liquidate(futureContract, user)
            : liquidatedAmount[user][futureContract];
        availableAmount[msg.sender] += amount;
        _addTradingUser();
    }
    
    function liquidate(address futureContract, address user) external returns(uint256 amount) {
        require(tradingAmount[user] > 0, "PrecogV2: TRADING_AMOUNT_NOT_ENOUGH");
        require(liquidatedAmount[user][futureContract] == 0, "PrecogV2: ALREADY_LIQUIDATED");
        address tokenA = IFutureContract(futureContract).token0();
        address tokenB = IFutureContract(futureContract).token1();
        require(tokenA == usdc || tokenB == usdc, "PrecogV2: INVALID_TOKEN");
        
        address tokenInvest = tokenA == usdc ? tokenB : tokenA; 
        uint256 expiryDate = IFutureContract(futureContract).expiryDate();
        address futureFactory = IOwnable(futureContract).owner();
        address futureExchange = IFutureTokenFactory(futureFactory).exchange();
        address futureToken = IFutureTokenFactory(futureFactory).getFutureToken(tokenInvest, usdc, expiryDate);
        amount = tradingAmountOnFutureContract[user][futureContract] + profitAmountOnFutureContract[user][futureContract];
        
        BorrowInfo[] memory loans = _getUserLoans(user, futureContract);
        if (loans.length > 0) {
            for (uint i = 0; i < loans.length; i++) {
                amount += loans[i].borrowAmount;
            }
        }
        
        if (IERC20(futureToken).allowance(address(this), futureExchange) == 0) {
            IERC20(futureToken).approve(futureExchange, type(uint256).max);
        }
        
        IFutureExchangeRouter(futureExchange).closeFuture(tokenInvest, usdc, expiryDate, address(this), amount);
        _repayLoan(loans);
        _updateLiquidateAmount(user, futureContract);
        
        emit Liquidate(user, futureContract, block.timestamp);
    }
    
    function _swapFee(uint feeEth) internal returns(uint usedUsdc) {
        address[] memory pair = new address[](2);
        pair[0] = usdc;
        pair[1] = weth;

        uint256 deadline = block.timestamp + 3600;

        (address exchange, uint256 feeTradingUsdc) = _selectBestPriceExchange(pair, feeEth);
        if (address(exchange) != address(0)) {
            uint[] memory amounts = IExchangeRouter(exchange).swapTokensForExactETH(feeTradingByEth, feeTradingUsdc, pair, tradingService, deadline);
            return (amounts[0]);
        }
    }

    function _selectBestPriceExchange(address[] memory pair, uint256 amount)
        internal view returns (address selected, uint256 inAmount)
    {
        inAmount = type(uint256).max;
        for (uint256 i = 0; i < exchanges.length; i++) {
            IExchangeRouter exchange = IExchangeRouter(exchanges[i]);
            try exchange.getAmountsIn(amount, pair) returns (uint256[] memory inAmounts) {
                if (inAmount > inAmounts[0]) {
                    inAmount = inAmounts[0];
                    selected = exchanges[i];
                }
            } catch {}
        }
    }
    
    function _getUserLoans(address user, address futureContract) internal view returns(BorrowInfo[] memory userLoans) {
        uint count = ILending(lendingContract).lendingPlatformsCount();
        userLoans = new BorrowInfo[](count);
        
        BorrowInfo[] memory loans = userBorrowInfo[user][futureContract];
        if (loans.length > 0) {
            for (uint i = 0; i < loans.length; i++) {
                uint index = loans[i].platformIndex - 1;
                if (userLoans[index].platformIndex == 0) {
                    userLoans[index] = loans[i];
                } else {
                    userLoans[index].borrowAmount += loans[i].borrowAmount;
                }
            }
        }
    }
    
    function _repayLoan(BorrowInfo[] memory loans) internal {
        if (loans.length > 0) {
            for (uint i = 0; i < loans.length; i++) {
                if (loans[i].platformIndex > 0) {
                    ILending(lendingContract).repayLoan(loans[i].platformIndex, usdc, loans[i].borrowAmount);
                }
            }
        }
    }
    
    function _updateLiquidateAmount(address user, address futureContract) internal {
        tradingAmount[user] -= tradingAmountOnFutureContract[user][futureContract];
        profitAmount[user] -= profitAmountOnFutureContract[user][futureContract];
        
        liquidatedAmount[user][futureContract] = 
            tradingAmountOnFutureContract[user][futureContract] + 
            profitAmountOnFutureContract[user][futureContract];
            
        tradingAmountOnFutureContract[user][futureContract] = 0;
        profitAmountOnFutureContract[user][futureContract] = 0;
    }

    function maxProfitable(address user) external view returns (
        uint256 amount, 
        uint256 profit, 
        TradeInfo memory tradeInfo,
        BorrowInfo memory borrowInfo
    ) {
        Fee memory fee = Fee(_convertEthToUsdc(feeTradingByEth), _convertEthToUsdc(feeLendingByEth));
        if (availableAmount[user] > fee.feeTrading) {
            amount = availableAmount[user];
            BorrowInfo[] memory loans = _getAvailableLoans(amount, fee.feeLending);
            if (loans.length == 0) {
                loans = new BorrowInfo[](1);
                loans[0] = BorrowInfo(0, 0);
            }
            for (uint k = 0; k < futureExchanges.length; k++) {
                address[] memory futureContracts = IFutureExchangeRouter(futureExchanges[k]).getListFutureContractsInPair(usdc);
                for (uint j = 0; j < futureContracts.length; j++) {
                    for (uint i = 0; i < exchanges.length; i++) {
                        TradeInfo memory _tradeInfo = TradeInfo(exchanges[i], futureExchanges[k], futureContracts[j]);
                        for (uint l = 0; l < loans.length; l++) {
                            (uint _profit, bool canBorrow,) = _calculateProfit(user, amount, fee, _tradeInfo, loans[l]);
                            if (_profit > profit) {
                                profit = _profit;
                                tradeInfo = _tradeInfo;
                                if (canBorrow && loans[l].borrowAmount > 0) {
                                    borrowInfo = loans[l];
                                }
                            }
                        }
                    }       
                }
            }
        }
    }
    
    function _convertEthToUsdc(uint amount) internal view returns(uint) {
        address[] memory pair = new address[](2);
        pair[0] = usdc;
        pair[1] = weth;
        (, uint256 feeTradingUsdc) = _selectBestPriceExchange(pair, amount);
        return feeTradingUsdc;
    }

    function _getAvailableLoans(uint amount, uint fee) internal view returns (BorrowInfo[] memory loans) {
        uint borrowLimit = amount * borrowRateLimit / 100;
        try ILending(lendingContract).lendingPlatformsCount() returns(uint platformCount) {
            loans = new BorrowInfo[](platformCount);
            for (uint i = 0; i < platformCount; ++i) {
                loans[i] = _getAvailableLoan(i + 1, borrowLimit, fee);
            }   
        } catch {}
    }

    function _getAvailableLoan(uint platformIndex, uint borrowLimit, uint fee) internal view returns (BorrowInfo memory loan) {
        uint borrowAmount = ILending(lendingContract).getBorrowableAmount(platformIndex, usdc);
        if (borrowAmount > borrowLimit)
            borrowAmount = borrowLimit;
        loan = BorrowInfo(platformIndex, borrowAmount);
    }

    function _calculateProfit(
        address user,
        uint256 amount,
        Fee memory fee,
        TradeInfo memory tradeInfo,
        BorrowInfo memory loan
    ) internal view returns (uint256 profit, bool canBorrow, uint256 expiryDate) {
        expiryDate = IFutureContract(tradeInfo.futureContract).expiryDate();
        if (expiryDate > block.timestamp) {
            address[] memory pairs = _getPairs(tradeInfo.futureContract);
            if (pairs[0] != address(0)) {
                if (amount > fee.feeTrading) {
                    uint tradeAmount = amount - fee.feeTrading;
                    uint revenue = _getRevenue(tradeAmount, expiryDate, pairs, tradeInfo);
                    if (revenue > amount) {
                        profit = revenue - amount;
                    }
                    if (loan.platformIndex > 0) {
                        tradeAmount += loan.borrowAmount;
                        if (userBorrowInfo[user][tradeInfo.futureContract].length == 0) {
                            if (tradeAmount > fee.feeLending) {
                                tradeAmount -= fee.feeLending;
                            } else {
                                return (profit, false, expiryDate);
                            }
                        }
                        revenue = _getRevenue(tradeAmount, expiryDate, pairs, tradeInfo);
                        uint debtAmount = _getDebtAmount(loan, block.timestamp, expiryDate);
                        if (revenue > amount + debtAmount) {
                            uint profitLoan = revenue - amount - debtAmount;
                            if (profitLoan > profit) {
                                profit = profitLoan;
                                canBorrow = true;
                            }    
                        }
                    }
                }
            }   
        }
    }
    
    function _getPairs(address futureContract) internal view returns (address[] memory pairs) {
        address token0 = IFutureContract(futureContract).token0();
        address token1 = IFutureContract(futureContract).token1();
        pairs = new address[](2);
        if (token0 == usdc || token1 == usdc) {
            (pairs[0], pairs[1]) = token0 == usdc ? (usdc, token1) : (usdc, token0);
        }
    }
    
    function _getRevenue(uint amount, uint expiryDate, address[] memory pairs, TradeInfo memory tradeInfo) 
        internal view returns (uint revenue) 
    {
        IExchangeRouter exchange = IExchangeRouter(tradeInfo.exchange);
        IFutureExchangeRouter futureExchange = IFutureExchangeRouter(tradeInfo.futureExchange);
        try exchange.getAmountsOut(amount, pairs) returns(uint[] memory amountsOut) {
            try futureExchange.getAmountsOutFuture(amountsOut[1], pairs[1], usdc, expiryDate) returns(uint _revenue) {
                revenue = _revenue;
            } catch {}
        } catch {}
    }
    
    function _getDebtAmount(BorrowInfo memory loan, uint startDate, uint endDate) internal view returns(uint) {
        return ILending(lendingContract).getDebtAmount(loan.platformIndex, usdc, loan.borrowAmount, startDate, endDate);
    }

    function invest(
        address user,
        uint256 amount,
        TradeInfo memory tradeInfo,
        uint256 platformIndex,
        uint256 borrowAmount
    ) external {
        require(availableAmount[user] >= amount, "PrecogV2: AVAILABLE_AMOUNT_NOT_ENOUGH");
        Fee memory fee = Fee(_swapFee(feeTradingByEth), _convertEthToUsdc(feeLendingByEth));
        BorrowInfo memory loan = _getBorrowForTrade(amount, borrowAmount, platformIndex, fee.feeLending);
        (uint profit, bool canBorrow, uint expiryDate) = _calculateProfit(user, amount, fee, tradeInfo, loan);
        require(profit > 0, "PrecogV2: NOT_PROFITABLE");
        
        uint tradeAmount = amount - fee.feeTrading;
        if (canBorrow) {
            uint debtAmount = _getDebtAmount(loan, block.timestamp, expiryDate);
            ILending(lendingContract).createLoan(platformIndex, usdc, borrowAmount);
            tradeAmount += loan.borrowAmount;
            loan.borrowAmount = debtAmount;
            if (userBorrowInfo[user][tradeInfo.futureContract].length == 0) {
                tradeAmount -= _swapFee(feeLendingByEth);
            }
            userBorrowInfo[user][tradeInfo.futureContract].push(loan);
        }
        
        _executeTrade(tradeAmount, expiryDate, tradeInfo);
        _updateTradingAmount(user, tradeInfo.futureContract, amount, profit);
        _removeTradingUser(user);
        
        emit Trade(user, 
            tradeInfo.futureContract, expiryDate, 
            amount, profit, fee.feeTrading, 
            block.timestamp, platformIndex
        );
    }

    function _getBorrowForTrade(uint amount, uint borrowAmount, uint platformIndex, uint fee) 
        internal view returns (BorrowInfo memory loan) 
    {
        if (platformIndex != 0) {
            uint256 borrowLimit = amount * borrowRateLimit / 100;
            loan = _getAvailableLoan(platformIndex, borrowLimit, fee);
            require(borrowAmount <= loan.borrowAmount, "PrecogV2: BORROW_AMOUNT_EXCEED_LIMIT");
            loan.borrowAmount = borrowAmount;
        }
    }
    
    function _executeTrade(uint amount, uint expiryDate, TradeInfo memory tradeInfo) internal {
        address[] memory pairs = _getPairs(tradeInfo.futureContract);
        uint256[] memory amounts = IExchangeRouter(tradeInfo.exchange).getAmountsOut(amount, pairs);
        
        uint allowance = IERC20(pairs[1]).allowance(address(this), tradeInfo.futureExchange);
        if (allowance < amounts[1]) {
            IERC20(pairs[1]).approve(tradeInfo.futureExchange, type(uint256).max);
        }
        
        // Swap USDC->Token
        IExchangeRouter(tradeInfo.exchange).swapExactTokensForTokens(amount, amounts[1], pairs, address(this), expiryDate);
        // Swap Token->USDC Future
        IFutureExchangeRouter(tradeInfo.futureExchange).swapFuture(pairs[1], pairs[0], expiryDate, address(this), amounts[1]);
    }

    function _updateTradingAmount(address user, address futureContract, uint amount, uint profit) internal {
        tradingAmount[user] += amount;
        tradingAmountOnFutureContract[user][futureContract] += amount;
        
        profitAmount[user] += profit;
        profitAmountOnFutureContract[user][futureContract] += profit;
        
        investAmount[user] += amount;
        availableAmount[user] -= amount;
    }
}

pragma solidity >=0.6.2;

interface IExchangeRouter {
    function factory() external view returns (address);
    function WETH() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
        
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
        
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
        
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

pragma solidity ^0.8.0;

interface IPrecog {
    function getFutureExchanges(uint256 index) external view returns (address);
    
    function getExchanges(uint256 index) external view returns (address);
    
    function getAvailableAmount(address user) external view returns (uint256);
    
    function getInvestAmount(address user) external view returns (uint256);

    function getTradingAmount(address user) external view returns (uint256);
    
    function getProfitAmount(address user) external view returns (uint256);
    
    function getTradingAmountOnFutureContract(address user, address futureContract) external view returns (uint256);
    
    function getProfitAmountOnFutureContract(address user, address futureContract) external view returns (uint256);
    
    function getLiquidatedAmount(address user, address futureContract) external view returns (uint256);

    function getTradeUserIndex(address user) external view returns (uint256);
}

