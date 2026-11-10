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
| practice.vawagners.cloud | basic auth or the sign-in cookie, then proxy to practice:8770 (piano practice app; see [Practice](#practice)) |
| gandalf.vawagners.cloud | proxy to gandalf:3000; the app's own accounts (tabletop app; see [Gandalf](#gandalf)) |

## Layout

```
terraform/        DNS records, SSH key, post-install script (NEVER the VPS subscription)
bootstrap.sh      blank box -> Compose host (docker, ufw, sshd hardening, clone)
compose.yaml      caddy, todo, myron-api, myron-bot, practice, practice-convert, gandalf; litellm commented out
caddy/Caddyfile   TLS (ACME), static sites, reverse proxies
caddy/practice-signin/  the practice sign-in page (chg-004), mounted into caddy
sites/            vawagners + fiddlesticks static content (tiamat lives in its own repo)
litellm/          cold storage; every key comes from env
scripts/          rebuild.sh, backup.sh, verify.sh, launchd plist; practice-{backup,restore,auth}.sh; gandalf-{backup,restore}.sh
spec/             spec-flow workspace (specs, plans, gates)
```

## Rebuild runbook

1. `scripts/backup.sh` on the laptop — fresh `todo.db` snapshot + Caddy cert volume + the practice
   app's own verified snapshot (`backup/practice/`) + Gandalf's snapshot and new image files (`backup/gandalf/`).
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
   Deliver Gandalf without starting it, in the Gandalf repo:
   `deploy/deploy.sh --host root@187.124.159.132 --rev <reviewed commit> --no-start`.
6. Copy secret env files from `~/Dropbox/andrew/secrets/millwright/` to `/srv/secrets/` (this includes
   `practice-auth.env`; caddy refuses to start without it), then
   `chmod 700 /srv/secrets && chmod 600 /srv/secrets/*.env`.
7. Restore data: copy the `todo.db` snapshot into the `todo-data` volume; untar the cert backup
   into the `caddy-data` volume (skips Let's Encrypt reissue — five duplicate certs/week limit).
   Nothing restores `myron-auth` (exploring-elan's logins) — it is deliberately not backed up, so
   recreate accounts by hand: `docker compose exec myron-api npm run users -- add <name>`.
   Practice: `scripts/practice-restore.sh <newest backup/practice/practice-….sqlite>` (laptop; the
   practice service is not running yet), which verifies the pair, imports it and restores it.
   Gandalf: `scripts/gandalf-restore.sh <newest backup/gandalf/gandalf-….db>` (laptop; gandalf not running
   yet) sends the image files and the database.
8. `cd /srv/millwright && docker compose up -d --build` (this also builds practice-convert, which downloads
   the pinned MuseScore AppImage from GitHub).
9. Check each hostname over HTTPS (practice: 401 without credentials, whose body links `/signin`; `/signin` 200; the app with them; gandalf: the sign-in page, then sign in
   and re-pair the AI runner, see [Gandalf](#gandalf)); on the box,
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

Gandalf (chg-006) is backed up through the running app too: `scripts/gandalf-backup.sh` asks it for an online
snapshot (`docker exec gandalf node src/server/cli.ts backup`), verifies it again at home (size, sha256,
integrity, migrations, every table count), copies new image files additively into `backup/gandalf/assets/`
(names are content hashes; nothing is deleted at home, so every older snapshot keeps its files), checks
that every image the snapshot names is there, and publishes snapshot then manifest. The box keeps its 7
newest snapshots. `backup.sh` runs practice, then Gandalf; both always run. Until the cutover the Gandalf
step says "nothing to back up" and passes (no volume, or no `gandalf.db` in it). Once `gandalf.db` exists it
fails loudly whenever the gandalf container isn't running (including after a rollback to the Mac).

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
| practice-auth.env | `PRACTICE_AUTH_USER`, `PRACTICE_AUTH_HASH` (bcrypt, single-quoted), `PRACTICE_SESSION_SECRET` (64 hex, the sign-in cookie) | caddy, for practice.vawagners.cloud |
| (none) | — | gandalf: needs no secret; its accounts and the AI runner's credential hashes live in its database |

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

- **Auth**: Caddy `basic_auth` on every path except the sign-in page, or the sign-in cookie (below); the
  user, bcrypt hash and session secret come from `/srv/secrets/practice-auth.env`. Make that file with
  `scripts/practice-auth.sh <user>` (asks for the password, hashes it with Caddy on stdin, writes it
  single-quoted — Compose mangles an unquoted bcrypt hash — and adds a random session secret). The app also
  admits only `Host: practice.vawagners.cloud` and that Origin, and ignores forwarded headers.
- **Network**: `practice` sits only on the internal `practice` network (with caddy); no host port, no route
  out. Its data is the `practice-data` named volume.
- **Scores**: private. `deploy/deploy.sh` in the practice repo rsyncs the `.mscz` files byte-for-byte to
  `/srv/practice/sources` and the laptop-made MusicXML sidecars to `/srv/practice/exports` (no MuseScore on
  the box). Neither is in this repo or any image.
- **One-off commands** (`docker compose run --rm --no-deps practice node src/cli.js …`) only while the
  service is stopped; while it runs they are refused (`DB_IN_USE`).
- **Day boundaries** follow `TZ: America/New_York` in compose.yaml (the box runs UTC).

### Converter (chg-005)

`practice-convert` turns `.mscz` files uploaded to the practice app into MusicXML with MuseScore Studio 4.6.5
(the app never runs MuseScore itself). Its image is built from `convert/` in the practice repo, which
`deploy/deploy.sh` delivers with the app to `/opt/practice/app/convert`; the build downloads the official
AppImage and refuses any bytes but the pinned sha256, so a build needs GitHub reachable.

- **Boxed in**: `network_mode: none`, read-only root, uid 10001, no capabilities, `no-new-privileges`,
  1.5 GB with no swap, 1 CPU, 64 processes, 120 s per batch. No database, practice home, scores or secrets.
- **Spool**: two named volumes. The app writes jobs to `practice-convert-in` (read-only for the converter)
  and collects answers from `practice-convert-out` (contract `practice-convert/1`, `src/convert.js`). Jobs
  are transient and are not backed up.
- **What it refuses**: the app checks each file first. Files saved in MuseScore 4.0–4.5 formats (and pre-3
  or newer than 4.6) are refused with advice to re-save in MuseScore 4.6; 3.x and 4.6 convert exactly as on
  the laptop (practice slice 11, S0: 1133/1133 and 20/20).
- **Idle cost**: a shell loop polling once a second; MuseScore runs only during a job (peak ~130 MB).
- **The existing books** keep their laptop exports (sidecars); the converter is only for uploads.

### Sign-in page (chg-004)

Some web views never show the browser's Basic prompt: the iPad "Web MIDI" apps render the empty 401 as a
blank page. So the practice site also has a sign-in page. Safari and Chrome still prompt and work as before.

- `GET /signin` is the only public path: a form (`caddy/practice-signin/signin.html`, mounted read-only).
- The form sends the typed user and password as the `Authorization` header of one `POST /signin/check`.
  Caddy's `basic_auth` checks them exactly as the prompt would; only then does Caddy set
  `practice_session=<PRACTICE_SESSION_SECRET>; Secure; HttpOnly; SameSite=Lax`, for a year. The `route` around
  that handler must stay: Caddy's default order would set the cookie before checking the password.
- A request whose cookie equals the secret goes to the app; so does one that passes basic auth. The app sees
  neither the cookie nor the `Authorization` header. Anything else gets 401 with `WWW-Authenticate` (browsers
  prompt) and a body that sends a web view to `/signin`.
- If the secret is missing or not 64 hex, the cookie admits nobody (basic auth still works).
- One secret for every device, so there is no per-device sign-out.
  **Rotating the secret signs out every device** (they get the sign-in page or the prompt again).

Apply (once; then a normal Millwright deploy):
1. Laptop: `scripts/practice-auth.sh --session-secret` adds the secret to
   `~/Dropbox/andrew/secrets/millwright/practice-auth.env`, keeping the user and hash lines.
2. Copy that file to `/srv/secrets/practice-auth.env` on the box, `chmod 600` (as runbook step 6).
3. Push, then on the box `cd /srv/millwright && git pull --ff-only && docker compose up -d caddy`. caddy is
   recreated (new env value and mount): every site pauses for a few seconds. Do it while no practice Session
   is open.
4. Check: no credentials → 401 whose body links `/signin`; `/signin` → 200; a wrong password on
   `/signin/check` → 401 and no `Set-Cookie`; a made-up cookie → 401; the other sites unchanged. Then sign in
   in a browser and in the iPad app.

Rollback: on the box `cd /srv/millwright && git checkout <previous commit> && docker compose up -d caddy`
(basic auth only, as before; the iPad app is blank again), then revert the merge on main, push, and
`git checkout main && git pull --ff-only` on the box. The extra line in `practice-auth.env` is harmless to
the old Caddyfile.

Rotate (sign every device out): `scripts/practice-auth.sh --rotate-session-secret`, copy the file to the
box as in step 2, then `docker compose up -d caddy`.

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

## Gandalf

Gandalf, the tabletop GM/Player app (code in its own repo; delivered by its `deploy/deploy.sh`).

- **Auth**: the app's own accounts (GM and Players). Caddy adds TLS and HSTS only. Sign-in, join and
  pairing are rate-limited by client address; `TRUST_PROXY: "1"` makes that the real address behind caddy.
- **Network**: `gandalf` sits only on the internal `gandalf` network (with caddy): no host port, no route
  out. The GM's AI runner connects in to `wss://gandalf.vawagners.cloud/api/worker`; Gandalf calls nothing.
- **Data**: the `gandalf-data` volume: `gandalf.db` (SQLite, WAL) and `assets/` (~6 GB of image files
  named by their content hash). No secret anywhere.
- **Delivery**: `deploy/deploy.sh --host root@187.124.159.132 --rev <reviewed commit>` in the Gandalf
  repo: `git archive` to `/opt/gandalf/releases/<sha>`, `/opt/gandalf/app` → that release, a snapshot of the running app first,
  then `docker compose up -d --build gandalf` (`--no-start`: build and `up --no-start gandalf` only).
  Migrations run at start; the snapshot taken first is the way back.
- **Memory**: 2560 MB, one CPU, one library import at a time.

### Moving Gandalf from the Mac (cutover)

Gandalf is never started on the box before this, so no empty second database is ever created there.

Before (any day, the Mac stays live). In the Gandalf repo, with `C` = the delivered commit:
1. Deliver without starting: `deploy/deploy.sh --host root@187.124.159.132 --rev $C --no-start` (builds
   the image; `up --no-start gandalf` makes the container and the empty volume).
2. Build a helper image of exactly that commit from a clean `git archive` (never the working tree, which
   may hold uncommitted files), tagged apart from the Mac's own stack:
   `git archive --format=tar $C | docker build -t gandalf-cutover:$C -`
3. Copy the Mac's image files to the backup folder (read-only on the Mac's volume):
   `docker run --rm -v gandalf_gandalf-data:/d:ro -v ~/Dropbox/andrew/secrets/millwright/backup/gandalf/assets:/out gandalf-cutover:$C cp -an /d/assets/. /out/`
4. Pre-seed the box: `scripts/gandalf-restore.sh --assets-only`.

The cutover (about 10 minutes; Players and GM off):
1. Mac, in the Gandalf repo: `docker compose stop app`.
2. Mac: the final snapshot. Its name must be exactly `gandalf-YYYYMMDD-HHMMSSZ.db` (UTC), or restore refuses it:
   `N=gandalf-$(date -u +%Y%m%d-%H%M%SZ).db`
   `docker run --rm -v gandalf_gandalf-data:/data gandalf-cutover:$C node src/server/cli.ts backup /data/backups/$N`
   then copy the pair out:
   `docker run --rm -v gandalf_gandalf-data:/d:ro gandalf-cutover:$C cat /d/backups/$N > ~/Dropbox/andrew/secrets/millwright/backup/gandalf/$N`
   and the same for `$N.manifest.json`.
3. Repeat "Before" step 3 (only new image files move).
4. `scripts/gandalf-restore.sh ~/Dropbox/andrew/secrets/millwright/backup/gandalf/$N`. It also checks that every
   image the snapshot names is on the box.
5. On the box: `cd /srv/millwright && docker compose up -d gandalf`.
6. Check: https://gandalf.vawagners.cloud answers; the GM signs in; a Player signs in from another
   device; the GM re-pairs the AI runner: `npm run runner -- pair --origin https://gandalf.vawagners.cloud`.
7. The Mac stays stopped (`docker compose stop`). Do not start it again; it is the rollback, not a copy.

### Rollback (back to the Mac)

On the box: `docker compose stop gandalf`, then keep a record of everything written there (the service is
stopped, so the nightly script can't do it):
`docker compose run --rm --no-deps -T gandalf node src/server/cli.ts backup /data/backups/gandalf-<UTC stamp>.db`.
Start the Mac: `docker compose start app` in the Gandalf repo. What that gives you, plainly:
- **Only on the Mac:** the Mac stack listens on 127.0.0.1 only. Remote Players lose access, and
  https://gandalf.vawagners.cloud answers 502 (Caddy's target is stopped).
- **The AI runner** must be re-paired to the Mac: `npm run runner -- pair --origin http://127.0.0.1:8080`.
- **The nightly backup fails every night** for its Gandalf step (gandalf.db on the box, container stopped),
  until Gandalf runs on the box again or chg-006 is reverted. That is deliberate: it must not pass silently.
- **Anything written on the box** after the cutover is NOT on the Mac. It stays in that record and is merged
  by hand, if at all.
