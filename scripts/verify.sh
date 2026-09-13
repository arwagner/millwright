#!/bin/bash
# millwright offline verification — one labeled check per acceptance criterion
# of feat-001 (spec/features/vps-rebuild/spec.md). Runs on the laptop, touches
# nothing live. AC-10 is the manual post-cutover check and is not here.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
ok()   { echo "PASS $1 — $2"; }
bad()  { echo "FAIL $1 — $2"; fail=1; }
check(){ # check <token> <description> <command...>
  local t="$1" d="$2"; shift 2
  if "$@" >/dev/null 2>&1; then ok "$t" "$d"; else bad "$t" "$d"; fi
}

# ---- feat-001/AC-1: terraform valid, provider pinned, no vps resource, .pub only
check feat-001/AC-1 "terraform validate"            terraform -chdir=terraform validate
check feat-001/AC-1 "provider pinned = 0.1.22"      grep -q 'version = "= 0.1.22"' terraform/main.tf
check feat-001/AC-1 "no hostinger_vps resource"     bash -c '! grep -q "resource \"hostinger_vps\"" terraform/*.tf'
check feat-001/AC-1 "ssh key ref ends in .pub"      bash -c 'grep -q "file(\"~/.ssh/id_ed25519.pub\")" terraform/ssh.tf && ! grep -E "file\(.*id_ed25519\"\)" terraform/ssh.tf'

# ---- feat-001/AC-2: exactly the five records, all -> the box IP
check feat-001/AC-2 "exactly 5 dns records"         bash -c '[ "$(grep -c "resource \"hostinger_dns_record\"" terraform/dns.tf)" = 5 ]'
for n in '"@"' '"www"' '"todo"' '"exploring-elan"' '"fiddlesticks"'; do
  check feat-001/AC-2 "record name $n"              grep -q "name  = $n" terraform/dns.tf
done
check feat-001/AC-2 "all records -> 187.124.159.132" bash -c '[ "$(grep -c "value = local.ip" terraform/dns.tf)" = 5 ] && grep -q "ip   = \"187.124.159.132\"" terraform/dns.tf'

# ---- feat-001/AC-3: bootstrap syntax + docker, ufw, keys, clone, sshd
check feat-001/AC-3 "bash -n bootstrap.sh"          bash -n bootstrap.sh
check feat-001/AC-3 "installs docker"               grep -q docker-compose-plugin bootstrap.sh
check feat-001/AC-3 "ufw allow only 22/80/443"      bash -c 'grep -q "ufw default deny incoming" bootstrap.sh && grep -q "ufw allow 22/tcp" bootstrap.sh && grep -q "ufw allow 80/tcp" bootstrap.sh && grep -q "ufw allow 443/tcp" bootstrap.sh && [ "$(grep -c "ufw allow" bootstrap.sh)" = 3 ]'
check feat-001/AC-3 "writes authorized_keys"        grep -q authorized_keys bootstrap.sh
check feat-001/AC-3 "credential-free https clone"   bash -c 'grep -q "https://github.com/arwagner/millwright.git" bootstrap.sh && ! grep -E "https://[^\"]*@" bootstrap.sh'
check feat-001/AC-3 "PasswordAuthentication no"     grep -q "PasswordAuthentication no" bootstrap.sh

# ---- feat-001/AC-4: compose valid, four services + restart, ports only on caddy
S=$(mktemp -d); touch "$S/todo.env" "$S/myron-api.env" "$S/myron-bot.env"
CJSON=$(docker run --rm -v "$PWD":/w -w /w -v "$S":/srv/secrets docker:cli docker compose config --format json 2>/dev/null)
rm -rf "$S"
check feat-001/AC-4 "compose config valid"          test -n "$CJSON"
check feat-001/AC-4 "services + restart + ports only on caddy" bash -c "echo \"\$1\" | python3 -c '
import json,sys
s=json.load(sys.stdin)[\"services\"]
assert set(s) == {\"caddy\",\"todo\",\"myron-api\",\"myron-bot\"}, set(s)
assert all(v.get(\"restart\")==\"unless-stopped\" for v in s.values())
assert [k for k,v in s.items() if v.get(\"ports\")] == [\"caddy\"]
'" _ "$CJSON"
check feat-001/AC-4 "litellm only in comments"      bash -c 'grep -q "# litellm:" compose.yaml && ! echo "$CJSON" | grep -q litellm'

# ---- feat-001/AC-11 (chg-001): myron-api keeps accounts in a named volume, runs as production
check feat-001/AC-11 "account db in a named volume, outside the image" bash -c "echo \"\$1\" | python3 -c '
import json,sys
api=json.load(sys.stdin)[\"services\"][\"myron-api\"]
mounts=api.get(\"volumes\",[])
auth=[m for m in mounts if m.get(\"type\")==\"volume\" and m.get(\"source\")==\"myron-auth\"]
assert len(auth)==1, mounts
target=auth[0][\"target\"].rstrip(\"/\")
env=api.get(\"environment\",{})
path=env.get(\"AUTH_DB_PATH\",\"\")
assert path.startswith(target+\"/\"), (path, target)
assert env.get(\"NODE_ENV\")==\"production\", env.get(\"NODE_ENV\")
assert not api.get(\"ports\"), api.get(\"ports\")
'" _ "$CJSON"
check feat-001/AC-11 "myron-auth declared as a volume"  bash -c "echo \"\$1\" | python3 -c '
import json,sys
assert \"myron-auth\" in json.load(sys.stdin).get(\"volumes\",{})
'" _ "$CJSON"

# ---- feat-001/AC-5: caddyfile valid, four hostnames + www redirect
check feat-001/AC-5 "caddy validate"                docker run --rm -v "$PWD/caddy/Caddyfile":/etc/caddy/Caddyfile:ro caddy:2 caddy validate --config /etc/caddy/Caddyfile
for h in vawagners.cloud todo.vawagners.cloud exploring-elan.vawagners.cloud fiddlesticks.vawagners.cloud; do
  check feat-001/AC-5 "site $h"                     grep -q "^$h" caddy/Caddyfile
done
check feat-001/AC-5 "www redirects to apex"         bash -c 'grep -A1 "^www.vawagners.cloud" caddy/Caddyfile | grep -q "redir https://vawagners.cloud"'

# ---- feat-001/AC-6: rebuild.sh uses recreate, never touches the subscription
check feat-001/AC-6 "bash -n rebuild.sh"            bash -n scripts/rebuild.sh
check feat-001/AC-6 "calls recreate endpoint"       grep -q '/recreate' scripts/rebuild.sh
check feat-001/AC-6 "no subscription mutation"      bash -c '! grep -iE "curl.*(cancel|purchase|subscription|-X *DELETE)" scripts/rebuild.sh'
check feat-001/AC-6 "token in header, not URL"      bash -c 'grep -q "Authorization: Bearer" scripts/rebuild.sh && ! grep -iE "curl.*[?&]token=" scripts/rebuild.sh && ! grep -E "^[[:space:]]*set -x" scripts/rebuild.sh'

# ---- feat-001/AC-7: backup.sh atomic snapshot + launchd documented
check feat-001/AC-7 "bash -n backup.sh"             bash -n scripts/backup.sh
check feat-001/AC-7 "atomic sqlite .backup in container" bash -c 'grep -q "docker exec todo sqlite3" scripts/backup.sh && grep -q "\.backup" scripts/backup.sh'
check feat-001/AC-7 "copies caddy cert volume"      grep -q caddy-data scripts/backup.sh
check feat-001/AC-7 "README documents launchd"      bash -c 'grep -q launchctl README.md && grep -q com.millwright.backup README.md'

# ---- feat-001/AC-8: no secret can enter the public repo
check feat-001/AC-8 "gitignore covers secret files" bash -c '[ "$(git check-ignore backend.hcl terraform/backend.hcl terraform.tfstate probe.env sub/dir/probe.env | wc -l)" -eq 5 ]'
check feat-001/AC-8 "pre-commit hook active"        bash -c 'test -x .githooks/pre-commit && [ "$(git config core.hooksPath)" = ".githooks" ]'
check feat-001/AC-8 "hook rejects a staged .env"    bash -c 'touch probe.env && git add -f probe.env && ! .githooks/pre-commit; r=$?; git rm --cached -q probe.env; rm -f probe.env; exit $r'
check feat-001/AC-8 "no key material in files"      bash -c '! grep -rInE "sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AAAA[A-Za-z0-9+/]{60,}==?[^ ]|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY" --exclude-dir=.git --exclude-dir=.terraform --exclude-dir=.scratchpad --exclude-dir=node_modules .'
check feat-001/AC-8 "litellm keys via env only"     bash -c '[ "$(grep -c "os.environ/" litellm/config.yaml)" -ge 8 ] && ! grep -E "(master_key|api_key): *[^o[:space:]]" litellm/config.yaml'
check feat-001/AC-8 "no secret VALUES assigned in tracked files" bash -c '! git ls-files -z 2>/dev/null | xargs -0 grep -lE "(TODO_TOKEN|DISCORD_BOT_TOKEN|OPENROUTER_API_KEY|LITELLM_MASTER_KEY|CHANNEL_WHITELIST|DM_WHITELIST)=[A-Za-z0-9]" 2>/dev/null | grep .'

# ---- feat-001/AC-9: README runbook + MCP snippet + two-file note
check feat-001/AC-9 "nine-step runbook"             bash -c 'grep -q "^9\. " README.md && grep -q "Rebuild runbook" README.md'
check feat-001/AC-9 "claude.json MCP snippet"       bash -c 'grep -q "docker exec -i todo" README.md && grep -q "\.claude\.json" README.md'
check feat-001/AC-9 "two-file new-service note"     grep -q "Adding a service" README.md

echo
if [ "$fail" = 0 ]; then echo "verify: ALL GREEN"; else echo "verify: FAILURES ABOVE"; exit 1; fi
