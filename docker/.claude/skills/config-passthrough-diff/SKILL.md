---
name: config-passthrough-diff
description: Use when migrating hand-written configs (YAML/JSON) to a manifest+generator pattern, or whenever you need to verify that a generator's output is semantically equivalent to a hand-written ground truth. Compares as sets of tuple keys per logical group, surfacing missing/extra entries.
---

# /config-passthrough-diff — semantic set-diff for generator migrations

When replacing hand-written configs with a generator (manifest -> emitted YAML), text-diff is the wrong tool. A correct generator can reorder, re-indent, or add comments and still be functionally identical. Set-diff on tuple keys is the right invariant.

## When to invoke

- You're standing up a config generator that replaces hand-written YAML/JSON files.
- Someone proposes flipping production over to the generator — verify first.
- A "generated config" looks suspiciously different by line count; need to know whether the delta is formatting or substance.
- Onboarding a hand-written config into a manifest and want to discover undocumented policy.

## What it does

`scripts/passthrough-diff.py` takes two YAML or JSON files plus a path spec, extracts comparable tuples, and compares them as sets per logical group. Exit 0 on full match; 1 on any divergence.

### Invocation

```bash
scripts/passthrough-diff.py \
  --left  /path/to/hand-written.yaml \
  --right /path/to/generated.yaml \
  --list-path 'model_list' \
  --group-by 'model_name' \
  --key-fields 'litellm_params.model' 'litellm_params.api_base'
```

- `--list-path`: dotted path into the document that yields the list to compare.
- `--group-by`: dotted field within each list item used to bucket entries. Omit for a single global bucket.
- `--key-fields`: one or more dotted fields per list item; together they form the tuple identity of an entry.

## Interpreting results

- **All zero diffs**: safe to flip the generator on.
- **`only-in-left` entries**: the hand-written file had something the generator doesn't — undocumented policy or incomplete manifest.
- **`only-in-right` entries**: the generator is creating entries that don't exist in production — likely a bug.

## Composability

- Run before any `git commit` that swaps hand-written for generated.
- For any list-structured config (Docker Compose services, Prowlarr indexers, etc.) the same script works — just point `--list-path` and `--key-fields` at the right shape.
