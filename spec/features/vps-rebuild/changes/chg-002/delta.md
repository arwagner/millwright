# Delta: vps-rebuild / chg-002 — serve the Tiamat campaign wiki

## ADDED
- **AC-12.** `compose.yaml` mounts the host path `/var/www/tiamat` read-only into caddy at
  `/srv/tiamat`; the Caddyfile's `tiamat.vawagners.cloud` block serves that root as static files,
  answering `/<name>` from `<name>.html`.
- Terraform record `tiamat` (A → 187.124.159.132).

## MODIFIED
- **AC-2** — Was: apex, todo, exploring-elan, fiddlesticks, www (five). Now: adds tiamat (six).
- **AC-5** — Was: four hostnames. Now: five, adding tiamat.vawagners.cloud.
- **product-global invariants** — DNS record set and hostname→target map gain tiamat.

## REMOVED
- Nothing.
