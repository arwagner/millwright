# Delta: vps-rebuild / chg-009 — aint-farm runs agents

## ADDED
- **AC-27.** `scripts/aint-farm-backup.sh` gets factory.db from the running app (`docker exec aint-farm
  factory backup`), never the live file; checks it with `PRAGMA integrity_check` at home and only then
  publishes it into `backup/aint-farm/`; skips with a message when there is no aint-farm container and
  fails when the box is unreachable or the container isn't running. `scripts/backup.sh` runs it after
  Gandalf; all steps always run and any failure exits non-zero.

## MODIFIED
- **AC-23** — Now also: a third mount, `/var/run/docker.sock` at the same path, and `group_add: ["988"]`.
  No other service mounts the socket. The env file also carries `FACTORY_SECRET_KEY`.
- **AC-26** — The Aint-farm section covers runs (socket, caps, labels, cleanup) and the nightly backup.
- **AC-8** — Now also: no `factory*.db` and no `*.pem` tracked.
- **product-global (od-6)** — Compose stays the only process manager, except aint-farm's per-run
  `docker run --rm` containers.

## REMOVED
- Nothing.
