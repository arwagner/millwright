#!/bin/bash
# millwright: create the practice site's auth env file (chg-003, chg-004). Runs on the laptop.
#
# Usage: scripts/practice-auth.sh <user> [DIR]                 new file: user, bcrypt hash, session secret
#        scripts/practice-auth.sh --session-secret [DIR]        add the session secret to an existing file
#        scripts/practice-auth.sh --rotate-session-secret [DIR] replace it: signs out EVERY device
#   DIR defaults to ~/Dropbox/andrew/secrets/millwright (the secrets source of truth; runbook step 6 copies
#   it to /srv/secrets/ on the box).
# <user>: asks for the password twice without echo (or reads two lines from stdin when not a terminal),
# hashes it with Caddy's own bcrypt (`caddy hash-password`, fed on stdin: never an argument, so never in
# `ps`), and writes DIR/practice-auth.env (mode 600, refusing to overwrite):
#   PRACTICE_AUTH_USER=<user>
#   PRACTICE_AUTH_HASH='<bcrypt>'      ← single quotes are required: Compose mangles an unquoted bcrypt
#                                        hash whose salt starts with a letter ($2a$14$Abc… → "$2a$14").
#   PRACTICE_SESSION_SECRET=<64 hex>   ← chg-004: the sign-in cookie's value (openssl rand -hex 32).
# --session-secret / --rotate-session-secret rewrite the existing file atomically (mode 600), keeping its
# other lines byte-for-byte. The password, the hash and the secret are never printed.
set -euo pipefail
USAGE="usage: practice-auth.sh <user> [DIR] | --session-secret [DIR] | --rotate-session-secret [DIR]"
USER_NAME="${1:?$USAGE}"
DIR="${2:-$HOME/Dropbox/andrew/secrets/millwright}"
OUT="$DIR/practice-auth.env"

new_secret() { # 32 random bytes as 64 lowercase hex, or fail
  local s; s=$(openssl rand -hex 32) || return 1
  [[ "$s" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$s"
}

if [ "$USER_NAME" = --session-secret ] || [ "$USER_NAME" = --rotate-session-secret ]; then
  [ -f "$OUT" ] || { echo "practice-auth: $OUT does not exist; make it with practice-auth.sh <user> (nothing changed)" >&2; exit 1; }
  N=$(grep -c '^PRACTICE_SESSION_SECRET=' "$OUT" || true)
  if [ "$USER_NAME" = --session-secret ] && [ "$N" != 0 ]; then
    echo "practice-auth: $OUT already has PRACTICE_SESSION_SECRET; use --rotate-session-secret to replace it (nothing changed)" >&2; exit 1
  fi
  if [ "$USER_NAME" = --rotate-session-secret ] && [ "$N" != 1 ]; then
    echo "practice-auth: $OUT has $N PRACTICE_SESSION_SECRET lines, expected 1 (nothing changed)" >&2; exit 1
  fi
  SECRET=$(new_secret) || { echo "practice-auth: openssl did not return 64 hex characters (nothing changed)" >&2; exit 1; }
  umask 077
  TMP=$(mktemp "$DIR/.practice-auth.env.XXXXXX")
  trap 'rm -f "$TMP"' EXIT
  { grep -v '^PRACTICE_SESSION_SECRET=' "$OUT" || true; printf 'PRACTICE_SESSION_SECRET=%s\n' "$SECRET"; } > "$TMP"
  unset SECRET
  chmod 600 "$TMP"
  mv -f "$TMP" "$OUT"
  trap - EXIT
  if [ "$USER_NAME" = --session-secret ]; then
    echo "practice-auth: added PRACTICE_SESSION_SECRET to $OUT (mode 600)"
  else
    echo "practice-auth: replaced PRACTICE_SESSION_SECRET in $OUT (mode 600); once caddy is recreated with it, every device must sign in again"
  fi
  exit 0
fi

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
SECRET=$(new_secret) || { echo "practice-auth: openssl did not return 64 hex characters (nothing written)" >&2; exit 1; }
mkdir -p "$DIR"
umask 077
TMP=$(mktemp "$DIR/.practice-auth.env.XXXXXX")
printf "PRACTICE_AUTH_USER=%s\nPRACTICE_AUTH_HASH='%s'\nPRACTICE_SESSION_SECRET=%s\n" "$USER_NAME" "$HASH" "$SECRET" > "$TMP"
unset SECRET
chmod 600 "$TMP"
mv -n "$TMP" "$OUT"
[ -e "$TMP" ] && { rm -f "$TMP"; echo "practice-auth: $OUT appeared meanwhile (nothing written)" >&2; exit 1; }
echo "practice-auth: wrote $OUT (user $USER_NAME, bcrypt hash, session secret, mode 600)"
