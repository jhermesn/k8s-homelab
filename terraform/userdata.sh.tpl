#!/bin/bash
set -euo pipefail

TAILSCALE_AUTHKEY=$(aws ssm get-parameter --name "${tailscale_authkey_ssm_param}" --with-decryption --query Parameter.Value --output text)
JOIN_COMMAND=$(aws ssm get-parameter --name "${kubeadm_join_ssm_param}" --with-decryption --query Parameter.Value --output text)

curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey "$TAILSCALE_AUTHKEY" --ssh

eval "$JOIN_COMMAND"
