# Delta: vps-rebuild / chg-007 — serve aint-farm, add swap

## ADDED
- **AC-23.** `compose.yaml` defines `aint-farm` (container name `aint-farm`, `restart: unless-stopped`,
  `init: true`) built from `/opt/aint-farm/app` with that tree's own Dockerfile. It declares no `ports:`, is
  on the default network only, keeps `/data` in the named volume `aint-farm-data` (its only mount; no Docker
  socket), has no `env_file` and no `environment`. `mem_limit` 512m with `memswap_limit` equal, `cpus` 0.5.
- **AC-24.** The Caddyfile's `factory.vawagners.cloud` block sets HSTS, drops `Server`, compresses, and has
  exactly one `reverse_proxy aint-farm:3000`, with no `basic_auth`, no `header_up` and no `trusted_proxies`.
- **AC-25.** `bootstrap.sh` makes a 4 GB `/swapfile` only if it isn't already swapped on, and adds it to
  `/etc/fstab` once. Every service with a `mem_limit` has an equal `memswap_limit` (practice gains 768m).
- **AC-26.** `README.md` has an Aint-farm section: network, data (and that it is not backed up yet), no
  secret, memory, the admin CLI (`docker exec aint-farm factory`), delivery by tag and the one-step rollback;
  and a Swap section.
- Terraform record `factory` (A → 187.124.159.132).

## MODIFIED
- **AC-2** — Was: eight records. Now: nine, adding `factory`.
- **AC-3** — Now also: bootstrap makes the swapfile (AC-25).
- **AC-4** — Was: seven services. Now: eight, adding aint-farm; still only caddy maps a port.
- **AC-5** — Was: seven hostnames. Now: eight, adding factory.vawagners.cloud.
- **AC-9** — Still nine steps; step 5 delivers aint-farm, step 9 checks its `/health`.
- **product-global (mainline patch, od-5)** — DNS set and hostname map gain factory; box hardware: 4 GB swap.

## REMOVED
- Nothing.
