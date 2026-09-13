# Proposal: vps-rebuild / chg-001 — durable account storage for myron-api

**Trigger:** exploring-elan re-enabled full-text search across the raw book text, this time behind a
password login (myron commits `383a67a..f118799`). That gives the box a kind of state it has never
held before: usernames and password hashes that must outlive an image rebuild.

**Summary:** `myron-api` builds from an rsync'd context and is rebuilt on every deploy, so anything
the api writes inside the container is destroyed by the next `docker compose up -d --build`. The
account database therefore needs a named volume, and the api needs `AUTH_DB_PATH` pointing into it.
The same service also needs `NODE_ENV: production` — the retired PM2 `ecosystem.config.cjs` used to
supply it, and the api reads it to decide whether to mark the session cookie `Secure`; without it
every session cookie on exploring-elan ships un-Secure. Both are already in `compose.yaml` and
`scripts/verify.sh` is green, but neither is described anywhere in the spec, and one of them
contradicts the letter of design decision D4.

## Blast radius
Everything this change touches, so the ripple is explicit.
- Requirements affected: AC-4 (compose shape — still true as written, but no longer the whole
  story for `myron-api`); the nightly-backup scenario and AC-7 (a new durable volume exists that
  the backup does not cover); AC-10 / the rebuild runbook (a rebuild silently loses every account).
- Design decisions affected: **D4**. Its "secrets via `env_file:` … never `environment:` literals"
  reads as a blanket ban on `environment:`; the compose file now uses it for two non-secret values.
  D4 needs to say what it actually meant — secrets never, configuration fine. D4's named-volume
  list (`todo-data`, `caddy-data`, `myron-client-dist`) also needs `myron-auth`.
- Tasks affected (regenerate these): none of T1–T12 (all done and still true). Two new tasks,
  T13 and T14 below.
- Already-built code affected: `compose.yaml` (`myron-api` service + `volumes:` block) — edited
  and verified. `scripts/verify.sh` has no check for the new requirement yet. `README.md`'s
  runbook step 7 ("Restore data") does not mention the account volume.

## Status
- [ ] delta reviewed (analyze)
- [x] implemented & verified (compose.yaml; `scripts/verify.sh` ALL GREEN, AC-4 checks included)
- [x] folded into the feature's spec.md (product.md regenerates; never edit it by hand)
