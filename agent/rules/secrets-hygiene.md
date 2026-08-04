---
description: Keep credentials and private OMP runtime state out of Git.
alwaysApply: true
---

Never force-add API keys, OAuth tokens, passwords, private keys, `.env`,
`secrets.yml`, `secret-placeholder.key`, databases, sessions, logs, caches, or
installed `node_modules`. Configuration may reference environment-variable
names, but must not contain their secret values.
