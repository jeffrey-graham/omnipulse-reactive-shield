// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISubscriptionService & IReactive
 * @notice Canonical Reactive Network interfaces for cross-chain event subscriptions
 *         and Reactive VM (`react(LogRecord calldata log)`) execution.
 */
interface ISubscriptionService {
    function subscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;

    function unsubscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;
}

interface IReactive {
    struct LogRecord {
        uint256 chain_id;
        address _contract;
        uint256 topic_0;
        uint256 topic_1;
        uint256 topic_2;
        uint256 topic_3;
        bytes data;
        uint256 block_number;
        uint256 op_code;
        uint256 block_hash;
        uint256 tx_hash;
        uint256 log_index;
    }

    event Callback(
        uint256 indexed chain_id,
        address indexed _contract,
        uint64 indexed gas_limit,
        bytes payload
    );

    function react(LogRecord calldata log) external;
}

abstract contract AbstractReactive is IReactive {
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    ISubscriptionService internal immutable service;
    bool internal vm;

    modifier rnOnly() {
        require(!vm, "ReactiveNetwork: RN network only");
        _;
    }

    modifier vmOnly() {
        require(vm, "ReactiveNetwork: Reactive VM only");
        _;
    }

    constructor(address _service, bool _vm) {
        service = ISubscriptionService(_service);
        vm = _vm;
    }
}

/**
 * @title OmniPulseReactiveShield
 * @notice Reactive Smart Contract targeting all 3 Reactive Omni Buildathon tracks:
 *   - Track 1 (Every Second Counts): Sub-second cross-chain liquidation shield via `react()`
 *   - Track 2 (Set It and Forget It): Personal autonomous yield rebalancing & auto-compounding
 *   - Track 3 (Reactive Meets AI): AI Volatility Regime ingestion & adaptive safety buffers
 */
contract OmniPulseReactiveShield is AbstractReactive {
    // Cross-chain event topic_0 constants
    uint256 public constant TOPIC_COLLATERAL_HEALTH_UPDATED =
        0x8f4e2b91a7c3d6e0f112233445566778899aabbccddeeff00112233445566778;
    uint256 public constant TOPIC_YIELD_SPREAD_DETECTED =
        0x5b1d9c44e2f8a1002233445566778899aabbccddeeff00112233445566778899;
    uint256 public constant TOPIC_AI_REGIME_SIGNAL =
        0xc3a9f701d4e6b21133445566778899aabbccddeeff0011223344556677889900;

    uint64 public constant CALLBACK_GAS_LIMIT = 450_000;

    struct AutomationPolicy {
        address owner;
        uint256 destinationChainId;
        address destinationVault;
        uint256 minHealthFactorBps;     // e.g. 12500 = 1.25x health factor floor
        uint256 minYieldDeltaBps;       // e.g. 180 = 1.80% APY improvement threshold
        uint256 emergencyTopUpAmount;   // Collateral reserve to inject on flash drop
        bool active;
    }

    struct AIRiskState {
        uint256 volatilityScoreBps;     // 0 - 10000 (e.g. 8200 = high volatility)
        uint256 dynamicBufferBps;       // Extra health factor buffer added by AI oracle
        uint256 lastUpdatedBlock;
    }

    address public immutable owner;
    uint256 public totalEmergencyCallbacksEmitted;
    uint256 public totalYieldRebalancesEmitted;
    uint256 public totalAISignalsProcessed;

    mapping(address => AutomationPolicy) public policies;
    AIRiskState public aiRiskState;

    event PolicyConfigured(
        address indexed user,
        uint256 indexed destinationChainId,
        address destinationVault,
        uint256 minHealthFactorBps,
        uint256 minYieldDeltaBps
    );

    event ShieldTriggered(
        address indexed user,
        uint256 indexed originChainId,
        uint256 indexed destinationChainId,
        uint256 observedHealthBps,
        uint256 effectiveThresholdBps,
        uint256 topUpAmount
    );

    event AutonomousRebalanceTriggered(
        address indexed user,
        uint256 indexed destinationChainId,
        uint256 netYieldDeltaBps,
        uint256 rebalanceAmount
    );

    event AIRiskRegimeUpdated(
        uint256 volatilityScoreBps,
        uint256 dynamicBufferBps,
        uint256 blockNumber
    );

    constructor(
        address _service,
        bool _vm,
        uint256 originLendingChainId,
        address originLendingPool,
        uint256 originYieldChainId,
        address originYieldOracle,
        address aiOracleContract
    ) AbstractReactive(_service, _vm) {
        owner = msg.sender;
        aiRiskState = AIRiskState({
            volatilityScoreBps: 2500,
            dynamicBufferBps: 500,
            lastUpdatedBlock: block.number
        });

        if (!_vm && _service != address(0)) {
            service.subscribe(
                originLendingChainId,
                originLendingPool,
                TOPIC_COLLATERAL_HEALTH_UPDATED,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            service.subscribe(
                originYieldChainId,
                originYieldOracle,
                TOPIC_YIELD_SPREAD_DETECTED,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            service.subscribe(
                originLendingChainId,
                aiOracleContract,
                TOPIC_AI_REGIME_SIGNAL,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    /**
     * @notice Configures a "Set It and Forget It" personal automation & liquidation shield policy.
     */
    function configurePolicy(
        address user,
        uint256 destinationChainId,
        address destinationVault,
        uint256 minHealthFactorBps,
        uint256 minYieldDeltaBps,
        uint256 emergencyTopUpAmount
    ) external {
        require(user != address(0), "OmniPulse: invalid user");
        require(destinationVault != address(0), "OmniPulse: invalid vault");
        require(minHealthFactorBps >= 10500, "OmniPulse: health factor floor too low");

        policies[user] = AutomationPolicy({
            owner: user,
            destinationChainId: destinationChainId,
            destinationVault: destinationVault,
            minHealthFactorBps: minHealthFactorBps,
            minYieldDeltaBps: minYieldDeltaBps,
            emergencyTopUpAmount: emergencyTopUpAmount,
            active: true
        });

        emit PolicyConfigured(
            user,
            destinationChainId,
            destinationVault,
            minHealthFactorBps,
            minYieldDeltaBps
        );
    }

    /**
     * @notice Core Reactive VM entry point invoked automatically when subscribed cross-chain logs arrive.
     */
    function react(LogRecord calldata log) external override vmOnly {
        if (log.topic_0 == TOPIC_AI_REGIME_SIGNAL) {
            _handleAIRegimeUpdate(log);
        } else if (log.topic_0 == TOPIC_COLLATERAL_HEALTH_UPDATED) {
            _handleCollateralHealthEvent(log);
        } else if (log.topic_0 == TOPIC_YIELD_SPREAD_DETECTED) {
            _handleYieldSpreadEvent(log);
        }
    }

    function _handleAIRegimeUpdate(LogRecord calldata log) internal {
        (uint256 volatilityScoreBps, uint256 recommendedBufferBps) =
            abi.decode(log.data, (uint256, uint256));

        uint256 cappedBuffer = recommendedBufferBps > 3500 ? 3500 : recommendedBufferBps;
        aiRiskState = AIRiskState({
            volatilityScoreBps: volatilityScoreBps,
            dynamicBufferBps: cappedBuffer,
            lastUpdatedBlock: log.block_number
        });
        totalAISignalsProcessed += 1;

        emit AIRiskRegimeUpdated(volatilityScoreBps, cappedBuffer, log.block_number);
    }

    function _handleCollateralHealthEvent(LogRecord calldata log) internal {
        address user = address(uint160(log.topic_1));
        AutomationPolicy memory policy = policies[user];
        if (!policy.active) {
            return;
        }

        (uint256 observedHealthBps, uint256 debtUsd) = abi.decode(log.data, (uint256, uint256));
        uint256 effectiveThresholdBps = policy.minHealthFactorBps + aiRiskState.dynamicBufferBps;

        if (observedHealthBps < effectiveThresholdBps) {
            bytes memory payload = abi.encodeWithSignature(
                "executeEmergencyCollateralTopUp(address,address,uint256,uint256,uint256)",
                address(0), // RVM ID placeholder injected by Reactive Network
                user,
                policy.emergencyTopUpAmount,
                observedHealthBps,
                debtUsd
            );

            totalEmergencyCallbacksEmitted += 1;
            emit ShieldTriggered(
                user,
                log.chain_id,
                policy.destinationChainId,
                observedHealthBps,
                effectiveThresholdBps,
                policy.emergencyTopUpAmount
            );
            emit Callback(
                policy.destinationChainId,
                policy.destinationVault,
                CALLBACK_GAS_LIMIT,
                payload
            );
        }
    }

    function _handleYieldSpreadEvent(LogRecord calldata log) internal {
        address user = address(uint160(log.topic_1));
        AutomationPolicy memory policy = policies[user];
        if (!policy.active) {
            return;
        }

        (uint256 candidateApyDeltaBps, uint256 rebalanceAmount, address targetPool) =
            abi.decode(log.data, (uint256, uint256, address));

        // Only rebalance when AI volatility regime is safe (< 7500 bps) and spread exceeds user policy
        if (
            aiRiskState.volatilityScoreBps < 7500 &&
            candidateApyDeltaBps >= policy.minYieldDeltaBps
        ) {
            bytes memory payload = abi.encodeWithSignature(
                "executeAutonomousRebalance(address,address,address,uint256,uint256)",
                address(0), // RVM ID placeholder injected by Reactive Network
                user,
                targetPool,
                rebalanceAmount,
                candidateApyDeltaBps
            );

            totalYieldRebalancesEmitted += 1;
            emit AutonomousRebalanceTriggered(
                user,
                policy.destinationChainId,
                candidateApyDeltaBps,
                rebalanceAmount
            );
            emit Callback(
                policy.destinationChainId,
                policy.destinationVault,
                CALLBACK_GAS_LIMIT,
                payload
            );
        }
    }
}
