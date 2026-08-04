---
description: Frontend changes require Playwright e2e verification before done.
alwaysApply: true
---

# Frontend Playwright e2e (mandatory)

Any frontend UI change is incomplete until verified end-to-end with Playwright.

## When this applies

- New or changed UI screens, components, flows, forms, navigation, auth UX,
  layouts, visual states, client routing, or browser-visible behavior.
- Bug fixes that affect what the user sees or clicks in a browser.

## Required workflow

1. Read `skill://playwright` (in-session browser) and/or
   `skill://playwright-cli` (project `npx playwright test` / agent-browser).
2. Prefer the project's existing Playwright suite when present:
   run the relevant specs with `npx playwright test` (or the project's script).
3. If no suite covers the change, drive the real UI with the OMP `browser`
   tool / Playwright helpers and exercise the changed path end-to-end.
4. Record concrete proof: pass/fail output, URL, and what was clicked/asserted.
5. Do not mark frontend work done without that Playwright evidence.

## Allowed vs forbidden browser control

- Required: Playwright via `skill://playwright`, `skill://playwright-cli`,
  or the OMP `browser` tool.
- Forbidden: Orca computer-use, desktop mouse/keyboard simulation, or other
  OS-level UI automation (see "No desktop control").

## Non-goals

- Pure backend/API/CLI changes with no browser UI do not need Playwright.
- Unit/component tests alone do not satisfy this rule for UI changes.
