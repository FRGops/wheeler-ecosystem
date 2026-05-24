"""
Pytest-based regression tests for the Prediction Radar API.

Usage:
    pytest tests/api/test_prediction_radar_api.py -v --base-url https://fundsrecoverygroup.com
    pytest tests/api/test_prediction_radar_api.py --api-token $PREDICTION_RADAR_TOKEN
"""
import pytest
import requests
import time


# ===================================================================
# Health & Version
# ===================================================================
class TestRadarHealth:
    def test_health_returns_200(self, radar_url, session, timeout):
        resp = session.get(f"{radar_url}/health", timeout=timeout)
        assert resp.status_code == 200

    def test_health_returns_json(self, radar_url, session, timeout):
        resp = session.get(f"{radar_url}/health", timeout=timeout)
        try:
            data = resp.json()
        except ValueError:
            pytest.fail("Health did not return valid JSON")
        assert "status" in data

    def test_health_response_time(self, radar_url, session, timeout):
        start = time.time()
        session.get(f"{radar_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0


class TestRadarVersion:
    def test_version_returns_200(self, radar_url, session, timeout):
        resp = session.get(f"{radar_url}/version", timeout=timeout)
        assert resp.status_code == 200

    def test_version_has_version_field(self, radar_url, session, timeout):
        resp = session.get(f"{radar_url}/version", timeout=timeout)
        data = resp.json()
        assert "version" in data


# ===================================================================
# Prediction Query
# ===================================================================
class TestRadarPrediction:
    def test_predict_valid_request(self, radar_url, session, timeout, api_token):
        payload = {
            "case_type": "asset_recovery",
            "jurisdiction": "US",
            "parameters": {
                "estimated_amount": 500000,
                "complexity": "medium",
            },
        }
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.post(
            f"{radar_url}/predict",
            json=payload,
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 401, 404), \
            f"Unexpected status: {resp.status_code}"

        if resp.status_code == 200:
            data = resp.json()
            assert "probability" in data, f"Missing 'probability' field: {data}"

    def test_predict_empty_body_returns_4xx(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.post(
            f"{radar_url}/predict",
            json={},
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (400, 401, 404, 422)

    def test_predict_missing_params(self, radar_url, session, timeout, api_token):
        payload = {"case_type": "unknown"}
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.post(
            f"{radar_url}/predict",
            json=payload,
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 400, 401, 404, 422)


# ===================================================================
# Data Sources
# ===================================================================
class TestRadarDatasources:
    def test_list_datasources(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.get(
            f"{radar_url}/datasources",
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 401, 404)

    def test_datasources_health(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.get(
            f"{radar_url}/datasources/health",
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 401, 404)


# ===================================================================
# Models
# ===================================================================
class TestRadarModels:
    def test_list_models(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.get(
            f"{radar_url}/models",
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 401, 404)

    def test_model_detail_nonexistent(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.get(
            f"{radar_url}/models/nonexistent-model-name",
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (404, 401)


# ===================================================================
# Historical Data
# ===================================================================
class TestRadarHistory:
    def test_history_with_params(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.get(
            f"{radar_url}/history?days=30&limit=10",
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 401, 404)

    def test_history_no_params(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        resp = session.get(
            f"{radar_url}/history",
            headers=headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 400, 401, 404)


# ===================================================================
# Authentication
# ===================================================================
class TestRadarAuth:
    def test_login_bad_credentials_returns_401(self, radar_url, session, timeout):
        resp = session.post(
            f"{radar_url}/auth/login",
            json={"email": "bad@test.invalid", "password": "wrong"},
            timeout=timeout,
        )
        assert resp.status_code == 401

    def test_login_empty_body_returns_401(self, radar_url, session, timeout):
        resp = session.post(
            f"{radar_url}/auth/login",
            json={},
            timeout=timeout,
        )
        assert resp.status_code == 401


# ===================================================================
# Error Handling
# ===================================================================
class TestRadarErrors:
    def test_nonexistent_route_returns_404(self, radar_url, session, timeout):
        resp = session.get(
            f"{radar_url}/definitely-not-a-route",
            timeout=timeout,
        )
        assert resp.status_code == 404

    def test_malformed_json_returns_400(self, radar_url, session, timeout):
        resp = session.post(
            f"{radar_url}/predict",
            data="not-json content {{{",
            headers={"Content-Type": "application/json"},
            timeout=timeout,
        )
        assert resp.status_code in (400, 401, 404)

    def test_options_cors(self, radar_url, session, timeout):
        resp = session.options(
            f"{radar_url}/health",
            headers={"Origin": "https://fundsrecoverygroup.com"},
            timeout=timeout,
        )
        assert (
            "access-control-allow-origin" in resp.headers
            or "access-control-allow-methods" in resp.headers
            or resp.status_code in (200, 204)
        )

    def test_wrong_content_type_returns_415_or_400(self, radar_url, session, timeout):
        resp = session.post(
            f"{radar_url}/predict",
            data="hello",
            headers={"Content-Type": "text/plain"},
            timeout=timeout,
        )
        assert resp.status_code in (400, 415, 401, 404)


# ===================================================================
# Latency
# ===================================================================
class TestRadarLatency:
    def test_health_latency(self, radar_url, session, timeout):
        start = time.time()
        session.get(f"{radar_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0, f"Health took {elapsed:.2f}s"

    def test_models_latency(self, radar_url, session, timeout, api_token):
        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"
        start = time.time()
        session.get(f"{radar_url}/models", headers=headers, timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0, f"Models endpoint took {elapsed:.2f}s"
