# Template de app

Referência pra subir uma app nova no cluster. Não é aplicado por `apply.sh`/`cd.sh`.
Copiar, ajustar, aplicar manualmente.

```bash
cp -r examples/app-template apps/minha-app   # fora do apply.sh de propósito
```

Editar em `app.yaml`:
- `image`: pinar por digest (`image@sha256:...`), nunca `:latest`.
- `hostnames` do `HTTPRoute`: subdomínio real.
- `containerPort`/`targetPort`/probes: porta real da app.
- `NetworkPolicy`: só permite ingress do namespace `gateway` (onde o Cilium
  Gateway/Envoy roda), ajustar se a app precisar receber de outro lugar.

Depois de aplicar (`kubectl apply -f apps/minha-app/app.yaml`):

1. Criar o registro DNS no Cloudflare: CNAME `minha-app` → `<TUNNEL_ID>.cfargotunnel.com`.
2. Zero Trust Access: configurar o subdomínio na CloudFlare.  