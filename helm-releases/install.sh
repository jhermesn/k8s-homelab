#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

set -a
source ../.env
set +a

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

envsubst < cilium/values.yaml > /tmp/cilium-values.rendered.yaml
if helm status cilium -n kube-system >/dev/null 2>&1; then
  cilium upgrade --version 1.19.5 -f /tmp/cilium-values.rendered.yaml
else
  cilium install --version 1.19.5 -f /tmp/cilium-values.rendered.yaml
fi

helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --version v1.21.0 -f cert-manager/values.yaml