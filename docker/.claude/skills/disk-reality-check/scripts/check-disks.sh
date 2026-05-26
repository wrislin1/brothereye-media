#!/usr/bin/env bash
# Emit a structured disk-reality report for use BEFORE committing to a storage
# plan. Read-only. Exits 0 if probes ran; non-fatal on per-disk parted errors.
set -uo pipefail

run_parted() {
  local rc
  if command -v sudo >/dev/null 2>&1; then
    sudo -n parted -l 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then return 0; fi
  fi
  echo "(parted -l skipped — sudo unavailable or not permitted)"
  return 0
}

echo "### Block tree (lsblk)"
echo
echo '```'
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,MODEL 2>&1
echo '```'
echo

echo "### Mounted filesystems (df -h, /dev/*)"
echo
echo '```'
df -h --output=source,size,used,avail,pcent,target 2>&1 | awk 'NR==1 || /^\/dev/'
echo '```'
echo

echo "### Partition tables (parted -l)"
echo
echo '```'
run_parted | head -300
echo '```'
echo

echo "### Reconcile checklist"
cat <<'EOF'
Before continuing the plan, answer in writing:
  • Is the "free space" number I'm relying on:
      ☐ inside an existing FS (df Avail)?  → note which FS, who else uses it
      ☐ raw unallocated space (parted gap)? → confirm with parted output above
      ☐ another partition I plan to reclaim? → confirm the partition's purpose
  • Does the live state contradict any claim in CLAUDE.md, the plan, or memory?
      → if yes, surface to the user before re-planning silently.
  • Are any partitions off-limits (Windows NTFS, recovery, ESP)?
      → list them explicitly so they don't get accidentally touched.
EOF
