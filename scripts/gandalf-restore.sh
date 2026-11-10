#!/bin/bash
# millwright: put Gandalf's data on the box from a verified backup (chg-006). Used at the cutover (the
# Mac's final snapshot becomes the box's database), for the pre-seed (--assets-only), and in a rebuild
# (the newest nightly pair comes back). The gandalf service must be STOPPED or never started: the
# running app owns gandalf.db. The volume must exist (`docker compose up --no-start gandalf` makes it).
#
#   1. here: the snapshot's name, size and sha256 checked against its manifest; nothing sent otherwise;
#   2. image files: every file in ASSETS the box lacks is copied in (rsync --ignore-existing, never
#      deleting, never overwriting, no *.tmp), then owned by the app's user (uid 1000); then, unless
#      --assets-only, every image file the snapshot names must be on the box (non-empty), or nothing
#      is switched;
#   3. the database: streamed into a FRESH staging folder in the volume (/data/import/<id>), its sha256
#      checked on the box, then moved to /data/gandalf.db. An existing gandalf.db is refused unless
#      --replace, which first moves it and its -wal/-shm into /data/replaced-<id>/ (never deleted).
# The app applies its migrations at its next start: deliver the same or a newer Gandalf commit than
# the one that wrote the snapshot.
#
# Usage: scripts/gandalf-restore.sh [--replace] <dir>/gandalf-YYYYMMDD-HHMMSSZ.db
#        scripts/gandalf-restore.sh --assets-only [ASSETS]
#   ASSETS / GANDALF_ASSETS  local image-file folder to send (default: <dir>/assets, or with
#                            --assets-only /Users/andrew/Dropbox/andrew/secrets/millwright/backup/gandalf/assets)
#   GANDALF_SSH, GANDALF_BOX, GANDALF_VOLUME, GANDALF_ASSETS_DIR as in gandalf-backup.sh
#   GANDALF_COMPOSE          compose command on the box (default: docker compose --project-directory /srv/millwright)
set -euo pipefail

SSH="${GANDALF_SSH:-ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=4}"
BOX="${GANDALF_BOX:-root@187.124.159.132}"
VOLUME="${GANDALF_VOLUME:-millwright_gandalf-data}"
COMPOSE="${GANDALF_COMPOSE:-docker compose --project-directory /srv/millwright}"
box() { $SSH "$BOX" "$@"; }
run() { box $COMPOSE run --rm --no-deps -T gandalf "$@"; }

REPLACE=0; ASSETS_ONLY=0
case "${1:-}" in --replace) REPLACE=1; shift ;; --assets-only) ASSETS_ONLY=1; shift ;; esac

if [ "$ASSETS_ONLY" = 1 ]; then
  ASSETS="${1:-${GANDALF_ASSETS:-/Users/andrew/Dropbox/andrew/secrets/millwright/backup/gandalf/assets}}"
else
  SNAP_PATH="${1:?usage: gandalf-restore.sh [--replace] <dir>/gandalf-YYYYMMDD-HHMMSSZ.db | --assets-only [ASSETS]}"
  SNAP=$(basename "$SNAP_PATH")
  [[ "$SNAP" =~ ^gandalf-[0-9]{8}-[0-9]{6}Z\.db$ ]] || { echo "gandalf restore: unexpected name $SNAP" >&2; exit 1; }
  MAN_PATH="$SNAP_PATH.manifest.json"
  [ -f "$SNAP_PATH" ] && [ -f "$MAN_PATH" ] || { echo "gandalf restore: need $SNAP_PATH and $MAN_PATH" >&2; exit 1; }
  ASSETS="${GANDALF_ASSETS:-$(dirname "$SNAP_PATH")/assets}"
  SNAP_SHA=$(python3 - "$SNAP_PATH" "$MAN_PATH" <<'PY'
import hashlib, json, os, sys
s, mp = sys.argv[1], sys.argv[2]
b, m = open(s, "rb").read(), json.load(open(mp))
h = hashlib.sha256(b).hexdigest()
if m.get("file") != os.path.basename(s) or len(b) != m.get("bytes") or h != m.get("sha256") or m.get("integrity") != "ok":
    sys.exit("gandalf restore: %s does not match its manifest; nothing was sent" % s)
print(h)
PY
)
  [[ "$SNAP_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "gandalf restore: could not hash the snapshot; nothing was sent" >&2; exit 1; }
fi
[ -d "$ASSETS" ] || { echo "gandalf restore: no image-file folder at $ASSETS; nothing was sent" >&2; exit 1; }

# The service must be stopped or never started (the running app owns gandalf.db).
if [ -n "$(box $COMPOSE ps --status running -q gandalf)" ]; then
  echo "gandalf restore: the gandalf service is running; stop it first (docker compose stop gandalf). Nothing was changed." >&2
  exit 1
fi

ASSETS_DIR="${GANDALF_ASSETS_DIR:-$(box docker volume inspect -f '{{.Mountpoint}}' "$VOLUME")/assets}"
[[ "$ASSETS_DIR" =~ ^/[A-Za-z0-9_./-]+/assets$ ]] || { echo "gandalf restore: unexpected assets path $ASSETS_DIR" >&2; exit 1; }

# 2: image files, additive
box mkdir -p "$ASSETS_DIR"
rsync -a --ignore-existing --exclude '*.tmp' -e "$SSH" "$ASSETS/" "$BOX:$ASSETS_DIR/"
box chown -R 1000:1000 "$ASSETS_DIR"
echo "gandalf restore: image files sent ($ASSETS → $ASSETS_DIR)"
[ "$ASSETS_ONLY" = 1 ] && exit 0

# 2b: every image file the snapshot names is ON THE BOX (not only at home), before anything switches
LISTING=$(mktemp); trap 'rm -f "$LISTING"' EXIT
# Full paths, basenames taken here: the arguments pass through the box's shell, which would turn a
# `-printf '%f\n'` into `%fn` and run every name together.
box find "$ASSETS_DIR" -maxdepth 1 -type f -size +0c > "$LISTING"
python3 - "$SNAP_PATH" "$LISTING" <<'PY'
import re, sqlite3, sys
snap, listing = sys.argv[1], sys.argv[2]
key = re.compile(r"\b[0-9a-f]{64}(?:\.thumb)?\.[a-z0-9]{2,5}\b")
db = sqlite3.connect("file:%s?mode=ro" % snap, uri=True)
names = set()
try:
    for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"):
        q = t.replace('"', '""')
        for c in [r[1].replace('"', '""') for r in db.execute('PRAGMA table_info("%s")' % q)]:
            for (v,) in db.execute('SELECT "%s" FROM "%s" WHERE typeof("%s") = \'text\'' % (c, q, c)):
                names.update(key.findall(v))
finally:
    db.close()
on_box = {line.rsplit("/", 1)[-1] for line in open(listing).read().split()}
missing = sorted(names - on_box)
if missing:
    sys.exit("gandalf restore: %d image file(s) the snapshot names are not on the box, e.g. %s; nothing was switched" % (len(missing), ", ".join(missing[:5])))
print("gandalf restore: all %d image files the snapshot names are on the box" % len(names), file=sys.stderr)
PY

# 3: the database
ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STAGE="/data/import/$ID"
FINISHED=0
cleanup() { local rc=$?; rm -f "$LISTING"; [ "$FINISHED" = 1 ] || [ "$rc" != 0 ] || rc=1; if [ "$FINISHED" = 0 ]; then run rm -rf /data/import >/dev/null 2>&1 || true; echo "gandalf restore: FAILED (exit $rc); gandalf.db was not switched" >&2; fi; exit $rc; }
trap cleanup EXIT
run rm -rf /data/import
run mkdir -p "$STAGE"
run dd "of=$STAGE/gandalf.db" status=none < "$SNAP_PATH"
GOT=$(run sha256sum "$STAGE/gandalf.db" | cut -c1-64)
[ "$GOT" = "$SNAP_SHA" ] || { echo "gandalf restore: sha256 on the box ($GOT) differs from the snapshot" >&2; exit 1; }
if run test -e /data/gandalf.db || run test -e /data/gandalf.db-wal; then
  [ "$REPLACE" = 1 ] || { echo "gandalf restore: the box already has a database; rerun with --replace to move it to /data/replaced-$ID/ first" >&2; exit 1; }
  run mkdir "/data/replaced-$ID"
  for f in gandalf.db gandalf.db-wal gandalf.db-shm; do
    if run test -e "/data/$f"; then run mv "/data/$f" "/data/replaced-$ID/$f"; fi
  done
fi
run mv -n "$STAGE/gandalf.db" /data/gandalf.db
run test -e /data/gandalf.db
run rm -rf /data/import
FINISHED=1
echo "gandalf restore ok: $SNAP (sha256 $SNAP_SHA) is the database gandalf opens on its next start"
