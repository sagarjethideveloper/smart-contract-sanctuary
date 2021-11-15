//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IKabyHero.sol";

contract StakingPool is IStakingPool, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint public BASE_APY = 5;
    uint public constant MIN_APY = 6;
    uint private constant ONE_YEAR_IN_SECONDS = 31536000;

    uint public payAmountForUpStar = 10;
    mapping(uint => uint) public heroCurrentExp;
    mapping(uint => uint) public heroLevel;
    mapping(uint => uint) public heroEarnedExp;

    IERC20 public immutable acceptedToken;
    IRewardDistributor public immutable rewardDistributorContract;
    IKabyHero public kabyHeroContract;
    
    uint public endTime;
    mapping(address => mapping(uint => StakingData)) public stakingData;
    mapping(uint => bool) private canUpStar;

    // All staking Heros of an address
    mapping(address => EnumerableSet.UintSet) private _stakingHeros;
    
    uint[9] expValue = [2596, 18669, 97685, 374690, 1059536, 2538067, 5730105, 11229970, 19371113];
    uint[9] earnExpToUps = [516, 3194, 14093, 43772, 94502, 204022, 440470, 652003, 965124];
    uint[5] expFactor = [120, 116, 112, 108, 104];
   
    constructor(
        IERC20 tokenAddr,
        IKabyHero kabyHeroAddr,
        IRewardDistributor distributorAddr,
        uint _endReward
    ) {
        acceptedToken = tokenAddr;
        kabyHeroContract = kabyHeroAddr;
        rewardDistributorContract = distributorAddr;
        endTime = _endReward;
    }
    
    /**
     * @dev Owner set new KabyHero contract
     * @param kabyHeroAddr new KabyHero address
     */
    function setKabyHeroContract(IKabyHero kabyHeroAddr) external onlyOwner {
        require(address(kabyHeroAddr) != address(0));
        kabyHeroContract = kabyHeroAddr;
        emit UpdateKabyHero(address(kabyHeroAddr));
    }
    
    /**
     * @dev Owner set endTime value
     */
    function setEndTime(uint _endTime) external onlyOwner {
        require(_endTime >= block.timestamp, "StakingPool: invalid end time");
        endTime = _endTime;
        emit UpdateEndTime(_endTime);
    }
    
    /**
     * @dev Owner set payAmountForUpStar value
     */
    function setPayAmountForUpStar(uint amount) external onlyOwner{
        payAmountForUpStar = amount;
    }
    
    /**
     * @dev Owner set BASE_APY value
     */
    function setBaseAPY(uint baseApy) external onlyOwner{
        BASE_APY = baseApy;
    }

    /**
     * @dev Get balance of rewardDistributorContract
     */
    function balanceOfRewardDistributor() public view returns (uint) {
        return acceptedToken.balanceOf(address(rewardDistributorContract));
    }

    /**
     * @dev Stake Kaby hero and Kaby token for upgrade star for hero
     * @param heroId id of hero want to stake to upgrade star.
     * @param amount amount of kaby token to stake 
     */
    function stake(uint heroId, uint amount) external override {
        require(amount > 0, "StakingPool: invalid amount");
        require(block.timestamp < endTime, "StakingPool: closed");
        require(heroId < kabyHeroContract.totalSupply(), "StakingPool: invalid hero");
        address account = msg.sender;
        
        StakingData storage stakingHero = stakingData[account][heroId];
        
        heroLevel[heroId] = heroLevel[heroId] == 0 ? 1 : heroLevel[heroId];
        
        _harvest(heroId, account);
        
        stakingHero.balance += amount;
        stakingHero.APY = BASE_APY;
        
        _stakingHeros[account].add(heroId);

        acceptedToken.safeTransferFrom(account, address(this), amount);

        emit Staked(heroId, account, amount);
    }

    /**
     * @dev Unstake from a hero and claim their rewards.
     * @param heroId id of hero.
     * @param amount amount of kaby token to unstake in this time
     */
    function unstake(uint heroId, uint amount) external override {
        require(heroId < kabyHeroContract.totalSupply(), "StakingPool: invalid hero");
        address account = msg.sender;
        require(_stakingHeros[account].contains(heroId), "StakingPool: Hero is not staking");
        StakingData storage stakingHero = stakingData[account][heroId];
        require(stakingHero.balance >= amount, "StakingPool: insufficient balance");
        
        _harvest(heroId, account);
        
        uint newBalance = stakingHero.balance - amount;
        stakingHero.balance = newBalance;

        if (newBalance == 0) {
            _stakingHeros[account].remove(heroId);
            stakingHero.APY = 0;
            uint reward = stakingHero.reward;
            stakingHero.reward = 0;
            rewardDistributorContract.distributeReward(account, reward);
        }

        acceptedToken.safeTransfer(account, amount);

        emit Unstaked(heroId, account, amount);
    }

    /**
     * @dev User claim their rewards and upgrade level of hero if can upgrade.
     * @param heroId id of hero.
     */
    function claim(uint heroId) external override {
        require(heroId < kabyHeroContract.totalSupply(), "StakingPool: invalid hero");
        address account = msg.sender;
        require(_stakingHeros[account].contains(heroId), "StakingPool: Hero is not staking");
        StakingData storage stakingHero = stakingData[account][heroId];

        _harvest(heroId, account);

        convertExpToLevels(heroId);

        uint reward = stakingHero.reward;
        stakingHero.reward = 0;
        rewardDistributorContract.distributeReward(account, reward);
        emit Claimed(heroId, account, reward);
    }
    
    /**
     * @dev Internal function to calculate and get range of level that hero can upgrade
     */
    function searchLevelIndexByExp(uint[9] memory levelExp, uint totalExp) private returns(uint){
        uint levelIndex = 1;
        uint maxLevelIndex = 90;
        if(totalExp >= levelExp[8] * 1e18)
        {
            levelIndex = maxLevelIndex;
            return levelIndex;
        }
        else if(totalExp >= levelExp[0] * 1e18 && totalExp < levelExp[8] * 1e18)
        { 
            uint minArray = 0;
            uint maxArray = levelExp.length - 1;
            while(minArray < maxArray)
            {
                uint midArray = (minArray + maxArray) / 2;
                if((maxArray - minArray) == 1)
                {
                    levelIndex = maxArray * 10;
                    return levelIndex;
                }
                else if (totalExp >= levelExp[midArray] * 1e18)
                {
                    minArray = midArray;
                }
                else
                {
                    maxArray = midArray;
                }
            }
        }
        return levelIndex;      
    }
    
    /**
     * @dev Internal function to calculate and get max level that hero can upgrade
     */
    function getMaxLevelToUp(
        uint heroId,
        uint levelIndex,
        uint totalExp,
        uint[5] memory _expFactors,
        uint[9] memory _levelExp,
        uint[9] memory _earnExpToUps) private returns(uint){
            
        uint maxLevel = levelIndex;
        uint expFactorValue = 0;
        uint currentStar = kabyHeroContract.getHeroStar(heroId);
        
        if (totalExp < 100 * 1e18)
        {
            return maxLevel;
        }
        if (totalExp >= (expValue[currentStar - 1]) * 1e18) {            
            maxLevel = currentStar * 10;            
            heroEarnedExp[heroId] = 0;
            heroCurrentExp[heroId] = expValue[currentStar - 1] * 1e18;
            return maxLevel;
        }
        if (levelIndex < 20)
        {
            expFactorValue = _expFactors[0];
        }
        else if (levelIndex < 30)
        {
            expFactorValue = _expFactors[1];
        }
        else if (levelIndex < 40)
        {
            expFactorValue = _expFactors[2];
        }
        else if (levelIndex < 70)
        {
            expFactorValue = _expFactors[3];
        }
        else
        {
            expFactorValue = _expFactors[4];
        }

        uint minExpToLevelUp = 100 * 1e18;
        uint minExp = 100 * 1e18;
        if (levelIndex > 1)
        {
            uint expArrayIndex = levelIndex / 10 - 1;
            minExp = _levelExp[expArrayIndex] * 1e18;
            minExpToLevelUp = _earnExpToUps[expArrayIndex] * 1e18;
        }
        for (uint i = levelIndex; i < levelIndex + 10; i++)
        {
            if (totalExp >= (minExp + minExpToLevelUp * expFactorValue / 100))
            {
                maxLevel++;
                minExpToLevelUp = minExpToLevelUp * expFactorValue / 100;
                minExp = minExp + minExpToLevelUp;
                heroCurrentExp[heroId] = minExp;
            }
            else
            {
                break;
            }
        }
        
        heroEarnedExp[heroId] = totalExp - minExp; 
        
        if (maxLevel == currentStar * 10) {
            heroEarnedExp[heroId] = 0;
            heroCurrentExp[heroId] = expValue[currentStar - 1] * 1e18;
        }
        return maxLevel;
    }
    
    /**
     * @dev Internal function to convert from exp to level
     */
    function convertExpToLevels(uint heroId) private {
        uint currentExp = heroCurrentExp[heroId];
        uint earnedExp = heroEarnedExp[heroId];
        uint totalExp = currentExp + earnedExp;
        
        uint levelIndex = searchLevelIndexByExp(expValue, totalExp);

        uint maxLevelToUp = getMaxLevelToUp(heroId, levelIndex, totalExp, expFactor, expValue, earnExpToUps);
        
        heroLevel[heroId] = maxLevelToUp;
    }

    /**
     * @dev User request to upgrade star of their hero
     * @param heroId id of hero.
     */
    function upgradeStarForHero(uint heroId) external override {
        require(heroId < kabyHeroContract.totalSupply(), "StakingPool: invalid hero");
        address account = msg.sender;

        _harvest(heroId, account);
        
        require(canUpStar[heroId], "StakingPool: Cannot upgrade star for this hero");
        
        uint currentStar = kabyHeroContract.getHeroStar(heroId);
        
        uint amount = currentStar * payAmountForUpStar * 10 ** ERC20(address(acceptedToken)).decimals();
        acceptedToken.safeTransferFrom(account, owner(), amount);
        kabyHeroContract.upgradeStar(heroId, 1);
    }

    /**
     * @dev Get status of upgradeStar for hero, amount of exp and reward earned
     * @param heroId id of hero.
     * @param account wallet address of user
     */
    function earned(uint heroId, address account) public view override returns (bool canUpgradeStar, uint expEarned, uint tokenEarned) {
        require(heroId < kabyHeroContract.totalSupply(), "StakingPool: invalid hero");
        StakingData memory stakingHero = stakingData[account][heroId];

        uint lastUpdatedTime = stakingHero.lastUpdatedTime;
        uint currentTime = block.timestamp > endTime ? endTime : block.timestamp;
        uint stakedTime = lastUpdatedTime > currentTime ? 0 : currentTime - lastUpdatedTime;
        uint stakedTimeInSeconds = lastUpdatedTime == 0 ? 0 : stakedTime;
        uint stakingDuration = stakingHero.balance * stakedTimeInSeconds;
        uint maxHeroLevel = kabyHeroContract.getHeroStar(heroId) * 10;

        canUpgradeStar = heroLevel[heroId] == maxHeroLevel;
        expEarned = heroLevel[heroId] < maxHeroLevel ? stakingDuration / 1e5 : 0;
        tokenEarned = stakingDuration * stakingHero.APY / ONE_YEAR_IN_SECONDS / 100;
    }

    /**
     * @dev Get staking data of an account with heroId 
     * @param heroId id of hero.
     * @param account wallet address of user
     */
    function balanceOf(uint heroId, address account) external view override returns (uint) {
        require(heroId < kabyHeroContract.totalSupply(), "StakingPool: invalid hero");
        return stakingData[account][heroId].balance;
    }

    /**
     * @dev Check and update status of upgradeStar for hero, amount of exp and reward earned
     * @param heroId id of hero.
     * @param account wallet address of user
     */
    function _harvest(uint heroId, address account) private {
        (bool canUpgradeStar, uint expEarned, uint tokenEarned) = earned(heroId, account);
        
        heroEarnedExp[heroId] += expEarned;
        canUpStar[heroId] = canUpgradeStar;
        StakingData storage stakingHero = stakingData[account][heroId];
        stakingHero.lastUpdatedTime = block.timestamp;
        stakingHero.reward += tokenEarned;
    }
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStakingPool {
    event Staked(uint indexed heroId, address indexed account, uint amount);
    event Unstaked(uint indexed heroId, address indexed account, uint amount);
    event Claimed(uint indexed heroId, address indexed account, uint reward);
    event UpdateKabyHero(address kabyHeroAddr);
    event UpdateEndTime(uint endTime);

    struct StakingData {
        uint balance;
        uint APY;
        uint lastUpdatedTime;
        uint reward;
    }

    /**
     * @notice Stake KABY token for upgrade hero star & receive reward.
     */
    function stake(uint heroId, uint amount) external;

    /**
     * @notice Unstake KABY token from a hero.
     */
    function unstake(uint heroId, uint amount) external;

    /**
     * @notice Harvest all time for upgrade star and reward earned from a Hero.
     */
    function claim(uint heroId) external;

    /**
     * @notice upgrade star for hero.
     */
    function upgradeStarForHero(uint heroId) external;

    /**
     * @notice Gets status of upgrade star and KABY earned by a hero so far.
     */
    function earned(uint heroId, address account) external view returns (bool canUpgradeStar, uint expEarned, uint tokenEarned);

    /**
     * @notice Gets total KABY staked of a Hero.
     */
    function balanceOf(uint heroId, address account) external view returns (uint);
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardDistributor {
    /**
     * @notice Distribute reward earned from Staking Pool
     */
    function distributeReward(address account, uint amount) external;
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKabyHero {
    struct Hero {
        uint256 star;
        uint256 gem1;
        uint256 gem2;
        uint256 gem3;
        uint256 gem4;
        uint256 gem5;
    }

    struct Version {
        uint256 currentSell;
        uint256 currentReserve;
        uint256 maxSupply;
        uint256 maxForSell;
        uint256 salePrice;
        uint256 startTime;
        uint256 endTime;
        string provenance; // This is the provenance record of all Hero artworks in existence.
        bool useSummonStaking;
        uint256[] starIndex;
    }

    struct VersionConstructorParams {
        uint256 maxSupply;
        uint256 maxForSell;
        uint256 salePrice;
        uint256 startTime;
        uint256 endTime;
        string provenance;
    }

    event HeroCreated(
        uint256 indexed heroId,
        uint256 star,
        address ownerOfHero
    );
    event HeroListed(
        uint256 indexed heroId,
        uint256 price,
        address ownerOfHero
    );
    event HeroDelisted(uint256 indexed heroId, address ownerOfHero);
    event HeroStarUpgraded(
        uint256 indexed heroId,
        uint256 newStar,
        uint256 amount
    );
    event HeroBought(
        uint256 indexed heroId,
        address buyer,
        address seller,
        uint256 price
    );
    event HeroOffered(uint256 indexed heroId, address buyer, uint256 price);
    event HeroOfferCanceled(uint256 indexed heroId, address buyer);
    event HeroPriceIncreased(
        uint256 indexed heroId,
        uint256 floorPrice,
        uint256 increasedAmount
    );
    event ItemsEquipped(uint256 indexed heroId, uint256[] itemIds);
    event ItemsUnequipped(uint256 indexed heroId, uint256[] itemIds);
    event NewVersionAdded(uint256 versionId);
    event UpdateRandomGenerator(address newRandomGenerator);
    event SetStar(uint256 indexed heroId, uint256 star, address ownerOfHero);
    event UpdateStakingPool(address newStakingPool);
    event UpdateSummonStakingPool(address newSummonStakingPool);
    event UpdateGem(address newGem);
    event UpdateMaxStar(uint256 newMaxStar);
    event UpdateMarketFee(uint256 newMarketFee);
    event UpdateEndTime(uint256 endTime);
    event UpdateMaxSupply(uint256 newMaxSupply);

    /**
     * @notice Claims Heros when it's on presale phase.
     */
    function claimHero(uint256 versionId, uint256 amount) external;

    /**
     * @notice Upgrade star for hero
     */
    function upgradeStar(uint256 heroId, uint256 amount) external;

    /**
     * @notice Mint Heros from Minter to user.
     */
    function mintHero(
        uint256 versionId,
        uint256 amount,
        address account
    ) external;

    /**
     * @notice Owner equips items to their Hero by burning ERC1155 Gem NFTs.
     *
     * Requirements:
     * - caller must be owner of the Hero.
     */
    function equipItems(uint256 heroId, uint256[] memory itemIds) external;

    /**
     * @notice Owner removes items from their Hero. ERC1155 Gem NFTs are minted back to the owner.
     *
     * Requirements:
     * - caller must be owner of the Hero.
     */
    function removeItems(uint256 heroId, uint256[] memory itemIds) external;

    /**
     * @notice Burns a Hero `.
     *
     * - Not financial advice: DONT DO THAT.
     * - Remember to remove all items before calling this function.
     */
    function sacrificeHero(uint256 heroId) external;

    /**
     * @notice Lists a Hero on sale.
     *
     * Requirements:
     * - `price` cannot be under Hero's `floorPrice`.
     * - Caller must be the owner of the Hero.
     */
    function list(uint256 heroId, uint256 price) external;

    /**
     * @notice Delist a Hero on sale.
     */
    function delist(uint256 heroId) external;

    /**
     * @notice Instant buy a specific Hero on sale.
     *
     * Requirements:
     * - Target Hero must be currently on sale.
     * - Sent value must be exact the same as current listing price.
     */
    function buy(uint256 heroId) external;

    /**
     * @notice Gives offer for a Hero.
     *
     * Requirements:
     * - Owner cannot offer.
     */
    function offer(uint256 heroId, uint256 offerValue) external;

    /**
     * @notice Owner take an offer to sell their Hero.
     *
     * Requirements:
     * - Cannot take offer under Hero's `floorPrice`.
     * - Offer value must be at least equal to `minPrice`.
     */
    function takeOffer(
        uint256 heroId,
        address offerAddr,
        uint256 minPrice
    ) external;

    /**
     * @notice Cancels an offer for a specific Hero.
     */
    function cancelOffer(uint256 heroId) external;

    /**
     * @notice Finalizes the battle aftermath of 2 Heros.
     */
    // function finalizeDuelResult(uint winningheroId, uint losingheroId, uint penaltyInBps) external;

    /**
     * @notice Gets Hero information.
     */
    function getHero(uint256 heroId)
        external
        view
        returns (uint256 star, uint256[5] memory gem);

    /**
     * @notice Gets current star of given hero.
     */
    function getHeroStar(uint256 heroId) external view returns (uint256);

    /**
     * @notice Gets current total hero was created.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Set random star
     */
    function setRandomStar(uint256 heroId, uint256 randomness) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
library EnumerableSet {
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
        mapping(bytes32 => uint256) _indexes;
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

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            if (lastIndex != toDeleteIndex) {
                bytes32 lastvalue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastvalue;
                // Update the index for the moved value
                set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex
            }

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
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
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
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
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

