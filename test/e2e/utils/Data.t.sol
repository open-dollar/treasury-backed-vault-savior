// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ODSaviour} from 'src/contracts/ODSaviour.sol';

contract Data {
  uint256 public constant TREASURY_AMOUNT = 1_000_000_000_000_000_000_000_000_000 ether;
  uint256 public constant PROTOCOL_AMOUNT = 1_000_000_000 ether;
  uint256 public constant USER_AMOUNT = 1000 ether;

  ODSaviour public saviour;
  address public treasury;

  address public aliceProxy;
  address public bobProxy;
  address public deployerProxy;

  mapping(address proxy => uint256 safeId) public vaults;
}
