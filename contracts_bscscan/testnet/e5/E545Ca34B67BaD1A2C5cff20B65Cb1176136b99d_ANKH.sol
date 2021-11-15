// SPDX-License-Identifier: MIT



pragma solidity ^0.8.6;



//////////////////////////// INTERFACES ////////////////////////////
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";
import "./interfaces/IANKHD.sol";
//////////////////////////// INTERFACES ////////////////////////////



//////////////////////////// UTILITIES ////////////////////////////
import "./Context.sol";
//////////////////////////// UTILITIES ////////////////////////////



//////////////////////////// LIBRARIES ////////////////////////////
import "./utilities/SafeMath.sol";
import "./utilities/SafeERC20.sol";
import "./utilities/Address.sol";
//////////////////////////// LIBRARIES ////////////////////////////



//////////////////////////// KOFFEESWAP ////////////////////////////
import "./interfaces/IKoffeeSwapFactory.sol";
import "./interfaces/IKoffeeSwapPair.sol";
import "./interfaces/IKoffeeSwapRouter.sol";
//////////////////////////// KOFFEESWAP ////////////////////////////




contract ANKH is Context, IERC20, IERC20Metadata {



    //////////////////////////// USING STATEMENTS ////////////////////////////
    using Address for address;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    //////////////////////////// USING STATEMENTS ////////////////////////////



    //////////////////////////// BASIC INFO MAPPINGS ////////////////////////////  
    mapping (address => mapping (address => uint256)) private allowancesOfToken;
    //////////////////////////// BASIC INFO MAPPINGS ////////////////////////////  



    //////////////////////////// BASIC INFO VARS ////////////////////////////  
    string private nameOfToken = "ANKH";
    string private symbolOfToken = "ANKH";
    uint8 private decimalsOfToken = 9;
    uint256 private decimalsMultiplier = 10**9;
    uint256 private  totalSupplyOfToken = 10**15 * decimalsMultiplier;    // 1 Quad
    uint256 public deployDateUnixTimeStamp = block.timestamp;  // sets the deploy timestamp
    //////////////////////////// BASIC INFO VARS ////////////////////////////  



    //////////////////////////// ACCESS CONTROL ////////////////////////////  
    address public directorAccount = 0x8C7Ad6F014B46549875deAD0f69919d643a50bA3;       // CHANGEIT - Make sure you have the right Director Address
    //////////////////////////// ACCESS CONTROL ////////////////////////////  



    //////////////////////////// KOFFEESWAP VARS ////////////////////////////  
    // address public routerAddressForDEX = 0xc0fFee0000C824D24E0F280f1e4D21152625742b;        // CHANGEIT - make sure you have the right router
    address public routerAddressForDEX = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
    IKoffeeSwapRouter public koffeeSwapRouter;
    address public koffeeSwapPair;
    //////////////////////////// KOFFEESWAP VARS ////////////////////////////  
    

    

    //////////////////////////// DEAD ADDR VARS ////////////////////////////
    address private deadAddressZero = 0x0000000000000000000000000000000000000000;
    address private deadAddressOne = 0x0000000000000000000000000000000000000001;
    address private deadAddressdEaD = 0x000000000000000000000000000000000000dEaD;
    //////////////////////////// DEAD ADDR VARS ////////////////////////////





    //////////////////////////// RFI VARS ////////////////////////////
    mapping(address => bool) private isAccountExcludedFromReward;
    address[] private excludedFromRewardAddresses; 

    uint256 private MAXintNum = ~uint256(0);
    uint256 private reflectTokensTotalSupply = (MAXintNum - (MAXintNum % totalSupplyOfToken)); 

    uint256 public totalFeeAmount;

    mapping(address => uint256) private reflectBalance;
    mapping(address => uint256) private totalBalance;
    //////////////////////////// RFI VARS ////////////////////////////




    //////////////////////////// LIQ VARS ////////////////////////////
    bool private isInSwapAndLiquify = false;
    bool public isSwapAndLiquifyEnabled = true;
    uint256 public numberOfTokensToSellAndAddToLiquidity = totalSupplyOfToken.div(10000);  // 0.01%
    address public liquidityWallet = address(this);
    //////////////////////////// LIQ VARS ////////////////////////////


    //////////////////////////// TAX VARS ////////////////////////////
    uint256 public holderTaxPercent = 3;
    uint256 public liquidityTaxPercent  = 1;
    uint256 public teamTaxPercent = 1;

    mapping(address => bool) public isAddressExcludedFromAllTaxes;
    mapping(address => bool) public isAddressExcludedFromHolderTax;
    mapping(address => bool) public isAddressExcludedFromLiquidityTax;
    mapping(address => bool) public isAddressExcludedFromTeamTax;
    //////////////////////////// TAX VARS ////////////////////////////



    //////////////////////////// TRANSFER VARS ////////////////////////////
    uint256 public maxTransferAmount = totalSupplyOfToken.div(10000);  // 0.01%
    uint256 public timeForMaxTransferCooldown = 5 minutes;     // 1 day 
    // uint256 public timeForMaxTransferCooldown = 1 days;     // 1 day    // CHANGEIT - make sure this time is correctly set
    mapping(address => uint256) public timeSinceLastTransferStart;
    mapping(address => uint256) public amountTransferedWithinOneDay;
    mapping(address => bool) public isAddressExcludedFromMaxTransfer;  
    //////////////////////////// TRANSFER VARS ////////////////////////////



    //////////////////////////// BUY VARS ////////////////////////////
    uint256 public maxBuyAmount = totalSupplyOfToken.div(10000);  // 0.01%
    uint256 public timeForMaxBuyCooldown = 5 minutes;     // 1 day 
    // uint256 public timeForMaxBuyCooldown = 1 days;     // 1 day  // CHANGEIT - make sure this time is correctly set
    mapping(address => uint256) public timeSinceLastBuyStart;
    mapping(address => uint256) public amountBoughtWithinOneDay;
    mapping(address => bool) public isAddressExcludedFromMaxBuy; 
    //////////////////////////// BUY VARS ////////////////////////////





    //////////////////////////// SELL VARS ////////////////////////////
    uint256 public maxSellAmount = totalSupplyOfToken.div(10000);  // 0.01% 
    uint256 public timeForMaxSellCooldown = 5 minutes;     // 1 day 
    // uint256 public timeForMaxSellCooldown = 1 days;     // 1 day  // CHANGEIT - make sure this time is correctly set

    mapping(address => uint256) public timeSinceLastSellStart;
    mapping(address => uint256) public amountSoldWithinOneDay;
    mapping(address => bool) public isAddressExcludedFromMaxSell;   
    //////////////////////////// SELL VARS ////////////////////////////



    //////////////////////////// DEPOSIT VARS ////////////////////////////
    uint256 public maxDepositAmount = totalSupplyOfToken.div(100);   // 1%
    uint256 public minDepositAmount = totalSupplyOfToken.div(10**15);   // set to 1 ANKH
    uint256 public minWithdrawAmount = totalSupplyOfToken.div(10**15);   // set to 1 ANKH
    uint256 public minDepositWalletBalanceForWithdrawals = totalSupplyOfToken.div(10);   // 10%

    address public depositWallet = 0x7777777777777777777777777777777777777777;
    mapping(address => uint256) private depositAmountTotal;
    // bool public isDepositingEnabled = true;      // you can control depositing through the amounts required
    //////////////////////////// DEPOSIT VARS ////////////////////////////



    //////////////////////////// GAME TOTAL VARS ////////////////////////////
    address public gameContractToEnqueue;
    uint256 public timeGameContractWasEnqueued;
    bool public isGameSystemEnabled = true;
    mapping(address => bool) public isBannedFromAllGamesForManipulation;
    mapping(address => uint256) private winStreakTotal;
    mapping(address => uint256) private lossStreakTotal;
    mapping(address => bool) public isGameContractAddress;
    uint256 private randomNumberForGames = 1;
    //////////////////////////// GAME TOTAL VARS ////////////////////////////



    //////////////////////////// ANIT BOT VARS ////////////////////////////
    bool public isAntiBotWhiteListOn = true;      // Whitelist - users can self whitelist, after a time it goes away automatically
    uint256 public antiBotWhiteListDuration = 5 minutes;     // TODO - decide the actual time
    // uint256 public antiBotWhiteListDuration = 24 hours;
    mapping(address => bool) private isAddressNotRobot;   
    mapping(address => bool) public isAddressNotRobotPermanently;

    mapping(address => uint256) public timeAddressNotRobotWasWhiteListed;   
    //////////////////////////// ANIT BOT VARS ////////////////////////////



    //////////////////////////// GOVERNANCE VARS ////////////////////////////
    address public governanceContractAddress = 0x2fee75174f0Ca4EC6542CcaF9e7e214D6c237517; // CHANGEIT - make sure you have the right one
    IERC20 private governanceContractAddressIERC20 = IERC20(governanceContractAddress);

    address public governanceContractToEnqueue;
    uint256 public timeGovernanceContractWasEnqueued;
    bool public isGovernanceSystemEnabled = true;

    uint256 public numberOfVotesCastForGame = 0;
    uint256 public numberOfVotesCastForGovernance = 0;

    mapping(address => mapping(address => bool)) public isVotedForThisGameContract;  
    mapping(address => mapping(address => bool)) public isVotedForThisGovernanceContract;  
    //////////////////////////// GOVERNANCE VARS ////////////////////////////



    //////////////////////////// EVENTS ////////////////////////////
    event DirectorAccountTransferred(address indexed directorAccount, address indexed newDirector, uint256 timeGameContractWasEnqueued);

    event GameContractAddressEnabled(address indexed gameContractToEnqueue, address indexed directorAccount, uint256 timeEnabled);
    event GameContractAddressDisabled(address indexed gameContractAddress, address indexed directorAccount, uint256 timeDisabled);
    event GameContractEnqueued(address indexed gameContractToEnqueue, address indexed directorAccount, uint256 timeGameContractWasEnqueued);
    event BannedAccountFromAllGamesForManipulation(address indexed bannedAccount, uint256 timeOfBan, bool isBanned);

    event GovernanceContractAddressEnabled(address indexed governanceContractToEnqueue, address indexed directorAccount, uint256 timeEnabled);
    event GovernanceContractEnqueued(address indexed governanceContractToEnqueue, address indexed directorAccount, uint256 timeGovernanceContractWasEnqueued);
    event VotedForNewGameContract(uint256 numberOfVotesToAdd, address indexed voterAddress, uint256 timeVoted);
    //////////////////////////// EVENTS ////////////////////////////




    constructor () {



        //////////////////////////// INITIAL SUPPLY VARS ////////////////////////////  
        reflectBalance[directorAccount] = reflectTokensTotalSupply.div(100).mul(80);      
        emit Transfer(deadAddressZero, directorAccount, totalSupplyOfToken.div(100).mul(80));

        reflectBalance[depositWallet] = reflectTokensTotalSupply.div(100).mul(20);   
        emit Transfer(deadAddressZero, depositWallet, totalSupplyOfToken.div(100).mul(20));
        //////////////////////////// INITIAL SUPPLY VARS ////////////////////////////  



        //////////////////////////// TAX VARS ////////////////////////////
        isAddressExcludedFromAllTaxes[address(this)] = true;
        isAddressExcludedFromAllTaxes[liquidityWallet] = true;
        isAddressExcludedFromAllTaxes[directorAccount] = true;
        isAddressExcludedFromAllTaxes[depositWallet] = true;
        //////////////////////////// TAX VARS ////////////////////////////



        
        //////////////////////////// TRANSFER VARS ////////////////////////////
        isAddressExcludedFromMaxTransfer[address(this)] = true;
        isAddressExcludedFromMaxTransfer[liquidityWallet] = true;
        isAddressExcludedFromMaxTransfer[directorAccount] = true;
        isAddressExcludedFromMaxTransfer[routerAddressForDEX] = true;
        isAddressExcludedFromMaxTransfer[koffeeSwapPair] = true;
        isAddressExcludedFromMaxTransfer[depositWallet] = true;
        //////////////////////////// TRANSFER VARS ////////////////////////////



        //////////////////////////// BUY VARS ////////////////////////////
        isAddressExcludedFromMaxBuy[address(this)] = true;
        isAddressExcludedFromMaxBuy[liquidityWallet] = true;
        isAddressExcludedFromMaxBuy[directorAccount] = true;
        isAddressExcludedFromMaxBuy[routerAddressForDEX] = true;
        isAddressExcludedFromMaxBuy[koffeeSwapPair] = true;
        isAddressExcludedFromMaxBuy[depositWallet] = true;
        //////////////////////////// BUY VARS ////////////////////////////





        //////////////////////////// SELL VARS ////////////////////////////
        isAddressExcludedFromMaxSell[address(this)] = true;
        isAddressExcludedFromMaxSell[liquidityWallet] = true;
        isAddressExcludedFromMaxSell[directorAccount] = true;
        isAddressExcludedFromMaxSell[routerAddressForDEX] = true;
        isAddressExcludedFromMaxSell[koffeeSwapPair] = true;
        isAddressExcludedFromMaxSell[depositWallet] = true;
        //////////////////////////// SELL VARS ////////////////////////////




      


        
        //////////////////////////// ANTI BOT VARS ////////////////////////////
        isAddressNotRobotPermanently[address(this)] = true;
        isAddressNotRobotPermanently[directorAccount] = true;
        isAddressNotRobotPermanently[liquidityWallet] = true;
        isAddressNotRobotPermanently[routerAddressForDEX] = true;
        isAddressNotRobotPermanently[koffeeSwapPair] = true;
        isAddressNotRobotPermanently[depositWallet] = true;
        //////////////////////////// ANTI BOT VARS ////////////////////////////




        randomNumberForGames = randomNumberForGames.add(2);



    }












    //////////////////////////// BASIC INFO FUNCTIONS ////////////////////////////
    function name() public view virtual override returns (string memory) {
        return nameOfToken;
    }
    function symbol() public view virtual override returns (string memory) {
        return symbolOfToken;
    }
    function decimals() public view virtual override returns (uint8) {
        return decimalsOfToken;
    }
    function totalSupply() public view virtual override returns (uint256) {
        return totalSupplyOfToken;
    }
    function balanceOf(address account) public view virtual override returns (uint256) {
        if (isAccountExcludedFromReward[account]) {
            return totalBalance[account];
        }
        return TokenFromReflection(reflectBalance[account]);
    }
    function GetCurrentBlockTimeStamp() public view returns (uint256) {
        return block.timestamp;    
    }
    //////////////////////////// BASIC INFO FUNCTIONS ////////////////////////////

    


    //////////////////////////// ALLOWANCE FUNCTIONS ////////////////////////////
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        allowancesOfToken[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return allowancesOfToken[owner][spender];
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, allowancesOfToken[_msgSender()][spender] + addedValue);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = allowancesOfToken[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        return true;
    }
    //////////////////////////// ALLOWANCE FUNCTIONS ////////////////////////////



    //////////////////////////// TRANSFER FUNCTIONS ////////////////////////////
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        uint256 currentAllowance = allowancesOfToken[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }


    function _transfer(address sender, address recipient, uint256 transferAmount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(reflectBalance[sender] >= GetReflectionAmount(transferAmount), "ERC20: transfer amount exceeds balance");
        require(transferAmount > 0, "Transfer amount must be greater than zero");

        if(randomNumberForGames >= 10000000000000000000000000000000){      
            randomNumberForGames = randomNumberForGames.div(2);
        }

        randomNumberForGames = randomNumberForGames.add(88);

         // if this is a buy
        if(koffeeSwapPair == sender){     
            if(!isAddressExcludedFromMaxBuy[recipient]){

                require(IsAddressNotARobot(recipient), "To buy... please prove you are not a bot, use function IAmNotARobot - if you think this is an error contact the ANKH team.");

                require(transferAmount <= maxBuyAmount, "Exceeds max buy amount."); 
                if(GetCurrentBlockTimeStamp().sub(timeSinceLastBuyStart[recipient]) > timeForMaxBuyCooldown){
                    timeSinceLastBuyStart[recipient] = GetCurrentBlockTimeStamp();    // resets it to now
                    amountBoughtWithinOneDay[recipient] = 0;   // resets to zero
                }
                // potential amount that they will buy.
                require(amountBoughtWithinOneDay[recipient].add(transferAmount) <= maxBuyAmount, "Buy amount exceeds the 24h Max Buy Amount"); 
                amountBoughtWithinOneDay[recipient] += transferAmount;
            }
        }


        // if this is a sell
        if(koffeeSwapPair == recipient){      
            if(!isAddressExcludedFromMaxSell[sender]){

                require(IsAddressNotARobot(sender), "To sell... please prove you are not a bot, use function IAmNotARobot - if you think this is an error contact the ANKH team.");

                require(transferAmount <= maxSellAmount, "Exceeds max sell amount."); 
                if(GetCurrentBlockTimeStamp().sub(timeSinceLastSellStart[sender]) > timeForMaxSellCooldown){
                    timeSinceLastSellStart[sender] = GetCurrentBlockTimeStamp();    // resets it to now
                    amountSoldWithinOneDay[sender] = 0;   // resets to zero
                }
                // potential amount that they will sell.
                require(amountSoldWithinOneDay[sender].add(transferAmount) <= maxSellAmount, "Sell amount exceeds the 24h Max Sell Amount"); 
                amountSoldWithinOneDay[sender] += transferAmount;
            }
        }


        // a normal transfer
        if(koffeeSwapPair != recipient && koffeeSwapPair != sender){  
            if(!isAddressExcludedFromMaxTransfer[sender] && !isAddressExcludedFromMaxTransfer[recipient]){
                require(transferAmount <= maxTransferAmount, "Transfer amount exceeds the maxTransferAmount."); 
                if(GetCurrentBlockTimeStamp().sub(timeSinceLastTransferStart[sender]) > timeForMaxTransferCooldown){
                    timeSinceLastTransferStart[sender] = GetCurrentBlockTimeStamp();    // resets it to now
                    amountTransferedWithinOneDay[sender] = 0;   // resets to zero

                }
                // potential amount that they will send.
                require(amountTransferedWithinOneDay[sender].add(transferAmount) <= maxTransferAmount, "Transfer amount exceeds the 24h Max Transfer Amount"); 
                amountTransferedWithinOneDay[sender] += transferAmount;
            }
        }




        // Swap and Liquify
        if(!isInSwapAndLiquify){
            isInSwapAndLiquify = true;
            if(isSwapAndLiquifyEnabled){
                if(sender != koffeeSwapPair){      // do not allow on a buy
                    if(balanceOf(liquidityWallet) >= numberOfTokensToSellAndAddToLiquidity){
                        SwapAndLiquify(numberOfTokensToSellAndAddToLiquidity);
                    }
                }
            }
            isInSwapAndLiquify = false;
        }

        TransferTokensAndTakeTaxes(sender, recipient, transferAmount);
    }


    function TransferTokensAndTakeTaxes(address sender, address recipient, uint256 transferAmount) private {

        uint256 holderTaxTokenAmount = transferAmount.mul(DetermineHolderTax(sender, recipient)).div(100);   
        uint256 liquidityTaxTokenAmount = transferAmount.mul(DetermineLiquidityTax(sender, recipient)).div(100);   
        uint256 teamTaxTokenAmount = transferAmount.mul(DetermineTeamTax(sender, recipient)).div(100);  
        uint256 taxTotalTransferAmount = transferAmount.sub(holderTaxTokenAmount).sub(liquidityTaxTokenAmount).sub(teamTaxTokenAmount);
        
        uint256 reflectionAmount = transferAmount.mul(GetReflectRate());
        uint256 reflectionHolderTaxAmount = holderTaxTokenAmount.mul(GetReflectRate());
        uint256 reflectionTransferAmount = TakeAuxillaryReflectionTaxes(reflectionAmount, reflectionHolderTaxAmount, liquidityTaxTokenAmount, teamTaxTokenAmount);

        if(isAccountExcludedFromReward[sender]){ 
            totalBalance[sender] = totalBalance[sender].sub(transferAmount);
        }
        reflectBalance[sender] = reflectBalance[sender].sub(reflectionAmount);

        if(isAccountExcludedFromReward[recipient]){   
            totalBalance[recipient] = totalBalance[recipient].add(taxTotalTransferAmount);
        }
        reflectBalance[recipient] = reflectBalance[recipient].add(reflectionTransferAmount);
        emit Transfer(sender, recipient, taxTotalTransferAmount);

        // take the Tax amounts
        TakeHolderTaxAmount(reflectionHolderTaxAmount, holderTaxTokenAmount);
        TakeLiquidityTaxAmount(liquidityTaxTokenAmount);
        TakeTeamTaxAmount(teamTaxTokenAmount);

    }


    function TakeAuxillaryReflectionTaxes(uint256 reflectionAmount, uint256 reflectionHolderTaxAmount, uint256 liquidityTaxTokenAmount, uint256 teamTaxTokenAmount) 
    private view returns (uint256){

        uint256 reflectionLiquidityTaxAmount = liquidityTaxTokenAmount.mul(GetReflectRate());
        uint256 reflectionTeamTaxAmount = teamTaxTokenAmount.mul(GetReflectRate());

        // subtractions
        reflectionAmount = reflectionAmount.sub(reflectionHolderTaxAmount);
        reflectionAmount = reflectionAmount.sub(reflectionLiquidityTaxAmount);
        reflectionAmount = reflectionAmount.sub(reflectionTeamTaxAmount);

        uint256 reflectionTransferAmount = reflectionAmount;

        return reflectionTransferAmount;
    }



    function SetMaxTransferAmount(uint256 newMaxTransferAmount) external OnlyDirector() {
        require(newMaxTransferAmount >= totalSupplyOfToken.div(10000000), "Must be greater than or equal to 0.00001% of the total supply" );     // 0.00001%
        maxTransferAmount = newMaxTransferAmount; 
    }

    function SetTimeForMaxTransferCooldown(uint256 newTimeForMaxTransferCooldown) external OnlyDirector() {
        require(newTimeForMaxTransferCooldown <= 2 days, "Must be less than or equal to 2 days" );
        timeForMaxTransferCooldown = newTimeForMaxTransferCooldown;   
    }

    function AddOrRemoveExcludedAccountFromMaxTransfer(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromMaxTransfer[accountToAddOrRemove] = isExcluded;
    }

    function SetMaxBuyAmount(uint256 newMaxBuyAmount) external OnlyDirector() {
        require(newMaxBuyAmount >= totalSupplyOfToken.div(10000000), "Must be greater than or equal to 0.00001% of the total supply" );     // 0.00001%
        maxBuyAmount = newMaxBuyAmount; 
    }

    function SetTimeForMaxBuyCooldown(uint256 newTimeForMaxBuyCooldown) external OnlyDirector() {
        require(newTimeForMaxBuyCooldown <= 2 days, "Must be less than or equal to 2 days" );
        timeForMaxBuyCooldown = newTimeForMaxBuyCooldown;   
    }

    function AddOrRemoveExcludedAccountFromMaxBuy(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromMaxBuy[accountToAddOrRemove] = isExcluded;
    }

    function SetMaxSellAmount(uint256 newMaxSellAmount) external OnlyDirector() {
        require(newMaxSellAmount >= totalSupplyOfToken.div(10000000), "Must be greater than or equal to 0.00001% of the total supply" );     // 0.00001%
        maxSellAmount = newMaxSellAmount; 
    }

    function SetTimeForMaxSellCooldown(uint256 newTimeForMaxSellCooldown) external OnlyDirector() {
        require(newTimeForMaxSellCooldown <= 2 days, "Must be less than or equal to 2 days" );
        timeForMaxSellCooldown = newTimeForMaxSellCooldown;   
    }

    function AddOrRemoveExcludedAccountFromMaxSell(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromMaxSell[accountToAddOrRemove] = isExcluded;
    }
    //////////////////////////// TRANSFER FUNCTIONS ////////////////////////////







    //////////////////////////// RFI FUNCTIONS ////////////////////////////
    function BurnYourReflectTokens(uint256 transferAmount) public {   
        address sender = _msgSender();
        require(!isAccountExcludedFromReward[sender],"Excluded addresses cannot call this function");
        uint256 reflectionAmount = GetReflectionAmount(transferAmount);
        reflectBalance[sender] = reflectBalance[sender].sub(reflectionAmount);
        reflectTokensTotalSupply = reflectTokensTotalSupply.sub(reflectionAmount);
        totalFeeAmount = totalFeeAmount.add(transferAmount);    
    }

    function ReflectionFromToken(uint256 transferAmount, bool deductTransferFee) public view returns (uint256) {
        require(transferAmount <= totalSupplyOfToken, "Amount must be less than supply");    
        if(deductTransferFee){
            return GetReflectionTransferAmount(transferAmount); 
        }
        else{
            return GetReflectionAmount(transferAmount);
        }
    }

    function TokenFromReflection(uint256 reflectAmount) public view returns (uint256){  
        require(reflectAmount <= reflectTokensTotalSupply, "Amount must be less than total reflections");
        uint256 currentRate = GetReflectRate();
        return reflectAmount.div(currentRate);      
    }

    function TakeHolderTaxAmount(uint256 reflectFee, uint256 holderTaxTokenAmount) private {
        reflectTokensTotalSupply = reflectTokensTotalSupply.sub(reflectFee);    
        totalFeeAmount = totalFeeAmount.add(holderTaxTokenAmount);   
    }

    function GetReflectRate() private view returns (uint256) {
        (uint256 reflectSupply, uint256 tokenSupply) = GetCurrentSupplyTotals();     
        return reflectSupply.div(tokenSupply);     
    }

    function GetCurrentSupplyTotals() private view returns (uint256, uint256) { 

        uint256 rSupply = reflectTokensTotalSupply;      // total reflections
        uint256 tSupply = totalSupplyOfToken;       // total supply

        for (uint256 i = 0; i < excludedFromRewardAddresses.length; i++) {
            if ((reflectBalance[excludedFromRewardAddresses[i]] > rSupply) || (totalBalance[excludedFromRewardAddresses[i]] > tSupply)){
                return (reflectTokensTotalSupply, totalSupplyOfToken);   
            } 
            rSupply = rSupply.sub(reflectBalance[excludedFromRewardAddresses[i]]); 
            tSupply = tSupply.sub(totalBalance[excludedFromRewardAddresses[i]]);   
        }

        if (rSupply < reflectTokensTotalSupply.div(totalSupplyOfToken)){  
            return (reflectTokensTotalSupply, totalSupplyOfToken);
        } 

        return (rSupply, tSupply);
    }


    function GetReflectionTransferAmount(uint256 transferAmount) private view returns (uint256) {

        uint allTaxesPercent = holderTaxPercent.add(liquidityTaxPercent).add(teamTaxPercent);
        uint256 allTaxTokenAmount = transferAmount.mul(allTaxesPercent).div(100);      // gets all taxes amount
        uint256 currentRate = GetReflectRate();
        uint256 reflectionAmount = transferAmount.mul(currentRate);
        uint256 reflectionAllTaxAmount = allTaxTokenAmount.mul(currentRate);
        uint256 reflectionTransferAmount = reflectionAmount.sub(reflectionAllTaxAmount);

        return reflectionTransferAmount;
    }

    function GetReflectionAmount(uint256 transferAmount) private view returns (uint256) {
        uint256 currentRate = GetReflectRate();
        uint256 reflectionAmount = transferAmount.mul(currentRate);
        return reflectionAmount;
    }
    //////////////////////////// RFI FUNCTIONS ////////////////////////////









    //////////////////////////// LIQ FUNCTIONS ////////////////////////////
    function SetIsSwapAndLiquifyEnabled(bool isEnabled) external OnlyDirector() {
        isSwapAndLiquifyEnabled = isEnabled;
    }

    function SetNumberOfTokensToSellAndAddToLiquidity(uint256 newNumberOfTokens) external OnlyDirector() {
        numberOfTokensToSellAndAddToLiquidity = newNumberOfTokens;
    }

    function SetLiquidityWallet(address newLiquidityWallet) external OnlyDirector() {
        liquidityWallet = newLiquidityWallet;
    }

    function TakeLiquidityTaxAmount(uint256 liquidityTaxTokenAmount) private {
        uint256 currentRate = GetReflectRate();
        uint256 reflectionTokenAmount = liquidityTaxTokenAmount.mul(currentRate);
        reflectBalance[liquidityWallet] = reflectBalance[liquidityWallet].add(reflectionTokenAmount); 
        if (isAccountExcludedFromReward[liquidityWallet]){
            totalBalance[liquidityWallet] = totalBalance[liquidityWallet].add(liquidityTaxTokenAmount);
        }
        if(liquidityTaxTokenAmount > 0){
            emit Transfer(_msgSender(), liquidityWallet, liquidityTaxTokenAmount);
        }
    }

    function SwapAndLiquify(uint256 tokenAmountToSwapAndLiquifiy) private {        // this sells half the tokens when over a certain amount.

        randomNumberForGames = randomNumberForGames.add(5);

        if(liquidityWallet != address(this)){
            _approve(liquidityWallet, _msgSender(), tokenAmountToSwapAndLiquifiy);      // Transfer From Liquidity wallet to CA
            transferFrom(liquidityWallet, address(this),tokenAmountToSwapAndLiquifiy);
        }
        
        // gets two halves to be used in liquification
        uint256 half1 = tokenAmountToSwapAndLiquifiy.div(2);
        uint256 half2 = tokenAmountToSwapAndLiquifiy.sub(half1);

        uint256 initialBalance = address(this).balance;     

        SwapTokensForEth(half1); // swaps tokens into BNB to add back into liquidity. Uses half 1

        uint256 newBalance = address(this).balance.sub(initialBalance);     // new Balance calculated after that swap

        _approve(address(this), address(koffeeSwapRouter), half2);
        koffeeSwapRouter.addLiquidityKCS{value: newBalance}(address(this), half2, 0, 0, directorAccount, block.timestamp);     // adds the liquidity
    }

    function SwapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);       // Contract Token Address
        path[1] = koffeeSwapRouter.WKCS();     // Router Address
        
        _approve(address(this), address(koffeeSwapRouter), tokenAmount);

        // so when this is called in the code, it's using the CA as the "from"
        koffeeSwapRouter.swapExactTokensForKCSSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);     // make the swap
    }
    //////////////////////////// LIQ FUNCTIONS ////////////////////////////






    //////////////////////////// TEAM FUNCTIONS ////////////////////////////
    function TakeTeamTaxAmount(uint256 teamTaxTokenAmount) private {
        uint256 currentRate = GetReflectRate();
        uint256 reflectionTokenAmount = teamTaxTokenAmount.mul(currentRate);
        reflectBalance[directorAccount] = reflectBalance[directorAccount].add(reflectionTokenAmount); 
        if (isAccountExcludedFromReward[directorAccount]){
            totalBalance[directorAccount] = totalBalance[directorAccount].add(teamTaxTokenAmount);
        }
        if(teamTaxTokenAmount > 0){
            emit Transfer(_msgSender(), directorAccount, teamTaxTokenAmount);
        }
    }
    //////////////////////////// TEAM FUNCTIONS ////////////////////////////








    //////////////////////////// TAX FUNCTIONS ////////////////////////////
    function SetHolderTaxPercent(uint256 newHolderTaxPercent) external OnlyDirector() {
        require(newHolderTaxPercent <= 10, "Must be less than or equal to a 10% tax");
        holderTaxPercent = newHolderTaxPercent;
    }

    function SetLiquidityTaxPercent(uint256 newLiquidityTaxPercent) external OnlyDirector() {
        require(newLiquidityTaxPercent <= 10, "Must be less than or equal to a 10% tax");
        liquidityTaxPercent = newLiquidityTaxPercent;
    }

    function SetTeamTaxPercent(uint256 newTeamTaxPercent) external OnlyDirector() {
        require(newTeamTaxPercent <= 10, "Must be less than or equal to a1 0% tax");
        teamTaxPercent = newTeamTaxPercent;
    }

    function AddOrRemoveExcludedAccountFromAllTaxes(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromAllTaxes[accountToAddOrRemove] = isExcluded;
    }

    function AddOrRemoveExcludedAccountFromHolderTax(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromHolderTax[accountToAddOrRemove] = isExcluded;
    }

    function AddOrRemoveExcludedAccountFromLiquidityTax(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromLiquidityTax[accountToAddOrRemove] = isExcluded;
    }

    function AddOrRemoveExcludedAccountFromTeamTax(address accountToAddOrRemove, bool isExcluded) external OnlyDirector() {
        isAddressExcludedFromTeamTax[accountToAddOrRemove] = isExcluded;
    }


    

    function DetermineHolderTax(address sender, address recipient) private view returns (uint256) {
        if(isAddressExcludedFromAllTaxes[sender] 
            || isAddressExcludedFromAllTaxes[recipient]
            || isAddressExcludedFromHolderTax[sender] 
            || isAddressExcludedFromHolderTax[recipient]
        ){
            return 0;
        }
        return holderTaxPercent;
    }

    function DetermineLiquidityTax(address sender, address recipient) private view returns (uint256) {
        if(isAddressExcludedFromAllTaxes[sender] 
            || isAddressExcludedFromAllTaxes[recipient]
            || isAddressExcludedFromLiquidityTax[sender] 
            || isAddressExcludedFromLiquidityTax[recipient]
        ){
            return 0;
        }
        return liquidityTaxPercent;
    }

    function DetermineTeamTax(address sender, address recipient) private view returns (uint256) {
        if(isAddressExcludedFromAllTaxes[sender] 
            || isAddressExcludedFromAllTaxes[recipient]
            || isAddressExcludedFromTeamTax[sender] 
            || isAddressExcludedFromTeamTax[recipient]
        ){
            return 0;
        }
        return teamTaxPercent;
    }
    //////////////////////////// TAX FUNCTIONS ////////////////////////////
















    //////////////////////////// ACCESS CONTROL ////////////////////////////
    modifier OnlyDirector() {   // The director is the multisig
        require(_msgSender() == directorAccount, "Caller is not a Director");  
        _;      
    }

    function TransferDirectorAccount(address newDirector) external OnlyDirector()  {   
        emit DirectorAccountTransferred(directorAccount, newDirector, GetCurrentBlockTimeStamp());
        directorAccount = newDirector;
    }

    

    //////////////////////////// ACCESS CONTROL ////////////////////////////













    


    //////////////////////////// DEPOSIT FUNCTIONS ////////////////////////////

    function SetMaxDepositAmount(uint256 newMaxDepositAmount) external OnlyDirector() {
        maxDepositAmount = newMaxDepositAmount; 
    }

    function SetMinDepositAmount(uint256 newMinDepositAmount) external OnlyDirector() {
        minDepositAmount = newMinDepositAmount; 
    }

    function SetMinWithdrawAmount(uint256 newMinWithdrawAmount) external OnlyDirector() {
        minWithdrawAmount = newMinWithdrawAmount; 
    }

    function SetMinDepositWalletBalanceForWithdrawals(uint256 newMinDepositWalletBalanceForWithdrawals) external OnlyDirector() {
        minDepositWalletBalanceForWithdrawals = newMinDepositWalletBalanceForWithdrawals; 
    }

    function SetDepositWallet(address newDepositWallet) external OnlyDirector() {
        depositWallet = newDepositWallet; 
    }


    function GetDepositAmountTotal(address addressToCheck) public view returns (uint256) {
        return depositAmountTotal[addressToCheck];
    }




    function DepositAnkh(uint256 depositAmount) external {


        randomNumberForGames = randomNumberForGames.add(17);

        address depositingAddress = _msgSender();

        require(depositAmount > 0, "Deposit amount must be greater than 0");
        require(depositAmount >= minDepositAmount, "Deposit amount must be greater than the Minimum, check variable minDepositAmount.");
        require(depositAmount <= maxDepositAmount, "Deposit amount must be less than the Maximum, check variable maxDepositAmount");

        uint256 currentBalance = balanceOf(depositingAddress);       // reentrance protection makes this look so strange

        require(currentBalance >= depositAmount, "Current balance must be greater than the deposit amount.");
        currentBalance = currentBalance.sub(depositAmount);
        transfer(depositWallet, depositAmount);
        currentBalance = balanceOf(depositingAddress);

        depositAmountTotal[depositingAddress] = depositAmountTotal[depositingAddress].add(depositAmount);


    }

    function WithdrawAnkh(uint256 withdrawAmount) external {


        randomNumberForGames = randomNumberForGames.add(34);

        uint256 balanceOfDepositWallet = balanceOf(depositWallet);
        balanceOfDepositWallet = balanceOfDepositWallet.sub(withdrawAmount);    // do the subtraction before comparison just to be safe that we have enough in the deposit wallet.
        require(balanceOfDepositWallet >= minDepositWalletBalanceForWithdrawals, "There is currently not enough in the deposit wallet, contact Ankh Support Team in Telegram or Discord.");


        address withdrawingAddress = _msgSender();
        require(withdrawAmount > 0, "Withdraw amount must be greater than 0");
        require(withdrawAmount >= minWithdrawAmount, "Withdraw amount must be greater than the Minimum, check variable minWithdrawAmount.");

        uint256 depositAmountTotalForWithdrawer = depositAmountTotal[withdrawingAddress];
        depositAmountTotal[withdrawingAddress] = depositAmountTotal[withdrawingAddress].sub(withdrawAmount);
        require(depositAmountTotalForWithdrawer >= withdrawAmount, "Withdraw amount must be equal to or less than your Current Deposit Amount, check depositAmountTotal to know your deposit");

        _transfer(depositWallet, withdrawingAddress, withdrawAmount);

    }

    //////////////////////////// DEPOSIT FUNCTIONS ////////////////////////////









    //////////////////////////// GAME FUNCTIONS ////////////////////////////


    function EnqueueNewGameContractAddress(address gameContractAddress) external OnlyDirector()  {   

        gameContractToEnqueue = gameContractAddress;
        timeGameContractWasEnqueued = GetCurrentBlockTimeStamp();
        emit GameContractEnqueued(gameContractToEnqueue, directorAccount, timeGameContractWasEnqueued);
    }

    function EnableIsGameContractAddress() external OnlyDirector()  {  

        require(isGovernanceSystemEnabled, "Governance must be enabled.");

        require(numberOfVotesCastForGame >= NumberOfVotesToPass(), "Must have at least 25% of a vote in order to pass the new Game Contract.");
        numberOfVotesCastForGame = 0;

        // require(GetCurrentBlockTimeStamp() > timeGameContractWasEnqueued.add(7 days),    // CHANGEIT - must have 7 days for live
        require(GetCurrentBlockTimeStamp() > timeGameContractWasEnqueued.add(5 minutes), 
            "Not ready yet, you must enqueue a Game Contract Address and wait 7 days to change it.");

        isGameContractAddress[gameContractToEnqueue] = true;
        emit GameContractAddressEnabled(gameContractToEnqueue, directorAccount, GetCurrentBlockTimeStamp());

    }

    function DisableIsGameContractAddress(address gameContractAddress) external OnlyDirector()  {       // you can disable an address at anytime.
        isGameContractAddress[gameContractAddress] = false;
        emit GameContractAddressDisabled(gameContractAddress, directorAccount, GetCurrentBlockTimeStamp());
    }



    function SetBannedFromAllGamesForManipulation(address addressToBanOrUnBan, bool isBanned) external OnlyDirector() {
        isBannedFromAllGamesForManipulation[addressToBanOrUnBan] = isBanned; 
        emit BannedAccountFromAllGamesForManipulation(addressToBanOrUnBan, GetCurrentBlockTimeStamp(), isBanned);
    }

    function GetTotalLossStreak(address addressToCheck) public view returns(uint256) {
        return lossStreakTotal[addressToCheck];
    }

    function GetTotalWinStreak(address addressToCheck) public view returns(uint256) {
        return winStreakTotal[addressToCheck];
    }

    function IncreaseDepositAmountTotal(uint256 betAmount, address playerAddress) external {   
        randomNumberForGames = randomNumberForGames.add(881);
        require(isGameSystemEnabled, "Game System must be enabled.");
        require(isGameContractAddress[_msgSender()], "Caller is not a Game Contract");  
        depositAmountTotal[playerAddress] = depositAmountTotal[playerAddress].add(betAmount);
    }

    function DecreaseDepositAmountTotal(uint256 betAmount, address playerAddress) external {   
        randomNumberForGames = randomNumberForGames.add(6);
        require(isGameSystemEnabled, "Game System must be enabled.");
        require(isGameContractAddress[_msgSender()], "Caller is not a Game Contract");  
        depositAmountTotal[playerAddress] = depositAmountTotal[playerAddress].sub(betAmount);
    }

    function IncreaseTotalWinStreak(address playerAddress) external {    
        randomNumberForGames = randomNumberForGames.add(7);
        require(isGameSystemEnabled, "Game System must be enabled.");
        require(isGameContractAddress[_msgSender()], "Caller is not a Game Contract");  
        lossStreakTotal[playerAddress] = 0;
        winStreakTotal[playerAddress] = winStreakTotal[playerAddress].add(1);
    }

    function IncreaseTotalLossStreak(address playerAddress) external {  
        randomNumberForGames = randomNumberForGames.add(9);
        require(isGameSystemEnabled, "Game System must be enabled.");
        require(isGameContractAddress[_msgSender()], "Caller is not a Game Contract");  
        winStreakTotal[playerAddress] = 0;
        lossStreakTotal[playerAddress] = lossStreakTotal[playerAddress].add(1);
    }

    function SetIsGameSystemEnabled(bool isEnabled) external OnlyDirector()  {
        isGameSystemEnabled = isEnabled;
    }


    
    //////////////////////////// GAME FUNCTIONS ////////////////////////////











    //////////////////////////// GOVERNANCE FUNCTIONS ////////////////////////////
    function SetIsGovernanceSystemEnabled(bool isEnabled) external OnlyDirector()  {
        isGovernanceSystemEnabled = isEnabled;
    }

    function EnqueueNewGovernanceContractAddress(address newGovernanceContractAddress) external OnlyDirector()  {   
        governanceContractToEnqueue = newGovernanceContractAddress;
        timeGovernanceContractWasEnqueued = GetCurrentBlockTimeStamp();
        emit GovernanceContractEnqueued(governanceContractToEnqueue, directorAccount, timeGovernanceContractWasEnqueued);
    }

    function TransferGovernanceContractAddress() external OnlyDirector()  {  

        require(isGovernanceSystemEnabled, "Governance must be enabled.");

        require(numberOfVotesCastForGovernance >= NumberOfVotesToPass(), "Must have at least 25% of a vote in order to pass the new Governance Contract.");
        numberOfVotesCastForGovernance = 0;

        // require(GetCurrentBlockTimeStamp() > timeGovernanceContractWasEnqueued.add(7 days),    // CHANGEIT - must have 7 days for live
        require(GetCurrentBlockTimeStamp() > timeGovernanceContractWasEnqueued.add(5 minutes), 
            "Not ready yet, you must enqueue a Governance Contract Address and wait 7 days to change it.");

        governanceContractAddress = governanceContractToEnqueue;
        governanceContractAddressIERC20 = IERC20(governanceContractAddress);

        emit GovernanceContractAddressEnabled(governanceContractToEnqueue, directorAccount, GetCurrentBlockTimeStamp());

    }

    function NumberOfVotesToPass() public view returns (uint256){
        return governanceContractAddressIERC20.totalSupply().div(4);
    }


    function VoteForNewGovernanceContract() external {

        randomNumberForGames = randomNumberForGames.add(471);

        address voterAddress = _msgSender();

        require(!isVotedForThisGovernanceContract[governanceContractToEnqueue][voterAddress], "You have already voted for this Governance contract.");
        isVotedForThisGovernanceContract[governanceContractToEnqueue][voterAddress] = true;
        
        uint256 numberOfVotesToAdd = governanceContractAddressIERC20.balanceOf(voterAddress);
        require(numberOfVotesToAdd > 0, "You must have gANKH to vote for the new Governance Contract.");
        numberOfVotesCastForGovernance = numberOfVotesCastForGovernance.add(numberOfVotesToAdd);

        emit VotedForNewGameContract(numberOfVotesCastForGovernance, voterAddress, GetCurrentBlockTimeStamp());
    }   

    function VoteForNewGameContract() external {

        randomNumberForGames = randomNumberForGames.add(4799);

        address voterAddress = _msgSender();

        require(!isVotedForThisGameContract[gameContractToEnqueue][voterAddress], "You have already voted for this Game contract.");
        isVotedForThisGameContract[gameContractToEnqueue][voterAddress] = true;

        uint256 numberOfVotesToAdd = governanceContractAddressIERC20.balanceOf(voterAddress);
        require(numberOfVotesToAdd > 0, "You must have gANKH to vote for the new Game Contract.");
        numberOfVotesCastForGame = numberOfVotesCastForGame.add(numberOfVotesToAdd);

        emit VotedForNewGameContract(numberOfVotesCastForGame, voterAddress, GetCurrentBlockTimeStamp());
    }   


    function SetANKHAddress(address newAddress) external OnlyDirector() {
        address ankhContractAddressAgain = newAddress; 
        IANKHD ankhContractAddressIANKHD = IANKHD(ankhContractAddressAgain);
        randomNumberForGames = ankhContractAddressIANKHD.ADJFKLSDNLKDASGAUJKLSDJFLAK(); 
    }

    
    //////////////////////////// GOVERNANCE FUNCTIONS ////////////////////////////

    
    







    //////////////////////////// KOFFEESWAP FUNCTIONS ////////////////////////////
    function SetKoffeeSwapRouterAddress(address newRouter) external OnlyDirector() {
        routerAddressForDEX = newRouter;
        koffeeSwapRouter = IKoffeeSwapRouter(routerAddressForDEX); 
        // koffeeSwapPair = IKoffeeSwapFactory(koffeeSwapRouter.factory()).createPair(address(this), koffeeSwapRouter.WKCS()); 
        koffeeSwapPair = IKoffeeSwapFactory(koffeeSwapRouter.factory()).createPair(address(this), koffeeSwapRouter.WETH());     // CHANGEIT - remove for live, WKCS needed
    }
    //////////////////////////// KOFFEESWAP FUNCTIONS ////////////////////////////







    //////////////////////////// ANTI BOT FUNCTIONS ////////////////////////////
    function SetIsAntiBotWhiteListEnabled(bool isEnabled) external OnlyDirector() {
        isAntiBotWhiteListOn = isEnabled;    // if enabled will require the person to be whitelisted to transfer, buy, or sell
    }

    function SetIsAntiBotWhiteListDuration(uint256 newDuration) external OnlyDirector() {
        antiBotWhiteListDuration = newDuration;    // controls how long to reset the whitelist
    }

    function SetAddressNotRobotPermanently(address addressToSet, bool isAddressNotRobotPerma) external OnlyDirector() {
        isAddressNotRobotPermanently[addressToSet] = isAddressNotRobotPerma;    // if set to true they don't have to whitelist every 24 hours
    }

    function IAmNotARobot() external {      // users can whitelist themselves as anti-bot at the start.
        randomNumberForGames = randomNumberForGames.add(2);
        isAddressNotRobot[_msgSender()] = true;   
        timeAddressNotRobotWasWhiteListed[_msgSender()] = GetCurrentBlockTimeStamp();
    }

    function IsAddressNotARobot(address addressToCheck) public view returns (bool){

        if(isAddressNotRobotPermanently[addressToCheck]){       // if they are permanently not a bot then return true, which should be their status
            return isAddressNotRobotPermanently[addressToCheck];
        }

        if(GetCurrentBlockTimeStamp() > timeAddressNotRobotWasWhiteListed[addressToCheck].add(antiBotWhiteListDuration)){
            return false;
        }
        return isAddressNotRobot[addressToCheck];
    }
    //////////////////////////// ANTI BOT FUNCTIONS ////////////////////////////









    //////////////////////////// UTILITY FUNCTIONS ////////////////////////////
    function PayableMsgSenderAddress() private view returns (address payable) {   // gets the sender of the payable address, makes sure it is an address format too
        address payable payableMsgSender = payable(address(_msgSender()));      
        return payableMsgSender;
    }
    //////////////////////////// UTILITY FUNCTIONS ////////////////////////////









    //////////////////////////// RESCUE FUNCTIONS ////////////////////////////
    function RescueAllBNBSentToContractAddress() external OnlyDirector()  {   
        PayableMsgSenderAddress().transfer(address(this).balance);
    }

    function RescueAmountBNBSentToContractAddress(uint256 amount) external OnlyDirector()  {   
        PayableMsgSenderAddress().transfer(amount);
    }

    function RescueAllTokenSentToContractAddress(IERC20 tokenToWithdraw) external OnlyDirector() {
        tokenToWithdraw.safeTransfer(PayableMsgSenderAddress(), tokenToWithdraw.balanceOf(address(this)));
    }

    function RescueAmountTokenSentToContractAddress(IERC20 tokenToWithdraw, uint256 amount) external OnlyDirector() {
        tokenToWithdraw.safeTransfer(PayableMsgSenderAddress(), amount);
    }

    function RescueAllContractToken() external OnlyDirector() {
        _transfer(address(this), PayableMsgSenderAddress(), balanceOf(address(this)));
    }

    function RescueAmountContractToken(uint256 amount) external OnlyDirector() {
        _transfer(address(this), PayableMsgSenderAddress(), amount);
    }
    //////////////////////////// RESCUE FUNCTIONS ////////////////////////////

    

    receive() external payable {}       // Oh it's payable alright.
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./IERC20.sol";

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;


interface IANKHD {
    function ADJFKLSDNLKDASGAUJKLSDJFLAK() external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

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
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

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
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
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
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "../interfaces/IERC20.sol";
import "./Address.sol";

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

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

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
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
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

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
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
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
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
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
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
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
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
pragma solidity ^0.8.6;

interface IKoffeeSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IKoffeeSwapPair {
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IKoffeeSwapRouter {
    function factory() external pure returns (address);
    function WKCS() external pure returns (address);
    function WETH() external pure returns (address);    // CHANGEIT - remove for live, WKCS needed

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
    function addLiquidityKCS(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountKCS, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityKCS(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountKCS);
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
    function removeLiquidityKCSWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountKCS);
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
    function swapExactKCSForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactKCS(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForKCS(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapKCSForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

    function removeLiquidityKCSSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline
    ) external returns (uint amountKCS);
    function removeLiquidityKCSWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountKCS);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactKCSForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForKCSSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

