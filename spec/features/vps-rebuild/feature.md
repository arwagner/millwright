---
schema_version: 2
id: "feat-001"
slug: "vps-rebuild"
title: "Rebuild srv1491903 from code"
status: active
owner: "Andrew"
depth: "prototype"
sprint: null
external: null
depends_on: []
requires_design: null
readiness:
  research: ready
  design:   n/a
  spec:     ready
  plan:     ready
  tasks:    draft
gate:
  analyze: blocking
  product_global_hash: "sha256:db50bf205d8a"
  constitution_hash: "sha256:0caed037eb38"
human_signoff:
  - { id: hs-1, description: "Approve the DNS adoption: delete the five existing records in the Hostinger panel, then run the first terraform apply", owner: "Andrew", resolved: true }
  - { id: hs-2, description: "Approve the cutover: delete ollama and litellm, recreate the box, deploy onto Compose", owner: "Andrew", resolved: true }
  - { id: hs-3, description: "chg-003 go-live: push millwright, terraform apply the practice record, deliver practice-auth.env, deliver practice code and private scores WITHOUT starting practice, recreate caddy (a few seconds of downtime for every site)", owner: "Andrew", resolved: false }
  - { id: hs-4, description: "chg-003 schedule cutover: retire the laptop home, import its final backup on the box, first scan, then the first start of practice; rollback by practice-rollback.sh", owner: "Andrew", resolved: false }
  - { id: hs-5, description: "chg-004 live: add PRACTICE_SESSION_SECRET (practice-auth.sh --session-secret), copy practice-auth.env to /srv/secrets, push millwright, pull on the box, recreate caddy (a few seconds of downtime for every site), while no practice Session is open", owner: "Andrew", resolved: false }
  - { id: hs-6, description: "chg-005 live: with the practice wave (uploads + converter app code), deliver the practice commit holding convert/, pull millwright, docker compose up -d --build practice practice-convert (builds the converter, downloading the pinned MuseScore AppImage on the box); no Session open", owner: "Andrew", resolved: false }
  - { id: hs-7, description: "chg-006 (a): push millwright and terraform apply the gandalf record", owner: "Andrew", resolved: false }
  - { id: hs-8, description: "chg-006 (b): deliver Gandalf without starting it (deploy.sh --no-start), pull millwright, recreate caddy (a few seconds of downtime for every site), pre-seed image files (gandalf-restore.sh --assets-only)", owner: "Andrew", resolved: false }
  - { id: hs-9, description: "chg-006 (c): cutover: stop Gandalf on the Mac, final snapshot, restore on the box, first start, re-pair the AI runner; rollback per README", owner: "Andrew", resolved: true, decision: "Cut over 00:16-00:18Z; Andrew signed in as GM and Player 01:28Z; first nightly 07:30Z verified. AI runner not yet re-paired (Andrew pairs it at his first AI session).", at: "2026-11-11" }
open_decisions:
  - { id: od-2, description: "chg-003 needs the product-global DNS/hostname/backup invariants updated on main (main-branch-only); merge the prepared mainline patch before go-live", owner: "Andrew", resolved: false }
  - { id: od-3, description: "chg-004: product-global's hostname invariant says practice is 'Caddy basic auth, then proxy to practice:8770'; on main (main-branch-only) it should read 'basic auth or the sign-in cookie'. Same target, same user and password", owner: "Andrew", resolved: false }
  - { id: od-4, description: "chg-006 needs the product-global DNS set, hostname map and privacy line to gain Gandalf on main (main-branch-only); merge the prepared mainline patch before hs-7", owner: "Andrew", resolved: false }
  - { id: od-1, description: "chg-001: back the myron-auth volume up nightly and restore it during a rebuild, or accept that a rebuild loses exploring-elan's accounts and recreate them by hand", owner: "Andrew", resolved: true, decision: "Accept the loss: one account, recreated with a single command. Recorded as a sharp edge in spec.md and in runbook step 7; revisit if the accounts stop being trivially recreatable.", at: "2026-09-12" }
overrides:
  - { id: ov-1, gate: open-items, by: "Andrew", reason: "hs-1 (DNS adoption) and hs-2 (cutover) gate only the final live tasks T11/T12; authoring tasks T1-T10 touch nothing live", at: "2026-08-17", resolved: true }
extends: []
---

# Feature notes — Rebuild srv1491903 from code

- Source design: `.scratchpad/iac-design.md` (full inventory, decisions 1–16, risks, build order).
- Build order steps 1–3 (authoring the repo) change nothing on the live box and need no approval.
  Steps 4–5 are the two sign-offs above (`hs-1` DNS adoption, `hs-2` cutover) — the constitution
  makes them ask-first regardless of prototype depth.
- Sixteen design decisions are already made and recorded in the scratchpad doc; the spec references
  them rather than reopening them.
- Provider quirk (0.1.22): `hostinger_vps_ssh_key` is destroyed and recreated on every apply
  (read drift). Harmless — same key content, new id each time — but noisy; revisit at promote.
- Cloudflare's WAF on the Hostinger API rejects the full bootstrap.sh as post-install content;
  terraform uploads a two-line stub that fetches the real script from the public repo. The stub
  only works once the repo is pushed to GitHub; until then runbook step 3 (SSH) is the path.
