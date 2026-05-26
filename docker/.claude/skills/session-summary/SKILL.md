---
name: session-summary
description: Use at the end of a working session (or on demand) to produce a Markdown document summarizing what was done — files changed, key commands run, decisions made, outstanding items. Writes the doc to ~/.claude/session-summaries/ by default.
---

# /session-summary — recap document

Produces a Markdown summary of the current working session. The output is both written to a file under `~/.claude/session-summaries/` and echoed inline so it can be pasted directly into a PR description, Slack, or a handoff note.

This skill documents *what happened*. It does not propose changes to other skills — that's `/skill-evolve`.

## When to invoke

- End of any non-trivial session.
- Before a handoff, before walking away, before context might be lost.
- When the user asks "what did we do today / in this session?"
- Before opening a PR — the summary is a draft PR description.

## How to invoke

```
/session-summary              # default: slug derived from the work
/session-summary <slug>       # forces a kebab-case slug into the filename
/session-summary -o <path>    # write to an explicit path instead of ~/.claude/session-summaries/
```

## Process

1. **Collect ground truth.** Run `scripts/collect-context.sh` from the current working directory. It dumps a Markdown block describing the repo, branch, uncommitted edits, recent commits, and ahead-of-base diffstat. Read its output before drafting — do not invent files-changed lists from memory.

2. **Draft the summary** by filling in `references/template.md`. The conversation context is the source for *what we decided, why, and what's deferred*; `collect-context.sh` is the source for *what actually changed on disk*. Reconcile the two.

3. **Save it.** Pipe the rendered Markdown into `scripts/save-summary.sh --echo` via stdin. Pass the slug (or `-o <path>`) if provided.

4. **Echo back.** Use the `--echo` output verbatim so the saved summary and chat response cannot drift.

## What goes in (mapped to template)

- **Title**: project (from `git remote` or CWD basename) and timestamp.
- **TL;DR**: 1-2 sentences of the session's outcome.
- **Tasks completed**: numbered list. One line per task, in the order they happened.
- **Files changed**: from `collect-context.sh` git status / diff stat.
- **Key commands run**: the meaningful ones (tests, builds, docker ops, ssh/scp). Skip noisy `grep`/`ls` calls.
- **Decisions & rationale**: each meaningful decision with the *why*.
- **Verification**: ✅ confirmed / ⚠️ partial / ❌ failed-or-untested. Be honest about what wasn't tested.
- **Deferred / open items**: anything explicitly skipped, blocked, or "for next session."

## Local state

Saved summaries live under `~/.claude/session-summaries/`. Never commit them into a work repo.
