# Proposal: vps-rebuild / chg-006 — serve Gandalf at gandalf.vawagners.cloud

**Trigger:** Andrew wants Gandalf (his tabletop GM/Player app, its own repo) reachable by his Players from
anywhere and by his own AI runner over HTTPS, instead of only on his Mac (approved direction 2026-11-09,
hostname and Dropbox room confirmed 22:54Z). An approved capability change, not a defect.

**Summary:** One new proxied hostname. A new `gandalf` container (Gandalf's own multi-stage Dockerfile,
built on the box from a `git archive` of a reviewed commit in `/opt/gandalf/app`) sits on an internal-only
network with caddy. Gandalf has its own accounts (GM and Players), so Caddy adds TLS and HSTS only. The
app needs no secret. Its data is one SQLite database plus ~6 GB of content-addressed image files; the
nightly backup takes the app's own online snapshot (`cli.ts backup`), verifies it again at home and copies
new image files additively. Moving from the Mac is a one-time cutover; the Mac copy is stopped and kept as
the rollback, never a second live copy.

## Blast radius
- Requirements affected: AC-2 (eight records), AC-4 (seven services), AC-5 (seven hostnames), AC-7 (backup
  also covers Gandalf), AC-8 (no Gandalf database tracked), AC-9 (runbook steps 1/5/7/8/9 mention
  Gandalf; still nine steps), AC-13 (caddy's networks gain `gandalf`). New AC-19 to AC-22.
- product-global (main-branch-only, NOT edited here): DNS record set, hostname→target map, privacy line.
  A mainline patch is prepared separately (od-4).
- Design: a second service built from its own repo's Dockerfile (precedent: practice-convert, chg-005);
  a third backup mechanism (app snapshot + additive file copy). No decision reversed.
- Live effects when applied (each behind its own approval, hs-7/8/9): one DNS record; caddy recreated
  (new network): every site pauses a few seconds; a new container, volume and network; `/opt/gandalf/`
  on the box; ~6 GB of image files in the volume; at cutover, Gandalf on the Mac stops for good.
- Memory: caps on the box become practice 768m + practice-convert 1536m + gandalf 2560m; the uncapped
  rest uses ~0.8 GB today; 7.8 GB total, no swap.

## Status
- [ ] delta reviewed (analyze)
- [ ] implemented & verified offline (verify.sh green) and in a local Compose rehearsal
- [ ] mainline product-global patch reviewed and merged (od-4)
- [ ] folded into the feature's spec.md (after review)
- [ ] live: hs-7 (push + DNS), hs-8 (deliver + pre-seed), hs-9 (cutover)
