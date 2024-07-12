// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ODProxy} from '@opendollar/contracts/proxies/ODProxy.sol';
import {ISAFEEngine} from '@opendollar/interfaces/ISAFEEngine.sol';
import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {IAuthorizable} from '@opendollar/interfaces/utils/IAuthorizable.sol';
import {DelayedOracleForTest} from '@opendollar/test/mocks/DelayedOracleForTest.sol';
import {Math} from '@opendollar/libraries/Math.sol';
import {ERC20ForTest} from '@opendollar/test/mocks/ERC20ForTest.sol';
import {TKN} from '@opendollar/test/e2e/Common.t.sol';
import {ODSaviour} from 'src/contracts/ODSaviour.sol';
import {IODSaviour} from 'src/interfaces/IODSaviour.sol';
import {SharedSetup, RAD, RAY, WAD} from 'test/e2e/utils/SharedSetup.t.sol';

contract E2ESaviourSetup is SharedSetup {
  function setUp() public virtual override {
    super.setUp();
    treasury = vm.addr(uint256(keccak256('ARB Treasury')));

    IODSaviour.SaviourInit memory _init = IODSaviour.SaviourInit({
      vault721: address(vault721),
      oracleRelayer: address(oracleRelayer),
      collateralJoinFactory: address(collateralJoinFactory)
    });

    saviour = new ODSaviour(_init);
    saviour.modifyParameters('saviourTreasury', abi.encode(treasury));
    saviour.initializeCollateralType(TKN, abi.encode(address(collateral[TKN])));

    _mintTKN(treasury, TREASURY_AMOUNT, address(saviour));
    aliceProxy = _userTKNVaultSetup(alice, USER_AMOUNT, 'AliceProxy');
    bobProxy = _userTKNVaultSetup(bob, USER_AMOUNT, 'BobProxy');
    deployerProxy = _userTKNVaultSetup(deployer, PROTOCOL_AMOUNT, 'DeployerProxy');
  }
}

contract E2ESaviourTestSetup is E2ESaviourSetup {
  function test_Addresses() public view {
    assertEq(saviour.saviourTreasury(), treasury);
    assertEq(saviour.liquidationEngine(), address(liquidationEngine));
  }

  function test_Contracts() public view {
    assertTrue(saviour.vault721() == vault721);
    assertTrue(saviour.oracleRelayer() == oracleRelayer);
    assertTrue(saviour.safeManager() == safeManager);
    assertTrue(saviour.safeEngine() == safeEngine);
    assertTrue(saviour.collateralJoinFactory() == collateralJoinFactory);
  }
}

contract E2ESaviourTestAccessControl is E2ESaviourSetup {
  modifier notZero(bytes32 _b, address _a) {
    vm.assume(_b != bytes32(0));
    vm.assume(_a != address(0));
    _;
  }

  function test_roles() public view {
    assertTrue(IAuthorizable(saviour).authorizedAccounts(treasury));
    assertTrue(IAuthorizable(saviour).authorizedAccounts(address(this)));
  }

  function test_initCType(bytes32 _cType, address _tokenAddress) public notZero(_cType, _tokenAddress) {
    vm.prank(treasury);
    saviour.initializeCollateralType(_cType, abi.encode(_tokenAddress));
    assertTrue(saviour.cType(_cType) == _tokenAddress);
  }

  function test_initCTypeRevert(
    address _attacker,
    bytes32 _cType,
    address _tokenAddress
  ) public notZero(_cType, _tokenAddress) {
    vm.assume(_attacker != treasury);
    vm.assume(_attacker != address(this));
    vm.prank(_attacker);
    vm.expectRevert();
    saviour.initializeCollateralType(_cType, abi.encode(_tokenAddress));
  }

  function test_setLiquidatorReward(uint256 _reward) public {
    saviour.modifyParameters('liquidatorReward', abi.encode(_reward));
    assertTrue(saviour.liquidatorReward() == _reward);
  }

  function test_setLiquidatorRewardRevert(address _attacker, uint256 _reward) public {
    vm.assume(_attacker != address(this));
    vm.prank(_attacker);
    vm.expectRevert();
    saviour.modifyParameters('liquidatorReward', abi.encode(_reward));
  }

  function test_modifyParams() public {
    uint256 _vaultId = 1;
    assertFalse(saviour.isVaultEnabled(_vaultId));
    saviour.modifyParameters('setVaultStatus', abi.encode(_vaultId, true));
    assertTrue(saviour.isVaultEnabled(_vaultId));
  }

  function test_modifyParams(bool _enabled) public {
    uint256 _vaultId = 2;
    saviour.modifyParameters('setVaultStatus', abi.encode(_vaultId, _enabled));
    assertTrue(saviour.isVaultEnabled(_vaultId) == _enabled);
  }

  function test_modifyParamsRevert(address _attacker, uint256 _vaultId, bool _enabled) public {
    vm.assume(_attacker != address(this));
    vm.prank(_attacker);
    vm.expectRevert();
    saviour.modifyParameters('setVaultStatus', abi.encode(_vaultId, _enabled));
  }

  function test_saveSafe(bytes32 _cType, address _safe) public {
    saviour.modifyParameters('setVaultStatus', abi.encode(1, true));
    vm.prank(address(liquidationEngine));
    (bool _ok,,) = saviour.saveSAFE(address(liquidationEngine), _cType, _safe);
    assertTrue(_ok);
  }

  function test_SaveSafe(address _liquidator, bytes32 _cType, address _safe) public {
    vm.prank(address(liquidationEngine));
    (bool _ok,,) = saviour.saveSAFE(_liquidator, _cType, _safe);
    assertTrue(_ok);
  }

  function test_saveSafeRevert(address _attacker, bytes32 _cType, address _safe) public {
    vm.assume(_attacker != address(liquidationEngine));
    vm.assume(_attacker != address(this));
    vm.prank(_attacker);
    vm.expectRevert();
    saviour.saveSAFE(address(liquidationEngine), _cType, _safe);
  }
}

contract E2ESaviourTestRiskSetup is E2ESaviourSetup {
  using Math for uint256;

  uint256 public constant RAY_WAD_DIFF = RAY / WAD;
  uint256 public constant TWO_DECIMAL_OFFSET = 1e2;

  uint256 public constant DEPOSIT = 100 ether;
  uint256 public constant MINT = DEPOSIT / 3 * 2;

  IDelayedOracle public oracle;
  DelayedOracleForTest public tknOracle;

  uint256 public oracleRead; // WAD

  function setUp() public virtual override {
    super.setUp();
    tknOracle = DelayedOracleForTest(address(delayedOracle[TKN]));
    _setAndRefreshData();
    _depositTKNAndGenDebt(vaults[aliceProxy], DEPOSIT, MINT, aliceProxy);
    _depositTKNAndGenDebt(vaults[bobProxy], DEPOSIT, MINT, bobProxy);
    _depositTKNAndGenDebt(vaults[deployerProxy], PROTOCOL_AMOUNT, MINT, deployerProxy);
    oracleRead = oracle.read();
  }

  /**
   * @dev Helper functions
   */
  function _setAndRefreshData() internal {
    aliceNFV = vault721.getNfvState(vaults[aliceProxy]);
    bobNFV = vault721.getNfvState(vaults[bobProxy]);
    cTypeData = safeEngine.cData(TKN);
    liquidationPrice = cTypeData.liquidationPrice;
    accumulatedRate = cTypeData.accumulatedRate;
    oracleParams = oracleRelayer.cParams(TKN);
    liquidationCRatio = oracleParams.liquidationCRatio;
    safetyCRatio = oracleParams.safetyCRatio;
    oracle = oracleParams.oracle;
  }

  function _toFixedPointPercent(uint256 _wad) internal pure returns (uint256 _fixedPtPercent) {
    _fixedPtPercent = _wad / (WAD / TWO_DECIMAL_OFFSET);
  }

  function _readRisk(address _safeHandler) internal view returns (uint256 _riskRatio, int256 _percentOverSafety) {
    (uint256 _collateral, uint256 _debt) = saviour.getCurrentCollateralAndDebt(TKN, _safeHandler);
    _riskRatio = _collateral.wmul(oracle.read()).wdiv(_debt.wmul(accumulatedRate)) / (RAY_WAD_DIFF / TWO_DECIMAL_OFFSET);
    unchecked {
      _percentOverSafety = int256(_riskRatio) - int256((safetyCRatio / RAY_WAD_DIFF) / (WAD / TWO_DECIMAL_OFFSET));
    }
  }
}

contract E2ESaviourTestRisk is E2ESaviourTestRiskSetup {
  function test_EmitLogs() public {
    /// @notice RAY format
    emit log_named_uint('Oracle Read - [to RAY]', oracleRead * RAY_WAD_DIFF);
    emit log_named_uint('Accumulated Rate [RAY]', accumulatedRate);
    emit log_named_uint('SafetyCRatio TKN [RAY]', safetyCRatio);
    emit log_named_uint('LiquidCRatio TKN [RAY]', liquidationCRatio);

    uint256 percentOracleRead = _toFixedPointPercent(oracleRead);
    uint256 percentSafetyCRatio = _toFixedPointPercent(safetyCRatio / RAY_WAD_DIFF);
    uint256 percentLiquidationCRatio = _toFixedPointPercent(liquidationCRatio / RAY_WAD_DIFF);

    /// @notice Fixed point 2-decimal format (nftRenderer format)
    emit log_named_uint('Oracle Read ---- [to %]', percentOracleRead);
    emit log_named_uint('SafetyCRatio TKN [to %]', percentSafetyCRatio);
    emit log_named_uint('LiquidCRatio TKN [to %]', percentLiquidationCRatio);
    assertTrue(percentSafetyCRatio / percentOracleRead > 0);
  }

  function test_oracle() public view {
    IOracleRelayer.OracleRelayerCollateralParams memory _oracleParams = oracleRelayer.cParams(TKN);
    IDelayedOracle _oracle = _oracleParams.oracle;
    assertEq(address(tknOracle), address(_oracle));
  }

  function test_setUp() public view {
    (uint256 _collateral, uint256 _debt) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    assertEq(_collateral, DEPOSIT);
    assertEq(_debt, MINT);
  }

  function test_isAboveRatio() public {
    (uint256 _riskRatio, int256 _percentOverSafety) = _readRisk(aliceNFV.safeHandler);
    emit log_named_uint('Vault   Ratio', _riskRatio);
    emit log_named_int('Percent Above', _percentOverSafety);
  }

  function test_increaseRisk1() public {
    _depositTKNAndGenDebt(vaults[aliceProxy], 0, 0.001 ether, aliceProxy);
    (uint256 _riskRatioAfter, int256 _percentOverSafetyAfter) = _readRisk(aliceNFV.safeHandler);
    emit log_named_uint('Vault   Ratio + 0.001 ether', _riskRatioAfter);
    emit log_named_int('Percent Above + 0.001 ether', _percentOverSafetyAfter);
  }

  function test_increaseRisk2() public {
    _depositTKNAndGenDebt(vaults[aliceProxy], 0, 1 ether, aliceProxy);
    (uint256 _riskRatioAfter, int256 _percentOverSafetyAfter) = _readRisk(aliceNFV.safeHandler);
    emit log_named_uint('Vault   Ratio + 1 ether', _riskRatioAfter);
    emit log_named_int('Percent Above + 1 ether', _percentOverSafetyAfter);
  }

  function test_increaseRisk3() public {
    _depositTKNAndGenDebt(vaults[aliceProxy], 0, 5 ether, aliceProxy);
    (uint256 _riskRatioAfter, int256 _percentOverSafetyAfter) = _readRisk(aliceNFV.safeHandler);
    emit log_named_uint('Vault   Ratio + 5 ether', _riskRatioAfter);
    emit log_named_int('Percent Above + 5 ether', _percentOverSafetyAfter);
  }

  function test_triggerLiquidationScenario() public {
    (uint256 _riskRatioBefore,) = _readRisk(aliceNFV.safeHandler);
    uint256 tknPriceBefore = tknOracle.read();
    tknOracle.setPriceAndValidity(tknPriceBefore - 0.05 ether, true);
    (uint256 _riskRatioAfter,) = _readRisk(aliceNFV.safeHandler);
    assertTrue(_riskRatioBefore > _riskRatioAfter);
  }
}

contract E2ESaviourTestLiquidateSetup is E2ESaviourTestRiskSetup {
  function setUp() public virtual override {
    super.setUp();
    // increase user's vault risk
    _depositTKNAndGenDebt(vaults[aliceProxy], 0, 5 ether, aliceProxy);
    _depositTKNAndGenDebt(vaults[bobProxy], 0, 5 ether, bobProxy);
    // devalue collateral TKN
    tknOracle.setPriceAndValidity(tknOracle.read() - 0.2 ether, true);
    // trigger update of collateral devaluation in safeEngine.cData.liquidationPrice
    _setAndRefreshData();
    oracleRelayer.updateCollateralPrice(TKN);
    _setAndRefreshData();
  }
}

contract E2ESaviourTestLiquidate is E2ESaviourTestLiquidateSetup {
  function test_belowSafety() public {
    (uint256 _riskRatioAfter, int256 _percentOverSafetyAfter) = _readRisk(aliceNFV.safeHandler);
    emit log_named_uint('Vault  Risk  Ratio', _riskRatioAfter);
    emit log_named_int('Percent Difference', _percentOverSafetyAfter);
    // collateralization ratio is negative (under-collateralized)
    assertTrue(0 > _percentOverSafetyAfter);
  }

  function test_safeNotSafe() public {
    (uint256 _collateral, uint256 _debt) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    uint256 collateralValue = _collateral * liquidationPrice;
    uint256 debtValue = _debt * accumulatedRate;
    emit log_named_uint('Collateral X LiquiPrice', collateralValue);
    emit log_named_uint('Debt X AccumulatedPrice', debtValue);
    assertTrue(collateralValue < debtValue);
  }

  function test_liquidateUnprotectedSafes() public {
    liquidationEngine.liquidateSAFE(TKN, aliceNFV.safeHandler);
    liquidationEngine.liquidateSAFE(TKN, bobNFV.safeHandler);
    (uint256 _collateralA, uint256 _debtA) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    (uint256 _collateralB, uint256 _debtB) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);
    assertTrue(_collateralA == 0 && _debtA == 0);
    assertTrue(_collateralB == 0 && _debtB == 0);
  }
}

contract E2ESaviourTestLiquidateAndSave is E2ESaviourTestLiquidateSetup {
  ERC20ForTest public token;

  function setUp() public virtual override {
    super.setUp();
    token = ERC20ForTest(saviour.cType(TKN));

    // Protocol DAO to connect saviour
    vm.prank(liquidationEngine.authorizedAccounts()[0]);
    liquidationEngine.connectSAFESaviour(address(saviour));

    // Treasury to approve select protocol vaults as eligible for saving
    saviour.modifyParameters('setVaultStatus', abi.encode(vaults[aliceProxy], true));

    bytes memory payloadAllow = abi.encodeWithSelector(
      basicActions.allowSAFE.selector, address(safeManager), vaults[aliceProxy], address(saviour), true
    );
    // Approve saviour as safe handler
    vm.prank(alice);
    ODProxy(aliceProxy).execute(address(basicActions), payloadAllow);

    bytes memory payloadProtect = abi.encodeWithSelector(
      basicActions.protectSAFE.selector, address(safeManager), vaults[aliceProxy], address(saviour)
    );
    // Proxy to elect saviour to protect vault
    vm.prank(alice);
    ODProxy(aliceProxy).execute(address(basicActions), payloadProtect);

    _setAndRefreshData();
  }

  function test_tokenBals() public view {
    assertEq(token.balanceOf(treasury), TREASURY_AMOUNT);
    assertEq(token.balanceOf(address(saviour)), 0);
    assertEq(token.allowance(treasury, address(saviour)), TREASURY_AMOUNT);
  }

  function test_enabledVault() public view {
    assertTrue(saviour.isVaultEnabled(vaults[aliceProxy]));
  }

  function test_disabledVault() public view {
    assertFalse(saviour.isVaultEnabled(vaults[bobProxy]));
  }

  function test_protectSafe() public view {
    address chosenSaviour = liquidationEngine.chosenSAFESaviour(TKN, aliceNFV.safeHandler);
    assertTrue(address(saviour) == chosenSaviour);
  }

  function test_failToProtectSafe() public {
    vm.prank(bobProxy);
    vm.expectRevert();
    liquidationEngine.protectSAFE(TKN, bobNFV.safeHandler, address(saviour));
  }

  function test_liquidateProtectedSafe() public {
    (uint256 _collateralA, uint256 _debtA) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    assertTrue(_collateralA > 0 && _debtA > 0);
    liquidationEngine.liquidateSAFE(TKN, aliceNFV.safeHandler);
    (uint256 _collateralB, uint256 _debtB) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    assertTrue(_collateralB > _collateralA && _debtB == _debtA);
  }

  function test_liquidateUnprotectedSafe() public {
    (uint256 _collateralA, uint256 _debtA) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);
    assertTrue(_collateralA > 0 && _debtA > 0);
    liquidationEngine.liquidateSAFE(TKN, bobNFV.safeHandler);
    (uint256 _collateralB, uint256 _debtB) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);
    assertTrue(_collateralB == 0 && _debtB == 0);
  }
}

contract E2ESaviourTestFuzz is E2ESaviourTestRiskSetup {
  using Math for uint256;

  ERC20ForTest public token;

  function setUp() public virtual override {
    super.setUp();
    token = ERC20ForTest(saviour.cType(TKN));

    // increase user's vault risk
    _depositTKNAndGenDebt(vaults[aliceProxy], 0, 5 ether, aliceProxy);
    _depositTKNAndGenDebt(vaults[bobProxy], 0, 5 ether, bobProxy);

    // Protocol DAO to connect saviour
    vm.prank(liquidationEngine.authorizedAccounts()[0]);
    liquidationEngine.connectSAFESaviour(address(saviour));

    // Treasury to approve select protocol vaults as eligible for saving
    saviour.modifyParameters('setVaultStatus', abi.encode(vaults[aliceProxy], true));

    bytes memory payloadAllow = abi.encodeWithSelector(
      basicActions.allowSAFE.selector, address(safeManager), vaults[aliceProxy], address(saviour), true
    );
    // Approve saviour as safe handler
    vm.prank(alice);
    ODProxy(aliceProxy).execute(address(basicActions), payloadAllow);

    bytes memory payloadProtect = abi.encodeWithSelector(
      basicActions.protectSAFE.selector, address(safeManager), vaults[aliceProxy], address(saviour)
    );
    // Proxy to elect saviour to protect vault
    vm.prank(alice);
    ODProxy(aliceProxy).execute(address(basicActions), payloadProtect);

    _setAndRefreshData();
  }

  function _devalueCollateral(uint256 _devaluation) internal {
    uint256 _tknPrice = tknOracle.read();
    tknOracle.setPriceAndValidity(_tknPrice - _devaluation, true);
    _setAndRefreshData();
    oracleRelayer.updateCollateralPrice(TKN);
    _setAndRefreshData();
  }

  function test_algorithm(uint256 _devaluation) public {
    _devaluation = bound(_devaluation, 0.1 ether, 1 ether - 1);
    _devalueCollateral(_devaluation);

    (uint256 _currentCollateral, uint256 _currentDebt) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);

    ISAFEEngine.SAFEEngineCollateralData memory _safeEngCData = safeEngine.cData(TKN);
    uint256 _liquidationPrice = _safeEngCData.liquidationPrice;
    uint256 _safetyPrice = _safeEngCData.safetyPrice;

    uint256 _collateralXliquidationPrice = _currentCollateral.wmul(_liquidationPrice);
    uint256 _debtXaccumulatedRate = _currentDebt.wmul(_safeEngCData.accumulatedRate);

    if (_collateralXliquidationPrice < _debtXaccumulatedRate) {
      uint256 _requiredAmount;

      {
        uint256 _collateralDeficit = (_debtXaccumulatedRate - _collateralXliquidationPrice).wdiv(_safetyPrice);
        uint256 _safetyCollateral = _collateralXliquidationPrice.wdiv(_safetyPrice);
        _requiredAmount = _collateralDeficit + _safetyCollateral - _currentCollateral;
      }
      uint256 _newCollateralXliquidationPrice = (_currentCollateral + _requiredAmount).wmul(_liquidationPrice);
      assertTrue(_newCollateralXliquidationPrice > _debtXaccumulatedRate);
    }
  }

  function test_liquidateProtectedSafe(uint256 _devaluation) public {
    _devaluation = bound(_devaluation, 0.1 ether, 1 ether - 1);
    (uint256 _collateralA, uint256 _debtA) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    assertTrue(_collateralA > 0 && _debtA > 0);
    assertTrue((_collateralA * liquidationPrice) >= (_debtA * accumulatedRate));

    _devalueCollateral(_devaluation);
    (uint256 _collateralB, uint256 _debtB) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    if (liquidationPrice != 0 && (_collateralB * liquidationPrice) < (_debtB * accumulatedRate)) {
      liquidationEngine.liquidateSAFE(TKN, aliceNFV.safeHandler);
    }
    (uint256 _collateralC, uint256 _debtC) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    assertTrue(_collateralC >= _collateralA);
    assertEq(_debtC, _debtA);
  }

  function test_liquidateUnprotectedSafe(uint256 _devaluation) public {
    _devaluation = bound(_devaluation, 0.1 ether, 1 ether - 1);
    uint256 _collateralC;
    uint256 _debtC;

    (uint256 _collateralA, uint256 _debtA) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);
    assertTrue(_collateralA > 0 && _debtA > 0);
    assertTrue((_collateralA * liquidationPrice) >= (_debtA * accumulatedRate));

    _devalueCollateral(_devaluation);
    (uint256 _collateralB, uint256 _debtB) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);

    if (liquidationPrice != 0 && (_collateralB * liquidationPrice) < (_debtB * accumulatedRate)) {
      liquidationEngine.liquidateSAFE(TKN, bobNFV.safeHandler);

      (_collateralC, _debtC) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);
      assertTrue(_collateralC == 0 && _debtC == 0);
    } else {
      (_collateralC, _debtC) = saviour.getCurrentCollateralAndDebt(TKN, bobNFV.safeHandler);
      assertTrue(_collateralC == _collateralA && _debtC == _debtA);
    }
  }

  /**
   * @dev `emit log_named_[dataType]` does not work for fuzz tests, only static tests
   * static tests added below for logging outputs
   */
  function test_algorithm_static() public {
    uint256 _devaluation = 0.15 ether;
    _devalueCollateral(_devaluation);

    ISAFEEngine.SAFEEngineCollateralData memory _safeEngCData = safeEngine.cData(TKN);

    (uint256 _currentCollateral, uint256 _currentDebt) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    emit log_named_uint('_currentCollateral ------------', _currentCollateral);
    emit log_named_uint('_currentDebt ------------------', _currentDebt);

    uint256 _accumulatedRate = _safeEngCData.accumulatedRate;
    uint256 _liquidationPrice = _safeEngCData.liquidationPrice;
    uint256 _safetyPrice = _safeEngCData.safetyPrice;
    emit log_named_uint('_accumulatedRate --------------', _accumulatedRate);
    emit log_named_uint('_liquidationPrice -------------', _liquidationPrice);
    emit log_named_uint('_safetyPrice ------------------', _safetyPrice);

    uint256 _collateralXliquidationPrice = _currentCollateral.wmul(_liquidationPrice);
    uint256 _debtXaccumulatedRate = _currentDebt.wmul(_accumulatedRate);
    emit log_named_uint('_collateralXliquidationPrice --', _collateralXliquidationPrice);
    emit log_named_uint('_debtXaccumulatedRate ---------', _debtXaccumulatedRate);

    if (_collateralXliquidationPrice < _debtXaccumulatedRate) {
      uint256 _requiredAmount;

      /// @notice scoped to reduce stack
      {
        uint256 _collateralDeficit = (_debtXaccumulatedRate - _collateralXliquidationPrice).wdiv(_safetyPrice);
        emit log_named_uint('_collateralDeficit ------------', _collateralDeficit);

        uint256 _safetyCollateral = _collateralXliquidationPrice.wdiv(_safetyPrice);
        emit log_named_uint('_safetyCollateral -------------', _safetyCollateral);

        _requiredAmount = _collateralDeficit + _safetyCollateral - _currentCollateral;
        emit log_named_uint('_requiredAmount ---------------', _requiredAmount);
      }

      uint256 _newCollateralXliquidationPrice = (_currentCollateral + _requiredAmount).wmul(_liquidationPrice);
      emit log_named_uint('_newCollateralXliquidationPrice', _newCollateralXliquidationPrice);

      assertTrue(_newCollateralXliquidationPrice > _debtXaccumulatedRate);

      /**
       * @notice compare ratio using NFTRenderer math
       * formatted to 9 fixed-point decimals instead of 2 fixed-point decimals
       */
      emit log_named_uint('_liquidationCRatio ------------', oracleRelayer.cParams(TKN).liquidationCRatio / 1e18);
      emit log_named_uint('_safetyCRatio -----------------', oracleRelayer.cParams(TKN).safetyCRatio / 1e18);

      /// @notice `_ratio` should approximately equal `_safetyCRatio`
      emit log_named_uint(
        '_ratio ------------------------',
        (
          ((_currentCollateral + _requiredAmount).wmul(oracleRelayer.cParams(TKN).oracle.read())).wdiv(
            _debtXaccumulatedRate
          )
        )
      );
    }
  }

  /// @notice liquidation does not trigger
  function test_liquidateProtectedSafe_static10() public {
    _staticDevaluationLiquidation(0.1 ether);
  }

  /// @notice liquidation is saved
  function test_liquidateProtectedSafe_static15() public {
    _staticDevaluationLiquidation(0.15 ether);
  }

  /// @notice liquidation is saved
  function test_liquidateProtectedSafe_static20() public {
    _staticDevaluationLiquidation(0.2 ether);
  }

  /**
   * @dev helper function to check:
   * `_ratioBeforeDevaluation` collateral-debt ratio before collateral devaluation
   * `_ratioAfterDevaluation` collateral-debt ratio after collateral devaluation
   * `_ratioAfterSaveSAFE` collateral-debt ratio after ODSaviour.saveSAFE is called && liquidation is valid
   */
  function _staticDevaluationLiquidation(uint256 _devaluation) internal {
    (uint256 _collateralA, uint256 _debtA) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    uint256 _debtXaccumulatedRate = _debtA.wmul(accumulatedRate);

    emit log_named_uint('_liquidationCRatio ------------', oracleRelayer.cParams(TKN).liquidationCRatio / 1e18);
    emit log_named_uint(
      '_ratioBeforeDevaluation -------',
      (((_collateralA).wmul(oracleRelayer.cParams(TKN).oracle.read())).wdiv(_debtXaccumulatedRate))
    );

    assertTrue(_collateralA > 0 && _debtA > 0);
    assertTrue((_collateralA * liquidationPrice) >= (_debtA * accumulatedRate));
    _devalueCollateral(_devaluation);

    (uint256 _collateralB, uint256 _debtB) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);

    emit log_named_uint(
      '_ratioAfterDevaluation --------',
      (((_collateralB).wmul(oracleRelayer.cParams(TKN).oracle.read())).wdiv(_debtXaccumulatedRate))
    );

    if (liquidationPrice != 0 && (_collateralB * liquidationPrice) < (_debtB * accumulatedRate)) {
      liquidationEngine.liquidateSAFE(TKN, aliceNFV.safeHandler);
    }
    (uint256 _collateralC, uint256 _debtC) = saviour.getCurrentCollateralAndDebt(TKN, aliceNFV.safeHandler);
    emit log_named_uint('_collateralA  -----------------', _collateralA);
    emit log_named_uint('_collateralC  -----------------', _collateralC);

    assertTrue(_collateralC >= _collateralA);
    assertEq(_debtC, _debtA);

    emit log_named_uint('_safetyCRatio -----------------', oracleRelayer.cParams(TKN).safetyCRatio / 1e18);
    emit log_named_uint(
      '_ratioAfterSaveSAFE -----------',
      (((_collateralC).wmul(oracleRelayer.cParams(TKN).oracle.read())).wdiv(_debtXaccumulatedRate))
    );
  }
}
