# k8s-homelab

Cluster Kubernetes on-premises (control plane + worker no mesmo node), com
worker Spot sob demanda na AWS, exposto via Cloudflare Tunnel + Zero Trust.

## Arquitetura

```
Internet → Cloudflare Zero Trust → Cloudflare Tunnel (outbound-only)
         → Cilium Gateway API (hostNetwork) → Pod

AWS Spot worker (0-2, sob demanda) → Tailscale mesh → kube-apiserver
```

| Componente | Escolha |
|---|---|
| Control plane | Roda control plane + workloads (sem HA multi-node) |
| Ingress | Cilium Gateway API (`hostNetwork`) |
| CNI | Cilium, dual-stack, kube-proxy replacement (eBPF) |
| TLS | cert-manager + Let's Encrypt (DNS-01 via Cloudflare) |
| Exposição pública | Cloudflare Tunnel |
| Mesh privado | Tailscale |
| Worker extra | Spot `t3.micro` na AWS, escalado pelo cluster-autoscaler |

## Estrutura do repo

```
.env.example        # copiar para .env (gitignored) no master node
cd.sh                # CD: git pull + helm/manifests + terraform apply
os-setup/setup.sh   # provisionamento OS-level (idempotente)
helm-releases/       # Cilium, cert-manager, Trivy Operator, Grafana Alloy (install.sh idempotente)
manifests/           # ClusterIssuer, Gateway, cloudflared, cluster-autoscaler (apply.sh)
terraform/           # worker Spot AWS
examples/app-template/  # referência pra deployar apps novas (não aplicado por apply.sh)
```

## Setup do zero

1. Ubuntu Server fresh install, rede configurada, DHCP reservation no roteador.
2. `bash os-setup/setup.sh` - SO hardening (SSH key-only, UFW restrito a
   `tailscale0`, fail2ban), containerd, kubeadm/kubelet/kubectl, Tailscale,
   Helm, cloudflared. Ver pendências manuais impressas ao final.
3. `kubeadm init` (dual-stack).
4. `cp .env.example .env` e preencher `TUNNEL_ID`, `ACME_EMAIL`,
   `CONTROL_PLANE_LAN_IP`, `AWS_REGION`, `GRAFANA_CLOUD_TOKEN` (requer
   `envsubst`, pacote `gettext-base`).
5. `bash helm-releases/install.sh` - Gateway API CRDs, Cilium, cert-manager,
   Trivy Operator, Grafana Alloy (métricas/logs/traces pro Grafana Cloud).
6. Criar o Secret `cloudflare-api-token` (ver [Secrets](#secrets)), depois
   `bash manifests/apply.sh`.
7. `cloudflared tunnel create` e criar o Secret `cloudflared-creds`.
8. `tailscale up` - adicionar o IP da tailnet como SAN extra no cert do
   apiserver (`kubeadm init phase certs apiserver --apiserver-cert-extra-sans=...`).

Depois disso, `bash cd.sh` mantém tudo sincronizado com o repo, então deve-se rodar
manual ou via cron numa máquina com Tailscale + credenciais AWS.

Se o Gateway responder `503 ... connection timeout` pra pods no mesmo nó, é o
`net.ipv4.conf.all.src_valid_mark=1` do Tailscale interagindo com o Envoy do
Cilium ([cilium/cilium#48706](https://github.com/cilium/cilium/issues/48706)).
O `setup.sh` já aplica o workaround (`net.ipv4.conf.default.accept_local=1`
em `/etc/sysctl.d/99-cilium-gateway.conf`); em nós já provisionados, criar
esse arquivo e setar `accept_local=1` nas veths `lxc*` existentes.

Novas apps: criar `HTTPRoute` apontando pro Gateway `cilium-gateway`
(namespace `gateway`) - sem Ingress, sem annotation de redirect.

## Secrets

Não versionados - criar manualmente:

- `cloudflare-api-token` (ns `cert-manager`): token Cloudflare escopado em
  **Zone** (`DNS:Edit` + `Zone:Read`), restrito ao domínio usado.
- `cloudflared-creds` (ns `cloudflare-tunnel`): `credentials.json` do
  `cloudflared tunnel create`.
- Worker Spot AWS: authkey do Tailscale e kubeadm join command (via
  `terraform.tfvars`, ver [terraform/README.md](terraform/README.md)).
- `aws-secret` (ns `kube-system`): credenciais do cluster-autoscaler, ver
  [terraform/README.md](terraform/README.md#cluster-autoscaler).
- `GRAFANA_CLOUD_TOKEN` (via `.env`): Cloud Access Policy token gerado pelo
  wizard "Connect Kubernetes" do Grafana Cloud.

## Licença

Este projeto está licenciado sob a [Licença MIT](LICENSE).
