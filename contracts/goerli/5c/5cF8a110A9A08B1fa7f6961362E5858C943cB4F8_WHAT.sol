// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.8.0;

contract WHAT {

    bytes32 public chainId;
    bytes32 public chainId2;

    constructor(        
        bytes32 _chainId
    ) {
        bytes memory initParams = abi.encode(
            _chainId
        );
        setUp(initParams);
    }

    function setUp(bytes memory initParams) public {
        (            
            bytes32 _chainId
        ) = abi.decode(initParams, (bytes32));

        chainId = _chainId;
        chainId2 = bytes32(uint256(80001));
    }

    function check() public view returns(bool){
        return chainId == chainId2;
    }

    function c1() public view returns(bytes32){
        return chainId;
    }

    function c2() public view returns(bytes32){
        return chainId2;
    }

}

