#!/bin/bash
# millwright: put a verified practice backup pair into the box's practice volume and restore it (chg-003).
# Used at the cutover (the laptop's final backup becomes the server's database) and in a rebuild (the
# latest nightly pair comes back). The practice service must be STOPPED: the running server owns its home,
# and this writes into it.
#
# Usage: scripts/practice-restore.sh <dir>/<practice-YYYYMMDD-HHMMSSZ>.sqlite
#   The matching .manifest.json must sit beside it. Here: name, size and sha256 checked against the
#   manifest, and both files hashed. On the box: both are streamed into a FRESH per-attempt staging folder
#   (/var/lib/practice/import/<id>, never backups/), then the app's own `practice import-backup` checks the
#   staged bytes against these hashes and the manifest, publishes the pair into backups/ without ever
#   overwriting (a same-named pair is reused only if BOTH files are byte-identical; any other collision is
#   refused before anything switches), runs the app's `restore` (sha256, integrity, foreign keys, schema,
#   table counts, copy to data/restored-<stamp>/, pointer switch) and removes the staging folder.
#   Finally `practice status` prints what the server will open. The previous database, if any, is untouched.
#   PRACTICE_BOX_EXEC / PRACTICE_COMPOSE as in practice-backup.sh. Every argument passed to the box is a fixed
#   token, a validated name or a hex hash, so the remote shell sees nothing to interpret.
set -euo pipefail

SNAP_PATH="${1:?usage: practice-restore.sh <dir>/practice-YYYYMMDD-HHMMSSZ.sqlite}"
BOX_EXEC="${PRACTICE_BOX_EXEC-ssh -o BatchMode=yes -o ConnectTimeout=15 root@187.124.159.132}"
COMPOSE="${PRACTICE_COMPOSE:-docker compose --project-directory /srv/millwright}"
IMPORT_ROOT=/var/lib/practice/import
box() { $BOX_EXEC "$@"; }
run() { box $COMPOSE run --rm --no-deps -T practice "$@"; }

SNAP=$(basename "$SNAP_PATH")
[[ "$SNAP" =~ ^practice-[0-9]{8}-[0-9]{6}Z(-[0-9]+)?\.sqlite$ ]] || { echo "practice restore: unexpected name $SNAP" >&2; exit 1; }
BASE="${SNAP%.sqlite}"
MAN_PATH="$(dirname "$SNAP_PATH")/$BASE.manifest.json"
[ -f "$SNAP_PATH" ] && [ -f "$MAN_PATH" ] || { echo "practice restore: need $SNAP_PATH and $MAN_PATH" >&2; exit 1; }

read -r SNAP_SHA MAN_SHA < <(python3 - "$SNAP_PATH" "$MAN_PATH" <<'PY'
import hashlib, json, os, sys
s, mp = sys.argv[1], sys.argv[2]
sb, mb = open(s, "rb").read(), open(mp, "rb").read()
m = json.loads(mb)
sh = hashlib.sha256(sb).hexdigest()
if m.get("snapshot") != os.path.basename(s) or len(sb) != m.get("bytes") or sh != m.get("sha256"):
    sys.exit("practice restore: %s does not match its manifest; nothing was sent" % s)
print(sh, hashlib.sha256(mb).hexdigest())
PY
)
[[ "$SNAP_SHA" =~ ^[0-9a-f]{64}$ && "$MAN_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "practice restore: could not hash the pair; nothing was sent" >&2; exit 1; }

# The service must be stopped (its server would own the home; a one-off command would be refused anyway).
if [ -n "$(box $COMPOSE ps --status running -q practice)" ]; then
  echo "practice restore: the practice service is running; stop it first (docker compose stop practice). Nothing was changed." >&2
  exit 1
fi

ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STAGE="$IMPORT_ROOT/$ID"
IMPORTED=0; FINISHED=0
# Any exit before the last line is a failure, whatever $? says (bash 3.2 can report 0 for an aborted script).
cleanup() { local rc=$?; [ "$FINISHED" = 1 ] || [ "$rc" != 0 ] || rc=1; if [ "$IMPORTED" = 0 ]; then run rm -rf "$STAGE" >/dev/null 2>&1 || true; [ $rc = 0 ] || echo "practice restore: FAILED (exit $rc); nothing was switched" >&2; fi; exit $rc; }
trap cleanup EXIT
run rm -rf "$IMPORT_ROOT"          # earlier interrupted attempts (only this script uses import/)
run mkdir -p "$STAGE"
run dd "of=$STAGE/$SNAP" status=none < "$SNAP_PATH"
run dd "of=$STAGE/$BASE.manifest.json" status=none < "$MAN_PATH"
run node src/cli.js import-backup "$SNAP" --from "$STAGE" --sha256 "$SNAP_SHA" --manifest-sha256 "$MAN_SHA" --restore
IMPORTED=1
run node src/cli.js status
FINISHED=1
echo "practice restore ok: $SNAP (sha256 $SNAP_SHA) is the database the practice service opens on its next start"
