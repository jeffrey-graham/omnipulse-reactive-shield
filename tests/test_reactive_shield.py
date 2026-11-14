#!/usr/bin/env python3
"""Unit test suite for OmniPulse Reactive AI (Reactive Omni Buildathon)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src.reactive_ai_automator import (
    AIRiskScoringEngine,
    AutomationPolicy,
    LogRecord,
    OmniPulseReactiveEngine,
    RVM_ID_PLACEHOLDER,
    TOPIC_AI_REGIME_SIGNAL,
    TOPIC_COLLATERAL_HEALTH_UPDATED,
    TOPIC_YIELD_SPREAD_DETECTED,
    run_omnipulse_simulation,
)


class TestOmniPulseReactiveShield(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = OmniPulseReactiveEngine(vm_mode=True)
        self.user = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
        self.vault = "0x9988776655443322110099887766554433221100"
        self.engine.configure_policy(
            AutomationPolicy(
                user=self.user,
                destination_chain_id=42161,
                destination_vault=self.vault,
                min_health_factor_bps=12500,
                min_yield_delta_bps=180,
                emergency_top_up_usd=15000,
            )
        )

    def test_solidity_contract_implements_reactive_interfaces(self) -> None:
        sol_path = ROOT / "contracts" / "OmniPulseReactiveShield.sol"
        self.assertTrue(sol_path.exists(), "OmniPulseReactiveShield.sol must exist")
        source = sol_path.read_text(encoding="utf-8")
        self.assertIn("interface IReactive", source)
        self.assertIn("abstract contract AbstractReactive is IReactive", source)
        self.assertIn("function react(LogRecord calldata log) external override vmOnly", source)
        self.assertIn("emit Callback(", source)
        self.assertIn("service.subscribe(", source)

    def test_vm_only_modifier_and_policy_validation(self) -> None:
        rn_engine = OmniPulseReactiveEngine(vm_mode=False)
        with self.assertRaises(PermissionError):
            rn_engine.react(
                LogRecord(
                    chain_id=8453,
                    contract_address="0x1234",
                    topic_0=TOPIC_COLLATERAL_HEALTH_UPDATED,
                    topic_1=self.user,
                    data={"observedHealthBps": 11000, "debtUsd": 50000},
                )
            )

        with self.assertRaises(ValueError):
            self.engine.configure_policy(
                AutomationPolicy(
                    user=self.user,
                    destination_chain_id=42161,
                    destination_vault=self.vault,
                    min_health_factor_bps=10100,  # Too low (< 10500)
                    min_yield_delta_bps=100,
                    emergency_top_up_usd=5000,
                )
            )

    def test_track3_ai_risk_scoring_and_regime_update(self) -> None:
        ai_scorer = AIRiskScoringEngine()
        calm = ai_scorer.evaluate_market_telemetry(1.2, 5.0, 4.0, 100)
        self.assertEqual(calm["regimeLabel"], "CALM_MARKET")
        self.assertLess(calm["volatilityScoreBps"], 4500)

        crash = ai_scorer.evaluate_market_telemetry(8.5, 65.0, -90.0, 105)
        self.assertEqual(crash["regimeLabel"], "FLASH_CRASH_HIGH_RISK")
        self.assertGreaterEqual(crash["volatilityScoreBps"], 7500)
        self.assertGreaterEqual(crash["recommendedBufferBps"], 2000)

    def test_track1_emergency_liquidation_shield_callback(self) -> None:
        # AI raises dynamic buffer to 2200 bps -> effective threshold = 12500 + 2200 = 14700 bps
        self.engine.react(
            LogRecord(
                chain_id=11155111,
                contract_address="0xAIOracle",
                topic_0=TOPIC_AI_REGIME_SIGNAL,
                topic_1=self.user,
                data={"volatilityScoreBps": 8800, "recommendedBufferBps": 2200},
            )
        )
        cb = self.engine.react(
            LogRecord(
                chain_id=11155111,
                contract_address="0xLendingPool",
                topic_0=TOPIC_COLLATERAL_HEALTH_UPDATED,
                topic_1=self.user,
                data={"observedHealthBps": 13900, "debtUsd": 85000},
            )
        )
        self.assertIsNotNone(cb)
        self.assertEqual(cb.destination_chain_id, 42161)  # type: ignore[union-attr]
        self.assertEqual(cb.rvm_id_injected, RVM_ID_PLACEHOLDER)  # type: ignore[union-attr]
        self.assertIn("executeEmergencyCollateralTopUp", cb.function_signature)  # type: ignore[union-attr]

    def test_track2_set_it_and_forget_it_yield_rebalance_and_crash_gate(self) -> None:
        # In calm market, +240 bps spread (> 180 bps floor) emits rebalance callback
        cb = self.engine.react(
            LogRecord(
                chain_id=8453,
                contract_address="0xYieldMonitor",
                topic_0=TOPIC_YIELD_SPREAD_DETECTED,
                topic_1=self.user,
                data={
                    "candidateApyDeltaBps": 240,
                    "rebalanceAmountUsd": 50000,
                    "targetPool": "0xArbMorphoVault",
                },
            )
        )
        self.assertIsNotNone(cb)
        self.assertIn("executeAutonomousRebalance", cb.function_signature)  # type: ignore[union-attr]

        # During FLASH_CRASH_HIGH_RISK (>=7500 bps), yield rebalance is gated for safety
        self.engine.react(
            LogRecord(
                chain_id=11155111,
                contract_address="0xAIOracle",
                topic_0=TOPIC_AI_REGIME_SIGNAL,
                topic_1=self.user,
                data={"volatilityScoreBps": 8500, "recommendedBufferBps": 2100},
            )
        )
        blocked_cb = self.engine.react(
            LogRecord(
                chain_id=8453,
                contract_address="0xYieldMonitor",
                topic_0=TOPIC_YIELD_SPREAD_DETECTED,
                topic_1=self.user,
                data={
                    "candidateApyDeltaBps": 310,
                    "rebalanceAmountUsd": 50000,
                    "targetPool": "0xArbMorphoVault",
                },
            )
        )
        self.assertIsNone(blocked_cb)

    def test_full_three_track_simulation_suite(self) -> None:
        sim = run_omnipulse_simulation()
        self.assertEqual(len(sim["tracksCovered"]), 3)
        self.assertEqual(sim["summaryMetrics"]["totalEmergencyCallbacksEmitted"], 1)
        self.assertEqual(sim["summaryMetrics"]["totalYieldRebalancesEmitted"], 1)
        self.assertEqual(sim["summaryMetrics"]["totalAISignalsProcessed"], 1)

    def test_policy_access_control_and_trusted_origin_guards(self) -> None:
        attacker = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        with self.assertRaises(PermissionError):
            self.engine.configure_policy(
                AutomationPolicy(
                    user=self.user,
                    destination_chain_id=42161,
                    destination_vault=attacker,
                    min_health_factor_bps=12500,
                    min_yield_delta_bps=180,
                    emergency_top_up_usd=15000,
                ),
                caller=attacker,
            )

        hardened = OmniPulseReactiveEngine(
            vm_mode=True,
            trusted_ai_oracle="0xAIOracle",
            trusted_lending_pool="0xLendingPool",
        )
        with self.assertRaises(PermissionError):
            hardened.react(
                LogRecord(
                    chain_id=11155111,
                    contract_address=attacker,
                    topic_0=TOPIC_AI_REGIME_SIGNAL,
                    topic_1=self.user,
                    data={"volatilityScoreBps": 9900, "recommendedBufferBps": 3500},
                )
            )


if __name__ == "__main__":
    unittest.main()
