# Local agent rules

## Source isolation

OMP reads only its own + Pi sources:

- Allowed: `~/.omp`, project `.omp`, Pi user/project skills, `AGENTS.md`
- Disabled: Codex skills, Claude skills/commands, OpenCode commands

Do not re-enable `skills.enableCodex*`, `skills.enableClaude*`,
`commands.enableClaude*`, or `commands.enableOpencode*` unless the user
explicitly asks.

## Frontend Playwright e2e (mandatory)

- Frontend UI changes are incomplete until verified e2e with Playwright.
- Use `skill://playwright` / `skill://playwright-cli` (or project Playwright
  specs). Record concrete browser proof before marking done.
- Backend/API/CLI-only work is exempt. Unit tests alone do not satisfy this.

## No desktop control

- Never use Orca computer-use, desktop automation, accessibility APIs,
  screenshots, mouse simulation, or keyboard simulation.
- Never open, focus, manipulate, or close desktop windows or applications.
- Use background CLI, shell commands, APIs, and non-interactive processes only.
- Orca CLI background operations are allowed only when they do not manipulate
  desktop UI.
- Playwright browser automation is allowed and required for frontend UI
  verification; desktop OS automation is not.
- If a task strictly requires desktop interaction outside Playwright, stop
  and ask the user instead.
