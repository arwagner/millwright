#!/bin/bash
# millwright bootstrap — turns a blank Ubuntu 24.04 box into a Compose host.
# Run over SSH (ssh root@187.124.159.132 'bash -s' < bootstrap.sh) or as the
# Hostinger post-install script. Idempotent: safe to run twice.
set -euo pipefail

REPO_URL="https://github.com/arwagner/millwright.git" # public: no credential needed
REPO_DIR="/srv/millwright"
AUTHORIZED_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKuqHCorCH62/+wfZI2sgSPjrDjNgKpPdgp21sWiHHKf wagner.andrew@gmail.com"

# --- SSH: keys only, no passwords ------------------------------------------
mkdir -p /root/.ssh && chmod 700 /root/.ssh
grep -qF "$AUTHORIZED_KEY" /root/.ssh/authorized_keys 2>/dev/null ||
  echo "$AUTHORIZED_KEY" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
# A drop-in that sorts first: cloud-init ships 50-cloud-init.conf with
# "PasswordAuthentication yes", and sshd takes the FIRST match across the
# included files — editing the main sshd_config alone does not win.
printf 'PasswordAuthentication no\n' > /etc/ssh/sshd_config.d/00-millwright.conf
systemctl restart ssh

# --- Firewall: only SSH and Caddy answer from the internet ------------------
apt-get update -qq
apt-get install -y -qq ufw git curl rsync
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# --- Docker Engine + Compose plugin ----------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# --- Secrets directory (files copied from Dropbox in runbook step 6) --------
mkdir -p /srv/secrets
chmod 700 /srv/secrets

# --- Clone the configuration (public repo, no credentials) ------------------
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

echo "bootstrap complete. Next: deploy sources, copy secrets, restore data,"
echo "then: cd $REPO_DIR && docker compose up -d --build"
