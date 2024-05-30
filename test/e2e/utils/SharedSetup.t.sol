// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Common, TKN} from '@opendollar/test/e2e/Common.t.sol';
import {Math} from '@opendollar/libraries/Math.sol';
import {ODProxy} from '@opendollar/contracts/proxies/ODProxy.sol';
import {ERC20ForTest} from '@opendollar/test/mocks/ERC20ForTest.sol';
import {IVault721} from '@opendollar/interfaces/proxies/IVault721.sol';
import {ISAFEEngine} from '@opendollar/interfaces/ISAFEEngine.sol';
import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {ODSaviour} from 'src/contracts/ODSaviour.sol';

uint256 constant RAD = 1e45;
uint256 constant RAY = 1e27;
uint256 constant WAD = 1e18;

contract SharedSetup is Common {
  using Math for uint256;

  uint256 public constant TREASURY_AMOUNT = 1_000_000_000_000_000_000_000_000_000 ether;
  uint256 public constant PROTOCOL_AMOUNT = 1_000_000_000 ether;
  uint256 public constant USER_AMOUNT = 1000 ether;

  ODSaviour public saviour;
  address public treasury;

  IVault721.NFVState public aliceNFV;
  IVault721.NFVState public bobNFV;

  address public aliceProxy;
  address public bobProxy;
  address public deployerProxy;

  ISAFEEngine.SAFEEngineCollateralData public cTypeData;
  IOracleRelayer.OracleRelayerCollateralParams public oracleParams;

  uint256 public liquidationCRatio; // RAY
  uint256 public safetyCRatio; // RAY
  uint256 public accumulatedRate; // RAY
  uint256 public liquidationPrice; // RAY

  mapping(address proxy => uint256 safeId) public vaults;

  function _userTKNVaultSetup(address _user, uint256 _amount, string memory _name) internal returns (address _proxy) {
    _proxy = _userVaultSetup(TKN, _user, _amount, _name);
  }

  function _userVaultSetup(
    bytes32 _cType,
    address _user,
    uint256 _amount,
    string memory _name
  ) internal returns (address _proxy) {
    _proxy = _deployOrFind(_user);
    _mintToken(_cType, _user, _amount, _proxy);
    vm.label(_proxy, _name);
    vm.prank(_proxy);
    vaults[_proxy] = safeManager.openSAFE(_cType, _proxy);
  }

  function _mintTKN(address _account, uint256 _amount, address _okAccount) internal {
    _mintToken(TKN, _account, _amount, _okAccount);
  }

  function _mintToken(bytes32 _cType, address _account, uint256 _amount, address _okAccount) internal {
    vm.startPrank(_account);
    ERC20ForTest _token = ERC20ForTest(address(collateral[_cType]));
    _token.mint(_amount);
    if (_okAccount != address(0)) {
      _token.approve(_okAccount, _amount);
    }
    vm.stopPrank();
  }

  function _deployOrFind(address _owner) internal returns (address) {
    address proxy = vault721.getProxy(_owner);
    if (proxy == address(0)) {
      return address(vault721.build(_owner));
    } else {
      return proxy;
    }
  }

  function _depositTKNAndGenDebt(uint256 _safeId, uint256 _collatAmount, uint256 _deltaWad, address _proxy) internal {
    _depositCollateralAndGenDebt(TKN, _safeId, _collatAmount, _deltaWad, _proxy);
  }

  function _depositCollateralAndGenDebt(
    bytes32 _cType,
    uint256 _safeId,
    uint256 _collatAmount,
    uint256 _deltaWad,
    address _proxy
  ) internal {
    vm.startPrank(ODProxy(_proxy).OWNER());
    bytes memory _payload = abi.encodeWithSelector(
      basicActions.lockTokenCollateralAndGenerateDebt.selector,
      address(safeManager),
      address(collateralJoin[_cType]),
      address(coinJoin),
      _safeId,
      _collatAmount,
      _deltaWad
    );
    ODProxy(_proxy).execute(address(basicActions), _payload);
    vm.stopPrank();
  }

  function _buyCollateral(
    bytes32 _cType,
    uint256 _auctionId,
    uint256 _minCollateral,
    uint256 _bid,
    address _proxy
  ) internal {
    vm.startPrank(ODProxy(_proxy).OWNER());
    bytes memory _payload = abi.encodeWithSelector(
      collateralBidActions.buyCollateral.selector,
      address(coinJoin),
      address(collateralJoin[_cType]),
      address(collateralAuctionHouse[_cType]),
      _auctionId,
      _minCollateral,
      _bid
    );
    ODProxy(_proxy).execute(address(collateralBidActions), _payload);
    vm.stopPrank();
  }

  function _refreshCData(bytes32 _cType) internal {
    cTypeData = safeEngine.cData(_cType);
    liquidationPrice = cTypeData.liquidationPrice;
    accumulatedRate = cTypeData.accumulatedRate;

    oracleParams = oracleRelayer.cParams(_cType);
    liquidationCRatio = oracleParams.liquidationCRatio;
    safetyCRatio = oracleParams.safetyCRatio;
  }

  function _getSAFE(bytes32 _cType, address _safe) internal view returns (uint256 _collateral, uint256 _debt) {
    ISAFEEngine.SAFE memory _safeData = safeEngine.safes(_cType, _safe);
    _collateral = _safeData.lockedCollateral;
    _debt = _safeData.generatedDebt;
  }

  function _getRatio(bytes32 _cType, uint256 _collateral, uint256 _debt) internal view returns (uint256 _ratio) {
    _ratio = _collateral.wmul(oracleRelayer.cParams(_cType).oracle.read()).wdiv(_debt.wmul(accumulatedRate));
  }

  function _getSafeRatio(bytes32 _cType, address _safe) internal view returns (uint256 _ratio) {
    (uint256 _collateral, uint256 _debt) = _getSAFE(_cType, _safe);
    _ratio = _getRatio(_cType, _collateral, _debt);
  }

  function _logWadAccountingEngineCoinAndDebtBalance() internal {
    emit log_named_uint('_accountingEngineCoinBalance --', safeEngine.coinBalance(address(accountingEngine)) / RAY);
    emit log_named_uint('_accountingEngineDebtBalance --', safeEngine.debtBalance(address(accountingEngine)) / RAY);
  }

  function _logWadCollateralAuctionHouseTokenCollateral(bytes32 _cType) internal {
    emit log_named_uint(
      '_CAH_tokenCollateral ----------', safeEngine.tokenCollateral(_cType, address(collateralAuctionHouse[_cType]))
    );
  }
}
