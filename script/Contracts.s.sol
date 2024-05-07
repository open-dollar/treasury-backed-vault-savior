// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// --- Base Contracts ---
import {OpenDollar, SystemCoin, ISystemCoin} from '@opendollar/contracts/tokens/SystemCoin.sol';
import {OpenDollarGovernance, ProtocolToken, IProtocolToken} from '@opendollar/contracts/tokens/ProtocolToken.sol';
import {SAFEEngine, ISAFEEngine} from '@opendollar/contracts/SAFEEngine.sol';
import {TaxCollector, ITaxCollector} from '@opendollar/contracts/TaxCollector.sol';
import {AccountingEngine, IAccountingEngine} from '@opendollar/contracts/AccountingEngine.sol';
import {LiquidationEngine, ILiquidationEngine} from '@opendollar/contracts/LiquidationEngine.sol';
import {SurplusAuctionHouse, ISurplusAuctionHouse} from '@opendollar/contracts/SurplusAuctionHouse.sol';
import {DebtAuctionHouse, IDebtAuctionHouse} from '@opendollar/contracts/DebtAuctionHouse.sol';
import {CollateralAuctionHouse, ICollateralAuctionHouse} from '@opendollar/contracts/CollateralAuctionHouse.sol';
import {StabilityFeeTreasury, IStabilityFeeTreasury} from '@opendollar/contracts/StabilityFeeTreasury.sol';
import {PIDController, IPIDController} from '@opendollar/contracts/PIDController.sol';
import {PIDRateSetter, IPIDRateSetter} from '@opendollar/contracts/PIDRateSetter.sol';

// --- Settlement ---
import {GlobalSettlement, IGlobalSettlement} from '@opendollar/contracts/settlement/GlobalSettlement.sol';
import {
  PostSettlementSurplusAuctionHouse,
  IPostSettlementSurplusAuctionHouse
} from '@opendollar/contracts/settlement/PostSettlementSurplusAuctionHouse.sol';
import {
  SettlementSurplusAuctioneer,
  ISettlementSurplusAuctioneer
} from '@opendollar/contracts/settlement/SettlementSurplusAuctioneer.sol';

// --- Oracles ---
import {OracleRelayer, IOracleRelayer} from '@opendollar/contracts/OracleRelayer.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';
import {DelayedOracle, IDelayedOracle} from '@opendollar/contracts/oracles/DelayedOracle.sol';
import {DenominatedOracle} from '@opendollar/contracts/oracles/DenominatedOracle.sol';
import {ChainlinkRelayer} from '@opendollar/contracts/oracles/ChainlinkRelayer.sol';

// --- Testnet contracts ---
import {MintableERC20} from '@opendollar/contracts/for-test/MintableERC20.sol';
import {MintableVoteERC20} from '@opendollar/contracts/for-test/MintableVoteERC20.sol';
import {DeviatedOracle} from '@opendollar/contracts/for-test/DeviatedOracle.sol';
import {HardcodedOracle} from '@opendollar/contracts/for-test/HardcodedOracle.sol';

// --- Token adapters ---
import {CoinJoin, ICoinJoin} from '@opendollar/contracts/utils/CoinJoin.sol';
import {ETHJoin, IETHJoin} from '@opendollar/contracts/utils/ETHJoin.sol';
import {CollateralJoin, ICollateralJoin} from '@opendollar/contracts/utils/CollateralJoin.sol';

// --- Factories ---
import {
  CollateralJoinFactory, ICollateralJoinFactory
} from '@opendollar/contracts/factories/CollateralJoinFactory.sol';
import {
  CollateralAuctionHouseFactory,
  ICollateralAuctionHouseFactory
} from '@opendollar/contracts/factories/CollateralAuctionHouseFactory.sol';
import {
  ChainlinkRelayerFactory,
  IChainlinkRelayerFactory
} from '@opendollar/contracts/factories/ChainlinkRelayerFactory.sol';
import {
  DenominatedOracleFactory,
  IDenominatedOracleFactory
} from '@opendollar/contracts/factories/DenominatedOracleFactory.sol';
import {DelayedOracleFactory, IDelayedOracleFactory} from '@opendollar/contracts/factories/DelayedOracleFactory.sol';
import {IODCreate2Factory} from '@opendollar/interfaces/factories/IODCreate2Factory.sol';

// --- Jobs ---
import {AccountingJob, IAccountingJob} from '@opendollar/contracts/jobs/AccountingJob.sol';
import {LiquidationJob, ILiquidationJob} from '@opendollar/contracts/jobs/LiquidationJob.sol';
import {OracleJob, IOracleJob} from '@opendollar/contracts/jobs/OracleJob.sol';

// --- Interfaces ---
import {IERC20Metadata} from '@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol';
import {IModifiable} from '@opendollar/interfaces/utils/IModifiable.sol';
import {IAuthorizable} from '@opendollar/interfaces/utils/IAuthorizable.sol';

// --- Proxy Contracts ---
import {BasicActions, CommonActions} from '@opendollar/contracts/proxies/actions/BasicActions.sol';
import {DebtBidActions} from '@opendollar/contracts/proxies/actions/DebtBidActions.sol';
import {SurplusBidActions} from '@opendollar/contracts/proxies/actions/SurplusBidActions.sol';
import {CollateralBidActions} from '@opendollar/contracts/proxies/actions/CollateralBidActions.sol';
import {PostSettlementSurplusBidActions} from
  '@opendollar/contracts/proxies/actions/PostSettlementSurplusBidActions.sol';
import {GlobalSettlementActions} from '@opendollar/contracts/proxies/actions/GlobalSettlementActions.sol';
import {RewardedActions} from '@opendollar/contracts/proxies/actions/RewardedActions.sol';
import {GlobalSettlementActions} from '@opendollar/contracts/proxies/actions/GlobalSettlementActions.sol';
import {PostSettlementSurplusBidActions} from
  '@opendollar/contracts/proxies/actions/PostSettlementSurplusBidActions.sol';
import {ODProxy} from '@opendollar/contracts/proxies/ODProxy.sol';
import {ODSafeManager} from '@opendollar/contracts/proxies/ODSafeManager.sol';
import {Vault721} from '@opendollar/contracts/proxies/Vault721.sol';
import {NFTRenderer} from '@opendollar/contracts/proxies/NFTRenderer.sol';

// --- Governance Contracts ---
import {TimelockController} from '@openzeppelin/governance/TimelockController.sol';
import {ODGovernor} from '@opendollar/contracts/gov/ODGovernor.sol';

// --- ForTestnet ---
import {OracleForTest} from '@opendollar/contracts/for-test/OracleForTest.sol';
import {OracleForTestnet} from '@opendollar/contracts/for-test/OracleForTestnet.sol';

/**
 * @title  Contracts
 * @notice This contract initializes all the contracts, so that they're inherited and available throughout scripts scopes.
 * @dev    It exports all the contracts and interfaces to be inherited or modified during the scripts dev and execution.
 */
abstract contract Contracts {
  // --- Helpers ---
  uint256 public chainId;
  address public deployer;
  address public tlcGov;
  address public delegate;
  bytes32[] public collateralTypes;
  mapping(bytes32 => address) public delegatee;

  // -- Create2 Factory --
  IODCreate2Factory public create2;

  // --- Base contracts ---
  ISAFEEngine public safeEngine;
  ITaxCollector public taxCollector;
  IAccountingEngine public accountingEngine;
  ILiquidationEngine public liquidationEngine;
  IOracleRelayer public oracleRelayer;
  ISurplusAuctionHouse public surplusAuctionHouse;
  IDebtAuctionHouse public debtAuctionHouse;
  IStabilityFeeTreasury public stabilityFeeTreasury;
  mapping(bytes32 => ICollateralAuctionHouse) public collateralAuctionHouse;

  // --- Token contracts ---
  IProtocolToken public protocolToken;
  ISystemCoin public systemCoin;
  mapping(bytes32 => MintableERC20) public erc20;
  mapping(bytes32 => IERC20Metadata) public collateral;
  ICoinJoin public coinJoin;
  IETHJoin public ethJoin;
  mapping(bytes32 => ICollateralJoin) public collateralJoin;

  // --- Oracle contracts ---
  IBaseOracle public systemCoinOracle;
  mapping(bytes32 => IDelayedOracle) public delayedOracle;

  // --- PID contracts ---
  IPIDController public pidController;
  IPIDRateSetter public pidRateSetter;

  // --- Factory contracts ---
  ICollateralJoinFactory public collateralJoinFactory;
  ICollateralAuctionHouseFactory public collateralAuctionHouseFactory;

  IChainlinkRelayerFactory public chainlinkRelayerFactory;
  IDenominatedOracleFactory public denominatedOracleFactory;
  IDelayedOracleFactory public delayedOracleFactory;

  // --- Settlement contracts ---
  IGlobalSettlement public globalSettlement;
  IPostSettlementSurplusAuctionHouse public postSettlementSurplusAuctionHouse;
  ISettlementSurplusAuctioneer public settlementSurplusAuctioneer;

  // --- Job contracts ---
  IAccountingJob public accountingJob;
  ILiquidationJob public liquidationJob;
  IOracleJob public oracleJob;

  // --- Proxy contracts ---
  ODSafeManager public safeManager;
  Vault721 public vault721;
  NFTRenderer public nftRenderer;

  BasicActions public basicActions;
  DebtBidActions public debtBidActions;
  SurplusBidActions public surplusBidActions;
  CollateralBidActions public collateralBidActions;
  RewardedActions public rewardedActions;
  GlobalSettlementActions public globalSettlementActions;
  PostSettlementSurplusBidActions public postSettlementSurplusBidActions;

  // --- Governance Contracts ---
  TimelockController public timelockController;
  ODGovernor public odGovernor;
}
