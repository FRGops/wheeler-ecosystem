"""
Wheeler Ecosystem API Test Configuration

Usage:
    pytest tests/api/ -v --base-url https://fundsrecoverygroup.com
    pytest tests/api/test_frgcrm_api.py --api-token $FRGCRM_TOKEN

Environment variables:
    TEST_BASE_URL          Default base URL for all APIs
    TEST_API_TOKEN         Default bearer token for authenticated tests
    TEST_REQUEST_TIMEOUT   Default HTTP request timeout (seconds)
"""
import pytest
import os
import requests


def pytest_addoption(parser):
    parser.addoption(
        "--base-url",
        default=os.environ.get("TEST_BASE_URL", "https://fundsrecoverygroup.com"),
        help="Base URL for the API under test",
    )
    parser.addoption(
        "--api-token",
        default=os.environ.get("TEST_API_TOKEN", ""),
        help="Bearer token for authenticated endpoints",
    )
    parser.addoption(
        "--timeout",
        type=int,
        default=int(os.environ.get("TEST_REQUEST_TIMEOUT", "10")),
        help="HTTP request timeout in seconds",
    )
    parser.addoption(
        "--api", action="append", default=[],
        help="Run tests for a specific API module (frgcrm|surplusai|attorneys|brain|radar)",
    )


@pytest.fixture(scope="session")
def base_url(request):
    """Return the configured base URL."""
    return request.config.getoption("--base_url")


@pytest.fixture(scope="session")
def api_token(request):
    """Return the configured API token (empty string if not set)."""
    return request.config.getoption("--api_token")


@pytest.fixture(scope="session")
def timeout(request):
    """Return the configured HTTP timeout in seconds."""
    return request.config.getoption("--timeout")


@pytest.fixture(scope="session")
def session():
    """Create a requests.Session for the test session, closed after all tests."""
    s = requests.Session()
    yield s
    s.close()


@pytest.fixture
def auth_headers(api_token):
    """Return Authorization headers if a token is configured, else empty dict."""
    if api_token:
        return {"Authorization": f"Bearer {api_token}"}
    return {}


# ------------------------------------------------------------------
# API-specific base URL fixtures
# ------------------------------------------------------------------
@pytest.fixture
def frgcrm_url(base_url):
    return f"{base_url}/api/crm"


@pytest.fixture
def surplusai_url(base_url):
    return f"{base_url}/api/surplusai"


@pytest.fixture
def attorneys_url(base_url):
    return f"{base_url}/api/attorneys"


@pytest.fixture
def brain_url(base_url):
    return f"{base_url}/api/brain"


@pytest.fixture
def radar_url(base_url):
    return f"{base_url}/api/radar"


# ------------------------------------------------------------------
# Convenience helpers
# ------------------------------------------------------------------
def assert_json_response(resp):
    """Assert that the response has a JSON content type or parseable body."""
    ct = resp.headers.get("content-type", "")
    if "application/json" in ct:
        return
    # Fallback: try to parse as JSON anyway
    try:
        resp.json()
    except ValueError as e:
        raise AssertionError(
            f"Response is not JSON. Content-Type: {ct}. Body: {resp.text[:200]}"
        ) from e


def assert_response_time(start_time, limit=2.0):
    """Assert elapsed time is under the limit."""
    import time
    elapsed = time.time() - start_time
    if elapsed > limit:
        raise AssertionError(
            f"Response took {elapsed:.3f}s, exceeding limit of {limit}s"
        )


def skip_if_unreachable(url, session, reason="Server unreachable"):
    """Decorator/helper: skip a test if the target server cannot be reached.
    Usage as a check (not a true decorator — call at start of test):
        skip_if_unreachable(health_url, session)
    """
    import socket
    try:
        resp = session.get(url, timeout=5)
        if resp.status_code == 0:
            pytest.skip(reason)
    except (requests.ConnectionError, requests.Timeout, socket.error):
        pytest.skip(reason)
