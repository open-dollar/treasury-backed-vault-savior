// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';
import {Assertions} from '@opendollar/libraries/Assertions.sol';
import {ODSaviour} from '../src/contracts/ODSaviour.sol';
import {ISAFESaviour} from '../src/interfaces/ISAFESaviour.sol';
import {IODSaviour} from '../src/interfaces/IODSaviour.sol';
import {SetUp} from './SetUp.sol';
import {ISAFEEngine} from './SetUp.sol';
import {OracleRelayerForTest} from './mock-contracts/OracleRelayerForTest.sol';
import 'forge-std/console2.sol';

contract ODSaviour_SetUp is SetUp {
  ODSaviour public saviour;
  address public saviourTreasury = _mockContract('saviourTreasury');
  address public protocolGovernor = _mockContract('protocolGovernor');

  address public oracleRelayer;
  IODSaviour.SaviourInit public saviourInit;

  function setUp() public virtual override {
    super.setUp();
    vm.startPrank(deployer);
    bytes32[] memory _cTypes = new bytes32[](1);
    _cTypes[0] = ARB;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(collateralToken);

    oracleRelayer = address(new OracleRelayerForTest());

    saviourInit = IODSaviour.SaviourInit({
      saviourTreasury: saviourTreasury,
      protocolGovernor: protocolGovernor,
      vault721: address(vault721),
      oracleRelayer: oracleRelayer,
      collateralJoinFactory: address(collateralJoinFactory),
      cTypes: _cTypes,
      saviourTokens: _tokens,
      liquidatorReward: 0
    });

    saviour = new ODSaviour(saviourInit);

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

contract UnitODSaviourDeployment is ODSaviour_SetUp {
  function test_Set_LiquidationEngine() public view {
    assertEq(address(saviour.liquidationEngine()), address(liquidationEngine));
  }

  function test_Set_SaviourTreasury() public view {
    assertEq(address(saviour.saviourTreasury()), address(saviourTreasury));
  }

  function test_Set_SaviourTreasury_RevertNullAddress() public {
    saviourInit.saviourTreasury = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_ProtocolGovernor() public view {
    assertEq(address(saviour.protocolGovernor()), address(protocolGovernor));
  }

  function test_Set_ProtocolGovernor_RevertNullAddress() public {
    saviourInit.protocolGovernor = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_Vault721() public view {
    assertEq(address(saviour.vault721()), address(vault721));
  }

  function test_Set_Vault721_RevertNullAddress() public {
    saviourInit.vault721 = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_OracleRelayer() public view {
    assertEq(address(saviour.oracleRelayer()), address(oracleRelayer));
  }

  function test_Set_OracleRelayer_RevertNullAddress() public {
    saviourInit.oracleRelayer = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_SafeManager() public view {
    assertEq(address(saviour.safeManager()), address(safeManager));
  }

  function test_Set_SafeEngine() public view {
    assertEq(address(saviour.safeEngine()), address(safeEngine));
  }

  function test_Set_CollateralJoinFactory() public view {
    assertEq(address(saviour.collateralJoinFactory()), address(collateralJoinFactory));
  }

  function test_Set_CollateralJoinFactory_RevertNullAddress() public {
    saviourInit.collateralJoinFactory = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_LiquidatorReward() public view {
    assertEq(saviour.liquidatorReward(), 0);
  }

  function test_Set_SaviourTokens() public view {
    assertEq(saviour.cType(ARB), address(collateralToken));
  }

  function test_Set_SaviourTokens_Revert_LengthMismatch() public {
    bytes32[] memory _mismatchTypes = new bytes32[](3);
    saviourInit.cTypes = _mismatchTypes;
    vm.expectRevert(IODSaviour.LengthMismatch.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_SaviourTokens_Revert_NullAddress() public {
    address[] memory _nullToken = new address[](1);
    _nullToken[0] = address(0);

    saviourInit.saviourTokens = _nullToken;
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }
}

contract UnitODSaviourSaveSafe is ODSaviour_SetUp {
  event SafeSaved(uint256 _vaultId, uint256 _reqCollateral);

  address public safeHandler;

  struct Liquidation {
    uint256 accumulatedRate;
    uint256 debtFloor;
    uint256 liquidationPrice;
    uint256 safeCollateral;
    uint256 safeDebt;
    uint256 onAuctionSystemCoinLimit;
    uint256 currentOnAuctionSystemCoins;
    uint256 liquidationPenalty;
    uint256 liquidationQuantity;
  }

  Liquidation public liquidation;

  function setUp() public override {
    super.setUp();
    safeHandler = safeManager.safeData(vaultId).safeHandler;
    vm.prank(aliceProxy);
    safeManager.protectSAFE(vaultId, address(saviour));
    vm.prank(saviourTreasury);
    saviour.modifyParameters('setVaultStatus', abi.encode(vaultId, true));

    collateralToken.mint(saviourTreasury, 10_000_000_000_000_000_000_000_000 ether);
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
  }

  function testLiquidateSafe() public {
    // _notSafeBool = _safeCollateral * _liquidationPrice < _safeDebt * _accumulatedRate;
    liquidation = Liquidation({
      accumulatedRate: _ray(10),
      debtFloor: 10_000,
      liquidationPrice: 30_000,
      safeCollateral: 1 ether,
      safeDebt: 10 ether,
      onAuctionSystemCoinLimit: 100 ether,
      currentOnAuctionSystemCoins: 10 ether,
      liquidationPenalty: 20_000,
      liquidationQuantity: 1 ether
    });
    vm.startPrank(aliceProxy);
    collateralToken.mint(100 ether);
    collateralToken.approve(address(collateralChild), type(uint256).max);
    collateralChild.join(safeHandler, 10 ether);
    vm.mockCall(taxCollector, abi.encodeWithSignature('taxSingle(bytes32)', ARB), abi.encode(0));
    safeManager.modifySAFECollateralization(
      vaultId, int256(liquidation.safeDebt), int256(liquidation.safeCollateral), false
    );
    uint256 safeStartingCollateralBalance = safeEngine.safes(ARB, safeHandler).lockedCollateral;
    vm.stopPrank();
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.mockCall(
      address(safeEngine),
      abi.encodeWithSelector(ISAFEEngine.cData.selector, ARB),
      abi.encode(
        ISAFEEngine.SAFEEngineCollateralData({
          debtAmount: 1_000_000_000_000_000_000,
          lockedAmount: 10_000_000_000_000_000_000,
          accumulatedRate: _rad(1000),
          safetyPrice: 1_000_000_000_000_000_000_000_000_000,
          liquidationPrice: _rad(1)
        })
      )
    );
    // vm.mockCall(mockCollateralAuctionHouse, abi.encodeWithSelector(CollateralAuctionHouseForTest, arg));
    vm.expectEmit(true, false, false, false);
    emit SafeSaved(vaultId, 1 ether);
    liquidationEngine.liquidateSAFE(ARB, safeHandler);
  }

  function test_SaveSafe() public {
    // _notSafeBool = _safeCollateral * _liquidationPrice < _safeDebt * _accumulatedRate;
    liquidation = Liquidation({
      accumulatedRate: _ray(10),
      debtFloor: 10_000,
      liquidationPrice: 30_000,
      safeCollateral: 1 ether,
      safeDebt: 10 ether,
      onAuctionSystemCoinLimit: 100 ether,
      currentOnAuctionSystemCoins: 10 ether,
      liquidationPenalty: 20_000,
      liquidationQuantity: 1 ether
    });
    vm.startPrank(aliceProxy);
    collateralToken.mint(100 ether);
    collateralToken.approve(address(collateralChild), type(uint256).max);
    collateralChild.join(safeHandler, 10 ether);
    vm.mockCall(taxCollector, abi.encodeWithSignature('taxSingle(bytes32)', ARB), abi.encode(0));
    safeManager.modifySAFECollateralization(
      vaultId, int256(liquidation.safeDebt), int256(liquidation.safeCollateral), false
    );
    uint256 safeStartingCollateralBalance = safeEngine.safes(ARB, safeHandler).lockedCollateral;
    vm.stopPrank();
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.mockCall(
      address(safeEngine),
      abi.encodeWithSelector(ISAFEEngine.cData.selector, ARB),
      abi.encode(
        ISAFEEngine.SAFEEngineCollateralData({
          debtAmount: 1_000_000_000_000_000_000,
          lockedAmount: 10_000_000_000_000_000_000,
          accumulatedRate: _rad(1000),
          safetyPrice: 1_000_000_000_000_000_000_000_000_000,
          liquidationPrice: _rad(1)
        })
      )
    );
    // vm.mockCall(mockCollateralAuctionHouse, abi.encodeWithSelector(CollateralAuctionHouseForTest, arg));
    vm.expectEmit(true, false, false, false);
    emit SafeSaved(vaultId, 1 ether);
    liquidationEngine.liquidateSAFE(ARB, safeHandler);
  }

  /// test that safe is liquidated without saviour

  /// using same conditions that created successful liquidation, add saviour to test liquidation averted

  /// use static test pattern to create fuzz tests
}
