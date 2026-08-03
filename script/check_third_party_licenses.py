#!/usr/bin/env python3
"""Verify third-party license claims against resolved source files."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys


def fail(message: str) -> None:
    print(f"third-party license check: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def detected_license(path: pathlib.Path) -> str:
    text = path.read_text(encoding="utf-8", errors="replace")
    if "Apache License" in text and "Version 2.0" in text:
        return "Apache-2.0"
    if "MIT License" in text or (
        "Permission is hereby granted, free of charge" in text
        and "THE SOFTWARE IS PROVIDED \"AS IS\"" in text
    ):
        return "MIT"
    return "UNKNOWN"


def first_license(directory: pathlib.Path) -> pathlib.Path:
    candidates = sorted(
        path
        for path in directory.glob("LICENSE*")
        if path.is_file() and path.stat().st_size > 0
    )
    if not candidates:
        fail(f"missing nonempty LICENSE* in {directory}")
    return candidates[0]


def checkout_map(root: pathlib.Path) -> dict[str, pathlib.Path]:
    checkouts = root / ".build" / "checkouts"
    if not checkouts.is_dir():
        return {}
    return {
        child.name.casefold(): child
        for child in checkouts.iterdir()
        if child.is_dir()
    }


def artifact_map(root: pathlib.Path) -> dict[str, pathlib.Path]:
    artifacts = root / ".build" / "artifacts"
    if not artifacts.is_dir():
        return {}

    result: dict[str, pathlib.Path] = {}
    for candidate in artifacts.glob("*/*"):
        if candidate.is_dir() and any(candidate.glob("LICENSE*")):
            result[candidate.name.casefold()] = candidate
    return result


def resolved_revision(checkout: pathlib.Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        fail(f"cannot read resolved revision from {checkout}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=pathlib.Path)
    parser.add_argument(
        "--license-source",
        type=pathlib.Path,
        help="workspace whose .build/checkouts and .build/artifacts provide resolved license evidence",
    )
    args = parser.parse_args()

    repo = args.repo.resolve()
    evidence_root = (args.license_source or repo).resolve()
    resolved_path = repo / "Package.resolved"
    notices_path = repo / "THIRD_PARTY_NOTICES.md"
    build_script_path = repo / "script" / "build_and_run.sh"
    for required in (resolved_path, notices_path, build_script_path):
        if not required.is_file():
            fail(f"missing required file: {required.relative_to(repo)}")

    resolved = json.loads(resolved_path.read_text(encoding="utf-8"))
    pins = {}
    for pin in resolved.get("pins", []):
        identity = str(pin.get("identity", "")).casefold()
        revision = str(pin.get("state", {}).get("revision", ""))
        if not identity or not revision:
            fail("Package.resolved contains a pin without identity or revision")
        pins[identity] = revision

    notices = notices_path.read_text(encoding="utf-8")
    table_rows = re.findall(
        r"^\| `([^`]+)` \| (Apache-2\.0|MIT) \|",
        notices,
        flags=re.MULTILINE,
    )
    table = {}
    for identity, expression in table_rows:
        key = identity.casefold()
        if key in table:
            fail(f"duplicate notice-table identity: {identity}")
        table[key] = expression

    vendor_root = repo / "Vendor"
    vendors = {
        child.name.casefold(): child
        for child in vendor_root.iterdir()
        if child.is_dir() and (child / "Package.swift").is_file()
    }
    expected = set(pins) | set(vendors)
    missing_rows = sorted(expected - set(table))
    extra_rows = sorted(set(table) - expected)
    if missing_rows:
        fail("notice table is missing: " + ", ".join(missing_rows))
    if extra_rows:
        fail("notice table has unresolved entries: " + ", ".join(extra_rows))

    checkouts = checkout_map(evidence_root)
    artifacts = artifact_map(evidence_root)
    if pins and not checkouts:
        fail(
            "resolved checkout licenses are unavailable; run Swift package "
            "resolution first or pass --license-source"
        )

    verified = []
    for identity, revision in sorted(pins.items()):
        checkout = checkouts.get(identity)
        if checkout is None:
            fail(f"missing resolved checkout for {identity} under {evidence_root}")
        actual_revision = resolved_revision(checkout)
        if actual_revision != revision:
            fail(
                f"checkout revision mismatch for {identity}: "
                f"Package.resolved={revision}, checkout={actual_revision}"
            )
        license_path = first_license(artifacts.get(identity, checkout))
        expression = detected_license(license_path)
        if expression == "UNKNOWN":
            fail(f"unrecognized license text: {license_path}")
        if table[identity] != expression:
            fail(
                f"license claim mismatch for {identity}: "
                f"table={table[identity]}, file={expression}"
            )
        verified.append((identity, expression, sha256(license_path)))

    for identity, directory in sorted(vendors.items()):
        license_path = first_license(directory)
        upstream = directory / "UPSTREAM.md"
        if not upstream.is_file() or upstream.stat().st_size == 0:
            fail(f"missing nonempty Vendor provenance: {upstream}")
        expression = detected_license(license_path)
        if expression == "UNKNOWN":
            fail(f"unrecognized vendored license text: {license_path}")
        if table[identity] != expression:
            fail(
                f"license claim mismatch for {identity}: "
                f"table={table[identity]}, file={expression}"
            )
        verified.append((identity, expression, sha256(license_path)))

    build_script = build_script_path.read_text(encoding="utf-8")
    if "NOTICE*" not in build_script:
        fail("release packaging does not collect upstream NOTICE* files")

    print(f"Verified {len(verified)} third-party package licenses from source files.")
    for identity, expression, digest in verified:
        print(f"  {identity}: {expression} {digest}")


if __name__ == "__main__":
    main()
