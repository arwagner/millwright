#!/bin/bash
# millwright rebuild — reinstalls srv1491903 via the Hostinger `recreate` API.
# Free, keeps the subscription and the IP address (187.124.159.132).
# NEVER touches the subscription itself: no create, no purchase-style setup,
# and nothing that ends the plan (the cancel-tier endpoint) — the VPS resource
# stays under manual control in the Hostinger panel (decision 9).
#
# WARNING: recreate WIPES the box and DELETES Hostinger snapshots. Run
# backup.sh first. Ask-first step (hs-2): only run this on explicit approval.
#
# Requires:
#   HOSTINGER_API_TOKEN  from Dropbox secrets, e.g.:
#     export HOSTINGER_API_TOKEN=$(cat ~/Dropbox/andrew/secrets/millwright/hostinger-api-token)
#   VM_ID        the virtual machine id (list with: $0 --list)
#   TEMPLATE_ID  the OS template id, Ubuntu 24.04 (list with: $0 --templates)
#
# Token goes in the Authorization header only — never in a URL. No set -x.
set -euo pipefail

API="https://developers.hostinger.com/api/vps/v1"
auth=(-H "Authorization: Bearer ${HOSTINGER_API_TOKEN:?export HOSTINGER_API_TOKEN first}")

case "${1:-}" in
--list)
  curl -sfS "${auth[@]}" "$API/virtual-machines"
  echo
  exit 0
  ;;
--templates)
  curl -sfS "${auth[@]}" "$API/templates"
  echo
  exit 0
  ;;
esac

: "${VM_ID:?set VM_ID (find it with: $0 --list)}"
: "${TEMPLATE_ID:?set TEMPLATE_ID (find Ubuntu 24.04 with: $0 --templates)}"

echo "About to RECREATE VM $VM_ID with template $TEMPLATE_ID."
echo "This wipes the box and deletes its snapshots. The IP stays the same."
read -r -p "Type 'rebuild' to proceed: " answer
[ "$answer" = "rebuild" ] || { echo "aborted"; exit 1; }

# Optional: POST_INSTALL_SCRIPT_ID (terraform output post_install_script_id)
# makes the recreate run bootstrap automatically.
payload="{\"template_id\": $TEMPLATE_ID}"
[ -n "${POST_INSTALL_SCRIPT_ID:-}" ] &&
  payload="{\"template_id\": $TEMPLATE_ID, \"post_install_script_id\": $POST_INSTALL_SCRIPT_ID}"

curl -sfS "${auth[@]}" \
  -H "Content-Type: application/json" \
  -X POST "$API/virtual-machines/$VM_ID/recreate" \
  -d "$payload"
echo
echo "recreate requested. When the box is up: ssh root@187.124.159.132 'bash -s' < bootstrap.sh"
