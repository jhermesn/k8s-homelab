#!/bin/bash
set -euo pipefail

# Cilium
cilium install --version 1.19.5 -f cilium/values.yaml

# ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --version 4.15.1 -f ingress-nginx/values.yaml

# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --version v1.21.0 -f cert-manager/values.yaml \
  --set crds.enabled=true
