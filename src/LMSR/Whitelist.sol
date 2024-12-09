// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelist is Ownable {

  event UsersAddedToWhitelist(address[] users);
  event UsersRemovedFromWhitelist(address[] users);

  mapping(address => bool) public isWhitelisted;

    constructor() Ownable(msg.sender) {}


  function addToWhitelist(address[] calldata users) onlyOwner external {
    for (uint i = 0; i < users.length; i++) {
      isWhitelisted[users[i]] = true;
    }
    emit UsersAddedToWhitelist(users);
  }

  function removeFromWhitelist(address[] calldata users) onlyOwner external {
    for (uint i = 0; i < users.length; i++) {
      isWhitelisted[users[i]] = false;
    }
    emit UsersRemovedFromWhitelist(users);
  }
}