#!/usr/bin/env python3
"""Read-only latency report over Lerro capture history.

Reads history.json (a JSON array of HistoryEntry objects) and summarizes the
capture milestones stored in each entry's phaseTimings. The file is opened
read-only. No text content (rawText, finalText, processedText, windowTitle) is
ever printed; applicationName is shown in the slowest-entries list.

Percentiles use the nearest-rank method on the sorted values: the p-th
percentile of n values is the value at 1-based rank ceil(p / 100 * n).
Negative and missing values are skipped.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

DEFAULT_HISTORY = Path.home() / "Library/Application Support/app.lerro.mac/history.json"

# Source of truth: Sources/LerroCore/Models/CaptureTrace.swift
# (CaptureMilestone.startupChain / analyzerChain / finishChain and CaptureTraceSegment.summaries).
# Keep these lists identical to the Swift definitions. Entries recorded before
# the microphone moved ahead of analyzer preparation have the old order, so
# steps that run backwards for them are skipped.
STARTUP_CHAIN = [
    "hotkeyPressed", "hotkeyHandled", "hudArmed", "permissionsChecked", "hotkeysConfigured",
    "contextCaptured", "speechResourcesReady", "speechStartRequested", "speechLocaleResolved",
    "audioEngineCreated", "audioInputConfigured", "audioEngineStarted", "listening",
]
ANALYZER_CHAIN = [
    "audioEngineStarted", "speechAssetsReserved", "audioFormatNegotiated", "analyzerCreated",
    "analyzerPrepared",
]
FINISH_CHAIN = [
    "stopRequested", "transcriptionFinished", "processingFinished", "deliveryCommitted",
    "deliveryFinished", "historySaved", "finished",
]

# (name, from, to)
SUMMARIES = [
    ("readyToSpeak", "hotkeyPressed", "listening"),
    ("hotkeyDispatch", "hotkeyPressed", "hotkeyHandled"),
    ("appPreparation", "hotkeyHandled", "speechStartRequested"),
    ("speechStartup", "speechStartRequested", "listening"),
    ("analyzerStartup", "audioEngineStarted", "analyzerPrepared"),
    ("firstAudio", "hotkeyPressed", "firstAudioBuffer"),
    ("firstPartial", "hotkeyPressed", "firstPartial"),
    ("recording", "listening", "stopRequested"),
    ("transcription", "stopRequested", "transcriptionFinished"),
    ("processing", "transcriptionFinished", "processingFinished"),
    ("delivery", "processingFinished", "deliveryFinished"),
    ("stopToDelivered", "stopRequested", "deliveryCommitted"),
]

STARTUP_STEPS = [(f"{a}>{b}", a, b) for a, b in zip(STARTUP_CHAIN, STARTUP_CHAIN[1:])]
ANALYZER_STEPS = [(f"{a}>{b}", a, b) for a, b in zip(ANALYZER_CHAIN, ANALYZER_CHAIN[1:])]
FINISH_STEPS = [(f"{a}>{b}", a, b) for a, b in zip(FINISH_CHAIN, FINISH_CHAIN[1:])]
STEPS = STARTUP_STEPS + ANALYZER_STEPS + FINISH_STEPS

KNOWN_MILESTONES = (
    set(STARTUP_CHAIN) | set(ANALYZER_CHAIN) | set(FINISH_CHAIN) | {"firstAudioBuffer", "firstPartial"}
)
LEGACY_FIELDS = ("transcription", "processing", "delivery")
MODES = ("dictation", "translation", "ask")
ROUTES = ("raw", "remote", "local", "localSnippet", "appleTranslation")


def percentile(sorted_values: list[float], p: int) -> float:
    """Nearest-rank percentile of an ascending list."""
    n = len(sorted_values)
    rank = max(1, -(-p * n // 100))
    return sorted_values[rank - 1]


def ms(seconds: float) -> int:
    return int(seconds * 1000 + 0.5)


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def parse_created_at(value) -> datetime | None:
    if not isinstance(value, str):
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.astimezone()  # naive input is read as local time
    return parsed.astimezone()


def parse_bound(value: str, end: bool) -> datetime:
    """Parse a local-time --since/--until value. A date-only --until covers that whole day."""
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid date/time: {value!r}") from None
    if end and len(value) <= 10:
        parsed += timedelta(days=1)
    return parsed.astimezone()


def milestones_of(entry: dict) -> dict[str, float]:
    timings = entry.get("phaseTimings")
    raw = timings.get("milestones") if isinstance(timings, dict) else None
    if not isinstance(raw, dict):
        return {}
    return {k: float(v) for k, v in raw.items() if k in KNOWN_MILESTONES and is_number(v)}


def segment_seconds(milestones: dict[str, float], start: str, end: str) -> float | None:
    if start not in milestones or end not in milestones:
        return None
    value = milestones[end] - milestones[start]
    return value if value >= 0 else None


def stats(values: list[float]) -> dict | None:
    values = sorted(v for v in values if v >= 0)
    if not values:
        return None
    return {
        "n": len(values),
        "p50": ms(percentile(values, 50)),
        "p90": ms(percentile(values, 90)),
        "max": ms(values[-1]),
    }


def load_entries(path: Path) -> list[dict]:
    with open(path, "rb") as handle:  # read-only
        document = json.loads(handle.read().decode("utf-8"))
    if not isinstance(document, list):
        raise ValueError("history file must contain a JSON array")
    return [e for e in document if isinstance(e, dict)]


def filter_entries(entries, since, until, mode, route, last):
    kept = []
    for entry in entries:
        created = parse_created_at(entry.get("createdAt"))
        if since or until:
            if created is None:
                continue
            if since and created < since:
                continue
            if until and created >= until:
                continue
        if mode and entry.get("mode") != mode:
            continue
        if route and entry.get("processingRoute") != route:
            continue
        kept.append((created, entry))
    kept.sort(key=lambda item: (item[0] is None, item[0] or datetime.min.astimezone()))
    if last is not None:
        kept = kept[-last:] if last > 0 else []
    return kept


def safe_label(value) -> str:
    text = value if isinstance(value, str) else ""
    return "".join(ch for ch in text if ch.isprintable())


def build_report(path: Path, kept, slowest_count: int) -> dict:
    dates = [created for created, _ in kept if created is not None]
    with_milestones = [(c, e, milestones_of(e)) for c, e in kept]
    with_milestones = [item for item in with_milestones if item[2]]

    summaries = []
    for name, start, end in SUMMARIES:
        s = stats([v for _, _, m in with_milestones if (v := segment_seconds(m, start, end)) is not None])
        summaries.append({"segment": name, **(s or {"n": 0})})

    steps = []
    for name, start, end in STEPS:
        s = stats([v for _, _, m in with_milestones if (v := segment_seconds(m, start, end)) is not None])
        if s:
            steps.append({"segment": name, **s})

    slowest = []
    for created, entry, m in with_milestones:
        ready = segment_seconds(m, "hotkeyPressed", "listening")
        if ready is None:
            continue
        durations = [(name, v) for name, a, b in STARTUP_STEPS if (v := segment_seconds(m, a, b)) is not None]
        durations.sort(key=lambda item: item[1], reverse=True)
        slowest.append({
            "createdAt": created.isoformat(timespec="seconds") if created else None,
            "mode": entry.get("mode"),
            "processingRoute": entry.get("processingRoute"),
            "applicationName": safe_label(entry.get("applicationName")),
            "readyToSpeak": ms(ready),
            "topSteps": [{"segment": n, "ms": ms(v)} for n, v in durations[:3]],
        })
    slowest.sort(key=lambda item: item["readyToSpeak"], reverse=True)

    legacy = {}
    for field in LEGACY_FIELDS:
        values = []
        for _, entry in kept:
            timings = entry.get("phaseTimings")
            value = timings.get(field) if isinstance(timings, dict) else None
            if is_number(value):
                values.append(float(value))
        legacy[field] = stats(values) or {"n": 0}

    return {
        "file": str(path),
        "entries": len(kept),
        "entriesWithMilestones": len(with_milestones),
        "from": min(dates).isoformat(timespec="seconds") if dates else None,
        "to": max(dates).isoformat(timespec="seconds") if dates else None,
        "summaries": summaries,
        "steps": steps,
        "slowest": slowest[:max(slowest_count, 0)],
        "legacy": legacy,
    }


def table(rows: list[dict]) -> list[str]:
    width = max([len("segment")] + [len(r["segment"]) for r in rows])
    lines = [f"{'segment':<{width}}  {'n':>5}  {'p50':>7}  {'p90':>7}  {'max':>7}"]
    for r in rows:
        if r["n"] == 0:
            lines.append(f"{r['segment']:<{width}}  {0:>5}  {'-':>7}  {'-':>7}  {'-':>7}")
        else:
            lines.append(f"{r['segment']:<{width}}  {r['n']:>5}  {r['p50']:>7}  {r['p90']:>7}  {r['max']:>7}")
    return lines


def render_text(report: dict, slowest_count: int) -> str:
    out = [
        f"file: {report['file']}",
        f"entries considered: {report['entries']}",
        f"entries with milestones: {report['entriesWithMilestones']}",
        f"date range: {report['from'] or '-'} .. {report['to'] or '-'}",
        "times in milliseconds; percentiles are nearest-rank",
        "",
    ]
    if report["entriesWithMilestones"] == 0:
        out.append("No entries with capture milestones yet. Record with a build that includes capture tracing.")
    else:
        out += ["Summary segments", *table(report["summaries"]), "", "Steps (chain order)", *table(report["steps"])]
        out += ["", f"Slowest {slowest_count} by readyToSpeak"]
        for item in report["slowest"]:
            steps = ", ".join(f"{s['segment']} {s['ms']}" for s in item["topSteps"])
            out.append(
                f"{item['createdAt'] or '-'}  {item['mode'] or '-'}  {item['processingRoute'] or '-'}  "
                f"{item['applicationName'] or '-'}  readyToSpeak {item['readyToSpeak']}  [{steps}]"
            )
    legacy = " | ".join(
        f"{field} n={v['n']}" + (f" p50={v['p50']} p90={v['p90']}" if v["n"] else "")
        for field, v in report["legacy"].items()
    )
    out += ["", f"Legacy phase timings: {legacy}"]
    return "\n".join(out)


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY, help="path to history.json")
    parser.add_argument("--since", type=lambda v: parse_bound(v, False), help="local YYYY-MM-DD[THH:MM]")
    parser.add_argument("--until", type=lambda v: parse_bound(v, True),
                        help="local YYYY-MM-DD[THH:MM]; a bare date includes that whole day")
    parser.add_argument("--mode", choices=MODES)
    parser.add_argument("--route", choices=ROUTES)
    parser.add_argument("--last", type=int, help="keep only the most recent N entries after filtering")
    parser.add_argument("--slowest", type=int, default=5, help="number of slowest entries to list")
    parser.add_argument("--json", action="store_true", help="print aggregates as JSON")
    args = parser.parse_args(argv)

    try:
        entries = load_entries(args.history)
    except (OSError, ValueError) as error:
        print(f"cannot read history: {type(error).__name__}", file=sys.stderr)
        return 2

    kept = filter_entries(entries, args.since, args.until, args.mode, args.route, args.last)
    report = build_report(args.history, kept, args.slowest)
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(render_text(report, args.slowest))
    return 0


if __name__ == "__main__":
    sys.exit(run())
