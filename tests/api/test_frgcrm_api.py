"""
Pytest-based regression tests for the FRGCRM API.

Usage:
    pytest tests/api/test_frgcrm_api.py -v --base-url https://fundsrecoverygroup.com
    pytest tests/api/test_frgcrm_api.py --api-token $FRGCRM_TOKEN
"""
import pytest
import requests
import time
import json


# ===================================================================
# Health Endpoint
# ===================================================================
class TestFRGCRMHealth:
    """Health-check endpoint tests."""

    def test_health_returns_200(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/health", timeout=timeout)
        assert resp.status_code == 200

    def test_health_returns_json(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/health", timeout=timeout)
        ct = resp.headers.get("content-type", "")
        try:
            data = resp.json()
        except ValueError:
            data = None
        assert "application/json" in ct or data is not None, \
            f"Expected JSON, got Content-Type={ct}"

    def test_health_contains_status_field(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/health", timeout=timeout)
        data = resp.json()
        assert "status" in data, f"Missing 'status' field in response: {data}"

    def test_health_response_time(self, frgcrm_url, session, timeout):
        start = time.time()
        session.get(f"{frgcrm_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0, f"Health endpoint took {elapsed:.2f}s (limit: 2s)"


# ===================================================================
# Version Endpoint
# ===================================================================
class TestFRGCRMVersion:
    """Version endpoint tests."""

    def test_version_returns_200(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/version", timeout=timeout)
        assert resp.status_code == 200

    def test_version_returns_json(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/version", timeout=timeout)
        try:
            resp.json()
        except ValueError:
            pytest.fail("Version endpoint did not return valid JSON")

    def test_version_has_version_field(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/version", timeout=timeout)
        data = resp.json()
        assert "version" in data, f"Missing 'version' field: {data}"


# ===================================================================
# Authentication
# ===================================================================
class TestFRGCRMAuth:
    """Authentication endpoint tests."""

    def test_login_empty_body_returns_401(self, frgcrm_url, session, timeout):
        resp = session.post(f"{frgcrm_url}/auth/login", json={}, timeout=timeout)
        assert resp.status_code == 401

    def test_login_bad_credentials_returns_401(self, frgcrm_url, session, timeout):
        payload = {"email": "invalid@nonexistent.test", "password": "wrong"}
        resp = session.post(f"{frgcrm_url}/auth/login", json=payload, timeout=timeout)
        assert resp.status_code == 401

    def test_login_missing_password_returns_401(self, frgcrm_url, session, timeout):
        payload = {"email": "user@example.com"}
        resp = session.post(f"{frgcrm_url}/auth/login", json=payload, timeout=timeout)
        assert resp.status_code == 401

    def test_protected_cases_no_token_returns_401(self, frgcrm_url, session, timeout):
        resp = session.get(f"{frgcrm_url}/cases", timeout=timeout)
        assert resp.status_code == 401

    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_verify_token_endpoint(self, frgcrm_url, session, timeout, auth_headers):
        resp = session.get(
            f"{frgcrm_url}/auth/verify",
            headers=auth_headers,
            timeout=timeout,
        )
        # May be 200 (valid) or 404 (endpoint not implemented)
        assert resp.status_code in (200, 404), f"Unexpected status: {resp.status_code}"


# ===================================================================
# Cases
# ===================================================================
class TestFRGCRMCases:
    """Case management endpoint tests (authenticated)."""

    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_list_cases_with_token(self, frgcrm_url, session, timeout, auth_headers):
        resp = session.get(
            f"{frgcrm_url}/cases",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code == 200
        data = resp.json()
        # Response should be a list or contain a list field
        assert isinstance(data, (list, dict)), "Unexpected response structure"

    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_get_nonexistent_case_returns_404(self, frgcrm_url, session, timeout, auth_headers):
        resp = session.get(
            f"{frgcrm_url}/cases/nonexistent-test-id-99999",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code == 404


# ===================================================================
# Error Handling
# ===================================================================
class TestFRGCRMErrors:
    """Error handling and edge-case tests."""

    def test_nonexistent_route_returns_404(self, frgcrm_url, session, timeout):
        resp = session.get(
            f"{frgcrm_url}/this-route-does-not-exist-12345",
            timeout=timeout,
        )
        assert resp.status_code == 404

    def test_malformed_json_returns_400(self, frgcrm_url, session, timeout):
        resp = session.post(
            f"{frgcrm_url}/cases",
            data="this is not valid json {{broken",
            headers={"Content-Type": "application/json"},
            timeout=timeout,
        )
        assert resp.status_code == 400

    def test_options_cors_headers(self, frgcrm_url, session, timeout):
        resp = session.options(
            f"{frgcrm_url}/health",
            headers={"Origin": "https://fundsrecoverygroup.com"},
            timeout=timeout,
        )
        assert (
            "access-control-allow-origin" in resp.headers
            or "access-control-allow-methods" in resp.headers
            or resp.status_code in (200, 204)
        ), f"CORS headers missing; status={resp.status_code}"

    def test_invalid_method_returns_405(self, frgcrm_url, session, timeout):
        resp = session.patch(f"{frgcrm_url}/health", timeout=timeout)
        assert resp.status_code in (405, 404), \
            f"Expected 405 or 404, got {resp.status_code}"
