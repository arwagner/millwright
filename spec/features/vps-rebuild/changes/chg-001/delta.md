# Delta: vps-rebuild / chg-001 — durable account storage for myron-api

> The change expressed against the current spec as explicit operations.

## ADDED

New requirements, written as full spec requirements. Each acceptance criterion takes the next stable
`AC-N` id when folded into `spec.md`: append, never renumber an existing id.

- **Acceptance criterion (next id: AC-11).** `compose.yaml` declares a named volume for the
  exploring-elan account database, mounts it into `myron-api`, and sets `AUTH_DB_PATH` to a path
  inside that mount — so the accounts live neither in the image nor under `/var/www`. The same
  service sets `NODE_ENV: production`. `docker compose config` still succeeds and `myron-api` still
  declares no `ports:`.

- **Scenario: accounts survive a redeploy.**
  - Given an account exists on exploring-elan and the laptop runs `deploy.sh`
  - When the deploy rsyncs a new `/var/www/exploring-elan/api` build context and runs
    `docker compose up -d --build myron-api myron-bot`
  - Then the `myron-api` image is rebuilt from scratch and the existing account still signs in,
    because the database was never inside the image or the build context.

- **Known sharp edge (prototype).** The account database is the first durable state on the box that
  the nightly backup does not cover, and the rebuild runbook does not restore. A box rebuild loses
  every account; they are recreated by hand with
  `docker compose exec myron-api npm run users -- add <name>`. Cheap while exploring-elan has a
  single account — see open decision od-1 before that stops being true.

## MODIFIED

For each, show before and after.

- **D4 — Compose shape: how secrets and configuration reach a service** (`plan.md`)
  - Was: "secrets via `env_file:` pointing at `/srv/secrets/*.env` (never `environment:` literals —
    keeps them out of `ps` and the repo …)".
  - Now: secrets still reach a service only through `env_file:` — that part is non-negotiable and
    unchanged, and it is what keeps `TODO_TOKEN` out of every command line (AC-10). An
    `environment:` block is permitted for values that are *not* secret, such as a mode flag or a
    path inside the container. `myron-api` uses it for `NODE_ENV` and `AUTH_DB_PATH`. A secret
    value in an `environment:` block remains forbidden.

- **D4 — Compose shape: the named-volume list** (`plan.md`)
  - Was: named volumes `todo-data`, `caddy-data` (certs), and `myron-client-dist`.
  - Now: adds `myron-auth`, holding exploring-elan's usernames and password hashes. Unlike
    `myron-client-dist` it is a plain named volume, not a bind mount to a host path — the point is
    to sit outside both the image and the tree the laptop mirrors with `rsync --delete`.

## REMOVED

- Nothing. No existing requirement stops being true; AC-4's four services, restart policies, and
  caddy-only `ports:` all still hold as written.
