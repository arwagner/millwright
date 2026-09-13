# Tasks — Rebuild srv1491903 from code (feat-001)

Glyphs: `[x]` done · `[ ]` not started · `[~]` in progress · `[-]` n/a · `[H]` human-gated.
`[P]` = can run in parallel with its peers (after T1).

- [x] T1: Initialize the repo: `git init`; write `.gitignore` (backend.hcl, `terraform.tfstate*`,
  `*.env` at any depth, `.terraform/`, `.scratchpad/`); install a pre-commit hook that rejects
  staged `*.env`, `backend.hcl`, and `*tfstate*` files; write the README skeleton. Files:
  `.gitignore`, `.githooks/pre-commit` (+ `git config core.hooksPath .githooks`), `README.md`.
  (AC-8 partial)
- [x] T2 [P]: Write `terraform/main.tf` (provider `hostinger/hostinger`, pinned `= 0.1.22`),
  `terraform/dns.tf` (the five records per plan D2), `terraform/ssh.tf`
  (`hostinger_vps_ssh_key`, fed a `.pub` public-key file only), `terraform/bootstrap.tf`
  (`hostinger_vps_post_install_script`), and `terraform/backend.hcl.example`. Write the real
  gitignored `terraform/backend.hcl` pointing at Dropbox. Run `terraform init -backend=false` +
  `terraform validate`. (AC-1, AC-2)
- [x] T3 [P]: Write `bootstrap.sh`: docker + compose plugin install, ufw allow 22/80/443 and
  default deny incoming, user + `authorized_keys`, `PasswordAuthentication no` in sshd_config,
  credential-free HTTPS clone of millwright. (AC-3)
- [x] T4 [P]: Write `compose.yaml` per plan D4 (four services, dockerfile_inline, env_file from
  `/srv/secrets/`, restart policies, todo-data + caddy-data + myron-client-dist volumes, ports
  only on caddy, litellm commented out, todo image adds sqlite3, base-image digest-pin note).
  (AC-4)
- [x] T5 [P]: Fetch `/var/www/vawagners` and the fiddlesticks content from the box read-only
  (scp); write `sites/vawagners/` and `sites/fiddlesticks/`; write `caddy/Caddyfile` per plan D3
  including the www redirect, serving exploring-elan from the myron-client-dist volume. (AC-5)
- [x] T6 [P]: Write `scripts/rebuild.sh`: curl the Hostinger `recreate` endpoint with
  `template_id`, token from env. No subscription create/destroy/cancel. (AC-6)
- [x] T7 [P]: Write `scripts/backup.sh` (atomic sqlite `.backup` via docker exec over ssh; copy
  snapshot + caddy-data volume to Dropbox) and `scripts/com.millwright.backup.plist`. (AC-7)
- [x] T8 [P]: Fetch the litellm config read-only from the box; write `litellm/config.yaml` cold
  storage with `master_key` read from env, never inline; grep the fetched file for any stray
  third-party API key before committing. (AC-8 partial)
- [x] T9: Write the full `README.md`: the nine-step rebuild runbook (step 6 includes
  `chmod 700 /srv/secrets && chmod 600 /srv/secrets/*.env`), the `~/.claude.json` todo MCP
  snippet, the new-service two-file note, the launchd install line, the secrets table (names
  only), and the named risks: Dropbox compromise = TLS private-key compromise (reissue is the
  mitigation), and Hostinger account 2FA as the root of trust. (AC-7 partial, AC-9)
- [x] T10: Write `scripts/verify.sh` running every offline check from the plan's verification
  table, each printing its `feat-001/AC-N` token; run it and get all green. Also confirm AC-8's
  secret scan passes. (AC-1..AC-9)
- [x] T11: DNS adoption (hs-1) — DONE 2026-08-17. Panel held seven records (five real + dead n8n
  and llm); Andrew approved dropping the two and deleted all seven in the panel; first
  `terraform apply` recreated the five records + SSH key + post-install stub (id 5136); all five
  hostnames verified resolving on the authoritative nameservers. Note: Cloudflare's WAF 403s the
  full bootstrap.sh as post-install content, so the uploaded script is a stub that fetches it
  from the public repo (see terraform/bootstrap.tf). `myron/api/.env` emptiness check moved to
  T12 pre-cutover (it belongs there).
- [x] T12: Cutover (hs-2) — DONE 2026-08-17, approved and observed by Andrew. Harvested secrets,
  todo.db (cold, service stopped), and source trees to Dropbox first; recreated via the API
  (template 1077, post-install stub ran bootstrap); restored sources, secrets (chmod 700/600),
  and todo.db; `docker compose up -d --build` brought up all four services. AC-10 verified: same
  IP, four hostnames 200 over fresh HTTPS certs, www redirects, `ps` clean of TODO_TOKEN,
  pm2/nginx/ollama absent, MCP adapter answers via docker exec. Notes: TODO_TOKEN was re-minted
  (the old one lived only in the wiped box's root env); Books deliberately not restored to the
  box (deferred-work item 1 done by omission); cert volume backup + laptop launchd job installed
  and proven with one real run. Original step list, for reference: fresh backup, `rebuild.sh`,
  `bootstrap.sh`, deploy myron and todo, copy secrets, restore data, compose up, then run the
  AC-10 manual checks (four hostnames, `ps` free of TODO_TOKEN, no pm2/nginx/ollama). Rotate the
  litellm master key.

- [x] T13: Add `scripts/verify.sh` checks for the account volume (chg-001): from
  `docker compose config --format json`, assert `myron-api` mounts `myron-auth`, that its
  `AUTH_DB_PATH` points inside that mount, that `NODE_ENV` is `production`, and that it still
  declares no `ports:`. Each prints `feat-001/AC-11`. (AC-11)
- [x] T14: Note in `README.md` that exploring-elan's accounts live in the `myron-auth` volume and
  are not restored by a rebuild — recreate them with
  `docker compose exec myron-api npm run users -- add <name>`. Fold into the existing runbook step 7
  rather than adding a step: AC-9 asserts the runbook has nine. (AC-9, AC-11)
