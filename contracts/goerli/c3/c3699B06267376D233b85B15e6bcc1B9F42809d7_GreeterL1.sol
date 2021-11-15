// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;


contract GreeterL1 {
  string greeting;
  // constructor(string memory _greeting) {
  //   // console.log("Deploying a Greeter with greeting:", _greeting);
  //   greeting = _greeting;
  // }

  // constructor() {
  //   greeting = 'Hello, World';
  // }

  function greet() public view returns (string memory) {
    return greeting;
  }

  function setGreeting(string memory _greeting) public {
    greeting = _greeting;
  }
}

