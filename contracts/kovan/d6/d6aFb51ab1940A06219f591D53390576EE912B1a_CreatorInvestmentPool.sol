// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
import "./InvestmentPool.sol";
import "./interface/IAssetsManageTeam.sol";
contract CreatorInvestmentPool {
    address private _poolRegistry; // Address pool registry
    address private _returnInvestmentLpartner;// Address ReturnInvestmentLpartner
    IAssetsManageTeam private _assetsManageTeam;// Address token request contract
    constructor(
        address pool,
        IAssetsManageTeam assetManageTeam,
        address returnInvestLpartner
    ) public {
        _poolRegistry = pool;
        _assetsManageTeam = assetManageTeam;
        _returnInvestmentLpartner = returnInvestLpartner;
    }
    function createPool(string memory name,uint256 lockPeriod,uint256 depositFixedFee,uint256 referralDepositFee,uint256 annualPercent,uint256 penaltyEarlyWithdraw,address superAdmin,address gPartner,address lPartner,address startupTeam) public returns (address) {
        require(msg.sender == _poolRegistry, "CreatorInvestmentPool: sender don't poolRegistry contract");
        InvestmentPool _poolContract = new InvestmentPool(name,lockPeriod,depositFixedFee,referralDepositFee,annualPercent,penaltyEarlyWithdraw,superAdmin,gPartner,lPartner,startupTeam,msg.sender,_returnInvestmentLpartner,_assetsManageTeam);
        _assetsManageTeam.addManager(address(_poolContract));
        return address(_poolContract);
    }
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
contract Context {
    constructor () internal { }
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode
        return msg.data;
    }
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
import "./interface/IPoolRegistry.sol";
import "./interface/IAssetsManageTeam.sol";
import "./interface/IERC20.sol";
import "./access/PoolRoles.sol";
import "./math/SafeMath.sol";
contract InvestmentPool is PoolRoles {
    using SafeMath for uint256;
    event Deposit(address indexed from, uint256 value);
    event DebugWithdrawLPartner(address sender,address owner, uint256 getDepositLengthSender, uint256 getDepositLengthOwner,uint256 totalAmountReturn,uint256 indexesDepositLength,uint256 balanceThis);
    string private _name; // Address token contract
    bool private _isPublicPool = true;
    address private _token;// Address token contract
    uint256 private _lockPeriod;// Period lock investment
    uint256 private _rate; // Token unit rate
    uint256 private _poolValueUSD = 0;// Pool value USD, wei
    uint256 private _poolValue = 0;// Pool value main network coin (ETH,BNB), wei
    string private _proofOfValue = "nothing";// Pool proof of value (API keys e.t.c), JSON
    uint256 private _depositFixedFee;// deposit commission LPartner
    uint256 private _referralDepositFee;// Referral commission
    uint256 private _annualPercent;//
    uint256 private _penaltyEarlyWithdraw;// Penalty early withdraw token
    uint256 private _totalInvestLpartner; // Total investment limited partner
    uint256 private _premiumFee;// Premium fee for General partner
    uint256 private _teamReward = 0;// team reward
    uint256 constant private multiplierDefault = 100000;
    struct DepositToPool {
        uint256 amount;          // Amount of funds deposited
        uint256 time;            // Deposit time
        uint256 lock_period;     // Asset lock time
        bool refund_authorize;   // Are assets unlocked for withdrawal
        uint256 amountWithdrawal;
        address investedToken; // address(0) for ETH/BNB
    }
    mapping(address => DepositToPool[]) private _deposites;// Collection of investors who made a deposit ETH
    mapping(address => address) private _referrals;// All referrals who are limited partners
    IAssetsManageTeam private _assetsManageTeam;// Smart contract for requests deposit or withdraw
    IPoolRegistry private _poolRegistry; // Smart contract pool registry contract
    modifier onlyAdmin(address sender) {
        if(hasRole(GENERAL_PARTNER_ROLE, sender) || hasRole(SUPER_ADMIN_ROLE, sender) || _poolRegistry.isTeam(sender)) {
            _;
        } else {
            revert("The sender does not have permission");
        }
    }
    constructor(string memory name, uint256 locked,uint256 depositFixedFee,uint256 referralDepositFee,uint256 annualPercent,uint256 penaltyEarlyWithdraw,address superAdmin,address gPartner, address lPartner,address team,address poolRegistry,address returnInvestmentLpartner,IAssetsManageTeam assetsManageTeam) public {
        _name = name;
        _lockPeriod = locked;
        _depositFixedFee = depositFixedFee;
        _referralDepositFee = referralDepositFee;
        _annualPercent = annualPercent;
        _penaltyEarlyWithdraw = penaltyEarlyWithdraw;
        _assetsManageTeam = assetsManageTeam;
        _poolRegistry = IPoolRegistry(poolRegistry);

        PoolRoles.addAdmin(SUPER_ADMIN_ROLE, msg.sender);
        PoolRoles.addAdmin(SUPER_ADMIN_ROLE, superAdmin);
        PoolRoles.addAdmin(SUPER_ADMIN_ROLE, poolRegistry);

        PoolRoles.finalize();
        grantRole(GENERAL_PARTNER_ROLE, gPartner);
        grantRole(LIMITED_PARTNER_ROLE, lPartner);
        grantRole(STARTUP_TEAM_ROLE, team);
        grantRole(POOL_REGISTRY, poolRegistry);
        grantRole(RETURN_INVESTMENT_LPARTNER, returnInvestmentLpartner);
    }
    receive() external payable {
        if (msg.sender == address(_poolRegistry)) {
            return;
        }

        if (!isContract(msg.sender)) {
            if (!hasRole(LIMITED_PARTNER_ROLE, msg.sender)) {
                _transferGeneralPartner(msg.value);
                return;
            }
            _deposit(msg.sender, msg.value, multiplierDefault);
            return;
        } else if(!hasRole(POOL_REGISTRY, msg.sender)) {
            _transferGeneralPartner(msg.value);
            return;
        }
    }
    function getDeposit(address owner, uint256 index) public view returns(uint256 amount, uint256 time, uint256 lock_period, bool refund_authorize, uint256 amountWithdrawal, address investedToken) {
        return ( _deposites[owner][index].amount,_deposites[owner][index].time,_deposites[owner][index].lock_period,_deposites[owner][index].refund_authorize,_deposites[owner][index].amountWithdrawal,_deposites[owner][index].investedToken);
    }
    function getDepositLength(address owner) public view returns(uint256) {
        return (_deposites[owner].length);
    }
    function getReferral(address lPartner) public view returns (address) {
        return _referrals[lPartner];
    }
    function getInfoPool() public view returns(string memory name,bool isPublicPool,address token,uint256 locked)
    {
        return (_name,_isPublicPool,_token,_lockPeriod);
    }
    function getInfoPoolFees() public view returns( uint256 rate,uint256 depositFixedFee,uint256 referralDepositFee,uint256 annualPercent,uint256 penaltyEarlyWithdraw,uint256 totalInvestLpartner,uint256 premiumFee)
    {
        return (_rate,_depositFixedFee,_referralDepositFee,_annualPercent, _penaltyEarlyWithdraw,_totalInvestLpartner,_premiumFee);
    }
    function _approveWithdrawLpartner(address lPartner, uint256 index, uint256 amount, address investedToken) external onlyReturnsInvestmentLpartner returns (bool) {
        _deposites[lPartner][index].refund_authorize = true;
        _deposites[lPartner][index].amountWithdrawal = amount;
        _deposites[lPartner][index].investedToken = investedToken;
        return true;
    }
    function _depositPoolRegistry(address sender, uint256 amount, uint256 feesMultipier) external onlyPoolRegistry returns (bool) {
        require(hasRole(LIMITED_PARTNER_ROLE, sender), "InvestmentPool: the sender does not have permission");
        return _deposit(sender, amount, feesMultipier);
    }
    function _depositTokenPoolRegistry(address payable sender, uint256 amount) external onlyPoolRegistry returns (bool) {
        require(hasRole(STARTUP_TEAM_ROLE, sender), "InvestmentPool: the sender does not have permission");
        return _depositToken(sender, amount);
    }
    function _withdrawTeam(address payable sender, uint256 amount) external onlyPoolRegistry returns (bool) {
        require(hasRole(STARTUP_TEAM_ROLE, sender), "InvestmentPool: the sender does not have permission");
        _assetsManageTeam._withdraw(address(this), sender, amount);
        sender.transfer(amount);
        return true;
    }
    function _withdrawTokensToStartup(address payable sender,address token, uint256 amount) external onlyPoolRegistry returns (bool) {
        require(hasRole(STARTUP_TEAM_ROLE, sender), "InvestmentPool: the sender does not have permission");
        _assetsManageTeam._withdrawTokensToStartup(address(this),token, sender, amount);
        IERC20(token).transfer(sender, amount);
        return true;
    }
    function _returnsInTokensFromTeam(address payable sender,address token, uint256 amount) external onlyPoolRegistry returns (bool) {
        require(hasRole(STARTUP_TEAM_ROLE, sender), "InvestmentPool: the sender does not have permission");
        IERC20(token).transferFrom(sender, address(this), amount);
        return true;
    }
    function _withdrawLPartner(address payable sender) external onlyPoolRegistry returns (bool, uint256, address) {
        require(hasRole(LIMITED_PARTNER_ROLE, sender), "InvestmentPool: the sender does not have permission");
        uint256 totalAmountReturn = 0;
        address token = address(0);
        uint256 lengthSender = getDepositLength(sender);
        bool result = false;
        for (uint256 i = 0; i < lengthSender; i++) {
            DepositToPool storage deposit = _deposites[sender][i];
            if (deposit.refund_authorize) {
                token = deposit.investedToken;
                if (_teamReward > 0) {
                    payable(getRoleMember(GENERAL_PARTNER_ROLE,0)).transfer(_teamReward);
                }
                if (deposit.amountWithdrawal > 0) {
                    if (token == address(0)) {
                        sender.transfer(deposit.amountWithdrawal);
                        totalAmountReturn = totalAmountReturn.add(deposit.amountWithdrawal);
                    } else {
                        IERC20(token).transfer(sender, deposit.amountWithdrawal);
                    }
                }
                _deposites[sender][i].refund_authorize = false;
                _deposites[sender][i].amountWithdrawal = 0;
            }
        }
        return (result,totalAmountReturn,token);
    }
    function _withdrawSuperAdmin(address payable sender,address token, uint256 amount) external onlyPoolRegistry returns (bool) {
        require(hasRole(SUPER_ADMIN_ROLE, sender), "InvestmentPool: the sender does not have permission");
        if (amount > 0) {
            if (token == address(0)) {
                sender.transfer(amount);
                return true;
            } else {
                IERC20(token).transfer(sender, amount);
                return true;
            }
        }
        return false;
    }
    function _activateDepositToPool() external onlyPoolRegistry returns (bool) {
        require(!_isPublicPool, "InvestmentPool: the pool is already activated");
        _isPublicPool = true;
        return true;
    }
    function _disactivateDepositToPool() external onlyPoolRegistry returns (bool) {
        require(_isPublicPool, "InvestmentPool: the pool is already deactivated");
        _isPublicPool = false;
        return true;
    }
    function _setReferral(address sender, address lPartner, address referral) external onlyPoolRegistry onlyAdmin(sender) returns (bool) {
        _referrals[lPartner] = referral;
        return true;
    }
    function _updatePool(string calldata name,bool isPublicPool,address token,uint256 locked,uint256 depositFixedFee,uint256 referralDepositFee,uint256 annualPercent,uint256 penaltyEarlyWithdraw) external onlyPoolRegistry returns (bool) {
        _name = name;
        _isPublicPool = isPublicPool;
        _token = token;
        _lockPeriod = locked;
        _depositFixedFee = depositFixedFee;
        _referralDepositFee = referralDepositFee;
        _annualPercent = annualPercent;
        _penaltyEarlyWithdraw = penaltyEarlyWithdraw;
        return true;
    }
    function _setRate(uint256 rate) external onlyPoolRegistry returns (bool) {
        _rate = rate;
        return true;
    }
    function _setTeamReward(uint256 teamReward) external onlyPoolRegistry returns (bool) {
        _teamReward = teamReward;
        return true;
    }
    function _setPoolValues(uint256 poolValueUSD,uint256 poolValue,string calldata proofOfValue) external onlyPoolRegistry returns (bool) {
        _poolValueUSD = poolValueUSD;
        _poolValue = poolValue;
        _proofOfValue = proofOfValue;
        return true;
    }
    function getPoolValues() public view returns(uint256 poolValueUSD,uint256 poolValue,string memory proofOfValue)
    {
        return (_poolValueUSD, _poolValue,_proofOfValue);
    }
    function _depositInvestmentInTokensToPool(address payable sender, uint256 amount, address token) external onlyPoolRegistry returns (bool) {
        require(hasRole(LIMITED_PARTNER_ROLE, sender), "InvestmentPool: the sender does not have permission");
        uint256 depositFee = amount.mul(_depositFixedFee).div(100);
        uint256 depositFeeReferrer = amount.mul(_referralDepositFee).div(100);
        uint256 totalDeposit = amount.sub(depositFee);
        if (_referrals[sender] != address(0)) {
            totalDeposit = totalDeposit.sub(depositFeeReferrer);
        }
        _deposites[sender].push(DepositToPool(totalDeposit,block.timestamp,_lockPeriod,false,0,token));
        return true;
    }
    function _deposit(address sender, uint256 amount, uint256 feesMultipier) private returns (bool) {
        require(_isPublicPool, "InvestmentPool: pool deposit blocked");
        address payable team = payable(getRoleMember(GENERAL_PARTNER_ROLE,0));
        uint256 depositFee = amount.mul(_depositFixedFee).div(feesMultipier).mul(multiplierDefault).div(100);
        uint256 totalDeposit = amount.sub(depositFee);
        team.transfer(depositFee);
        if (_referrals[sender] != address(0)) {
            uint256 depositFeeReferrer = amount.mul(_referralDepositFee).div(feesMultipier).mul(multiplierDefault).div(100);
            totalDeposit = totalDeposit.sub(depositFeeReferrer);
            payable(_referrals[sender]).transfer(depositFeeReferrer);
        }
        _deposites[sender].push(DepositToPool(totalDeposit,block.timestamp,_lockPeriod,false,0,address(0)));
        _totalInvestLpartner = _totalInvestLpartner.add(amount);
        emit Deposit(sender, amount);
        return true;
    }
    function _depositToken(address payable sender, uint256 amount) private returns (bool) {
        _assetsManageTeam._depositToken(address(this), sender, _token, amount);
        uint256 amountConverted = _getTokenAmount(amount);
        require(amountConverted <= address(this).balance, "InvestmentPool: contract balance is insufficient");
        sender.transfer(amountConverted);
        return true;
    }
    function _transferGeneralPartner(uint256 amount) private returns (bool) {
        address payable gPartner = payable(getMembersRole(GENERAL_PARTNER_ROLE)[0]);
        gPartner.transfer(amount);
        return true;
    }
    function _getTokenAmount(uint256 weiAmount) public view returns (uint256) {
        uint8 DECIMALS = IERC20(_token).decimals();
        return (weiAmount.mul(_rate)).div(10 ** uint256(DECIMALS));
    }
    function isContract(address _addr) private view returns (bool is_contract) {
        uint length;
        assembly {
            length := extcodesize(_addr)// retrieve the size of the code on target address, this needs assembly
        }
        return (length>0);
    }
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;

import "../utils/EnumerableSet.sol";
import "../GSN/Context.sol";

contract AccessControl is Context {
    using EnumerableSet for EnumerableSet.AddressSet;
    struct RoleData {
        EnumerableSet.AddressSet members;
        bytes32 adminRole;
    }
    mapping (bytes32 => RoleData) private _roles;
    mapping (bytes32 => address[]) private _addressesRoles;
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return _roles[role].members.length();
    }
   function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
        return _roles[role].members.at(index);
    }
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }
    function getMembersRole(bytes32 role) public view returns (address[] memory Accounts) {
        return _addressesRoles[role];
    }
    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to grant");
        _grantRole(role, account);
    }
    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to revoke");

        _revokeRole(role, account);
    }
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        _roles[role].adminRole = adminRole;
    }
    function _grantRole(bytes32 role, address account) private {
        if (_roles[role].members.add(account)) {
            _addressesRoles[role].push(account);
            emit RoleGranted(role, account, _msgSender());
        }
    }
    function _revokeRole(bytes32 role, address account) private {
        if (_roles[role].members.remove(account)) {
            for (uint256 i; i < _addressesRoles[role].length; i++) {
                if (_addressesRoles[role][i] == account) {
                    _removeIndexArray(i, _addressesRoles[role]);
                    break;
                }
            }
            emit RoleRevoked(role, account, _msgSender());
        }
    }
    function _removeIndexArray(uint256 index, address[] storage array) internal virtual {
        for(uint256 i = index; i < array.length-1; i++) {
            array[i] = array[i+1];
        }
        array.pop();
    }
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
import "./AccessControl.sol";
import "../ownership/Ownable.sol";
import "../interface/IRoleModel.sol";
contract PoolRoles is AccessControl, Ownable, IRoleModel {
    bool private _finalized = false;
    event Finalized();
    modifier onlyGPartner() {
        require(hasRole(GENERAL_PARTNER_ROLE, msg.sender), "Roles: caller does not have the general partner role");
        _;
    }
    modifier onlyLPartner() {
        require(hasRole(LIMITED_PARTNER_ROLE, msg.sender), "Roles: caller does not have the limited partner role");
        _;
    }
    modifier onlyStartupTeam() {
        require(hasRole(STARTUP_TEAM_ROLE, msg.sender), "Roles: caller does not have the team role");
        _;
    }
    modifier onlyPoolRegistry() {
        require(hasRole(POOL_REGISTRY, msg.sender), "Roles: caller does not have the pool regystry role");
        _;
    }
    modifier onlyReturnsInvestmentLpartner() {
        require(hasRole(RETURN_INVESTMENT_LPARTNER, msg.sender), "Roles: caller does not have the return invesment lpartner role");
        _;
    }
    modifier onlyOracle() {
        require(hasRole(ORACLE, msg.sender), "Roles: caller does not have oracle role");
        _;
    }
    constructor () public {
        _setRoleAdmin(GENERAL_PARTNER_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(LIMITED_PARTNER_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(STARTUP_TEAM_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(POOL_REGISTRY, SUPER_ADMIN_ROLE);
        _setRoleAdmin(RETURN_INVESTMENT_LPARTNER, SUPER_ADMIN_ROLE);
        _setRoleAdmin(ORACLE, SUPER_ADMIN_ROLE);
    }
    function addAdmin(bytes32 role, address account) public onlyOwner returns (bool) {
        require(!_finalized, "ManagerRole: already finalized");

        _setupRole(role, account);
        return true;
    }
    function finalize() public onlyOwner {
        require(!_finalized, "ManagerRole: already finalized");
        _finalized = true;
        emit Finalized();
    }
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
interface IAssetsManageTeam {
    function _depositToken(address pool, address team, address token, uint256 amount) external returns (bool);
    function _withdraw(address pool, address team, uint256 amount) external returns (bool);
    function _withdrawTokensToStartup(address pool,address token, address team, uint256 amount) external returns (bool);
    function _request(bool withdraw, address pool, address team, uint256 maxValue) external returns(bool);
    function _requestTokensWidthdrawalFromStartup(address pool, address token, address team, uint256 maxValue) external returns(bool);
    function _approve(address pool, address team, address owner) external returns(bool);
    function _approveTokensWidthdrawalFromStartup(address pool, address token, address team, address owner) external returns(bool);
    function _disapprove(address pool, address team, address owner) external returns(bool);
    function _lock(address pool, address team, address owner) external returns(bool);
    function _unlock(address pool, address team, address owner) external returns(bool);
    function addManager(address account) external;
    function getPerformedOperationsLength(address pool, address owner) external view returns(uint256 length);
    function getPerformedOperations(address pool, address owner, uint256 index) external view returns(address token, uint256 amountToken, uint256 withdraw, uint256 time);
    function getRequests(address pool) external view returns(address[] memory);
    function getApproval(address pool) external view returns(address[] memory);
    function getRequestTeamAddress(address pool, address team) external view returns(bool lock, uint256 maxValueToken, uint256 madeValueToken, uint256 maxValue, uint256 madeValue);
    function getApproveTeamAddress(address pool, address team) external view returns(bool lock, uint256 maxValueToken, uint256 madeValueToken, uint256 maxValue, uint256 madeValueE);
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
interface IOracle {
    function getLatestPrice() external view returns ( uint256,uint8);
    function getCustomPrice(address aggregator) external view returns (uint256,uint8);
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
import "./IOracle.sol";
interface IPoolRegistry {
    function isTeam(address account) external view returns (bool);
    function getTeamAddresses() external view returns (address[] memory);
    function getOracleContract() external view returns (IOracle);
    function feesMultipier(address sender) external view returns (uint256);
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
contract IRoleModel {
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant GENERAL_PARTNER_ROLE = keccak256("GENERAL_PARTNER_ROLE");
    bytes32 public constant LIMITED_PARTNER_ROLE = keccak256("LIMITED_PARTNER_ROLE");
    bytes32 public constant STARTUP_TEAM_ROLE = keccak256("STARTUP_TEAM_ROLE");
    bytes32 public constant POOL_REGISTRY = keccak256("POOL_REGISTRY");
    bytes32 public constant RETURN_INVESTMENT_LPARTNER = keccak256("RETURN_INVESTMENT_LPARTNER");
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant REFERER_ROLE = keccak256("REFERER_ROLE");
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
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
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
import "../GSN/Context.sol";
contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    constructor() internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }
    function owner() public view returns (address) {
        return _owner;
    }
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
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

// SPDX-License-Identifier: UNLICENSED
// (c) Oleksii Vynogradov 2021, All rights reserved, contact [email protected] if you like to use code
pragma solidity ^0.6.8;
library EnumerableSet {
    struct Set {
        bytes32[] _values;
        address[] _collection;
        mapping (bytes32 => uint256) _indexes;
    }
    function _add(Set storage set, bytes32 value, address addressValue) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            set._collection.push(addressValue);
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        uint256 valueIndex = set._indexes[value];
        if (valueIndex != 0) { // Equivalent to contains(set, value)
            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;
            bytes32 lastValue = set._values[lastIndex];
            set._values[toDeleteIndex] = lastValue;
            set._values.pop();

            address lastvalueAddress = set._collection[lastIndex];
            set._collection[toDeleteIndex] = lastvalueAddress;
            set._collection.pop();

            set._indexes[lastValue] = toDeleteIndex + 1; // All indexes are 1-based
            delete set._indexes[value];
//            for(uint256 i = 0; i < set._collection.length; i++) {
//                if (set._collection[i] == addressValue) {
//                    _removeIndexArray(i, set._collection);
//                    break;
//                }
//            }
            return true;
        } else {
            return false;
        }
    }
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }
    function _collection(Set storage set) private view returns (address[] memory) {
        return set._collection;    
    }
//    function _removeIndexArray(uint256 index, address[] storage array) internal virtual {
//        for(uint256 i = index; i < array.length-1; i++) {
//            array[i] = array[i+1];
//        }
//        array.pop();
//    }
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }
    struct AddressSet {
        Set _inner;
    }
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(value)), value);
    }
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(value)));
    }
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(value)));
    }
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }
    function collection(AddressSet storage set) internal view returns (address[] memory) {
        return _collection(set._inner);
    }
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint256(_at(set._inner, index)));
    }
}

