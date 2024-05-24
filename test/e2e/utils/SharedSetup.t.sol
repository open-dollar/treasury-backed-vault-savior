// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Common, TKN} from '@opendollar/test/e2e/Common.t.sol';
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
    bytes memory payload = abi.encodeWithSelector(
      basicActions.lockTokenCollateralAndGenerateDebt.selector,
      address(safeManager),
      address(collateralJoin[_cType]),
      address(coinJoin),
      _safeId,
      _collatAmount,
      _deltaWad
    );
    ODProxy(_proxy).execute(address(basicActions), payload);
    vm.stopPrank();
  }

  function _getSAFE(bytes32 _cType, address _safe) public view returns (uint256 _collateral, uint256 _debt) {
    ISAFEEngine.SAFE memory _safeData = safeEngine.safes(_cType, _safe);
    _collateral = _safeData.lockedCollateral;
    _debt = _safeData.generatedDebt;
  }

  function _refreshCData(bytes32 _cType) internal {
    cTypeData = safeEngine.cData(_cType);
    liquidationPrice = cTypeData.liquidationPrice;
    accumulatedRate = cTypeData.accumulatedRate;

    oracleParams = oracleRelayer.cParams(_cType);
    liquidationCRatio = oracleParams.liquidationCRatio;
    safetyCRatio = oracleParams.safetyCRatio;
  }
}
