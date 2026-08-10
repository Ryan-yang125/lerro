#!/usr/bin/env python3
"""Validate and score Lerro's fixed contextual-dictation benchmark."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import unicodedata
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORPUS = ROOT / "benchmarks" / "contextual-dictation-v1.3.json"
REQUIRED_FIELDS = {
    "id", "locale", "applicationName", "bundleIdentifier", "category",
    "transcript", "expected", "protectedSpans", "formatting",
}


def normalized(value: str) -> str:
    return " ".join(unicodedata.normalize("NFC", value).split())


def load_corpus(path: Path) -> list[dict]:
    document = json.loads(path.read_text(encoding="utf-8"))
    cases = document.get("cases", [])
    if document.get("caseCount") != 60 or len(cases) != 60:
        raise ValueError("benchmark must contain exactly 60 cases")
    ids = [case.get("id") for case in cases]
    if len(set(ids)) != len(ids):
        raise ValueError("benchmark case IDs must be unique")
    for case in cases:
        missing = REQUIRED_FIELDS.difference(case)
        if missing:
            raise ValueError(f"{case.get('id', '<unknown>')} is missing {sorted(missing)}")
        if not case["transcript"].strip() or not case["expected"].strip():
            raise ValueError(f"{case['id']} has empty benchmark text")
    if len({case["bundleIdentifier"] for case in cases}) != 5:
        raise ValueError("benchmark must cover exactly five application contexts")
    if {case["locale"] for case in cases} != {"zh-CN", "en-US", "zh-en"}:
        raise ValueError("benchmark must cover Chinese, English, and mixed speech")
    return cases


def formatting_score(case: dict, output: str) -> float:
    expected = case["expected"]
    kind = case["formatting"]
    if kind == "bullets":
        expected_bullets = sum(line.startswith("- ") for line in expected.splitlines())
        output_bullets = sum(line.startswith("- ") for line in output.splitlines())
        return 1.0 if output_bullets == expected_bullets else 0.0
    if kind == "code":
        return 1.0 if output.count("`") == expected.count("`") else 0.0
    if kind == "short":
        return 1.0 if "\n" not in output.strip() else 0.0
    return 1.0 if output.count("\n") == expected.count("\n") else 0.0


def percentile(values: list[float], percentile_value: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(percentile_value * len(ordered)) - 1)
    return ordered[index]


def score(cases: list[dict], results_document: dict) -> dict:
    results = {item["id"]: item for item in results_document.get("results", [])}
    if set(results) != {case["id"] for case in cases}:
        missing = sorted({case["id"] for case in cases}.difference(results))
        extra = sorted(set(results).difference(case["id"] for case in cases))
        raise ValueError(f"result IDs mismatch; missing={missing}, extra={extra}")

    exact = 0
    similarities: list[float] = []
    protected_hits = 0
    protected_total = 0
    formatting: list[float] = []
    latencies: list[float] = []
    per_case = []
    for case in cases:
        result = results[case["id"]]
        output = result.get("output", "")
        expected = case["expected"]
        exact_match = normalized(output) == normalized(expected)
        exact += int(exact_match)
        similarity = SequenceMatcher(None, normalized(expected), normalized(output)).ratio()
        similarities.append(similarity)
        hits = sum(span in output for span in case["protectedSpans"])
        protected_hits += hits
        protected_total += len(case["protectedSpans"])
        format_value = formatting_score(case, output)
        formatting.append(format_value)
        latency = float(result.get("latencyMilliseconds", 0))
        if latency > 0:
            latencies.append(latency)
        per_case.append({
            "id": case["id"],
            "exact": exact_match,
            "similarity": round(similarity, 4),
            "protectedSpanAccuracy": round(hits / max(1, len(case["protectedSpans"])), 4),
            "formatting": format_value,
            "latencyMilliseconds": latency,
        })

    summary = {
        "caseCount": len(cases),
        "exactMatchRate": round(exact / len(cases), 4),
        "meanSimilarity": round(statistics.fmean(similarities), 4),
        "protectedSpanAccuracy": round(protected_hits / max(1, protected_total), 4),
        "formattingAccuracy": round(statistics.fmean(formatting), 4),
        "latencyP50Milliseconds": round(percentile(latencies, 0.50), 1) if latencies else None,
        "latencyP95Milliseconds": round(percentile(latencies, 0.95), 1) if latencies else None,
    }
    return {"summary": summary, "cases": per_case}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--results", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()

    cases = load_corpus(args.corpus)
    if args.validate or args.results is None:
        print(f"validated {len(cases)} contextual-dictation cases")
        return 0

    report = score(cases, json.loads(args.results.read_text(encoding="utf-8")))
    encoded = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
