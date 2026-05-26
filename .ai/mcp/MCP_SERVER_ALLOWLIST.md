# MCP Server Allowlist

## Currently Approved MCP Servers

| Server | Purpose | Scope | Reviewed |
|--------|---------|-------|----------|
| *(populate as servers are reviewed)* | | | |

## How to Add a Server

1. Create a proposal in `.ai/mcp/proposals/`
2. Document the server's: name, purpose, network access, filesystem access
3. Get security review
4. Add to this allowlist with scope limits

## Template

```markdown
### Server Name
- **Purpose**: What it does
- **Network**: What it connects to
- **Filesystem**: What it reads/writes
- **Secrets access**: Yes/No (explain)
- **Approved by**: Reviewer name
- **Date**: YYYY-MM-DD
- **Expires**: YYYY-MM-DD (review date)
```
