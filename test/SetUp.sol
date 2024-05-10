// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import 'forge-std/Test.sol';
import {LiquidationEngine} from '@opendollar/contracts/LiquidationEngine.sol';
import {ILiquidationEngine} from '@opendollar/interfaces/ILiquidationEngine.sol';
import {IAccountingEngine} from '@opendollar/interfaces/IAccountingEngine.sol';
import {IVault721} from '@opendollar/interfaces/proxies/IVault721.sol';
import {Vault721} from '@opendollar/contracts/proxies/Vault721.sol';
import {IODSafeManager} from '@opendollar/interfaces/proxies/IODSafeManager.sol';
import {ODSafeManager} from '@opendollar/contracts/proxies/ODSafeManager.sol';
import {ISAFEEngine} from '@opendollar/interfaces/ISAFEEngine.sol';
import {SAFEEngine} from '@opendollar/contracts/SAFEEngine.sol';
import {ICollateralAuctionHouse} from '@opendollar/interfaces/ICollateralAuctionHouse.sol';
import {CollateralJoinFactory} from '@opendollar/contracts/factories/CollateralJoinFactory.sol';
import {ICollateralJoin} from '@opendollar/interfaces/utils/ICollateralJoin.sol';
import {IModifiablePerCollateral} from '@opendollar/interfaces/utils/IModifiablePerCollateral.sol';

import {IERC20} from '@openzeppelin/token/ERC20/ERC20.sol';
import {MintableERC20} from './mock-contracts/MintableERC20.sol';

import {DummyCollateralAuctionHouse} from './mock-contracts/CollateralAuctionHouseForTest.sol';
import {LiquidationEngineForTest} from './mock-contracts/LiquidationEngineForTest.sol';

import {EnumerableSet} from '@openzeppelin/utils/structs/EnumerableSet.sol';

import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {Math, MAX_RAD, RAY, WAD}from '@opendollar/libraries/Math.sol';
import {Assertions} from '@opendollar/libraries/Assertions.sol';

contract SetUp is Test {
  using stdStorage for StdStorage;

  bytes32 public nextAddressSeed = keccak256(abi.encodePacked('address'));

  uint256 public auctionId = 123_456;

  address public deployer = _label('deployer');
  address public mockCollateralAuctionHouse = address(new DummyCollateralAuctionHouse());
  address public mockSaviour = _label('saviour');
  address public alice = _label('alice');
  address public aliceProxy;
  uint256 public vaultId;

  bytes32 public ARB = bytes32(abi.encodePacked('ARB'));

  MintableERC20 public collateralToken;

  ISAFEEngine public safeEngine;
  IODSafeManager public safeManager;
  IVault721 public vault721;
  IAccountingEngine public mockAccountingEngine = IAccountingEngine(_mockContract('AccountingEngine'));
  CollateralJoinFactory public collateralJoinFactory;
  ICollateralJoin public collateralChild;

  address public taxCollector = _mockContract('taxCollector');
  address public timelockController = _mockContract('timelockController');

  LiquidationEngine public liquidationEngine;

  // NOTE: calculating _limitAdjustedDebt to mock call is complex, so we use a contract for test
  ICollateralAuctionHouse public collateralAuctionHouseForTest =
    ICollateralAuctionHouse(address(new DummyCollateralAuctionHouse()));

  ILiquidationEngine.LiquidationEngineParams _liquidationEngineParams = ILiquidationEngine.LiquidationEngineParams({
    onAuctionSystemCoinLimit: type(uint256).max,
    saviourGasLimit: 3_000_000
  });
  ISAFEEngine.SAFEEngineParams _safeEngineParams =
    ISAFEEngine.SAFEEngineParams({safeDebtCeiling: type(uint256).max, globalDebtCeiling: _rad(100000 ether)});

  function setUp() public virtual {
    vm.startPrank(deployer);

    collateralToken = new MintableERC20('Arbitrum', 'ARB', 18);
    collateralToken.mint(10_000 ether);
    safeEngine = new SAFEEngine(_safeEngineParams);

    ISAFEEngine.SAFEEngineCollateralParams memory _collateralParams =
      ISAFEEngine.SAFEEngineCollateralParams({debtCeiling: _rad(1000 ether), debtFloor: 0});

    safeEngine.initializeCollateralType(ARB, abi.encode(_collateralParams));

    collateralJoinFactory = new CollateralJoinFactory(address(safeEngine));

    safeEngine.addAuthorization(address(collateralJoinFactory));

    collateralChild = collateralJoinFactory.deployCollateralJoin(ARB, address(collateralToken));

    safeEngine.updateCollateralPrice(ARB, _ray(1 ether), _ray(1 ether));

    vault721 = new Vault721();

    vault721.initialize(timelockController, 1, 1);

    liquidationEngine =
      new LiquidationEngineForTest(address(safeEngine), address(mockAccountingEngine), _liquidationEngineParams);
    vm.label(address(liquidationEngine), 'LiquidationEngine');

    ILiquidationEngine.LiquidationEngineCollateralParams memory __collateralParams = ILiquidationEngine.LiquidationEngineCollateralParams({collateralAuctionHouse: mockCollateralAuctionHouse, liquidationPenalty: 1, liquidationQuantity: _rad(1)});
    
    liquidationEngine.initializeCollateralType(ARB, abi.encode(__collateralParams));
    safeManager =
    new ODSafeManager(address(safeEngine), address(vault721), address(taxCollector), address(liquidationEngine));
    safeEngine.addAuthorization(address(liquidationEngine));
    vm.stopPrank();
    vm.prank(alice);
    aliceProxy = vault721.build();
    vm.prank(aliceProxy);
    vaultId = safeManager.openSAFE(ARB, aliceProxy);
  }

  function _label(string memory name) internal returns (address) {
    address _newAddr = _newAddress();
    vm.label(_newAddr, name);
    return _newAddr;
  }

  function _mockContract(string memory name) internal returns (address) {
    address _newAddr = _newAddress();
    vm.etch(_newAddr, new bytes(0x1));
    vm.label(_newAddr, name);
    return _newAddr;
  }

  function _newAddress() internal returns (address) {
    address payable nextAddress = payable(address(uint160(uint256(nextAddressSeed))));
    nextAddressSeed = keccak256(abi.encodePacked(nextAddressSeed));
    return nextAddress;
  }

  function _ray(uint256 _wad) internal pure returns (uint256) {
    return _wad * 10 ** 9;
  }

  function _rad(uint256 wad) internal pure returns (uint256) {
    return wad * 10 ** 27;
  }
}
