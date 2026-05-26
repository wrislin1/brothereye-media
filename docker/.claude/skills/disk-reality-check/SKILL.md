---
name: disk-reality-check
description: Use BEFORE planning storage layout, partitioning, new mounts, or anything that depends on "free space" estimates. Forces a live lsblk/parted/df probe and reconciles against prior claims.
---

# /disk-reality-check — verify disk state before planning storage

A 30-second sanity check before committing to a storage plan. Catches the failure mode where documentation, memory, or user expectation says "we have ~1 TB free" but the live disk state disagrees.

## When to invoke

- A plan or task references creating a new mount, partition, filesystem, or "free space" you intend to use.
- The user says "use the unallocated terabyte" / "we have plenty of room on X" / "create a partition for …".
- A skill or plan cites a stored figure. Verify before relying on it.
- BEFORE writing destructive partitioning commands (`parted mkpart`, `mkfs`, `resize2fs`).

## What it does

`scripts/check-disks.sh` emits three sections, in order, with no side effects:

1. **`lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,MODEL`** — block tree, sizes, what's a filesystem vs. raw partition.
2. **`df -h` for `/dev/*` mounts** — actual used / available per mount.
3. **`parted -l` per disk** (best-effort via sudo; otherwise prints "skipped").

The script always exits 0 if the probes ran; failure to access a particular disk via parted is non-fatal.

## How to interpret

After running the script, **explicitly reconcile against prior claims** before continuing:

- An "unpartitioned" claim is only true if `lsblk` shows the device with **no children** AND `parted -l` reports no partition table or the partition table is empty.
- A "free space" claim must point at one of:
  - **Inside an existing FS** (`df -h Avail` column) — usable now, but the FS may be shared with another consumer; call that out.
  - **Unallocated raw space** between partitions (visible only in `parted -l` as a gap).
  - **NTFS partitions** — do NOT count as available unless the user explicitly says it's safe to touch.
- Always ask back if reality contradicts the plan. Don't silently re-plan against a different number.

## Composability

- Run before any infra-migration plan finalizes.
- For Docker-data filesystems specifically, sanity-check with `du -sh` on Docker volumes and media library paths.
