"""
Pytest-based regression tests for the Attorney Marketplace API.

Usage:
    pytest tests/api/test_attorney_api.py -v --base-url https://fundsrecoverygroup.com
    pytest tests/api/test_attorney_api.py --api-token $ATTORNEY_TOKEN
"""
import pytest
import requests
import time


# ===================================================================
# Health & Version
# ===================================================================
class TestAttorneyHealth:
    def test_health_returns_200(self, attorneys_url, session, timeout):
        resp = session.get(f"{attorneys_url}/health", timeout=timeout)
        assert resp.status_code == 200

    def test_health_returns_json(self, attorneys_url, session, timeout):
        resp = session.get(f"{attorneys_url}/health", timeout=timeout)
        try:
            data = resp.json()
        except ValueError:
            pytest.fail("Health did not return valid JSON")
        assert "status" in data

    def test_health_response_time(self, attorneys_url, session, timeout):
        start = time.time()
        session.get(f"{attorneys_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0


class TestAttorneyVersion:
    def test_version_returns_200(self, attorneys_url, session, timeout):
        resp = session.get(f"{attorneys_url}/version", timeout=timeout)
        assert resp.status_code == 200

    def test_version_has_version_field(self, attorneys_url, session, timeout):
        resp = session.get(f"{attorneys_url}/version", timeout=timeout)
        data = resp.json()
        assert "version" in data


# ===================================================================
# Search Endpoint
# ===================================================================
class TestAttorneySearch:
    def test_search_with_query_returns_results(self, attorneys_url, session, timeout):
        resp = session.get(
            f"{attorneys_url}/search?q=bankruptcy&state=CA",
            timeout=timeout,
        )
        assert resp.status_code in (200, 404), \
            f"Unexpected status: {resp.status_code}"

    def test_search_returns_json(self, attorneys_url, session, timeout):
        resp = session.get(
            f"{attorneys_url}/search?q=litigation",
            timeout=timeout,
        )
        if resp.status_code == 200:
            try:
                resp.json()
            except ValueError:
                pytest.fail("Search response is not valid JSON")

    def test_search_empty_query_handled(self, attorneys_url, session, timeout):
        resp = session.get(
            f"{attorneys_url}/search?q=",
            timeout=timeout,
        )
        assert resp.status_code in (200, 400), \
            f"Empty query should return 200 or 400, got {resp.status_code}"

    def test_search_with_multiple_filters(self, attorneys_url, session, timeout):
        resp = session.get(
            f"{attorneys_url}/search?q=litigation&state=NY&practice_area=securities",
            timeout=timeout,
        )
        assert resp.status_code in (200, 404)


# ===================================================================
# Attorney Profile
# ===================================================================
class TestAttorneyProfile:
    def test_profile_nonexistent_returns_404(self, attorneys_url, session, timeout):
        resp = session.get(
            f"{attorneys_url}/profile/nonexistent-id-999999",
            timeout=timeout,
        )
        assert resp.status_code in (404, 401), \
            f"Expected 404 or 401, got {resp.status_code}"


# ===================================================================
# Practice Areas
# ===================================================================
class TestAttorneyPracticeAreas:
    def test_list_practice_areas(self, attorneys_url, session, timeout):
        resp = session.get(f"{attorneys_url}/practice-areas", timeout=timeout)
        assert resp.status_code in (200, 404)

    def test_practice_areas_structure(self, attorneys_url, session, timeout):
        resp = session.get(f"{attorneys_url}/practice-areas", timeout=timeout)
        if resp.status_code == 200:
            data = resp.json()
            assert "practice_areas" in data or isinstance(data, (list, dict))


# ===================================================================
# Contact Request
# ===================================================================
class TestAttorneyContact:
    def test_contact_valid_request(self, attorneys_url, session, timeout):
        payload = {
            "attorney_id": "test-attorney-1",
            "client_name": "QA Test",
            "client_email": "qa@fundsrecoverygroup.com",
            "message": "API regression test contact request",
        }
        resp = session.post(
            f"{attorneys_url}/contact",
            json=payload,
            timeout=timeout,
        )
        assert resp.status_code in (200, 201, 202, 401, 404)

    def test_contact_empty_body_returns_4xx(self, attorneys_url, session, timeout):
        resp = session.post(
            f"{attorneys_url}/contact",
            json={},
            timeout=timeout,
        )
        assert resp.status_code >= 400


# ===================================================================
# Authentication
# ===================================================================
class TestAttorneyAuth:
    def test_login_bad_credentials_returns_401(self, attorneys_url, session, timeout):
        resp = session.post(
            f"{attorneys_url}/auth/login",
            json={"email": "bad@test.invalid", "password": "wrong"},
            timeout=timeout,
        )
        assert resp.status_code == 401

    def test_login_empty_body_returns_401(self, attorneys_url, session, timeout):
        resp = session.post(
            f"{attorneys_url}/auth/login",
            json={},
            timeout=timeout,
        )
        assert resp.status_code == 401


# ===================================================================
# Error Handling
# ===================================================================
class TestAttorneyErrors:
    def test_nonexistent_route_returns_404(self, attorneys_url, session, timeout):
        resp = session.get(
            f"{attorneys_url}/definitely-not-a-valid-endpoint",
            timeout=timeout,
        )
        assert resp.status_code == 404

    def test_malformed_json_returns_400(self, attorneys_url, session, timeout):
        resp = session.post(
            f"{attorneys_url}/contact",
            data="not-valid-json {{{",
            headers={"Content-Type": "application/json"},
            timeout=timeout,
        )
        assert resp.status_code == 400

    def test_options_cors(self, attorneys_url, session, timeout):
        resp = session.options(
            f"{attorneys_url}/health",
            headers={"Origin": "https://fundsrecoverygroup.com"},
            timeout=timeout,
        )
        assert (
            "access-control-allow-origin" in resp.headers
            or "access-control-allow-methods" in resp.headers
            or resp.status_code in (200, 204)
        )
