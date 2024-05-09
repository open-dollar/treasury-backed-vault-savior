// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface ISAFESaviour {
  error OnlySaviourTreasury();
  error LengthMismatch();
  error VaultNotAllowed(uint256 vaultId);

  event VaultStatusSet(uint256 _tokenId, bool _enabled);
  event CollateralTypeAdded(bytes32 _cType, address _tokenAddress);

  function isEnabled(uint256 _vaultId) external view returns (bool _enabled);

  function setVaultStatus(uint256 _tokenId, bool _enabled) external;

  function saveSAFE(
    address _liquidator,
    bytes32 _cType,
    address _safe
  ) external returns (bool _ok, uint256 _collateralAdded, uint256 _liquidatorReward);
}
