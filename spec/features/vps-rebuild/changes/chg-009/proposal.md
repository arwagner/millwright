# Proposal: vps-rebuild / chg-009 — aint-farm runs agents

**Trigger:** aint-farm tickets #5 (Docker runner) and #6 (the tracer bullet: a real review on a real PR).
The orchestrator starts each agent run as its own container, and stores agent credentials sealed in
`factory.db`. An approved capability change (Andrew, 2026-11-18), not a defect.

**Summary:** aint-farm gains the host's Docker socket and the docker group (gid 988), `FACTORY_SECRET_KEY`
in its env file, and a nightly backup of `factory.db` through the app. Product-global's "Compose is the
only process manager" gains one exception: aint-farm's per-run `docker run --rm` containers, which are
jobs, not services.

## Blast radius
- Requirements affected: AC-23 (a third mount, the socket; `group_add`), AC-26 (README: runs, backup),
  AC-7/backup (step 6). New AC-27.
- product-global: the process-manager invariant (od-6), merged on main with this change.
- Security: the socket is root-equivalent on the box. aint-farm's design accepts it for a single-tenant
  factory and revisits it before multitenancy. Runs themselves get no socket and no mounts.
- Live effects (hs-13): aint-farm is recreated by its next deploy; no other service changes. Run
  containers use up to 2 × 2.5 GB beside the others; the 4 GB swap (chg-007) absorbs bursts.

## Status
- [x] implemented & verified offline (verify.sh)
- [ ] live: hs-13
- [ ] folded into the feature's spec.md (after review)
