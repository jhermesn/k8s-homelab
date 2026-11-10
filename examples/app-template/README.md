# Template de app

Referência pra subir uma app nova no cluster. Não é aplicado por `apply.sh`/`cd.sh`.
Copiar, ajustar, aplicar manualmente.

```bash
cp -r examples/app-template apps/minha-app   # fora do apply.sh de propósito
```

Editar em `app.yaml`:
- `image`: pinar por digest (`image@sha256:...`), nunca `:latest`.
- `hostnames` do `HTTPRoute`: subdomínio real.
- `containerPort`/`targetPort`/probes: porta real da app (e a porta no
  `toPorts` do `CiliumNetworkPolicy`).
- `CiliumNetworkPolicy`: só permite ingress vindo do Gateway (entity `ingress`,
  o Envoy do Cilium), ajustar se a app precisar receber de outro lugar.
  `NetworkPolicy` com `namespaceSelector` não funciona aqui.

Depois de aplicar (`kubectl apply -f apps/minha-app/app.yaml`):

1. Criar o registro DNS no Cloudflare: CNAME `minha-app` → `<TUNNEL_ID>.cfargotunnel.com`.
2. Zero Trust Access: configurar o subdomínio na CloudFlare.  