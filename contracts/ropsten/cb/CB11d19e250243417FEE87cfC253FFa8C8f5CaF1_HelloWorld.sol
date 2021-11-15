pragma solidity >=0.4.22 <0.8.0;


contract HelloWorld {
  
  string public message;
  
  function helloWorld(string memory myMessage) public {
    message = myMessage;
  }

  function getMessage() view public returns(string memory){
    return message;
  }

}

