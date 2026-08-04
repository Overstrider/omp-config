# OMP fork bundle

This directory makes the runtime fork reproducible without committing a
platform-specific 160+ MB executable.

- `manifest.json` pins the exact fork repository and base commit containing
  the Kimi K3 harness plus the earlier Cursor and Merlin fixes.
- `patches/oh-my-pi-runtime-fixes.patch` carries the later Grok stream
  recovery, model-discovery, and global ask-timeout fixes together with their
  regression tests and changelogs.
- `scripts/Install-OmpFork.ps1` verifies the manifest and patch hashes, applies
  the patch exactly once, runs the relevant tests and checks, builds OMP, and
  installs a content-addressed binary for the current user.

Generated source, binaries, and the local runtime pointer stay under ignored
runtime paths or the Bun user bin directory. No credential is stored here.
