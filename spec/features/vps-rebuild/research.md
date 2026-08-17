# Problem Brief — vps-rebuild

> Condensed from `.scratchpad/iac-design.md` (full inventory and decision log live there).

## Problem statement
Andrew struggles to recover or reproduce his Hostinger VPS (srv1491903) because its configuration
lives only on the box itself — seven services under three process managers, hand-edited nginx
vhosts, and four files whose only copy is the VPS. If the box dies, the services do not come back.
A solution should make a rebuild a repeatable, written-down procedure without putting any secret or
the VPS subscription itself under repository or Terraform control.

## Target users
- Andrew — sole operator; needs a rebuild he can run from his laptop in one evening.

## Jobs to be done
- Rebuild the dead or wiped box: backup → Hostinger `recreate` call → `bootstrap.sh` → deploy
  myron and todo → copy secrets → restore data → `docker compose up -d --build` → check hostnames.
- Keep nightly laptop-side backups of the only VPS-resident data (`todo.db`, Caddy cert volume).
- Add a new service by editing `compose.yaml` and the Caddyfile, nothing more.

## Success signals (how we'll know the pain shrank)
- One deliberate, real rebuild completes and every hostname answers afterward (an untested rebuild
  is not a rebuild — risk 2 in the design doc).
- The repo alone (plus Dropbox secrets) is enough: a blank box clones millwright with no credential.
- The four known problems the rebuild fixes are gone: PM2 no-startup, litellm public-by-sort-order,
  ollama impossible on this hardware, `TODO_TOKEN` visible in `ps`.

## Constraints
- Public repo: no secrets, no state; Dropbox holds secrets and tfstate (constitution non-negotiables).
- Terraform never manages the `hostinger_vps` subscription; rebuilds use the free `recreate`
  endpoint that keeps the IP (decision 9).
- Provider pinned `= 0.1.22`; its DNS resource cannot import or update — adoption requires deleting
  the five panel records first (decision 16).
- Live-box and live-DNS steps are ask-first.

## Explicitly out of scope
- ollama and litellm as running services (litellm config kept in cold storage only).
- myron and todo application code (their own repos); millwright runs and backs them up.
- Deferred work items 1–4 in the design doc (Books removal, 1Password, MCP-over-HTTP, todo commit
  reconcile).

## Open questions
- None blocking authoring. Pre-rebuild check recorded in the spec: confirm `myron/api/.env` on the
  box is really empty before cutover.
