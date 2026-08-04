#!/usr/bin/env python3
"""Exercise deterministic CycloneDX SBOM generation and rejection paths."""

from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True

import generate_sbom
import verify_sbom


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(arguments: list[str], should_succeed: bool) -> None:
    result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode == 0 and not should_succeed:
        raise SystemExit("SBOM negative test unexpectedly succeeded: " + " ".join(arguments))
    if result.returncode != 0 and should_succeed:
        raise SystemExit(
            "SBOM positive test failed: "
            + " ".join(arguments)
            + "\n"
            + result.stdout
            + result.stderr
        )


def manifest_for_sbom(source: pathlib.Path, sbom: pathlib.Path, destination: pathlib.Path) -> None:
    manifest = json.loads(source.read_text(encoding="utf-8"))
    artifact = manifest["artifacts"]["softwareBillOfMaterials"]
    artifact["file"] = sbom.name
    artifact["sha256"] = sha256(sbom)
    artifact["bytes"] = sbom.stat().st_size
    destination.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def component_property(component: dict[str, object], name: str) -> str:
    properties = component["properties"]
    if not isinstance(properties, list):
        raise SystemExit("SBOM component properties are missing")
    for entry in properties:
        if isinstance(entry, dict) and entry.get("name") == name and isinstance(entry.get("value"), str):
            return entry["value"]
    raise SystemExit(f"SBOM component property is missing: {name}")


def rebind_serial(document: dict[str, object]) -> None:
    payload = dict(document)
    payload.pop("serialNumber", None)
    document["serialNumber"] = "urn:uuid:" + str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        )
    )


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit(f"Usage: {sys.argv[0]} PROJECT APP MANIFEST")
    project, app, manifest = (pathlib.Path(value).resolve() for value in sys.argv[1:])
    script_dir = pathlib.Path(__file__).resolve().parent
    generator = script_dir / "generate_sbom.py"
    verifier = script_dir / "verify_sbom.py"

    for invalid_url in (
        "https://user:token@github.com/example/repository.git",
        "https://github.com:443/example/repository.git",
        "https://github.com/example/repository.git?token=value",
        "https://github.com/example/repository.git#fragment",
    ):
        for parser in (generate_sbom.public_github_vcs, verify_sbom.public_github_vcs):
            try:
                parser(invalid_url)
            except (generate_sbom.SBOMError, verify_sbom.VerificationError):
                continue
            raise SystemExit(f"credential-bearing VCS URL was accepted: {invalid_url}")

    with tempfile.TemporaryDirectory(prefix="lerro-sbom-tests-") as directory:
        temporary = pathlib.Path(directory)
        first = temporary / "first.cdx.json"
        second = temporary / "second.cdx.json"
        common_generate = [
            sys.executable,
            str(generator),
            str(project),
            str(app),
        ]
        run(common_generate + [str(first), "--manifest", str(manifest)], True)
        run(common_generate + [str(second), "--manifest", str(manifest)], True)
        if first.read_bytes() != second.read_bytes():
            raise SystemExit("same SBOM inputs produced different bytes")

        valid_manifest = temporary / "valid-manifest.json"
        manifest_for_sbom(manifest, first, valid_manifest)
        common_verify = [
            sys.executable,
            str(verifier),
            str(project),
            str(first),
            str(app),
            str(valid_manifest),
        ]
        run(common_verify, True)

        first_document = json.loads(first.read_text(encoding="utf-8"))
        if first_document.get("version") != 1 or "timestamp" in first_document.get("metadata", {}):
            raise SystemExit("deterministic SBOM document metadata is incorrect")
        eventsource = next(
            component
            for component in first_document["components"]
            if component_property(component, "lerro:package:identity") == "eventsource"
        )
        resolved = json.loads((project / "Package.resolved").read_text(encoding="utf-8"))
        eventsource_pin = next(pin for pin in resolved["pins"] if pin["identity"] == "eventsource")
        _, namespace, repository = generate_sbom.public_github_vcs(eventsource_pin["location"])
        expected_version = eventsource_pin["state"].get("version") or eventsource_pin["state"]["revision"]
        expected_purl = generate_sbom.swift_purl(namespace, repository, expected_version)
        if eventsource.get("name") != repository or eventsource.get("purl") != expected_purl:
            raise SystemExit("Swift PURL or native repository name is incorrect")

        invalid_purl = temporary / "invalid-purl.cdx.json"
        invalid_document = json.loads(first.read_text(encoding="utf-8"))
        invalid_component = next(
            component
            for component in invalid_document["components"]
            if component_property(component, "lerro:package:identity") == "eventsource"
        )
        invalid_component["purl"] = f"pkg:swift/eventsource@{expected_version}"
        invalid_component["bom-ref"] = f"pkg:swift/eventsource@{expected_version}"
        rebind_serial(invalid_document)
        invalid_purl.write_text(json.dumps(invalid_document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        invalid_purl_manifest = temporary / "invalid-purl-manifest.json"
        manifest_for_sbom(manifest, invalid_purl, invalid_purl_manifest)
        run(
            [
                sys.executable,
                str(verifier),
                str(project),
                str(invalid_purl),
                str(app),
                str(invalid_purl_manifest),
            ],
            False,
        )

        invalid_serial = temporary / "invalid-serial.cdx.json"
        invalid_serial_document = json.loads(first.read_text(encoding="utf-8"))
        invalid_serial_document["serialNumber"] = "urn:uuid:00000000-0000-0000-0000-000000000000"
        invalid_serial.write_text(
            json.dumps(invalid_serial_document, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        invalid_serial_manifest = temporary / "invalid-serial-manifest.json"
        manifest_for_sbom(manifest, invalid_serial, invalid_serial_manifest)
        run(
            [
                sys.executable,
                str(verifier),
                str(project),
                str(invalid_serial),
                str(app),
                str(invalid_serial_manifest),
            ],
            False,
        )

        invalid_graph = temporary / "invalid-graph.cdx.json"
        invalid_graph_document = json.loads(first.read_text(encoding="utf-8"))
        invalid_graph_document["dependencies"][0]["dependsOn"] = []
        rebind_serial(invalid_graph_document)
        invalid_graph.write_text(json.dumps(invalid_graph_document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        invalid_graph_manifest = temporary / "invalid-graph-manifest.json"
        manifest_for_sbom(manifest, invalid_graph, invalid_graph_manifest)
        run(
            [
                sys.executable,
                str(verifier),
                str(project),
                str(invalid_graph),
                str(app),
                str(invalid_graph_manifest),
            ],
            False,
        )

        tampered_manifest = temporary / "tampered-lock-manifest.json"
        tampered = json.loads(manifest.read_text(encoding="utf-8"))
        tampered["packageResolved"]["pins"][0]["state"]["revision"] = "0" * 40
        tampered_manifest.write_text(json.dumps(tampered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        run(common_generate + [str(temporary / "tampered.cdx.json"), "--manifest", str(tampered_manifest)], False)

        lockfile_only_graph = temporary / "lockfile-only-graph.json"
        lockfile_only_graph.write_text('{"identity":"lerro","dependencies":[]}\n', encoding="utf-8")
        lockfile_only = temporary / "lockfile-only.cdx.json"
        run(
            common_generate
            + [
                str(lockfile_only),
                "--manifest",
                str(manifest),
                "--swiftpm-graph",
                str(lockfile_only_graph),
            ],
            True,
        )
        lockfile_only_document = json.loads(lockfile_only.read_text(encoding="utf-8"))
        if lockfile_only_document.get("serialNumber") == first_document.get("serialNumber"):
            raise SystemExit("changed SBOM payload reused the same serial")
        if any(
            component_property(component, "lerro:package:graph-reachable") != "false"
            or component_property(component, "lerro:package:graph-source") != "lockfile-only"
            for component in lockfile_only_document["components"]
        ):
            raise SystemExit("lockfile-only component marking is incorrect")
        if any(entry["dependsOn"] for entry in lockfile_only_document["dependencies"]):
            raise SystemExit("lockfile-only graph contains reachable dependencies")
        lockfile_only_manifest = temporary / "lockfile-only-manifest.json"
        manifest_for_sbom(manifest, lockfile_only, lockfile_only_manifest)
        run(
            [
                sys.executable,
                str(verifier),
                str(project),
                str(lockfile_only),
                str(app),
                str(lockfile_only_manifest),
                "--swiftpm-graph",
                str(lockfile_only_graph),
            ],
            True,
        )

    print("Verified deterministic SBOM generation and negative validation cases.")


if __name__ == "__main__":
    main()
