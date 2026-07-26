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

helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm upgrade --install trivy-operator aqua/trivy-operator \
  -n trivy-system --create-namespace \
  --version 0.34.0 -f trivy-operator/values.yaml

helm repo add grafana https://grafana.github.io/helm-charts
envsubst < grafana-k8s-monitoring/values.yaml > /tmp/grafana-k8s-monitoring.rendered.yaml
helm upgrade --install --atomic --timeout 300s grafana-k8s-monitoring grafana/k8s-monitoring \
  -n monitoring --create-namespace \
  --version 4.3.1 -f /tmp/grafana-k8s-monitoring.rendered.yaml