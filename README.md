# millwright

Infrastructure as code for srv1491903 (Hostinger VPS, 187.124.159.132, Ubuntu 24.04). A rebuild of
the box is a repeatable procedure: Terraform for DNS, SSH key, and post-install script;
`bootstrap.sh` for the base OS; Docker Compose + Caddy for every service; laptop-side scripts for
rebuild and nightly backup. The repo is public so a blank box can clone its own configuration with
no credentials. Secrets live in Dropbox, never here.

| Hostname | Serves |
|---|---|
| vawagners.cloud | static, `sites/vawagners` |
| www.vawagners.cloud | redirect to the apex |
| todo.vawagners.cloud | reverse proxy to todo:8787 |
| exploring-elan.vawagners.cloud | static client `dist`, `/api/*` to myron-api:3001 |
| fiddlesticks.vawagners.cloud | static, `sites/fiddlesticks` |
| tiamat.vawagners.cloud | static, `/var/www/tiamat` (rsync'd by the Tiamat wiki's `deploy.sh`) |
| practice.vawagners.cloud | basic auth, then proxy to practice:8770 (piano practice app; see [Practice](#practice)) |

## Layout

```
terraform/        DNS records, SSH key, post-install script (NEVER the VPS subscription)
bootstrap.sh      blank box -> Compose host (docker, ufw, sshd hardening, clone)
compose.yaml      caddy, todo, myron-api, myron-bot, practice; litellm commented out
caddy/Caddyfile   TLS (ACME), static sites, reverse proxies
sites/            vawagners + fiddlesticks static content (tiamat lives in its own repo)
litellm/          cold storage; every key comes from env
scripts/          rebuild.sh, backup.sh, verify.sh, launchd plist; practice-{backup,restore,auth}.sh
spec/             spec-flow workspace (specs, plans, gates)
```

## Rebuild runbook

1. `scripts/backup.sh` on the laptop — fresh `todo.db` snapshot + Caddy cert volume + the practice
   app's own verified snapshot (`backup/practice/`).
2. `scripts/rebuild.sh` — calls the Hostinger `recreate` endpoint. Free, keeps the IP,
   **wipes the box and deletes Hostinger snapshots**. Needs `HOSTINGER_API_TOKEN`, `VM_ID`,
   `TEMPLATE_ID` (discover with `--list` / `--templates`).
3. `ssh root@187.124.159.132 'bash -s' < bootstrap.sh` (skip if it ran as the post-install script).
4. Deploy myron: `./deploy.sh` in the myron repo (rsync, `--exclude='*.png'` keeps Books off the
   wire — 9.6 GB down to ~200 MB).
5. Deploy todo: push to the deploy remote. Deploy the Tiamat wiki: `./deploy.sh` in the wiki repo
   (`~/Dropbox/andrew/D&D/sessions/Tiamat/wiki`). Deliver practice without starting it:
   `deploy/deploy.sh --rev <reviewed commit> --no-start` in the practice repo (code, private scores,
   MusicXML sidecars).
6. Copy secret env files from `~/Dropbox/andrew/secrets/millwright/` to `/srv/secrets/` (this includes
   `practice-auth.env`; caddy refuses to start without it), then
   `chmod 700 /srv/secrets && chmod 600 /srv/secrets/*.env`.
7. Restore data: copy the `todo.db` snapshot into the `todo-data` volume; untar the cert backup
   into the `caddy-data` volume (skips Let's Encrypt reissue — five duplicate certs/week limit).
   Nothing restores `myron-auth` (exploring-elan's logins) — it is deliberately not backed up, so
   recreate accounts by hand: `docker compose exec myron-api npm run users -- add <name>`.
   Practice: `scripts/practice-restore.sh <newest backup/practice/practice-….sqlite>` (laptop; the
   practice service is not running yet), which verifies the pair, imports it and restores it.
8. `cd /srv/millwright && docker compose up -d --build`.
9. Check each hostname over HTTPS (practice: 401 without credentials, the app with them); on the box,
   `ps axww | grep TODO_TOKEN` must find nothing and `pm2`/`nginx`/`ollama` must not exist.

## Nightly backup

`scripts/backup.sh` runs on the laptop at 02:30 under launchd. Install:

```
cp scripts/com.millwright.backup.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.millwright.backup.plist
```

It takes an **atomic** SQLite snapshot inside the container (`sqlite3 ".backup"` — todo runs WAL
mode; a raw copy can tear) plus the Caddy cert volume, into Dropbox. If the laptop is asleep or
the box is down, the night's run silently skips. Old snapshots are pruned by hand.

Practice is different: its server owns its database exclusively for its whole life, so `sqlite3`
cannot touch it. `scripts/practice-backup.sh` asks the running app for its normal verified backup
(`docker exec practice node src/admin.js backup`, a local socket, no credential), copies that finished
snapshot and manifest home, verifies them again (size, sha256, integrity, foreign keys, every table
count) and publishes them into `backup/practice/`, manifest last. Any failure publishes nothing.

## todo MCP adapter

The adapter runs by `docker exec` into the todo container, which inherits the container's env —
no token on any command line. `~/.claude.json` needs (this file can't live in the repo):

```json
"todo": {
  "command": "ssh",
  "args": ["-o", "BatchMode=yes", "root@187.124.159.132",
           "docker exec -i todo node src/adapters/mcp/main.ts"]
}
```

## Adding a service

Two files: a service block in `compose.yaml` (no `ports:` — only caddy publishes) and a site block
in `caddy/Caddyfile` (plus a Terraform DNS record if it gets a new hostname). Nothing else.

## Secrets

Values live only in `~/Dropbox/andrew/secrets/millwright/` and on the box in `/srv/secrets/`.
Names, for the grep in `scripts/verify.sh`:

| File | Variables | Used by |
|---|---|---|
| todo.env | `TODO_TOKEN` | todo + MCP adapter |
| myron-bot.env | `DISCORD_BOT_TOKEN`, `OPENROUTER_API_KEY`, `CHANNEL_WHITELIST`, `DM_WHITELIST` | myron bot |
| myron-api.env | (empty today — confirm at cutover) | myron api |
| litellm.env | `LITELLM_MASTER_KEY` | litellm, if ever resurrected (rotate: the old key is burned) |
| hostinger-api-token | `HOSTINGER_API_TOKEN` | rebuild.sh |
| practice-auth.env | `PRACTICE_AUTH_USER`, `PRACTICE_AUTH_HASH` (bcrypt, single-quoted) | caddy, for practice.vawagners.cloud |

## Known risks

- **Dropbox compromise = TLS private-key compromise** — the cert backup contains the domain's
  private keys. Mitigation is revoke + reissue, not encryption at rest.
- **The Hostinger account is the root of trust** — its API token can wipe the box. Keep 2FA on.
- **Base images are tag-pinned, not digest-pinned** — pin by digest before this leaves prototype.
- **Dropbox is sync, not backup** — a local delete propagates everywhere.
- **The myron client ships as `dist` only** — a rebuild depends on the laptop's build toolchain.
- **DNS adoption is manual-first**: the provider can't import or update records. Delete all seven
  records in the Hostinger panel (the five above plus the dead `n8n` and `llm` pointers, dropped
  by decision 2026-08-17), then `terraform apply` recreates exactly the five in `dns.tf`.

## Practice

The piano practice app (code in the practice repo; its `docs/DEPLOY.md` is the app-side contract).
One user, one server-owned SQLite schedule used from every computer.

- **Auth**: Caddy `basic_auth` on every path; the user and bcrypt hash come from
  `/srv/secrets/practice-auth.env`. Make that file with `scripts/practice-auth.sh <user>` (asks for the
  password, hashes it with Caddy on stdin, writes it single-quoted — Compose mangles an unquoted bcrypt
  hash). The app also admits only `Host: practice.vawagners.cloud` and that Origin, and ignores forwarded
  headers.
- **Network**: `practice` sits only on the internal `practice` network (with caddy); no host port, no route
  out. Its data is the `practice-data` named volume.
- **Scores**: private. `deploy/deploy.sh` in the practice repo rsyncs the `.mscz` files byte-for-byte to
  `/srv/practice/sources` and the laptop-made MusicXML sidecars to `/srv/practice/exports` (no MuseScore on
  the box). Neither is in this repo or any image.
- **One-off commands** (`docker compose run --rm --no-deps practice node src/cli.js …`) only while the
  service is stopped; while it runs they are refused (`DB_IN_USE`).
- **Day boundaries** follow `TZ: America/New_York` in compose.yaml (the box runs UTC).

### Moving the schedule from the laptop (cutover)

The practice service is never started before this: at go-live only caddy is (re)started, so no empty
second database can be created on the server.

1. Laptop: stop the local app (close its window), then
   `node src/cli.js retire --to https://practice.vawagners.cloud` in the practice repo. It refuses while a
   Session is open, takes a final verified backup (`kind: final`) and retires the home: from then on the
   laptop app refuses to open it (`HOME_RETIRED`), so two schedules cannot diverge.
2. `scripts/practice-restore.sh <practice home>/backups/<final snapshot>.sqlite` (service stopped). It
   stages the pair in a fresh folder on the box and the app's `import-backup` publishes it (never over a
   different same-named pair) and restores it.
3. On the box: `docker compose run --rm --no-deps practice node src/cli.js scan` — expect every Exercise
   present, `exported: 0` and no changes (the scores and sidecars match the stored revisions).
4. `docker compose up -d practice`, then sign in at https://practice.vawagners.cloud from each computer.

### Rollback (back to the laptop)

`scripts/practice-rollback.sh` (laptop), at any point after step 1. It first writes a record (revisions of
this checkout, the practice commit on the box and the laptop checkout, the retirement note, whether the
service ran), stops the service, then decides from the data which copy is authoritative:

- the server is provably empty — no pointer, a complete walk of the whole home (every file, any name — SQLite recognised by its header —
  no symlink, special or unreadable entry), no `data/` folder (every first run, selection or restore makes one,
  even for a database kept outside the home), no file but the ownership lock/note files and the laptop's own
  final pair byte-identical, the practice service container never created on the box, and no server snapshot
  made after the retirement in the laptop's backup folder — or its verified backup
  equals the laptop's final backup in history AND music identity (`compare-history`: same) → the laptop: it
  is unretired as it was;
- the server's verified backup extends the final backup (every laptop row, revision and Exercise identity
  unchanged, plus Reviews etc. made there) → the server: its backup is imported into the laptop home and
  restored, then the home is unretired;
- anything else → STOP, nothing on the laptop changes and it stays retired: no (or an unreadable) pointer
  with any evidence that history may exist — a database under any name or path, `data/`, symlinks or
  unreadable parts, a service that has run, a later server snapshot — or diverged histories or music, or
  anything unreadable. Recovery: on the box find the database the service last used and select it with
  `practice use-db <file>` (the server then has a pointer again), and rerun; the rollback never guesses.

The server stays stopped afterwards; it is the record, not a second schedule.
