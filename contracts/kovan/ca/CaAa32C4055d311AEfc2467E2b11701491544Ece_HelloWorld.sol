pragma solidity >=0.4.16 <0.9.0;

contract HelloWorld {

    string public message;

    constructor(string memory initMessage) public {
        message = initMessage;
    }

    function update(string memory newMessage) public {
        message = newMessage;
    }
}

