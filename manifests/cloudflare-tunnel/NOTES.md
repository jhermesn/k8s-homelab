# Notas — Ingress atrás do Cloudflare Tunnel

Todo Ingress exposto via cloudflared precisa de:

    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"

Motivo: cloudflared fala HTTP puro com o ingress-nginx (TLS já foi
terminado na borda da Cloudflare). Sem essas annotations, o ingress-nginx
força redirect HTTPS e gera loop infinito com o túnel.

Zero Trust Application: qualquer subdomínio novo cai automaticamente
sob "Global Protection" (*.jhermesn.dev, policy Admin Access) a menos
que seja explicitamente adicionado em "Rotas Públicas".
