// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ISAFESaviour} from './ISAFESaviour.sol';

interface IODSaviour is ISAFESaviour {
  event VaultStatusSet(uint256 _vaultId, bool _enabled);
  event CollateralTypeAdded(bytes32 _cType, address _tokenAddress);
  event SafeSaved(uint256 _vaultId, uint256 _reqCollateral);
  event LiquidatorRewardSet(uint256 _newReward);

  error OnlySaviourTreasury();
  error LengthMismatch();
  error VaultNotAllowed(uint256 _vaultId);
  error CollateralTransferFailed();
  error OnlyLiquidationEngine();
  error AlreadyInitialized(bytes32);
  error UninitializedCollateral(bytes32);
  error CollateralMustBeInitialized(bytes32);
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
    address vault721;
    address oracleRelayer;
    address collateralJoinFactory;
  }

  struct VaultData {
    uint256 id;
    bool isAllowed;
    bool isChosenSaviour;
    bool isEnabled;
    address vaultCtypeTokenAddress;
    uint256 saviourAllowance;
    uint256 treasuryBalance;
  }

  function isVaultEnabled(uint256 _vaultId) external view returns (bool _enabled);
  function vaultData(uint256 _vaultId) external view returns (VaultData memory _vData);
  function saviourIsReady(bytes32 _cType) external view returns (bool);
  function cType(bytes32 _cType) external view returns (address _tokenAddress);
  function saveSAFE(
    address _liquidator,
    bytes32 _cType,
    address _safe
  ) external returns (bool _ok, uint256 _collateralAdded, uint256 _liquidatorReward);
}
