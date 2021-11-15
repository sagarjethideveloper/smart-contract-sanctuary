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
pragma solidity >=0.8.5;

/**
 * Import statements for integration of interfaces and other implementations
 **/
import "./IERC20.sol";  // The ERC20 interface

contract SurveyTokenFaucet{
    
    address private owner;  // Owner of the faucet
    mapping (address => mapping (address => uint16)) private tokenAllowance; // Holds how many tokens were payed out to an address for different contracts/ tokens
    mapping (address => mapping (address => uint16)) private gasFundsAllowance; // Holds how many tokens were payed out to an address for different contracts/ tokens
    //   Token Contract Address => (User Address => Amount of Tokens already sent there)

    constructor() {
        owner = msg.sender;
    }

    event FundsAdded(address _tokenContract, address _participant);  // Denotes successfull transfer of funds
    event TokenAdded(address _tokenContract, address _participant);  // Denotes successfull transfer of a token

    // ------ ------ ------ ------ ------ ------ //
    // ------ Fallback-function ----- //
    // ------ ------ ------ ------ ------ ------ //

    /**
     * This function gets called when no other function matches;
     */
    fallback () external{
        require(msg.data.length == 0); // We fail on wrong calls to other functions
    }

    receive () payable external{
        // Receive ETH to fund the faucet
    }

    // ------ ------ ------ ------ ------ ------ //
    // ------ Funding a potential participant ----- //
    // ------ ------ ------ ------ ------ ------ //

    /**
    * Allows to fund a participant with the required gas fees and token to enable a direct start of the survey
    * @param tokenContract The contract that represents the token for the survey the participant wants to participate
    * @param accountToFund The account that needs funding
    * @param gasFeeAmountGwei The amount to send to the participant based on current gas prices in Gwei
    */
    function fundParticipant(address tokenContract, address accountToFund, uint256 gasFeeAmountGwei) external {
        require(msg.sender == owner, "Only the owner of the contract is able to distribute funds");
        if(gasFundsAllowance[tokenContract][accountToFund] < 1){
            // Send some gas to the potential participant, as none was claimed before
            (payable(accountToFund)).transfer(gasFeeAmountGwei * 1000000000); // Send the gas fee in Wei
            gasFundsAllowance[tokenContract][accountToFund] = 1;
            emit FundsAdded(tokenContract, accountToFund);
        }
        if(tokenAllowance[tokenContract][accountToFund] < 1){
             IERC20 token = IERC20(tokenContract);
            //require(token.balanceOf(address(this)) > 0, "The faucet for this token is empty.");
            token.transfer(accountToFund, 1);
            tokenAllowance[tokenContract][accountToFund] = 1;    // Update the allowance)
            emit TokenAdded(tokenContract, accountToFund);
        }
    }

}

