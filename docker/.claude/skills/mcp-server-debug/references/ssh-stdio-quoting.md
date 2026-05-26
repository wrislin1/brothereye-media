# The remote-shell redirection trap in MCP args

## The fault

When an MCP server's `command` is `ssh` and the last `args[]` element is the remote command string, that string is passed to the remote login shell. Anything that looks like shell syntax **will be interpreted there**.

The one that bites in practice is the `>` in a version pin:

```jsonc
// looks reasonable, is broken
"args": ["riz-llm", "cd /opt/app && exec uv run --with mcp>=1.13.0 python -u server.py"]
```

The remote bash parses `mcp>=1.13.0` as: token `mcp` + redirection `>=1.13.0`. So stdout goes to a file named `=1.13.0` instead of back over SSH.

## Diagnostic fingerprints

- `claude mcp list` shows `✗ Failed to connect` for an SSH-tunneled server.
- Manual probe returns **0 bytes**, rc=0.
- A file with a suspicious literal name appears remotely — e.g. `=1.13.0`.

## Fixes (pick one)

**Single-quote the constraint** (recommended):
```jsonc
"cd /opt/app && exec uv run --with 'mcp>=1.13.0' python -u server.py"
```

**Backslash-escape the `>`**:
```jsonc
"cd /opt/app && exec uv run --with mcp\\>=1.13.0 python -u server.py"
```

**Drop the pin** if latest is acceptable:
```jsonc
"cd /opt/app && exec uv run --with mcp python -u server.py"
```

## Other characters that bite

| Char(s) | Why it bites |
|---|---|
| `>`, `>>`, `<`, `<<` | Redirections |
| `\|`, `&`, `;` | Pipelines / backgrounding / separators |
| `*`, `?`, `[...]` | Globbing |
| `{a,b}` | Brace expansion |
| `` ` ``, `$( )`, `$VAR` | Command/variable substitution |
| `~` | Tilde expansion |

Rule of thumb: **if the arg contains anything outside `[A-Za-z0-9_./=-]`, quote it.**

## After-fix checklist

1. Validate JSON: `python3 -c "import json; json.load(open('$HOME/.claude.json'))"`
2. Probe: `scripts/probe-mcp-stdio.sh "<command + args>"` — expect a JSON line.
3. `claude mcp list | grep <name>` — should be `✓ Connected`.
4. Clean up any leftover file remotely: `ssh <host> 'rm -f <dir>/=*'`.
