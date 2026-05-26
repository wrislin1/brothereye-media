---
name: code-intelligence
description: Use when navigating, reviewing, or refactoring code where symbol definitions, references, diagnostics, or call impact matter. Prefer Serena/LSP for semantic code intelligence and rg for plain-text/config searches.
---

Use Serena/LSP as the semantic layer and the normal shell tools as the text/runtime layer.

## Use Serena/LSP for

- Symbol overview for a file or module.
- Go-to-definition and hover/type context.
- Find references before changing functions, classes, config helpers, callbacks, or public interfaces.
- Diagnostics before and after semantic edits.
- Rename/refactor blast-radius checks.

## Use `rg` or shell tools for

- Plain text, docs, configs, shell snippets, logs, generated bundles, Docker Compose, and systemd units.
- Runtime/service truth from Docker container state.
- YAML/JSON config files (docker-compose, env files, etc.).

## Review flow

1. Use `rg` to find likely files and non-code references.
2. Use Serena/LSP to inspect symbols, definitions, and references in source files.
3. Make scoped edits following repo patterns.
4. Run the narrowest relevant validation: syntax checks, script checks, or stack health checks as appropriate.

Do not trust LSP alone for operational behavior; Docker container state, logs, and network connectivity must be verified with shell tools.
