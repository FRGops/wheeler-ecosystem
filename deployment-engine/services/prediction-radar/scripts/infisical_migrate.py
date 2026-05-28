#!/usr/bin/env python3
"""Migrate Prediction Radar secrets from .env → Infisical.

Reads the current .env file, identifies secrets (anything with key containing
PASSWORD, SECRET, KEY, TOKEN, or with a value that looks like a credential),
and pushes them to an Infisical project.

Usage:
  INFISICAL_TOKEN=<svc-token> python3 scripts/infisical_migrate.py --dry-run
  INFISICAL_TOKEN=<svc-token> python3 scripts/infisical_migrate.py --migrate

Requires: INFISICAL_TOKEN env var (service token for prediction-radar project)
          INFISICAL_API_URL env var (default: http://100.118.166.117:8443)
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

API_URL = os.getenv("INFISICAL_API_URL", "http://100.118.166.117:8443")
TOKEN = os.getenv("INFISICAL_TOKEN", "")
PROJECT_ID = os.getenv("INFISICAL_PROJECT_ID", "")
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"

# Patterns that identify a value as a secret (not a config value like "true" or "localhost")
SECRET_KEY_PATTERNS = [
    r"(?i)PASSWORD", r"(?i)SECRET", r"(?i)API_?KEY", r"(?i)TOKEN",
    r"(?i)PRIVATE_?KEY", r"(?i)WEBHOOK", r"(?i)ENCRYPTION",
    r"(?i)CREDENTIAL", r"(?i)AUTH_?TOKEN",
]

PUBLIC_CONFIG_KEYS = {
    "PAPER_MODE", "ENABLE_LIVE_EXECUTION", "LOG_LEVEL", "DEBUG",
    "PORT", "HOST", "DATABASE_URL", "REDIS_URL", "QUESTDB_HOST",
    "QUESTDB_PORT", "INFISICAL_API_URL",
}


def is_secret_key(key: str) -> bool:
    if key in PUBLIC_CONFIG_KEYS:
        return False
    return any(re.search(p, key) for p in SECRET_KEY_PATTERNS)


def is_secret_value(value: str) -> bool:
    """Heuristic: long random-ish strings are likely secrets."""
    if len(value) < 16:
        return False
    if value.startswith("$"):  # env var reference
        return False
    if value in ("true", "false", "yes", "no", "1", "0"):
        return False
    if re.match(r"^\d+$", value):  # purely numeric
        return False
    if re.match(r"^https?://", value):  # URL
        return False
    return True


def parse_env_file(path: Path) -> dict[str, str]:
    """Parse a dotenv file, returning key-value pairs."""
    secrets = {}
    if not path.exists():
        print(f"ERROR: .env file not found at {path}", file=sys.stderr)
        sys.exit(1)

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if not key or not value:
                continue
            if is_secret_key(key) or is_secret_value(value):
                secrets[key] = value
    return secrets


def api_request(method: str, path: str, body: dict | None = None) -> dict:
    """Make an authenticated Infisical API request."""
    url = f"{API_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Content-Type", "application/json")
    try:
        with urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        err = e.read().decode()[:300]
        return {"error": str(e.code), "detail": err}
    except URLError as e:
        return {"error": "connection_failed", "detail": str(e)}


def push_secrets(secrets: dict[str, str], dry_run: bool = False) -> int:
    """Push secrets to Infisical v3 API. Returns count of secrets pushed."""
    pushed = 0
    for key, value in sorted(secrets.items()):
        if dry_run:
            print(f"  [DRY-RUN] {key}={value[:6]}{'*' * max(0, len(value)-6)}")
            pushed += 1
            continue

        result = api_request("POST", f"/api/v3/secrets/raw/{key}", {
            "secretValue": value,
            "workspaceId": PROJECT_ID,
            "environment": "prod",
            "type": "shared",
        })
        if "error" in result:
            print(f"  ERROR pushing {key}: {result.get('detail', result['error'])}", file=sys.stderr)
        else:
            print(f"  OK {key}")
            pushed += 1
    return pushed


def main():
    if not TOKEN:
        print("ERROR: INFISICAL_TOKEN not set. Export your service token.", file=sys.stderr)
        print("Get one from: http://100.118.166.117:8443/admin", file=sys.stderr)
        sys.exit(1)

    if not PROJECT_ID:
        print("ERROR: INFISICAL_PROJECT_ID not set. Export your project ID.", file=sys.stderr)
        sys.exit(1)

    dry_run = "--dry-run" in sys.argv
    do_migrate = "--migrate" in sys.argv

    if not dry_run and not do_migrate:
        print("Usage: INFISICAL_TOKEN=<token> python3 scripts/infisical_migrate.py --dry-run | --migrate")
        sys.exit(1)

    secrets = parse_env_file(ENV_FILE)
    print(f"Parsed {len(secrets)} secrets from {ENV_FILE}")
    pushed = push_secrets(secrets, dry_run=dry_run)

    if dry_run:
        print(f"\nDRY-RUN: Would push {pushed} secrets to Infisical at {API_URL}")
        print("Run with --migrate to actually push.")
    else:
        print(f"\nMigrated {pushed} secrets to Infisical at {API_URL}")


if __name__ == "__main__":
    main()
