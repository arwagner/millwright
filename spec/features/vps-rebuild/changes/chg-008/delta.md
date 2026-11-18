# Delta: vps-rebuild / chg-008 — aint-farm's first secrets

## ADDED
- Nothing.

## MODIFIED
- **AC-23** (chg-007, not yet folded)
  - Was: ... keeps `/data` in the named volume `aint-farm-data` (its only mount; no Docker socket), has no
    `env_file` and no `environment`. ...
  - Now: ... keeps `/data` in the named volume `aint-farm-data`, and bind-mounts
    `/srv/secrets/aint-farm-github-app.pem` read-only at `/run/secrets/github-app.pem` (no other mount; no
    Docker socket). Its only `env_file` is `/srv/secrets/aint-farm.env` (required); it has no
    `environment`. The rest of AC-23 is unchanged.
- **AC-26** (chg-007, not yet folded)
  - Was: the Aint-farm section says "no secret".
  - Now: it names the env file and the key file, and the README's Secrets table lists both.

## REMOVED
- Nothing.
