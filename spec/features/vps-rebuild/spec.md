## Why
The box's configuration lives only on the box (see `research.md`). This feature captures all of it
as code in this repository so that a rebuild is a repeatable procedure: Terraform for DNS, SSH key,
and post-install script; `bootstrap.sh` for the base OS; Docker Compose plus Caddy for every
service; two laptop-side scripts for rebuild and nightly backup. Design decisions 1–16 in
`.scratchpad/iac-design.md` are settled and are not reopened here.

## User stories
- As the operator, I want the whole box described in one public repo so that a blank VPS can be
  rebuilt from it in one evening with no credential needed to clone.
- As the operator, I want nightly automatic backups of the VPS-only data so that a dead box loses
  at most one day of `todo.db`.
- As the operator, I want one process manager (Compose) and one web entry point (Caddy) so that a
  reboot brings everything back and adding a service is a two-file edit.

## Behavior & scenarios
- **Scenario: authoring validates cleanly (no live changes)**
  - Given the repo with terraform/, bootstrap.sh, compose.yaml, caddy/Caddyfile, sites/, scripts/
  - When the offline checks run (`terraform validate`, `docker compose config`, `caddy validate`,
    `bash -n` on each script)
  - Then every check passes and nothing has touched the live box or live DNS.
- **Scenario: full rebuild (after both sign-offs)**
  - Given a fresh backup exists and the cutover is approved (hs-2)
  - When the runbook runs: `scripts/rebuild.sh` (Hostinger `recreate`), `bootstrap.sh` over SSH,
    myron and todo deploys, secrets copied from Dropbox to `/srv/secrets/`, `todo.db` and the cert
    volume restored, `docker compose up -d --build`
  - Then the IP is unchanged and all four hostnames answer over HTTPS with their assigned content
    (per the product-global hostname invariant).
- **Scenario: accounts survive a redeploy**
  - Given an account exists on exploring-elan and the laptop runs myron's `deploy.sh`
  - When the deploy rsyncs a new `/var/www/exploring-elan/api` build context and runs
    `docker compose up -d --build myron-api myron-bot`
  - Then the `myron-api` image is rebuilt from scratch and the existing account still signs in,
    because the account database was never inside the image or the build context.
- **Scenario: nightly backup**
  - Given the box is running and the laptop launchd job fires
  - When `scripts/backup.sh` runs
  - Then a consistent `todo.db` snapshot (taken with SQLite `.backup` inside the container, never a
    raw file copy) and the Caddy certificate volume land in Dropbox.

## Acceptance criteria
- [x] AC-1: `terraform validate` passes in `terraform/`; the provider is pinned exactly to
  `hostinger/hostinger = 0.1.22`; no `hostinger_vps` resource exists in any `.tf` file.
- [x] AC-2: `terraform/dns.tf` declares exactly the record set from the product-global DNS
  invariant — A records for the apex, todo, exploring-elan, and fiddlesticks pointing at
  187.124.159.132, plus a www record answering for the apex — and no others.
- [x] AC-3: `bash -n bootstrap.sh` passes, and the script installs docker, writes
  `authorized_keys`, clones millwright over HTTPS with no credential, configures ufw to allow
  only ports 22, 80, and 443 in and deny everything else, and sets
  `PasswordAuthentication no` in `sshd_config`.
- [x] AC-4: `docker compose config` succeeds on `compose.yaml`; it defines caddy, todo, myron-api,
  and myron-bot with restart policies; litellm appears only as commented-out text; no service
  other than caddy maps a host port (`ports:`).
- [x] AC-5: The Caddyfile validates (`caddy validate`), maps each of the four hostnames to its
  assigned target from the product-global hostname invariant, and redirects www.vawagners.cloud to
  the apex.
- [x] AC-6: `scripts/rebuild.sh` calls the Hostinger VPS `recreate` API endpoint and contains no
  subscription create, destroy, or cancel call.
- [x] AC-7: `scripts/backup.sh` passes `bash -n`, takes the `todo.db` snapshot via
  `docker exec … sqlite3 ".backup"`, and copies the snapshot and the Caddy certificate volume to
  Dropbox; the README documents the launchd schedule.
- [x] AC-8: A clean checkout contains no secret: `.gitignore` covers `backend.hcl`,
  `terraform.tfstate*`, and `*.env` (including nested paths); a pre-commit hook rejects staged
  `*.env`, `backend.hcl`, and `*tfstate*` files; and no value of the six named secrets
  (`DISCORD_BOT_TOKEN`, `OPENROUTER_API_KEY`, `CHANNEL_WHITELIST`, `DM_WHITELIST`, `TODO_TOKEN`,
  the litellm `master_key`) appears in any tracked file, `litellm/config.yaml` included.
- [x] AC-9: `README.md` contains the numbered rebuild runbook (the nine steps), the
  `~/.claude.json` todo MCP snippet, and a note confirming that adding a new static or proxied
  service touches only `compose.yaml` and the Caddyfile.
- [x] AC-10: (manual) After the approved cutover, one real rebuild completes: same IP, all four
  hostnames answer over HTTPS, `todo.db` restored, `pm2`/`nginx`/`ollama` no longer run on the
  box, and `TODO_TOKEN` appears in no process command line (`ps axww | grep TODO_TOKEN` finds
  nothing).

- [x] AC-11: `compose.yaml` declares a named volume for exploring-elan's account database, mounts
  it into `myron-api`, and sets `AUTH_DB_PATH` to a path inside that mount, so the accounts live
  neither in the image nor under `/var/www`; the same service sets `NODE_ENV: production` (the api
  reads it to mark the session cookie `Secure`). `docker compose config` still succeeds and
  `myron-api` still declares no `ports:`.

## Known sharp edges (prototype)
- The provider is community-tier 0.x; the exact pin is the only protection against a breaking release.
- The `recreate` endpoint deletes Hostinger snapshots — snapshots cannot protect the rebuild itself.
- Dropbox is sync, not backup: it holds the only off-box copy of Books; a local delete propagates.
- The myron client ships as `dist` only; a rebuild silently depends on the laptop's build toolchain.
- No rollback exists; mitigation is scheduling the cutover on a free evening (downtime accepted).
- Let's Encrypt allows five duplicate certificates per week; repeated rebuild tests must restore the
  cert volume rather than re-issue.
- Hostinger docs do not say whether `recreate` reapplies account SSH keys; `bootstrap.sh` writes
  `authorized_keys` itself so the result is the same either way.
- Pre-cutover check: confirm `myron/api/.env` on the box is genuinely empty; rotate the weak litellm
  master key even though the service is retired.
- The nightly backup skips silently when the laptop is asleep or the box is down — no retry, no
  alert at prototype depth.
- No backup retention policy is stated; snapshots accumulate in Dropbox until pruned by hand.
- exploring-elan's accounts (the `myron-auth` volume) are the one piece of durable state the nightly
  backup does not cover, so a rebuild loses every login. Accepted deliberately (od-1, 2026-09-12):
  the site has a single account and recreating it is one command,
  `docker compose exec myron-api npm run users -- add <name>`, which runbook step 7 now states.
  Revisit if exploring-elan ever has accounts that are not trivially recreatable.
- DNS reconciled 2026-08-17: the panel held seven records — the five Terraform declares plus two
  dead pointers (n8n, llm) with nothing behind them. Andrew approved dropping both at the DNS
  adoption (hs-1): all seven get deleted in the panel, five come back via terraform apply.

## Open questions
- None — the two human calls (DNS adoption, cutover) are tracked as sign-offs hs-1 and hs-2 in the
  manifest.
