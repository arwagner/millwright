# Proposal: vps-rebuild / chg-003 — serve the piano practice app at practice.vawagners.cloud

**Trigger:** Andrew wants his piano practice app (its own repo, `~/Dropbox/andrew/music/Exercises/practice`)
reachable from every computer he plays on, with one shared schedule instead of one per laptop
(intake qitem-20261107004519-4557c595daa45340, 2026-11-07). An approved capability change, not a defect.

**Summary:** One new proxied hostname for one user. Caddy puts basic auth in front of a new `practice`
container (Node 24, the app's own server) that sits on an internal-only network with caddy. The app owns
its SQLite database exclusively for its whole life, so the nightly backup cannot be the todo pattern
(`sqlite3 .backup` from outside); it asks the running app for its own verified backup over a local socket
and re-verifies the copy on the laptop. The scores are private: they are rsync'd to the box, never in this
repo or an image, and the box has no MuseScore — the laptop's MuseScore exports MusicXML "sidecars" that
travel with them. Moving the schedule from the laptop is a one-time cutover that retires the laptop copy.

## Blast radius
- Requirements affected: AC-2 (seven records), AC-4 (five services; caddy gains a second network and an
  env file), AC-5 (six hostnames), AC-7 (backup also covers practice, by a different mechanism), AC-8
  (new secret file; no practice data or notation may be tracked), AC-9 (runbook steps 1/5/6/7/9 mention
  practice; still nine steps). New AC-13 to AC-16. AC-10 gains a practice check at the next real rebuild.
- product-global (main-branch-only, NOT edited here): the DNS record set and hostname→target invariants,
  and the privacy line that names only `todo.db` and `.backup`. A dedicated mainline patch is prepared
  separately (see the approval packet); this change depends on it.
- Design decisions affected: D2/D3 lists grow by one; **D4** gains a second network (first non-default
  network) and a service whose backup is not `docker exec … sqlite3`; **D6** gains a second backup
  mechanism. New D9 (practice). No decision reversed.
- Already-built code: `compose.yaml` (practice service, caddy env_file + networks, `practice` network,
  `practice-data` volume), `caddy/Caddyfile` (one new block, additions only), `terraform/dns.tf` (one
  record), `scripts/backup.sh` (calls the practice step last), new `scripts/practice-{backup,restore,auth}.sh`,
  `scripts/verify.sh`, `README.md`. todo, myron-api and myron-bot resolve identically to main.
- Live effects when applied (each behind its own approval): one DNS record; caddy is recreated by
  `docker compose up -d` (env file + network change), interrupting every site for a few seconds; a new
  container, volume and network; `/srv/practice/{sources,exports}` and `/opt/practice/app` on the box.

## Status
- [ ] delta reviewed (analyze) — pre-build consistency check recorded in the slice evidence; independent
      review pending
- [x] implemented & verified offline (verify.sh green) and in a local Compose rehearsal
      (slice 09 evidence: auth, origin, isolation, single owner, backup/restore, real-data cutover)
- [x] independent review r2 findings F1–F5 repaired (slice 09 candidate r2: import-backup restore,
      data-decided rollback, guarded Linux reads, quoted remote delivery, fresh release staging)
- [ ] mainline product-global patch reviewed and merged (policy, separate from this branch)
- [ ] folded into the feature's spec.md (after review)
- [ ] live: needs Andrew's explicit approvals (hs-3 go-live, hs-4 schedule cutover)
