---
name: git-snapshot
description: Safely prepare infrastructure repo commits by checking branch, remote, ignored sensitive files, tracked ignored files, and staged secret patterns before commit.
argument-hint: [status|check|commit "message"]
disable-model-invocation: true
allowed-tools: Bash
---

Run from `/opt/brothereye-media`. Manual invocation only.

Use this before committing or pushing media server infrastructure changes.

## Check

```bash
echo "=== branch ==="
git rev-parse --abbrev-ref HEAD

echo "=== remote ==="
git remote -v

echo "=== gitignored sensitive files present on disk ==="
for p in docker/.env docker/.env.production secrets/; do
  [[ -e "$p" ]] && ls -l "$p" || echo "missing $p"
done

echo "=== staged files ==="
git diff --cached --name-only

echo "=== secret scan (staged) ==="
git diff --cached -U0 | grep -iE '(api[_-]?key|secret|token|password|bearer)\s*[:=]' | head -20 || echo "(clean)"

echo "=== status ==="
git status --short
```

## Commit

Only commit after the check passes and the user explicitly asked to commit:

```bash
git status --short
git diff --cached --name-only
git commit -m "<message>"
```

## Rules

- Never commit `.env`, `.env.production`, `secrets/`, Docker volumes, logs, or generated runtime state.
- Do not push unless the user explicitly asks for a push.
- If the secret scan flags a high-confidence token, stop and report the file/path without printing the secret value.
