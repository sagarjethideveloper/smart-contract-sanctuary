pragma solidity ^0.8.0;



library mylib { 
    struct Data {
        mapping(uint => bool) flags;
    }
    function doTrue(Data storage self,uint256 value) public returns(bool){
        self.flags[value]=true;
        return true;
    }
    function doFalse(Data storage self,uint256 value) public returns(bool){
        self.flags[value]=false;
        return false;
    }
}

