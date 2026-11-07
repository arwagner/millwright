#!/bin/bash
# millwright: practice backup (chg-003). Called nightly by backup.sh; also used at cutover/rollback.
#
# The practice server owns its SQLite database for its whole life, so nothing outside it can take a
# consistent snapshot: `sqlite3 .backup` is refused by its lock and a raw copy of a live file is not a
# backup. Instead:
#   1. ask the RUNNING server for its normal verified backup (VACUUM INTO, integrity + foreign-key check,
#      sha256, manifest last) over its maintenance socket — `docker exec practice node src/admin.js backup`;
#      with --stopped (service stopped: cutover, rollback), a one-off `cli.js backup` owns the home instead;
#   2. copy that finished, immutable snapshot and its manifest home (never the live file);
#   3. verify again here: size + sha256 against the manifest, integrity_check, foreign_key_check, schema
#      version, and every table count against the manifest;
#   4. publish into DEST, snapshot first and manifest last, never overwriting an existing name.
# Exit 0: DEST/<name>.sqlite + DEST/<name>.manifest.json published (printed on the last line).
# Exit != 0: nothing published (the staging folder is removed); earlier backups are never touched.
#
# Usage: scripts/practice-backup.sh [--stopped] [DEST]
#   DEST                default /Users/andrew/Dropbox/andrew/secrets/millwright/backup/practice
#   PRACTICE_BOX_EXEC   prefix that runs a command on the box (default: ssh … root@187.124.159.132);
#                       a rehearsal sets it to "" to run docker locally against an isolated target.
#   PRACTICE_COMPOSE    compose command on the box (default: docker compose --project-directory /srv/millwright)
#   PRACTICE_CONTAINER  running container name (default: practice)
# No credential is involved: reaching the socket takes a shell on the box (root over SSH).
set -euo pipefail

STOPPED=0
if [ "${1:-}" = "--stopped" ]; then STOPPED=1; shift; fi
DEST="${1:-/Users/andrew/Dropbox/andrew/secrets/millwright/backup/practice}"
BOX_EXEC="${PRACTICE_BOX_EXEC-ssh -o BatchMode=yes -o ConnectTimeout=15 root@187.124.159.132}"
COMPOSE="${PRACTICE_COMPOSE:-docker compose --project-directory /srv/millwright}"
CONTAINER="${PRACTICE_CONTAINER:-practice}"
APP_BACKUPS=/var/lib/practice/backups

# Word splitting of BOX_EXEC / COMPOSE is intended (a command prefix). Every argument passed through is a
# fixed token or a name validated below, so nothing from the box is ever interpreted as shell on the box.
box() { $BOX_EXEC "$@"; }
in_app() { if [ "$STOPPED" = 1 ]; then box $COMPOSE run --rm --no-deps -T practice "$@"; else box docker exec "$CONTAINER" "$@"; fi; }

mkdir -p "$DEST"
STAGE=$(mktemp -d "$DEST/.staging.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# 1: the app's own verified backup
if [ "$STOPPED" = 1 ]; then
  box $COMPOSE run --rm --no-deps -T practice node src/cli.js backup > "$STAGE/answer.json"
else
  box docker exec "$CONTAINER" node src/admin.js backup --kind nightly > "$STAGE/answer.json"
fi
SNAP=$(python3 - "$STAGE/answer.json" <<'PY'
import json, os, re, sys
a = json.load(open(sys.argv[1]))
if a.get("ok") is False:
    sys.exit("server refused: %s" % json.dumps(a.get("error")))
name = os.path.basename(a.get("snapshot") or "")
if not re.fullmatch(r"practice-\d{8}-\d{6}Z(-\d+)?\.sqlite", name):
    sys.exit("unexpected snapshot name %r" % name)
print(name)
PY
)
BASE="${SNAP%.sqlite}"
MAN="$BASE.manifest.json"
if [ -e "$DEST/$SNAP" ] || [ -e "$DEST/$MAN" ]; then echo "practice backup: $DEST already has $BASE; refusing to overwrite" >&2; exit 1; fi

# 2: copy the finished pair (not the live database)
in_app cat "$APP_BACKUPS/$SNAP" > "$STAGE/$SNAP"
in_app cat "$APP_BACKUPS/$MAN" > "$STAGE/$MAN"

# 3: verify here, from the bytes we hold
python3 - "$STAGE/$SNAP" "$STAGE/$MAN" <<'PY'
import hashlib, json, os, sqlite3, sys
snap, man = sys.argv[1], sys.argv[2]
m = json.load(open(man))
fail = []
if m.get("format") != "piano-practice-backup/1": fail.append("manifest format %r" % m.get("format"))
if m.get("snapshot") != os.path.basename(snap): fail.append("manifest names %r" % m.get("snapshot"))
if os.path.getsize(snap) != m.get("bytes"): fail.append("size %d != manifest %r" % (os.path.getsize(snap), m.get("bytes")))
h = hashlib.sha256(open(snap, "rb").read()).hexdigest()
if h != m.get("sha256"): fail.append("sha256 mismatch")
if not fail:
    db = sqlite3.connect("file:%s?mode=ro" % snap, uri=True)
    try:
        ic = [r[0] for r in db.execute("PRAGMA integrity_check")]
        if ic != ["ok"]: fail.append("integrity_check: %s" % "; ".join(ic[:5]))
        fk = db.execute("PRAGMA foreign_key_check").fetchall()
        if fk: fail.append("foreign_key_check: %d violation(s)" % len(fk))
        uv = db.execute("PRAGMA user_version").fetchone()[0]
        if uv != m.get("schema_version"): fail.append("schema %r != manifest %r" % (uv, m.get("schema_version")))
        for t, n in sorted((m.get("table_counts") or {}).items()):
            got = db.execute('SELECT count(*) FROM "%s"' % t.replace('"', '""')).fetchone()[0]
            if got != n: fail.append("table %s has %d rows, manifest says %d" % (t, got, n))
        if not m.get("table_counts"): fail.append("manifest has no table_counts")
    finally:
        db.close()
if fail:
    sys.exit("practice backup verification FAILED: " + "; ".join(fail))
c = m["table_counts"]
print("verified %s: %d bytes, exercises %d, reviews %d, attempts %d, sessions %d" % (m["snapshot"], m["bytes"], c.get("exercise", -1), c.get("review", -1), c.get("attempt", -1), c.get("session", -1)), file=sys.stderr)
PY

# 4: publish, manifest last (a listing never sees a manifest without its snapshot)
mv -n "$STAGE/$SNAP" "$DEST/$SNAP"
if [ -e "$STAGE/$SNAP" ]; then echo "practice backup: $DEST/$SNAP appeared meanwhile; nothing published" >&2; exit 1; fi
mv -n "$STAGE/$MAN" "$DEST/$MAN"
if [ -e "$STAGE/$MAN" ]; then echo "practice backup: could not publish $MAN (snapshot left unpublished-without-manifest)" >&2; exit 1; fi
echo "practice backup ok: $DEST/$SNAP + $MAN"
