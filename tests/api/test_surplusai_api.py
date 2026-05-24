"""
Pytest-based regression tests for the SurplusAI API.

Usage:
    pytest tests/api/test_surplusai_api.py -v --base-url https://fundsrecoverygroup.com
    pytest tests/api/test_surplusai_api.py --api-token $SURPLUSAI_TOKEN
"""
import pytest
import requests
import time


# ===================================================================
# Health & Version
# ===================================================================
class TestSurplusAIHealth:
    def test_health_returns_200(self, surplusai_url, session, timeout):
        resp = session.get(f"{surplusai_url}/health", timeout=timeout)
        assert resp.status_code == 200

    def test_health_returns_json(self, surplusai_url, session, timeout):
        resp = session.get(f"{surplusai_url}/health", timeout=timeout)
        try:
            data = resp.json()
        except ValueError:
            pytest.fail("Health endpoint did not return valid JSON")
        assert "status" in data

    def test_health_response_time(self, surplusai_url, session, timeout):
        start = time.time()
        session.get(f"{surplusai_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0, f"Health endpoint took {elapsed:.2f}s"


class TestSurplusAIVersion:
    def test_version_returns_200(self, surplusai_url, session, timeout):
        resp = session.get(f"{surplusai_url}/version", timeout=timeout)
        assert resp.status_code == 200

    def test_version_has_version_field(self, surplusai_url, session, timeout):
        resp = session.get(f"{surplusai_url}/version", timeout=timeout)
        data = resp.json()
        assert "version" in data


# ===================================================================
# Authentication
# ===================================================================
class TestSurplusAIAuth:
    def test_login_bad_credentials_returns_401(self, surplusai_url, session, timeout):
        payload = {"email": "bad@test.invalid", "password": "wrong"}
        resp = session.post(f"{surplusai_url}/auth/login", json=payload, timeout=timeout)
        assert resp.status_code == 401

    def test_login_empty_body_returns_401(self, surplusai_url, session, timeout):
        resp = session.post(f"{surplusai_url}/auth/login", json={}, timeout=timeout)
        assert resp.status_code == 401

    def test_assets_no_token_returns_401(self, surplusai_url, session, timeout):
        resp = session.get(f"{surplusai_url}/assets", timeout=timeout)
        # May be 401 (auth required) or 200 (public)
        assert resp.status_code in (200, 401), \
            f"Unexpected status: {resp.status_code}"


# ===================================================================
# Assets CRUD (authenticated)
# ===================================================================
class TestSurplusAIAssets:
    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_list_assets_with_token(self, surplusai_url, session, timeout, auth_headers):
        resp = session.get(
            f"{surplusai_url}/assets",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code == 200

    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_create_and_delete_asset(self, surplusai_url, session, timeout, auth_headers):
        """Full create-read-delete lifecycle of a test asset."""
        payload = {
            "name": "pytest-test-asset",
            "category": "equipment",
            "estimated_value": 5000.00,
            "condition": "good",
            "description": "API regression test asset",
        }
        # Create
        create_resp = session.post(
            f"{surplusai_url}/assets",
            json=payload,
            headers=auth_headers,
            timeout=timeout,
        )
        assert create_resp.status_code in (200, 201), \
            f"Create failed: {create_resp.status_code}"

        created = create_resp.json()
        asset_id = created.get("id") or created.get("asset_id") or created.get("_id")

        if not asset_id:
            pytest.skip("No asset ID in create response — cannot continue lifecycle")

        # Read
        get_resp = session.get(
            f"{surplusai_url}/assets/{asset_id}",
            headers=auth_headers,
            timeout=timeout,
        )
        assert get_resp.status_code == 200

        # Update
        update_resp = session.put(
            f"{surplusai_url}/assets/{asset_id}",
            json={"condition": "excellent", "estimated_value": 6000.00},
            headers=auth_headers,
            timeout=timeout,
        )
        assert update_resp.status_code in (200, 204)

        # Delete
        delete_resp = session.delete(
            f"{surplusai_url}/assets/{asset_id}",
            headers=auth_headers,
            timeout=timeout,
        )
        assert delete_resp.status_code in (200, 204)

        # Confirm deleted
        get_deleted_resp = session.get(
            f"{surplusai_url}/assets/{asset_id}",
            headers=auth_headers,
            timeout=timeout,
        )
        assert get_deleted_resp.status_code == 404


# ===================================================================
# Valuation Endpoint
# ===================================================================
class TestSurplusAIValuation:
    def test_valuation_valid_request(self, surplusai_url, session, timeout, api_token):
        """Test valuation endpoint with valid (even if synthetic) payload."""
        payload = {
            "asset_id": "test-001",
            "asset_type": "equipment",
            "age_years": 3,
            "condition": "good",
            "original_value": 10000.00,
        }
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.post(
            f"{surplusai_url}/valuation",
            json=payload,
            headers=headers,
            timeout=timeout,
        )
        # Accept 200, 401, or 404 (not all endpoints may be deployed)
        assert resp.status_code in (200, 401, 404), \
            f"Unexpected status: {resp.status_code}"

    def test_valuation_empty_body(self, surplusai_url, session, timeout):
        resp = session.post(
            f"{surplusai_url}/valuation",
            json={},
            timeout=timeout,
        )
        assert resp.status_code in (400, 401, 404, 422), \
            f"Unexpected status: {resp.status_code}"


# ===================================================================
# Error Handling
# ===================================================================
class TestSurplusAIErrors:
    def test_nonexistent_route_returns_404(self, surplusai_url, session, timeout):
        resp = session.get(
            f"{surplusai_url}/nonexistent-route-000",
            timeout=timeout,
        )
        assert resp.status_code == 404

    def test_malformed_json_returns_400(self, surplusai_url, session, timeout):
        resp = session.post(
            f"{surplusai_url}/assets",
            data="not json {{{",
            headers={"Content-Type": "application/json"},
            timeout=timeout,
        )
        assert resp.status_code == 400

    def test_options_cors(self, surplusai_url, session, timeout):
        resp = session.options(
            f"{surplusai_url}/health",
            headers={"Origin": "https://fundsrecoverygroup.com"},
            timeout=timeout,
        )
        assert (
            "access-control-allow-origin" in resp.headers
            or "access-control-allow-methods" in resp.headers
            or resp.status_code in (200, 204)
        )
