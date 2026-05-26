---
name: skill-evolve
description: Use at the end of a non-trivial task to review the back-and-forth, decide whether anything surprising should become a forever rule, and produce a concrete edit to the relevant skill (or scaffold a new one).
---

# Skill-evolve

The point of skills is that they get smarter every session. After any non-trivial task, the question is: *what surprised us, and should it become a forever rule?* If yes, the rule belongs in a skill — not in a memory, not in CLAUDE.md, not lost.

## When to invoke

- At the end of a coding session that involved correction, friction, or a non-obvious win.
- When the user explicitly says "remember this" or "we keep hitting this."
- When you (the agent) had to course-correct mid-task — that's a signal a skill missed a case.
- When a new pattern emerged that the user accepted without pushback.

## The recipe

Walk through `references/upgrade-recipe.md`. The short version:

1. **List the surprises.** What corrections, redirections, or accepted-without-pushback choices showed up that weren't covered by an existing skill?
2. **Triage each one: one-time or forever?**
   - *One-time*: it was specific to this codebase / this PR / this hour. Drop it.
   - *Forever*: it would recur if you faced a similar task next month. Keep it.
3. **For each "forever" item, locate the right owner.**
   - Existing skill that should cover this? Propose a specific diff to that skill.
   - No existing skill is a fit? Propose a new skill: name, one-line description, what's in `SKILL.md`, what scripts/references would carry the leverage.
4. **Output the proposal as concrete edits, not prose.** Use code blocks with file paths. The user should be able to approve or reject each one in isolation.
5. **Bias toward tools over prose.** Most leverage is in scripts, references, and structured data — not more bullet points.

## Output shape

Always finish with a numbered list like:

```
1. ADD scripts/foo.sh to .claude/skills/code-intelligence/  — reason: …
2. EDIT .claude/skills/docker-stack-health/SKILL.md          — add a "do not …" note
3. NEW skill `media-health`                                  — see attached SKILL.md sketch
```

So the user can quickly say "yes, do 1 and 3; skip 2." Then implement only what they accepted, and stop.

## What NOT to do

- Don't propose memory entries. Memory is for context about the user; skills are for procedural knowledge.
- Don't propose CLAUDE.md edits unless the rule is *meta*. Specific behaviors belong in skills.
- Don't write the edits without showing the user the diff first. The user opts in per item.
