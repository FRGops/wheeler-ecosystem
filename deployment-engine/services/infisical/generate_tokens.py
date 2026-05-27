#!/usr/bin/env python3
"""Generate Infisical access tokens for all machine identities.

Requires INFISICAL_ADMIN_TOKEN env var — obtain via:
  infisical login --method=user --email=ops@fundsrecoverygroup.com --domain=http://localhost:8080
  infisical user get token --domain=http://localhost:8080
"""
import os
import urllib.request
import json
import sys

ADMIN_TOKEN = os.environ.get("INFISICAL_ADMIN_TOKEN", "")
if not ADMIN_TOKEN:
    print("ERROR: INFISICAL_ADMIN_TOKEN environment variable not set")
    print("Run: infisical login && export INFISICAL_ADMIN_TOKEN=$(infisical user get token --plain)")
    sys.exit(1)

API = os.environ.get("INFISICAL_API_URL", "http://localhost:8080")

def api_call(method, path, data=None):
    url = f"{API}{path}"
    headers = {
        "Authorization": f"Bearer {ADMIN_TOKEN}",
        "Content-Type": "application/json"
    }
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {"error": e.code, "body": e.read().decode()}
    except Exception as e:
        return {"error": str(e)}

# Get all identities via API
resp = api_call("GET", "/api/v1/identities")
identities = []
if "identities" in resp:
    for identity in resp["identities"]:
        name = identity.get("name", "")
        id_val = identity.get("id", "")
        if name != "wheeler-infra-agent":
            identities.append((id_val, name))
elif "error" not in resp:
    # Maybe different response format
    print(f"Unexpected response: {json.dumps(resp)[:200]}")

# Fallback: hardcode the IDs we already know
if not identities:
    print("API list failed, using known IDs")
    identities = [
        ("53f62639-455f-43f8-bb92-2228d09f7eda", "wheeler-deploy-agent"),
        ("b3becc23-249e-41cb-a3ee-9dba55936506", "docker-expert"),
        ("bcce0d50-2ac1-42b2-a2e1-df3ae377aab0", "deployment-intelligence"),
        ("31279a7f-eae5-489e-a406-eb4aa222f265", "rollback-intelligence"),
        ("aadb4dde-b631-416a-843e-fc3adee370e1", "wheeler-db-agent"),
        ("ef0d47dd-5d5d-4b59-ad42-f007bd5c28dc", "database-rls-auditor"),
        ("8f3c8e8a-826e-46a0-a330-50b91c5fd379", "ecosystem-memory"),
        ("20937aa8-0575-47eb-82a8-6b44e2d8a5f5", "vector-database"),
        ("bf10459d-1f04-4d82-ba42-eadb074784e1", "wheeler-security-agent"),
        ("ce01d8e1-5f88-4a5a-a158-cbf6ef45656a", "security-intelligence"),
        ("8c28afb8-0e46-49c9-b8f6-e497f98b2d3b", "stripe-revenue"),
        ("54d5ce70-1b5c-4f47-9d82-3aaf7e76ae30", "monetization-orchestrator"),
        ("52879ec5-80b8-4f82-965c-a2f5cc9edcbd", "revenue-intelligence"),
        ("b6298e4c-f9ca-4133-8891-d4f72b93f770", "github-intelligence"),
        ("c94c48c1-8e1a-404d-9e6b-57c6b8a7a9b8", "repo-intelligence"),
        ("33b289ec-c033-4c14-a938-a0a839947ef9", "ai-routing"),
        ("1205ae7f-eeca-4a90-ae95-b62a737d7819", "ai-token-cost"),
        ("05ae70da-fa3c-45f3-accd-9a593062df46", "autonomous-execution-engine"),
        ("8a8e5d5c-5e25-43ab-8b9a-da8a6d44e23d", "chief-of-staff"),
        ("09d79246-6f60-4e90-90a3-4cb4563abe01", "wheeler-brain-core"),
        ("23c434a4-0a30-4f9d-91cf-1a3cdab1f567", "growth-orchestrator"),
        ("83cd0128-fb86-44da-bbd0-156711e9d8e7", "ecosystem-health-scoring"),
    ]

print(f"Found {len(identities)} identities to configure tokens for\n")

tokens = {}
for idx, (identity_id, name) in enumerate(identities):
    if not identity_id or not name:
        continue

    # Step 1: Configure token auth
    auth_data = {
        "accessTokenTTL": 7776000,      # 90 days
        "accessTokenMaxTTL": 7776000,
        "accessTokenTrustedIps": [{"ipAddress": "0.0.0.0/0"}]
    }
    auth_resp = api_call("POST", f"/api/v1/identities/{identity_id}/token-auth", auth_data)

    if "error" in auth_resp and auth_resp.get("error") != 200:
        # If already configured, this might return an error - that's OK
        pass

    # Step 2: Create access token
    token_resp = api_call("POST", f"/api/v1/identities/{identity_id}/token-auth/tokens", {})

    if "error" in token_resp:
        print(f"  {idx+1:2d}/{len(identities)} {name:35s} FAILED: {token_resp.get('body', token_resp.get('error', 'unknown'))[:80]}")
        continue

    token = token_resp.get("accessToken", "")
    if token:
        tokens[name] = {"identity_id": identity_id, "token": token}
        print(f"  {idx+1:2d}/{len(identities)} {name:35s} OK")
    else:
        print(f"  {idx+1:2d}/{len(identities)} {name:35s} NO TOKEN: {json.dumps(token_resp)[:100]}")

print(f"\n{'='*60}")
print(f"Total tokens created: {len(tokens)} / {len(identities)}")

# Save tokens to file with secure permissions
output_dir = "/root/.infisical"
os.makedirs(output_dir, mode=0o700, exist_ok=True)
output_path = os.path.join(output_dir, "agent_tokens.json")
with open(os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
    json.dump(tokens, f, indent=2)
print(f"Tokens saved to {output_path}")

# Summary
if len(tokens) == len(identities):
    print("\nALL IDENTITIES CONFIGURED SUCCESSFULLY")
    sys.exit(0)
else:
    missing = [name for _, name in identities if name not in tokens]
    print(f"\nMISSING: {missing}")
    sys.exit(1)
