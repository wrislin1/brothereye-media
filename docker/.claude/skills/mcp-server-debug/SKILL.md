---
name: mcp-server-debug
description: Use when an MCP server shows "Failed to connect" in `claude mcp list`, or its tools fail to appear in a session — diagnose stdio/SSE/HTTP MCP servers layer-by-layer, with special attention to silent failure modes (remote-shell redirection eating stdout, stdin-EOF early exit, missing version pins).
---

# Debug MCP server connection failures

Connection failures in MCP servers often present as a generic "Failed to connect" or `MCP error -32000: Connection closed`. The server may actually be running fine — the failure is usually in the transport. Don't guess; probe each layer.

## When to use

- `claude mcp list` shows `✗ Failed to connect` for a server you control.
- A session reminder says a server is "still connecting" and never resolves.
- Your `mcp__<server>__*` tools are missing or vanish mid-session.
- You just added or edited an entry under `mcpServers` in `~/.claude.json` (or any project `.mcp.json`).

Don't use this for SaaS HTTP MCP servers that say "Needs authentication" — those just need an OAuth login.

## The recipe

Work the layers in order. Each step has a single yes/no answer; don't skip ahead.

### 1. Get the exact error and timing

```bash
claude --debug 'mcp' --debug-file /tmp/claude-mcp.log mcp get <server-name>
grep -iE "(<server-name>|fail|connect|spawn|error)" /tmp/claude-mcp.log
```

### 2. Reproduce the transport manually

For stdio servers, copy the `command` + `args` from `claude mcp get` and run them with stdin held open:

```bash
( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"debug","version":"0"}}}'; sleep 10 ) \
  | <exact-command-from-mcp-get>
```

You should see a JSON line with `"result":{"protocolVersion":..., "serverInfo":...}`.

If you get **no output and rc=0**, the server's stdout is being lost — see `references/ssh-stdio-quoting.md`.

`scripts/probe-mcp-stdio.sh` wraps the above for any stdio command.

### 3. Confirm each layer for SSH-tunneled servers

```bash
ssh <host> 'echo ok'                                 # auth + reachability
ssh <host> 'cd <remote-dir> && <interpreter> --version'   # remote tools present
ssh <host> 'cd <remote-dir> && <full remote command>'     # exec layer
```

If layer 3 succeeds in shell but fails inside the MCP config, the difference is almost always **shell quoting** of arguments containing `>`, `<`, `|`, `*`, `?`, `{`, `}`. See `references/ssh-stdio-quoting.md`.

### 4. Verify the fix end-to-end

```bash
claude mcp list 2>&1 | grep <server-name>
```

Should now show `✓ Connected`.

## Common silent failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `Connection closed` after 20–30 s | Shell ate `>` from a `>=` version pin as a redirection | Single-quote the constraint |
| Server exits immediately, rc=0, no output | stdio server saw EOF on stdin | Hold stdin open in your probe |
| `command not found` only when launched by Claude | `env: {}` plus a `PATH`-dependent command | Use absolute paths or set `env: { "PATH": "..." }` |
| Works under `ssh` interactively, fails as MCP | Identity not loadable in non-interactive ssh | Pass `-i /full/path/to/key -o IdentitiesOnly=yes -o BatchMode=yes` |
| Server starts but `tools/list` returns nothing | Server's tool registration crashed at import | Look at remote stderr |

## Where MCP servers are configured

- User scope: `~/.claude.json` → `mcpServers` (top-level key).
- Project scope: `<repo>/.mcp.json`.
- Use `claude mcp get <name>` to print the effective config.

## Scripts

- `scripts/probe-mcp-stdio.sh "<full stdio command>"` — send an MCP `initialize` to a stdio command and print the first JSON line received.
