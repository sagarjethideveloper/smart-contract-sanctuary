pragma solidity ^0.6.6;

contract Equation{

    function equation () public returns (uint256) {

        bytes32 predictableRandom = keccak256(abi.encodePacked( blockhash(block.number-1), msg.sender, address(this) ));
           //bytes2 equation = bytes2(predictableRandom[0]) | ( bytes2(predictableRandom[1]) >> 8 ) | ( bytes2(predictableRandom[2]) >> 16 );
        uint256 base = 35+((55*uint256(uint8(predictableRandom[3])))/255);



     uint256 _number = 35+((55*uint256(uint8(predictableRandom[3])))/255) / 2;

     uint256 equationResult = ((_number / base) % base);

     return equationResult;
    }
}

