# Proposal: vps-rebuild / chg-007 — serve aint-farm at factory.vawagners.cloud, add swap

**Trigger:** aint-farm (Andrew's software factory, its own repo) needs its orchestrator running on the box
behind Caddy, as its design settled 2026-11-17 (aint-farm `docs/design.md`; ticket arwagner/aint-farm#13).
The same design adds a 4 GB swapfile. An approved capability change, not a defect.

**Summary:** One new proxied hostname. A new `aint-farm` container (aint-farm's own Dockerfile, built on the
box from a `git archive` of a release tag in `/opt/aint-farm/app`) on the default network, because it
calls GitHub's API. GitHub App webhooks are verified by signature in the app, so Caddy adds TLS and HSTS
only. No secret yet. Its data is one SQLite database, not backed up nightly until it holds something that
can't be recreated. The box gains a 4 GB swapfile; every capped container sets `memswap_limit` equal to
`mem_limit` (practice gains one), so the caps mean what they meant before.

## Blast radius
- Requirements affected: AC-2 (nine records), AC-3 (bootstrap makes swap), AC-4 (eight services), AC-5
  (eight hostnames), AC-9 (runbook steps 5 and 9 mention aint-farm; still nine steps). New AC-23 to AC-26.
- product-global (main-branch-only, NOT edited here): the DNS set, hostname map and the box-hardware line
  ("no swap" becomes "4 GB swap") need a mainline patch (od-5).
- Design: the first service that calls out to the internet on purpose from the default network beside
  todo and the myron services. Later aint-farm tickets will mount the Docker socket (root-equivalent; an
  accepted risk in aint-farm's design) and start per-run containers outside Compose: that needs its own
  change here, because the product invariant says Compose is the only process manager.
- Live effects when applied (each behind its own approval, hs-10/11): one DNS record; caddy restarted for the new
  site (`git pull` replaces the bind-mounted Caddyfile's inode, so a reload would read the old file): every
  site pauses a few seconds;
  a new container and volume; `/opt/aint-farm/` on the box; a 4 GB file at `/swapfile`.
- Memory: caps become practice 768m + practice-convert 1536m + gandalf 2560m + aint-farm 512m; 7.8 GB plus
  4 GB swap.

## Status
- [ ] delta reviewed (analyze)
- [x] implemented & verified offline (verify.sh green); deploy rehearsed on local Docker (aint-farm deploy/rehearse.sh)
- [x] mainline product-global patch merged (od-5)
- [ ] folded into the feature's spec.md (after review)
- [x] live: hs-10 (push + DNS), hs-11 (swap, pull, restart caddy, first deploy), 2026-11-18
