# Delta: vps-rebuild / chg-003 — serve the piano practice app

## ADDED
- **AC-13.** `compose.yaml` defines a `practice` service (container name `practice`, `restart:
  unless-stopped`) built with `dockerfile_inline` from `/opt/practice/app` on a digest-pinned
  `node:24.16.0-bookworm-slim`, `npm ci --omit=dev`, running as `node`. It declares no `ports:`, is attached
  only to a `practice` network declared `internal: true` (caddy is the only other member), keeps its home
  in the named volume `practice-data`, mounts `/srv/practice/sources` and `/srv/practice/exports` read-only
  with `create_host_path: false`, has a 0700 tmpfs at `/run/practice` for its maintenance socket, carries
  only non-secret `environment:` (public origin `https://practice.vawagners.cloud`, bind `0.0.0.0`, sidecar
  exporter, `TZ: America/New_York`) and no `env_file`, and has memory and CPU limits.
- **AC-14.** The Caddyfile's `practice.vawagners.cloud` block puts `basic_auth` with only the
  `{$PRACTICE_AUTH_USER} {$PRACTICE_AUTH_HASH}` placeholders in front of everything, proxies to
  `practice:8770` without the `Authorization` header, sets HSTS and no Permissions-Policy. caddy reads
  `/srv/secrets/practice-auth.env` as a required env file; no bcrypt hash or practice credential is in any
  tracked file. `scripts/practice-auth.sh` makes that file (password on stdin, hash single-quoted).
- **AC-15.** `scripts/practice-backup.sh` gets the snapshot from the running app (`docker exec practice node
  src/admin.js backup`; `--stopped` uses a one-off `cli.js backup`), never `sqlite3` and never the live file;
  re-verifies size, sha256, integrity, foreign keys, schema and every table count on the laptop; publishes
  snapshot then manifest into `backup/practice/` and publishes nothing on any failure. `scripts/backup.sh`
  runs it last. `scripts/practice-restore.sh` refuses while the service runs, checks the pair, stages it in a
  fresh per-attempt folder and lets the app's `import-backup` publish it — reusing a same-named pair only when
  both files are byte-identical, refusing any other collision before anything switches — then `restore`.
  `scripts/practice-rollback.sh` records the revisions and state first, stops the service and takes the
  authoritative copy from the data: the laptop only when the server is proven empty (whole-home
  `practice inventory` — any file name, SQLite by header — with no `data/`, nothing but lock/note files and the
  laptop's own final pair, the service never created, no later server snapshot), or the verified backups compare `same` (history and music identity, by content, not numeric ids);
  the server when it verifiably extends the laptop's; otherwise (a missing/unreadable pointer beside any
  database or backup file, divergence, anything unreadable) it stops with the laptop still retired.
- **AC-16.** `README.md` has a Practice section: auth file, network, private score delivery, one-off command
  rule, time zone, the cutover (`cli.js retire --to https://practice.vawagners.cloud`, import, first scan,
  the service's first start — never at go-live) and the rollback (`practice-rollback.sh`).
- Terraform record `practice` (A → 187.124.159.132).

## MODIFIED
- **AC-2** — Was: six records. Now: seven, adding `practice`.
- **AC-4** — Was: caddy, todo, myron-api, myron-bot. Now: adds practice; still no service but caddy maps a
  port.
- **AC-5** — Was: five hostnames. Now: six, adding practice.vawagners.cloud.
- **AC-7** — Was: todo.db `.backup` + caddy certs. Now: also the practice pair via the app (AC-15).
- **AC-8** — Was: six named secrets. Now: also `PRACTICE_AUTH_USER`/`PRACTICE_AUTH_HASH`; no `*.sqlite`,
  `*.mscz`, `*.musicxml` or `retired.json` tracked.
- **AC-9** — Was: nine-step runbook. Now: still nine steps; steps 1, 5, 6, 7 and 9 include practice.
- **Nightly backup scenario** — gains the practice snapshot; a practice failure exits non-zero after todo
  and caddy have landed.
- **product-global invariants (mainline patch, not this branch)** — DNS record set and hostname→target map
  gain practice; the privacy line gains the practice backup mechanism.

## REMOVED
- Nothing.
