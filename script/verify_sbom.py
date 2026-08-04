#!/usr/bin/env python3
"""Verify the release-safe CycloneDX SBOM against Lerro release inputs."""

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


EXPECTED_COMPONENT_COUNT = 17
SYSTEM_FRAMEWORKS = (
    "ApplicationServices,AVFoundation,Carbon,ServiceManagement,Speech,Translation"
)
LICENSE_PATTERN = re.compile(
    r"^\| `([^`]+)` \| (Apache-2\.0|MIT) \|", re.MULTILINE
)
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
ABSOLUTE_PATH_PATTERN = re.compile(
    r"(?<![A-Za-z0-9+.-])/(?:Users|private|var|tmp|Volumes|Applications|Library|System|opt|usr|bin|sbin|etc)(?:/|$)"
)
SECRET_PATTERN = re.compile(
    r"(?i)(?:api[_-]?key|authorization|bearer|credential|password|secret|token)\s*[\"']?\s*[:=]"
)
GITHUB_NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class VerificationError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise VerificationError(message)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def first_license(directory: pathlib.Path) -> pathlib.Path:
    candidates = sorted(
        path
        for path in directory.glob("LICENSE*")
        if path.is_file() and path.stat().st_size > 0
    )
    if not candidates:
        fail(f"missing nonempty LICENSE* in release evidence for {directory.name}")
    return candidates[0]


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


def properties(item: object) -> dict[str, str]:
    if not isinstance(item, list):
        fail("SBOM properties are missing")
    result: dict[str, str] = {}
    for entry in item:
        if not isinstance(entry, dict):
            fail("SBOM property has an invalid shape")
        name = entry.get("name")
        value = entry.get("value")
        if not isinstance(name, str) or not isinstance(value, str) or name in result:
            fail("SBOM property is invalid or duplicated")
        result[name] = value
    return result


def notice_claims(path: pathlib.Path) -> dict[str, str]:
    return {
        identity.casefold(): expression
        for identity, expression in LICENSE_PATTERN.findall(path.read_text(encoding="utf-8"))
    }


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


def public_github_vcs(url: str) -> tuple[str, str, str]:
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


def vendor_metadata(path: pathlib.Path) -> tuple[str, str, str]:
    upstream = path / "UPSTREAM.md"
    text = upstream.read_text(encoding="utf-8")
    url_match = re.search(r"https://github\.com/[^\s)>`]+", text)
    release_match = re.search(
        r"(?:Upstream release baseline|Release):\s*`?([0-9][0-9A-Za-z.+-]*)`?", text
    )
    revision_match = re.search(
        r"(?:Upstream baseline commit|Commit):\s*`?([0-9a-f]{40})`?",
        text,
    )
    if url_match is None or release_match is None or revision_match is None:
        fail(f"Vendor provenance is incomplete: {path.name}")
    return url_match.group(0), release_match.group(1), revision_match.group(1)


def current_resolved(project: pathlib.Path) -> tuple[dict[str, object], str]:
    path = project / "Package.resolved"
    try:
        resolved = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        fail(f"Package.resolved is not JSON: {error}")
    if not isinstance(resolved, dict):
        fail("Package.resolved has an invalid shape")
    return resolved, sha256(path)


def verify_manifest_resolved_binding(
    project: pathlib.Path, manifest: dict[str, object]
) -> tuple[dict[str, object], str]:
    current, current_hash = current_resolved(project)
    toolchains = manifest.get("toolchains")
    if not isinstance(toolchains, dict):
        fail("canonical release manifest is missing toolchain metadata")
    if toolchains.get("packageResolvedSHA256") != current_hash:
        fail("canonical manifest Package.resolved hash differs from the current raw lockfile")
    if manifest.get("packageResolved") != current:
        fail("canonical manifest Package.resolved snapshot differs from the current parsed lockfile")
    return current, current_hash


def expected_inputs(
    project: pathlib.Path, resolved: dict[str, object]
) -> tuple[dict[str, dict[str, object]], dict[str, pathlib.Path], dict[str, str]]:
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
    claims = notice_claims(project / "THIRD_PARTY_NOTICES.md")
    expected = set(pins) | set(vendors)
    if len(expected) != EXPECTED_COMPONENT_COUNT:
        fail(f"expected {EXPECTED_COMPONENT_COUNT} package components, found {len(expected)}")
    if set(claims) != expected:
        fail("third-party notice inventory differs from the resolved package inventory")
    return pins, vendors, claims


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

    visit(root, None, is_root=True)
    return graph, direct_dependencies, observed


def component_license(component: dict[str, object]) -> str:
    licenses = component.get("licenses")
    if not isinstance(licenses, list) or len(licenses) != 1:
        fail("component must have exactly one verified license")
    license_entry = licenses[0]
    if not isinstance(license_entry, dict) or not isinstance(license_entry.get("license"), dict):
        fail("component license has an invalid shape")
    identifier = license_entry["license"].get("id")
    if not isinstance(identifier, str):
        fail("component license has no SPDX identifier")
    return identifier


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=pathlib.Path)
    parser.add_argument("sbom", type=pathlib.Path)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument(
        "--swiftpm-graph",
        type=pathlib.Path,
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    project = args.project.resolve()
    sbom_path = args.sbom.resolve()
    app = args.app.resolve()
    manifest_path = args.manifest.resolve()
    document = json.loads(sbom_path.read_text(encoding="utf-8"))
    encoded = json.dumps(document, ensure_ascii=False, sort_keys=True)
    if ABSOLUTE_PATH_PATTERN.search(encoded):
        fail("SBOM contains an absolute filesystem path")
    if SECRET_PATTERN.search(encoded):
        fail("SBOM contains a credential-like value")
    if document.get("bomFormat") != "CycloneDX" or document.get("specVersion") != "1.7":
        fail("SBOM is not CycloneDX 1.7")
    if document.get("$schema") != "https://cyclonedx.org/schema/bom-1.7.schema.json":
        fail("SBOM uses an unexpected CycloneDX schema")
    if document.get("version") != 1:
        fail("SBOM document version is not 1")
    metadata_for_serial = document.get("metadata")
    if isinstance(metadata_for_serial, dict) and "timestamp" in metadata_for_serial:
        fail("deterministic SBOM must not contain a timestamp")
    serial_payload = dict(document)
    serial_number = serial_payload.pop("serialNumber", None)
    expected_serial = "urn:uuid:" + str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            json.dumps(serial_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
        )
    )
    if serial_number != expected_serial:
        fail("SBOM serial does not bind the canonical document payload")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        fail("canonical release manifest has an invalid shape")
    manifest_application = manifest.get("application")
    manifest_toolchains = manifest.get("toolchains")
    if not isinstance(manifest_application, dict) or not isinstance(manifest_toolchains, dict):
        fail("canonical release manifest is missing application or toolchain metadata")
    resolved, lock_hash = verify_manifest_resolved_binding(project, manifest)
    pins, vendors, claims = expected_inputs(project, resolved)
    expected = set(pins) | set(vendors)
    expected_graph, expected_direct_dependencies, reachable = resolved_graph(
        project, expected, args.swiftpm_graph.resolve() if args.swiftpm_graph else None
    )
    checkouts, artifacts = package_maps(project)
    components = document.get("components")
    if not isinstance(components, list) or len(components) != EXPECTED_COMPONENT_COUNT:
        fail("SBOM does not contain exactly 17 package components")
    by_identity: dict[str, dict[str, object]] = {}
    component_properties_by_identity: dict[str, dict[str, str]] = {}
    references: dict[str, str] = {}
    for component in components:
        if not isinstance(component, dict):
            fail("SBOM component has an invalid shape")
        component_properties = properties(component.get("properties"))
        identity = component_properties.get("lerro:package:identity", "").casefold()
        if not identity or identity in by_identity:
            fail("SBOM component identity is missing or duplicated")
        by_identity[identity] = component
        component_properties_by_identity[identity] = component_properties
        reference = component.get("bom-ref")
        if not isinstance(reference, str) or component.get("purl") != reference:
            fail(f"SBOM component reference is invalid: {identity}")
        references[identity] = reference
    if set(by_identity) != expected:
        fail("SBOM component inventory differs from Package.resolved and Vendor")

    resources = app / "Contents" / "Resources"
    for identity in sorted(expected):
        component = by_identity[identity]
        component_properties = component_properties_by_identity[identity]
        if component.get("type") != "library":
            fail(f"SBOM component type differs for {identity}")
        if component_license(component) != claims[identity]:
            fail(f"SBOM license claim differs from notices for {identity}")
        graph_reachable = identity in reachable
        if component_properties.get("lerro:package:graph-reachable") != str(graph_reachable).lower():
            fail(f"SBOM graph reachability differs for {identity}")
        expected_graph_source = "swiftpm-show-dependencies" if graph_reachable else "lockfile-only"
        if component_properties.get("lerro:package:graph-source") != expected_graph_source:
            fail(f"SBOM graph source differs for {identity}")
        evidence = component_properties.get("lerro:package:license-evidence")
        evidence_hash = component_properties.get("lerro:package:license-sha256")
        evidence_parts = pathlib.PurePosixPath(evidence).parts if isinstance(evidence, str) else ()
        if (
            not isinstance(evidence, str)
            or pathlib.PurePosixPath(evidence).is_absolute()
            or ".." in evidence_parts
            or len(evidence_parts) < 2
            or evidence_parts[0] != "ThirdPartyLicenses"
        ):
            fail(f"SBOM license evidence path is unsafe for {identity}")
        evidence_path = (resources / evidence).resolve()
        licenses_root = (resources / "ThirdPartyLicenses").resolve()
        if licenses_root not in evidence_path.parents:
            fail(f"SBOM license evidence escapes ThirdPartyLicenses for {identity}")
        if not evidence_path.is_file() or not SHA256_PATTERN.fullmatch(str(evidence_hash)):
            fail(f"SBOM license evidence is missing for {identity}")
        if sha256(evidence_path) != evidence_hash:
            fail(f"SBOM license evidence hash differs for {identity}")
        if detected_license(evidence_path) != claims[identity]:
            fail(f"SBOM license evidence text differs for {identity}")
        if identity in pins:
            pin = pins[identity]
            revision = str(pin["state"]["revision"])
            upstream = str(pin["location"])
            if component_properties.get("lerro:package:source") != "swiftpm-resolved":
                fail(f"SBOM source kind differs for {identity}")
            if component_properties.get("lerro:package:revision") != revision:
                fail(f"SBOM revision differs from Package.resolved for {identity}")
            expected_version = str(pin["state"].get("version") or revision)
            source_directory = artifacts.get(identity, checkouts.get(identity))
            if source_directory is None:
                fail(f"source license evidence is unavailable for {identity}")
        else:
            upstream, expected_version, expected_revision = vendor_metadata(vendors[identity])
            if component_properties.get("lerro:package:source") != "vendored":
                fail(f"SBOM source kind differs for Vendor package {identity}")
            if component_properties.get("lerro:package:revision") != expected_revision:
                fail(f"SBOM revision differs from Vendor provenance for {identity}")
            source_directory = vendors[identity]
        expected_vcs, namespace, repository = public_github_vcs(upstream)
        expected_purl = swift_purl(namespace, repository, expected_version)
        if component.get("name") != repository:
            fail(f"SBOM component name differs from its VCS repository for {identity}")
        if component.get("version") != expected_version:
            fail(f"SBOM version differs from resolved provenance for {identity}")
        if component.get("purl") != expected_purl or component.get("bom-ref") != expected_purl:
            fail(f"SBOM Swift PURL differs from resolved provenance for {identity}")
        if component.get("externalReferences") != [{"type": "vcs", "url": expected_vcs}]:
            fail(f"SBOM VCS reference differs from resolved provenance for {identity}")
        source_license_hash = sha256(first_license(source_directory))
        if component_properties.get("lerro:package:source-license-sha256") != source_license_hash:
            fail(f"SBOM source license hash differs for {identity}")
        if source_license_hash != evidence_hash:
            fail(f"source and packaged license evidence differ for {identity}")

    metadata = document.get("metadata")
    if not isinstance(metadata, dict) or not isinstance(metadata.get("component"), dict):
        fail("SBOM application metadata is missing")
    application = metadata["component"]
    application_properties = properties(application.get("properties"))
    info_path = app / "Contents" / "Info.plist"
    binary = app / "Contents" / "MacOS" / "Lerro"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    binary_hash = sha256(binary)
    if application.get("type") != "application" or application.get("name") != info.get("CFBundleName"):
        fail("SBOM application identity differs from Info.plist")
    if application.get("version") != info.get("CFBundleShortVersionString"):
        fail("SBOM application version differs from Info.plist")
    if application_properties.get("lerro:application:bundle-id") != info.get("CFBundleIdentifier"):
        fail("SBOM bundle identifier differs from Info.plist")
    if application_properties.get("lerro:application:build") != str(info.get("CFBundleVersion")):
        fail("SBOM build differs from Info.plist")
    if application_properties.get("lerro:application:binary-sha256") != binary_hash:
        fail("SBOM binary hash differs from the app")
    if application_properties.get("lerro:package-resolved-sha256") != lock_hash:
        fail("SBOM lockfile hash differs from Package.resolved")
    if application_properties.get("lerro:application:minimum-os") != info.get("LSMinimumSystemVersion"):
        fail("SBOM minimum OS differs from Info.plist")
    if not str(info.get("LSMinimumSystemVersion", "")).startswith("26"):
        fail("release app does not declare macOS 26")
    if application_properties.get("lerro:application:architecture") != "arm64":
        fail("SBOM architecture is not arm64")
    try:
        actual_architecture = subprocess.check_output(
            ["lipo", "-archs", str(binary)], text=True, stderr=subprocess.STDOUT
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"cannot inspect app architecture: {error}")
    if actual_architecture != "arm64":
        fail(f"extracted app is not arm64-only: {actual_architecture}")
    source = manifest.get("source")
    if not isinstance(source, dict):
        fail("canonical manifest is missing its source snapshot")
    for source_key, property_name in (
        ("commit", "lerro:source:commit"),
        ("tree", "lerro:source:tree"),
        ("workingTreeContentSHA256", "lerro:source:working-tree-sha256"),
    ):
        if application_properties.get(property_name) != source.get(source_key):
            fail(f"SBOM {source_key} differs from the canonical manifest")
    if application_properties.get("lerro:source:dirty") != str(source.get("dirty")).lower():
        fail("SBOM dirty-tree state differs from the canonical manifest")
    if application_properties.get("lerro:system-frameworks") != SYSTEM_FRAMEWORKS:
        fail("SBOM system-framework declaration differs")
    if manifest_application.get("bundleIdentifier") != info.get("CFBundleIdentifier"):
        fail("canonical manifest bundle identifier differs from the app")
    if manifest_application.get("version") != info.get("CFBundleShortVersionString"):
        fail("canonical manifest version differs from the app")
    if str(manifest_application.get("build")) != str(info.get("CFBundleVersion")):
        fail("canonical manifest build differs from the app")
    if manifest_application.get("binarySHA256") != binary_hash:
        fail("canonical manifest binary hash differs from the app")
    if manifest_toolchains.get("packageResolvedSHA256") != lock_hash:
        fail("canonical manifest lockfile hash differs from Package.resolved")
    hashes = application.get("hashes")
    if hashes != [{"alg": "SHA-256", "content": binary_hash}]:
        fail("SBOM application hashes differ from the app binary")

    dependencies = document.get("dependencies")
    if not isinstance(dependencies, list) or len(dependencies) != EXPECTED_COMPONENT_COUNT + 1:
        fail("SBOM dependency graph has an unexpected entry count")
    dependency_map: dict[str, set[str]] = {}
    for entry in dependencies:
        if not isinstance(entry, dict) or not isinstance(entry.get("ref"), str):
            fail("SBOM dependency entry has an invalid shape")
        reference = entry["ref"]
        depends_on = entry.get("dependsOn")
        if not isinstance(depends_on, list) or any(not isinstance(value, str) for value in depends_on):
            fail("SBOM dependency entry has invalid dependencies")
        if reference in dependency_map:
            fail("SBOM dependency graph has a duplicate reference")
        dependency_map[reference] = set(depends_on)
    expected_references = set(references.values())
    application_ref = application.get("bom-ref")
    if not isinstance(application_ref, str) or set(dependency_map) != expected_references | {application_ref}:
        fail("SBOM dependency graph references differ from the component inventory")
    expected_dependency_map = {
        application_ref: {references[identity] for identity in expected_direct_dependencies},
        **{
            references[identity]: {references[child] for child in expected_graph[identity]}
            for identity in expected
        },
    }
    if dependency_map != expected_dependency_map:
        fail("SBOM dependency graph differs from the resolved SwiftPM graph")

    sbom_artifact = manifest.get("artifacts", {}).get("softwareBillOfMaterials")
    if not isinstance(sbom_artifact, dict):
        fail("release manifest has no valid SBOM artifact")
    if sbom_artifact.get("file") != sbom_path.name or sbom_artifact.get("sha256") != sha256(sbom_path):
        fail("release manifest SBOM artifact differs from the SBOM")
    if sbom_artifact.get("format") != "CycloneDX" or sbom_artifact.get("specVersion") != "1.7":
        fail("release manifest SBOM format differs")
    if sbom_artifact.get("bytes") != sbom_path.stat().st_size:
        fail("release manifest SBOM byte count differs from the SBOM")
    print("Verified CycloneDX SBOM: application identity, 17 packages, graph, licenses, hashes, and safe content.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError, VerificationError) as error:
        print(f"SBOM verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
