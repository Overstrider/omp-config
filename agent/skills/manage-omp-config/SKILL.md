---
name: manage-omp-config
description: Maintain the active, Git-versioned Oh My Pi configuration while keeping credentials and runtime state untracked.
---

# Manage OMP config

This repository is the active OMP config root.

- Portable settings belong in `agent/config.yml`.
- MCP servers belong in `agent/mcp.json`.
- Skills, agents, commands, extensions, rules, prompts, tools, and hooks belong
  under their matching `agent/` directories.
- Pin plugin dependencies through `omp plugin install <name>@<version>` and
  review `plugins/package.json`.
- Never force-add ignored databases, sessions, `.env`, secrets, credentials,
  caches, logs, or `node_modules`.
- Run `scripts/Test-OmpConfigRepo.ps1` before committing.
