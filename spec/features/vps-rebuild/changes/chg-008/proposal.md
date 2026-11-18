# Proposal: vps-rebuild / chg-008 — aint-farm's first secrets (the GitHub App)

**Trigger:** aint-farm ticket arwagner/aint-farm#2 (GitHub App, webhook intake, installation allowlist).
The orchestrator needs the App's id, its webhook secret and its private key. An approved capability
change, not a defect.

**Summary:** aint-farm gains one env file, `/srv/secrets/aint-farm.env` (`GITHUB_APP_ID`,
`GITHUB_WEBHOOK_SECRET`, `GITHUB_PRIVATE_KEY_PATH`), and a read-only bind mount of the App's private key,
`/srv/secrets/aint-farm-github-app.pem`, at `/run/secrets/github-app.pem`. The key is a multi-line PEM, so
it travels as a file, not an env var. It is one key for the whole factory, not per installation, so it
lives beside the other box secrets rather than encrypted in `factory.db` (chg-007's comment guessed the
latter; per-installation agent credentials and project secrets still go there).

## Blast radius
- Requirements affected: AC-23 (was: no `env_file`, one mount), AC-26 (README said "no secret").
- README: Secrets table row, runbook step 6 (the pem is not a `*.env`), Aint-farm section.
- verify.sh: the AC-23 check; the stub secrets dir gains `aint-farm.env`.
- Live effects when applied (hs-12): `env_file` is required, and a missing bind source becomes an empty
  directory, so both files must be on the box before the pull. Only aint-farm is recreated; no other site
  pauses.

## Status
- [ ] delta reviewed (analyze)
- [x] implemented & verified offline (verify.sh)
- [ ] live: hs-12
- [ ] folded into the feature's spec.md (after review)
