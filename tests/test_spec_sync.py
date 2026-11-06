"""Keeps PRODUCT_SPEC.md honest about the things batch 3 synced."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
SPEC = (REPO / "PRODUCT_SPEC.md").read_text(encoding="utf-8")


def _section(start: str, end: str) -> str:
    return SPEC[SPEC.index(start) : SPEC.index(end, SPEC.index(start))]


def test_old_spec_copy_is_gone_and_nothing_links_to_it():
    assert not (REPO / "docs/yoma-triage-product-spec.md").exists()
    tracked = subprocess.run(
        ["git", "grep", "-l", "yoma-triage-product-spec", "--", "*.md", "*.py", "*.dart", "*.yaml"],
        cwd=REPO,
        capture_output=True,
        text=True,
    ).stdout.split()
    assert [path for path in tracked if path != "tests/test_spec_sync.py"] == []


def test_yamnet_never_reports_green():
    section = _section("### 7.1.1 Acoustic Screening", "### 7.1.2")
    assert "**GREEN: Normal**" not in section
    assert "YAMNet never reports GREEN" in section
    assert "normal breathing, wheeze, crackle, stridor" not in section


def test_part_v_no_longer_promises_normal_or_code_red():
    section = _section("# PART V", "# PART VI")
    assert "Normal or Code Red" not in section
    assert "Incomplete" in section


def test_incomplete_result_is_described():
    section = _section("### Triage Categories", "### Integration with Acoustic")
    assert "**Incomplete" in section
    assert "Green (Score: 0-2)" not in section
    assert "SpO₂ not measured" in section


@pytest.mark.parametrize(
    "heading",
    [
        "### 7.1.3 Emergency: Skip Vitals",
        "## 7.8 CHO Registration",
        "## 7.9 Offline Manual Fallback",
        "## 10.8 Durable Dispatch and SMS Outbox",
        "## 10.9 RAG and LLM",
    ],
)
def test_built_features_have_a_section(heading):
    assert heading in SPEC


@pytest.mark.parametrize(
    "decision",
    ["**Pilot scope, paediatric or obstetric:**", "**Acoustic screening in the pilot:**"],
)
def test_pilot_scope_is_an_open_decision(decision):
    assert decision in _section("### Open Decisions", "# PART I")


@pytest.mark.parametrize(
    "unbuilt",
    [
        "### 7.5.1 Purpose\n\n> **Not built:**",
        "### 7.7.1 Purpose\n\n> **Not built:**",
        "### 8.2 Clinical Triage (SLM — Small Language Model)\n\n> **Not built:**",
        "### 8.3 Referral Prioritization\n\n> **Not built:**",
        "### 9.6.1 Outcome Recording\n\n> **Not built:**",
        "## Journey 5: Family Refuses Transport\n\n> **Not built:**",
    ],
)
def test_unbuilt_features_are_marked_not_deleted(unbuilt):
    assert unbuilt in SPEC


def test_every_endpoint_in_the_spec_exists():
    import main

    def normalized(path: str) -> str:
        return re.sub(r"\{[^}]+\}", "{}", path)

    paths = {normalized(path) for path in main.app.openapi()["paths"]}
    table = _section("| Endpoint | Method | Purpose |", "**Key services:**")
    for line in table.splitlines():
        if line.startswith("| `"):
            path = line.split("`")[1].split(" ")[1]
            assert normalized(path) in paths, path
