// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';
import {ODSaviour} from '../src/contracts/ODSaviour.sol';
import {ISAFESaviour} from '../src/interfaces/ISAFESaviour.sol';
import {IODSaviour} from '../src/interfaces/IODSaviour.sol';
import {SetUp} from './SetUp.sol';

contract ODSaviourSetUp is SetUp {
  ODSaviour public saviour;
  address public saviourTreasury = _mockContract('saviourTreasury');
  address public protocolGovernor = _mockContract('protocolGovernor');
  address public oracleRelayer = _mockContract('oracleRelayer');

  function setUp() public override {
    super.setUp();
    bytes32[] memory _cTypes = new bytes32[](1);
    _cTypes[0] = ARB;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(collateralToken);

    IODSaviour.SaviourInit memory _saviourInit = IODSaviour.SaviourInit({
      saviourTreasury: saviourTreasury,
      protocolGovernor: protocolGovernor,
      vault721: address(vault721),
      oracleRelayer: oracleRelayer,
      collateralJoinFactory: address(collateralJoinFactory),
      cTypes: _cTypes,
      saviourTokens: _tokens,
      liquidatorReward: 1 ether
    });

    saviour = new ODSaviour(_saviourInit);

    IOracleRelayer.OracleRelayerCollateralParams memory oracleCParams = IOracleRelayer.OracleRelayerCollateralParams({
      oracle: IDelayedOracle(address(1)),
      safetyCRatio: 1.25e27,
      liquidationCRatio: 1.2e27
    });

    vm.mockCall(
      oracleRelayer, abi.encodeWithSelector(IOracleRelayer.cParams.selector, bytes32(0)), abi.encode(oracleCParams)
    );
    vm.mockCall(address(1), abi.encodeWithSelector(IBaseOracle.read.selector), abi.encode(1 ether));
    liquidationEngine.connectSAFESaviour(address(saviour));
    vm.stopPrank();
  }
}

contract TestODSaviourDeployment is ODSaviourSetUp {
  function test_ODSaviour_Depolyment() public {
    assertEq(saviour.liquidationEngine(), address(liquidationEngine));
  }
}
