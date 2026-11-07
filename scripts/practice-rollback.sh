#!/bin/bash
# millwright: move the practice schedule back to the laptop (chg-003 rollback). Runs on the laptop.
#
# Which copy is authoritative is decided from the data, never from how far the cutover got:
#   - the server provably holds no history (see "EMPTY" below: whole-home inventory without opening any
#     database, no data/, no file but locks/notes and the laptop's own final pair, service never created,
#     no later server snapshot) → the laptop's retired home is authoritative: unretired as it was;
#   - no pointer (or an unreadable one) with ANY other evidence is ambiguous — history may be stranded, even
#     in a database selected under another name or outside the home → STOP; recover the pointer, rerun;
#   - the server's history equals the laptop's final backup (`compare-history` → same: imported, maybe
#     scanned, nothing practised) → the laptop is authoritative, as above;
#   - the server's history extends it (→ server_extends: Sessions/Reviews/settings made on the server)
#       → the server is authoritative: its stopped-service backup is imported into the laptop home
#         (never over a different pair) and restored there, then the home is unretired;
#   - diverged, or any other server state → STOP: nothing on the laptop changes; a human decides.
# Before any change, a record is written to <DEST>/rollback-<stamp>.json with the revisions in play
# (Millwright checkout, practice commit on the box, laptop practice checkout), the laptop's retirement note
# and whether the service was running; the outcome is added at the end. The server stays stopped.
#
# Usage: scripts/practice-rollback.sh [--laptop-repo DIR] [--laptop-home DIR] [DEST]
#   laptop repo default /Users/andrew/Dropbox/andrew/music/Exercises/practice (its CLI must include
#   retire/import-backup/compare-history); laptop home defaults to the repo; DEST as practice-backup.sh.
#   PRACTICE_BOX_EXEC / PRACTICE_COMPOSE as in practice-backup.sh; PRACTICE_APP_DIR (box) default /opt/practice/app.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=/Users/andrew/Dropbox/andrew/music/Exercises/practice; LHOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --laptop-repo) REPO="$2"; shift 2 ;;
    --laptop-home) LHOME="$2"; shift 2 ;;
    *) break ;;
  esac
done
LHOME="${LHOME:-$REPO}"
DEST="${1:-/Users/andrew/Dropbox/andrew/secrets/millwright/backup/practice}"
BOX_EXEC="${PRACTICE_BOX_EXEC-ssh -o BatchMode=yes -o ConnectTimeout=15 root@187.124.159.132}"
COMPOSE="${PRACTICE_COMPOSE:-docker compose --project-directory /srv/millwright}"
APP_DIR="${PRACTICE_APP_DIR:-/opt/practice/app}"
box() { $BOX_EXEC "$@"; }
pcli() { node "$REPO/src/cli.js" "$@" --home "$LHOME"; }
mkdir -p "$DEST"
REC="$DEST/rollback-$(date -u +%Y%m%dT%H%M%SZ).json"
note() { python3 - "$REC" "$@" <<'PY'
import json, os, sys
rec, kv = sys.argv[1], sys.argv[2:]
d = json.load(open(rec)) if os.path.exists(rec) else {}
for i in range(0, len(kv), 2):
    k, v = kv[i], kv[i + 1]
    try: v = json.loads(v)
    except Exception: pass
    d[k] = v
json.dump(d, open(rec + ".tmp", "w"), indent=2); os.replace(rec + ".tmp", rec)
PY
}

# 0: the laptop must be the retired side (otherwise there is nothing to roll back)
MARKER="$LHOME/data/retired.json"
[ -f "$MARKER" ] || { echo "practice rollback: $LHOME is not retired; nothing to roll back" >&2; exit 1; }
FINAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("final_backup") or "")' "$MARKER")
[[ "$FINAL" =~ ^practice-[0-9]{8}-[0-9]{6}Z(-[0-9]+)?\.sqlite$ ]] && [ -f "$LHOME/backups/$FINAL" ] || { echo "practice rollback: the retirement note names no final backup present in $LHOME/backups; stop" >&2; exit 1; }

# 1: record before any change
RUNNING=0; [ -n "$(box $COMPOSE ps --status running -q practice)" ] && RUNNING=1
note started_at "\"$(date -u +%FT%TZ)\"" \
  millwright_rev "\"$(git -C "$HERE/.." rev-parse HEAD 2>/dev/null || echo unknown)\"" \
  box_practice_commit "\"$(box cat "$APP_DIR/DEPLOYED_COMMIT" 2>/dev/null | head -1 || echo unknown)\"" \
  laptop_repo_rev "\"$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)\"" \
  laptop_repo_dirty "$( [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null)" ] && echo true || echo false)" \
  laptop_home "\"$LHOME\"" retired_note "$(cat "$MARKER")" server_running_before "$RUNNING"
echo "practice rollback: record $REC"

# 2: freeze the server
if [ "$RUNNING" = 1 ]; then box $COMPOSE stop practice; note server_stopped true; fi

# 3: what the server holds, read without opening any database (`practice inventory`, service stopped)
stop() { note outcome '"stopped"' reason "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")"
  echo "practice rollback: STOP — $1. Nothing on the laptop changed; it stays retired; the server stays stopped with its files as they are." >&2
  [ -n "${2:-}" ] && echo "$2" >&2; exit 1; }
set +e; INV=$(box $COMPOSE run --rm --no-deps -T practice node src/cli.js inventory 2>&1); IRC=$?; set -e
[ $IRC = 0 ] || stop "the server's home could not be inventoried" "$INV"
note server_inventory "$INV"
# A server with no pointer is EMPTY only when every piece of evidence agrees (otherwise: STOP, laptop stays
# retired). A valid database may be selected under any name or path (`practice use-db`), so absence is never
# inferred from file names:
#   - the inventory walked the whole home completely (no unreadable entry), with no symlink or special entry;
#   - there is no data/ folder (every first run, selection or restore creates one, even for a database kept
#     outside the home);
#   - the only files are the ownership lock/note files and, optionally, the laptop's own final pair
#     byte-identical (an import that published but never switched);
#   - the practice service container was never created on the box (`compose ps -a`: nothing ever served);
#   - no server snapshot made after the retirement exists in this laptop's backup folder.
LSHA=$(shasum -a 256 "$LHOME/backups/$FINAL" | cut -d' ' -f1); LMSHA=$(shasum -a 256 "$LHOME/backups/${FINAL%.sqlite}.manifest.json" | cut -d' ' -f1)
EVER=$(box $COMPOSE ps -a -q practice 2>&1) || stop "could not ask the box whether the practice service ever ran" "$EVER"
note server_service_created "$( [ -n "$EVER" ] && echo true || echo false )"
SHAPE=$(python3 - "$INV" "$FINAL" "$LSHA" "$LMSHA" "$EVER" "$DEST" "$(cat "$MARKER")" <<'PY'
import glob, json, os, sys
inv, final, lsha, lmsha, ever, dest, note = json.loads(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5].strip(), sys.argv[6], json.loads(sys.argv[7])
ptr = inv.get("pointer")
if isinstance(ptr, dict) and "invalid" in ptr: print("ambiguous: the server's pointer is unreadable (%s)" % ptr["invalid"]); sys.exit()
if ptr: print("live"); sys.exit()
why = []
if inv.get("format") != "practice-inventory/2": why.append("the inventory is not a full-home inventory")
if not inv.get("complete") or inv.get("unreadable"): why.append("parts of the home could not be read: " + ", ".join("%s (%s)" % (u["path"], u["reason"]) for u in inv.get("unreadable", [])))
if inv.get("symlinks"): why.append("symlinks: " + ", ".join("%s -> %s" % (l["path"], l["to"]) for l in inv["symlinks"]))
if inv.get("other"): why.append("special entries: " + ", ".join(o["path"] for o in inv["other"]))
if inv.get("has_data_dir"): why.append("data/ exists (a database was created, selected or restored there at some point)")
locks = {".practice-owner.lock", "backups/.practice-owner.lock"}
notes = {".practice-owner.json", "backups/.practice-owner.json"}
own = {"backups/" + final: lsha, "backups/" + final[:-len(".sqlite")] + ".manifest.json": lmsha}
for o in inv.get("owned", []):
    if o["path"] not in locks: why.append("held file %s" % o["path"])
for f in inv.get("files", []):
    if f["path"] in notes and not f["sqlite"]: continue
    if f["path"] in locks: continue
    if own.get(f["path"]) == f["sha256"]: continue
    why.append("%s%s (%s bytes)" % (f["path"], " [SQLite database]" if f["sqlite"] else "", f["bytes"]))
if ever: why.append("the practice service container exists on the box (it has run)")
later = []
for m in glob.glob(os.path.join(dest, "practice-*.manifest.json")):
    try:
        c = json.load(open(m)).get("created_at") or ""
        if note.get("at") and c > note["at"]: later.append(os.path.basename(m))
    except Exception: later.append(os.path.basename(m) + " (unreadable)")
if later: why.append("server snapshots made after the retirement exist in %s: %s" % (dest, ", ".join(sorted(later))))
if why: print("ambiguous: no pointer, and the server cannot be proven empty: " + "; ".join(why)); sys.exit()
print("empty-own-final" if any(f["path"] in own for f in inv.get("files", [])) else "empty")
PY
)
case "$SHAPE" in
  empty) AUTH=laptop; WHY="the server is provably empty: no pointer, no data/, no other file anywhere in its home, the service never ran, no later server snapshot (the import never ran or never published)" ;;
  empty-own-final) AUTH=laptop; WHY="the server is provably empty apart from the laptop's own final pair, byte-identical, never switched to: no pointer, no data/, the service never ran, no later server snapshot" ;;
  live)
    set +e; OUT=$("$HERE/practice-backup.sh" --stopped "$DEST" 2>&1); RC=$?; set -e
    [ $RC = 0 ] || stop "the server has a live database but its backup failed" "$OUT"
    SPATH=$(sed -n 's/^practice backup ok: \(.*\.sqlite\) + .*$/\1/p' <<<"$OUT" | tail -1)
    [ -f "$SPATH" ] || stop "no server snapshot found after its backup" "$OUT"
    note server_backup "\"$SPATH\""
    set +e; CMP=$(pcli compare-history "$LHOME/backups/$FINAL" "$SPATH" 2>&1); CRC=$?; set -e
    VERDICT=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["verdict"])' "$CMP" 2>/dev/null || echo error)
    [ "$VERDICT" = error ] || note comparison "$CMP"
    case "$VERDICT" in
      same) AUTH=laptop; WHY="the server holds exactly the laptop's final history and music identity (nothing practised there)" ;;
      server_extends) AUTH=server; WHY="the server extends the laptop's history: $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["added"])' "$CMP")" ;;
      diverged) stop "the laptop's final backup and the server's history diverged" "$CMP" ;;
      *) stop "the histories could not be compared" "$CMP" ;;
    esac ;;
  *) stop "${SHAPE}. Recover and verify the server's history first (on the box: find the database the service last used and select it with practice use-db <file>, so the server has a pointer again), then run this again; if the server truly never held history, a human decides and records why" ;;
esac
note authority "\"$AUTH\"" why "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$WHY")"
echo "practice rollback: authoritative copy = $AUTH ($WHY)"

# 4: apply on the laptop
SAVED=$(mktemp); cp "$MARKER" "$SAVED"
reretire() { mkdir -p "$(dirname "$MARKER")"; cp "$SAVED" "$MARKER"; echo "practice rollback: FAILED; the laptop home was re-retired as before" >&2; }
if [ "$AUTH" = server ]; then
  NAME=$(basename "$SPATH"); BASE="${NAME%.sqlite}"; ST=$(mktemp -d)
  cp "$SPATH" "$ST/"; cp "$(dirname "$SPATH")/$BASE.manifest.json" "$ST/"
  S1=$(shasum -a 256 "$ST/$NAME" | cut -d' ' -f1); S2=$(shasum -a 256 "$ST/$BASE.manifest.json" | cut -d' ' -f1)
  pcli import-backup "$NAME" --from "$ST" --sha256 "$S1" --manifest-sha256 "$S2" > /dev/null   # still retired: a conflict stops here
  pcli unretire > /dev/null
  pcli restore "$NAME" > /dev/null || { reretire; exit 1; }
  note restored_on_laptop "\"$NAME\""
else
  pcli unretire > /dev/null
fi
# 5: verify what the laptop now opens
STATUS=$(pcli status) || { reretire; exit 1; }
WANT="$LHOME/backups/$FINAL"; [ "$AUTH" = server ] && WANT="$SPATH"
python3 - "$STATUS" "${WANT%.sqlite}.manifest.json" <<'PY' || { reretire; exit 1; }
import json, sys
s, m = json.loads(sys.argv[1]), json.load(open(sys.argv[2]))["table_counts"]
got = {"exercise": s["exercises"], "review": s["reviews"]}
want = {"exercise": m["exercise"], "review": m["review"]}
if got != want: sys.exit("laptop opens %s, expected %s" % (got, want))
print("practice rollback: laptop opens", got, file=sys.stderr)
PY
rm -f "$SAVED"
note outcome '"done"' finished_at "\"$(date -u +%FT%TZ)\""
echo "practice rollback ok: authority $AUTH; the laptop home is in use again; the server stays stopped (record $REC)"
