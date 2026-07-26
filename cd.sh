#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# CD único do projeto: cluster on-prem (via Tailscale) + worker Spot AWS.
# Roda em qualquer máquina com acesso à tailnet e credenciais AWS locais
# (aws configure / SSO). Agendar via cron/systemd timer, ou rodar manual.

git pull --ff-only

set -a
source .env
set +a

bash helm-releases/install.sh
bash manifests/apply.sh

(cd terraform && terraform init -backend-config=backend.hcl -input=false && terraform apply -auto-approve)
