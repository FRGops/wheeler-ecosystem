# MCP Governance Policy

## Purpose
All Model Context Protocol (MCP) servers used in the Wheeler ecosystem must be reviewed, approved, and monitored. No unvetted MCP servers.

## Allow Rules

MCP servers are allowed ONLY if:
1. **Approved**: Listed in `MCP_SERVER_ALLOWLIST.md`
2. **No secret exfiltration**: Does not read or transmit API keys, tokens, or credentials
3. **No browser/screenshot with DeepSeek**: Browser automation tools must be compatible with the model in use
4. **No production credentials**: Does not require production database or service credentials
5. **Reviewed**: Filesystem write tools have been reviewed for safety

## Deny Rules

MCP servers are BLOCKED if:
1. **Unknown remote**: Not in allowlist, connecting to unapproved remote endpoint
2. **Secret access**: Reads `.env`, `secrets/`, or environment variables
3. **Auto-deploy**: Pushes code or deploys without human review
4. **Personal accounts**: Accesses personal email, messaging, or social media unless explicitly needed
5. **Unreviewed write**: Has filesystem write capability without review

## MCP Server Lifecycle

1. **Proposal**: Document what the server does and why it's needed
2. **Review**: Security review for data access, network calls, write capabilities
3. **Approval**: Added to allowlist with scope limits
4. **Monitoring**: Activity logged; anomalies flagged
5. **Deprecation**: Removed from allowlist when no longer needed

## Emergency Disable

If an MCP server is suspected of misbehavior:
```bash
# Disable all MCP servers
export CLAUDE_CODE_DISABLE_MCP=1
```

## DeepSeek Note
When using DeepSeek V4 as the primary model, ensure MCP tools are compatible. Some MCP tools (especially browser/screenshot tools) may not work with all models.
