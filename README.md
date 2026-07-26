# k8s-homelab

Cluster Kubernetes on-premises (control plane + worker no mesmo node) com nodes
spot remotos, exposto com segurança via Cloudflare Tunnel + Zero Trust.

## Arquitetura

```
Internet → Cloudflare (Zero Trust Access) → Cloudflare Tunnel (outbound-only)
         → ingress-nginx (ClusterIP) → Service → Pod

Spot nodes (AWS) → Tailscale mesh → kube-apiserver (control plane)
```

- **Control plane**: Lenovo IdeaPad (i3 6th gen, 12GB RAM), Ubuntu Server,
  clamshell na parede, sempre na tomada. Roda control plane + workloads
  (taint removido — sem HA multi-node, não faz sentido isolar).
- **CNI**: Cilium, dual-stack IPv4/IPv6, kube-proxy replacement (eBPF).
- **Ingress**: ingress-nginx.
- **TLS**: cert-manager + Let's Encrypt via DNS-01 (Cloudflare).
- **Exposição pública**: Cloudflare Tunnel — zero portas abertas no roteador.
- **Zero Trust**: Access Applications por hostname (`*.jhermesn.dev` sob
  proteção Admin por padrão; hosts específicos liberados via "Rotas Públicas").
- **Mesh privado**: Tailscale — conecta Mac, control plane e futuros spot
  nodes sem expor a rede local.
- **IaC futura**: Terraform + ServiceAccount RBAC escopado (`kube-system/terraform`).

## Estrutura do repo

```
helm-releases/       # Charts instalados (Cilium, ingress-nginx, cert-manager)
  install.sh          # Script único de reprodução, versões pinadas
  <chart>/values.yaml # Values reais aplicados em cada release

manifests/
  cert-manager/       # ClusterIssuer (Let's Encrypt DNS-01 via Cloudflare)
  cloudflare-tunnel/  # ConfigMap + Deployment do cloudflared, notas de padrão
  rbac/               # ServiceAccount/RBAC escopado para Terraform
```

## Rebuild do zero (disaster recovery)

1. Ubuntu Server fresh install → configura rede (netplan/wifi), DHCP
   reservation no roteador para o MAC da wlp2s0.
2. Swap off, sysctl (`br_netfilter`, `ip_forward`), containerd
   (`SystemdCgroup=true`), kubeadm/kubelet/kubectl instalados e pinados.
3. `kubeadm init` com dual-stack (`podSubnet`/`serviceSubnet` com CIDR v4+v6)
   e `KubeletConfiguration` com `systemReserved`/`kubeReserved`.
4. `bash helm-releases/install.sh` — reinstala Cilium, ingress-nginx,
   cert-manager nas versões pinadas.
5. `kubectl apply -f manifests/cert-manager/clusterissuer.yaml`
   (recriar o Secret `cloudflare-api-token` antes — não versionado, ver abaixo).
6. Recriar o túnel Cloudflare (`cloudflared tunnel create`) e o Secret de
   credenciais, depois `kubectl apply -f manifests/cloudflare-tunnel/`.
7. `kubectl apply -f manifests/rbac/terraform-rbac.yaml`.
8. Tailscale: `tailscale up`, adicionar IP como SAN extra no cert do
   apiserver (`kubeadm init phase certs apiserver --apiserver-cert-extra-sans=...`).

## Secrets (não versionados — recriar manualmente)

- `cloudflare-api-token` (namespace `cert-manager`): token Cloudflare
  escopado em **Zone** (não Account) — `Zone:DNS:Edit` + `Zone:Zone:Read`,
  restrito à zona `jhermesn.dev`.
- `cloudflared-creds` (namespace `cloudflare-tunnel`): `credentials.json`
  gerado por `cloudflared tunnel create`.

## Notas operacionais

- Todo Ingress atrás do Cloudflare Tunnel precisa de
  `nginx.ingress.kubernetes.io/ssl-redirect: "false"` e
  `force-ssl-redirect: "false"` — evita loop de redirect (TLS público já
  termina na borda da Cloudflare, túnel fala HTTP puro com o ingress-nginx).
- SSH restrito à interface `tailscale0` (UFW), chave-only, sem senha.
- Governor de CPU em `performance` (laptop sempre na tomada).
- Lid switch mascarado (`HandleLidSwitch=ignore`) — cluster roda com a
  tampa fechada.
