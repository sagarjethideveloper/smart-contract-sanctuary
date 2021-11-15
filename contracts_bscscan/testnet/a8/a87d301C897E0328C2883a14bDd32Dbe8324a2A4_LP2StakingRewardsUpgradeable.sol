pragma solidity ^0.6.5;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IRandoms.sol";
import "./shields.sol";
import "./Consumables.sol";
import "./weapons.sol";
import "./cryptoblades.sol";

contract Blacksmith is Initializable, AccessControlUpgradeable {
    /* ========== CONSTANTS ========== */

    bytes32 public constant GAME = keccak256("GAME");

    uint256 public constant SHIELD_SKILL_FEE = 3 ether;

    uint256 public constant ITEM_WEAPON_RENAME = 1;
    uint256 public constant ITEM_CHARACTER_RENAME = 2;
    uint256 public constant ITEM_CHARACTER_TRAITCHANGE_FIRE = 3;
    uint256 public constant ITEM_CHARACTER_TRAITCHANGE_EARTH = 4;
    uint256 public constant ITEM_CHARACTER_TRAITCHANGE_WATER = 5;
    uint256 public constant ITEM_CHARACTER_TRAITCHANGE_LIGHTNING = 6;

    /* ========== STATE VARIABLES ========== */

    Weapons public weapons;
    IRandoms public randoms;

    mapping(address => uint32) public tickets;

    Shields public shields;
    CryptoBlades public game;

    // keys: ITEM_ constant
    mapping(uint256 => address) public itemAddresses;
    mapping(uint256 => uint256) public itemFlatPrices;

    /* ========== INITIALIZERS AND MIGRATORS ========== */

    function initialize(Weapons _weapons, IRandoms _randoms)
        public
        initializer
    {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        weapons = _weapons;
        randoms = _randoms;
    }

    function migrateRandoms(IRandoms _newRandoms) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        randoms = _newRandoms;
    }

    function migrateTo_61c10da(Shields _shields, CryptoBlades _game) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        shields = _shields;
        game = _game;
    }

    function migrateTo_16884dd(
        address _characterRename,
        address _weaponRename,
        address _charFireTraitChange,
        address _charEarthTraitChange,
        address _charWaterTraitChange,
        address _charLightningTraitChange
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        itemAddresses[ITEM_WEAPON_RENAME] = _weaponRename;
        itemAddresses[ITEM_CHARACTER_RENAME] = _characterRename;
        itemAddresses[ITEM_CHARACTER_TRAITCHANGE_FIRE] = _charFireTraitChange;
        itemAddresses[ITEM_CHARACTER_TRAITCHANGE_EARTH] = _charEarthTraitChange;
        itemAddresses[ITEM_CHARACTER_TRAITCHANGE_WATER] = _charWaterTraitChange;
        itemAddresses[ITEM_CHARACTER_TRAITCHANGE_LIGHTNING] = _charLightningTraitChange;

        itemFlatPrices[ITEM_WEAPON_RENAME] = 0.1 ether;
        itemFlatPrices[ITEM_CHARACTER_RENAME] = 0.1 ether;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_FIRE] = 0.2 ether;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_EARTH] = 0.2 ether;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_WATER] = 0.2 ether;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_LIGHTNING] = 0.2 ether;
    }

    /* ========== VIEWS ========== */

    /* ========== MUTATIVE FUNCTIONS ========== */

    // function spendTicket(uint32 _num) external {
    //     require(_num > 0);
    //     require(tickets[msg.sender] >= _num, "Not enough tickets");
    //     tickets[msg.sender] -= _num;

    //     for (uint256 i = 0; i < _num; i++) {
    //         weapons.mint(
    //             msg.sender,
    //             // TODO: Do the thing we do in cryptoblades.sol to "lock in" the user into a given blockhash
    //         );
    //     }
    // }

    function giveTicket(address _player, uint32 _num) external onlyGame {
        tickets[_player] += _num;
    }

    function purchaseShield() public {
        Promos promos = game.promos();
        uint256 BIT_LEGENDARY_DEFENDER = promos.BIT_LEGENDARY_DEFENDER();

        require(!promos.getBit(msg.sender, BIT_LEGENDARY_DEFENDER), "Limit 1");
        promos.setBit(msg.sender, BIT_LEGENDARY_DEFENDER);
        game.payContractTokenOnly(msg.sender, SHIELD_SKILL_FEE);
        shields.mintForPurchase(msg.sender);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyGame() {
        require(hasRole(GAME, msg.sender), "Only game");
        _;
    }

     modifier isAdmin() {
         require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    /* ========== Generic Getters ========== */

    function getAddressOfItem(uint256 itemIndex) public view returns(address) {
        return itemAddresses[itemIndex];
    }

    function getFlatPriceOfItem(uint256 itemIndex) public view returns(uint256) {
        return itemFlatPrices[itemIndex];
    }

    /* ========== Character Rename ========== */
    
    function setCharacterRenamePrice(uint256 newPrice) external isAdmin {
        require(newPrice > 0, 'invalid price');
        itemFlatPrices[ITEM_CHARACTER_RENAME] = newPrice;
    }

    function characterRenamePrice() public view returns (uint256){
        return itemFlatPrices[ITEM_CHARACTER_RENAME];
    }

    function purchaseCharacterRenameTag(uint256 paying) public {
        require(paying == itemFlatPrices[ITEM_CHARACTER_RENAME], 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_CHARACTER_RENAME]);
        Consumables(itemAddresses[ITEM_CHARACTER_RENAME]).giveItem(msg.sender, 1);
    }
    
    function purchaseCharacterRenameTagDeal(uint256 paying) public { // 4 for the price of 3
        require(paying == itemFlatPrices[ITEM_CHARACTER_RENAME] * 3, 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_CHARACTER_RENAME] * 3);
        Consumables(itemAddresses[ITEM_CHARACTER_RENAME]).giveItem(msg.sender, 4);
    }
    
    /* ========== Weapon Rename ========== */

    function setWeaponRenamePrice(uint256 newPrice) external isAdmin {
        require(newPrice > 0, 'invalid price');
        itemFlatPrices[ITEM_WEAPON_RENAME] = newPrice;
    }

    function weaponRenamePrice() public view returns (uint256){
        return itemFlatPrices[ITEM_WEAPON_RENAME];
    }

    function purchaseWeaponRenameTag(uint256 paying) public {
        require(paying == itemFlatPrices[ITEM_WEAPON_RENAME], 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_WEAPON_RENAME]);
        Consumables(itemAddresses[ITEM_WEAPON_RENAME]).giveItem(msg.sender, 1);
    }

    function purchaseWeaponRenameTagDeal(uint256 paying) public { // 4 for the price of 3
        require(paying == itemFlatPrices[ITEM_WEAPON_RENAME] * 3, 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_WEAPON_RENAME] * 3);
        Consumables(itemAddresses[ITEM_WEAPON_RENAME]).giveItem(msg.sender, 4);
    }

     /* ========== Character Trait Change ========== */

     function setCharacterTraitChangePrice(uint256 newPrice) external isAdmin {
        require(newPrice > 0, 'invalid price');
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_FIRE] = newPrice;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_EARTH] = newPrice;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_WATER] = newPrice;
        itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_LIGHTNING] = newPrice;
    }

     function characterTraitChangePrice() public view returns (uint256){
        return itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_FIRE];
    }

    function purchaseCharacterFireTraitChange(uint256 paying) public {
        require(paying == itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_FIRE], 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_FIRE]);
        Consumables(itemAddresses[ITEM_CHARACTER_TRAITCHANGE_FIRE]).giveItem(msg.sender, 1);
    }

    function purchaseCharacterEarthTraitChange(uint256 paying) public {
        require(paying == itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_EARTH], 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_EARTH]);
        Consumables(itemAddresses[ITEM_CHARACTER_TRAITCHANGE_EARTH]).giveItem(msg.sender, 1);
    }

    function purchaseCharacterWaterTraitChange(uint256 paying) public {
        require(paying == itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_WATER], 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_WATER]);
        Consumables(itemAddresses[ITEM_CHARACTER_TRAITCHANGE_WATER]).giveItem(msg.sender, 1);
    }

    function purchaseCharacterLightningTraitChange(uint256 paying) public {
        require(paying == itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_LIGHTNING], 'Invalid price');
        game.payContractTokenOnly(msg.sender, itemFlatPrices[ITEM_CHARACTER_TRAITCHANGE_LIGHTNING]);
        Consumables(itemAddresses[ITEM_CHARACTER_TRAITCHANGE_LIGHTNING]).giveItem(msg.sender, 1);
    }
}

pragma solidity ^0.6.5;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";


contract Consumables is Initializable, AccessControlUpgradeable {

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    event ConsumableGiven(address indexed owner, uint32 amount);

    mapping(address => uint32) public owned;
    
    bool internal _enabled;

    function initialize()
        public
        initializer
    {
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _enabled = true;
    }

    modifier isAdmin() {
         require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier itemNotDisabled() {
         require(_enabled, "Item disabled");
        _;
    }

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier haveItem(uint32 amount) {
        require(owned[msg.sender] >= amount, "No item");
        _;
    }

    function giveItem(address buyer, uint32 amount) public restricted {
        owned[buyer] += amount;
        emit ConsumableGiven(buyer, amount);
    }

    function consumeItem(uint32 amount) internal haveItem(amount) itemNotDisabled {
        owned[msg.sender] -= amount;
    }

    function getItemCount() public view returns (uint32) {
        return owned[msg.sender];
    }

    function toggleItemCanUse(bool canUse) external isAdmin {
        _enabled = canUse;
    }

    function giveItemByAdmin(address receiver, uint32 amount) external isAdmin {
        owned[receiver] += amount;
    }

    function takeItemByAdmin(address target, uint32 amount) external isAdmin {
        require(owned[target] >= amount, 'Not enough item');
        owned[target] -= amount;
    }

    function itemEnabled() public view returns (bool){
        return _enabled;
    }
}

pragma solidity ^0.6.2;

import "./staking/StakingRewardsUpgradeable.sol";

contract LP2StakingRewardsUpgradeable is StakingRewardsUpgradeable {
}

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";

contract Promos is Initializable, AccessControlUpgradeable {
    using ABDKMath64x64 for int128;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    function initialize() public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function migrateTo_f73df27() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        firstCharacterPromoInGameOnlyFundsGivenInUsd = ABDKMath64x64.divu(
            17220,
            100
        );
    }

    mapping(address => uint256) public bits;
    uint256 public constant BIT_FIRST_CHARACTER = 1;
    uint256 public constant BIT_FOUNDER_SHIELD = 2;
    uint256 public constant BIT_BAD_ACTOR = 4;
    uint256 public constant BIT_LEGENDARY_DEFENDER = 8;

    int128 public firstCharacterPromoInGameOnlyFundsGivenInUsd;

    modifier restricted() {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
        _;
    }

    function setBit(address user, uint256 bit) external restricted {
        bits[user] |= bit;
    }

    function setBits(address[] memory user, uint256 bit) public restricted {
        for(uint i = 0; i < user.length; i++)
            bits[user[i]] |= bit;
    }

    function unsetBit(address user, uint256 bit) public restricted {
        bits[user] &= ~bit;
    }

    function unsetBits(address[] memory user, uint256 bit) public restricted {
        for(uint i = 0; i < user.length; i++)
            bits[user[i]] &= ~bit;
    }

    function getBit(address user, uint256 bit) external view returns (bool) {
        return (bits[user] & bit) == bit;
    }

    function firstCharacterPromoInGameOnlyFundsGivenInUsdAsCents() external view returns (uint256) {
        return firstCharacterPromoInGameOnlyFundsGivenInUsd.mulu(100);
    }

    function setFirstCharacterPromoInGameOnlyFundsGivenInUsdAsCents(
        uint256 _usdCents
    ) external restricted {
        firstCharacterPromoInGameOnlyFundsGivenInUsd = ABDKMath64x64.divu(
            _usdCents,
            100
        );
    }

    function setFirstCharacterPromoInGameOnlyFundsGivenInUsdAsRational(
        uint256 _numerator,
        uint256 _denominator
    ) external restricted {
        firstCharacterPromoInGameOnlyFundsGivenInUsd = ABDKMath64x64.divu(
            _numerator,
            _denominator
        );
    }
}

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Promos.sol";
import "./util.sol";
import "./interfaces/ITransferCooldownable.sol";

contract Characters is Initializable, ERC721Upgradeable, AccessControlUpgradeable, ITransferCooldownable {

    using SafeMath for uint16;
    using SafeMath for uint8;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");
    bytes32 public constant NO_OWNED_LIMIT = keccak256("NO_OWNED_LIMIT");
    bytes32 public constant RECEIVE_DOES_NOT_SET_TRANSFER_TIMESTAMP = keccak256("RECEIVE_DOES_NOT_SET_TRANSFER_TIMESTAMP");

    uint256 public constant TRANSFER_COOLDOWN = 1 days;

    function initialize () public initializer {
        __ERC721_init("CryptoBlades character", "CBC");
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function migrateTo_1ee400a() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        experienceTable = [
            16, 17, 18, 19, 20, 22, 24, 26, 28, 30, 33, 36, 39, 42, 46, 50, 55, 60, 66
            , 72, 79, 86, 94, 103, 113, 124, 136, 149, 163, 178, 194, 211, 229, 248, 268
            , 289, 311, 334, 358, 383, 409, 436, 464, 493, 523, 554, 586, 619, 653, 688
            , 724, 761, 799, 838, 878, 919, 961, 1004, 1048, 1093, 1139, 1186, 1234, 1283
            , 1333, 1384, 1436, 1489, 1543, 1598, 1654, 1711, 1769, 1828, 1888, 1949, 2011
            , 2074, 2138, 2203, 2269, 2336, 2404, 2473, 2543, 2614, 2686, 2759, 2833, 2908
            , 2984, 3061, 3139, 3218, 3298, 3379, 3461, 3544, 3628, 3713, 3799, 3886, 3974
            , 4063, 4153, 4244, 4336, 4429, 4523, 4618, 4714, 4811, 4909, 5008, 5108, 5209
            , 5311, 5414, 5518, 5623, 5729, 5836, 5944, 6053, 6163, 6274, 6386, 6499, 6613
            , 6728, 6844, 6961, 7079, 7198, 7318, 7439, 7561, 7684, 7808, 7933, 8059, 8186
            , 8314, 8443, 8573, 8704, 8836, 8969, 9103, 9238, 9374, 9511, 9649, 9788, 9928
            , 10069, 10211, 10354, 10498, 10643, 10789, 10936, 11084, 11233, 11383, 11534
            , 11686, 11839, 11993, 12148, 12304, 12461, 12619, 12778, 12938, 13099, 13261
            , 13424, 13588, 13753, 13919, 14086, 14254, 14423, 14593, 14764, 14936, 15109
            , 15283, 15458, 15634, 15811, 15989, 16168, 16348, 16529, 16711, 16894, 17078
            , 17263, 17449, 17636, 17824, 18013, 18203, 18394, 18586, 18779, 18973, 19168
            , 19364, 19561, 19759, 19958, 20158, 20359, 20561, 20764, 20968, 21173, 21379
            , 21586, 21794, 22003, 22213, 22424, 22636, 22849, 23063, 23278, 23494, 23711
            , 23929, 24148, 24368, 24589, 24811, 25034, 25258, 25483, 25709, 25936, 26164
            , 26393, 26623, 26854, 27086, 27319, 27553, 27788, 28024, 28261, 28499, 28738
            , 28978
        ];
    }

    function migrateTo_951a020() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        _registerInterface(TransferCooldownableInterfaceId.interfaceId());
    }

    function migrateTo_ef994e2(Promos _promos) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        promos = _promos;
    }

    function migrateTo_b627f23() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        characterLimit = 4;
    }

    /*
        visual numbers start at 0, increment values by 1
        levels: 1-256
        traits: 0-3 [0(fire) > 1(earth) > 2(lightning) > 3(water) > repeat]
    */

    struct Character {
        uint16 xp; // xp to next level
        uint8 level; // up to 256 cap
        uint8 trait; // 2b trait, TBD
        uint64 staminaTimestamp; // standard timestamp in seconds-resolution marking regen start from 0
    }
    struct CharacterCosmetics {
        uint8 version;
        uint256 seed;
    }

    Character[] private tokens;
    CharacterCosmetics[] private cosmetics;

    uint256 public constant maxStamina = 200;
    uint256 public constant secondsPerStamina = 300; //5 * 60

    uint256[256] private experienceTable; // fastest lookup in the west

    mapping(uint256 => uint256) public override lastTransferTimestamp;

    Promos public promos;

    uint256 private lastMintedBlock;
    uint256 private firstMintedOfLastBlock;

    uint256 public characterLimit;

    event NewCharacter(uint256 indexed character, address indexed minter);
    event LevelUp(address indexed owner, uint256 indexed character, uint16 level);

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier noFreshLookup(uint256 id) {
        _noFreshLookup(id);
        _;
    }

    function _noFreshLookup(uint256 id) internal view {
        require(id < firstMintedOfLastBlock || lastMintedBlock < block.number, "Too fresh for lookup");
    }

    function transferCooldownEnd(uint256 tokenId) public override view returns (uint256) {
        return lastTransferTimestamp[tokenId].add(TRANSFER_COOLDOWN);
    }

    function transferCooldownLeft(uint256 tokenId) public override view returns (uint256) {
        (bool success, uint256 secondsLeft) =
            lastTransferTimestamp[tokenId].trySub(
                block.timestamp.sub(TRANSFER_COOLDOWN)
            );

        return success ? secondsLeft : 0;
    }

    function get(uint256 id) public view noFreshLookup(id) returns (uint16, uint8, uint8, uint64, uint16, uint16, uint16, uint16, uint16, uint16) {
        Character memory c = tokens[id];
        CharacterCosmetics memory cc = cosmetics[id];
        return (c.xp, c.level, c.trait, c.staminaTimestamp,
            getRandomCosmetic(cc.seed, 1, 13), // head
            getRandomCosmetic(cc.seed, 2, 45), // arms
            getRandomCosmetic(cc.seed, 3, 61), // torso
            getRandomCosmetic(cc.seed, 4, 41), // legs
            getRandomCosmetic(cc.seed, 5, 22), // boots
            getRandomCosmetic(cc.seed, 6, 2) // race
        );
    }

    function getRandomCosmetic(uint256 seed, uint256 seed2, uint16 limit) private pure returns (uint16) {
        return uint16(RandomUtil.randomSeededMinMax(0, limit, RandomUtil.combineSeeds(seed, seed2)));
    }

    function mint(address minter, uint256 seed) public restricted {
        uint256 tokenID = tokens.length;

        if(block.number != lastMintedBlock)
            firstMintedOfLastBlock = tokenID;
        lastMintedBlock = block.number;

        uint16 xp = 0;
        uint8 level = 0; // 1
        uint8 trait = uint8(RandomUtil.randomSeededMinMax(0,3,seed));
        uint64 staminaTimestamp = uint64(now.sub(getStaminaMaxWait()));

        tokens.push(Character(xp, level, trait, staminaTimestamp));
        cosmetics.push(CharacterCosmetics(0, RandomUtil.combineSeeds(seed, 1)));
        _mint(minter, tokenID);
        emit NewCharacter(tokenID, minter);
    }

    function getLevel(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return tokens[id].level; // this is used by dataminers and it benefits us
    }

    function getRequiredXpForNextLevel(uint8 currentLevel) public view returns (uint16) {
        return uint16(experienceTable[currentLevel]); // this is helpful to users as the array is private
    }

    function getPower(uint256 id) public view noFreshLookup(id) returns (uint24) {
        return getPowerAtLevel(tokens[id].level);
    }

    function getPowerAtLevel(uint8 level) public pure returns (uint24) {
        // does not use fixed points since the numbers are simple
        // the breakpoints every 10 levels are floored as expected
        // level starts at 0 (visually 1)
        // 1000 at lvl 1
        // 9000 at lvl 51 (~3months)
        // 22440 at lvl 105 (~3 years)
        // 92300 at lvl 255 (heat death of the universe)
        return uint24(
            uint256(1000)
                .add(level.mul(10))
                .mul(level.div(10).add(1))
        );
    }

    function getTrait(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return tokens[id].trait;
    }

    function setTrait(uint256 id, uint8 trait) public restricted {
        tokens[id].trait = trait;
    }

    function getXp(uint256 id) public view noFreshLookup(id) returns (uint32) {
        return tokens[id].xp;
    }

    function gainXp(uint256 id, uint16 xp) public restricted {
        Character storage char = tokens[id];
        if(char.level < 255) {
            uint newXp = char.xp.add(xp);
            uint requiredToLevel = experienceTable[char.level]; // technically next level
            while(newXp >= requiredToLevel) {
                newXp = newXp - requiredToLevel;
                char.level += 1;
                emit LevelUp(ownerOf(id), id, char.level);
                if(char.level < 255)
                    requiredToLevel = experienceTable[char.level];
                else
                    newXp = 0;
            }
            char.xp = uint16(newXp);
        }
    }

    function getStaminaTimestamp(uint256 id) public view noFreshLookup(id) returns (uint64) {
        return tokens[id].staminaTimestamp;
    }

    function setStaminaTimestamp(uint256 id, uint64 timestamp) public restricted {
        tokens[id].staminaTimestamp = timestamp;
    }

    function getStaminaPoints(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getStaminaPointsFromTimestamp(tokens[id].staminaTimestamp);
    }

    function getStaminaPointsFromTimestamp(uint64 timestamp) public view returns (uint8) {
        if(timestamp  > now)
            return 0;

        uint256 points = (now - timestamp) / secondsPerStamina;
        if(points > maxStamina) {
            points = maxStamina;
        }
        return uint8(points);
    }

    function isStaminaFull(uint256 id) public view noFreshLookup(id) returns (bool) {
        return getStaminaPoints(id) >= maxStamina;
    }

    function getStaminaMaxWait() public pure returns (uint64) {
        return uint64(maxStamina * secondsPerStamina);
    }

    function getFightDataAndDrainStamina(uint256 id, uint8 amount) public restricted returns(uint96) {
        Character storage char = tokens[id];
        uint8 staminaPoints = getStaminaPointsFromTimestamp(char.staminaTimestamp);
        require(staminaPoints >= amount, "Not enough stamina!");

        uint64 drainTime = uint64(amount * secondsPerStamina);
        uint64 preTimestamp = char.staminaTimestamp;
        if(staminaPoints >= maxStamina) { // if stamina full, we reset timestamp and drain from that
            char.staminaTimestamp = uint64(now - getStaminaMaxWait() + drainTime);
        }
        else {
            char.staminaTimestamp = uint64(char.staminaTimestamp + drainTime);
        }
        // bitwise magic to avoid stacking limitations later on
        return uint96(char.trait | (getPowerAtLevel(char.level) << 8) | (preTimestamp << 32));
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        if(to != address(0) && to != address(0x000000000000000000000000000000000000dEaD) && !hasRole(NO_OWNED_LIMIT, to)) {
            require(balanceOf(to) < characterLimit, "Recv has too many characters");
        }

        // when not minting or burning...
        if(from != address(0) && to != address(0)) {
            // only allow transferring a particular token every TRANSFER_COOLDOWN seconds
            require(lastTransferTimestamp[tokenId] < block.timestamp.sub(TRANSFER_COOLDOWN), "Transfer cooldown");

            if(!hasRole(RECEIVE_DOES_NOT_SET_TRANSFER_TIMESTAMP, to)) {
                lastTransferTimestamp[tokenId] = block.timestamp;
            }
        }

        promos.setBit(from, promos.BIT_FIRST_CHARACTER());
        promos.setBit(to, promos.BIT_FIRST_CHARACTER());
    }

    function setCharacterLimit(uint256 max) public restricted {
        characterLimit = max;
    }
}

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IStakeFromGame.sol";
import "./interfaces/IRandoms.sol";
import "./interfaces/IPriceOracle.sol";
import "./characters.sol";
import "./Promos.sol";
import "./weapons.sol";
import "./util.sol";
import "./Blacksmith.sol";

contract CryptoBlades is Initializable, AccessControlUpgradeable {
    using ABDKMath64x64 for int128;
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    // Payment must be recent enough that the hash is available for the payment block.
    // Use 200 as a 'friendly' window of "You have 10 minutes."
    uint256 public constant MINT_PAYMENT_TIMEOUT = 200;
    uint256 public constant MINT_PAYMENT_RECLAIM_MINIMUM_WAIT_TIME = 3 hours;

    int128 public constant REWARDS_CLAIM_TAX_MAX = 2767011611056432742; // = ~0.15 = ~15%
    uint256 public constant REWARDS_CLAIM_TAX_DURATION = 15 days;

    Characters public characters;
    Weapons public weapons;
    IERC20 public skillToken;//0x154A9F9cbd3449AD22FDaE23044319D6eF2a1Fab;
    IPriceOracle public priceOracleSkillPerUsd;
    IRandoms public randoms;

    function initialize(IERC20 _skillToken, Characters _characters, Weapons _weapons, IPriceOracle _priceOracleSkillPerUsd, IRandoms _randoms) public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GAME_ADMIN, msg.sender);

        skillToken = _skillToken;
        characters = _characters;
        weapons = _weapons;
        priceOracleSkillPerUsd = _priceOracleSkillPerUsd;
        randoms = _randoms;

        staminaCostFight = 40;
        mintCharacterFee = ABDKMath64x64.divu(10, 1);//10 usd;
        mintWeaponFee = ABDKMath64x64.divu(3, 1);//3 usd;

        // migrateTo_1ee400a
        fightXpGain = 32;

        // migrateTo_aa9da90
        oneFrac = ABDKMath64x64.fromUInt(1);
        fightTraitBonus = ABDKMath64x64.divu(75, 1000);

        // migrateTo_7dd2a56
        // numbers given for the curves were $4.3-aligned so they need to be multiplied
        // additional accuracy may be in order for the setter functions for these
        fightRewardGasOffset = ABDKMath64x64.divu(23177, 100000); // 0.0539 x 4.3
        fightRewardBaseline = ABDKMath64x64.divu(344, 1000); // 0.08 x 4.3

        // migrateTo_5e833b0
        durabilityCostFight = 1;
    }

    function migrateTo_ef994e2(Promos _promos) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));

        promos = _promos;
    }

    function migrateTo_23b3a8b(IStakeFromGame _stakeFromGame) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));

        stakeFromGameImpl = _stakeFromGame;
    }

    function migrateTo_801f279() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));

        burnWeaponFee = ABDKMath64x64.divu(2, 10);//0.2 usd;
        reforgeWeaponWithDustFee = ABDKMath64x64.divu(3, 10);//0.3 usd;

        reforgeWeaponFee = burnWeaponFee + reforgeWeaponWithDustFee;//0.5 usd;
    }

    function migrateTo_60872c8(Blacksmith _blacksmith) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));

        blacksmith = _blacksmith;
    }

    // UNUSED; KEPT FOR UPGRADEABILITY PROXY COMPATIBILITY
    uint characterLimit;
    // config vars
    uint8 staminaCostFight;

    // prices & payouts are in USD, with 4 decimals of accuracy in 64.64 fixed point format
    int128 public mintCharacterFee;
    //int128 public rerollTraitFee;
    //int128 public rerollCosmeticsFee;
    int128 public refillStaminaFee;
    // lvl 1 player power could be anywhere between ~909 to 1666
    // cents per fight multiplied by monster power divided by 1000 (lv1 power)
    int128 public fightRewardBaseline;
    int128 public fightRewardGasOffset;

    int128 public mintWeaponFee;
    int128 public reforgeWeaponFee;

    uint256 nonce;

    mapping(address => uint256) lastBlockNumberCalled;

    uint256 public fightXpGain; // multiplied based on power differences

    mapping(address => uint256) tokenRewards; // user adress : skill wei
    mapping(uint256 => uint256) xpRewards; // character id : xp

    int128 public oneFrac; // 1.0
    int128 public fightTraitBonus; // 7.5%

    mapping(address => uint256) public inGameOnlyFunds;
    uint256 public totalInGameOnlyFunds;

    Promos public promos;

    mapping(address => uint256) private _rewardsClaimTaxTimerStart;

    IStakeFromGame public stakeFromGameImpl;

    uint8 durabilityCostFight;

    int128 public burnWeaponFee;
    int128 public reforgeWeaponWithDustFee;

    Blacksmith public blacksmith;

    struct MintPayment {
        bytes32 blockHash;
        uint256 blockNumber;
        address nftAddress;
        uint count;
    }

    mapping(address => MintPayment) mintPayments;

    struct MintPaymentSkillDeposited {
        uint256 skillDepositedFromWallet;
        uint256 skillDepositedFromRewards;
        uint256 skillDepositedFromIgo;

        uint256 skillRefundableFromWallet;
        uint256 skillRefundableFromRewards;
        uint256 skillRefundableFromIgo;

        uint256 refundClaimableTimestamp;
    }

    uint256 public totalMintPaymentSkillRefundable;
    mapping(address => MintPaymentSkillDeposited) mintPaymentSkillDepositeds;

    event FightOutcome(address indexed owner, uint256 indexed character, uint256 weapon, uint32 target, uint24 playerRoll, uint24 enemyRoll, uint16 xpGain, uint256 skillGain);
    event InGameOnlyFundsGiven(address indexed to, uint256 skillAmount);
    event MintWeaponsSuccess(address indexed minter, uint32 count);
    event MintWeaponsFailure(address indexed minter, uint32 count);

    function recoverSkill(uint256 amount) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        skillToken.safeTransfer(msg.sender, amount);
    }

    function getSkillToSubtract(uint256 _inGameOnlyFunds, uint256 _tokenRewards, uint256 _skillNeeded)
        public
        pure
        returns (uint256 fromInGameOnlyFunds, uint256 fromTokenRewards, uint256 fromUserWallet) {

        if(_skillNeeded <= _inGameOnlyFunds) {
            return (_skillNeeded, 0, 0);
        }

        _skillNeeded -= _inGameOnlyFunds;

        if(_skillNeeded <= _tokenRewards) {
            return (_inGameOnlyFunds, _skillNeeded, 0);
        }

        _skillNeeded -= _tokenRewards;

        return (_inGameOnlyFunds, _tokenRewards, _skillNeeded);
    }

    function getSkillNeededFromUserWallet(address playerAddress, uint256 skillNeeded)
        public
        view
        returns (uint256 skillNeededFromUserWallet) {

        (,, skillNeededFromUserWallet) = getSkillToSubtract(
            inGameOnlyFunds[playerAddress],
            tokenRewards[playerAddress],
            skillNeeded
        );
    }

    function getMyCharacters() public view returns(uint256[] memory) {
        uint256[] memory tokens = new uint256[](characters.balanceOf(msg.sender));
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = characters.tokenOfOwnerByIndex(msg.sender, i);
        }
        return tokens;
    }

    function getMyWeapons() public view returns(uint256[] memory) {
        uint256[] memory tokens = new uint256[](weapons.balanceOf(msg.sender));
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = weapons.tokenOfOwnerByIndex(msg.sender, i);
        }
        return tokens;
    }

    function unpackFightData(uint96 playerData)
        public pure returns (uint8 charTrait, uint24 basePowerLevel, uint64 timestamp) {

        charTrait = uint8(playerData & 0xFF);
        basePowerLevel = uint24((playerData >> 8) & 0xFFFFFF);
        timestamp = uint64((playerData >> 32) & 0xFFFFFFFFFFFFFFFF);
    }

    function fight(uint256 char, uint256 wep, uint32 target, uint8 fightMultiplier) external
            // These have been combined due to error: CompilerError: Stack too deep, try removing local variables. TODO
            // onlyNonContract
            // isCharacterOwner(char)
            // isWeaponOwner(wep) {
        fightModifierChecks(char, wep) {
        require(fightMultiplier >= 1 && fightMultiplier <= 5);

        (uint8 charTrait, uint24 basePowerLevel, uint64 timestamp) =
            unpackFightData(characters.getFightDataAndDrainStamina(char, staminaCostFight * fightMultiplier));

        (int128 weaponMultTarget,
            int128 weaponMultFight,
            uint24 weaponBonusPower,
            uint8 weaponTrait) = weapons.getFightDataAndDrainDurability(wep, charTrait,
                durabilityCostFight * fightMultiplier);

        _verifyFight(
            basePowerLevel,
            weaponMultTarget,
            weaponBonusPower,
            timestamp,
            target
        );
        performFight(
            char,
            wep,
            getPlayerPower(basePowerLevel, weaponMultFight, weaponBonusPower),
            uint24(charTrait | (uint24(weaponTrait) << 8) | (target & 0xFF000000) >> 8),
            uint24(target & 0xFFFFFF),
            fightMultiplier
        );
    }

    function _verifyFight(
        uint24 basePowerLevel,
        int128 weaponMultTarget,
        uint24 weaponBonusPower,
        uint64 timestamp,
        uint32 target
    ) internal view {
        verifyFight(
            basePowerLevel,
            weaponMultTarget,
            weaponBonusPower,
            timestamp,
            now.div(1 hours),
            target
        );
    }

    function verifyFight(
        uint24 playerBasePower,
        int128 wepMultiplier,
        uint24 wepBonusPower,
        uint64 staminaTimestamp,
        uint256 hour,
        uint32 target
    ) public pure {

        uint32[4] memory targets = getTargetsInternal(
            getPlayerPower(playerBasePower, wepMultiplier, wepBonusPower),
            staminaTimestamp,
            hour
        );
        bool foundMatch = false;
        for(uint i = 0; i < targets.length; i++) {
            if(targets[i] == target) {
                foundMatch = true;
                i = targets.length;
            }
        }
        require(foundMatch, "Target invalid");
    }

    function isUnlikely(uint24 pp, uint24 ep)
        private
        pure
        returns(bool)
    {
        int128 playerMin = ABDKMath64x64.fromUInt(pp).mul(ABDKMath64x64.fromUInt(90)).div(ABDKMath64x64.fromUInt(100));
        int128 playerMax = ABDKMath64x64.fromUInt(pp).mul(ABDKMath64x64.fromUInt(110)).div(ABDKMath64x64.fromUInt(100));
        int128 playerRange = playerMax.sub(playerMin);
        int128 enemyMin = ABDKMath64x64.fromUInt(ep).mul(ABDKMath64x64.fromUInt(90)).div(ABDKMath64x64.fromUInt(100));
        int128 enemyMax = ABDKMath64x64.fromUInt(ep).mul(ABDKMath64x64.fromUInt(110)).div(ABDKMath64x64.fromUInt(100));
        int128 enemyRange = enemyMax.sub(enemyMin);
        int256 rollingTotal = 0;

        if (playerMin > enemyMax) return false;
        if (playerMax < enemyMin) return true;

        if (playerMin >= enemyMin) {
            int128 temp = playerMin.sub(enemyMin).div(enemyRange);
            temp = temp.add(ABDKMath64x64.fromUInt(1).sub(temp).mul(playerMax.sub(enemyMax).div(playerRange)));
            temp = temp.add(ABDKMath64x64.fromUInt(1).sub(temp).mul(ABDKMath64x64.fromUInt(50).div(ABDKMath64x64.fromUInt(100))));
            rollingTotal = ABDKMath64x64.toInt(temp.mul(ABDKMath64x64.fromUInt(1000)));
        } else {
            int128 temp = enemyMin.sub(playerMin).div(playerRange);
            temp = temp.add(ABDKMath64x64.fromUInt(1).sub(temp).mul(enemyMax.sub(playerMax).div(enemyRange)));
            temp = temp.add(ABDKMath64x64.fromUInt(1).sub(temp).mul(ABDKMath64x64.fromUInt(50).div(ABDKMath64x64.fromUInt(100))));
            temp = ABDKMath64x64.fromUInt(1).sub(temp);
            rollingTotal = ABDKMath64x64.toInt(temp.mul(ABDKMath64x64.fromUInt(1000)));
        }

        return rollingTotal <= 300 ? true : false;
    }

    function performFight(
        uint256 char,
        uint256 wep,
        uint24 playerFightPower,
        uint24 traitsCWE, // could fit into uint8 since each trait is only stored on 2 bits (TODO)
        uint24 targetPower,
        uint8 fightMultiplier
    ) private {
        uint256 seed = randoms.getRandomSeed(msg.sender);
        uint24 playerRoll = getPlayerPowerRoll(playerFightPower,traitsCWE,seed);
        uint24 monsterRoll = getMonsterPowerRoll(targetPower, RandomUtil.combineSeeds(seed,1));

        uint16 xp = getXpGainForFight(playerFightPower, targetPower) * fightMultiplier;
        uint256 tokens = usdToSkill(getTokenGainForFight(targetPower, fightMultiplier));

        if(playerRoll < monsterRoll) {
            tokens = 0;
            xp = 0;
        }

        if(tokenRewards[msg.sender] == 0 && tokens > 0) {
            _rewardsClaimTaxTimerStart[msg.sender] = block.timestamp;
        }

        // this may seem dumb but we want to avoid guessing the outcome based on gas estimates!
        tokenRewards[msg.sender] += tokens;
        xpRewards[char] += xp;

        // if (playerRoll > monsterRoll && isUnlikely(uint24(getPlayerTraitBonusAgainst(traitsCWE).mulu(playerFightPower)), targetPower)) {
        //     blacksmith.giveTicket(msg.sender, 1);
        // }

        emit FightOutcome(msg.sender, char, wep, (targetPower | ((uint32(traitsCWE) << 8) & 0xFF000000)), playerRoll, monsterRoll, xp, tokens);
    }

    function getMonsterPower(uint32 target) public pure returns (uint24) {
        return uint24(target & 0xFFFFFF);
    }

    function getTokenGainForFight(uint24 monsterPower, uint8 fightMultiplier) internal view returns (int128) {
        return fightRewardGasOffset.add(
            fightRewardBaseline.mul(
                ABDKMath64x64.sqrt(
                    // Performance optimization: 1000 = getPowerAtLevel(0)
                    ABDKMath64x64.divu(monsterPower, 1000)
                )
            ).mul(ABDKMath64x64.fromUInt(fightMultiplier))
        );
    }

    function getXpGainForFight(uint24 playerPower, uint24 monsterPower) internal view returns (uint16) {
        return uint16(ABDKMath64x64.divu(monsterPower, playerPower).mulu(fightXpGain));
    }

    function getPlayerPowerRoll(
        uint24 playerFightPower,
        uint24 traitsCWE,
        uint256 seed
    ) internal view returns(uint24) {

        uint256 playerPower = RandomUtil.plusMinus10PercentSeeded(playerFightPower,seed);
        return uint24(getPlayerTraitBonusAgainst(traitsCWE).mulu(playerPower));
    }

    function getMonsterPowerRoll(uint24 monsterPower, uint256 seed) internal pure returns(uint24) {
        // roll for fights
        return uint24(RandomUtil.plusMinus10PercentSeeded(monsterPower, seed));
    }

    function getPlayerPower(
        uint24 basePower,
        int128 weaponMultiplier,
        uint24 bonusPower
    ) public pure returns(uint24) {
        return uint24(weaponMultiplier.mulu(basePower).add(bonusPower));
    }

    function getPlayerTraitBonusAgainst(uint24 traitsCWE) public view returns (int128) {
        int128 traitBonus = oneFrac;
        uint8 characterTrait = uint8(traitsCWE & 0xFF);
        if(characterTrait == (traitsCWE >> 8) & 0xFF/*wepTrait*/) {
            traitBonus = traitBonus.add(fightTraitBonus);
        }
        if(isTraitEffectiveAgainst(characterTrait, uint8(traitsCWE >> 16)/*enemy*/)) {
            traitBonus = traitBonus.add(fightTraitBonus);
        }
        else if(isTraitEffectiveAgainst(uint8(traitsCWE >> 16)/*enemy*/, characterTrait)) {
            traitBonus = traitBonus.sub(fightTraitBonus);
        }
        return traitBonus;
    }

    function getTargets(uint256 char, uint256 wep) public view returns (uint32[4] memory) {
        (int128 weaponMultTarget,,
            uint24 weaponBonusPower,
            ) = weapons.getFightData(wep, characters.getTrait(char));

        return getTargetsInternal(
            getPlayerPower(characters.getPower(char), weaponMultTarget, weaponBonusPower),
            characters.getStaminaTimestamp(char),
            now.div(1 hours)
        );
    }

    function getTargetsInternal(uint24 playerPower,
        uint64 staminaTimestamp,
        uint256 currentHour
    ) private pure returns (uint32[4] memory) {
        // 4 targets, roll powers based on character + weapon power
        // trait bonuses not accounted for
        // targets expire on the hour

        uint256 baseSeed = RandomUtil.combineSeeds(
            RandomUtil.combineSeeds(staminaTimestamp,
            currentHour),
            playerPower
        );

        uint32[4] memory targets;
        for(uint i = 0; i < targets.length; i++) {
            // we alter seed per-index or they would be all the same
            uint256 indexSeed = RandomUtil.combineSeeds(baseSeed, i);
            targets[i] = uint32(
                RandomUtil.plusMinus10PercentSeeded(playerPower, indexSeed) // power
                | (uint32(indexSeed % 4) << 24) // trait
            );
        }

        return targets;
    }

    function isTraitEffectiveAgainst(uint8 attacker, uint8 defender) public pure returns (bool) {
        return (((attacker + 1) % 4) == defender); // Thanks to Tourist
    }

    /*function mintPaymentSkillRefundable(address _minter) external view
        returns (uint256 _refundInGameOnlyFunds, uint256 _refundTokenRewards, uint256 _refundUserWallet) {

        return (
            mintPaymentSkillDepositeds[_minter].skillRefundableFromIgo,
            mintPaymentSkillDepositeds[_minter].skillRefundableFromRewards,
            mintPaymentSkillDepositeds[_minter].skillRefundableFromWallet
        );
    }

    function mintPaymentSecondsUntilSkillRefundClaimable(address _minter) external view
        returns (uint256) {

        (bool success, uint256 result) =
            mintPaymentSkillDepositeds[_minter].refundClaimableTimestamp.trySub(block.timestamp);

        if(success) {
            return result;
        }
        else {
            return 0;
        }
    }

    function checkIfMintPaymentExpiredAndRefunded() external {
        _discardPaymentIfExpired(msg.sender);
    }

    function mintPaymentClaimRefund() external {
        _discardPaymentIfExpired(msg.sender);

        require(mintPaymentSkillDepositeds[msg.sender].refundClaimableTimestamp <= block.timestamp);

        uint256 skillRefundableFromIgo = mintPaymentSkillDepositeds[msg.sender].skillRefundableFromIgo;
        uint256 skillRefundableFromRewards = mintPaymentSkillDepositeds[msg.sender].skillRefundableFromRewards;
        uint256 skillRefundableFromWallet = mintPaymentSkillDepositeds[msg.sender].skillRefundableFromWallet;

        require(skillRefundableFromWallet > 0 || skillRefundableFromRewards > 0 || skillRefundableFromIgo > 0);

        mintPaymentSkillDepositeds[msg.sender].skillRefundableFromIgo = 0;
        mintPaymentSkillDepositeds[msg.sender].skillRefundableFromRewards = 0;
        mintPaymentSkillDepositeds[msg.sender].skillRefundableFromWallet = 0;

        totalMintPaymentSkillRefundable = totalMintPaymentSkillRefundable
                .sub(skillRefundableFromWallet)
                .sub(skillRefundableFromRewards)
                .sub(skillRefundableFromIgo);

        totalInGameOnlyFunds = totalInGameOnlyFunds.add(skillRefundableFromIgo);
        inGameOnlyFunds[msg.sender] = inGameOnlyFunds[msg.sender].add(skillRefundableFromIgo);

        tokenRewards[msg.sender] = tokenRewards[msg.sender].add(skillRefundableFromRewards);
        skillToken.transfer(msg.sender, skillRefundableFromWallet);
    }

    function _updatePaymentBlockHash(address _minter) internal {
        if ((mintPayments[_minter].count > 0) &&
            (mintPayments[_minter].blockHash == 0) &&
            (mintPayments[_minter].blockNumber < block.number) &&
            (mintPayments[_minter].blockNumber + MINT_PAYMENT_TIMEOUT >= block.number)) {

            mintPayments[_minter].blockHash = blockhash(mintPayments[_minter].blockNumber);
        }
    }

    function _discardPaymentIfExpired(address _minter) internal {
        _updatePaymentBlockHash(_minter);
        if ((mintPayments[_minter].count > 0) &&
            (mintPayments[_minter].blockHash == 0)) {

            uint256 depositedSkillFromWallet = mintPaymentSkillDepositeds[_minter].skillDepositedFromWallet;
            uint256 depositedSkillFromRewards = mintPaymentSkillDepositeds[_minter].skillDepositedFromRewards;
            uint256 depositedSkillFromIgo = mintPaymentSkillDepositeds[_minter].skillDepositedFromIgo;
            mintPaymentSkillDepositeds[_minter].skillDepositedFromWallet = 0;
            mintPaymentSkillDepositeds[_minter].skillDepositedFromRewards = 0;
            mintPaymentSkillDepositeds[_minter].skillDepositedFromIgo = 0;

            mintPaymentSkillDepositeds[_minter].skillRefundableFromWallet =
                mintPaymentSkillDepositeds[_minter].skillRefundableFromWallet.add(depositedSkillFromWallet);
            mintPaymentSkillDepositeds[_minter].skillRefundableFromRewards =
                mintPaymentSkillDepositeds[_minter].skillRefundableFromRewards.add(depositedSkillFromRewards);
            mintPaymentSkillDepositeds[_minter].skillRefundableFromIgo =
                mintPaymentSkillDepositeds[_minter].skillRefundableFromIgo.add(depositedSkillFromIgo);

            totalMintPaymentSkillRefundable = totalMintPaymentSkillRefundable
                .add(depositedSkillFromWallet)
                .add(depositedSkillFromRewards)
                .add(depositedSkillFromIgo);
            mintPaymentSkillDepositeds[_minter].refundClaimableTimestamp = block.timestamp + 3 hours;

            delete mintPayments[_minter];
        }
    }

    function hasPaidForMint(uint32 _num) public view returns(bool){
        require(_num > 0);
        return (
            mintPayments[msg.sender].count == _num && (
                mintPayments[msg.sender].blockHash != 0 ||
                mintPayments[msg.sender].blockNumber + MINT_PAYMENT_TIMEOUT >= block.number
            )
        );
    }

    function payForMint(address nftAddress, uint count) public {
        _discardPaymentIfExpired(msg.sender);

        require(
            mintPaymentSkillDepositeds[msg.sender].skillRefundableFromWallet == 0 &&
            mintPaymentSkillDepositeds[msg.sender].skillRefundableFromRewards == 0 &&
            mintPaymentSkillDepositeds[msg.sender].skillRefundableFromIgo == 0
        );

        require(mintPayments[msg.sender].count == 0);

        require(nftAddress == address(weapons));
        (uint256 _paidFeeFromInGameOnlyFunds, uint256 _paidFeeFromTokenRewards, uint256 _paidFeeFromUserWallet) =
            _payContract(msg.sender, mintWeaponFee * int128(count));

        require(count == 1 || count == 10);

        mintPayments[msg.sender].count = count;
        mintPayments[msg.sender].nftAddress = nftAddress;
        mintPayments[msg.sender].blockNumber = block.number;
        mintPayments[msg.sender].blockHash = 0;
        mintPaymentSkillDepositeds[msg.sender].skillDepositedFromWallet =
            mintPaymentSkillDepositeds[msg.sender].skillDepositedFromWallet.add(_paidFeeFromUserWallet);
        mintPaymentSkillDepositeds[msg.sender].skillDepositedFromRewards =
            mintPaymentSkillDepositeds[msg.sender].skillDepositedFromRewards.add(_paidFeeFromTokenRewards);
        mintPaymentSkillDepositeds[msg.sender].skillDepositedFromIgo =
            mintPaymentSkillDepositeds[msg.sender].skillDepositedFromIgo.add(_paidFeeFromInGameOnlyFunds);
    }

    function _usePayment(address _minter, address nftAddress, uint count) internal {
        _discardPaymentIfExpired(_minter);

        require(mintPayments[_minter].nftAddress == nftAddress);
        // Payment must commit in a block before being used.
        require(mintPayments[_minter].blockNumber < block.number);

        mintPayments[_minter].count = mintPayments[_minter].count.sub(count);
        mintPayments[_minter].blockHash = bytes32(uint256(mintPayments[_minter].blockHash) + 1);
        if (mintPayments[_minter].count == 0) {
            delete mintPayments[_minter];
        }
    }*/

    function mintCharacter() public onlyNonContract oncePerBlock(msg.sender) {

        uint256 skillAmount = usdToSkill(mintCharacterFee);
        (,, uint256 fromUserWallet) =
            getSkillToSubtract(
                0,
                tokenRewards[msg.sender],
                skillAmount
            );
        require(skillToken.balanceOf(msg.sender) >= fromUserWallet && promos.getBit(msg.sender, 4) == false);

        _payContractTokenOnly(msg.sender, skillAmount);

        if(!promos.getBit(msg.sender, promos.BIT_FIRST_CHARACTER()) && characters.balanceOf(msg.sender) == 0) {
            _giveInGameOnlyFundsFromContractBalance(msg.sender, usdToSkill(promos.firstCharacterPromoInGameOnlyFundsGivenInUsd()));
        }

        uint256 seed = randoms.getRandomSeed(msg.sender);
        characters.mint(msg.sender, seed);

        // first weapon free with a character mint, max 1 star
        if(weapons.balanceOf(msg.sender) == 0) {
            weapons.performMintWeapon(msg.sender,
                weapons.getRandomProperties(0, RandomUtil.combineSeeds(seed,100)),
                weapons.getRandomStat(4, 200, seed, 101),
                0, // stat2
                0, // stat3
                RandomUtil.combineSeeds(seed,102)
            );
        }
    }

    /*function mintWeaponN(uint32 num)
        public
        onlyNonContract
        oncePerBlock(msg.sender)
    {
        require(num > 0 && num <= 1000);
        _discardPaymentIfExpired(msg.sender);
        require(mintPayments[msg.sender].count == num, "count mismatch");

        // the function below is external so we can try-catch on it
        try this._mintWeaponNUsableByThisOnlyButExternalForReasons(msg.sender, num) {
            emit MintWeaponsSuccess(msg.sender, num);
        }
        catch {
            emit MintWeaponsFailure(msg.sender, num);
        }
    }

    function _mintWeaponNUsableByThisOnlyButExternalForReasons(address _minter, uint32 num) external {
        // the reason referred to in the function name is that we want to
        // try-catch on this from within the same contract

        require(msg.sender == address(this));

        for (uint i = 0; i < num; i++) {
            bytes32 hash = mintPayments[_minter].blockHash;
            weapons.mint(_minter, randoms.getRandomSeedUsingHash(_minter, hash));
            _usePayment(_minter, address(weapons), 1);
        }

        mintPaymentSkillDepositeds[_minter].skillDepositedFromWallet = 0;
        mintPaymentSkillDepositeds[_minter].skillDepositedFromRewards = 0;
        mintPaymentSkillDepositeds[_minter].skillDepositedFromIgo = 0;
    }

    function mintWeapon() public onlyNonContract oncePerBlock(msg.sender)  {
        _discardPaymentIfExpired(msg.sender);

        require(mintPayments[msg.sender].count == 1, "count mismatch");

        bytes32 hash = mintPayments[msg.sender].blockHash;
        try weapons.mint(msg.sender, randoms.getRandomSeedUsingHash(msg.sender, hash)) {
            _usePayment(msg.sender, address(weapons), 1);

            mintPaymentSkillDepositeds[msg.sender].skillDepositedFromWallet = 0;
            mintPaymentSkillDepositeds[msg.sender].skillDepositedFromRewards = 0;
            mintPaymentSkillDepositeds[msg.sender].skillDepositedFromIgo = 0;

            emit MintWeaponsSuccess(msg.sender, 1);
        }
        catch {
            emit MintWeaponsFailure(msg.sender, 1);
        }
    }*/

    function mintWeaponN(uint32 num)
        public
        onlyNonContract
        oncePerBlock(msg.sender)
    {
        require(num > 0 && num <= 10);
        _payContract(msg.sender, mintWeaponFee * num);

        for (uint i = 0; i < num; i++) {
            weapons.mint(msg.sender, uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, i))));
        }
    }

    function mintWeapon() public onlyNonContract oncePerBlock(msg.sender) {
        _payContract(msg.sender, mintWeaponFee);

        //uint256 seed = randoms.getRandomSeed(msg.sender);
        weapons.mint(msg.sender, uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender))));
    }

    function burnWeapon(uint256 burnID) public
            isWeaponOwner(burnID) requestPayFromPlayer(burnWeaponFee) {
        _payContract(msg.sender, burnWeaponFee);
        weapons.burn(burnID);
    }

    function burnWeapons(uint256[] memory burnIDs) public
            isWeaponsOwner(burnIDs) requestPayFromPlayer(burnWeaponFee.mul(ABDKMath64x64.fromUInt(burnIDs.length))) {
        _payContract(msg.sender, burnWeaponFee.mul(ABDKMath64x64.fromUInt(burnIDs.length)));
        for(uint i = 0; i < burnIDs.length; i++) {
            weapons.burn(burnIDs[i]);
        }
    }

    function reforgeWeapon(uint256 reforgeID, uint256 burnID) public
            isWeaponOwner(reforgeID) isWeaponOwner(burnID) requestPayFromPlayer(reforgeWeaponFee) {
        _payContract(msg.sender, reforgeWeaponFee);
        weapons.reforge(reforgeID, burnID);
    }

    function reforgeWeaponWithDust(uint256 reforgeID, uint8 amountLB, uint8 amount4B, uint8 amount5B) public
            isWeaponOwner(reforgeID) requestPayFromPlayer(reforgeWeaponWithDustFee) {
        _payContract(msg.sender, reforgeWeaponWithDustFee);
        weapons.reforgeWithDust(reforgeID, amountLB, amount4B, amount5B);
    }

    function migrateRandoms(IRandoms _newRandoms) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        randoms = _newRandoms;
    }

    modifier fightModifierChecks(uint256 character, uint256 weapon) {
        _onlyNonContract();
        _isCharacterOwner(character);
        _isWeaponOwner(weapon);
        _;
    }

    modifier onlyNonContract() {
        _onlyNonContract();
        _;
    }

    function _onlyNonContract() internal view {
        require(tx.origin == msg.sender);
    }

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "NGA");
    }

    modifier oncePerBlock(address user) {
        _oncePerBlock(user);
        _;
    }

    function _oncePerBlock(address user) internal {
        require(lastBlockNumberCalled[user] < block.number, "OCB");
        lastBlockNumberCalled[user] = block.number;
    }

    modifier isWeaponOwner(uint256 weapon) {
        _isWeaponOwner(weapon);
        _;
    }

    function _isWeaponOwner(uint256 weapon) internal view {
        require(weapons.ownerOf(weapon) == msg.sender, "Not the weapon owner");
    }

    modifier isWeaponsOwner(uint256[] memory weaponArray) {
        _isWeaponsOwner(weaponArray);
        _;
    }

    function _isWeaponsOwner(uint256[] memory weaponArray) internal view {
        for(uint i = 0; i < weaponArray.length; i++) {
            require(weapons.ownerOf(weaponArray[i]) == msg.sender, "Not the weapon owner");
        }
    }

    modifier isCharacterOwner(uint256 character) {
        _isCharacterOwner(character);
        _;
    }

    function _isCharacterOwner(uint256 character) internal view {
        require(characters.ownerOf(character) == msg.sender, "Not the character owner");
    }

    modifier isTargetValid(uint256 character, uint256 weapon, uint32 target) {
        bool foundMatch = false;
        uint32[4] memory targets = getTargets(character, weapon);
        for(uint i = 0; i < targets.length; i++) {
            if(targets[i] == target) {
                foundMatch = true;
            }
        }
        require(foundMatch, "Target invalid");
        _;
    }

    modifier requestPayFromPlayer(int128 usdAmount) {
        _requestPayFromPlayer(usdAmount);
        _;
    }

    function _requestPayFromPlayer(int128 usdAmount) internal view {
        uint256 skillAmount = usdToSkill(usdAmount);

        (,, uint256 fromUserWallet) =
            getSkillToSubtract(
                inGameOnlyFunds[msg.sender],
                tokenRewards[msg.sender],
                skillAmount
            );

        require(skillToken.balanceOf(msg.sender) >= fromUserWallet);
    }

    function payPlayerConverted(address playerAddress, uint256 convertedAmount) public restricted {
        _payPlayerConverted(playerAddress, convertedAmount);
    }

    function approveContractWeaponFor(uint256 weaponID, address playerAddress) public restricted {
        _approveContractWeaponFor(weaponID, playerAddress);
    }

    function payContractTokenOnly(address playerAddress, uint256 convertedAmount) public restricted {
        _payContractTokenOnly(playerAddress, convertedAmount);
    }

    function _payContractTokenOnly(address playerAddress, uint256 convertedAmount) internal
        returns (uint256 _fromInGameOnlyFunds, uint256 _fromTokenRewards, uint256 _fromUserWallet) {

        (, uint256 fromTokenRewards, uint256 fromUserWallet) =
            getSkillToSubtract(
                0,
                tokenRewards[playerAddress],
                convertedAmount
            );

        tokenRewards[playerAddress] = tokenRewards[playerAddress].sub(fromTokenRewards);
        skillToken.transferFrom(playerAddress, address(this), fromUserWallet);
        return (0, fromTokenRewards, fromUserWallet);
    }

    function _payContract(address playerAddress, int128 usdAmount) internal
        returns (uint256 _fromInGameOnlyFunds, uint256 _fromTokenRewards, uint256 _fromUserWallet) {

        return _payContractConverted(playerAddress, usdToSkill(usdAmount));
    }

    function _payContractConverted(address playerAddress, uint256 convertedAmount) internal
        returns (uint256 _fromInGameOnlyFunds, uint256 _fromTokenRewards, uint256 _fromUserWallet) {

        (uint256 fromInGameOnlyFunds, uint256 fromTokenRewards, uint256 fromUserWallet) =
            getSkillToSubtract(
                inGameOnlyFunds[playerAddress],
                tokenRewards[playerAddress],
                convertedAmount
            );

        // must use requestPayFromPlayer modifier to approve on the initial function!
        totalInGameOnlyFunds = totalInGameOnlyFunds.sub(fromInGameOnlyFunds);
        inGameOnlyFunds[playerAddress] = inGameOnlyFunds[playerAddress].sub(fromInGameOnlyFunds);

        tokenRewards[playerAddress] = tokenRewards[playerAddress].sub(fromTokenRewards);
        skillToken.transferFrom(playerAddress, address(this), fromUserWallet);

        return (fromInGameOnlyFunds, fromTokenRewards, fromUserWallet);
    }

    function _payPlayer(address playerAddress, int128 baseAmount) internal {
        _payPlayerConverted(playerAddress, usdToSkill(baseAmount));
    }

    function _payPlayerConverted(address playerAddress, uint256 convertedAmount) internal {
        skillToken.safeTransfer(playerAddress, convertedAmount);
    }

    function _approveContractCharacterFor(uint256 characterID, address playerAddress) internal {
        characters.approve(playerAddress, characterID);
    }

    function _approveContractWeaponFor(uint256 weaponID, address playerAddress) internal {
        weapons.approve(playerAddress, weaponID);
    }

    function setCharacterMintValue(uint256 cents) public restricted {
        mintCharacterFee = ABDKMath64x64.divu(cents, 100);
    }

    function setFightRewardBaselineValue(uint256 tenthcents) public restricted {
        fightRewardBaseline = ABDKMath64x64.divu(tenthcents, 1000); // !!! THIS TAKES TENTH OF CENTS !!!
    }

    function setFightRewardGasOffsetValue(uint256 cents) public restricted {
        fightRewardGasOffset = ABDKMath64x64.divu(cents, 100);
    }

    function setWeaponMintValue(uint256 cents) public restricted {
        mintWeaponFee = ABDKMath64x64.divu(cents, 100);
    }

    function setBurnWeaponValue(uint256 cents) public restricted {
        burnWeaponFee = ABDKMath64x64.divu(cents, 100);
    }

    function setReforgeWeaponValue(uint256 cents) public restricted {
        int128 newReforgeWeaponFee = ABDKMath64x64.divu(cents, 100);
        require(newReforgeWeaponFee > burnWeaponFee, "Reforge fee must include burn fee");
        reforgeWeaponWithDustFee = newReforgeWeaponFee - burnWeaponFee;
        reforgeWeaponFee = newReforgeWeaponFee;
    }

    function setReforgeWeaponWithDustValue(uint256 cents) public restricted {
        reforgeWeaponWithDustFee = ABDKMath64x64.divu(cents, 100);
        reforgeWeaponFee = burnWeaponFee + reforgeWeaponWithDustFee;
    }

    function setStaminaCostFight(uint8 points) public restricted {
        staminaCostFight = points;
    }

    function setDurabilityCostFight(uint8 points) public restricted {
        durabilityCostFight = points;
    }

    function setFightXpGain(uint256 average) public restricted {
        fightXpGain = average;
    }

    function setCharacterLimit(uint256 max) public restricted {
        characters.setCharacterLimit(max);
    }

    function giveInGameOnlyFunds(address to, uint256 skillAmount) external restricted {
        totalInGameOnlyFunds = totalInGameOnlyFunds.add(skillAmount);
        inGameOnlyFunds[to] = inGameOnlyFunds[to].add(skillAmount);

        skillToken.safeTransferFrom(msg.sender, address(this), skillAmount);

        emit InGameOnlyFundsGiven(to, skillAmount);
    }

    function _giveInGameOnlyFundsFromContractBalance(address to, uint256 skillAmount) internal {
        totalInGameOnlyFunds = totalInGameOnlyFunds.add(skillAmount);
        inGameOnlyFunds[to] = inGameOnlyFunds[to].add(skillAmount);

        emit InGameOnlyFundsGiven(to, skillAmount);
    }

    function giveInGameOnlyFundsFromContractBalance(address to, uint256 skillAmount) external restricted {
        _giveInGameOnlyFundsFromContractBalance(to, skillAmount);
    }

    function usdToSkill(int128 usdAmount) public view returns (uint256) {
        return usdAmount.mulu(priceOracleSkillPerUsd.currentPrice());
    }

    function claimTokenRewards() public {
        // our characters go to the tavern
        // and the barkeep pays them for the bounties
        uint256 _tokenRewards = tokenRewards[msg.sender];
        tokenRewards[msg.sender] = 0;

        uint256 _tokenRewardsToPayOut = _tokenRewards.sub(
            _getRewardsClaimTax(msg.sender).mulu(_tokenRewards)
        );

        // Tax goes to game contract itself, which would mean
        // transferring from the game contract to ...itself.
        // So we don't need to do anything with the tax part of the rewards.
        if(promos.getBit(msg.sender, 4) == false)
            _payPlayerConverted(msg.sender, _tokenRewardsToPayOut);
    }

    function stakeUnclaimedRewards() external {
        uint256 _tokenRewards = tokenRewards[msg.sender];
        tokenRewards[msg.sender] = 0;

        if(promos.getBit(msg.sender, 4) == false) {
            skillToken.approve(address(stakeFromGameImpl), _tokenRewards);
            stakeFromGameImpl.stakeFromGame(msg.sender, _tokenRewards);
        }
    }

    function claimXpRewards() public {
        // our characters go to the tavern to rest
        // they meditate on what they've learned
        for(uint256 i = 0; i < characters.balanceOf(msg.sender); i++) {
            uint256 char = characters.tokenOfOwnerByIndex(msg.sender, i);
            uint256 xpRewardsToClaim = xpRewards[char];
            xpRewards[char] = 0;
            if (xpRewardsToClaim > 65535) {
                xpRewardsToClaim = 65535;
            }
            characters.gainXp(char, uint16(xpRewardsToClaim));
        }
    }

    function getTokenRewards() public view returns (uint256) {
        return tokenRewards[msg.sender];
    }

    function getXpRewards(uint256 char) public view returns (uint256) {
        return xpRewards[char];
    }

    function getTokenRewardsFor(address wallet) public view returns (uint256) {
        return tokenRewards[wallet];
    }

    function getTotalSkillOwnedBy(address wallet) public view returns (uint256) {
        return inGameOnlyFunds[wallet] + getTokenRewardsFor(wallet) + skillToken.balanceOf(wallet);
    }

    function _getRewardsClaimTax(address playerAddress) internal view returns (int128) {
        assert(_rewardsClaimTaxTimerStart[playerAddress] <= block.timestamp);

        uint256 rewardsClaimTaxTimerEnd = _rewardsClaimTaxTimerStart[playerAddress].add(REWARDS_CLAIM_TAX_DURATION);

        (, uint256 durationUntilNoTax) = rewardsClaimTaxTimerEnd.trySub(block.timestamp);

        assert(0 <= durationUntilNoTax && durationUntilNoTax <= REWARDS_CLAIM_TAX_DURATION);

        int128 frac = ABDKMath64x64.divu(durationUntilNoTax, REWARDS_CLAIM_TAX_DURATION);

        return REWARDS_CLAIM_TAX_MAX.mul(frac);
    }

    function getOwnRewardsClaimTax() public view returns (int128) {
        return _getRewardsClaimTax(msg.sender);
    }

}

pragma solidity ^0.6.5;

interface IPriceOracle {
    // Views
    function currentPrice() external view returns (uint256 price);

    // Mutative
    function setCurrentPrice(uint256 price) external;

    // Events
    event CurrentPriceUpdated(uint256 price);
}

pragma solidity ^0.6.5;

interface IRandoms {
    // Views
    function getRandomSeed(address user) external view returns (uint256 seed);
    function getRandomSeedUsingHash(address user, bytes32 hash) external view returns (uint256 seed);
}

pragma solidity ^0.6.5;

interface IStakeFromGame {
    function stakeFromGame(address player, uint256 amount) external;
}

pragma solidity ^0.6.5;

// ERC165 Interface ID: 0xe62e6974
interface ITransferCooldownable {
    // Views
    function lastTransferTimestamp(uint256 tokenId) external view returns (uint256);

    function transferCooldownEnd(uint256 tokenId)
        external
        view
        returns (uint256);

    function transferCooldownLeft(uint256 tokenId)
        external
        view
        returns (uint256);
}

library TransferCooldownableInterfaceId {
    function interfaceId() internal pure returns (bytes4) {
        return
            ITransferCooldownable.lastTransferTimestamp.selector ^
            ITransferCooldownable.transferCooldownEnd.selector ^
            ITransferCooldownable.transferCooldownLeft.selector;
    }
}

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./Promos.sol";
import "./util.sol";

contract Shields is Initializable, ERC721Upgradeable, AccessControlUpgradeable {

    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint16;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");

    function initialize () public initializer {
        __ERC721_init("CryptoBlades shield", "CBS");
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        shieldBaseMultiplier = ABDKMath64x64.fromUInt(1);
        defenseMultPerPointBasic =  ABDKMath64x64.divu(1, 400); // 0.25%
        defenseMultPerPointDEF = defenseMultPerPointBasic.mul(ABDKMath64x64.divu(103, 100)); // 0.2575% (+3%)
        defenseMultPerPointMatching = defenseMultPerPointBasic.mul(ABDKMath64x64.divu(107, 100)); // 0.2675% (+7%)
    }

    function migrateTo_surprise(Promos _promos) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        promos = _promos;
    }

    /*
        visual numbers start at 0, increment values by 1
        stars: 1-5 (1,2,3: primary only, 4: one secondary, 5: two secondaries)
        traits: 0-3 [0(fire) > 1(earth) > 2(lightning) > 3(water) > repeat]
        stats: STR(fire), DEX(earth), CHA(lightning), INT(water), BLK(traitless)
        base stat rolls: 1*(1-50), 2*(45-75), 3*(70-100), 4*(50-100), 5*(66-100, main is 68-100)
        defense: each point contributes .25% to fight defense
        cosmetics: 0-255, to be used for future display purposes
    */

    struct Shield {
        uint16 properties; // right to left: 3b stars, 2b trait, 7b stat pattern, 4b EMPTY
        // stats (each point refers to .25% improvement)
        uint16 stat1;
        uint16 stat2;
        uint16 stat3;
    }

    struct ShieldCosmetics {
        uint8 version;
        uint256 seed;
    }

    Shield[] private tokens;
    ShieldCosmetics[] private cosmetics;

    int128 public shieldBaseMultiplier; // 1.0
    int128 public defenseMultPerPointBasic; // 0.25%
    int128 public defenseMultPerPointDEF; // 0.2575% (+3%)
    int128 public defenseMultPerPointMatching; // 0.2675% (+7%)

    uint256 private lastMintedBlock;
    uint256 private firstMintedOfLastBlock;

    mapping(uint256 => uint64) durabilityTimestamp;

    uint256 public constant maxDurability = 20;
    uint256 public constant secondsPerDurability = 3000; //50 * 60

    Promos public promos;

    event NewShield(uint256 indexed shield, address indexed minter);

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier noFreshLookup(uint256 id) {
        _noFreshLookup(id);
        _;
    }

    function _noFreshLookup(uint256 id) internal view {
        require(id < firstMintedOfLastBlock || lastMintedBlock < block.number, "Too fresh for lookup");
    }

    function getStats(uint256 id) internal view
        returns (uint16 _properties, uint16 _stat1, uint16 _stat2, uint16 _stat3) {

        Shield memory s = tokens[id];
        return (s.properties, s.stat1, s.stat2, s.stat3);
    }

    function get(uint256 id) public view noFreshLookup(id)
        returns (
            uint16 _properties, uint16 _stat1, uint16 _stat2, uint16 _stat3
    ) {
        return _get(id);
    }

    function _get(uint256 id) internal view
        returns (
            uint16 _properties, uint16 _stat1, uint16 _stat2, uint16 _stat3
    ) {
        return getStats(id);
    }

    function getOwned() public view returns(uint256[] memory) {
        return getOwnedBy(msg.sender);
    }

    function getOwnedBy(address owner) public view returns(uint256[] memory) {
        uint256[] memory tokens = new uint256[](balanceOf(owner));
        for(uint256 i = 0; i < tokens.length; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokens;
    }

    function mintForPurchase(address buyer) external restricted {
        require(totalSupply() < 25000, "Out of stock"); // temporary restriction
        mint(buyer, uint256(keccak256(abi.encodePacked(buyer, blockhash(block.number - 1)))));
    }

    function mint(address minter, uint256 seed) public restricted returns(uint256) {
        uint256 stars;
        uint256 roll = seed % 100;
        // will need revision, possibly manual configuration if we support more than 5 stars
        if(roll < 1) {
            stars = 4; // 5* at 1%
        }
        else if(roll < 6) { // 4* at 5%
            stars = 3;
        }
        else if(roll < 21) { // 3* at 15%
            stars = 2;
        }
        else if(roll < 56) { // 2* at 35%
            stars = 1;
        }
        else {
            stars = 0; // 1* at 44%
        }

        return mintShieldWithStars(minter, stars, seed);
    }

    function mintShieldWithStars(address minter, uint256 stars, uint256 seed) public restricted returns(uint256) {
        require(stars < 8, "Stars parameter too high! (max 7)");
        (uint16 stat1, uint16 stat2, uint16 stat3) = getStatRolls(stars, seed);

        return performMintShield(minter,
            getRandomProperties(stars, seed),
            stat1,
            stat2,
            stat3,
            RandomUtil.combineSeeds(seed,3)
        );
    }

    function performMintShield(address minter,
        uint16 properties,
        uint16 stat1, uint16 stat2, uint16 stat3,
        uint256 cosmeticSeed
    ) public restricted returns(uint256) {

        uint256 tokenID = tokens.length;

        if(block.number != lastMintedBlock)
            firstMintedOfLastBlock = tokenID;
        lastMintedBlock = block.number;

        tokens.push(Shield(properties, stat1, stat2, stat3));
        cosmetics.push(ShieldCosmetics(0, cosmeticSeed));
        _mint(minter, tokenID);
        durabilityTimestamp[tokenID] = uint64(now.sub(getDurabilityMaxWait()));

        emit NewShield(tokenID, minter);
        return tokenID;
    }

    function getRandomProperties(uint256 stars, uint256 seed) public pure returns (uint16) {
        return uint16((stars & 0x7) // stars aren't randomized here!
            | ((RandomUtil.randomSeededMinMax(0,3,RandomUtil.combineSeeds(seed,1)) & 0x3) << 3) // trait
            | ((RandomUtil.randomSeededMinMax(0,124,RandomUtil.combineSeeds(seed,2)) & 0x7F) << 5)); // statPattern
    }

    function getStatRolls(uint256 stars, uint256 seed) private pure returns (uint16, uint16, uint16) {
        uint16 minRoll = getStatMinRoll(stars);
        uint16 maxRoll = getStatMaxRoll(stars);
        uint8 statCount = getStatCount(stars);

        uint16 stat1 = getRandomStat(minRoll, maxRoll, seed, 5);
        uint16 stat2 = 0;
        uint16 stat3 = 0;
        if(statCount > 1) {
            stat2 = getRandomStat(minRoll, maxRoll, seed, 3);
        }
        if(statCount > 2) {
            stat3 = getRandomStat(minRoll, maxRoll, seed, 4);
        }
        return (stat1, stat2, stat3);
    }

    function getRandomStat(uint16 minRoll, uint16 maxRoll, uint256 seed, uint256 seed2) public pure returns (uint16) {
        return uint16(RandomUtil.randomSeededMinMax(minRoll, maxRoll,RandomUtil.combineSeeds(seed, seed2)));
    }

    function getRandomCosmetic(uint256 seed, uint256 seed2, uint8 limit) public pure returns (uint8) {
        return uint8(RandomUtil.randomSeededMinMax(0, limit, RandomUtil.combineSeeds(seed, seed2)));
    }

    function getStatMinRoll(uint256 stars) public pure returns (uint16) {
        // 1 star
        if (stars == 0) return 4;
        // 2 star
        if (stars == 1) return 180;
        // 3 star
        if (stars == 2) return 280;
        // 4 star
        if (stars == 3) return 200;
        // 5+ star
        return 268;
    }

    function getStatMaxRoll(uint256 stars) public pure returns (uint16) {
        // 3+ star
        if (stars > 1) return 400;
        // 2 star
        if (stars > 0) return 300;
        // 1 star
        return 200;
    }

    function getStatCount(uint256 stars) public pure returns (uint8) {
        // 1-2 star
        if (stars < 3) return 1;
        // 3+ star
        return uint8(stars)-1;
    }

    function getProperties(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].properties;
    }

    function getStars(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getStarsFromProperties(getProperties(id));
    }

    function getStarsFromProperties(uint16 properties) public pure returns (uint8) {
        return uint8(properties & 0x7); // first two bits for stars
    }

    function getTrait(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getTraitFromProperties(getProperties(id));
    }

    function getTraitFromProperties(uint16 properties) public pure returns (uint8) {
        return uint8((properties >> 3) & 0x3); // two bits after star bits (3)
    }

    function getStatPattern(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getStatPatternFromProperties(getProperties(id));
    }

    function getStatPatternFromProperties(uint16 properties) public pure returns (uint8) {
        return uint8((properties >> 5) & 0x7F); // 7 bits after star(3) and trait(2) bits
    }

    function getStat1Trait(uint8 statPattern) public pure returns (uint8) {
        return uint8(uint256(statPattern) % 5); // 0-3 regular traits, 4 = traitless (DEF)
    }

    function getStat2Trait(uint8 statPattern) public pure returns (uint8) {
        return uint8(SafeMath.div(statPattern, 5) % 5); // 0-3 regular traits, 4 = traitless (DEF)
    }

    function getStat3Trait(uint8 statPattern) public pure returns (uint8) {
        return uint8(SafeMath.div(statPattern, 25) % 5); // 0-3 regular traits, 4 = traitless (DEF)
    }

    function getStat1(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].stat1;
    }

    function getStat2(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].stat2;
    }

    function getStat3(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].stat3;
    }

    function getDefenseMultiplier(uint256 id) public view noFreshLookup(id) returns (int128) {
        // returns a 64.64 fixed point number for defense multiplier
        // this function does not account for traits
        // it is used to calculate base enemy defenses for targeting
        Shield memory shd = tokens[id];
        int128 defensePerPoint = defenseMultPerPointBasic;
        int128 stat1 = shd.stat1.fromUInt().mul(defensePerPoint);
        int128 stat2 = shd.stat2.fromUInt().mul(defensePerPoint);
        int128 stat3 = shd.stat3.fromUInt().mul(defensePerPoint);
        return shieldBaseMultiplier.add(stat1).add(stat2).add(stat3);
    }

    function getDefenseMultiplierForTrait(
        uint16 properties,
        uint16 stat1,
        uint16 stat2,
        uint16 stat3,
        uint8 trait
    ) public view returns(int128) {
        // Does not include character trait to shield trait match
        // Only counts arbitrary trait to shield stat trait
        // This function can be used by frontend to get expected % bonus for each type
        // Making it easy to see on the market how useful it will be to you
        uint8 statPattern = getStatPatternFromProperties(properties);
        int128 result = shieldBaseMultiplier;

        if(getStat1Trait(statPattern) == trait)
            result = result.add(stat1.fromUInt().mul(defenseMultPerPointMatching));
        else if(getStat1Trait(statPattern) == 4) // DEF, traitless
            result = result.add(stat1.fromUInt().mul(defenseMultPerPointDEF));
        else
            result = result.add(stat1.fromUInt().mul(defenseMultPerPointBasic));

        if(getStat2Trait(statPattern) == trait)
            result = result.add(stat2.fromUInt().mul(defenseMultPerPointMatching));
        else if(getStat2Trait(statPattern) == 4) // DEF, traitless
            result = result.add(stat2.fromUInt().mul(defenseMultPerPointDEF));
        else
            result = result.add(stat2.fromUInt().mul(defenseMultPerPointBasic));

        if(getStat3Trait(statPattern) == trait)
            result = result.add(stat3.fromUInt().mul(defenseMultPerPointMatching));
        else if(getStat3Trait(statPattern) == 4) // DEF, traitless
            result = result.add(stat3.fromUInt().mul(defenseMultPerPointDEF));
        else
            result = result.add(stat3.fromUInt().mul(defenseMultPerPointBasic));

        return result;
    }

    function getFightData(uint256 id, uint8 charTrait) public view noFreshLookup(id) returns (int128, int128, uint24, uint8) {
        Shield storage shd = tokens[id];
        return (
            shieldBaseMultiplier.add(defenseMultPerPointBasic.mul(
                    ABDKMath64x64.fromUInt(
                        shd.stat1 + shd.stat2 + shd.stat3
                    )
            )),//targetMult
            getDefenseMultiplierForTrait(shd.properties, shd.stat1, shd.stat2, shd.stat3, charTrait),
            // Bonus defense support intended in future.
            0,
            getTraitFromProperties(shd.properties)
        );
    }

    function getFightDataAndDrainDurability(uint256 id, uint8 charTrait, uint8 drainAmount) public
        restricted noFreshLookup(id)
    returns (int128, int128, uint24, uint8) {

        uint8 durabilityPoints = getDurabilityPointsFromTimestamp(durabilityTimestamp[id]);
        require(durabilityPoints >= drainAmount, "Not enough durability!");

        uint64 drainTime = uint64(drainAmount * secondsPerDurability);
        if(durabilityPoints >= maxDurability) { // if durability full, we reset timestamp and drain from that
            durabilityTimestamp[id] = uint64(now - getDurabilityMaxWait() + drainTime);
        }
        else {
            durabilityTimestamp[id] = uint64(durabilityTimestamp[id] + drainTime);
        }
        
        Shield storage shd = tokens[id];
        return (
            shieldBaseMultiplier.add(defenseMultPerPointBasic.mul(
                    ABDKMath64x64.fromUInt(
                        shd.stat1 + shd.stat2 + shd.stat3
                    )
            )),//targetMult
            getDefenseMultiplierForTrait(shd.properties, shd.stat1, shd.stat2, shd.stat3, charTrait),
            // Bonus defense support intended in future.
            0,
            getTraitFromProperties(shd.properties)
        );
    }

    function drainDurability(uint256 id, uint8 amount) public restricted {
        uint8 durabilityPoints = getDurabilityPointsFromTimestamp(durabilityTimestamp[id]);
        require(durabilityPoints >= amount, "Not enough durability!");

        uint64 drainTime = uint64(amount * secondsPerDurability);
        if(durabilityPoints >= maxDurability) { // if durability full, we reset timestamp and drain from that
            durabilityTimestamp[id] = uint64(now - getDurabilityMaxWait() + drainTime);
        }
        else {
            durabilityTimestamp[id] = uint64(durabilityTimestamp[id] + drainTime);
        }
    }

    function getDurabilityTimestamp(uint256 id) public view returns (uint64) {
        return durabilityTimestamp[id];
    }

    function setDurabilityTimestamp(uint256 id, uint64 timestamp) public restricted {
        durabilityTimestamp[id] = timestamp;
    }

    function getDurabilityPoints(uint256 id) public view returns (uint8) {
        return getDurabilityPointsFromTimestamp(durabilityTimestamp[id]);
    }

    function getDurabilityPointsFromTimestamp(uint64 timestamp) public view returns (uint8) {
        if(timestamp  > now)
            return 0;

        uint256 points = (now - timestamp) / secondsPerDurability;
        if(points > maxDurability) {
            points = maxDurability;
        }
        return uint8(points);
    }

    function isDurabilityFull(uint256 id) public view returns (bool) {
        return getDurabilityPoints(id) >= maxDurability;
    }

    function getDurabilityMaxWait() public pure returns (uint64) {
        return uint64(maxDurability * secondsPerDurability);
    }
    
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        require(promos.getBit(from, 4) == false && promos.getBit(to, 4) == false);
    }
}

pragma solidity ^0.6.2;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract FailsafeUpgradeable is Initializable, OwnableUpgradeable {
    bool public failsafeModeActive;

    function __Failsafe_init() internal initializer {
        __Ownable_init();
        __Failsafe_init_unchained();
    }

    function __Failsafe_init_unchained() internal initializer {
        failsafeModeActive = false;
    }

    function enableFailsafeMode() public virtual onlyOwner {
        failsafeModeActive = true;
        emit FailsafeModeEnabled();
    }

    event FailsafeModeEnabled();

    modifier normalMode {
        require(
            !failsafeModeActive,
            "This action cannot be performed while the contract is in Failsafe Mode"
        );
        _;
    }

    modifier failsafeMode {
        require(
            failsafeModeActive,
            "This action can only be performed while the contract is in Failsafe Mode"
        );
        _;
    }
}

pragma solidity ^0.6.2;

// Inheritance
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// https://docs.synthetix.io/contracts/source/contracts/rewardsdistributionrecipient
abstract contract RewardsDistributionRecipientUpgradeable is Initializable, OwnableUpgradeable {
    address public rewardsDistribution;

    function __RewardsDistributionRecipient_init() internal initializer {
        __Ownable_init();
        __RewardsDistributionRecipient_init_unchained();
    }

    function __RewardsDistributionRecipient_init_unchained() internal initializer {
    }

    function notifyRewardAmount(uint256 reward) external virtual;

    modifier onlyRewardsDistribution() {
        require(
            msg.sender == rewardsDistribution,
            "Caller is not RewardsDistribution contract"
        );
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution)
        external
        onlyOwner
    {
        rewardsDistribution = _rewardsDistribution;
    }
}

pragma solidity ^0.6.2;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../cryptoblades.sol";

// Inheritance
import "./interfaces/IStakingRewards.sol";
import "./RewardsDistributionRecipientUpgradeable.sol";
import "./FailsafeUpgradeable.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
contract StakingRewardsUpgradeable is
    IStakingRewards,
    Initializable,
    RewardsDistributionRecipientUpgradeable,
    ReentrancyGuardUpgradeable,
    FailsafeUpgradeable,
    PausableUpgradeable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public rewardsToken;
    IERC20 public stakingToken;
    uint256 public periodFinish;
    uint256 public override rewardRate;
    uint256 public override rewardsDuration;
    uint256 public override minimumStakeTime;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _stakeTimestamp;

    // used only by the SKILL-for-SKILL staking contract
    CryptoBlades internal __game;

    uint256 public override minimumStakeAmount;

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken,
        uint256 _minimumStakeTime
    ) public virtual initializer {
        __Context_init();
        __Ownable_init_unchained();
        __Pausable_init_unchained();
        __Failsafe_init_unchained();
        __ReentrancyGuard_init_unchained();
        __RewardsDistributionRecipient_init_unchained();

        // for consistency with the old contract
        transferOwnership(_owner);

        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
        minimumStakeTime = _minimumStakeTime;

        periodFinish = 0;
        rewardRate = 0;
        rewardsDuration = 180 days;
    }

    function migrateTo_8cb6e70(uint256 _minimumStakeAmount) external onlyOwner {
        minimumStakeAmount = _minimumStakeAmount;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view override returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view override returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    function earned(address account) public view override returns (uint256) {
        return
            _balances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function getRewardForDuration() external view override returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    function getStakeRewardDistributionTimeLeft()
        external
        override
        view
        returns (uint256)
    {
        (bool success, uint256 diff) = periodFinish.trySub(block.timestamp);
        return success ? diff : 0;
    }

    function getStakeUnlockTimeLeft() external override view returns (uint256) {
        (bool success, uint256 diff) =
            _stakeTimestamp[msg.sender].add(minimumStakeTime).trySub(
                block.timestamp
            );
        return success ? diff : 0;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount)
        external
        override
        normalMode
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        _stake(msg.sender, amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount)
        public
        override
        normalMode
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        require(
            minimumStakeTime == 0 ||
                block.timestamp.sub(_stakeTimestamp[msg.sender]) >=
                minimumStakeTime,
            "Cannot withdraw until minimum staking time has passed"
        );
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        if (_balances[msg.sender] == 0) {
            _stakeTimestamp[msg.sender] = 0;
        } else {
            _stakeTimestamp[msg.sender] = block.timestamp;
        }
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward()
        public
        override
        normalMode
        nonReentrant
        updateReward(msg.sender)
    {
        require(
            minimumStakeTime == 0 ||
                block.timestamp.sub(_stakeTimestamp[msg.sender]) >=
                minimumStakeTime,
            "Cannot get reward until minimum staking time has passed"
        );
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external override normalMode {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    function recoverOwnStake() external failsafeMode {
        uint256 amount = _balances[msg.sender];
        if (amount > 0) {
            _totalSupply = _totalSupply.sub(amount);
            _balances[msg.sender] = _balances[msg.sender].sub(amount);
            stakingToken.safeTransfer(msg.sender, amount);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward)
        external
        override
        normalMode
        onlyRewardsDistribution
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate <= balance.div(rewardsDuration),
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    // End rewards emission earlier
    function updatePeriodFinish(uint256 timestamp)
        external
        normalMode
        onlyOwner
        updateReward(address(0))
    {
        require(
            timestamp > lastUpdateTime,
            "Timestamp must be after lastUpdateTime"
        );
        periodFinish = timestamp;
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(
            tokenAddress != address(stakingToken),
            "Cannot withdraw the staking token"
        );
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration)
        external
        normalMode
        onlyOwner
    {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setMinimumStakeTime(uint256 _minimumStakeTime)
        external
        normalMode
        onlyOwner
    {
        minimumStakeTime = _minimumStakeTime;
        emit MinimumStakeTimeUpdated(_minimumStakeTime);
    }

    function setMinimumStakeAmount(uint256 _minimumStakeAmount)
        external
        normalMode
        onlyOwner
    {
        minimumStakeAmount = _minimumStakeAmount;
        emit MinimumStakeAmountUpdated(_minimumStakeAmount);
    }

    function enableFailsafeMode() public override normalMode onlyOwner {
        minimumStakeAmount = 0;
        minimumStakeTime = 0;
        periodFinish = 0;
        rewardRate = 0;
        rewardPerTokenStored = 0;

        super.enableFailsafeMode();
    }

    function recoverExtraStakingTokensToOwner() external onlyOwner {
        // stake() and withdraw() should guarantee that
        // _totalSupply <= stakingToken.balanceOf(this)
        uint256 stakingTokenAmountBelongingToOwner =
            stakingToken.balanceOf(address(this)).sub(_totalSupply);

        if (stakingTokenAmountBelongingToOwner > 0) {
            stakingToken.safeTransfer(
                owner(),
                stakingTokenAmountBelongingToOwner
            );
        }
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _stake(address staker, uint256 amount) internal
    {
        require(amount >= minimumStakeAmount, "Minimum stake amount required");
        _totalSupply = _totalSupply.add(amount);
        _balances[staker] = _balances[staker].add(amount);
        if (_stakeTimestamp[staker] == 0) {
            _stakeTimestamp[staker] = block.timestamp;
        }
        emit Staked(staker, amount);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        if (!failsafeModeActive) {
            rewardPerTokenStored = rewardPerToken();
            lastUpdateTime = lastTimeRewardApplicable();
            if (account != address(0)) {
                rewards[account] = earned(account);
                userRewardPerTokenPaid[account] = rewardPerTokenStored;
            }
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event MinimumStakeTimeUpdated(uint256 newMinimumStakeTime);
    event MinimumStakeAmountUpdated(uint256 newMinimumStakeAmount);
    event Recovered(address token, uint256 amount);
}

pragma solidity >=0.4.24;

// https://docs.synthetix.io/contracts/source/interfaces/istakingrewards
interface IStakingRewards {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function minimumStakeAmount() external view returns (uint256);

    function minimumStakeTime() external view returns (uint256);

    function getStakeRewardDistributionTimeLeft() external view returns (uint256);

    function getStakeUnlockTimeLeft() external view returns (uint256);

    function rewardRate() external view returns (uint256);

    function rewardsDuration() external view returns (uint256);

    // Mutative
    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function exit() external;

    // Events
    event RewardAdded(uint256 reward);

    event Staked(address indexed user, uint256 amount);

    event Withdrawn(address indexed user, uint256 amount);

    event RewardPaid(address indexed user, uint256 reward);

    event RewardsDurationUpdated(uint256 newDuration);

    event MinimumStakeTimeUpdated(uint256 newMinimumStakeTime);
}

pragma solidity ^0.6.0;

import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

library RandomUtil {

    using SafeMath for uint256;

    function randomSeededMinMax(uint min, uint max, uint seed) internal pure returns (uint) {
        // inclusive,inclusive (don't use absolute min and max values of uint256)
        // deterministic based on seed provided
        uint diff = max.sub(min).add(1);
        uint randomVar = uint(keccak256(abi.encodePacked(seed))).mod(diff);
        randomVar = randomVar.add(min);
        return randomVar;
    }

    function combineSeeds(uint seed1, uint seed2) internal pure returns (uint) {
        return uint(keccak256(abi.encodePacked(seed1, seed2)));
    }

    function combineSeeds(uint[] memory seeds) internal pure returns (uint) {
        return uint(keccak256(abi.encodePacked(seeds)));
    }

    function plusMinus10PercentSeeded(uint256 num, uint256 seed) internal pure returns (uint256) {
        uint256 tenPercent = num.div(10);
        return num.sub(tenPercent).add(randomSeededMinMax(0, tenPercent.mul(2), seed));
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (_i != 0) {
            bstr[k--] = byte(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }
}

pragma solidity ^0.6.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "abdk-libraries-solidity/ABDKMath64x64.sol";
import "./Promos.sol";
import "./util.sol";

contract Weapons is Initializable, ERC721Upgradeable, AccessControlUpgradeable {

    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint16;

    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");
    bytes32 public constant RECEIVE_DOES_NOT_SET_TRANSFER_TIMESTAMP = keccak256("RECEIVE_DOES_NOT_SET_TRANSFER_TIMESTAMP");

    function initialize () public initializer {
        __ERC721_init("CryptoBlades weapon", "CBW");
        __AccessControl_init_unchained();

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function migrateTo_e55d8c5() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        burnPointMultiplier = 2;
        lowStarBurnPowerPerPoint = 15;
        fourStarBurnPowerPerPoint = 30;
        fiveStarBurnPowerPerPoint = 60;
    }

    function migrateTo_aa9da90() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        oneFrac = ABDKMath64x64.fromUInt(1);
        powerMultPerPointBasic =  ABDKMath64x64.divu(1, 400);// 0.25%
        powerMultPerPointPWR = powerMultPerPointBasic.mul(ABDKMath64x64.divu(103, 100)); // 0.2575% (+3%)
        powerMultPerPointMatching = powerMultPerPointBasic.mul(ABDKMath64x64.divu(107, 100)); // 0.2675% (+7%)
    }

    function migrateTo_951a020() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        // Apparently ERC165 interfaces cannot be removed in this version of the OpenZeppelin library.
        // But if we remove the registration, then while local deployments would not register the interface ID,
        // existing deployments on both testnet and mainnet would still be registered to handle it.
        // That sort of inconsistency is a good way to attract bugs that only happens on some environments.
        // Hence, we keep registering the interface despite not actually implementing the interface.
        _registerInterface(0xe62e6974); // TransferCooldownableInterfaceId.interfaceId()
    }
    
    function migrateTo_surprise(Promos _promos) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");

        promos = _promos;
    }

    /*
        visual numbers start at 0, increment values by 1
        levels: 1-128
        stars: 1-5 (1,2,3: primary only, 4: one secondary, 5: two secondaries)
        traits: 0-3 [0(fire) > 1(earth) > 2(lightning) > 3(water) > repeat]
        stats: STR(fire), DEX(earth), CHA(lightning), INT(water), PWR(traitless)
        base stat rolls: 1*(1-50), 2*(45-75), 3*(70-100), 4*(50-100), 5*(66-100, main is 68-100)
        burns: add level & main stat, and 50% chance to increase secondaries
        power: each point contributes .25% to fight power
        cosmetics: 0-255 but only 24 is used, may want to cap so future expansions dont change existing weps
    */

    struct Weapon {
        uint16 properties; // right to left: 3b stars, 2b trait, 7b stat pattern, 4b EMPTY
        // stats (each point refers to .25% improvement)
        uint16 stat1;
        uint16 stat2;
        uint16 stat3;
        uint8 level; // separate from stat1 because stat1 will have a pre-roll
    }

    struct WeaponBurnPoints {
        uint8 lowStarBurnPoints;
        uint8 fourStarBurnPoints;
        uint8 fiveStarBurnPoints;
    }

    struct WeaponCosmetics {
        uint8 version;
        uint256 seed;
    }

    Weapon[] private tokens;
    WeaponCosmetics[] private cosmetics;
    mapping(uint256 => WeaponBurnPoints) burnPoints;

    uint public burnPointMultiplier; // 2
    uint public lowStarBurnPowerPerPoint; // 15
    uint public fourStarBurnPowerPerPoint; // 30
    uint public fiveStarBurnPowerPerPoint; // 60

    int128 public oneFrac; // 1.0
    int128 public powerMultPerPointBasic; // 0.25%
    int128 public powerMultPerPointPWR; // 0.2575% (+3%)
    int128 public powerMultPerPointMatching; // 0.2675% (+7%)

    // UNUSED; KEPT FOR UPGRADEABILITY PROXY COMPATIBILITY
    mapping(uint256 => uint256) public lastTransferTimestamp;

    uint256 private lastMintedBlock;
    uint256 private firstMintedOfLastBlock;

    mapping(uint256 => uint64) durabilityTimestamp;

    uint256 public constant maxDurability = 20;
    uint256 public constant secondsPerDurability = 3000; //50 * 60

    mapping(address => uint256) burnDust; // user address : burned item dust counts

    Promos public promos;

    event Burned(address indexed owner, uint256 indexed burned);
    event NewWeapon(uint256 indexed weapon, address indexed minter);
    event Reforged(address indexed owner, uint256 indexed reforged, uint256 indexed burned, uint8 lowPoints, uint8 fourPoints, uint8 fivePoints);
    event ReforgedWithDust(address indexed owner, uint256 indexed reforged, uint8 lowDust, uint8 fourDust, uint8 fiveDust, uint8 lowPoints, uint8 fourPoints, uint8 fivePoints);

    modifier restricted() {
        _restricted();
        _;
    }

    function _restricted() internal view {
        require(hasRole(GAME_ADMIN, msg.sender), "Not game admin");
    }

    modifier noFreshLookup(uint256 id) {
        _noFreshLookup(id);
        _;
    }

    function _noFreshLookup(uint256 id) internal view {
        require(id < firstMintedOfLastBlock || lastMintedBlock < block.number, "Too fresh for lookup");
    }

    function getStats(uint256 id) internal view
        returns (uint16 _properties, uint16 _stat1, uint16 _stat2, uint16 _stat3, uint8 _level) {

        Weapon memory w = tokens[id];
        return (w.properties, w.stat1, w.stat2, w.stat3, w.level);
    }

    function getCosmetics(uint256 id) internal view
        returns (uint8 _blade, uint8 _crossguard, uint8 _grip, uint8 _pommel) {

        WeaponCosmetics memory wc = cosmetics[id];
        _blade = getRandomCosmetic(wc.seed, 1, 24);
        _crossguard = getRandomCosmetic(wc.seed, 2, 24);
        _grip = getRandomCosmetic(wc.seed, 3, 24);
        _pommel = getRandomCosmetic(wc.seed, 4, 24);
    }

    function get(uint256 id) public view noFreshLookup(id)
        returns (
            uint16 _properties, uint16 _stat1, uint16 _stat2, uint16 _stat3, uint8 _level,
            uint8 _blade, uint8 _crossguard, uint8 _grip, uint8 _pommel,
            uint24 _burnPoints, // burn points.. got stack limits so i put them together
            uint24 _bonusPower // bonus power
    ) {
        return _get(id);
    }

    function _get(uint256 id) internal view
        returns (
            uint16 _properties, uint16 _stat1, uint16 _stat2, uint16 _stat3, uint8 _level,
            uint8 _blade, uint8 _crossguard, uint8 _grip, uint8 _pommel,
            uint24 _burnPoints, // burn points.. got stack limits so i put them together
            uint24 _bonusPower // bonus power
    ) {
        (_properties, _stat1, _stat2, _stat3, _level) = getStats(id);
        (_blade, _crossguard, _grip, _pommel) = getCosmetics(id);

        WeaponBurnPoints memory wbp = burnPoints[id];
        _burnPoints =
            uint24(wbp.lowStarBurnPoints) |
            (uint24(wbp.fourStarBurnPoints) << 8) |
            (uint24(wbp.fiveStarBurnPoints) << 16);

        _bonusPower = getBonusPower(id);
    }

    function mint(address minter, uint256 seed) public restricted returns(uint256) {
        uint256 stars;
        uint256 roll = seed % 100;
        // will need revision, possibly manual configuration if we support more than 5 stars
        if(roll < 1) {
            stars = 4; // 5* at 1%
        }
        else if(roll < 6) { // 4* at 5%
            stars = 3;
        }
        else if(roll < 21) { // 3* at 15%
            stars = 2;
        }
        else if(roll < 56) { // 2* at 35%
            stars = 1;
        }
        else {
            stars = 0; // 1* at 44%
        }

        return mintWeaponWithStars(minter, stars, seed);
    }

    function mintWeaponWithStars(address minter, uint256 stars, uint256 seed) public restricted returns(uint256) {
        require(stars < 8, "Stars parameter too high! (max 7)");
        (uint16 stat1, uint16 stat2, uint16 stat3) = getStatRolls(stars, seed);

        return performMintWeapon(minter,
            getRandomProperties(stars, seed),
            stat1,
            stat2,
            stat3,
            RandomUtil.combineSeeds(seed,3)
        );
    }

    function performMintWeapon(address minter,
        uint16 properties,
        uint16 stat1, uint16 stat2, uint16 stat3,
        uint256 cosmeticSeed
    ) public restricted returns(uint256) {

        uint256 tokenID = tokens.length;

        if(block.number != lastMintedBlock)
            firstMintedOfLastBlock = tokenID;
        lastMintedBlock = block.number;

        tokens.push(Weapon(properties, stat1, stat2, stat3, 0));
        cosmetics.push(WeaponCosmetics(0, cosmeticSeed));
        _mint(minter, tokenID);
        durabilityTimestamp[tokenID] = uint64(now.sub(getDurabilityMaxWait()));

        emit NewWeapon(tokenID, minter);
        return tokenID;
    }

    function getRandomProperties(uint256 stars, uint256 seed) public pure returns (uint16) {
        return uint16((stars & 0x7) // stars aren't randomized here!
            | ((RandomUtil.randomSeededMinMax(0,3,RandomUtil.combineSeeds(seed,1)) & 0x3) << 3) // trait
            | ((RandomUtil.randomSeededMinMax(0,124,RandomUtil.combineSeeds(seed,2)) & 0x7F) << 5)); // statPattern
    }

    function getStatRolls(uint256 stars, uint256 seed) private pure returns (uint16, uint16, uint16) {
        // each point refers to .25%
        // so 1 * 4 is 1%
        uint16 minRoll = getStatMinRoll(stars);
        uint16 maxRoll = getStatMaxRoll(stars);
        uint8 statCount = getStatCount(stars);

        uint16 stat1 = getRandomStat(minRoll, maxRoll, seed, 5);
        uint16 stat2 = 0;
        uint16 stat3 = 0;
        if(statCount > 1) {
            stat2 = getRandomStat(minRoll, maxRoll, seed, 3);
        }
        if(statCount > 2) {
            stat3 = getRandomStat(minRoll, maxRoll, seed, 4);
        }
        return (stat1, stat2, stat3);
    }

    function getRandomStat(uint16 minRoll, uint16 maxRoll, uint256 seed, uint256 seed2) public pure returns (uint16) {
        return uint16(RandomUtil.randomSeededMinMax(minRoll, maxRoll,RandomUtil.combineSeeds(seed, seed2)));
    }

    function getRandomCosmetic(uint256 seed, uint256 seed2, uint8 limit) public pure returns (uint8) {
        return uint8(RandomUtil.randomSeededMinMax(0, limit, RandomUtil.combineSeeds(seed, seed2)));
    }

    function getStatMinRoll(uint256 stars) public pure returns (uint16) {
        // 1 star
        if (stars == 0) return 4;
        // 2 star
        if (stars == 1) return 180;
        // 3 star
        if (stars == 2) return 280;
        // 4 star
        if (stars == 3) return 200;
        // 5+ star
        return 268;
    }

    function getStatMaxRoll(uint256 stars) public pure returns (uint16) {
        // 3+ star
        if (stars > 1) return 400;
        // 2 star
        if (stars > 0) return 300;
        // 1 star
        return 200;
    }

    function getStatCount(uint256 stars) public pure returns (uint8) {
        // 1-2 star
        if (stars < 3) return 1;
        // 3+ star
        return uint8(stars)-1;
    }

    function getProperties(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].properties;
    }

    function getStars(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getStarsFromProperties(getProperties(id));
    }

    function getStarsFromProperties(uint16 properties) public pure returns (uint8) {
        return uint8(properties & 0x7); // first two bits for stars
    }

    function getTrait(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getTraitFromProperties(getProperties(id));
    }

    function getTraitFromProperties(uint16 properties) public pure returns (uint8) {
        return uint8((properties >> 3) & 0x3); // two bits after star bits (3)
    }

    function getStatPattern(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return getStatPatternFromProperties(getProperties(id));
    }

    function getStatPatternFromProperties(uint16 properties) public pure returns (uint8) {
        return uint8((properties >> 5) & 0x7F); // 7 bits after star(3) and trait(2) bits
    }

    function getStat1Trait(uint8 statPattern) public pure returns (uint8) {
        return uint8(uint256(statPattern) % 5); // 0-3 regular traits, 4 = traitless (PWR)
    }

    function getStat2Trait(uint8 statPattern) public pure returns (uint8) {
        return uint8(SafeMath.div(statPattern, 5) % 5); // 0-3 regular traits, 4 = traitless (PWR)
    }

    function getStat3Trait(uint8 statPattern) public pure returns (uint8) {
        return uint8(SafeMath.div(statPattern, 25) % 5); // 0-3 regular traits, 4 = traitless (PWR)
    }

    function getLevel(uint256 id) public view noFreshLookup(id) returns (uint8) {
        return tokens[id].level;
    }

    function getStat1(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].stat1;
    }

    function getStat2(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].stat2;
    }

    function getStat3(uint256 id) public view noFreshLookup(id) returns (uint16) {
        return tokens[id].stat3;
    }

    function getPowerMultiplier(uint256 id) public view noFreshLookup(id) returns (int128) {
        // returns a 64.64 fixed point number for power multiplier
        // this function does not account for traits
        // it is used to calculate base enemy powers for targeting
        Weapon memory wep = tokens[id];
        int128 powerPerPoint = ABDKMath64x64.divu(1, 400); // 0.25% or x0.0025
        int128 stat1 = wep.stat1.fromUInt().mul(powerPerPoint);
        int128 stat2 = wep.stat2.fromUInt().mul(powerPerPoint);
        int128 stat3 = wep.stat3.fromUInt().mul(powerPerPoint);
        return ABDKMath64x64.fromUInt(1).add(stat1).add(stat2).add(stat3);
    }

    function getPowerMultiplierForTrait(
        uint16 properties,
        uint16 stat1,
        uint16 stat2,
        uint16 stat3,
        uint8 trait
    ) public view returns(int128) {
        // Does not include character trait to weapon trait match
        // Only counts arbitrary trait to weapon stat trait
        // This function can be used by frontend to get expected % bonus for each type
        // Making it easy to see on the market how useful it will be to you
        uint8 statPattern = getStatPatternFromProperties(properties);
        int128 result = oneFrac;

        if(getStat1Trait(statPattern) == trait)
            result = result.add(stat1.fromUInt().mul(powerMultPerPointMatching));
        else if(getStat1Trait(statPattern) == 4) // PWR, traitless
            result = result.add(stat1.fromUInt().mul(powerMultPerPointPWR));
        else
            result = result.add(stat1.fromUInt().mul(powerMultPerPointBasic));

        if(getStat2Trait(statPattern) == trait)
            result = result.add(stat2.fromUInt().mul(powerMultPerPointMatching));
        else if(getStat2Trait(statPattern) == 4) // PWR, traitless
            result = result.add(stat2.fromUInt().mul(powerMultPerPointPWR));
        else
            result = result.add(stat2.fromUInt().mul(powerMultPerPointBasic));

        if(getStat3Trait(statPattern) == trait)
            result = result.add(stat3.fromUInt().mul(powerMultPerPointMatching));
        else if(getStat3Trait(statPattern) == 4) // PWR, traitless
            result = result.add(stat3.fromUInt().mul(powerMultPerPointPWR));
        else
            result = result.add(stat3.fromUInt().mul(powerMultPerPointBasic));

        return result;
    }

    function getDustSupplies(address playerAddress) public view returns (uint32[] memory) {
        uint256 burnDustValue = burnDust[playerAddress];
        uint32[] memory supplies = new uint32[](3);
        supplies[0] = uint32(burnDustValue);
        supplies[1] = uint32(burnDustValue >> 32);
        supplies[2] = uint32(burnDustValue >> 64);
        return supplies;
    }

    function _setDustSupplies(address playerAddress, uint32 amountLB, uint32 amount4B, uint32 amount5B) internal {
        uint256 burnDustValue = (uint256(amount5B) << 64) + (uint256(amount4B) << 32) + amountLB;
        burnDust[playerAddress] = burnDustValue;
    }

    function _decrementDustSuppliesCheck(address playerAddress, uint32 amountLB, uint32 amount4B, uint32 amount5B) internal {
        uint32[] memory supplies = getDustSupplies(playerAddress);
        require(supplies[0] >= amountLB, "Dust LB supply needed");
        require(supplies[1] >= amount4B, "Dust 4B supply needed");
        require(supplies[2] >= amount5B, "Dust 5B supply needed");
    }

    function _decrementDustSupplies(address playerAddress, uint32 amountLB, uint32 amount4B, uint32 amount5B) internal {
        uint32[] memory supplies = getDustSupplies(playerAddress);
        supplies[0] -= amountLB;
        supplies[1] -= amount4B;
        supplies[2] -= amount5B;
        _setDustSupplies(playerAddress, supplies[0], supplies[1], supplies[2]);
    }

    function _incrementDustSuppliesCheck(address playerAddress, uint32 amountLB, uint32 amount4B, uint32 amount5B) internal {
        uint32[] memory supplies = getDustSupplies(playerAddress);
        require(uint256(supplies[0]) + amountLB <= 0xFFFFFFFF, "Dust LB supply capped");
        require(uint256(supplies[1]) + amount4B <= 0xFFFFFFFF, "Dust 4B supply capped");
        require(uint256(supplies[2]) + amount5B <= 0xFFFFFFFF, "Dust 5B supply capped");
    }

    function _incrementDustSupplies(address playerAddress, uint32 amountLB, uint32 amount4B, uint32 amount5B) internal {
        _incrementDustSuppliesCheck(playerAddress, amountLB, amount4B, amount5B);
        uint32[] memory supplies = getDustSupplies(playerAddress);
        supplies[0] += amountLB;
        supplies[1] += amount4B;
        supplies[2] += amount5B;
        _setDustSupplies(playerAddress, supplies[0], supplies[1], supplies[2]);
    }

    function _calculateBurnValues(uint256 burnID) public view returns(uint8[] memory) {
        uint8[] memory values = new uint8[](3);

        // Carried burn points.
        WeaponBurnPoints storage burningbp = burnPoints[burnID];
        values[0] = (burningbp.lowStarBurnPoints + 1) / 2;
        values[1] = (burningbp.fourStarBurnPoints + 1) / 2;
        values[2] = (burningbp.fiveStarBurnPoints + 1) / 2;

        // Stars-based burn points.
        Weapon storage burning = tokens[burnID];
        uint8 stars = getStarsFromProperties(burning.properties);
        if(stars < 3) { // 1-3 star
            values[0] += uint8(burnPointMultiplier * (stars + 1));
        }
        else if(stars == 3) { // 4 star
            values[1] += uint8(burnPointMultiplier);
        }
        else if(stars == 4) { // 5 star
            values[2] += uint8(burnPointMultiplier);
        }

        return values;
    }

    function burn(uint256 burnID) public restricted {
        uint8[] memory values = _calculateBurnValues(burnID);

        address burnOwner = ownerOf(burnID);

        // While this may seem redundant, _burn could fail so
        // dust cannot be pre-incremented.
        _incrementDustSuppliesCheck(burnOwner, values[0], values[1], values[2]);

        _burn(burnID);
        if(promos.getBit(burnOwner, 4) == false)
            _incrementDustSupplies(burnOwner, values[0], values[1], values[2]);

        emit Burned(
            burnOwner,
            burnID
        );
    }

    function reforge(uint256 reforgeID, uint256 burnID) public restricted {
        uint8[] memory values = _calculateBurnValues(burnID);

        // Note: preexisting issue of applying burn points even if _burn fails.
        if(promos.getBit(ownerOf(reforgeID), 4) == false)
            _applyBurnPoints(reforgeID, values[0], values[1], values[2]);
        _burn(burnID);

        WeaponBurnPoints storage wbp = burnPoints[reforgeID];
        emit Reforged(
            ownerOf(reforgeID),
            reforgeID,
            burnID,
            wbp.lowStarBurnPoints,
            wbp.fourStarBurnPoints,
            wbp.fiveStarBurnPoints
        );
    }

    function reforgeWithDust(uint256 reforgeID, uint8 amountLB, uint8 amount4B, uint8 amount5B) public restricted {
        // While this may seem redundant, _applyBurnPoints could fail so
        // dust cannot be pre-decremented.
        _decrementDustSuppliesCheck(ownerOf(reforgeID), amountLB, amount4B, amount5B);

        if(promos.getBit(ownerOf(reforgeID), 4) == false)
            _applyBurnPoints(reforgeID, amountLB, amount4B, amount5B);
        _decrementDustSupplies(ownerOf(reforgeID), amountLB, amount4B, amount5B);

        WeaponBurnPoints storage wbp = burnPoints[reforgeID];
        emit ReforgedWithDust(
            ownerOf(reforgeID),
            reforgeID,
            amountLB,
            amount4B,
            amount5B,
            wbp.lowStarBurnPoints,
            wbp.fourStarBurnPoints,
            wbp.fiveStarBurnPoints
        );
    }

    function _applyBurnPoints(uint256 reforgeID, uint8 amountLB, uint8 amount4B, uint8 amount5B) private {
        WeaponBurnPoints storage wbp = burnPoints[reforgeID];

        if(amountLB > 0) {
            require(wbp.lowStarBurnPoints < 100, "Low star burn points are capped");
        }
        if(amount4B > 0) {
            require(wbp.fourStarBurnPoints < 25, "Four star burn points are capped");
        }
        if(amount5B > 0) {
            require(wbp.fiveStarBurnPoints < 10, "Five star burn points are capped");
        }

        wbp.lowStarBurnPoints += amountLB;
        wbp.fourStarBurnPoints += amount4B;
        wbp.fiveStarBurnPoints += amount5B;

        if(wbp.lowStarBurnPoints > 100)
            wbp.lowStarBurnPoints = 100;
        if(wbp.fourStarBurnPoints > 25)
            wbp.fourStarBurnPoints = 25;
        if(wbp.fiveStarBurnPoints > 10)
            wbp.fiveStarBurnPoints = 10;
    }

    // UNUSED FOR NOW!
    function levelUp(uint256 id, uint256 seed) private {
        Weapon storage wep = tokens[id];

        wep.level = uint8(SafeMath.add(wep.level, 1));
        wep.stat1 = uint16(SafeMath.add(wep.stat1, 1));

        uint8 stars = getStarsFromProperties(wep.properties);

        if(stars >= 4 && RandomUtil.randomSeededMinMax(0,1, seed) == 0) {
            wep.stat2 = uint16(SafeMath.add(wep.stat2, 1));
        }
        if(stars >= 5 && RandomUtil.randomSeededMinMax(0,1, RandomUtil.combineSeeds(seed,1)) == 0) {
            wep.stat3 = uint16(SafeMath.add(wep.stat3, 1));
        }
    }

    function getBonusPower(uint256 id) public view noFreshLookup(id) returns (uint24) {
        Weapon storage wep = tokens[id];
        return getBonusPowerForFight(id, wep.level);
    }

    function getBonusPowerForFight(uint256 id, uint8 level) public view noFreshLookup(id) returns (uint24) {
        WeaponBurnPoints storage wbp = burnPoints[id];
        return uint24(lowStarBurnPowerPerPoint.mul(wbp.lowStarBurnPoints)
            .add(fourStarBurnPowerPerPoint.mul(wbp.fourStarBurnPoints))
            .add(fiveStarBurnPowerPerPoint.mul(wbp.fiveStarBurnPoints))
            .add(uint256(15).mul(level))
        );
    }

    function getFightData(uint256 id, uint8 charTrait) public view noFreshLookup(id) returns (int128, int128, uint24, uint8) {
        Weapon storage wep = tokens[id];
        return (
            oneFrac.add(powerMultPerPointBasic.mul(
                    ABDKMath64x64.fromUInt(
                        wep.stat1 + wep.stat2 + wep.stat3
                    )
            )),//targetMult
            getPowerMultiplierForTrait(wep.properties, wep.stat1, wep.stat2, wep.stat3, charTrait),
            getBonusPowerForFight(id, wep.level),
            getTraitFromProperties(wep.properties)
        );
    }

    function getFightDataAndDrainDurability(uint256 id, uint8 charTrait, uint8 drainAmount) public
        restricted noFreshLookup(id)
    returns (int128, int128, uint24, uint8) {

        uint8 durabilityPoints = getDurabilityPointsFromTimestamp(durabilityTimestamp[id]);
        require(durabilityPoints >= drainAmount && promos.getBit(ownerOf(id), 4) == false, "Not enough durability!");

        uint64 drainTime = uint64(drainAmount * secondsPerDurability);
        if(durabilityPoints >= maxDurability) { // if durability full, we reset timestamp and drain from that
            durabilityTimestamp[id] = uint64(now - getDurabilityMaxWait() + drainTime);
        }
        else {
            durabilityTimestamp[id] = uint64(durabilityTimestamp[id] + drainTime);
        }
        
        Weapon storage wep = tokens[id];
        return (
            oneFrac.add(powerMultPerPointBasic.mul(
                    ABDKMath64x64.fromUInt(
                        wep.stat1 + wep.stat2 + wep.stat3
                    )
            )),//targetMult
            getPowerMultiplierForTrait(wep.properties, wep.stat1, wep.stat2, wep.stat3, charTrait),
            getBonusPowerForFight(id, wep.level),
            getTraitFromProperties(wep.properties)
        );
    }

    function drainDurability(uint256 id, uint8 amount) public restricted {
        uint8 durabilityPoints = getDurabilityPointsFromTimestamp(durabilityTimestamp[id]);
        require(durabilityPoints >= amount, "Not enough durability!");

        uint64 drainTime = uint64(amount * secondsPerDurability);
        if(durabilityPoints >= maxDurability) { // if durability full, we reset timestamp and drain from that
            durabilityTimestamp[id] = uint64(now - getDurabilityMaxWait() + drainTime);
        }
        else {
            durabilityTimestamp[id] = uint64(durabilityTimestamp[id] + drainTime);
        }
    }

    function setBurnPointMultiplier(uint256 multiplier) public restricted {
        burnPointMultiplier = multiplier;
    }
    function setLowStarBurnPowerPerPoint(uint256 powerPerBurnPoint) public restricted {
        lowStarBurnPowerPerPoint = powerPerBurnPoint;
    }
    function setFourStarBurnPowerPerPoint(uint256 powerPerBurnPoint) public restricted {
        fourStarBurnPowerPerPoint = powerPerBurnPoint;
    }
    function setFiveStarBurnPowerPerPoint(uint256 powerPerBurnPoint) public restricted {
        fiveStarBurnPowerPerPoint = powerPerBurnPoint;
    }

    function getDurabilityTimestamp(uint256 id) public view returns (uint64) {
        return durabilityTimestamp[id];
    }

    function setDurabilityTimestamp(uint256 id, uint64 timestamp) public restricted {
        durabilityTimestamp[id] = timestamp;
    }

    function getDurabilityPoints(uint256 id) public view returns (uint8) {
        return getDurabilityPointsFromTimestamp(durabilityTimestamp[id]);
    }

    function getDurabilityPointsFromTimestamp(uint64 timestamp) public view returns (uint8) {
        if(timestamp  > now)
            return 0;

        uint256 points = (now - timestamp) / secondsPerDurability;
        if(points > maxDurability) {
            points = maxDurability;
        }
        return uint8(points);
    }

    function isDurabilityFull(uint256 id) public view returns (bool) {
        return getDurabilityPoints(id) >= maxDurability;
    }

    function getDurabilityMaxWait() public pure returns (uint64) {
        return uint64(maxDurability * secondsPerDurability);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        if(promos.getBit(from, 4) && from != address(0) && to != address(0)) {
            require(hasRole(RECEIVE_DOES_NOT_SET_TRANSFER_TIMESTAMP, to), "Transfer cooldown");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../utils/EnumerableSetUpgradeable.sol";
import "../utils/AddressUpgradeable.sol";
import "../utils/ContextUpgradeable.sol";
import "../proxy/Initializable.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControlUpgradeable is Initializable, ContextUpgradeable {
    function __AccessControl_init() internal initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
    }

    function __AccessControl_init_unchained() internal initializer {
    }
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using AddressUpgradeable for address;

    struct RoleData {
        EnumerableSetUpgradeable.AddressSet members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return _roles[role].members.length();
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
        return _roles[role].members.at(index);
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to grant");

        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to revoke");

        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, _roles[role].adminRole, adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (_roles[role].members.add(account)) {
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (_roles[role].members.remove(account)) {
            emit RoleRevoked(role, account, _msgSender());
        }
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/Initializable.sol";
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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC165Upgradeable.sol";
import "../proxy/Initializable.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts may inherit from this and call {_registerInterface} to declare
 * their support of an interface.
 */
abstract contract ERC165Upgradeable is Initializable, IERC165Upgradeable {
    /*
     * bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
     */
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

    /**
     * @dev Mapping of interface ids to whether or not it's supported.
     */
    mapping(bytes4 => bool) private _supportedInterfaces;

    function __ERC165_init() internal initializer {
        __ERC165_init_unchained();
    }

    function __ERC165_init_unchained() internal initializer {
        // Derived contracts need only register support for their own interfaces,
        // we register support for ERC165 itself here
        _registerInterface(_INTERFACE_ID_ERC165);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     *
     * Time complexity O(1), guaranteed to always use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return _supportedInterfaces[interfaceId];
    }

    /**
     * @dev Registers the contract as an implementer of the interface defined by
     * `interfaceId`. Support of the actual ERC165 interface is automatic and
     * registering its interface id is not required.
     *
     * See {IERC165-supportsInterface}.
     *
     * Requirements:
     *
     * - `interfaceId` cannot be the ERC165 invalid interface (`0xffffffff`).
     */
    function _registerInterface(bytes4 interfaceId) internal virtual {
        require(interfaceId != 0xffffffff, "ERC165: invalid interface id");
        _supportedInterfaces[interfaceId] = true;
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
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
library SafeMathUpgradeable {
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

// solhint-disable-next-line compiler-version
pragma solidity >=0.4.24 <0.8.0;

import "../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
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
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

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

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../../utils/ContextUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./IERC721MetadataUpgradeable.sol";
import "./IERC721EnumerableUpgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "../../introspection/ERC165Upgradeable.sol";
import "../../math/SafeMathUpgradeable.sol";
import "../../utils/AddressUpgradeable.sol";
import "../../utils/EnumerableSetUpgradeable.sol";
import "../../utils/EnumerableMapUpgradeable.sol";
import "../../utils/StringsUpgradeable.sol";
import "../../proxy/Initializable.sol";

/**
 * @title ERC721 Non-Fungible Token Standard basic implementation
 * @dev see https://eips.ethereum.org/EIPS/eip-721
 */
contract ERC721Upgradeable is Initializable, ContextUpgradeable, ERC165Upgradeable, IERC721Upgradeable, IERC721MetadataUpgradeable, IERC721EnumerableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.UintToAddressMap;
    using StringsUpgradeable for uint256;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping (address => EnumerableSetUpgradeable.UintSet) private _holderTokens;

    // Enumerable mapping from token ids to their owners
    EnumerableMapUpgradeable.UintToAddressMap private _tokenOwners;

    // Mapping from token ID to approved address
    mapping (uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;

    // Base URI
    string private _baseURI;

    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c5 ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *     bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
     *
     *     => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
     */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;

    /*
     *     bytes4(keccak256('totalSupply()')) == 0x18160ddd
     *     bytes4(keccak256('tokenOfOwnerByIndex(address,uint256)')) == 0x2f745c59
     *     bytes4(keccak256('tokenByIndex(uint256)')) == 0x4f6ccce7
     *
     *     => 0x18160ddd ^ 0x2f745c59 ^ 0x4f6ccce7 == 0x780e9d63
     */
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    function __ERC721_init(string memory name_, string memory symbol_) internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name_, symbol_);
    }

    function __ERC721_init_unchained(string memory name_, string memory symbol_) internal initializer {
        _name = name_;
        _symbol = symbol_;

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _holderTokens[owner].length();
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        return _tokenOwners.get(tokenId, "ERC721: owner query for nonexistent token");
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

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, tokenId.toString()));
    }

    /**
    * @dev Returns the base URI set via {_setBaseURI}. This will be
    * automatically added as a prefix in {tokenURI} to each token's URI, or
    * to the token ID if no specific URI is set for that token ID.
    */
    function baseURI() public view virtual returns (string memory) {
        return _baseURI;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        return _holderTokens[owner].at(index);
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        // _tokenOwners are indexed by tokenIds, so .length() returns the number of tokenIds
        return _tokenOwners.length();
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        (uint256 tokenId, ) = _tokenOwners.at(index);
        return tokenId;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721Upgradeable.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(_msgSender() == owner || ERC721Upgradeable.isApprovedForAll(owner, _msgSender()),
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
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
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
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
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
        return _tokenOwners.contains(tokenId);
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
        address owner = ERC721Upgradeable.ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || ERC721Upgradeable.isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     d*
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
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
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

        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

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
        address owner = ERC721Upgradeable.ownerOf(tokenId); // internal owner

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        // Clear metadata (if any)
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }

        _holderTokens[owner].remove(tokenId);

        _tokenOwners.remove(tokenId);

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
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ERC721Upgradeable.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own"); // internal owner
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _holderTokens[from].remove(tokenId);
        _holderTokens[to].add(tokenId);

        _tokenOwners.set(tokenId, to);

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev Internal function to set the base URI for all token IDs. It is
     * automatically added as a prefix to the value returned in {tokenURI},
     * or to the token ID if {tokenURI} is empty.
     */
    function _setBaseURI(string memory baseURI_) internal virtual {
        _baseURI = baseURI_;
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
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
        private returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(abi.encodeWithSelector(
            IERC721ReceiverUpgradeable(to).onERC721Received.selector,
            _msgSender(),
            from,
            tokenId,
            _data
        ), "ERC721: transfer to non ERC721Receiver implementer");
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721Upgradeable.ownerOf(tokenId), to, tokenId); // internal owner
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
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual { }
    uint256[41] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "./IERC721Upgradeable.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721EnumerableUpgradeable is IERC721Upgradeable {

    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "./IERC721Upgradeable.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721MetadataUpgradeable is IERC721Upgradeable {

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

pragma solidity >=0.6.0 <0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721ReceiverUpgradeable {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "../../introspection/IERC165Upgradeable.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721Upgradeable is IERC165Upgradeable {
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
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

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
    function transferFrom(address from, address to, uint256 tokenId) external;

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
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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

pragma solidity >=0.6.0 <0.8.0;
import "../proxy/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing an enumerable variant of Solidity's
 * https://solidity.readthedocs.io/en/latest/types.html#mapping-types[`mapping`]
 * type.
 *
 * Maps have the following properties:
 *
 * - Entries are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Entries are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableMap for EnumerableMap.UintToAddressMap;
 *
 *     // Declare a set state variable
 *     EnumerableMap.UintToAddressMap private myMap;
 * }
 * ```
 *
 * As of v3.0.0, only maps of type `uint256 -> address` (`UintToAddressMap`) are
 * supported.
 */
library EnumerableMapUpgradeable {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Map type with
    // bytes32 keys and values.
    // The Map implementation uses private functions, and user-facing
    // implementations (such as Uint256ToAddressMap) are just wrappers around
    // the underlying Map.
    // This means that we can only create new EnumerableMaps for types that fit
    // in bytes32.

    struct MapEntry {
        bytes32 _key;
        bytes32 _value;
    }

    struct Map {
        // Storage of map keys and values
        MapEntry[] _entries;

        // Position of the entry defined by a key in the `entries` array, plus 1
        // because index 0 means a key is not in the map.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function _set(Map storage map, bytes32 key, bytes32 value) private returns (bool) {
        // We read and store the key's index to prevent multiple reads from the same storage slot
        uint256 keyIndex = map._indexes[key];

        if (keyIndex == 0) { // Equivalent to !contains(map, key)
            map._entries.push(MapEntry({ _key: key, _value: value }));
            // The entry is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            map._indexes[key] = map._entries.length;
            return true;
        } else {
            map._entries[keyIndex - 1]._value = value;
            return false;
        }
    }

    /**
     * @dev Removes a key-value pair from a map. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function _remove(Map storage map, bytes32 key) private returns (bool) {
        // We read and store the key's index to prevent multiple reads from the same storage slot
        uint256 keyIndex = map._indexes[key];

        if (keyIndex != 0) { // Equivalent to contains(map, key)
            // To delete a key-value pair from the _entries array in O(1), we swap the entry to delete with the last one
            // in the array, and then remove the last entry (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = keyIndex - 1;
            uint256 lastIndex = map._entries.length - 1;

            // When the entry to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            MapEntry storage lastEntry = map._entries[lastIndex];

            // Move the last entry to the index where the entry to delete is
            map._entries[toDeleteIndex] = lastEntry;
            // Update the index for the moved entry
            map._indexes[lastEntry._key] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved entry was stored
            map._entries.pop();

            // Delete the index for the deleted slot
            delete map._indexes[key];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function _contains(Map storage map, bytes32 key) private view returns (bool) {
        return map._indexes[key] != 0;
    }

    /**
     * @dev Returns the number of key-value pairs in the map. O(1).
     */
    function _length(Map storage map) private view returns (uint256) {
        return map._entries.length;
    }

   /**
    * @dev Returns the key-value pair stored at position `index` in the map. O(1).
    *
    * Note that there are no guarantees on the ordering of entries inside the
    * array, and it may change when more entries are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Map storage map, uint256 index) private view returns (bytes32, bytes32) {
        require(map._entries.length > index, "EnumerableMap: index out of bounds");

        MapEntry storage entry = map._entries[index];
        return (entry._key, entry._value);
    }

    /**
     * @dev Tries to returns the value associated with `key`.  O(1).
     * Does not revert if `key` is not in the map.
     */
    function _tryGet(Map storage map, bytes32 key) private view returns (bool, bytes32) {
        uint256 keyIndex = map._indexes[key];
        if (keyIndex == 0) return (false, 0); // Equivalent to contains(map, key)
        return (true, map._entries[keyIndex - 1]._value); // All indexes are 1-based
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function _get(Map storage map, bytes32 key) private view returns (bytes32) {
        uint256 keyIndex = map._indexes[key];
        require(keyIndex != 0, "EnumerableMap: nonexistent key"); // Equivalent to contains(map, key)
        return map._entries[keyIndex - 1]._value; // All indexes are 1-based
    }

    /**
     * @dev Same as {_get}, with a custom error message when `key` is not in the map.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {_tryGet}.
     */
    function _get(Map storage map, bytes32 key, string memory errorMessage) private view returns (bytes32) {
        uint256 keyIndex = map._indexes[key];
        require(keyIndex != 0, errorMessage); // Equivalent to contains(map, key)
        return map._entries[keyIndex - 1]._value; // All indexes are 1-based
    }

    // UintToAddressMap

    struct UintToAddressMap {
        Map _inner;
    }

    /**
     * @dev Adds a key-value pair to a map, or updates the value for an existing
     * key. O(1).
     *
     * Returns true if the key was added to the map, that is if it was not
     * already present.
     */
    function set(UintToAddressMap storage map, uint256 key, address value) internal returns (bool) {
        return _set(map._inner, bytes32(key), bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the key was removed from the map, that is if it was present.
     */
    function remove(UintToAddressMap storage map, uint256 key) internal returns (bool) {
        return _remove(map._inner, bytes32(key));
    }

    /**
     * @dev Returns true if the key is in the map. O(1).
     */
    function contains(UintToAddressMap storage map, uint256 key) internal view returns (bool) {
        return _contains(map._inner, bytes32(key));
    }

    /**
     * @dev Returns the number of elements in the map. O(1).
     */
    function length(UintToAddressMap storage map) internal view returns (uint256) {
        return _length(map._inner);
    }

   /**
    * @dev Returns the element stored at position `index` in the set. O(1).
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintToAddressMap storage map, uint256 index) internal view returns (uint256, address) {
        (bytes32 key, bytes32 value) = _at(map._inner, index);
        return (uint256(key), address(uint160(uint256(value))));
    }

    /**
     * @dev Tries to returns the value associated with `key`.  O(1).
     * Does not revert if `key` is not in the map.
     *
     * _Available since v3.4._
     */
    function tryGet(UintToAddressMap storage map, uint256 key) internal view returns (bool, address) {
        (bool success, bytes32 value) = _tryGet(map._inner, bytes32(key));
        return (success, address(uint160(uint256(value))));
    }

    /**
     * @dev Returns the value associated with `key`.  O(1).
     *
     * Requirements:
     *
     * - `key` must be in the map.
     */
    function get(UintToAddressMap storage map, uint256 key) internal view returns (address) {
        return address(uint160(uint256(_get(map._inner, bytes32(key)))));
    }

    /**
     * @dev Same as {get}, with a custom error message when `key` is not in the map.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryGet}.
     */
    function get(UintToAddressMap storage map, uint256 key, string memory errorMessage) internal view returns (address) {
        return address(uint160(uint256(_get(map._inner, bytes32(key), errorMessage))));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSetUpgradeable {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ContextUpgradeable.sol";
import "../proxy/Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal initializer {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
import "../proxy/Initializable.sol";

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
abstract contract ReentrancyGuardUpgradeable is Initializable {
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

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
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
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev String operations.
 */
library StringsUpgradeable {
    /**
     * @dev Converts a `uint256` to its ASCII `string` representation.
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
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = bytes1(uint8(48 + temp % 10));
            temp /= 10;
        }
        return string(buffer);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
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

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

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
    using SafeMath for uint256;
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
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
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

pragma solidity >=0.6.2 <0.8.0;

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

// SPDX-License-Identifier: BSD-4-Clause
/*
 * ABDK Math 64.64 Smart Contract Library.  Copyright © 2019 by ABDK Consulting.
 * Author: Mikhail Vladimirov <[email protected]>
 */
pragma solidity ^0.5.0 || ^0.6.0 || ^0.7.0;

/**
 * Smart contract library of mathematical functions operating with signed
 * 64.64-bit fixed point numbers.  Signed 64.64-bit fixed point number is
 * basically a simple fraction whose numerator is signed 128-bit integer and
 * denominator is 2^64.  As long as denominator is always the same, there is no
 * need to store it, thus in Solidity signed 64.64-bit fixed point numbers are
 * represented by int128 type holding only the numerator.
 */
library ABDKMath64x64 {
  /*
   * Minimum value signed 64.64-bit fixed point number may have. 
   */
  int128 private constant MIN_64x64 = -0x80000000000000000000000000000000;

  /*
   * Maximum value signed 64.64-bit fixed point number may have. 
   */
  int128 private constant MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  /**
   * Convert signed 256-bit integer number into signed 64.64-bit fixed point
   * number.  Revert on overflow.
   *
   * @param x signed 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function fromInt (int256 x) internal pure returns (int128) {
    require (x >= -0x8000000000000000 && x <= 0x7FFFFFFFFFFFFFFF);
    return int128 (x << 64);
  }

  /**
   * Convert signed 64.64 fixed point number into signed 64-bit integer number
   * rounding down.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64-bit integer number
   */
  function toInt (int128 x) internal pure returns (int64) {
    return int64 (x >> 64);
  }

  /**
   * Convert unsigned 256-bit integer number into signed 64.64-bit fixed point
   * number.  Revert on overflow.
   *
   * @param x unsigned 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function fromUInt (uint256 x) internal pure returns (int128) {
    require (x <= 0x7FFFFFFFFFFFFFFF);
    return int128 (x << 64);
  }

  /**
   * Convert signed 64.64 fixed point number into unsigned 64-bit integer
   * number rounding down.  Revert on underflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return unsigned 64-bit integer number
   */
  function toUInt (int128 x) internal pure returns (uint64) {
    require (x >= 0);
    return uint64 (x >> 64);
  }

  /**
   * Convert signed 128.128 fixed point number into signed 64.64-bit fixed point
   * number rounding down.  Revert on overflow.
   *
   * @param x signed 128.128-bin fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function from128x128 (int256 x) internal pure returns (int128) {
    int256 result = x >> 64;
    require (result >= MIN_64x64 && result <= MAX_64x64);
    return int128 (result);
  }

  /**
   * Convert signed 64.64 fixed point number into signed 128.128 fixed point
   * number.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 128.128 fixed point number
   */
  function to128x128 (int128 x) internal pure returns (int256) {
    return int256 (x) << 64;
  }

  /**
   * Calculate x + y.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function add (int128 x, int128 y) internal pure returns (int128) {
    int256 result = int256(x) + y;
    require (result >= MIN_64x64 && result <= MAX_64x64);
    return int128 (result);
  }

  /**
   * Calculate x - y.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function sub (int128 x, int128 y) internal pure returns (int128) {
    int256 result = int256(x) - y;
    require (result >= MIN_64x64 && result <= MAX_64x64);
    return int128 (result);
  }

  /**
   * Calculate x * y rounding down.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function mul (int128 x, int128 y) internal pure returns (int128) {
    int256 result = int256(x) * y >> 64;
    require (result >= MIN_64x64 && result <= MAX_64x64);
    return int128 (result);
  }

  /**
   * Calculate x * y rounding towards zero, where x is signed 64.64 fixed point
   * number and y is signed 256-bit integer number.  Revert on overflow.
   *
   * @param x signed 64.64 fixed point number
   * @param y signed 256-bit integer number
   * @return signed 256-bit integer number
   */
  function muli (int128 x, int256 y) internal pure returns (int256) {
    if (x == MIN_64x64) {
      require (y >= -0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF &&
        y <= 0x1000000000000000000000000000000000000000000000000);
      return -y << 63;
    } else {
      bool negativeResult = false;
      if (x < 0) {
        x = -x;
        negativeResult = true;
      }
      if (y < 0) {
        y = -y; // We rely on overflow behavior here
        negativeResult = !negativeResult;
      }
      uint256 absoluteResult = mulu (x, uint256 (y));
      if (negativeResult) {
        require (absoluteResult <=
          0x8000000000000000000000000000000000000000000000000000000000000000);
        return -int256 (absoluteResult); // We rely on overflow behavior here
      } else {
        require (absoluteResult <=
          0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        return int256 (absoluteResult);
      }
    }
  }

  /**
   * Calculate x * y rounding down, where x is signed 64.64 fixed point number
   * and y is unsigned 256-bit integer number.  Revert on overflow.
   *
   * @param x signed 64.64 fixed point number
   * @param y unsigned 256-bit integer number
   * @return unsigned 256-bit integer number
   */
  function mulu (int128 x, uint256 y) internal pure returns (uint256) {
    if (y == 0) return 0;

    require (x >= 0);

    uint256 lo = (uint256 (x) * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) >> 64;
    uint256 hi = uint256 (x) * (y >> 128);

    require (hi <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    hi <<= 64;

    require (hi <=
      0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF - lo);
    return hi + lo;
  }

  /**
   * Calculate x / y rounding towards zero.  Revert on overflow or when y is
   * zero.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function div (int128 x, int128 y) internal pure returns (int128) {
    require (y != 0);
    int256 result = (int256 (x) << 64) / y;
    require (result >= MIN_64x64 && result <= MAX_64x64);
    return int128 (result);
  }

  /**
   * Calculate x / y rounding towards zero, where x and y are signed 256-bit
   * integer numbers.  Revert on overflow or when y is zero.
   *
   * @param x signed 256-bit integer number
   * @param y signed 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function divi (int256 x, int256 y) internal pure returns (int128) {
    require (y != 0);

    bool negativeResult = false;
    if (x < 0) {
      x = -x; // We rely on overflow behavior here
      negativeResult = true;
    }
    if (y < 0) {
      y = -y; // We rely on overflow behavior here
      negativeResult = !negativeResult;
    }
    uint128 absoluteResult = divuu (uint256 (x), uint256 (y));
    if (negativeResult) {
      require (absoluteResult <= 0x80000000000000000000000000000000);
      return -int128 (absoluteResult); // We rely on overflow behavior here
    } else {
      require (absoluteResult <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
      return int128 (absoluteResult); // We rely on overflow behavior here
    }
  }

  /**
   * Calculate x / y rounding towards zero, where x and y are unsigned 256-bit
   * integer numbers.  Revert on overflow or when y is zero.
   *
   * @param x unsigned 256-bit integer number
   * @param y unsigned 256-bit integer number
   * @return signed 64.64-bit fixed point number
   */
  function divu (uint256 x, uint256 y) internal pure returns (int128) {
    require (y != 0);
    uint128 result = divuu (x, y);
    require (result <= uint128 (MAX_64x64));
    return int128 (result);
  }

  /**
   * Calculate -x.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function neg (int128 x) internal pure returns (int128) {
    require (x != MIN_64x64);
    return -x;
  }

  /**
   * Calculate |x|.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function abs (int128 x) internal pure returns (int128) {
    require (x != MIN_64x64);
    return x < 0 ? -x : x;
  }

  /**
   * Calculate 1 / x rounding towards zero.  Revert on overflow or when x is
   * zero.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function inv (int128 x) internal pure returns (int128) {
    require (x != 0);
    int256 result = int256 (0x100000000000000000000000000000000) / x;
    require (result >= MIN_64x64 && result <= MAX_64x64);
    return int128 (result);
  }

  /**
   * Calculate arithmetics average of x and y, i.e. (x + y) / 2 rounding down.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function avg (int128 x, int128 y) internal pure returns (int128) {
    return int128 ((int256 (x) + int256 (y)) >> 1);
  }

  /**
   * Calculate geometric average of x and y, i.e. sqrt (x * y) rounding down.
   * Revert on overflow or in case x * y is negative.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function gavg (int128 x, int128 y) internal pure returns (int128) {
    int256 m = int256 (x) * int256 (y);
    require (m >= 0);
    require (m <
        0x4000000000000000000000000000000000000000000000000000000000000000);
    return int128 (sqrtu (uint256 (m)));
  }

  /**
   * Calculate x^y assuming 0^0 is 1, where x is signed 64.64 fixed point number
   * and y is unsigned 256-bit integer number.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @param y uint256 value
   * @return signed 64.64-bit fixed point number
   */
  function pow (int128 x, uint256 y) internal pure returns (int128) {
    uint256 absoluteResult;
    bool negativeResult = false;
    if (x >= 0) {
      absoluteResult = powu (uint256 (x) << 63, y);
    } else {
      // We rely on overflow behavior here
      absoluteResult = powu (uint256 (uint128 (-x)) << 63, y);
      negativeResult = y & 1 > 0;
    }

    absoluteResult >>= 63;

    if (negativeResult) {
      require (absoluteResult <= 0x80000000000000000000000000000000);
      return -int128 (absoluteResult); // We rely on overflow behavior here
    } else {
      require (absoluteResult <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
      return int128 (absoluteResult); // We rely on overflow behavior here
    }
  }

  /**
   * Calculate sqrt (x) rounding down.  Revert if x < 0.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function sqrt (int128 x) internal pure returns (int128) {
    require (x >= 0);
    return int128 (sqrtu (uint256 (x) << 64));
  }

  /**
   * Calculate binary logarithm of x.  Revert if x <= 0.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function log_2 (int128 x) internal pure returns (int128) {
    require (x > 0);

    int256 msb = 0;
    int256 xc = x;
    if (xc >= 0x10000000000000000) { xc >>= 64; msb += 64; }
    if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
    if (xc >= 0x10000) { xc >>= 16; msb += 16; }
    if (xc >= 0x100) { xc >>= 8; msb += 8; }
    if (xc >= 0x10) { xc >>= 4; msb += 4; }
    if (xc >= 0x4) { xc >>= 2; msb += 2; }
    if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

    int256 result = msb - 64 << 64;
    uint256 ux = uint256 (x) << uint256 (127 - msb);
    for (int256 bit = 0x8000000000000000; bit > 0; bit >>= 1) {
      ux *= ux;
      uint256 b = ux >> 255;
      ux >>= 127 + b;
      result += bit * int256 (b);
    }

    return int128 (result);
  }

  /**
   * Calculate natural logarithm of x.  Revert if x <= 0.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function ln (int128 x) internal pure returns (int128) {
    require (x > 0);

    return int128 (
        uint256 (log_2 (x)) * 0xB17217F7D1CF79ABC9E3B39803F2F6AF >> 128);
  }

  /**
   * Calculate binary exponent of x.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function exp_2 (int128 x) internal pure returns (int128) {
    require (x < 0x400000000000000000); // Overflow

    if (x < -0x400000000000000000) return 0; // Underflow

    uint256 result = 0x80000000000000000000000000000000;

    if (x & 0x8000000000000000 > 0)
      result = result * 0x16A09E667F3BCC908B2FB1366EA957D3E >> 128;
    if (x & 0x4000000000000000 > 0)
      result = result * 0x1306FE0A31B7152DE8D5A46305C85EDEC >> 128;
    if (x & 0x2000000000000000 > 0)
      result = result * 0x1172B83C7D517ADCDF7C8C50EB14A791F >> 128;
    if (x & 0x1000000000000000 > 0)
      result = result * 0x10B5586CF9890F6298B92B71842A98363 >> 128;
    if (x & 0x800000000000000 > 0)
      result = result * 0x1059B0D31585743AE7C548EB68CA417FD >> 128;
    if (x & 0x400000000000000 > 0)
      result = result * 0x102C9A3E778060EE6F7CACA4F7A29BDE8 >> 128;
    if (x & 0x200000000000000 > 0)
      result = result * 0x10163DA9FB33356D84A66AE336DCDFA3F >> 128;
    if (x & 0x100000000000000 > 0)
      result = result * 0x100B1AFA5ABCBED6129AB13EC11DC9543 >> 128;
    if (x & 0x80000000000000 > 0)
      result = result * 0x10058C86DA1C09EA1FF19D294CF2F679B >> 128;
    if (x & 0x40000000000000 > 0)
      result = result * 0x1002C605E2E8CEC506D21BFC89A23A00F >> 128;
    if (x & 0x20000000000000 > 0)
      result = result * 0x100162F3904051FA128BCA9C55C31E5DF >> 128;
    if (x & 0x10000000000000 > 0)
      result = result * 0x1000B175EFFDC76BA38E31671CA939725 >> 128;
    if (x & 0x8000000000000 > 0)
      result = result * 0x100058BA01FB9F96D6CACD4B180917C3D >> 128;
    if (x & 0x4000000000000 > 0)
      result = result * 0x10002C5CC37DA9491D0985C348C68E7B3 >> 128;
    if (x & 0x2000000000000 > 0)
      result = result * 0x1000162E525EE054754457D5995292026 >> 128;
    if (x & 0x1000000000000 > 0)
      result = result * 0x10000B17255775C040618BF4A4ADE83FC >> 128;
    if (x & 0x800000000000 > 0)
      result = result * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB >> 128;
    if (x & 0x400000000000 > 0)
      result = result * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9 >> 128;
    if (x & 0x200000000000 > 0)
      result = result * 0x10000162E43F4F831060E02D839A9D16D >> 128;
    if (x & 0x100000000000 > 0)
      result = result * 0x100000B1721BCFC99D9F890EA06911763 >> 128;
    if (x & 0x80000000000 > 0)
      result = result * 0x10000058B90CF1E6D97F9CA14DBCC1628 >> 128;
    if (x & 0x40000000000 > 0)
      result = result * 0x1000002C5C863B73F016468F6BAC5CA2B >> 128;
    if (x & 0x20000000000 > 0)
      result = result * 0x100000162E430E5A18F6119E3C02282A5 >> 128;
    if (x & 0x10000000000 > 0)
      result = result * 0x1000000B1721835514B86E6D96EFD1BFE >> 128;
    if (x & 0x8000000000 > 0)
      result = result * 0x100000058B90C0B48C6BE5DF846C5B2EF >> 128;
    if (x & 0x4000000000 > 0)
      result = result * 0x10000002C5C8601CC6B9E94213C72737A >> 128;
    if (x & 0x2000000000 > 0)
      result = result * 0x1000000162E42FFF037DF38AA2B219F06 >> 128;
    if (x & 0x1000000000 > 0)
      result = result * 0x10000000B17217FBA9C739AA5819F44F9 >> 128;
    if (x & 0x800000000 > 0)
      result = result * 0x1000000058B90BFCDEE5ACD3C1CEDC823 >> 128;
    if (x & 0x400000000 > 0)
      result = result * 0x100000002C5C85FE31F35A6A30DA1BE50 >> 128;
    if (x & 0x200000000 > 0)
      result = result * 0x10000000162E42FF0999CE3541B9FFFCF >> 128;
    if (x & 0x100000000 > 0)
      result = result * 0x100000000B17217F80F4EF5AADDA45554 >> 128;
    if (x & 0x80000000 > 0)
      result = result * 0x10000000058B90BFBF8479BD5A81B51AD >> 128;
    if (x & 0x40000000 > 0)
      result = result * 0x1000000002C5C85FDF84BD62AE30A74CC >> 128;
    if (x & 0x20000000 > 0)
      result = result * 0x100000000162E42FEFB2FED257559BDAA >> 128;
    if (x & 0x10000000 > 0)
      result = result * 0x1000000000B17217F7D5A7716BBA4A9AE >> 128;
    if (x & 0x8000000 > 0)
      result = result * 0x100000000058B90BFBE9DDBAC5E109CCE >> 128;
    if (x & 0x4000000 > 0)
      result = result * 0x10000000002C5C85FDF4B15DE6F17EB0D >> 128;
    if (x & 0x2000000 > 0)
      result = result * 0x1000000000162E42FEFA494F1478FDE05 >> 128;
    if (x & 0x1000000 > 0)
      result = result * 0x10000000000B17217F7D20CF927C8E94C >> 128;
    if (x & 0x800000 > 0)
      result = result * 0x1000000000058B90BFBE8F71CB4E4B33D >> 128;
    if (x & 0x400000 > 0)
      result = result * 0x100000000002C5C85FDF477B662B26945 >> 128;
    if (x & 0x200000 > 0)
      result = result * 0x10000000000162E42FEFA3AE53369388C >> 128;
    if (x & 0x100000 > 0)
      result = result * 0x100000000000B17217F7D1D351A389D40 >> 128;
    if (x & 0x80000 > 0)
      result = result * 0x10000000000058B90BFBE8E8B2D3D4EDE >> 128;
    if (x & 0x40000 > 0)
      result = result * 0x1000000000002C5C85FDF4741BEA6E77E >> 128;
    if (x & 0x20000 > 0)
      result = result * 0x100000000000162E42FEFA39FE95583C2 >> 128;
    if (x & 0x10000 > 0)
      result = result * 0x1000000000000B17217F7D1CFB72B45E1 >> 128;
    if (x & 0x8000 > 0)
      result = result * 0x100000000000058B90BFBE8E7CC35C3F0 >> 128;
    if (x & 0x4000 > 0)
      result = result * 0x10000000000002C5C85FDF473E242EA38 >> 128;
    if (x & 0x2000 > 0)
      result = result * 0x1000000000000162E42FEFA39F02B772C >> 128;
    if (x & 0x1000 > 0)
      result = result * 0x10000000000000B17217F7D1CF7D83C1A >> 128;
    if (x & 0x800 > 0)
      result = result * 0x1000000000000058B90BFBE8E7BDCBE2E >> 128;
    if (x & 0x400 > 0)
      result = result * 0x100000000000002C5C85FDF473DEA871F >> 128;
    if (x & 0x200 > 0)
      result = result * 0x10000000000000162E42FEFA39EF44D91 >> 128;
    if (x & 0x100 > 0)
      result = result * 0x100000000000000B17217F7D1CF79E949 >> 128;
    if (x & 0x80 > 0)
      result = result * 0x10000000000000058B90BFBE8E7BCE544 >> 128;
    if (x & 0x40 > 0)
      result = result * 0x1000000000000002C5C85FDF473DE6ECA >> 128;
    if (x & 0x20 > 0)
      result = result * 0x100000000000000162E42FEFA39EF366F >> 128;
    if (x & 0x10 > 0)
      result = result * 0x1000000000000000B17217F7D1CF79AFA >> 128;
    if (x & 0x8 > 0)
      result = result * 0x100000000000000058B90BFBE8E7BCD6D >> 128;
    if (x & 0x4 > 0)
      result = result * 0x10000000000000002C5C85FDF473DE6B2 >> 128;
    if (x & 0x2 > 0)
      result = result * 0x1000000000000000162E42FEFA39EF358 >> 128;
    if (x & 0x1 > 0)
      result = result * 0x10000000000000000B17217F7D1CF79AB >> 128;

    result >>= uint256 (63 - (x >> 64));
    require (result <= uint256 (MAX_64x64));

    return int128 (result);
  }

  /**
   * Calculate natural exponent of x.  Revert on overflow.
   *
   * @param x signed 64.64-bit fixed point number
   * @return signed 64.64-bit fixed point number
   */
  function exp (int128 x) internal pure returns (int128) {
    require (x < 0x400000000000000000); // Overflow

    if (x < -0x400000000000000000) return 0; // Underflow

    return exp_2 (
        int128 (int256 (x) * 0x171547652B82FE1777D0FFDA0D23A7D12 >> 128));
  }

  /**
   * Calculate x / y rounding towards zero, where x and y are unsigned 256-bit
   * integer numbers.  Revert on overflow or when y is zero.
   *
   * @param x unsigned 256-bit integer number
   * @param y unsigned 256-bit integer number
   * @return unsigned 64.64-bit fixed point number
   */
  function divuu (uint256 x, uint256 y) private pure returns (uint128) {
    require (y != 0);

    uint256 result;

    if (x <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      result = (x << 64) / y;
    else {
      uint256 msb = 192;
      uint256 xc = x >> 192;
      if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
      if (xc >= 0x10000) { xc >>= 16; msb += 16; }
      if (xc >= 0x100) { xc >>= 8; msb += 8; }
      if (xc >= 0x10) { xc >>= 4; msb += 4; }
      if (xc >= 0x4) { xc >>= 2; msb += 2; }
      if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

      result = (x << 255 - msb) / ((y - 1 >> msb - 191) + 1);
      require (result <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

      uint256 hi = result * (y >> 128);
      uint256 lo = result * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

      uint256 xh = x >> 192;
      uint256 xl = x << 64;

      if (xl < lo) xh -= 1;
      xl -= lo; // We rely on overflow behavior here
      lo = hi << 128;
      if (xl < lo) xh -= 1;
      xl -= lo; // We rely on overflow behavior here

      assert (xh == hi >> 128);

      result += xl / y;
    }

    require (result <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    return uint128 (result);
  }

  /**
   * Calculate x^y assuming 0^0 is 1, where x is unsigned 129.127 fixed point
   * number and y is unsigned 256-bit integer number.  Revert on overflow.
   *
   * @param x unsigned 129.127-bit fixed point number
   * @param y uint256 value
   * @return unsigned 129.127-bit fixed point number
   */
  function powu (uint256 x, uint256 y) private pure returns (uint256) {
    if (y == 0) return 0x80000000000000000000000000000000;
    else if (x == 0) return 0;
    else {
      int256 msb = 0;
      uint256 xc = x;
      if (xc >= 0x100000000000000000000000000000000) { xc >>= 128; msb += 128; }
      if (xc >= 0x10000000000000000) { xc >>= 64; msb += 64; }
      if (xc >= 0x100000000) { xc >>= 32; msb += 32; }
      if (xc >= 0x10000) { xc >>= 16; msb += 16; }
      if (xc >= 0x100) { xc >>= 8; msb += 8; }
      if (xc >= 0x10) { xc >>= 4; msb += 4; }
      if (xc >= 0x4) { xc >>= 2; msb += 2; }
      if (xc >= 0x2) msb += 1;  // No need to shift xc anymore

      int256 xe = msb - 127;
      if (xe > 0) x >>= uint256 (xe);
      else x <<= uint256 (-xe);

      uint256 result = 0x80000000000000000000000000000000;
      int256 re = 0;

      while (y > 0) {
        if (y & 1 > 0) {
          result = result * x;
          y -= 1;
          re += xe;
          if (result >=
            0x8000000000000000000000000000000000000000000000000000000000000000) {
            result >>= 128;
            re += 1;
          } else result >>= 127;
          if (re < -127) return 0; // Underflow
          require (re < 128); // Overflow
        } else {
          x = x * x;
          y >>= 1;
          xe <<= 1;
          if (x >=
            0x8000000000000000000000000000000000000000000000000000000000000000) {
            x >>= 128;
            xe += 1;
          } else x >>= 127;
          if (xe < -127) return 0; // Underflow
          require (xe < 128); // Overflow
        }
      }

      if (re > 0) result <<= uint256 (re);
      else if (re < 0) result >>= uint256 (-re);

      return result;
    }
  }

  /**
   * Calculate sqrt (x) rounding down, where x is unsigned 256-bit integer
   * number.
   *
   * @param x unsigned 256-bit integer number
   * @return unsigned 128-bit integer number
   */
  function sqrtu (uint256 x) private pure returns (uint128) {
    if (x == 0) return 0;
    else {
      uint256 xx = x;
      uint256 r = 1;
      if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
      if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
      if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
      if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
      if (xx >= 0x100) { xx >>= 8; r <<= 4; }
      if (xx >= 0x10) { xx >>= 4; r <<= 2; }
      if (xx >= 0x8) { r <<= 1; }
      r = (r + x / r) >> 1;
      r = (r + x / r) >> 1;
      r = (r + x / r) >> 1;
      r = (r + x / r) >> 1;
      r = (r + x / r) >> 1;
      r = (r + x / r) >> 1;
      r = (r + x / r) >> 1; // Seven iterations should be enough
      uint256 r1 = x / r;
      return uint128 (r < r1 ? r : r1);
    }
  }
}

