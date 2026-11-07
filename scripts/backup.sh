#!/bin/bash
# millwright nightly backup — runs on the laptop under launchd.
# 1. Atomic SQLite snapshot of todo.db inside the todo container (todo runs
#    WAL mode; a raw cp/rsync of a live db can tear — `.backup` cannot).
# 2. Copy the snapshot to Dropbox.
# 3. Copy the Caddy certificate volume to Dropbox (keeps rebuild tests under
#    Let's Encrypt's five-duplicate-certs-per-week limit).
# 4. (chg-003) The practice app's own verified snapshot, copied home and verified
#    again (scripts/practice-backup.sh). It runs last: a failure there exits
#    non-zero after todo and caddy have already landed, and publishes nothing.
#
# Prototype failure mode: if the laptop is asleep or the box is down, tonight's
# run silently skips — no retry, no alert (spec sharp edge). Dropbox holds
# version history; old snapshots are pruned by hand.
set -euo pipefail

BOX="root@187.124.159.132"
DEST="/Users/andrew/Dropbox/andrew/secrets/millwright/backup"
STAMP=$(date +%Y-%m-%d)

mkdir -p "$DEST"

# 1+2: consistent todo.db snapshot, streamed home
ssh -o BatchMode=yes -o ConnectTimeout=15 "$BOX" \
  "docker exec todo sqlite3 /data/todo.db \".backup /tmp/b.db\" && docker exec todo cat /tmp/b.db && docker exec todo rm /tmp/b.db" \
  > "$DEST/todo-$STAMP.db"

# 3: caddy cert volume (small: certs + ACME account), as a tarball
ssh -o BatchMode=yes "$BOX" \
  "docker run --rm -v millwright_caddy-data:/data alpine tar -czf - -C /data ." \
  > "$DEST/caddy-data-$STAMP.tgz"

echo "backup ok: $DEST/todo-$STAMP.db + caddy-data-$STAMP.tgz"

# 4: practice (chg-003) — never a raw copy and never sqlite3: the running app makes it
"$(dirname "$0")/practice-backup.sh" "$DEST/practice"
