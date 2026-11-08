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

# ---- feat-001/AC-2: exactly the seven records (chg-002 adds tiamat, chg-003 practice), all -> the box IP
check feat-001/AC-2 "exactly 7 dns records"         bash -c '[ "$(grep -c "resource \"hostinger_dns_record\"" terraform/dns.tf)" = 7 ]'
for n in '"@"' '"www"' '"todo"' '"exploring-elan"' '"fiddlesticks"' '"tiamat"' '"practice"'; do
  check feat-001/AC-2 "record name $n"              grep -q "name  = $n" terraform/dns.tf
done
check feat-001/AC-2 "all records -> 187.124.159.132" bash -c '[ "$(grep -c "value = local.ip" terraform/dns.tf)" = 7 ] && grep -q "ip   = \"187.124.159.132\"" terraform/dns.tf'

# ---- feat-001/AC-3: bootstrap syntax + docker, ufw, keys, clone, sshd
check feat-001/AC-3 "bash -n bootstrap.sh"          bash -n bootstrap.sh
check feat-001/AC-3 "installs docker"               grep -q docker-compose-plugin bootstrap.sh
check feat-001/AC-3 "ufw allow only 22/80/443"      bash -c 'grep -q "ufw default deny incoming" bootstrap.sh && grep -q "ufw allow 22/tcp" bootstrap.sh && grep -q "ufw allow 80/tcp" bootstrap.sh && grep -q "ufw allow 443/tcp" bootstrap.sh && [ "$(grep -c "ufw allow" bootstrap.sh)" = 3 ]'
check feat-001/AC-3 "writes authorized_keys"        grep -q authorized_keys bootstrap.sh
check feat-001/AC-3 "credential-free https clone"   bash -c 'grep -q "https://github.com/arwagner/millwright.git" bootstrap.sh && ! grep -E "https://[^\"]*@" bootstrap.sh'
check feat-001/AC-3 "PasswordAuthentication no"     grep -q "PasswordAuthentication no" bootstrap.sh

# ---- feat-001/AC-4: compose valid, four services + restart, ports only on caddy
S=$(mktemp -d); touch "$S/todo.env" "$S/myron-api.env" "$S/myron-bot.env" "$S/practice-auth.env"
CJSON=$(docker run --rm -v "$PWD":/w -w /w -v "$S":/srv/secrets docker:cli docker compose config --format json 2>/dev/null)
# The same, with env files left as references (the resolved form merges them into environment).
CJSON_REFS=$(docker run --rm -v "$PWD":/w -w /w -v "$S":/srv/secrets docker:cli docker compose config --no-env-resolution --format json 2>/dev/null)
rm -rf "$S"
check feat-001/AC-4 "compose config valid"          test -n "$CJSON"
check feat-001/AC-4 "services + restart + ports only on caddy" bash -c "echo \"\$1\" | python3 -c '
import json,sys
s=json.load(sys.stdin)[\"services\"]
assert set(s) == {\"caddy\",\"todo\",\"myron-api\",\"myron-bot\",\"practice\"}, set(s)
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

# ---- feat-001/AC-5: caddyfile valid, five hostnames + www redirect
check feat-001/AC-5 "caddy validate"                docker run --rm -v "$PWD/caddy/Caddyfile":/etc/caddy/Caddyfile:ro caddy:2 caddy validate --config /etc/caddy/Caddyfile
for h in vawagners.cloud todo.vawagners.cloud exploring-elan.vawagners.cloud fiddlesticks.vawagners.cloud tiamat.vawagners.cloud practice.vawagners.cloud; do
  check feat-001/AC-5 "site $h"                     grep -q "^$h" caddy/Caddyfile
done
check feat-001/AC-5 "www redirects to apex"         bash -c 'grep -A1 "^www.vawagners.cloud" caddy/Caddyfile | grep -q "redir https://vawagners.cloud"'

# ---- feat-001/AC-12 (chg-002): tiamat wiki served read-only from a host path
check feat-001/AC-12 "caddy mounts /var/www/tiamat read-only" bash -c "echo \"\$1\" | python3 -c '
import json,sys
m=[v for v in json.load(sys.stdin)[\"services\"][\"caddy\"][\"volumes\"] if v.get(\"source\")==\"/var/www/tiamat\"]
assert len(m)==1 and m[0][\"target\"]==\"/srv/tiamat\" and m[0].get(\"read_only\"), m
'" _ "$CJSON"
check feat-001/AC-12 "tiamat site serves /srv/tiamat" bash -c 'grep -A2 "^tiamat.vawagners.cloud" caddy/Caddyfile | grep -q "root \* /srv/tiamat"'

# ---- feat-001/AC-13 (chg-003): practice service — internal-only, private read-only sources, local volume, pinned
check feat-001/AC-13 "practice service shape" bash -c "echo \"\$1\" | python3 -c '
import json,sys
c=json.load(sys.stdin); p=c[\"services\"][\"practice\"]
assert p.get(\"container_name\")==\"practice\" and p.get(\"restart\")==\"unless-stopped\"
assert not p.get(\"ports\"), p.get(\"ports\")
assert list(p[\"networks\"])==[\"practice\"], p[\"networks\"]
assert c[\"networks\"][\"practice\"].get(\"internal\") is True
assert set(c[\"services\"][\"caddy\"][\"networks\"])=={\"default\",\"practice\"}
for k,v in c[\"services\"].items():
    if k not in (\"caddy\",\"practice\"): assert \"practice\" not in (v.get(\"networks\") or {}), k
e=p[\"environment\"]
assert e[\"PRACTICE_PUBLIC_ORIGIN\"]==\"https://practice.vawagners.cloud\" and e[\"PRACTICE_BIND\"]==\"0.0.0.0\"
assert e[\"PRACTICE_EXPORTER\"]==\"sidecar\" and e[\"TZ\"]==\"America/New_York\"
assert not any(\"AUTH\" in k or \"PASS\" in k or \"TOKEN\" in k for k in e), sorted(e)
assert not p.get(\"env_file\"), \"practice needs no secret\"
vols=p[\"volumes\"]
data=[v for v in vols if v[\"type\"]==\"volume\"]
assert len(data)==1 and data[0][\"source\"]==\"practice-data\" and data[0][\"target\"]==e[\"PRACTICE_HOME\"]
binds={v[\"source\"]:v for v in vols if v[\"type\"]==\"bind\"}
assert set(binds)=={\"/srv/practice/sources\",\"/srv/practice/exports\"}, set(binds)
assert all(b.get(\"read_only\") and b.get(\"bind\",{}).get(\"create_host_path\") is False for b in binds.values())
assert any(t.startswith(\"/run/practice:\") and \"mode=0700\" in t for t in p.get(\"tmpfs\",[]))
d=p[\"build\"][\"dockerfile_inline\"]
assert \"FROM node:24.16.0-bookworm-slim@sha256:\" in d and \"USER node\" in d and \"npm ci --omit=dev\" in d
assert p[\"build\"][\"context\"]==\"/opt/practice/app\"
assert p.get(\"mem_limit\") and p.get(\"cpus\")
'" _ "$CJSON"
check feat-001/AC-13 "practice-data declared as a volume" bash -c "echo \"\$1\" | python3 -c '
import json,sys
assert \"practice-data\" in json.load(sys.stdin).get(\"volumes\",{})
'" _ "$CJSON"

# ---- feat-001/AC-14 (chg-003): practice site behind basic auth; credentials only from /srv/secrets
check feat-001/AC-14 "caddy reads practice-auth.env (required)" bash -c "echo \"\$1\" | python3 -c '
import json,sys
ef=json.load(sys.stdin)[\"services\"][\"caddy\"][\"env_file\"]
m=[f for f in ef if f[\"path\"]==\"/srv/secrets/practice-auth.env\"]
assert len(m)==1 and m[0].get(\"required\",True) is not False, ef
'" _ "$CJSON_REFS"
check feat-001/AC-14 "practice block: basic_auth placeholders, proxy, no Authorization upstream (chg-004: two basic_auth, two proxies)" bash -c 'b=$(sed -n "/^practice.vawagners.cloud {/,/^}/p" caddy/Caddyfile); grep -q "basic_auth {" <<<"$b" && grep -q "{\$PRACTICE_AUTH_USER} {\$PRACTICE_AUTH_HASH}" <<<"$b" && grep -q "reverse_proxy practice:8770" <<<"$b" && grep -q "header_up -Authorization" <<<"$b" && ! grep -qi "permissions-policy" <<<"$b"'
check feat-001/AC-14 "no bcrypt hash or practice password in tracked files" bash -c '! git ls-files -z | xargs -0 grep -lE "\\\$2[aby]\\\$[0-9]{2}\\\$[./A-Za-z0-9]{53}|PRACTICE_AUTH_(HASH|USER)=['"'"'\"]?[^ <%'"'"'\"]" 2>/dev/null | grep .'

# ---- feat-001/AC-17 (chg-004): practice sign-in page + cookie beside basic auth; secret only from /srv/secrets
PB='b=$(sed -n "/^practice.vawagners.cloud {/,/^}/p" caddy/Caddyfile)'
check feat-001/AC-17 "sign-in page tracked and mounted read-only into caddy" bash -c "test -f caddy/practice-signin/signin.html && echo \"\$1\" | python3 -c '
import json,sys
v=json.load(sys.stdin)[\"services\"][\"caddy\"][\"volumes\"]
m=[x for x in v if x.get(\"target\")==\"/srv/practice-signin\"]
assert len(m)==1 and m[0][\"source\"].endswith(\"/caddy/practice-signin\") and m[0].get(\"read_only\") is True, m
'" _ "$CJSON"
check feat-001/AC-17 "only /signin is public; it serves signin.html from the mount" bash -c "$PB"'; grep -q "handle /signin {" <<<"$b" && grep -A4 "handle /signin {" <<<"$b" | grep -q "root \* /srv/practice-signin" && grep -A4 "handle /signin {" <<<"$b" | grep -q "rewrite \* /signin.html" && [ "$(grep -c "^	handle" <<<"$b")" = 5 ]'
check feat-001/AC-17 "/signin/check: route keeps basic_auth before Set-Cookie" bash -c "$PB"'; c=$(sed -n "/handle \/signin\/check {/,/^	}/p" <<<"$b"); grep -q "route {" <<<"$c" && [ "$(grep -n basic_auth <<<"$c" | cut -d: -f1)" -lt "$(grep -n "Set-Cookie" <<<"$c" | cut -d: -f1)" ] && grep -q "practice_session={\$PRACTICE_SESSION_SECRET}; Path=/; Secure; HttpOnly; SameSite=Lax" <<<"$c"'
check feat-001/AC-17 "cookie matcher anchored to the secret, refused when the secret is missing" bash -c "$PB"'; grep -qF "header_regexp Cookie (^|;\s*)practice_session={\$PRACTICE_SESSION_SECRET}(;|\$)" <<<"$b" && grep -qF "expression \`\"{\$PRACTICE_SESSION_SECRET}\".matches(\"^[0-9a-f]{64}\$\")\`" <<<"$b"'
check feat-001/AC-17 "neither cookie nor Authorization reaches the app" bash -c "$PB"'; [ "$(grep -c "reverse_proxy practice:8770" <<<"$b")" = 2 ] && [ "$(grep -c "header_up -Cookie" <<<"$b")" = 2 ] && [ "$(grep -c "header_up -Authorization" <<<"$b")" = 2 ]'
check feat-001/AC-17 "no credentials: 401 keeps WWW-Authenticate, body leads to /signin" bash -c "$PB"'; grep -qF "header WWW-Authenticate \"Basic realm=\\\"restricted\\\"\"" <<<"$b" && grep -q "url=/signin" <<<"$b" && grep -qE "</p>\` 401$" <<<"$b"'
check feat-001/AC-17 "practice-auth.sh makes and rotates a 64-hex secret, never printed" bash -c 'grep -q "openssl rand -hex 32" scripts/practice-auth.sh && grep -q -- "--session-secret" scripts/practice-auth.sh && grep -q -- "--rotate-session-secret" scripts/practice-auth.sh && ! grep -E "echo[^#]*\\\$SECRET|printf[^>]*\\\$SECRET[^>]*$" scripts/practice-auth.sh | grep .'
check feat-001/AC-17 "no session secret value in tracked files" bash -c '! git ls-files -z | xargs -0 grep -lE "PRACTICE_SESSION_SECRET=['"'"'\"]?[0-9a-fA-F]{8}" 2>/dev/null | grep .'
check feat-001/AC-17 "README: sign-in apply, rollback, rotation" bash -c 'grep -q "^### Sign-in page" README.md && grep -q -- "--rotate-session-secret" README.md && grep -q "signs out every device" README.md && grep -q "PRACTICE_SESSION_SECRET" README.md'

# ---- feat-001/AC-15 (chg-003): practice backup through the app; verified; restore script
check feat-001/AC-15 "bash -n practice scripts"     bash -c 'for s in practice-backup practice-restore practice-rollback practice-auth; do bash -n scripts/$s.sh && test -x scripts/$s.sh || exit 1; done'
check feat-001/AC-15 "backup asks the running app (admin socket), never sqlite3 or the live file" bash -c 'grep -q "docker exec \"\$CONTAINER\" node src/admin.js backup" scripts/practice-backup.sh && ! grep -E "sqlite3 [^.]|\.backup|data/practice\.sqlite|restored-" scripts/practice-backup.sh | grep -v "^#" | grep -v "import sqlite3" | grep .'
check feat-001/AC-15 "backup re-verifies sha256, integrity, counts; manifest published last" bash -c 'grep -q "hashlib.sha256" scripts/practice-backup.sh && grep -q "PRAGMA integrity_check" scripts/practice-backup.sh && grep -q "PRAGMA foreign_key_check" scripts/practice-backup.sh && grep -q "table_counts" scripts/practice-backup.sh && [ "$(grep -n "^mv -n" scripts/practice-backup.sh | tail -1 | grep -c MAN)" = 1 ]'
check feat-001/AC-15 "backup.sh runs the practice backup" grep -q 'practice-backup.sh' scripts/backup.sh
check feat-001/AC-15 "restore refuses a running service" grep -q 'ps --status running -q practice' scripts/practice-restore.sh
check feat-001/AC-15 "restore goes through the app's import-backup (no overwrite), fresh staging" bash -c 'grep -q "node src/cli.js import-backup" scripts/practice-restore.sh && grep -q "IMPORT_ROOT/\$ID" <(sed "s/\"//g" scripts/practice-restore.sh) && ! grep -qE "^[^#]*mv -n" scripts/practice-restore.sh'
check feat-001/AC-15 "rollback decides authority from the data and records first" bash -c 'grep -q "compare-history" scripts/practice-rollback.sh && grep -q "src/cli.js inventory" scripts/practice-rollback.sh && grep -q "ambiguous" scripts/practice-rollback.sh && ! grep -q "NO_POINTER_EXISTING_STATE" scripts/practice-rollback.sh && [ "$(grep -n "^note started_at" scripts/practice-rollback.sh | cut -d: -f1)" -lt "$(grep -n "COMPOSE stop practice" scripts/practice-rollback.sh | cut -d: -f1)" ]'

# ---- feat-001/AC-16 (chg-003): runbook covers practice delivery, cutover and rollback
check feat-001/AC-16 "README practice section" bash -c 'grep -q "^## Practice" README.md && grep -q "src/cli.js retire --to https://practice.vawagners.cloud" README.md && grep -q "unretired" README.md && grep -q "scripts/practice-rollback.sh" README.md && grep -q "never started before this" README.md && grep -q "practice-restore.sh" README.md && grep -q "practice-auth.env" README.md'

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
check feat-001/AC-8 "no practice data or private notation tracked" bash -c '! git ls-files | grep -E "\.(sqlite|sqlite-journal|mscz|musicxml)$|(^|/)retired\.json$" | grep .'
check feat-001/AC-8 "no secret VALUES assigned in tracked files" bash -c '! git ls-files -z 2>/dev/null | xargs -0 grep -lE "(TODO_TOKEN|DISCORD_BOT_TOKEN|OPENROUTER_API_KEY|LITELLM_MASTER_KEY|CHANNEL_WHITELIST|DM_WHITELIST)=[A-Za-z0-9]" 2>/dev/null | grep .'

# ---- feat-001/AC-9: README runbook + MCP snippet + two-file note
check feat-001/AC-9 "nine-step runbook"             bash -c 'grep -q "^9\. " README.md && grep -q "Rebuild runbook" README.md'
check feat-001/AC-9 "claude.json MCP snippet"       bash -c 'grep -q "docker exec -i todo" README.md && grep -q "\.claude\.json" README.md'
check feat-001/AC-9 "two-file new-service note"     grep -q "Adding a service" README.md

echo
if [ "$fail" = 0 ]; then echo "verify: ALL GREEN"; else echo "verify: FAILURES ABOVE"; exit 1; fi
