// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {ILiquidationEngine} from '@opendollar/interfaces/ILiquidationEngine.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';
import {Assertions} from '@opendollar/libraries/Assertions.sol';
import {ODSaviour} from '../../src/contracts/ODSaviour.sol';
import {ISAFESaviour} from '../../src/interfaces/ISAFESaviour.sol';
import {IODSaviour} from '../../src/interfaces/IODSaviour.sol';
import {SetUp} from './SetUp.sol';
import {ISAFEEngine} from './SetUp.sol';
import {OracleRelayerForTest} from '../mock-contracts/OracleRelayerForTest.sol';
import {IModifiablePerCollateral} from '@opendollar/interfaces/utils/IModifiablePerCollateral.sol';

contract ODSaviourSetUp is SetUp {
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
      vault721: address(vault721),
      oracleRelayer: oracleRelayer,
      collateralJoinFactory: address(collateralJoinFactory)
    });
    saviour = new ODSaviour(saviourInit);

    for (uint256 i; i < _cTypes.length; i++) {
      saviour.initializeCollateralType(_cTypes[i], abi.encode(_tokens[i]));
    }

    saviour.modifyParameters('saviourTreasury', abi.encode(saviourTreasury));

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

contract UnitODSaviourVaultData is ODSaviourSetUp {
  function setUp() public override {
    super.setUp();

    collateralToken.mint(saviourTreasury, 100 ether);
  }

  modifier happyPath() {
    vm.prank(aliceProxy);
    safeManager.protectSAFE(vaultId, address(saviour));
    vm.prank(saviourTreasury);
    saviour.modifyParameters('setVaultStatus', abi.encode(vaultId, true));
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.prank(aliceProxy);
    safeManager.allowSAFE(vaultId, address(saviour), true);
    _;
  }

  function test_VaultData_TreasuryBalance() public happyPath {
    IODSaviour.VaultData memory vData = saviour.vaultData(vaultId);
    assertEq(vData.treasuryBalance, 100 ether);
  }
  /**
   * uint256 vaultId;
   *   bool allowed;
   *   bool enabled;
   *   address vaultCtypeTokenAddress;
   *   uint256 saviourAllowance;
   *   bool isChosenSaviour;
   *   bool treasuryBalance;
   */

  function test_VaultData_False_NotAllowed() public {
    vm.prank(aliceProxy);
    safeManager.protectSAFE(vaultId, address(saviour));
    vm.prank(saviourTreasury);
    saviour.modifyParameters('setVaultStatus', abi.encode(vaultId, true));
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);

    IODSaviour.VaultData memory saftey = saviour.vaultData(vaultId);

    assertEq(saftey.treasuryBalance, 100 ether);
    assertFalse(saftey.isAllowed);
    assertTrue(saftey.isEnabled);
    assertTrue(saftey.saviourAllowance != 0);
    assertTrue(saftey.isChosenSaviour);
    assertEq(saftey.vaultCtypeTokenAddress, address(collateralToken));
  }

  function test_VaultData_False_NoAllowance() public {
    vm.prank(aliceProxy);
    safeManager.protectSAFE(vaultId, address(saviour));
    vm.prank(saviourTreasury);
    saviour.modifyParameters('setVaultStatus', abi.encode(vaultId, true));
    vm.prank(aliceProxy);
    safeManager.allowSAFE(vaultId, address(saviour), true);
    IODSaviour.VaultData memory saftey = saviour.vaultData(vaultId);
    assertEq(saftey.treasuryBalance, 100 ether);
    assertTrue(saftey.isAllowed);
    assertTrue(saftey.isEnabled);
    assertTrue(saftey.saviourAllowance == 0);
    assertTrue(saftey.isChosenSaviour);
    assertEq(saftey.vaultCtypeTokenAddress, address(collateralToken));
  }

  function test_VaultData_False_NotEnabled() public {
    vm.prank(aliceProxy);
    safeManager.protectSAFE(vaultId, address(saviour));

    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.prank(aliceProxy);
    safeManager.allowSAFE(vaultId, address(saviour), true);
    IODSaviour.VaultData memory saftey = saviour.vaultData(vaultId);
    assertEq(saftey.treasuryBalance, 100 ether);
    assertTrue(saftey.isAllowed);
    assertFalse(saftey.isEnabled);
    assertTrue(saftey.saviourAllowance != 0);
    assertTrue(saftey.isChosenSaviour);
    assertEq(saftey.vaultCtypeTokenAddress, address(collateralToken));
  }

  function test_VaultData_False_NotProtected() public {
    vm.prank(saviourTreasury);
    saviour.modifyParameters('setVaultStatus', abi.encode(vaultId, true));
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.prank(aliceProxy);
    safeManager.allowSAFE(vaultId, address(saviour), true);
    IODSaviour.VaultData memory saftey = saviour.vaultData(vaultId);
    assertEq(saftey.treasuryBalance, 100 ether);
    assertTrue(saftey.isAllowed);
    assertTrue(saftey.isEnabled);
    assertTrue(saftey.saviourAllowance != 0);
    assertFalse(saftey.isChosenSaviour);
    assertEq(saftey.vaultCtypeTokenAddress, address(collateralToken));
  }

  function test_VaultData_False_WrongCType() public {
    vm.startPrank(aliceProxy);
    uint256 newVaultId = safeManager.openSAFE('TKN', aliceProxy);
    safeManager.protectSAFE(newVaultId, address(saviour));
    safeManager.allowSAFE(newVaultId, address(saviour), true);
    vm.expectRevert(
      abi.encodeWithSelector(IODSaviour.UninitializedCollateral.selector, bytes32(abi.encodePacked('TKN')))
    );
    IODSaviour.VaultData memory saftey = saviour.vaultData(newVaultId);
  }
}

contract UnitOdSaviourSaviourIsReady is ODSaviourSetUp {
  function test_SaviourIsReady_True() public {
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    assertTrue(saviour.saviourIsReady(ARB));
  }

  function test_SaviourIsReady_False_NoAllowance() public {
    assertFalse(saviour.saviourIsReady(ARB));
  }

  function test_SaviourIsReady_False_NotAChosenSafe() public {
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.mockCall(
      address(liquidationEngine),
      abi.encodeWithSelector(ILiquidationEngine.safeSaviours.selector, address(saviour)),
      abi.encode(0)
    );
    assertFalse(saviour.saviourIsReady(ARB));
  }
}

contract UnitODSaviourDeployment is ODSaviourSetUp {
  function test_Set_LiquidationEngine() public {
    assertEq(address(saviour.liquidationEngine()), address(liquidationEngine));
  }

  function test_Set_Vault721() public {
    assertEq(address(saviour.vault721()), address(vault721));
  }

  function test_Set_Vault721_RevertNullAddress() public {
    saviourInit.vault721 = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_OracleRelayer() public {
    assertEq(address(saviour.oracleRelayer()), address(oracleRelayer));
  }

  function test_Set_OracleRelayer_RevertNullAddress() public {
    saviourInit.oracleRelayer = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_SafeManager() public {
    assertEq(address(saviour.safeManager()), address(safeManager));
  }

  function test_Set_SafeEngine() public {
    assertEq(address(saviour.safeEngine()), address(safeEngine));
  }

  function test_Set_CollateralJoinFactory() public {
    assertEq(address(saviour.collateralJoinFactory()), address(collateralJoinFactory));
  }

  function test_Set_CollateralJoinFactory_RevertNullAddress() public {
    saviourInit.collateralJoinFactory = address(0);
    vm.expectRevert(Assertions.NullAddress.selector);
    saviour = new ODSaviour(saviourInit);
  }

  function test_Set_LiquidatorReward() public {
    assertEq(saviour.liquidatorReward(), 0);
  }

  function test_Set_SaviourTokens() public {
    assertEq(saviour.cType(ARB), address(collateralToken));
  }
}

contract UnitODSaviourModifyParameters is ODSaviourSetUp {
  function test_ModifyParameters_SetVaultStatus() public {
    vm.prank(aliceProxy);
    uint256 safeId = safeManager.openSAFE(ARB, aliceProxy);
    vm.startPrank(saviourTreasury);
    saviour.modifyParameters('setVaultStatus', abi.encode(safeId, true));
    assertTrue(saviour.isVaultEnabled(safeId));
    saviour.modifyParameters('setVaultStatus', abi.encode(safeId, false));
    assertFalse(saviour.isVaultEnabled(safeId));
  }

  function test_ModifyParameters_SetVaultStatus_Revert() public {
    uint256 safeId = 3;
    vm.prank(saviourTreasury);
    vm.expectRevert(abi.encodeWithSelector(IODSaviour.UninitializedCollateral.selector, bytes32(0)));
    saviour.modifyParameters('setVaultStatus', abi.encode(safeId, true));
    assertFalse(saviour.isVaultEnabled(safeId));
  }

  function test_ModifyParameters_liquidatorReward() public {
    vm.startPrank(saviourTreasury);
    saviour.modifyParameters('liquidatorReward', abi.encode(10 ether));
    assertEq(saviour.liquidatorReward(), 10 ether);
  }

  function test_ModifyParameters_saviourTreasury() public {
    vm.startPrank(saviourTreasury);
    saviour.modifyParameters('saviourTreasury', abi.encode(address(2)));
    assertEq(saviour.saviourTreasury(), address(2));
  }
}

contract UnitODSaviourModifiablePerCollateral is ODSaviourSetUp {
  function test_ModifyParameters_PerCollateral_SaviourToken() public {
    vm.prank(saviourTreasury);
    saviour.modifyParameters(ARB, 'saviourToken', abi.encode(address(1)));
    assertEq(address(saviour.cType(ARB)), address(1));
  }

  function test_ModifyParameters_PerCollateral_SaviourToken_Revert_MustBeInitialized() public {
    vm.prank(saviourTreasury);
    vm.expectRevert(
      abi.encodeWithSelector(IODSaviour.CollateralMustBeInitialized.selector, bytes32(abi.encodePacked('BOO')))
    );
    saviour.modifyParameters('BOO', 'saviourToken', abi.encode(address(1)));
  }

  function test__initializeCollateralType() public {
    vm.prank(saviourTreasury);
    saviour.initializeCollateralType('BOO', abi.encode(address(1)));
    assertEq(address(saviour.cType('BOO')), address(1));
  }

  function test__initializeCollateralType_Revert_AlreadyInitialized() public {
    vm.prank(saviourTreasury);
    vm.expectRevert(abi.encodeWithSelector(IModifiablePerCollateral.CollateralTypeAlreadyInitialized.selector));
    saviour.initializeCollateralType(ARB, abi.encode(address(1)));
  }
}

contract UnitODSaviourSaveSafe is ODSaviourSetUp {
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

    collateralToken.mint(saviourTreasury, 100 ether);
    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);

    liquidation = Liquidation({
      accumulatedRate: _ray(10 ether),
      debtFloor: 10_000,
      liquidationPrice: _ray(2 ether), // orcale returns 1 ether as price
      safeCollateral: 10 ether,
      safeDebt: 10 ether,
      onAuctionSystemCoinLimit: 100 ether,
      currentOnAuctionSystemCoins: 10 ether,
      liquidationPenalty: 20_000,
      liquidationQuantity: 1 ether
    });

    vm.prank(aliceProxy);
    safeManager.allowSAFE(vaultId, address(saviour), true);
  }

  event Liquidate(
    bytes32 indexed _cType,
    address indexed _safe,
    uint256 _collateralAmount,
    uint256 _debtAmount,
    uint256 _amountToRaise,
    address _collateralAuctioneer,
    uint256 _auctionId
  );

  function testLiquidateSafe() public {
    liquidation.accumulatedRate = _rad(1 ether);
    vm.startPrank(aliceProxy);
    collateralToken.mint(100 ether);
    collateralToken.approve(address(collateralChild), type(uint256).max);
    collateralChild.join(safeHandler, 10 ether);
    vm.mockCall(taxCollector, abi.encodeWithSignature('taxSingle(bytes32)', ARB), abi.encode(0));
    safeManager.modifySAFECollateralization(
      vaultId, int256(liquidation.safeCollateral), int256(liquidation.safeDebt), false
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
          debtAmount: liquidation.safeDebt,
          lockedAmount: liquidation.safeCollateral,
          accumulatedRate: liquidation.accumulatedRate,
          safetyPrice: _ray(1 ether),
          liquidationPrice: liquidation.liquidationPrice
        })
      )
    );
    //     struct SAFEEngineCollateralData {
    //   // Total amount of debt issued by the collateral type
    //   uint256 /* WAD */ debtAmount;
    //   // Total amount of collateral locked in SAFEs using the collateral type
    //   uint256 /* WAD */ lockedAmount;
    //   // Accumulated rate of the collateral type
    //   uint256 /* RAY */ accumulatedRate;
    //   // Floor price at which a SAFE is allowed to generate debt
    //   uint256 /* RAY */ safetyPrice;
    //   // Price at which a SAFE gets liquidated
    //   uint256 /* RAY */ liquidationPrice;
    // }

    vm.expectEmit();
    emit Liquidate(
      0x4152420000000000000000000000000000000000000000000000000000000000,
      0x8e395224D77551f0aB8C558962240DAfE755bd36,
      1,
      1,
      1_000_000_000_000_000_000_000_000_000,
      0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f,
      123_456
    );
    //attempts to save but the saviour doesn't have enough funds.
    liquidationEngine.liquidateSAFE(ARB, safeHandler);
    assertEq(safeEngine.safes(ARB, safeHandler).lockedCollateral, 9.999999999999999999 ether);
    assertEq(safeEngine.safes(ARB, safeHandler).generatedDebt, 9.999999999999999999 ether);
  }

  function test_SaveSafe() public {
    uint256 startingSaviourBalance = collateralToken.balanceOf(saviourTreasury);
    assertEq(startingSaviourBalance, 100 ether);
    vm.startPrank(aliceProxy);
    collateralToken.mint(10 ether);
    collateralToken.approve(address(collateralChild), type(uint256).max);
    collateralChild.join(safeHandler, 10 ether);
    vm.mockCall(taxCollector, abi.encodeWithSignature('taxSingle(bytes32)', ARB), abi.encode(0));
    safeManager.modifySAFECollateralization(
      vaultId, int256(liquidation.safeCollateral), int256(liquidation.safeDebt), false
    );
    vm.stopPrank();

    uint256 safeStartingCollateralBalance = safeEngine.safes(ARB, safeHandler).lockedCollateral;
    assertEq(collateralToken.balanceOf(address(saviour)), 0);

    // _notSafeBool = _safeCollateral * _liquidationPrice < _safeDebt * _accumulatedRate;

    vm.prank(saviourTreasury);
    collateralToken.approve(address(saviour), type(uint256).max);
    vm.mockCall(
      address(safeEngine),
      abi.encodeWithSelector(ISAFEEngine.cData.selector, ARB),
      abi.encode(
        ISAFEEngine.SAFEEngineCollateralData({
          debtAmount: liquidation.safeDebt,
          lockedAmount: liquidation.safeCollateral,
          accumulatedRate: liquidation.accumulatedRate,
          safetyPrice: _ray(1 ether),
          liquidationPrice: liquidation.liquidationPrice
        })
      )
    );
    vm.expectEmit(true, true, false, true);
    emit SafeSaved(vaultId, 90 ether);
    liquidationEngine.liquidateSAFE(ARB, safeHandler);
    assertEq(safeEngine.safes(ARB, safeHandler).lockedCollateral, safeStartingCollateralBalance + 90 ether);
    assertEq(safeEngine.safes(ARB, safeHandler).generatedDebt, liquidation.safeDebt);
    assertEq(collateralToken.balanceOf(saviourTreasury), startingSaviourBalance - 90 ether);
  }

  /// test that safe is liquidated without saviour

  /// using same conditions that created successful liquidation, add saviour to test liquidation averted

  /// use static test pattern to create fuzz tests
}
