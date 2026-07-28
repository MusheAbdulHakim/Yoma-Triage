"""Tests for the versioned referral graph catalog API."""
from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_referral_graph_returns_versioned_catalog_with_coordinates(
    client, seeded_db
) -> None:
    response = await client.get(
        "/api/v1/catalog/referral-graph",
        params={"region": "northern"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["version"] == "2026-07-28.4"
    assert body["region"] == "northern"
    assert len(body["compounds"]) == 16
    assert len(body["facilities"]) == 16
    assert set(body["compounds"][0]) == {
        "id",
        "name",
        "latitude",
        "longitude",
        "district",
    }
    assert set(body["facilities"][0]) >= {
        "id",
        "name",
        "latitude",
        "longitude",
        "district",
        "has_maternity",
        "has_icu",
        "type",
    }
    assert isinstance(body["preferred_links"], list)
    assert len(body["preferred_links"]) == 16


@pytest.mark.asyncio
async def test_referral_graph_excludes_private_and_driver_data(client, seeded_db) -> None:
    response = await client.get("/api/v1/catalog/referral-graph")

    assert response.status_code == 200
    body = response.json()
    assert "drivers" not in body
    assert all("phone" not in compound for compound in body["compounds"])
    assert all("phone" not in facility for facility in body["facilities"])
    assert "patient" not in response.text.lower()


@pytest.mark.asyncio
async def test_referral_graph_filters_by_district(client, seeded_db) -> None:
    response = await client.get(
        "/api/v1/catalog/referral-graph",
        params={"district": "Tamale Metropolitan"},
    )

    assert response.status_code == 200
    body = response.json()
    assert [compound["id"] for compound in body["compounds"]] == [1]
    assert [facility["id"] for facility in body["facilities"]] == [1]


@pytest.mark.asyncio
async def test_referral_graph_unknown_region_404(client, seeded_db) -> None:
    response = await client.get(
        "/api/v1/catalog/referral-graph",
        params={"region": "savannah"},
    )
    assert response.status_code == 404
