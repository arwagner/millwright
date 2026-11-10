#!/bin/bash
# millwright: Gandalf backup (chg-006). Called nightly by backup.sh; also by hand before risky steps.
#
# Gandalf keeps one SQLite database (gandalf.db, WAL) and content-addressed image files (assets/, each
# named by its content's sha256, written once by write-then-rename) in the gandalf-data volume.
#   1. ask the RUNNING app for an online snapshot: `docker exec gandalf node src/server/cli.ts backup
#      /data/backups/<name>.db` (SQLite online backup, integrity-checked, manifest beside it, never
#      overwrites, runs as the image's node user);
#   2. copy that finished snapshot and its manifest home (never the live file);
#   3. verify again here: size + sha256 against the manifest, integrity_check, migration count and every
#      table count against the manifest;
#   4. copy NEW image files home (rsync --ignore-existing; nothing is ever deleted at home, so older
#      snapshots keep every file they name);
#   5. check that every image file name the snapshot mentions exists at home (non-empty);
#   6. publish into DEST, snapshot first and manifest last, never overwriting an existing name;
#   7. keep the 7 newest snapshots on the box.
# Exit 0: DEST/<name>.db + DEST/<name>.db.manifest.json published (printed on the last line), or Gandalf
#   holds no data on the box yet (no gandalf-data volume, or no gandalf.db in it: before the cutover):
#   says so, publishes nothing.
# Exit != 0: no snapshot published. Image files copied in step 4 stay (additive and harmless). This
#   includes: the box unreachable; gandalf.db present but the container not running (e.g. after a
#   rollback to the Mac), which must never pass silently.
#
# Usage: scripts/gandalf-backup.sh [DEST]
#   DEST                default /Users/andrew/Dropbox/andrew/secrets/millwright/backup/gandalf
#   GANDALF_SSH         ssh command (default: ssh -o BatchMode=yes -o ConnectTimeout=15
#                       -o ServerAliveInterval=30 -o ServerAliveCountMax=4, so a stalled link ends)
#   GANDALF_BOX         ssh target (default root@187.124.159.132); a rehearsal points both at a local box
#   GANDALF_VOLUME      the data volume (default millwright_gandalf-data)
#   GANDALF_ASSETS_DIR  assets/ path on the box (default: the volume's mountpoint + /assets)
#   GANDALF_CONTAINER   container name (default gandalf)
# No credential is involved: reaching the app takes a shell on the box (root over SSH).
set -euo pipefail

DEST="${1:-/Users/andrew/Dropbox/andrew/secrets/millwright/backup/gandalf}"
SSH="${GANDALF_SSH:-ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=4}"
BOX="${GANDALF_BOX:-root@187.124.159.132}"
VOLUME="${GANDALF_VOLUME:-millwright_gandalf-data}"
CONTAINER="${GANDALF_CONTAINER:-gandalf}"
KEEP_ON_BOX=7
NAME_RE='^gandalf-[0-9]{8}-[0-9]{6}Z\.db$'
# Word splitting of SSH is intended (a command prefix). Every argument passed to the box is a fixed
# token or a name validated here, so nothing from the box is interpreted as shell on the box.
box() { $SSH "$BOX" "$@"; }

# 0: is there anything to back up? Reachability first, so an ssh failure is never read as "not deployed".
box true || { echo "gandalf backup: FAILED: cannot reach the box; nothing published" >&2; exit 1; }
# Only a clear "absent" skips: a listing or a check that fails (a daemon error, a dropped link) fails the step.
VOLS=$(box docker volume ls -q) || { echo "gandalf backup: FAILED: cannot list the box's volumes; nothing published" >&2; exit 1; }
if ! grep -Fxq -- "$VOLUME" <<< "$VOLS"; then
  echo "gandalf backup: no $VOLUME volume on the box (Gandalf not delivered yet); nothing to back up"; exit 0
fi
MP=$(box docker volume inspect -f '{{.Mountpoint}}' "$VOLUME") || { echo "gandalf backup: FAILED: cannot inspect $VOLUME; nothing published" >&2; exit 1; }
[[ "$MP" =~ ^/[A-Za-z0-9_./-]+$ ]] || { echo "gandalf backup: unexpected volume path $MP" >&2; exit 1; }
rc=0; box test -e "$MP/gandalf.db" || rc=$?
case "$rc" in
  0) ;;
  1) echo "gandalf backup: $VOLUME holds no gandalf.db yet (before the cutover); nothing to back up"; exit 0 ;;
  *) echo "gandalf backup: FAILED: checking for gandalf.db failed (exit $rc); nothing published" >&2; exit 1 ;;
esac
STATE=$(box docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo missing)
[ "$STATE" = running ] || { echo "gandalf backup: FAILED: gandalf.db exists on the box but the gandalf container is $STATE; nothing published" >&2; exit 1; }

ASSETS_DIR="${GANDALF_ASSETS_DIR:-$MP/assets}"
[[ "$ASSETS_DIR" =~ ^/[A-Za-z0-9_./-]+/assets$ ]] || { echo "gandalf backup: unexpected assets path $ASSETS_DIR" >&2; exit 1; }

mkdir -p "$DEST/assets"
STAGE=$(mktemp -d "$DEST/.staging.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# 1: the app's own online snapshot
SNAP="gandalf-$(date -u +%Y%m%d-%H%M%SZ).db"
MAN="$SNAP.manifest.json"
if [ -e "$DEST/$SNAP" ] || [ -e "$DEST/$MAN" ]; then echo "gandalf backup: $DEST already has $SNAP; refusing to overwrite" >&2; exit 1; fi
box docker exec "$CONTAINER" mkdir -p /data/backups
box docker exec "$CONTAINER" node src/server/cli.ts backup "/data/backups/$SNAP" >&2

# 2: copy the finished pair (not the live database)
box docker exec "$CONTAINER" cat "/data/backups/$SNAP" > "$STAGE/$SNAP"
box docker exec "$CONTAINER" cat "/data/backups/$MAN" > "$STAGE/$MAN"

# 3: verify here, from the bytes we hold
python3 - "$STAGE/$SNAP" "$STAGE/$MAN" <<'PY'
import hashlib, json, os, sqlite3, sys
snap, man = sys.argv[1], sys.argv[2]
m = json.load(open(man))
fail = []
if m.get("file") != os.path.basename(snap): fail.append("manifest names %r" % m.get("file"))
if os.path.getsize(snap) != m.get("bytes"): fail.append("size %d != manifest %r" % (os.path.getsize(snap), m.get("bytes")))
if hashlib.sha256(open(snap, "rb").read()).hexdigest() != m.get("sha256"): fail.append("sha256 mismatch")
if m.get("integrity") != "ok": fail.append("manifest integrity %r" % m.get("integrity"))
if not fail:
    db = sqlite3.connect("file:%s?mode=ro" % snap, uri=True)
    try:
        ic = [r[0] for r in db.execute("PRAGMA integrity_check")]
        if ic != ["ok"]: fail.append("integrity_check: %s" % "; ".join(ic[:5]))
        n = db.execute("SELECT count(*) FROM __drizzle_migrations").fetchone()[0]
        if n != m.get("migrations"): fail.append("migrations %d != manifest %r" % (n, m.get("migrations")))
        tables = m.get("tables") or {}
        if not tables: fail.append("manifest has no table counts")
        for t, want in sorted(tables.items()):
            got = db.execute('SELECT count(*) FROM "%s"' % t.replace('"', '""')).fetchone()[0]
            if got != want: fail.append("table %s has %d rows, manifest says %d" % (t, got, want))
    finally:
        db.close()
if fail:
    sys.exit("gandalf backup verification FAILED: " + "; ".join(fail))
print("verified %s: %d bytes, %d tables, %d migrations" % (m["file"], m["bytes"], len(m["tables"]), m["migrations"]), file=sys.stderr)
PY

# 4: new image files home (additive; names are content hashes, so an existing name never changes).
# In-flight writes (<key>.<pid>.<ms>.tmp, assets.ts put) are skipped. A file the app removes while
# rsync runs is "vanished" (exit 24): harmless here, because step 5 decides what must be present.
rc=0; rsync -a --ignore-existing --exclude '*.tmp' -e "$SSH" "$BOX:$ASSETS_DIR/" "$DEST/assets/" || rc=$?
[ "$rc" = 0 ] || [ "$rc" = 24 ] || { echo "gandalf backup: FAILED: rsync exit $rc; nothing published" >&2; exit 1; }

# 5: every image file the snapshot names is here
python3 - "$STAGE/$SNAP" "$DEST/assets" <<'PY'
import os, re, sqlite3, sys
snap, assets = sys.argv[1], sys.argv[2]
key = re.compile(r"\b[0-9a-f]{64}(?:\.thumb)?\.[a-z0-9]{2,5}\b")
db = sqlite3.connect("file:%s?mode=ro" % snap, uri=True)
names = set()
try:
    for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"):
        q = t.replace('"', '""')
        for (c,) in [(r[1],) for r in db.execute('PRAGMA table_info("%s")' % q)]:
            for (v,) in db.execute('SELECT "%s" FROM "%s" WHERE typeof("%s") = \'text\'' % (c.replace('"', '""'), q, c.replace('"', '""'))):
                names.update(key.findall(v))
finally:
    db.close()
missing = [n for n in sorted(names) if not (os.path.isfile(os.path.join(assets, n)) and os.path.getsize(os.path.join(assets, n)) > 0)]
if missing:
    sys.exit("gandalf backup: %d image file(s) named by the snapshot are missing at home, e.g. %s" % (len(missing), ", ".join(missing[:5])))
print("assets: all %d image files the snapshot names are at home" % len(names), file=sys.stderr)
PY

# 6: publish, manifest last (a listing never sees a manifest without its snapshot)
mv -n "$STAGE/$SNAP" "$DEST/$SNAP"
if [ -e "$STAGE/$SNAP" ]; then echo "gandalf backup: $DEST/$SNAP appeared meanwhile; nothing published" >&2; exit 1; fi
mv -n "$STAGE/$MAN" "$DEST/$MAN"
if [ -e "$STAGE/$MAN" ]; then echo "gandalf backup: could not publish $MAN (snapshot left without its manifest)" >&2; exit 1; fi

# 7: keep the newest KEEP_ON_BOX snapshots on the box (names validated before any rm)
# The pair is already published, so a failed listing only skips this night's pruning, and says so.
OLD=""
if LISTED=$(box docker exec "$CONTAINER" ls -1 /data/backups); then
  OLD=$(printf '%s\n' "$LISTED" | grep -E "$NAME_RE" | sort -r | tail -n +"$((KEEP_ON_BOX + 1))" || true)
else
  echo "gandalf backup: WARNING: could not list the box's snapshots; nothing pruned this time" >&2
fi
for old in $OLD; do
  [[ "$old" =~ $NAME_RE ]] || continue
  box docker exec "$CONTAINER" rm -f "/data/backups/$old" "/data/backups/$old.manifest.json"
done

echo "gandalf backup ok: $DEST/$SNAP + $MAN"
