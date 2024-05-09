// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {LiquidationEngine, ILiquidationEngine} from '@opendollar/contracts/LiquidationEngine.sol';
import {CollateralAuctionHouse, ICollateralAuctionHouse} from '@opendollar/contracts/CollateralAuctionHouse.sol';
import {Authorizable} from '@opendollar/contracts/utils/Authorizable.sol';

contract ODSaviour is Authorizable {
  constructor() {}

  function enableVault(uint256 _tokenId) external {}
}
