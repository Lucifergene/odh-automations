#!/usr/bin/env python3
"""Compare CRD OpenAPI schemas between dashboard fixtures and upstream CRDs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import yaml


def load_crd(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def discover_crd_files(fixture_dir: Path) -> list[Path]:
    return sorted(fixture_dir.glob("*.yaml"))


def get_comparison_version(crd: dict[str, Any]) -> str | None:
    versions = crd.get("spec", {}).get("versions", [])
    for version in versions:
        if version.get("storage"):
            return version["name"]
    for version in versions:
        if version.get("served"):
            return version["name"]
    return versions[0]["name"] if versions else None


def get_schema(crd: dict[str, Any], version: str) -> dict[str, Any] | None:
    for entry in crd.get("spec", {}).get("versions", []):
        if entry.get("name") == version:
            return entry.get("schema", {}).get("openAPIV3Schema")
    return None


def summarize_schema(schema: dict[str, Any]) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    if schema.get("type"):
        summary["type"] = schema["type"]
    if "enum" in schema:
        summary["enum"] = schema["enum"]
    if schema.get("format"):
        summary["format"] = schema["format"]
    if schema.get("x-kubernetes-int-or-string"):
        summary["intOrString"] = True
    if schema.get("nullable"):
        summary["nullable"] = True
    return summary


def walk_schema_paths(schema: dict[str, Any] | None, prefix: str = "") -> dict[str, dict[str, Any]]:
    paths: dict[str, dict[str, Any]] = {}
    if not schema:
        return paths

    schema_type = schema.get("type")
    if schema_type == "object":
        properties = schema.get("properties", {})
        for key, value in properties.items():
            path = f"{prefix}.{key}" if prefix else key
            paths[path] = summarize_schema(value)
            paths.update(walk_schema_paths(value, path))
    elif schema_type == "array":
        items = schema.get("items", {})
        item_prefix = f"{prefix}[]" if prefix else "[]"
        paths[item_prefix] = summarize_schema(items)
        paths.update(walk_schema_paths(items, item_prefix))
    elif prefix:
        paths[prefix] = summarize_schema(schema)

    return paths


def compare_schema_paths(
    baseline_paths: dict[str, dict[str, Any]],
    upstream_paths: dict[str, dict[str, Any]],
) -> list[dict[str, Any]]:
    changes: list[dict[str, Any]] = []
    for path in sorted(set(baseline_paths) | set(upstream_paths)):
        baseline = baseline_paths.get(path)
        upstream = upstream_paths.get(path)
        if baseline is None and upstream is not None:
            changes.append({"path": path, "change": "added", "upstream": upstream})
        elif baseline is not None and upstream is None:
            changes.append({"path": path, "change": "removed", "baseline": baseline})
        elif baseline != upstream:
            changes.append(
                {
                    "path": path,
                    "change": "modified",
                    "baseline": baseline,
                    "upstream": upstream,
                }
            )
    return changes


def compare_versions(
    baseline_crd: dict[str, Any],
    upstream_crd: dict[str, Any],
) -> list[dict[str, Any]]:
    changes: list[dict[str, Any]] = []
    baseline_versions = {
        version["name"]: version for version in baseline_crd.get("spec", {}).get("versions", [])
    }
    upstream_versions = {
        version["name"]: version for version in upstream_crd.get("spec", {}).get("versions", [])
    }

    for name in sorted(set(baseline_versions) | set(upstream_versions)):
        if name not in baseline_versions:
            changes.append({"version": name, "change": "added"})
            continue
        if name not in upstream_versions:
            changes.append({"version": name, "change": "removed"})
            continue

        baseline = baseline_versions[name]
        upstream = upstream_versions[name]
        if baseline.get("served") != upstream.get("served"):
            changes.append(
                {
                    "version": name,
                    "change": "served_changed",
                    "baseline": baseline.get("served"),
                    "upstream": upstream.get("served"),
                }
            )
        if baseline.get("storage") != upstream.get("storage"):
            changes.append(
                {
                    "version": name,
                    "change": "storage_changed",
                    "baseline": baseline.get("storage"),
                    "upstream": upstream.get("storage"),
                }
            )

    return changes


def diff_crd_pair(baseline_file: Path, upstream_file: Path) -> dict[str, Any]:
    baseline_crd = load_crd(baseline_file)
    upstream_crd = load_crd(upstream_file)
    version = get_comparison_version(baseline_crd) or get_comparison_version(upstream_crd)

    version_changes = compare_versions(baseline_crd, upstream_crd)
    schema_changes: list[dict[str, Any]] = []
    if version:
        baseline_schema = get_schema(baseline_crd, version)
        upstream_schema = get_schema(upstream_crd, version)
        if baseline_schema and upstream_schema:
            schema_changes = compare_schema_paths(
                walk_schema_paths(baseline_schema),
                walk_schema_paths(upstream_schema),
            )

    return {
        "file": baseline_file.name,
        "group": baseline_crd.get("spec", {}).get("group"),
        "kind": baseline_crd.get("spec", {}).get("names", {}).get("kind"),
        "version": version,
        "version_changes": version_changes,
        "schema_changes": schema_changes,
    }


def diff_directories(baseline_dir: Path, upstream_dir: Path) -> dict[str, Any]:
    results: dict[str, Any] = {
        "baseline_dir": str(baseline_dir),
        "upstream_dir": str(upstream_dir),
        "crds": [],
        "has_changes": False,
        "total_changes": 0,
    }

    for baseline_file in discover_crd_files(baseline_dir):
        upstream_file = upstream_dir / baseline_file.name
        if not upstream_file.exists():
            entry = {
                "file": baseline_file.name,
                "error": "missing_upstream",
                "version_changes": [],
                "schema_changes": [],
            }
            results["crds"].append(entry)
            results["has_changes"] = True
            results["total_changes"] += 1
            continue

        entry = diff_crd_pair(baseline_file, upstream_file)
        change_count = len(entry["version_changes"]) + len(entry["schema_changes"])
        if change_count > 0:
            results["has_changes"] = True
        results["total_changes"] += change_count
        results["crds"].append(entry)

    return results


def write_github_output(path: Path, results: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"has_changes={'true' if results['has_changes'] else 'false'}\n")
        handle.write(f"total_changes={results['total_changes']}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Diff CRD schemas between baseline and upstream.")
    parser.add_argument("--baseline-dir", required=True, type=Path)
    parser.add_argument("--upstream-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()

    results = diff_directories(args.baseline_dir, args.upstream_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        json.dump(results, handle, indent=2)

    if args.github_output:
        write_github_output(args.github_output, results)

    print(json.dumps({"has_changes": results["has_changes"], "total_changes": results["total_changes"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
