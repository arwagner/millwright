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

## Layout

```
terraform/        DNS records, SSH key, post-install script (NEVER the VPS subscription)
bootstrap.sh      blank box -> Compose host (docker, ufw, sshd hardening, clone)
compose.yaml      caddy, todo, myron-api, myron-bot; litellm commented out
caddy/Caddyfile   TLS (ACME), static sites, reverse proxies
sites/            vawagners + fiddlesticks static content
litellm/          cold storage; every key comes from env
scripts/          rebuild.sh, backup.sh, verify.sh, launchd plist
spec/             spec-flow workspace (specs, plans, gates)
```

## Rebuild runbook

1. `scripts/backup.sh` on the laptop — fresh `todo.db` snapshot + Caddy cert volume.
2. `scripts/rebuild.sh` — calls the Hostinger `recreate` endpoint. Free, keeps the IP,
   **wipes the box and deletes Hostinger snapshots**. Needs `HOSTINGER_API_TOKEN`, `VM_ID`,
   `TEMPLATE_ID` (discover with `--list` / `--templates`).
3. `ssh root@187.124.159.132 'bash -s' < bootstrap.sh` (skip if it ran as the post-install script).
4. Deploy myron: `./deploy.sh` in the myron repo (rsync, `--exclude='*.png'` keeps Books off the
   wire — 9.6 GB down to ~200 MB).
5. Deploy todo: push to the deploy remote.
6. Copy secret env files from `~/Dropbox/andrew/secrets/millwright/` to `/srv/secrets/`, then
   `chmod 700 /srv/secrets && chmod 600 /srv/secrets/*.env`.
7. Restore data: copy the `todo.db` snapshot into the `todo-data` volume; untar the cert backup
   into the `caddy-data` volume (skips Let's Encrypt reissue — five duplicate certs/week limit).
   Nothing restores `myron-auth` (exploring-elan's logins) — it is deliberately not backed up, so
   recreate accounts by hand: `docker compose exec myron-api npm run users -- add <name>`.
8. `cd /srv/millwright && docker compose up -d --build`.
9. Check each hostname over HTTPS; on the box, `ps axww | grep TODO_TOKEN` must find nothing and
   `pm2`/`nginx`/`ollama` must not exist.

## Nightly backup

`scripts/backup.sh` runs on the laptop at 02:30 under launchd. Install:

```
cp scripts/com.millwright.backup.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.millwright.backup.plist
```

It takes an **atomic** SQLite snapshot inside the container (`sqlite3 ".backup"` — todo runs WAL
mode; a raw copy can tear) plus the Caddy cert volume, into Dropbox. If the laptop is asleep or
the box is down, the night's run silently skips. Old snapshots are pruned by hand.

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
