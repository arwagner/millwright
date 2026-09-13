---
schema_version: 2
id: "feat-001"
slug: "vps-rebuild"
title: "Rebuild srv1491903 from code"
status: done
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
  tasks:    ready
gate:
  analyze: not-run
  product_global_hash: "sha256:9f31328a8e60"
  constitution_hash: "sha256:0caed037eb38"
human_signoff:
  - { id: hs-1, description: "Approve the DNS adoption: delete the five existing records in the Hostinger panel, then run the first terraform apply", owner: "Andrew", resolved: true }
  - { id: hs-2, description: "Approve the cutover: delete ollama and litellm, recreate the box, deploy onto Compose", owner: "Andrew", resolved: true }
open_decisions:
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
