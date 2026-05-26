# Upgrade recipe — turning a session into skill edits

Run through this template at the end of a non-trivial task.

## 1. List what surprised us this session

Fill in 2-6 lines. Each line is one observation: a correction the user made, a redirection you needed to take, a successful choice the user explicitly affirmed, or a recurring friction.

```
- <observation 1>
- <observation 2>
- ...
```

A good observation is *specific*: "the user wanted commits in conventional-commit format but the message I drafted was prose" — not "user has opinions about commits."

## 2. Triage each: one-time or forever?

For each observation, ask: *if I faced a similar task next month, would this matter again?*

```
| # | Observation | One-time or forever? | Why |
|---|-------------|----------------------|-----|
| 1 | …           | forever              | this is a global preference, not repo-specific |
| 2 | …           | one-time             | only true for this codebase's quirky build |
```

Drop the one-time rows. Continue with the forever rows.

## 3. Locate the owner

For each forever row, identify the skill that *should* own this:

- An existing skill — needs a body edit or a new script/reference.
- A new skill — better when the topic is distinct from any existing skill.
- CLAUDE.md — only if the rule is *meta* (about how skills get invoked).

## 4. Propose concrete edits

For each owner, write the actual change as a diff or a sketched new file:

### Existing skill — edit body

```
File: .claude/skills/docker-stack-health/SKILL.md
Change: in the "Known issues" section, add:
  - When Jellyfin reports unhealthy but is still serving, check transcoding temp dir.
Reason: hit this in the last session and lost 15 minutes.
```

### Existing skill — add a script

```
File: .claude/skills/docker-stack-health/scripts/check-vpn-routing.sh (NEW)
Purpose: verify gluetun container is routing *arr traffic correctly.
Reason: this check comes up every time we troubleshoot download failures.
```

### New skill

```
NEW skill: media-library-health
Frontmatter:
---
name: media-library-health
description: Check Jellyfin library scan status, Sonarr/Radarr import health, and media filesystem permissions.
---
Body sketch: …
Scripts: scripts/check-imports.sh
Reason: this is now the third time we debugged import failures from scratch.
```

## 5. Present the proposal

Output a numbered list of changes. Wait for the user to accept/reject per item. Implement only what they accept. Do not bundle.

## 6. (After approval) actually do the edits

Use the Write/Edit tools to apply each accepted change under `.claude/skills/`. After editing, run:

```bash
.claude/skills/skill-evolve/scripts/check-skill-links.sh
```
