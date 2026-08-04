#!/usr/bin/env python3
"""Generate the release CycloneDX SBOM from Lerro's resolved SwiftPM graph.

The generated document deliberately contains only release-safe identifiers:
package identities, immutable revisions, public upstream URLs, relative license
evidence paths, and hashes.  Build checkout paths and package-manager output
paths stay outside the artifact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import uuid
from urllib.parse import quote, urlsplit


CYCLONEDX_SCHEMA = "https://cyclonedx.org/schema/bom-1.7.schema.json"
EXPECTED_COMPONENT_COUNT = 17
SYSTEM_FRAMEWORKS = (
    "ApplicationServices,AVFoundation,Carbon,ServiceManagement,Speech,Translation"
)
LICENSE_PATTERN = re.compile(
    r"^\| `([^`]+)` \| (Apache-2\.0|MIT) \|", re.MULTILINE
)
ABSOLUTE_PATH_PATTERN = re.compile(
    r"(?<![A-Za-z0-9+.-])/(?:Users|private|var|tmp|Volumes|Applications|Library|System|opt|usr|bin|sbin|etc)(?:/|$)"
)
SECRET_PATTERN = re.compile(
    r"(?i)(?:api[_-]?key|authorization|bearer|credential|password|secret|token)\s*[\"']?\s*[:=]"
)
GITHUB_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class SBOMError(RuntimeError):
    """A release input cannot safely form the expected SBOM."""


def fail(message: str) -> None:
    raise SBOMError(message)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_output(*arguments: str) -> str:
    try:
        return subprocess.check_output(arguments, text=True, stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"cannot run {' '.join(arguments)}: {error}")


def release_source(snapshot: object) -> dict[str, str | bool]:
    if not isinstance(snapshot, dict):
        fail("release source snapshot has an invalid shape")
    required_hashes = ("commit", "tree", "workingTreeContentSHA256")
    result: dict[str, str | bool] = {}
    for key in required_hashes:
        value = snapshot.get(key)
        length = 40 if key in {"commit", "tree"} else 64
        if not isinstance(value, str) or not re.fullmatch(rf"[0-9a-f]{{{length}}}", value):
            fail(f"release source snapshot has an invalid {key}")
        result[key] = value
    dirty = snapshot.get("dirty")
    if not isinstance(dirty, bool):
        fail("release source snapshot has an invalid dirty field")
    result["dirty"] = dirty
    return result


def first_license(directory: pathlib.Path) -> pathlib.Path:
    candidates = sorted(
        path
        for path in directory.glob("LICENSE*")
        if path.is_file() and path.stat().st_size > 0
    )
    if not candidates:
        fail(f"missing nonempty LICENSE* in release evidence for {directory.name}")
    return candidates[0]


def detected_license(path: pathlib.Path) -> str:
    text = path.read_text(encoding="utf-8", errors="replace")
    if "Apache License" in text and "Version 2.0" in text:
        return "Apache-2.0"
    if "MIT License" in text or (
        "Permission is hereby granted, free of charge" in text
        and "THE SOFTWARE IS PROVIDED \"AS IS\"" in text
    ):
        return "MIT"
    fail(f"unrecognized license text: {path.name}")


def license_claims(notices_path: pathlib.Path) -> dict[str, str]:
    claims: dict[str, str] = {}
    for identity, expression in LICENSE_PATTERN.findall(
        notices_path.read_text(encoding="utf-8")
    ):
        key = identity.casefold()
        if key in claims:
            fail(f"duplicate third-party notice identity: {identity}")
        claims[key] = expression
    return claims


def public_github_vcs(url: str) -> tuple[str, str, str]:
    """Return the exact VCS URL plus the Swift PURL namespace and repository name."""
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError as error:
        fail(f"invalid VCS URL: {error}")
    if (
        parsed.scheme != "https"
        or parsed.netloc != "github.com"
        or parsed.hostname != "github.com"
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
        or parsed.query
        or parsed.fragment
    ):
        fail(f"VCS URL must be a public GitHub HTTPS repository: {url}")
    parts = parsed.path.split("/")
    if len(parts) != 3 or parts[0] or not parts[1] or not parts[2]:
        fail(f"VCS URL must identify exactly one GitHub repository: {url}")
    owner = parts[1]
    repository = parts[2][:-4] if parts[2].endswith(".git") else parts[2]
    if not repository or not GITHUB_NAME_PATTERN.fullmatch(owner) or not GITHUB_NAME_PATTERN.fullmatch(repository):
        fail(f"VCS URL has an unsupported GitHub owner or repository name: {url}")
    return url, f"github.com/{owner}", repository


def swift_purl(namespace: str, repository: str, version: str) -> str:
    return (
        f"pkg:swift/{quote(namespace, safe='/-._')}"
        f"/{quote(repository, safe='.-_')}@{quote(version, safe='.-_')}"
    )


def current_resolved(project: pathlib.Path) -> tuple[dict[str, object], str]:
    path = project / "Package.resolved"
    if not path.is_file():
        fail("missing SBOM input: Package.resolved")
    try:
        resolved = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"Package.resolved is not JSON: {error}")
    if not isinstance(resolved, dict):
        fail("Package.resolved has an invalid shape")
    return resolved, sha256(path)


def verify_manifest_resolved_binding(
    project: pathlib.Path, manifest: dict[str, object], manifest_resolved: object
) -> tuple[dict[str, object], str]:
    current, current_hash = current_resolved(project)
    toolchains = manifest.get("toolchains")
    if not isinstance(toolchains, dict):
        fail("canonical manifest has no toolchain metadata")
    if toolchains.get("packageResolvedSHA256") != current_hash:
        fail("canonical manifest Package.resolved hash differs from the current raw lockfile")
    if not isinstance(manifest_resolved, dict) or manifest_resolved != current:
        fail("canonical manifest Package.resolved snapshot differs from the current parsed lockfile")
    return current, current_hash


def package_maps(project: pathlib.Path) -> tuple[dict[str, pathlib.Path], dict[str, pathlib.Path]]:
    checkouts_root = project / ".build" / "checkouts"
    artifacts_root = project / ".build" / "artifacts"
    checkouts = {
        child.name.casefold(): child
        for child in checkouts_root.iterdir()
        if child.is_dir()
    } if checkouts_root.is_dir() else {}
    artifacts: dict[str, pathlib.Path] = {}
    if artifacts_root.is_dir():
        for child in artifacts_root.glob("*/*"):
            if child.is_dir() and any(child.glob("LICENSE*")):
                artifacts[child.name.casefold()] = child
    return checkouts, artifacts


def vendor_metadata(vendor: pathlib.Path) -> tuple[str, str, str]:
    """Return public upstream URL, release version, and immutable revision."""
    upstream_path = vendor / "UPSTREAM.md"
    if not upstream_path.is_file() or upstream_path.stat().st_size == 0:
        fail(f"missing Vendor provenance: {vendor.name}/UPSTREAM.md")
    text = upstream_path.read_text(encoding="utf-8")
    url_match = re.search(r"https://github\.com/[^\s)>`]+", text)
    release_match = re.search(
        r"(?:Upstream release baseline|Release):\s*`?([0-9][0-9A-Za-z.+-]*)`?", text
    )
    revision_match = re.search(
        r"(?:Upstream baseline commit|Commit):\s*`?([0-9a-f]{40})`?", text
    )
    if url_match is None or release_match is None or revision_match is None:
        fail(f"incomplete Vendor provenance for {vendor.name}")
    return url_match.group(0), release_match.group(1), revision_match.group(1)


def resolved_graph(
    project: pathlib.Path, expected: set[str], graph_path: pathlib.Path | None = None
) -> tuple[dict[str, set[str]], set[str], set[str]]:
    try:
        if graph_path is None:
            result = subprocess.run(
                ["swift", "package", "show-dependencies", "--format", "json"],
                cwd=project,
                check=True,
                capture_output=True,
                text=True,
            )
            graph_json = result.stdout
        else:
            graph_json = graph_path.read_text(encoding="utf-8")
        root = json.loads(graph_json)
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"cannot obtain the resolved SwiftPM dependency graph: {error}")
    except json.JSONDecodeError as error:
        fail(f"SwiftPM dependency graph is not JSON: {error}")

    graph: dict[str, set[str]] = {identity: set() for identity in expected}
    direct_dependencies: set[str] = set()
    observed: set[str] = set()

    def visit(node: object, parent: str | None, is_root: bool = False) -> None:
        if not isinstance(node, dict):
            fail("SwiftPM dependency graph contains an invalid node")
        identity = str(node.get("identity", "")).casefold()
        if is_root:
            if identity != "lerro":
                fail("SwiftPM dependency graph has an unexpected root")
        else:
            if identity not in expected:
                fail(f"SwiftPM graph has an unresolved component: {identity or 'empty identity'}")
            observed.add(identity)
        if parent is not None:
            graph[parent].add(identity)
        children = node.get("dependencies", [])
        if not isinstance(children, list):
            fail(f"SwiftPM graph has invalid dependencies for {identity or 'root'}")
        for child in children:
            child_identity = str(child.get("identity", "")).casefold() if isinstance(child, dict) else ""
            if is_root:
                if child_identity not in expected:
                    fail(f"SwiftPM graph has an unexpected direct dependency: {child_identity}")
                direct_dependencies.add(child_identity)
                visit(child, None)
            else:
                visit(child, identity)
            if not is_root and child_identity not in expected:
                fail(f"SwiftPM graph has an unexpected direct dependency: {child_identity}")

    visit(root, None, is_root=True)
    return graph, direct_dependencies, observed


def relative_packaged_license(resources: pathlib.Path, identity: str) -> pathlib.Path:
    records = sorted(
        path
        for path in (resources / "ThirdPartyLicenses").glob(f"{identity}-LICENSE*")
        if path.is_file() and path.stat().st_size > 0
    )
    if not records:
        fail(f"missing packaged license evidence for {identity}")
    return records[0].relative_to(resources)


def safe_document(document: dict[str, object]) -> None:
    encoded = json.dumps(document, ensure_ascii=False, sort_keys=True)
    if ABSOLUTE_PATH_PATTERN.search(encoded):
        fail("generated SBOM contains an absolute filesystem path")
    if SECRET_PATTERN.search(encoded):
        fail("generated SBOM contains a credential-like value")


def package_component(
    *,
    identity: str,
    name: str,
    version: str,
    revision: str,
    upstream: str,
    license_expression: str,
    license_path: pathlib.Path,
    source_license_hash: str,
    resources: pathlib.Path,
    source_kind: str,
    graph_reachable: bool,
) -> dict[str, object]:
    vcs_url, namespace, repository = public_github_vcs(upstream)
    if name != repository:
        fail(f"component name does not match its GitHub repository: {identity}")
    purl = swift_purl(namespace, repository, version)
    component: dict[str, object] = {
        "type": "library",
        "bom-ref": purl,
        "name": name,
        "version": version,
        "purl": purl,
        "licenses": [{"license": {"id": license_expression}}],
        "externalReferences": [{"type": "vcs", "url": vcs_url}],
        "properties": [
            {"name": "lerro:package:identity", "value": identity},
            {"name": "lerro:package:source", "value": source_kind},
            {"name": "lerro:package:revision", "value": revision},
            {
                "name": "lerro:package:license-evidence",
                "value": license_path.as_posix(),
            },
            {
                "name": "lerro:package:license-sha256",
                "value": sha256(resources / license_path),
            },
            {
                "name": "lerro:package:source-license-sha256",
                "value": source_license_hash,
            },
            {
                "name": "lerro:package:graph-reachable",
                "value": str(graph_reachable).lower(),
            },
            {
                "name": "lerro:package:graph-source",
                "value": "swiftpm-show-dependencies" if graph_reachable else "lockfile-only",
            },
        ],
    }
    return component


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=pathlib.Path)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        help="canonical release manifest for SBOM backfill from an independently extracted app",
    )
    parser.add_argument(
        "--source-snapshot",
        type=pathlib.Path,
        help="source snapshot emitted by package_release.sh for a newly built release",
    )
    parser.add_argument(
        "--swiftpm-graph",
        type=pathlib.Path,
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    project = args.project.resolve()
    app = args.app.resolve()
    output = args.output.resolve()
    notices_path = project / "THIRD_PARTY_NOTICES.md"
    info_path = app / "Contents" / "Info.plist"
    binary = app / "Contents" / "MacOS" / "Lerro"
    resources = app / "Contents" / "Resources"
    for required in (notices_path, info_path, binary, resources / "ThirdPartyLicenses"):
        if not required.exists():
            fail(f"missing SBOM input: {required.name}")
    manifest: dict[str, object] | None = None
    if args.manifest is None:
        resolved, lock_hash = current_resolved(project)
        if args.source_snapshot is None:
            fail("--source-snapshot is required without --manifest")
        source = release_source(
            json.loads(args.source_snapshot.resolve().read_text(encoding="utf-8"))
        )
    else:
        manifest_path = args.manifest.resolve()
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict):
            fail("canonical manifest has an invalid shape")
        resolved = manifest.get("packageResolved")
        resolved, lock_hash = verify_manifest_resolved_binding(project, manifest, resolved)
        source = release_source(manifest.get("source"))
        if args.source_snapshot is not None:
            supplied_source = release_source(
                json.loads(args.source_snapshot.resolve().read_text(encoding="utf-8"))
            )
            if supplied_source != source:
                fail("--source-snapshot differs from the canonical manifest")
    pins = {
        str(pin["identity"]).casefold(): pin
        for pin in resolved.get("pins", [])
        if isinstance(pin, dict) and pin.get("identity") and pin.get("state", {}).get("revision")
    }
    if len(pins) != len(resolved.get("pins", [])):
        fail("Package.resolved has a pin without identity or revision")
    vendors = {
        path.name.casefold(): path
        for path in (project / "Vendor").iterdir()
        if path.is_dir() and (path / "Package.swift").is_file()
    }
    expected = set(pins) | set(vendors)
    if len(expected) != EXPECTED_COMPONENT_COUNT:
        fail(f"expected {EXPECTED_COMPONENT_COUNT} package components, found {len(expected)}")

    claims = license_claims(notices_path)
    if set(claims) != expected:
        fail("third-party notice inventory differs from the resolved package inventory")
    checkouts, artifacts = package_maps(project)
    graph, direct_dependencies, reachable = resolved_graph(
        project, expected, args.swiftpm_graph.resolve() if args.swiftpm_graph else None
    )

    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    app_name = str(info.get("CFBundleName", ""))
    bundle_identifier = str(info.get("CFBundleIdentifier", ""))
    version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if not all((app_name, bundle_identifier, version, build)):
        fail("application Info.plist is missing release identity fields")
    binary_hash = sha256(binary)
    architecture = command_output("lipo", "-archs", str(binary))
    if architecture != "arm64":
        fail(f"SBOM release app must be arm64-only, found {architecture}")
    minimum_os = str(info.get("LSMinimumSystemVersion", ""))
    if not minimum_os.startswith("26"):
        fail(f"SBOM release app must require macOS 26, found {minimum_os or 'missing value'}")
    application_purl = f"pkg:generic/{quote(bundle_identifier, safe='.-_')}@{quote(version, safe='.-_')}?build={quote(build, safe='.-_')}"
    if manifest is not None:
        manifest_application = manifest.get("application")
        if not isinstance(manifest_application, dict):
            fail("canonical manifest has no application metadata")
        if manifest_application.get("bundleIdentifier") != bundle_identifier:
            fail("canonical manifest bundle identifier differs from the extracted app")
        if str(manifest_application.get("version")) != version or str(manifest_application.get("build")) != build:
            fail("canonical manifest version or build differs from the extracted app")
        if manifest_application.get("binarySHA256") != binary_hash:
            fail("canonical manifest binary hash differs from the extracted app")

    components: list[dict[str, object]] = []
    references: dict[str, str] = {}
    for identity in sorted(expected):
        license_path = relative_packaged_license(resources, identity)
        actual_license = detected_license(resources / license_path)
        if actual_license != claims[identity]:
            fail(f"packaged license claim mismatch for {identity}: {actual_license}")
        if identity in pins:
            pin = pins[identity]
            state = pin["state"]
            revision = str(state["revision"])
            component_version = str(state.get("version") or revision)
            upstream = str(pin["location"])
            _, _, component_name = public_github_vcs(upstream)
            evidence = artifacts.get(identity, checkouts.get(identity))
            if evidence is None:
                fail(f"missing source license evidence for {identity}")
            source_license = first_license(evidence)
            if detected_license(source_license) != actual_license:
                fail(f"source and packaged license claims differ for {identity}")
            source_kind = "swiftpm-resolved"
        else:
            upstream, component_version, revision = vendor_metadata(vendors[identity])
            _, _, component_name = public_github_vcs(upstream)
            source_license = first_license(vendors[identity])
            if detected_license(source_license) != actual_license:
                fail(f"source and packaged license claims differ for {identity}")
            source_kind = "vendored"
        source_license_hash = sha256(source_license)
        if source_license_hash != sha256(resources / license_path):
            fail(f"source and packaged license hashes differ for {identity}")
        component = package_component(
            identity=identity,
            name=component_name,
            version=component_version,
            revision=revision,
            upstream=upstream,
            license_expression=actual_license,
            license_path=license_path,
            source_license_hash=source_license_hash,
            resources=resources,
            source_kind=source_kind,
            graph_reachable=identity in reachable,
        )
        references[identity] = str(component["bom-ref"])
        components.append(component)

    dependencies = [
        {
            "ref": application_purl,
            "dependsOn": sorted(
                references[identity]
                for identity in direct_dependencies
            ),
        }
    ]
    dependencies.extend(
        {
            "ref": references[identity],
            "dependsOn": sorted(references[child] for child in graph[identity]),
        }
        for identity in sorted(expected)
    )
    document: dict[str, object] = {
        "$schema": CYCLONEDX_SCHEMA,
        "bomFormat": "CycloneDX",
        "specVersion": "1.7",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": application_purl,
                "name": app_name,
                "version": version,
                "purl": application_purl,
                "hashes": [{"alg": "SHA-256", "content": binary_hash}],
                "properties": [
                    {"name": "lerro:application:bundle-id", "value": bundle_identifier},
                    {"name": "lerro:application:build", "value": build},
                    {"name": "lerro:application:binary-sha256", "value": binary_hash},
                    {"name": "lerro:application:minimum-os", "value": minimum_os},
                    {"name": "lerro:application:architecture", "value": architecture},
                    {"name": "lerro:package-resolved-sha256", "value": lock_hash},
                    {"name": "lerro:source:commit", "value": str(source["commit"])},
                    {"name": "lerro:source:tree", "value": str(source["tree"])},
                    {
                        "name": "lerro:source:working-tree-sha256",
                        "value": str(source["workingTreeContentSHA256"]),
                    },
                    {"name": "lerro:source:dirty", "value": str(source["dirty"]).lower()},
                    {"name": "lerro:system-frameworks", "value": SYSTEM_FRAMEWORKS},
                ],
            },
        },
        "components": components,
        "dependencies": dependencies,
    }
    serial_payload = json.dumps(
        document, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    document["serialNumber"] = "urn:uuid:" + str(
        uuid.uuid5(uuid.NAMESPACE_URL, serial_payload)
    )
    safe_document(document)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated CycloneDX 1.7 SBOM with {len(components)} package components: {output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError, SBOMError) as error:
        print(f"SBOM generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
