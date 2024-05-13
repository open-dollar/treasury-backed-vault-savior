// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';

contract OracleRelayerForTest {
  struct OracleRelayerParams {
    // Upper bound for the per-second redemption rate
    uint256 /* RAY */ redemptionRateUpperBound;
    // Lower bound for the per-second redemption rate
    uint256 /* RAY */ redemptionRateLowerBound;
  }

  struct OracleRelayerCollateralParams {
    // Usually a DelayedOracle that enforces delays to fresh price feeds
    IDelayedOracle /* */ oracle;
    // CRatio used to compute the 'safePrice' - the price used when generating debt in SAFEEngine
    uint256 /* RAY    */ safetyCRatio;
    // CRatio used to compute the 'liquidationPrice' - the price used when liquidating SAFEs
    uint256 /* RAY    */ liquidationCRatio;
  }

  constructor() {}

  function cParams(bytes32 _cType) external returns (OracleRelayerCollateralParams memory) {
    return OracleRelayerCollateralParams({
      oracle: IDelayedOracle(address(this)),
      safetyCRatio: 1e27,
      liquidationCRatio: 1e27
    });
  }

  function read() external returns (uint256) {
    return 1 ether;
  }
}

// contract OracleRelayerForInternalCallsTest is OracleRelayerForTest {
//   event UpdateRedemptionPriceCalled();
//   event GetRedemptionPriceCalled();

//   constructor(
//     address _safeEngine,
//     IBaseOracle _systemCoinOracle,
//     OracleRelayerParams memory _oracleRelayerParams
//   ) OracleRelayerForTest(_safeEngine, _systemCoinOracle, _oracleRelayerParams) {}

//   function _updateRedemptionPrice() internal override returns (uint256 _redemptionPrice) {
//     emit UpdateRedemptionPriceCalled();
//     return super._updateRedemptionPrice();
//   }

//   function _getRedemptionPrice() internal override returns (uint256 _redemptionPrice) {
//     emit GetRedemptionPriceCalled();
//     return super._getRedemptionPrice();
//   }
// }
