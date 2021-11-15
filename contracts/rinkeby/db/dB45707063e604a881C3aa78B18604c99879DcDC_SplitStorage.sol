// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

/**
 * @title SplitStorage
 * @author MirrorXYZ
 * @notice Modified by NA. Use at your own risk
 */
contract SplitStorage {
    bytes32 public merkleRoot;
    uint256 public currentWindow;
    address internal _splitter;
    uint256[] public balanceForWindow;
    mapping(bytes32 => bool) internal claimed;
    uint256 internal depositedInWindow;
    
    address public owner;

    /// @notice Do not forget to change these according to network you are deploying to
    address internal immutable wethAddress = 0xc778417E063141139Fce010982780140Aa0cD5Ab; 
    address internal immutable zoraMedia = 0x85e946e1Bd35EC91044Dc83A5DdAB2B6A262ffA6;
}

