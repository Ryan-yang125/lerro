#!/usr/bin/env python3

import importlib.util
import json
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("benchmark_contextual_dictation.py")
SPEC = importlib.util.spec_from_file_location("benchmark_contextual_dictation", MODULE_PATH)
BENCHMARK = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BENCHMARK)


class ContextualBenchmarkTests(unittest.TestCase):
    def test_fixed_corpus_and_reference_score(self):
        cases = BENCHMARK.load_corpus(BENCHMARK.DEFAULT_CORPUS)
        results = {
            "results": [
                {"id": case["id"], "output": case["expected"], "latencyMilliseconds": 100 + index}
                for index, case in enumerate(cases)
            ]
        }
        report = BENCHMARK.score(cases, results)["summary"]
        self.assertEqual(report["caseCount"], 60)
        self.assertEqual(report["exactMatchRate"], 1.0)
        self.assertEqual(report["meanSimilarity"], 1.0)
        self.assertEqual(report["protectedSpanAccuracy"], 1.0)
        self.assertEqual(report["formattingAccuracy"], 1.0)
        self.assertEqual(report["latencyP50Milliseconds"], 129.0)
        self.assertEqual(report["latencyP95Milliseconds"], 156.0)

    def test_rejects_incomplete_results(self):
        cases = BENCHMARK.load_corpus(BENCHMARK.DEFAULT_CORPUS)
        with self.assertRaises(ValueError):
            BENCHMARK.score(cases, {"results": []})


if __name__ == "__main__":
    unittest.main()
