// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ImplementationV2 {
    uint256 public anotherNum;
    uint256 public num;
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    function increment(uint256 _num) public {
        anotherNum += _num;
    }
}

