# Plan — Rebuild srv1491903 from code (feat-001)

The WHAT lives in `spec.md`; decisions 1–16 in `.scratchpad/iac-design.md` are settled inputs.
This plan states the remaining HOW and the build order. Source code lives at the project root
(terraform/, caddy/, sites/, scripts/, bootstrap.sh, compose.yaml), never inside `spec/`.

## Design decisions

- **D1 — Repo layout** follows the design doc exactly: `terraform/` (main.tf, dns.tf, ssh.tf,
  bootstrap.tf, gitignored backend.hcl), `bootstrap.sh`, `compose.yaml`, `caddy/Caddyfile`,
  `sites/{vawagners,fiddlesticks}/`, `litellm/config.yaml` (cold storage), `scripts/{rebuild.sh,
  backup.sh}`. Millwright's operational scripts share `scripts/` with the spec-flow `.mjs` tooling;
  they do not interact.
- **D2 — DNS as five records, www as an A record.** Live DNS (verified 2026-08-17) holds the apex,
  todo, exploring-elan, fiddlesticks (A) and www (CNAME to apex). Terraform declares five
  `hostinger_dns_record` resources, converting www to an A record pointing at 187.124.159.132 —
  same answer, one record type, and the provider's create-only behavior favors simple A records.
  A `backend.hcl.example` documents the gitignored real `backend.hcl` (local backend, state file in
  Dropbox).
- **D3 — Caddyfile shape.** One site block per hostname: apex and fiddlesticks are `file_server`
  on `sites/…`; exploring-elan serves the myron client from the shared `myron-client-dist`
  volume (see D4) with `handle /api/*` proxied to `myron-api:3001`; todo is a plain proxy to
  `todo:8787`; `www.vawagners.cloud` is a `redir` to the apex. ACME is Caddy's default — no TLS
  config needed.
- **D4 — Compose shape.** Services caddy, todo, myron-api, myron-bot; `restart: unless-stopped`
  on all; app images built on the VPS via `dockerfile_inline` from source directories the laptop
  delivers (`/opt/todo`, `/var/www/exploring-elan`); secrets via `env_file:` pointing at
  `/srv/secrets/*.env` (never `environment:` literals — keeps them out of `ps` and the repo; and
  `docker exec` into the todo container inherits that env, which is what removes `TODO_TOKEN`
  from any command line and closes AC-10's `ps` check). An `environment:` block is permitted for
  values that are *not* secret — a mode flag or a path inside the container; `myron-api` uses it
  for `NODE_ENV` and `AUTH_DB_PATH` (chg-001). A secret value there stays forbidden. Named volumes
  `todo-data`, `caddy-data` (certs), `myron-client-dist`, and `myron-auth` — `myron-client-dist` is
  mounted read-only into caddy and populated from the myron client's `dist` at deploy, the shared
  contract between T4 and T5; `myron-auth` holds exploring-elan's usernames and password hashes and
  is a plain named volume precisely so it sits outside both the image and the tree the laptop
  mirrors with `rsync --delete` (chg-001). **No service other than
  caddy declares `ports:`.** Base images carry an MVP-cliff note: pin by digest before promote.
  The todo image installs `sqlite3` (~2 MB) for the atomic backup.
- **D5 — rebuild.sh** is a curl call to the Hostinger API `recreate` endpoint with
  `template_id`, reading `HOSTINGER_API_TOKEN` from the environment (sourced from Dropbox, never
  stored in the repo) and sending it only as an `Authorization: Bearer` header — never in a URL —
  with no `set -x` in the script. No subscription create/destroy/cancel call exists in the
  script.
- **D6 — backup.sh + launchd.** `scripts/backup.sh` runs on the laptop: `ssh` +
  `docker exec todo sqlite3 /data/todo.db ".backup /tmp/b.db"`, then `scp`/`docker cp` the
  snapshot and the `caddy-data` volume to Dropbox. A `scripts/com.millwright.backup.plist`
  ships in the repo; the README documents `launchctl load`. Failure mode at prototype: silent
  skip (spec sharp edge).
- **D7 — Verification toolchain.** No test framework; the prototype's checks are offline shell
  commands collected in `scripts/verify.sh`, one labeled check per acceptance criterion
  (`feat-001/AC-N` in the echo/comment). `terraform validate` needs terraform installed locally;
  `caddy validate` and `docker compose config` run through Docker so the laptop needs no extra
  installs. `spec/.spec-flow.md` `tests:` is set to `scripts/verify.sh`.
- **D8 — Live content is fetched read-only.** The 233-byte vawagners page, the fiddlesticks site,
  and the litellm config are copied off the running box with `scp` (read-only; touches nothing) —
  the constitution's ask-first rule covers changes to the box, not reads.

## Task breakdown

Ordered; `[P]` tasks are mutually independent once T1 is done. See `tasks.md` for the live
checklist. T11 and T12 are the two ask-first live steps (hs-1, hs-2 in the manifest).

## Verification approach

Offline checks run via `scripts/verify.sh`; each prints its trace token. Seams: the shell (script
invocations) and, for AC-10, the public HTTPS endpoints.

| Criterion | Check (seam) | Trace token |
|---|---|---|
| AC-1 | `terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate`; grep pins `= 0.1.22`; grep finds no `hostinger_vps"` resource; the key path `ssh.tf` references ends in `.pub` | feat-001/AC-1 |
| AC-2 | grep `dns.tf` for exactly the five records of the product-global DNS invariant, all → 187.124.159.132 | feat-001/AC-2 |
| AC-3 | `bash -n bootstrap.sh`; grep for docker install, ufw allow 22/80/443 + default deny, authorized_keys write, credential-free HTTPS clone, `PasswordAuthentication no` | feat-001/AC-3 |
| AC-4 | `docker compose config -q`; grep services + `restart:`; litellm only in comments; `docker compose config --format json` shows a `ports` key on no service except caddy | feat-001/AC-4 |
| AC-5 | `docker run --rm -v ./caddy/Caddyfile:/etc/caddy/Caddyfile caddy:2 caddy validate --config /etc/caddy/Caddyfile`; grep the four hostnames + www redir | feat-001/AC-5 |
| AC-6 | `bash -n scripts/rebuild.sh`; grep for the recreate endpoint path; grep finds no destroy/cancel call | feat-001/AC-6 |
| AC-7 | `bash -n scripts/backup.sh`; grep for `sqlite3` `.backup` via `docker exec`; README documents the launchd schedule | feat-001/AC-7 |
| AC-8 | `git check-ignore backend.hcl terraform/backend.hcl terraform.tfstate x.env sub/dir/x.env`; the pre-commit hook exists and rejects a staged `.env` test file; grep tracked files (litellm/config.yaml included) for the six secret names' values (names may appear, values may not) | feat-001/AC-8 |
| AC-9 | grep README for the nine runbook steps, the `~/.claude.json` snippet, the two-file-edit note | feat-001/AC-9 |
| AC-10 | (manual, post-cutover) curl the four hostnames over HTTPS; `ssh` in: `ps axww | grep TODO_TOKEN` empty; `pm2`/`nginx`/`ollama` absent; todo.db restored | feat-001/AC-10 |
| AC-11 | `docker compose config --format json`: `myron-api` mounts the `myron-auth` volume, its `AUTH_DB_PATH` resolves inside that mount, `NODE_ENV` is `production`, and it still declares no `ports:` | feat-001/AC-11 |
