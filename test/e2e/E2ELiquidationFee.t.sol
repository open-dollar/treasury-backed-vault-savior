// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IERC20} from '@openzeppelin/token/ERC20/ERC20.sol';
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
uint256 constant DEFAULT_DEVALUATION = 0.2 ether;

contract E2ELiquidationFeeSetup is SharedSetup {
  /**
   * @notice testing for Super Over-Collateralized (SOC) Token
   * 0x534f430000000000000000000000000000000000000000000000000000000000
   */
  bytes32 public constant SOC = bytes32('SOC');
  uint256 public initialSystemCoinSupply;

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

    bobProxy = _userVaultSetup(SOC, bob, USER_AMOUNT, 'BobProxy');
    bobNFV = vault721.getNfvState(vaults[bobProxy]);
    _depositCollateralAndGenDebt(SOC, vaults[bobProxy], DEPOSIT * 3, MINT * 3, bobProxy);

    initialSystemCoinSupply = systemCoin.totalSupply();
  }

  function _collateralDevaluation(uint256 _devaluation) internal {
    uint256 _p = delayedOracle[SOC].read();
    DelayedOracleForTest(address(delayedOracle[SOC])).setPriceAndValidity(_p - _devaluation, true);
    oracleRelayer.updateCollateralPrice(SOC);
  }
}

contract E2ELiquidationFeeTestSetup is E2ELiquidationFeeSetup {
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
    _collateralDevaluation(DEFAULT_DEVALUATION);
    assertEq(delayedOracle[SOC].read(), TEST_TKN_PRICE - _deval);
  }

  function test_vaultRatioDevaluation() public {
    uint256 _ratioBeforeDevaluation = _getSafeRatio(SOC, aliceNFV.safeHandler);
    emit log_named_uint('_ratioBeforeDevaluation -------', _ratioBeforeDevaluation);

    _collateralDevaluation(DEFAULT_DEVALUATION);

    uint256 _ratioAfterDevaluation = _getSafeRatio(SOC, aliceNFV.safeHandler);
    emit log_named_uint('_ratioAfterDevaluation --------', _ratioAfterDevaluation);

    assertTrue(_ratioBeforeDevaluation > _ratioAfterDevaluation);
  }

  function test_liquidation() public {
    _collateralDevaluation(DEFAULT_DEVALUATION);
    (uint256 _collateralBefore, uint256 _debtBefore) = _getSAFE(SOC, aliceNFV.safeHandler);
    assertGt(_collateralBefore, 0);
    assertGt(_debtBefore, 0);
    liquidationEngine.liquidateSAFE(SOC, aliceNFV.safeHandler);
    (uint256 _collateralAfter, uint256 _debtAfter) = _getSAFE(SOC, aliceNFV.safeHandler);
    assertEq(_collateralAfter, 0);
    assertEq(_debtAfter, 0);
  }
}

contract E2ELiquidationFeeTest is E2ELiquidationFeeSetup {
  using Math for uint256;

  function setUp() public virtual override {
    super.setUp();
    _collateralDevaluation(DEFAULT_DEVALUATION);
    auctionId = liquidationEngine.liquidateSAFE(SOC, aliceNFV.safeHandler);

    vm.prank(bob);
    systemCoin.approve(bobProxy, USER_AMOUNT);
  }

  function test_buyCollateral1() public {
    // bob's non-deposited collateral balance before collateral auction
    uint256 _externalCollateralBefore = collateral[SOC].balanceOf(bob);

    // alice + bob systemCoin supply
    assertEq(initialSystemCoinSupply, systemCoin.totalSupply());

    // bob to buy alice's liquidated collateral
    _buyCollateral(SOC, auctionId, 0, MINT, bobProxy);

    // alice systemCoin supply burned in collateral auction
    assertEq(systemCoin.totalSupply(), initialSystemCoinSupply - MINT);

    // bob's non-deposited collateral balance after collateral auction
    uint256 _externalCollateralGain = collateral[SOC].balanceOf(bob) - _externalCollateralBefore;
    emit log_named_uint('_externalCollateralGain -------', _externalCollateralGain);
  }

  function test_buyCollateral2() public {
    uint256 _externalCollateralBefore = collateral[SOC].balanceOf(bob);

    // bob double's bid from first test
    _buyCollateral(SOC, auctionId, 0, MINT * 2, bobProxy);
    assertEq(systemCoin.totalSupply(), initialSystemCoinSupply - MINT * 2);

    uint256 _externalCollateralGain = collateral[SOC].balanceOf(bob) - _externalCollateralBefore;
    emit log_named_uint('_externalCollateralGain -------', _externalCollateralGain);
  }

  function test_buyCollateral3() public {
    uint256 _externalCollateralBefore = collateral[SOC].balanceOf(bob);

    // bob triple's bid from first test
    _buyCollateral(SOC, auctionId, 0, MINT * 3, bobProxy);
    assertEq(systemCoin.totalSupply(), initialSystemCoinSupply - MINT * 3);

    uint256 _externalCollateralGain = collateral[SOC].balanceOf(bob) - _externalCollateralBefore;
    emit log_named_uint('_externalCollateralGain -------', _externalCollateralGain);
  }
}
