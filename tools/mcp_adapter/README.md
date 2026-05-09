MCP Adapter notes — migrating Codex/Claude usage to MCP
------------------------------------------------------

What this does

- Provides guidance and small helpers to use the Model Context Protocol (MCP) servers
  in place of the older Codex/Claude CLI flows used previously.

Recommended quick steps

1. Populate `.codex/.env` from `.codex/.env.example`.
2. Start `code-review-graph` and the GitHub MCP server (see `MCP_SETUP.md`).
3. Confirm `.claude/settings.local.json` has `enableAllProjectMcpServers` true and
   that `enabledMcpjsonServers` includes `code-review-graph` and `github` if you plan to use them.
4. Optionally flip `experimental_use_rmcp_client = true` in `.codex/config.toml` to try the RMCP client.

How to use MCP tools instead of Codex CLI calls

- File fetch / GitHub operations: use the `github` MCP server configured in `.codex/config.toml`.
- Code review / graph ops: use `code-review-graph` MCP server.
- For ad-hoc tasks you previously ran with `codex` or `claude`, run the corresponding MCP server command directly (the `.codex/config.toml` entries show examples).

Automation

- This repo already contains `.codex/scripts/start-github-mcp.ps1` which runs `npx -y @modelcontextprotocol/server-github`.
- Use `MCP_SETUP.md` for step-by-step instructions on Windows.

If you want, I can:

- Flip `experimental_use_rmcp_client` to true in `.codex/config.toml` and create a short verification script.
- Create a minimal Node helper that proxies common Codex CLI calls to MCP JSON endpoints.

Tell me which of the above you want me to implement next.
