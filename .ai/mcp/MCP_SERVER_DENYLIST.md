# MCP Server Denylist

## Permanently Denied MCP Categories

| Category | Reason |
|----------|--------|
| Unauthenticated remote MCP servers | Security risk |
| Servers requiring production credentials | Credential exposure |
| Servers that auto-push to git | Bypasses review |
| Servers that read secrets/ or .env | Secret exfiltration |
| Servers that access personal email/social media | Privacy boundary |
| Unreviewed filesystem write tools | Data loss risk |

## Currently Denied Specific Servers

*(populate as servers are reviewed and denied)*

## Denial Process

1. Server proposed in `.ai/mcp/proposals/`
2. Security review identifies blocking issue
3. Server added to denylist with reason
4. Re-review possible if blocking issue resolved

## Override Process

Emergency override requires:
1. Written justification
2. Human approval
3. Time-limited scope (max 24 hours)
4. Post-override review
