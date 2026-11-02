# Proposal: vps-rebuild / chg-002 — serve the Tiamat campaign wiki

**Trigger:** Andrew wants his D&D campaign wiki (markdown, kept in its own git repo under
`~/Dropbox/andrew/D&D/sessions/Tiamat/wiki`) publicly viewable at `tiamat.vawagners.cloud`.

**Summary:** One new static hostname. The wiki builds to HTML on the laptop and its `deploy.sh`
rsyncs the output to `/var/www/tiamat` on the box — the same host-path pattern as
`myron-client-dist`. Caddy mounts it read-only and serves it with clean URLs.

## Blast radius
- Requirements affected: AC-2 (record set grows to six), AC-5 (five hostnames), product-global
  DNS and hostname invariants. New AC-12.
- Design decisions affected: D2/D3 record and site-block lists grow by one; no decision reversed.
- Already-built code: `terraform/dns.tf`, `caddy/Caddyfile`, `compose.yaml` (caddy volume),
  `scripts/verify.sh`, `README.md` (hostname table, runbook step 5).
- Backup: none needed — the content is reproducible from the wiki repo.

## Status
- [ ] delta reviewed (analyze)
- [ ] implemented & verified (verify.sh green; AC-12 live check after deploy)
- [x] folded into the feature's spec.md
- [ ] live: `terraform apply` and box `git pull && docker compose up -d caddy` — need Andrew's go-ahead
