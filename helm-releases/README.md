# Helm releases aplicados manualmente

## Cilium
cilium install --set ipv4.enabled=true --set ipv6.enabled=true \
  --set ipam.mode=kubernetes --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.1.7 --set k8sServicePort=6443

## ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace

## cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set installCRDs=true
