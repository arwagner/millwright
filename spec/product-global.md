# Product-global — millwright

## Vision
One public repository rebuilds the whole VPS: Terraform for DNS/SSH/post-install, `bootstrap.sh`
for the base box, Docker Compose + Caddy for every service, laptop-side scripts for rebuild and
nightly backup.

## Glossary
- **rebuild** — the full procedure: laptop backup, Hostinger `recreate` call, `bootstrap.sh`,
  source deploys, secret copy, data restore, `docker compose up -d --build`, hostname checks.
- **recreate endpoint** — the Hostinger API call that reinstalls the existing VPS subscription from
  a template. Free, keeps the subscription and the IP address, deletes Hostinger snapshots.
- **cold storage** — configuration kept in the repo for a service that does not run (litellm).
- **the box** — srv1491903, Hostinger VPS at 187.124.159.132, Ubuntu 24.04.

## Global non-functional requirements
- Performance: none (prototype).
- Security: only ports 80/443 (Caddy) and SSH answer from the internet; no secret appears in the
  repository, in an image, or on a process command line.
- Accessibility: none (prototype).
- Reliability / availability: every service returns after a reboot without manual steps; a rebuild
  restores every service on the same IP; downtime during a scheduled rebuild is acceptable.
- Privacy / data handling: `todo.db` is backed up nightly via an atomic SQLite `.backup` inside the
  container (never a raw copy of a live WAL database), landing in Dropbox with the Caddy
  certificate volume.

## Product invariants
- The IP address 187.124.159.132 does not change across rebuilds.
- Terraform owns every DNS record for vawagners.cloud; nothing else creates or edits them. The
  record set (verified against live DNS 2026-08-17): A records at the apex, todo, exploring-elan,
  and fiddlesticks, plus www (currently a CNAME to the apex). The design doc says "six" — reconcile
  the count in the Hostinger panel before the DNS adoption.
- Docker Compose is the only process manager on the box — no systemd app units, no PM2.
- Each hostname serves exactly its assigned target: vawagners.cloud (static), todo.vawagners.cloud
  (proxy to todo:8787), exploring-elan.vawagners.cloud (static client + /api/* to myron-api:3001),
  fiddlesticks.vawagners.cloud (static).
- A blank box can clone millwright without any credential.

## Cross-cutting constraints
- Provider `hostinger/hostinger = 0.1.22` limits on `hostinger_dns_record`: no import, no in-place
  update (every field ForceNew), `overwrite: false` hardcoded — adopting existing records requires
  deleting them in the panel first.
- Let's Encrypt issues at most five duplicate certificates per week — the certificate volume backup
  exists to keep rebuild tests under this limit.
- Box hardware: 2 cores, 7.8 GB RAM, 96 GB disk, no swap. Nothing scheduled on the box may assume
  more.
- Billing is annual; destroying the subscription forfeits prepaid months and the IP address.
