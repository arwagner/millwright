#!/bin/bash
# millwright: create the practice site's basic-auth env file (chg-003). Runs on the laptop.
#
# Usage: scripts/practice-auth.sh <user> [DIR]
#   DIR defaults to ~/Dropbox/andrew/secrets/millwright (the secrets source of truth; runbook step 6 copies
#   it to /srv/secrets/ on the box).
# Asks for the password twice without echo (or reads two lines from stdin when not a terminal), hashes it
# with Caddy's own bcrypt (`caddy hash-password`, fed on stdin: never an argument, so never in `ps`), and
# writes DIR/practice-auth.env (mode 600, refusing to overwrite):
#   PRACTICE_AUTH_USER=<user>
#   PRACTICE_AUTH_HASH='<bcrypt>'      ← single quotes are required: Compose mangles an unquoted bcrypt
#                                        hash whose salt starts with a letter ($2a$14$Abc… → "$2a$14").
# The password and the hash are never printed.
set -euo pipefail
USER_NAME="${1:?usage: practice-auth.sh <user> [DIR]}"
DIR="${2:-$HOME/Dropbox/andrew/secrets/millwright}"
OUT="$DIR/practice-auth.env"
[[ "$USER_NAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || { echo "practice-auth: user must be 1-64 letters, digits, . _ -" >&2; exit 64; }
[ -e "$OUT" ] && { echo "practice-auth: $OUT exists; move it aside first (nothing changed)" >&2; exit 1; }
if [ -t 0 ]; then
  read -r -s -p "Password for $USER_NAME: " P1; echo >&2
  read -r -s -p "Again: " P2; echo >&2
else
  IFS= read -r P1; IFS= read -r P2
fi
[ "$P1" = "$P2" ] || { echo "practice-auth: passwords differ (nothing written)" >&2; exit 1; }
[ "${#P1}" -ge 16 ] || { echo "practice-auth: use at least 16 characters (the site is on the internet; basic auth has no lockout)" >&2; exit 1; }
HASH=$(printf '%s\n%s\n' "$P1" "$P1" | docker run --rm -i caddy:2 caddy hash-password 2>/dev/null | tail -1)
unset P1 P2
[[ "$HASH" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]] || { echo "practice-auth: caddy did not return a bcrypt hash (nothing written)" >&2; exit 1; }
mkdir -p "$DIR"
umask 077
TMP=$(mktemp "$DIR/.practice-auth.env.XXXXXX")
printf "PRACTICE_AUTH_USER=%s\nPRACTICE_AUTH_HASH='%s'\n" "$USER_NAME" "$HASH" > "$TMP"
chmod 600 "$TMP"
mv -n "$TMP" "$OUT"
[ -e "$TMP" ] && { rm -f "$TMP"; echo "practice-auth: $OUT appeared meanwhile (nothing written)" >&2; exit 1; }
echo "practice-auth: wrote $OUT (user $USER_NAME, bcrypt hash, mode 600)"
