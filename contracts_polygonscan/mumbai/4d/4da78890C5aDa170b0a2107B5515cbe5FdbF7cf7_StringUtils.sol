// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

library StringUtils {
  function equals(string memory self, string memory b) public pure returns (bool) {
    return (keccak256(bytes(self)) == keccak256(bytes(b)));
  }
}

