// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Math} from '@opendollar/libraries/Math.sol';
import {ERC20ForTest} from '@opendollar/test/mocks/ERC20ForTest.sol';
import {Common, TKN, TEST_TKN_PRICE} from '@opendollar/test/e2e/Common.t.sol';
import {DelayedOracleForTest} from '@opendollar/test/mocks/DelayedOracleForTest.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {ITaxCollector} from '@opendollar/interfaces/ITaxCollector.sol';
import {ISAFEEngine} from '@opendollar/interfaces/ISAFEEngine.sol';
import {ILiquidationEngine} from '@opendollar/interfaces/ILiquidationEngine.sol';
import {ICollateralAuctionHouse} from '@opendollar/interfaces/ICollateralAuctionHouse.sol';
import {IAuthorizable} from '@opendollar/interfaces/utils/IAuthorizable.sol';
import {SharedSetup, RAD, RAY, WAD} from 'test/e2e/utils/SharedSetup.t.sol';

uint256 constant MINUS_0_5_PERCENT_PER_HOUR = 999_998_607_628_240_588_157_433_861;
uint256 constant DEPOSIT = 185 ether + 1; // 185% collateralized
uint256 constant MINT = 100 ether;

contract E2ELiquidationFeeSetup is SharedSetup {
  /**
   * @notice testing for Super Over-Collateralized (SOC) Token
   * 0x534f430000000000000000000000000000000000000000000000000000000000
   */
  bytes32 public constant SOC = bytes32('SOC');

  function setUp() public virtual override {
    super.setUp();
    collateral[SOC] = new ERC20ForTest();
    delayedOracle[SOC] = new DelayedOracleForTest(TEST_TKN_PRICE, address(0xabcdef));
    collateralTypes.push(SOC);

    _collateralAuctionHouseParams[SOC] = ICollateralAuctionHouse.CollateralAuctionHouseParams({
      minimumBid: 1,
      minDiscount: WAD,
      maxDiscount: 0.9e18,
      perSecondDiscountUpdateRate: MINUS_0_5_PERCENT_PER_HOUR
    });

    vm.startPrank(tlcGov);
    collateralJoin[SOC] = collateralJoinFactory.deployCollateralJoin(SOC, address(collateral[SOC]));
    collateralAuctionHouseFactory.initializeCollateralType(SOC, abi.encode(_collateralAuctionHouseParams[SOC]));
    collateralAuctionHouse[SOC] = ICollateralAuctionHouse(collateralAuctionHouseFactory.collateralAuctionHouses(SOC));
    vm.stopPrank();

    _oracleRelayerCParams[SOC] = IOracleRelayer.OracleRelayerCollateralParams({
      oracle: delayedOracle[SOC],
      safetyCRatio: 1.85e27,
      liquidationCRatio: 1.75e27
    });

    _taxCollectorCParams[SOC] = ITaxCollector.TaxCollectorCollateralParams({stabilityFee: RAY + 1.54713e18});

    _safeEngineCParams[SOC] = ISAFEEngine.SAFEEngineCollateralParams({debtCeiling: 1_000_000_000 * RAD, debtFloor: 0});

    _liquidationEngineCParams[SOC] = ILiquidationEngine.LiquidationEngineCollateralParams({
      collateralAuctionHouse: address(collateralAuctionHouse[SOC]),
      liquidationPenalty: 1.1e18,
      liquidationQuantity: 100_000e45
    });

    vm.startPrank(tlcGov);
    _setupCollateral(SOC);
    vm.stopPrank();

    _refreshCData(SOC);
    aliceProxy = _userVaultSetup(SOC, alice, USER_AMOUNT, 'AliceProxy');
    aliceNFV = vault721.getNfvState(vaults[aliceProxy]);
    _depositCollateralAndGenDebt(SOC, vaults[aliceProxy], DEPOSIT, MINT, aliceProxy);
  }

  function _collateralDevaluation(uint256 _devaluation) internal {
    uint256 _p = delayedOracle[SOC].read();
    DelayedOracleForTest(address(delayedOracle[SOC])).setPriceAndValidity(_p - _devaluation, true);
    oracleRelayer.updateCollateralPrice(SOC);
  }
}

contract E2ELiquidationFeeTestSetup is E2ELiquidationFeeSetup {
  using Math for uint256;

  uint256 public deval = 0.2 ether;

  function test_cTypes() public {
    bytes32[] memory cTypes = collateralJoinFactory.collateralTypesList(); // bytes32 collateralTypes in the protocol
    bytes32[] memory cList = collateralAuctionHouseFactory.collateralList(); // bytes32 collateralTypes for collateral auction
    uint256 _l = cTypes.length;
    assertEq(_l, cList.length);
    for (uint256 _i = 0; _i < _l; _i++) {
      assertTrue(cTypes[_i] == cList[_i]);
    }
    assertEq(cTypes[_l - 1], SOC);
  }

  function test_cTypePriceDevaluation() public {
    uint256 _deval = 0.2 ether;
    assertEq(delayedOracle[SOC].read(), TEST_TKN_PRICE);
    _collateralDevaluation(deval);
    assertEq(delayedOracle[SOC].read(), TEST_TKN_PRICE - _deval);
  }

  function test_vaultRatioDevaluation() public {
    (uint256 _collateral, uint256 _debt) = _getSAFE(SOC, aliceNFV.safeHandler);
    uint256 _ratioBeforeDevaluation =
      _collateral.wmul(oracleRelayer.cParams(SOC).oracle.read()).wdiv(_debt.wmul(accumulatedRate));
    emit log_named_uint('_ratioBeforeDevaluation -------', _ratioBeforeDevaluation);
    _collateralDevaluation(deval);
    uint256 _ratioAfterDevaluation =
      _collateral.wmul(oracleRelayer.cParams(SOC).oracle.read()).wdiv(_debt.wmul(accumulatedRate));
    emit log_named_uint('_ratioAfterDevaluation --------', _ratioAfterDevaluation);
    assertTrue(_ratioBeforeDevaluation > _ratioAfterDevaluation);
  }
}
