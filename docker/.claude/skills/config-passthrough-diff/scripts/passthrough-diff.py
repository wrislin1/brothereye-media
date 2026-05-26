#!/usr/bin/env python3
"""Semantic set-diff for config migrations.

Compare two YAML/JSON files as sets of tuple-keys per logical group. Designed
for verifying that a hand-written config and a generator-produced config are
semantically equivalent — surfacing missing or extra entries that text-diff
would bury in formatting noise.

Exit codes: 0 = full match; 1 = at least one group diverges.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


def load(path: Path) -> Any:
    text = path.read_text()
    if path.suffix in (".yaml", ".yml"):
        import yaml
        return yaml.safe_load(text)
    return json.loads(text)


def dotted_get(obj: Any, path: str) -> Any:
    """Resolve a dotted path like 'litellm_params.model' against a nested dict."""
    cur = obj
    for part in path.split("."):
        if cur is None:
            return None
        if isinstance(cur, dict):
            cur = cur.get(part)
            continue
        if "[" in part and part.endswith("]"):
            name, idx = part[:-1].split("[", 1)
            cur = cur.get(name)
            if isinstance(cur, list):
                cur = cur[int(idx)]
            else:
                return None
            continue
        return None
    return cur


def extract_groups(
    doc: Any, list_path: str, group_by: str | None, key_fields: list[str]
) -> dict[str, set[tuple]]:
    items = dotted_get(doc, list_path)
    if items is None:
        raise SystemExit(f"list-path {list_path!r} not found in document")
    if not isinstance(items, list):
        raise SystemExit(f"list-path {list_path!r} did not resolve to a list")
    groups: dict[str, set[tuple]] = defaultdict(set)
    for item in items:
        group = "(all)" if group_by is None else str(dotted_get(item, group_by))
        tup = tuple(dotted_get(item, kf) for kf in key_fields)
        groups[group].add(tup)
    return groups


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--left", required=True, type=Path, help="ground-truth file")
    ap.add_argument("--right", required=True, type=Path, help="file under test")
    ap.add_argument("--list-path", required=True,
                    help="dotted path to the list of comparable items")
    ap.add_argument("--group-by", default=None,
                    help="dotted field within each item used as group key")
    ap.add_argument("--key-fields", required=True, nargs="+",
                    help="dotted fields whose values form the tuple identity")
    ap.add_argument("--max-print", type=int, default=10,
                    help="max diverging tuples to print per group (default 10)")
    args = ap.parse_args()

    left = load(args.left)
    right = load(args.right)

    lg = extract_groups(left, args.list_path, args.group_by, args.key_fields)
    rg = extract_groups(right, args.list_path, args.group_by, args.key_fields)

    all_groups = sorted(set(lg) | set(rg))
    total_match = total_only_left = total_only_right = 0
    any_diff = False
    for g in all_groups:
        ls = lg.get(g, set())
        rs = rg.get(g, set())
        match = ls & rs
        only_l = ls - rs
        only_r = rs - ls
        total_match += len(match)
        total_only_left += len(only_l)
        total_only_right += len(only_r)
        if only_l or only_r:
            any_diff = True
            label = f"group={g}" if args.group_by else "(all)"
            print(f"== {label} ==")
            print(f"  matches: {len(match)}")
            print(f"  only-in-left: {len(only_l)}")
            for t in sorted(only_l)[: args.max_print]:
                print(f"    {t}")
            if len(only_l) > args.max_print:
                print(f"    ... and {len(only_l) - args.max_print} more")
            print(f"  only-in-right: {len(only_r)}")
            for t in sorted(only_r)[: args.max_print]:
                print(f"    {t}")
            if len(only_r) > args.max_print:
                print(f"    ... and {len(only_r) - args.max_print} more")

    status = "MISMATCH" if any_diff else "MATCH"
    print(
        f"SUMMARY: {total_match} matches, "
        f"{total_only_left} only-left, {total_only_right} only-right — {status}"
    )
    return 1 if any_diff else 0


if __name__ == "__main__":
    sys.exit(main())
