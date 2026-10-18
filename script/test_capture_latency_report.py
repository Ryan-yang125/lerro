#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("capture_latency_report.py")
SPEC = importlib.util.spec_from_file_location("capture_latency_report", MODULE_PATH)
REPORT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(REPORT)

SENTINEL = "SENTINEL-SECRET-TRANSCRIPT"


def legacy_entry(created_at, **extra):
    entry = {
        "id": "00000000-0000-0000-0000-000000000001",
        "createdAt": created_at,
        "mode": "dictation",
        "rawText": "legacy raw",
        "finalText": "legacy final",
        "duration": 3,
        "applicationName": "Notes",
        "phaseTimings": {"recording": 1.0, "transcription": 0.2, "processing": 0.3, "delivery": 0.1},
    }
    entry.update(extra)
    return entry


def traced_entry(created_at, ready, **extra):
    """An entry whose hotkeyPressed -> listening takes `ready` seconds."""
    entry = legacy_entry(created_at, **extra)
    entry["phaseTimings"]["milestones"] = {
        "hotkeyPressed": 0,
        "hotkeyHandled": 0.01,
        "hudArmed": 0.02,
        "speechStartRequested": ready - 0.1,
        "listening": ready,
        "stopRequested": ready + 2,
        "transcriptionFinished": ready + 2.3,
    }
    entry["phaseTimings"]["outcome"] = "completed"
    return entry


class CaptureLatencyReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "history.json"

    def write(self, entries):
        self.path.write_text(json.dumps(entries), encoding="utf-8")

    def run_report(self, *args, as_json=True):
        out = io.StringIO()
        argv = ["--history", str(self.path), *args] + (["--json"] if as_json else [])
        with contextlib.redirect_stdout(out):
            code = REPORT.run(argv)
        self.assertEqual(code, 0)
        return json.loads(out.getvalue()) if as_json else out.getvalue()

    @staticmethod
    def segment(report, name, key="summaries"):
        return next(row for row in report[key] if row["segment"] == name)

    def test_nearest_rank_percentiles(self):
        values = [float(i) for i in range(1, 11)]
        self.assertEqual(REPORT.percentile(values, 50), 5.0)
        self.assertEqual(REPORT.percentile(values, 90), 9.0)
        self.assertEqual(REPORT.percentile([7.0], 90), 7.0)
        self.assertEqual(REPORT.percentile([1.0, 2.0], 50), 1.0)

    def test_segment_statistics_in_milliseconds(self):
        self.write([traced_entry(f"2026-10-1{i}T10:00:00Z", 0.1 * i) for i in range(1, 6)])
        row = self.segment(self.run_report(), "readyToSpeak")
        self.assertEqual((row["n"], row["p50"], row["p90"], row["max"]), (5, 300, 500, 500))
        steps = self.run_report()["steps"]
        self.assertTrue(all(step["n"] > 0 for step in steps))
        self.assertEqual(steps[0]["segment"], "hotkeyPressed>hotkeyHandled")

    def test_negative_and_missing_values_are_skipped(self):
        bad = traced_entry("2026-10-12T10:00:00Z", 0.5)
        bad["phaseTimings"]["milestones"]["stopRequested"] = 0.2  # before listening
        self.write([traced_entry("2026-10-11T10:00:00Z", 0.4), bad])
        report = self.run_report()
        self.assertEqual(self.segment(report, "recording")["n"], 1)
        self.assertEqual(self.segment(report, "readyToSpeak")["n"], 2)

    def test_filters(self):
        self.write([
            traced_entry("2026-10-10T12:00:00", 0.1, mode="dictation", processingRoute="raw"),
            traced_entry("2026-10-11T12:00:00", 0.2, mode="translation", processingRoute="remote"),
            traced_entry("2026-10-12T12:00:00", 0.3, mode="dictation", processingRoute="local"),
            traced_entry("2026-10-13T12:00:00", 0.4, mode="dictation", processingRoute="localSnippet"),
        ])
        self.assertEqual(self.run_report("--mode", "translation")["entries"], 1)
        self.assertEqual(self.run_report("--route", "local")["entries"], 1)
        self.assertEqual(self.run_report("--route", "localSnippet")["entries"], 1)
        self.assertEqual(self.run_report("--since", "2026-10-12")["entries"], 2)
        self.assertEqual(self.run_report("--until", "2026-10-11")["entries"], 2)
        self.assertEqual(self.run_report("--since", "2026-10-11T00:00", "--until", "2026-10-12T00:00")["entries"], 1)
        last = self.run_report("--last", "2")
        self.assertEqual(last["entries"], 2)
        self.assertEqual(self.segment(last, "readyToSpeak")["max"], 400)
        combined = self.run_report("--mode", "dictation", "--last", "1")
        self.assertEqual(self.segment(combined, "readyToSpeak")["max"], 400)

    def test_slowest_ordering(self):
        self.write([
            traced_entry("2026-10-10T12:00:00Z", 0.3, applicationName="Slow"),
            traced_entry("2026-10-11T12:00:00Z", 0.9, applicationName="Slowest"),
            traced_entry("2026-10-12T12:00:00Z", 0.1, applicationName="Fast"),
        ])
        slowest = self.run_report("--slowest", "2")["slowest"]
        self.assertEqual([s["applicationName"] for s in slowest], ["Slowest", "Slow"])
        self.assertEqual(slowest[0]["readyToSpeak"], 900)
        steps = slowest[0]["topSteps"]
        self.assertTrue(0 < len(steps) <= 3)
        startup_names = {name for name, _, _ in REPORT.STARTUP_STEPS}
        self.assertTrue(all(s["segment"] in startup_names for s in steps))
        self.assertEqual([s["ms"] for s in steps], sorted((s["ms"] for s in steps), reverse=True))

    def test_unknown_milestone_key_is_ignored(self):
        entry = traced_entry("2026-10-10T12:00:00Z", 0.4)
        entry["phaseTimings"]["milestones"]["futureThing"] = 1.0
        self.write([entry])
        report = self.run_report()
        self.assertEqual(report["entriesWithMilestones"], 1)
        self.assertNotIn("futureThing", json.dumps(report))

    def test_legacy_only_file_reports_no_milestones(self):
        self.write([legacy_entry("2026-10-10T12:00:00Z"), legacy_entry("2026-10-11T12:00:00Z")])
        text = self.run_report(as_json=False)
        self.assertIn("No entries with capture milestones yet", text)
        self.assertIn("entries considered: 2", text)
        report = self.run_report()
        self.assertEqual(report["entriesWithMilestones"], 0)
        self.assertEqual(report["legacy"]["transcription"]["p50"], 200)
        self.assertEqual(report["legacy"]["processing"]["n"], 2)

    def test_legacy_line_is_printed_with_milestones(self):
        self.write([traced_entry("2026-10-10T12:00:00Z", 0.4)])
        text = self.run_report(as_json=False)
        self.assertIn("Legacy phase timings: transcription n=1 p50=200", text)
        self.assertIn("Slowest 5 by readyToSpeak", text)

    def test_text_content_is_never_printed(self):
        entry = traced_entry(
            "2026-10-10T12:00:00Z", 0.4,
            rawText=SENTINEL, finalText=SENTINEL, processedText=SENTINEL, windowTitle=SENTINEL,
        )
        self.write([entry])
        self.assertNotIn(SENTINEL, self.run_report(as_json=False))
        self.assertNotIn(SENTINEL, json.dumps(self.run_report()))

    def test_input_file_is_not_modified(self):
        self.write([traced_entry("2026-10-10T12:00:00Z", 0.4, rawText=SENTINEL)])
        os.utime(self.path, (1_700_000_000, 1_700_000_000))
        before_bytes = self.path.read_bytes()
        before_stat = self.path.stat()
        self.run_report(as_json=False)
        self.run_report()
        after_stat = self.path.stat()
        self.assertEqual(self.path.read_bytes(), before_bytes)
        self.assertEqual(after_stat.st_mtime_ns, before_stat.st_mtime_ns)
        self.assertEqual(after_stat.st_size, before_stat.st_size)

    def test_steps_match_chain_pairs(self):
        names = [name for name, _, _ in REPORT.STEPS]
        self.assertEqual(names[0], "hotkeyPressed>hotkeyHandled")
        self.assertNotIn("listening>stopRequested", names)
        self.assertEqual(len(names), 17 + 6)
        self.assertEqual(len(REPORT.SUMMARIES), 11)

    def test_missing_file_exits_nonzero(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(REPORT.run(["--history", str(self.path)]), 2)


if __name__ == "__main__":
    unittest.main()
