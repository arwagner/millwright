# Delta: vps-rebuild / chg-004 — a sign-in page for practice.vawagners.cloud

## ADDED
- **AC-17.** The Caddyfile's `practice.vawagners.cloud` block serves `GET /signin` publicly from
  `/srv/practice-signin/signin.html` (caddy mounts `caddy/practice-signin` read-only there); no other path is
  public. `POST /signin/check` runs, inside a `route` so the written order holds, `basic_auth` with the same
  `{$PRACTICE_AUTH_USER} {$PRACTICE_AUTH_HASH}`, then sets
  `practice_session={$PRACTICE_SESSION_SECRET}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=31536000`.
  A request whose `Cookie` header holds exactly that pair (anchored) reaches `practice:8770`, but only when the
  secret is 64 lowercase hex; a request with an `Authorization` header passes `basic_auth` as before; both
  proxies drop `Authorization` and `Cookie`. Anything else gets 401 with `WWW-Authenticate: Basic
  realm="restricted"` and an HTML body that redirects to `/signin`. HSTS and the removed `Server` header apply
  to every response. `PRACTICE_SESSION_SECRET` lives only in `/srv/secrets/practice-auth.env`;
  `scripts/practice-auth.sh` writes it (`openssl rand -hex 32`) for a new file, adds it with
  `--session-secret` and replaces it with `--rotate-session-secret`, never printing it. README documents the
  apply, the rollback and that rotation signs out every device.

## MODIFIED
- **AC-14** — Was: `basic_auth` in front of everything. Now: in front of everything except `/signin` and the
  exact session cookie (AC-17); the user and hash, the proxy target and the stripped `Authorization` are
  unchanged.
- **AC-8** — Was: practice secrets `PRACTICE_AUTH_USER`/`PRACTICE_AUTH_HASH`. Now: also
  `PRACTICE_SESSION_SECRET`; no value of it in any tracked file.
- **AC-16** — The Practice section gains "Sign-in page (chg-004)".
- **product-global (mainline patch, not this branch)** — the practice hostname row: "basic auth or the
  sign-in cookie, then proxy to practice:8770" (od-3).

## REMOVED
- Nothing.
