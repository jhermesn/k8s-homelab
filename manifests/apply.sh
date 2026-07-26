#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
source .env
set +a

envsubst < manifests/cert-manager/clusterissuer.yaml | kubectl apply -f -
kubectl apply -f manifests/gateway-api/gateway.yaml
envsubst < manifests/cloudflare-tunnel/cloudflared.yaml | kubectl apply -f -
envsubst < manifests/cluster-autoscaler/cluster-autoscaler.yaml | kubectl apply -f -
kubectl apply -f manifests/rbac/terraform-rbac.yaml
