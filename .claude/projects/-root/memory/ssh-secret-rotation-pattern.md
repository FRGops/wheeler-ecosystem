---
name: ssh-secret-rotation-pattern
description: "Safe pattern for rotating secrets across SSH — use scp tmp file, never rely on bash variable persistence"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cf1e5c0f-ee3a-43ab-aadd-f99343ec85e0
---

When rotating secrets across multiple servers, never rely on bash variables persisting between Claude Code Bash tool calls. Each call is a separate shell process.

**Why:** Lost the wheeler postgres password mid-rotation because `${NEW_PW}` was empty in a subsequent Bash call. Had to recover by reading the correct password back from AIOPS.

**How to apply:** Use scp to pass secrets between servers, or do the full rotation in a single chained Bash call. Pattern:
```
PW=$(openssl rand -hex 24)
echo "$PW" > /tmp/secret.txt
scp /tmp/secret.txt root@TARGET:/tmp/
ssh root@TARGET 'PW=$(cat /tmp/secret.txt); sed -i "s|OLD|${PW}|" /path/.env; rm /tmp/secret.txt'
rm /tmp/secret.txt
```
Never: set variable in one Bash call, use in another. Always verify the written value after sed.
