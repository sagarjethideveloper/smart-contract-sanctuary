// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract DirectTest {
  

    constructor(){}

    function testRangeFunctionForDirectSwap(uint tokenInValue,uint tokenOutValue) external pure returns(bool){
        return (tokenInValue/tokenOutValue)+(tokenOutValue/tokenInValue)==1;
    }

  

}

