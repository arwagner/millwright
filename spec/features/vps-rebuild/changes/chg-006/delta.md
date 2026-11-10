# Delta: vps-rebuild / chg-006 — serve Gandalf

## ADDED
- **AC-19.** `compose.yaml` defines `gandalf` (container name `gandalf`, `restart: unless-stopped`,
  `init: true`) built from `/opt/gandalf/app` with that tree's own Dockerfile. It declares no `ports:`, is
  attached only to a `gandalf` network declared `internal: true` (caddy is the only other member), keeps
  `/data` in the named volume `gandalf-data` (its only mount), has no `env_file`, and has exactly this
  non-secret environment: `PUBLIC_ORIGIN=https://gandalf.vawagners.cloud`, `COOKIE_SECURE=true`,
  `TRUST_PROXY=1`, `GANDALF_AI_PROVIDER=session`, `IMPORT_RUNNING=1`. `mem_limit` 2560m with
  `memswap_limit` equal, `cpus` 1.0.
- **AC-20.** The Caddyfile's `gandalf.vawagners.cloud` block sets HSTS, drops `Server`, compresses, and
  has exactly one `reverse_proxy gandalf:3000`, with no `basic_auth`, no `header_up` and no
  `trusted_proxies` (Caddy replaces any client X-Forwarded-For; the app trusts exactly one hop).
- **AC-21.** `scripts/gandalf-backup.sh` gets the snapshot from the running app (`docker exec gandalf node
  src/server/cli.ts backup`), never the live file; re-verifies size, sha256, integrity, migration count
  and every table count on the laptop; copies new asset files with `rsync --ignore-existing` (never
  `--delete`); fails if any asset name the snapshot mentions is missing at home; publishes snapshot then
  manifest into `backup/gandalf/`, publishing nothing on failure; keeps the 7 newest snapshots on the box;
  excludes in-flight `*.tmp` files and tolerates files removed mid-copy; skips with a message only when
  the box has no `gandalf-data` volume or no `gandalf.db` in it, and fails when the box is unreachable or
  `gandalf.db` exists without a running container; its ssh ends a stalled link (`ServerAliveInterval`).
  `scripts/backup.sh` runs practice, then it; both always run and either failure exits non-zero.
  `scripts/gandalf-restore.sh` refuses while the service runs, checks the pair against its manifest,
  sends asset files additively and owns them to uid 1000, checks that every image the snapshot names is
  on the box, stages the database in a fresh folder in the volume, checks its sha256 on the box, and
  refuses an existing `gandalf.db` unless `--replace` (which moves it aside, never deletes).
  `--assets-only` is the pre-seed.
- **AC-22.** `README.md` has a Gandalf section: network, data, no secret, delivery, backup, restore, the
  cutover from the Mac (never started on the box before it), the runner re-pair, and the rollback.
- Terraform record `gandalf` (A → 187.124.159.132).

## MODIFIED
- **AC-2** — Was: seven records. Now: eight, adding `gandalf`.
- **AC-4** — Was: six services. Now: seven, adding gandalf; still only caddy maps a port.
- **AC-5** — Was: six hostnames. Now: seven, adding gandalf.vawagners.cloud.
- **AC-7** — Was: todo.db `.backup` + caddy certs + practice. Now: also Gandalf (AC-21).
- **AC-8** — Now also: no `gandalf*.db` or `*.db.manifest.json` tracked.
- **AC-9** — Still nine steps; steps 1, 5, 7, 8 and 9 include Gandalf.
- **AC-13** — caddy's networks: was `{default, practice}`, now `{default, practice, gandalf}`.
- **Nightly backup scenario** — gains the Gandalf snapshot and asset copy.
- **product-global (mainline patch, od-4)** — DNS set, hostname map and privacy line gain Gandalf.

## REMOVED
- Nothing.
