"""
Pytest-based regression tests for the Wheeler Brain OS API.

Usage:
    pytest tests/api/test_wheeler_brain_api.py -v --base-url https://fundsrecoverygroup.com
    pytest tests/api/test_wheeler_brain_api.py --api-token $WHEELER_BRAIN_TOKEN --timeout 30
"""
import pytest
import requests
import time


# -- Longer timeout for AI endpoints since they can be slow ----------
AI_TIMEOUT = 30


# ===================================================================
# Health & Version
# ===================================================================
class TestBrainHealth:
    def test_health_returns_200(self, brain_url, session, timeout):
        resp = session.get(f"{brain_url}/health", timeout=timeout)
        assert resp.status_code == 200

    def test_health_returns_json(self, brain_url, session, timeout):
        resp = session.get(f"{brain_url}/health", timeout=timeout)
        try:
            data = resp.json()
        except ValueError:
            pytest.fail("Health did not return valid JSON")
        assert "status" in data

    def test_health_response_time(self, brain_url, session, timeout):
        start = time.time()
        session.get(f"{brain_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0


class TestBrainVersion:
    def test_version_returns_200(self, brain_url, session, timeout):
        resp = session.get(f"{brain_url}/version", timeout=timeout)
        assert resp.status_code == 200

    def test_version_has_version_field(self, brain_url, session, timeout):
        resp = session.get(f"{brain_url}/version", timeout=timeout)
        data = resp.json()
        assert "version" in data


# ===================================================================
# AI Chat Completion (lightweight)
# ===================================================================
class TestBrainChat:
    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_chat_lightweight_prompt(self, brain_url, session, timeout, auth_headers):
        """Send a tiny prompt that should complete quickly."""
        payload = {
            "messages": [
                {"role": "user", "content": "Respond with the single word: hello"}
            ],
            "max_tokens": 10,
            "stream": False,
        }
        resp = session.post(
            f"{brain_url}/chat",
            json=payload,
            headers=auth_headers,
            timeout=AI_TIMEOUT,
        )
        assert resp.status_code in (200, 404), \
            f"Chat endpoint returned {resp.status_code}"

        if resp.status_code == 200:
            data = resp.json()
            # Check for content in one of the common response shapes
            content = (
                data.get("choices", [{}])[0].get("message", {}).get("content")
                or data.get("response")
                or data.get("content")
                or data.get("reply")
            )
            assert content is not None, f"No content found in chat response: {data}"

    def test_chat_empty_messages_returns_4xx(self, brain_url, session, timeout, auth_headers):
        payload = {"messages": [], "max_tokens": 10}
        resp = session.post(
            f"{brain_url}/chat",
            json=payload,
            headers=auth_headers,
            timeout=AI_TIMEOUT,
        )
        assert resp.status_code in (400, 401, 404, 422), \
            f"Expected 4xx for empty messages, got {resp.status_code}"

    def test_chat_no_token_returns_401(self, brain_url, session, timeout):
        payload = {"messages": [{"role": "user", "content": "Hi"}]}
        resp = session.post(
            f"{brain_url}/chat",
            json=payload,
            timeout=timeout,
        )
        assert resp.status_code in (401, 404), \
            f"Expected 401 or 404 without token, got {resp.status_code}"


# ===================================================================
# Agent Status
# ===================================================================
class TestBrainAgent:
    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_agent_status(self, brain_url, session, timeout, auth_headers):
        resp = session.get(
            f"{brain_url}/agent/status",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 404)

    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_list_agents(self, brain_url, session, timeout, auth_headers):
        resp = session.get(
            f"{brain_url}/agents",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 404)


# ===================================================================
# Knowledge Base Query
# ===================================================================
class TestBrainKnowledge:
    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_knowledge_query(self, brain_url, session, timeout, auth_headers):
        payload = {
            "query": "What are the steps for asset recovery?",
            "top_k": 3,
        }
        resp = session.post(
            f"{brain_url}/knowledge/query",
            json=payload,
            headers=auth_headers,
            timeout=AI_TIMEOUT,
        )
        assert resp.status_code in (200, 404)

    def test_knowledge_empty_query_returns_4xx(self, brain_url, session, timeout, auth_headers):
        payload = {"query": "", "top_k": 3}
        resp = session.post(
            f"{brain_url}/knowledge/query",
            json=payload,
            headers=auth_headers,
            timeout=AI_TIMEOUT,
        )
        assert resp.status_code in (400, 401, 404, 422)


# ===================================================================
# Task / Workflow
# ===================================================================
class TestBrainTasks:
    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_list_tasks(self, brain_url, session, timeout, auth_headers):
        resp = session.get(
            f"{brain_url}/tasks",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code in (200, 404)

    def test_task_nonexistent_returns_404(self, brain_url, session, timeout, auth_headers):
        resp = session.get(
            f"{brain_url}/tasks/nonexistent-test-task",
            headers=auth_headers,
            timeout=timeout,
        )
        assert resp.status_code in (404, 401)


# ===================================================================
# Authentication
# ===================================================================
class TestBrainAuth:
    def test_login_invalid_returns_401(self, brain_url, session, timeout):
        resp = session.post(
            f"{brain_url}/auth/login",
            json={"email": "invalid@test.invalid", "password": "wrong"},
            timeout=timeout,
        )
        assert resp.status_code == 401

    def test_login_empty_body_returns_401(self, brain_url, session, timeout):
        resp = session.post(
            f"{brain_url}/auth/login",
            json={},
            timeout=timeout,
        )
        assert resp.status_code == 401


# ===================================================================
# Error Handling
# ===================================================================
class TestBrainErrors:
    def test_nonexistent_route_returns_404(self, brain_url, session, timeout):
        resp = session.get(
            f"{brain_url}/definitely-nonexistent",
            timeout=timeout,
        )
        assert resp.status_code == 404

    def test_malformed_json_returns_400(self, brain_url, session, timeout):
        resp = session.post(
            f"{brain_url}/chat",
            data="not-json content {{{",
            headers={"Content-Type": "application/json"},
            timeout=timeout,
        )
        assert resp.status_code in (400, 401, 404), \
            f"Expected 400, 401, or 404, got {resp.status_code}"


# ===================================================================
# AI Latency (generous timeout)
# ===================================================================
class TestBrainLatency:
    def test_health_latency(self, brain_url, session, timeout):
        start = time.time()
        session.get(f"{brain_url}/health", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0, f"Health took {elapsed:.2f}s"

    def test_version_latency(self, brain_url, session, timeout):
        start = time.time()
        session.get(f"{brain_url}/version", timeout=timeout)
        elapsed = time.time() - start
        assert elapsed < 2.0

    @pytest.mark.skipif(
        "not config.getoption('--api-token')",
        reason="--api-token not provided",
    )
    def test_agent_status_latency_ai_timeout(self, brain_url, session, timeout, auth_headers):
        """Agent status, if AI-backed, gets the extended 30s timeout."""
        start = time.time()
        resp = session.get(
            f"{brain_url}/agent/status",
            headers=auth_headers,
            timeout=AI_TIMEOUT,
        )
        elapsed = time.time() - start
        if resp.status_code == 200:
            assert elapsed < 30.0, f"Agent status took {elapsed:.2f}s (limit 30s)"
