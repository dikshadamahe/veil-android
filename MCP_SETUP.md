MCP setup and quick start
=========================

This file explains how to start the local MCP servers used by the project's Codex/Claude tooling.

1) Create your env file

- Copy `.codex/.env.example` to `.codex/.env` and fill the secrets (do NOT commit `.codex/.env`).

PowerShell example:

Copy-Item .codex\\.env.example .codex\\.env
# Edit the file in your editor and set GITHUB_PERSONAL_ACCESS_TOKEN, ORACLE_VM_IP, TMDB_TOKEN, etc.

2) Start the GitHub MCP server (Windows PowerShell)

- The project includes a helper script used by `.codex/config.toml`:

Run these commands from the project root:

.\\.codex\\scripts\\start-github-mcp.ps1 -Check
.\\.codex\\scripts\\start-github-mcp.ps1

The helper runs `npx -y @modelcontextprotocol/server-github`.

3) Start the code-review-graph server (Python)

- Install once (Windows PowerShell):

python -m pip install --user code-review-graph
code-review-graph init
code-review-graph serve

4) Using MCP tools

- The Codex/MCP config is in `.codex/config.toml`. It maps logical servers (github, dart, code-review-graph) to commands.
- `.claude/settings.local.json` controls which MCP servers the CLAUDE agent will enable.

5) Notes

- Do not commit `.codex/.env` or any secrets.
- If you prefer to run the GitHub server without the helper script run `npx -y @modelcontextprotocol/server-github` directly.
- If you want RMCP (experimental) behavior, set `experimental_use_rmcp_client = true` in `.codex/config.toml` (be cautious).
