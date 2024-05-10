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
import {IERC20} from '@openzeppelin/token/ERC20/ERC20.sol';
import {MintableERC20} from './mock-contracts/MintableERC20.sol';

import {DummyCollateralAuctionHouse} from './mock-contracts/CollateralAuctionHouseForTest.sol';
import {LiquidationEngineForTest} from './mock-contracts/LiquidationEngineForTest.sol';

import {EnumerableSet} from '@openzeppelin/utils/structs/EnumerableSet.sol';

import {StdStorage, stdStorage} from 'forge-std/StdStorage.sol';
import {Math, MAX_RAD, RAY, WAD} from '@libraries/Math.sol';
import {Assertions} from '@libraries/Assertions.sol';

contract SetUp is Test {
  using stdStorage for StdStorage;

  bytes32 public nextAddressSeed = keccak256(abi.encodePacked('address'));

  uint256 public auctionId = 123_456;

  address public deployer = _label('deployer');
  address public account = _label('account');
  address public safe = _label('safe');
  address public mockCollateralAuctionHouse = _label('collateralTypeSampleAuctionHouse');
  address public mockSaviour = _label('saviour');
  address public user = _label('user');

  bytes32 public ARB = 'ARB';

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
  ICollateralAuctionHouse _collateralAuctionHouseForTest =
    ICollateralAuctionHouse(address(new DummyCollateralAuctionHouse()));

  ILiquidationEngine.LiquidationEngineParams _liquidationEngineParams = ILiquidationEngine.LiquidationEngineParams({
    onAuctionSystemCoinLimit: type(uint256).max,
    saviourGasLimit: 3_000_000
  });
  ISAFEEngine.SAFEEngineParams _safeEngineParams =
    ISAFEEngine.SAFEEngineParams({safeDebtCeiling: type(uint256).max, globalDebtCeiling: 0});

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

    safeEngine.updateCollateralPrice('gold', _ray(1 ether), _ray(1 ether));

    vault721 = new Vault721();

    vault721.initialize(timelockController, 1, 1);

    liquidationEngine =
      new LiquidationEngineForTest(address(safeEngine), address(mockAccountingEngine), _liquidationEngineParams);
    vm.label(address(liquidationEngine), 'LiquidationEngine');

    safeManager =
      new ODSafeManager(address(safeEngine), address(vault721), address(taxCollector), address(liquidationEngine));
    
  }

  function _label(string memory name) internal returns (address) {
    address _newAddress = _newAddress();
    vm.label(_newAddress, name);
    return _newAddress;
  }

  function _mockContract(string memory name) internal returns (address) {
    address _newAddress = _newAddress();
    vm.etch(_newAddress, new bytes(0x1));
    vm.label(_newAddress, 'name');
    return _newAddress;
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
