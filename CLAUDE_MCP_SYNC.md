Why sync Claude MCP servers with Codex
====================================

Summary
-------
This project uses a set of MCP servers (Model Context Protocol servers) to provide tooling to both the Codex CLI and Claude agent. Codex is already configured for a set of MCP servers in `.codex/config.toml` (for example: `dart`, `github`, `code-review-graph`). To make Claude behave the same way when it starts, we synchronize its local MCP configuration so it can call the same project-local MCP servers.

Why this matters
-----------------
- Consistency: both agents will see the same tool surface (code-review graph, GitHub fetch, Dart mcp server) and therefore run the same fetch/review/format flows.
- Reproducibility: team members running Claude locally will get the same behavior as Codex sessions without manual reconfiguration.
- Security: the project-local PAT and env are read from `.codex/.env` and the same MCP servers avoid using any global or unauthenticated tools.

What I changed
--------------
- Updated `.claude/settings.local.json` to enable the same MCP servers configured by `.codex/config.toml` (`code-review-graph`, `github`, `dart`).
- Added this file to explain the reason and how to start the servers.

How to validate locally
-----------------------
1. Copy the example env into place and fill secrets (do NOT commit):

```powershell
Copy-Item .codex\.env.example .codex\.env
# Edit .codex\.env and set GITHUB_PERSONAL_ACCESS_TOKEN, ORACLE_VM_IP, TMDB_TOKEN
```

2. Quick health check (PowerShell):

```powershell
.
.codex\scripts\check-mcp.ps1
```

3. Start the GitHub MCP server (the helper runs `npx -y @modelcontextprotocol/server-github`):

```powershell
.
.codex\scripts\start-github-mcp.ps1
```

4. Start `code-review-graph` (Python):

```powershell
# install once
python -m pip install --user code-review-graph
code-review-graph init
code-review-graph serve
```

5. Start the Dart MCP server if needed (configured in `.codex/config.toml` as `mcp_servers.dart`): run from project root:

```powershell
# The dart MCP server is configured to be: `dart mcp-server` in .codex/config.toml
# Ensure `dart` is on PATH and run the server as documented for your environment.
```

Notes and safety
----------------
- Keep `.codex/.env` private. Never commit it.
- If a server fails to start, check the corresponding install instructions in `MCP_SETUP.md` and the helper scripts in `.codex/scripts`.

If you want, I can also:
- add `github` and `dart` to `enabledMcpjsonServers` automatically (already done),
- create a short verification script that performs one sample call using each MCP server (fetch a GitHub file, request code-review-graph context), or
- revert the change if you'd prefer a different MCP list.