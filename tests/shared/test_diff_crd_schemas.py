#!/usr/bin/env python3
"""Unit tests for diff-crd-schemas.py."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "shared" / "diff-crd-schemas.py"


def write_crd(
    target: Path,
    *,
    name: str,
    group: str,
    kind: str,
    versions: list[dict],
) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "apiVersion": "apiextensions.k8s.io/v1",
        "kind": "CustomResourceDefinition",
        "metadata": {"name": name},
        "spec": {
            "group": group,
            "names": {"kind": kind, "plural": f"{kind.lower()}s"},
            "scope": "Namespaced",
            "versions": versions,
        },
    }
    target.write_text(yaml.safe_dump(document), encoding="utf-8")


def run_diff(baseline_dir: Path, upstream_dir: Path, output: Path) -> dict:
    subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--baseline-dir",
            str(baseline_dir),
            "--upstream-dir",
            str(upstream_dir),
            "--output",
            str(output),
        ],
        check=True,
    )
    return json.loads(output.read_text(encoding="utf-8"))


def test_no_changes_when_schemas_match(tmp_path: Path) -> None:
    schema = {
        "type": "object",
        "properties": {
            "spec": {
                "type": "object",
                "properties": {"active": {"type": "boolean"}},
            }
        },
    }
    version = [{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": schema}}]
    write_crd(tmp_path / "baseline" / "demo.yaml", name="demo.example.com", group="example.com", kind="Demo", versions=version)
    write_crd(tmp_path / "upstream" / "demo.yaml", name="demo.example.com", group="example.com", kind="Demo", versions=version)

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    assert results["has_changes"] is False
    assert results["total_changes"] == 0


def test_detects_added_field(tmp_path: Path) -> None:
    baseline_schema = {
        "type": "object",
        "properties": {"spec": {"type": "object", "properties": {"active": {"type": "boolean"}}}},
    }
    upstream_schema = {
        "type": "object",
        "properties": {
            "spec": {
                "type": "object",
                "properties": {
                    "active": {"type": "boolean"},
                    "queueName": {"type": "string"},
                },
            }
        },
    }
    write_crd(
        tmp_path / "baseline" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": baseline_schema}}],
    )
    write_crd(
        tmp_path / "upstream" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": upstream_schema}}],
    )

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    assert results["has_changes"] is True
    changes = results["crds"][0]["schema_changes"]
    assert any(change["change"] == "added" and change["path"] == "spec.queueName" for change in changes)


def test_detects_removed_field(tmp_path: Path) -> None:
    baseline_schema = {
        "type": "object",
        "properties": {
            "spec": {
                "type": "object",
                "properties": {
                    "active": {"type": "boolean"},
                    "queueName": {"type": "string"},
                },
            }
        },
    }
    upstream_schema = {
        "type": "object",
        "properties": {"spec": {"type": "object", "properties": {"active": {"type": "boolean"}}}},
    }
    write_crd(
        tmp_path / "baseline" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": baseline_schema}}],
    )
    write_crd(
        tmp_path / "upstream" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": upstream_schema}}],
    )

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    changes = results["crds"][0]["schema_changes"]
    assert any(change["change"] == "removed" and change["path"] == "spec.queueName" for change in changes)


def test_detects_type_change(tmp_path: Path) -> None:
    baseline_schema = {
        "type": "object",
        "properties": {"spec": {"type": "object", "properties": {"priority": {"type": "integer"}}}},
    }
    upstream_schema = {
        "type": "object",
        "properties": {"spec": {"type": "object", "properties": {"priority": {"type": "string"}}}},
    }
    write_crd(
        tmp_path / "baseline" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": baseline_schema}}],
    )
    write_crd(
        tmp_path / "upstream" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": upstream_schema}}],
    )

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    changes = results["crds"][0]["schema_changes"]
    assert any(change["change"] == "modified" and change["path"] == "spec.priority" for change in changes)


def test_detects_version_deprecation(tmp_path: Path) -> None:
    baseline_versions = [
        {"name": "v1beta1", "served": True, "storage": False, "schema": {"openAPIV3Schema": {"type": "object"}}},
        {"name": "v1beta2", "served": True, "storage": True, "schema": {"openAPIV3Schema": {"type": "object"}}},
    ]
    upstream_versions = [
        {"name": "v1beta1", "served": False, "storage": False, "schema": {"openAPIV3Schema": {"type": "object"}}},
        {"name": "v1beta2", "served": True, "storage": True, "schema": {"openAPIV3Schema": {"type": "object"}}},
    ]
    write_crd(
        tmp_path / "baseline" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=baseline_versions,
    )
    write_crd(
        tmp_path / "upstream" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=upstream_versions,
    )

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    version_changes = results["crds"][0]["version_changes"]
    assert any(change["version"] == "v1beta1" and change["change"] == "served_changed" for change in version_changes)


def test_detects_enum_expansion(tmp_path: Path) -> None:
    baseline_schema = {
        "type": "object",
        "properties": {
            "spec": {
                "type": "object",
                "properties": {"stopPolicy": {"type": "string", "enum": ["None", "Hold"]}},
            }
        },
    }
    upstream_schema = {
        "type": "object",
        "properties": {
            "spec": {
                "type": "object",
                "properties": {"stopPolicy": {"type": "string", "enum": ["None", "Hold", "Drain"]}},
            }
        },
    }
    write_crd(
        tmp_path / "baseline" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": baseline_schema}}],
    )
    write_crd(
        tmp_path / "upstream" / "demo.yaml",
        name="demo.example.com",
        group="example.com",
        kind="Demo",
        versions=[{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": upstream_schema}}],
    )

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    changes = results["crds"][0]["schema_changes"]
    assert any(change["change"] == "modified" and change["path"] == "spec.stopPolicy" for change in changes)


def test_dynamic_discovery_from_baseline_directory(tmp_path: Path) -> None:
    schema = {"type": "object", "properties": {"spec": {"type": "object"}}}
    version = [{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": schema}}]
    write_crd(tmp_path / "baseline" / "one.yaml", name="one.example.com", group="example.com", kind="One", versions=version)
    write_crd(tmp_path / "baseline" / "two.yaml", name="two.example.com", group="example.com", kind="Two", versions=version)
    write_crd(tmp_path / "upstream" / "one.yaml", name="one.example.com", group="example.com", kind="One", versions=version)

    results = run_diff(tmp_path / "baseline", tmp_path / "upstream", tmp_path / "out.json")
    assert results["has_changes"] is True
    assert any(entry.get("error") == "missing_upstream" for entry in results["crds"])
