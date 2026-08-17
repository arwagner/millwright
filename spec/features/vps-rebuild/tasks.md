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
- [H] T11: DNS adoption (hs-1) — reconcile the record list in the Hostinger panel against plan D2
  (design doc said six, live shows five), confirm `myron/api/.env` on the box is empty, then on
  approval: delete the panel records and run the first `terraform apply`.
- [H] T12: Cutover (hs-2) — on approval, on a free evening: fresh backup, `rebuild.sh`,
  `bootstrap.sh`, deploy myron (rsync, `--exclude='*.png'`) and todo (git push), copy secrets to
  `/srv/secrets/` and `chmod 700 /srv/secrets && chmod 600 /srv/secrets/*.env`, restore todo.db +
  cert volume, `docker compose up -d --build`, then run the
  AC-10 manual checks (four hostnames, `ps` free of TODO_TOKEN, no pm2/nginx/ollama). Rotate the
  litellm master key.
