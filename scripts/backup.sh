#!/bin/bash
# millwright nightly backup — runs on the laptop under launchd.
# 1. Atomic SQLite snapshot of todo.db inside the todo container (todo runs
#    WAL mode; a raw cp/rsync of a live db can tear — `.backup` cannot).
# 2. Copy the snapshot to Dropbox.
# 3. Copy the Caddy certificate volume to Dropbox (keeps rebuild tests under
#    Let's Encrypt's five-duplicate-certs-per-week limit).
# 4. (chg-003) The practice app's own verified snapshot, copied home and verified
#    again (scripts/practice-backup.sh).
# 5. (chg-006) Gandalf: the app's own online snapshot, verified again at home, plus
#    new image files copied additively (scripts/gandalf-backup.sh). It skips with a
#    message while Gandalf holds no data on the box.
# Steps 4 and 5 run in that order after todo and caddy have landed, and both always
# run: either failing exits non-zero, and a failed step publishes nothing.
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

# 4 + 5: practice (chg-003) then gandalf (chg-006) — never a raw copy of a live database:
# each running app makes its own snapshot. Both run whatever the other does.
rc=0
"$(dirname "$0")/practice-backup.sh" "$DEST/practice" || rc=1
"$(dirname "$0")/gandalf-backup.sh" "$DEST/gandalf" || rc=1
exit $rc
