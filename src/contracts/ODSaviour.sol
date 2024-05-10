// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {AccessControl} from '@openzeppelin/access/AccessControl.sol';
import {IERC20} from '@openzeppelin/token/ERC20/ERC20.sol';
import {SAFEEngine, ISAFEEngine} from '@opendollar/contracts/SAFEEngine.sol';
import {LiquidationEngine, ILiquidationEngine} from '@opendollar/contracts/LiquidationEngine.sol';
import {CollateralAuctionHouse, ICollateralAuctionHouse} from '@opendollar/contracts/CollateralAuctionHouse.sol';
import {IOracleRelayer} from '@opendollar/interfaces/IOracleRelayer.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {IVault721} from '@opendollar/interfaces/proxies/IVault721.sol';
import {ISAFESaviour} from '../interfaces/ISAFESaviour.sol';
import {ODSafeManager, IODSafeManager} from '@opendollar/contracts/proxies/ODSafeManager.sol';
import {Math} from '@opendollar/libraries/Math.sol';

/**
 * @notice Steps to save a safe using ODSaviour:
 *
 * 1. Protocol DAO => connect [this] saviour `LiquidationEngine.connectSAFESaviour`
 * 2. Treasury DAO => enable specific vaults `ODSaviour.setVaultStatus`
 * 3. Treasury DAO => approve `ERC20.approveTransferFrom` to the saviour
 * 4. Vault owner => protect thier safe with elected saviour `LiquidationEngine.protectSAFE` (only works if ARB DAO enable vaultId)
 * 5. Safe in liquidation => auto call `LiquidationEngine.attemptSave` gets saviour from chosenSAFESaviour mapping
 * 6. Saviour => increases collateral `ODSaviour.saveSAFE`
 */

/**
 * @notice SaviourInit struct
 *   @param saviourTreasury the address of the saviour treasury
 *   @param protocolGovernor the address of the protocol governor
 *   @param liquidationEngine the address ot the liquidation engine;
 *   @param vault721 the address of the vault721
 *   @param cTypes an array of collateral types that can be used in this saviour (bytes32('ARB'));
 *   @param saviourTokens the addresses of the saviour tokens to be used in this contract;
 */
struct SaviourInit {
  address saviourTreasury;
  address protocolGovernor;
  address vault721;
  address oracleRelayer;
  bytes32[] cTypes;
  address[] saviourTokens;
}

contract ODSaviour is AccessControl, ISAFESaviour {
  using Math for uint256;

  //solhint-disable-next-line modifier-name-mixedcase
  bytes32 public constant SAVIOUR_TREASURY = keccak256(abi.encode('SAVIOUR_TREASURY'));
  bytes32 public constant PROTOCOL = keccak256(abi.encode('PROTOCOL'));

  address public saviourTreasury;
  address public protocolGovernor;
  address public liquidationEngine;

  IVault721 public vault721;
  IOracleRelayer public oracleRelayer;
  IODSafeManager public safeManager;
  ISAFEEngine public safeEngine;

  mapping(uint256 _vaultId => bool _enabled) private _enabledVaults;
  mapping(bytes32 _cType => address _tokenAddress) private _saviourTokenAddresses;

  /**
   * @param _init The SaviourInit struct;
   */
  constructor(SaviourInit memory _init) {
    saviourTreasury = _init.saviourTreasury;
    protocolGovernor = _init.protocolGovernor;
    vault721 = IVault721(_init.vault721);
    oracleRelayer = IOracleRelayer(_init.oracleRelayer);
    safeManager = IODSafeManager(vault721.safeManager());
    liquidationEngine = ODSafeManager(address(safeManager)).liquidationEngine(); // todo update @opendollar package to include `liquidationEngine` - PR #693
    safeEngine = ISAFEEngine(safeManager.safeEngine());

    if (_init.saviourTokens.length != _init.cTypes.length) revert LengthMismatch();

    for (uint256 i; i < _init.cTypes.length; i++) {
      _saviourTokenAddresses[_init.cTypes[i]] = _init.saviourTokens[i];
    }
    grantRole(SAVIOUR_TREASURY, saviourTreasury);
    grantRole(PROTOCOL, protocolGovernor);
    grantRole(PROTOCOL, liquidationEngine);
  }

  function isEnabled(uint256 _vaultId) external view returns (bool _enabled) {
    _enabled = _enabledVaults[_vaultId];
  }

  function addCType(bytes32 _cType, address _tokenAddress) external onlyRole(SAVIOUR_TREASURY) {
    _saviourTokenAddresses[_cType] = _tokenAddress;
    emit CollateralTypeAdded(_cType, _tokenAddress);
  }

  /**
   * @dev
   */
  function setVaultStatus(uint256 _vaultId, bool _enabled) external onlyRole(SAVIOUR_TREASURY) {
    _enabledVaults[_vaultId] = _enabled;

    emit VaultStatusSet(_vaultId, _enabled);
  }

  /**
   * todo increase collateral to sufficient level
   * 1. find out how much collateral is required to effectively save the safe
   * 2. transfer the collateral to the vault, so the liquidation math will result in null liquidation
   * 3. write tests
   */
  function saveSAFE(
    address _liquidator,
    bytes32 _cType,
    address _safe
  ) external onlyRole(PROTOCOL) returns (bool _ok, uint256 _collateralAdded, uint256 _liquidatorReward) {
    uint256 vaultId = safeManager.safeHandlerToSafeId(_safe);
    if (!_enabledVaults[vaultId]) revert VaultNotAllowed(vaultId);

    ISAFEEngine.SAFE memory SafeEngineData = safeEngine.safes(_cType, _safe);
    uint256 currCollateral = SafeEngineData.lockedCollateral;
    uint256 currDebt = SafeEngineData.generatedDebt;

    ISAFEEngine.SAFEEngineCollateralData memory cTypeData = safeEngine.cData(_cType);
    IOracleRelayer.OracleRelayerCollateralParams memory oracleParams = oracleRelayer.cParams(_cType);
    IDelayedOracle oracle = oracleParams.oracle;

    uint256 currCRatio = ((currCollateral.wmul(oracle.read())).wdiv(currDebt.wmul(cTypeData.accumulatedRate))) / 1e7;
    uint256 safetyCRatio = oracleParams.safetyCRatio / 10e24;
    uint256 diffCRatio = safetyCRatio.wdiv(currCRatio);

    uint256 reqCollateral = (currCollateral.wmul(diffCRatio)) - currCollateral;

    // todo: transferFrom ARB Treasury amount of reqCollateral

    uint256 _collateralAdded = type(uint256).max;
    _liquidatorReward = type(uint256).max;
  }
}
