#!/bin/bash
# aint-farm nightly backup (chg-009): the running app writes an online snapshot of factory.db
# (`factory backup`, node:sqlite's backup API, safe while it writes), it is streamed home, checked with
# PRAGMA integrity_check, and only then published as backup/aint-farm/factory-<date>.db. The box keeps
# no copy. Skips with a message when the aint-farm container doesn't exist; fails when the box is
# unreachable or the container isn't running.
#
#   scripts/aint-farm-backup.sh <dest dir>
set -euo pipefail

DEST="${1:?usage: aint-farm-backup.sh <dest dir>}"
BOX="${AINT_FARM_BACKUP_BOX:-root@187.124.159.132}"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 "$BOX")
STAMP=$(date +%Y-%m-%d)

state=$("${SSH[@]}" "docker ps -a --filter name=^aint-farm\$ --format '{{.State}}'") || {
  echo "aint-farm backup: cannot reach the box" >&2
  exit 1
}
if [ -z "$state" ]; then
  echo "aint-farm backup: no aint-farm container on the box; nothing to back up"
  exit 0
fi
[ "$state" = running ] || { echo "aint-farm backup: the aint-farm container is $state, not running" >&2; exit 1; }

mkdir -p "$DEST"
TMP="$DEST/.factory-$STAMP.db.tmp"
trap 'rm -f "$TMP"' EXIT
SNAP="/data/backups/nightly-$STAMP.db"
"${SSH[@]}" "docker exec aint-farm sh -c 'mkdir -p /data/backups && factory backup $SNAP > /dev/null && cat $SNAP && rm -f $SNAP'" > "$TMP"
ok=$(python3 -c 'import sqlite3, sys; print(sqlite3.connect(sys.argv[1]).execute("PRAGMA integrity_check").fetchone()[0])' "$TMP")
[ "$ok" = ok ] || { echo "aint-farm backup: the snapshot failed its integrity check: $ok" >&2; exit 1; }
mv "$TMP" "$DEST/factory-$STAMP.db"
trap - EXIT
echo "aint-farm backup ok: $DEST/factory-$STAMP.db"
