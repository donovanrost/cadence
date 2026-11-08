"""Safety and continuity checks for the destructive test runner."""
import unittest
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import lab


class LabTest(unittest.TestCase):
    def test_process_kill_verifies_sigkill_before_retiring_the_pod(self):
        pod = {"metadata": {"namespace": lab.NAMESPACE, "uid": "uid", "labels": lab.labels("cadence")},
               "status": {"containerStatuses": [{"name": "cadence", "containerID": "docker://container",
                                                  "state": {"running": {}}}]}}
        stopped = {"Running": False, "ExitCode": 137, "OOMKilled": False}
        calls = []
        def kube(*args, **kwargs):
            calls.append(args)
            return SimpleNamespace(stdout=json.dumps(pod))
        def command(args, **kwargs):
            calls.append(tuple(args))
            return SimpleNamespace(stdout=json.dumps(stopped))
        with patch.object(lab, "kube", side_effect=kube), patch.object(lab, "command", side_effect=command):
            result = lab.kill_pod_process("pod")
        self.assertEqual(result["signal"], "SIGKILL")
        self.assertEqual(calls[1], ("docker", "--context", "orbstack", "kill", "--signal", "KILL", "container"))
        self.assertEqual(calls[3][:3], ("delete", "pod", "pod"))
        calls.clear()
        stopped["ExitCode"] = 0
        with patch.object(lab, "kube", side_effect=kube), patch.object(lab, "command", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "Unexpected container state"):
                lab.kill_pod_process("pod")
        self.assertFalse(any(call[0] == "delete" for call in calls))
        pod["metadata"]["labels"] = {}
        with patch.object(lab, "kube", side_effect=kube), patch.object(lab, "command") as command:
            with self.assertRaisesRegex(RuntimeError, "outside"):
                lab.kill_pod_process("pod")
            command.assert_not_called()

    def test_archive_counters_cross_connections_and_wrap_without_hiding_gaps(self):
        batches = [{"scid": i, "vcid": 0, "receipt_time": "first", "sequences": [255, 254],
                    "transport_session_id": "old"} for i in range(1, 11)]
        batches.append({"scid": 1, "vcid": 0, "receipt_time": "next", "sequences": [1, 0],
                        "transport_session_id": "new"})
        result = lab.frame_counter_continuity(batches)
        self.assertTrue(result["passed"])
        self.assertEqual(result["session_changes_checked"], 1)
        batches[-1]["sequences"] = [2, 3]
        result = lab.frame_counter_continuity(batches)
        self.assertFalse(result["passed"])
        self.assertEqual(result["issues"][0]["expected"], 0)
        self.assertTrue(result["issues"][0]["session_changed"])

    def test_archive_counter_audit_rejects_duplicates_ambiguous_batches_and_missing_feeds(self):
        for sequences in ([1, 1], [1, 3], list(range(256)), []):
            result = lab.frame_counter_continuity([
                {"scid": 1, "vcid": 0, "receipt_time": "now", "sequences": sequences}])
            self.assertFalse(result["passed"])
            self.assertEqual(len(result["issues"]), 1)
        self.assertFalse(lab.frame_counter_continuity([])["passed"])

    def test_journal_exposure_excludes_historical_and_surviving_pods(self):
        snapshot = {"streams": [
            {"pod_uid": uid, "bytes_after_checkpoint": {"processing": processing, "archive": archive},
             "unscanned_bytes": unscanned}
            for uid, processing, archive, unscanned in [
                ("retired", 20, 10, 3), ("retired", 5, 0, 0), ("historical", 999, 999, 99),
                ("surviving", 300, 300, 30)]]}
        self.assertEqual(lab.journal_exposure(snapshot, {"retired"}), {
            "pod_uids": ["retired"], "streams": 2,
            "bytes_after_checkpoint": {"processing": 25, "archive": 10}, "unscanned_bytes": 3})

    def test_startup_command_dispatches_requested_replica_count(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(lab, "STATE", Path(directory)), patch.object(lab, "settings", return_value={}):
                with patch.object(lab, "startup", return_value=0) as startup:
                    with patch.object(lab.sys, "argv", ["lab.py", "startup", "--replicas", "3"]):
                        self.assertEqual(lab.main(), 0)
                    startup.assert_called_once_with(3)

    def test_startup_requires_stopped_deployments_before_scaling(self):
        for deployment in ({"spec": {"replicas": 3}},
                           {"spec": {"replicas": 0}, "status": {"replicas": 1}}):
            with patch.object(lab, "kube", return_value=SimpleNamespace(stdout=json.dumps(deployment))) as kube:
                with self.assertRaisesRegex(RuntimeError, "scaled to zero"):
                    lab.startup(3)
                self.assertEqual(kube.call_count, 1)
                self.assertEqual(kube.call_args.args[:2], ("get", "deployment"))

    def test_active_receiver_requires_established_ingress_socket(self):
        tables = """sl local_address rem_address st
  0: 00000000:A474 00000000:0000 0A
  1: 0100007F:A474 0100007F:4321 01
  2: 0100007F:0FA1 0100007F:4322 01
  3: 0100007F:A47D 0100007F:4323 01
"""
        self.assertEqual(lab.count_ingress_connections(tables), 2)

    def test_diagnostics_and_unhealthy_start_cannot_pass_after_recovery(self):
        samples = [{"continuity_ok": True}]
        self.assertTrue(lab.continuity_passed(True, False, True, samples))
        self.assertFalse(lab.continuity_passed(True, True, True, samples))
        self.assertFalse(lab.continuity_passed(False, False, True, samples))
        self.assertFalse(lab.continuity_passed(True, False, False, samples))

    def test_namespace_filter_uses_required_annotation(self):
        with patch.object(lab, "apply") as apply, patch.object(lab, "kube") as kube:
            kube.return_value.returncode = 0
            lab.init_namespace()
        namespace = apply.call_args.args[0][0]
        self.assertEqual(namespace["metadata"]["name"], "cadence-chaos")
        self.assertEqual(namespace["metadata"]["annotations"], {"chaos-mesh.org/inject": "enabled"})

    def test_failed_injection_does_not_pass_and_recovered_injection_is_retained(self):
        experiment = {"status": {"experiment": {"containerRecords": [
            {"phase": "Not Injected", "injectedCount": 0}]}}}
        self.assertFalse(lab.injection_observed(experiment))
        experiment["status"]["experiment"]["containerRecords"][0] = {
            "phase": "Recovered", "injectedCount": 1}
        self.assertTrue(lab.injection_observed(experiment))

    def test_all_ten_feeds_are_required(self):
        sample = {"http_status": 200, "telemetry": [
            {"scid": i, "age_seconds": 1} for i in range(1, 11)]}
        self.assertTrue(lab.healthy(sample, 10))
        sample["telemetry"].pop()
        self.assertFalse(lab.healthy(sample, 10))

    def test_stale_feed_or_http_failure_fails_continuity(self):
        sample = {"http_status": 200, "telemetry": [
            {"scid": i, "age_seconds": 1} for i in range(1, 11)]}
        sample["telemetry"][0]["age_seconds"] = 11
        self.assertFalse(lab.healthy(sample, 10))
        sample["telemetry"][0]["age_seconds"] = 1
        sample["http_status"] = 503
        self.assertFalse(lab.healthy(sample, 10))

    def test_manifests_are_isolated_and_rollouts_preserve_http_capacity(self):
        manifests = lab.manifests({"server": "test:1", "simulator": "simulator:1"})
        for group in manifests.values():
            for obj in group:
                self.assertEqual(obj["metadata"]["namespace"], "cadence-chaos")
        app = manifests["app"][1]["spec"]
        self.assertEqual(app["replicas"], 3)
        self.assertEqual(app["strategy"]["rollingUpdate"], {"maxUnavailable": 0, "maxSurge": 1})
        container = app["template"]["spec"]["containers"][0]
        self.assertEqual(container["readinessProbe"]["httpGet"]["path"], "/health/ready")
        self.assertEqual(container["livenessProbe"]["httpGet"]["path"], "/health/live")
        self.assertEqual(container["lifecycle"]["preStop"]["exec"]["command"], [
            "/app/bin/cadence_web", "rpc", "CadenceWeb.Release.drain()"])
        self.assertGreater(app["template"]["spec"]["terminationGracePeriodSeconds"], 65)
        self.assertEqual(manifests["traffic"][0]["spec"]["strategy"], {"type": "Recreate"})
        self.assertEqual(app["template"]["spec"]["volumes"], [
            {"name": "data", "persistentVolumeClaim": {"claimName": "cadence-archives"}}])
        values = {item["name"]: item.get("value") for item in container["env"]}
        self.assertEqual(values["CADENCE_INGRESS_JOURNAL_PATH"], "/data/journal/$(POD_UID)")


if __name__ == "__main__":
    unittest.main()
