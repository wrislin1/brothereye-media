---
name: brainstorming-locals
description: Use alongside brainstorming for planning and execution. Disciplines learned from prior sessions — one question at a time, gloss unfamiliar tech terms inline, decompose scope first, first question must be the framing fork, and ASK the user before staging a workaround when blocked.
---

# Brainstorming locals — media server overlay

Applies on top of general brainstorming patterns. These are specific disciplines that prevent common failure modes in planning sessions.

## 1. One question at a time. Yes, even with AskUserQuestion.

`AskUserQuestion` supports 1–4 questions per batch. Use it for **the** one question, not as license to batch.

**Why this rule exists.** Multi-question batches force the user to commit context for downstream decisions before they've understood the upstream one — and downstream questions usually get reshaped by upstream answers.

**Exception.** Scope-decomposition / slicing questions where options are explicitly independent may batch up to **2**. Never more.

**Test.** If the answer to Q1 might change what Q2 should ask, you can't batch them.

## 2. Explain unfamiliar tech terms inline before asking dependent questions.

If an option label or description contains a term that isn't standard for this user, gloss it in the option's `description` field — or ship the explanation as its own message *before* the question.

**Test.** If the user couldn't answer the question without googling a term you used, you owe them the explanation up-front.

## 3. Scope-decomposition is the FIRST move after recon.

Before any design question, ask yourself: "is this one project or several?" If several, ship the slicing proposal as the first message. Don't ship a sub-design question for slice 1 while the user is still thinking the request is one whole.

**Test.** Can you state in one sentence what's in scope for slice 1 and what's deferred to later slices? If not, you haven't decomposed yet.

## 4. The first clarifying question is the framing fork.

After (3), the first design question should be the architectural fork where all downstream decisions depend on the answer. Not "what colour" but "is this a viewer, or a service?"

**Test.** If the second question's options would be identical regardless of how the first is answered, you picked the wrong first question.

## 5. When blocked, ASK before staging a workaround.

When you encounter a block — missing tool, missing perm, path that doesn't exist, service not running, env var not set — surface it to the user before silently routing around it. The user often can fix the root cause faster than you can devise the workaround.

**The pattern.** Before writing or staging the workaround:
- Name the block in one sentence.
- Name the root-cause fix (often a one-line system change the user can do).
- Surface both and ask which they prefer.

**Exception.** Truly trivial detours (absolute vs relative path, picking which of two equivalent libraries) don't need the round-trip.

## 6. Multi-repo reviews: check `git status` on EVERY repo, not just `git log`.

When reviewing work that spans more than one repo, run `git status --short` on each repo before forming an opinion. `git log` only sees committed history; working-tree state often diverges.

Use `scripts/cross-repo-status.sh <path1> <path2> ...` as the one-shot recon.

**Test.** If your review's recommendation depends on what code exists in another repo, can you point to the exact `git status` and `git log` output you read?
