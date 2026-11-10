#!/bin/bash
set -euo pipefail

# setup.sh para provisionamento OS-level do control plane (Ubuntu Server)
# Pré-requisito: rede já configurada (netplan/wifi) e usuário sudo já logado.
# Rodar como usuário normal com sudo, não como root.
# Idempotente: pode rodar de novo a qualquer momento pra convergir o estado.

log() { echo -e "\n>>> $1\n"; }

update_system() {
  log "Atualizando sistema"
  sudo apt update && sudo apt full-upgrade -y
}

configure_hostname_timezone() {
  log "Hostname e timezone"
  sudo timedatectl set-timezone America/Sao_Paulo
}

harden_ssh() {
  log "Hardening SSH (key-only, sem root)"
  sudo sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    /etc/ssh/sshd_config
  sudo systemctl restart ssh
}

setup_firewall() {
  log "UFW - regras base"
  sudo apt install -y ufw
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow OpenSSH

  # Control plane só é alcançado pelos workers via mesh Tailscale,
  # nenhuma dessas portas precisa existir na LAN/WAN. Regra "in on tailscale0" é
  # aceita pelo ufw mesmo antes da interface existir (install_tailscale roda
  # depois); só passa a valer quando subir.
  log "UFW - portas do control plane Kubernetes (restrito a tailscale0)"
  sudo ufw allow in on tailscale0 to any port 6443 proto tcp        # API server
  sudo ufw allow in on tailscale0 to any port 2379:2380 proto tcp   # etcd
  sudo ufw allow in on tailscale0 to any port 10250 proto tcp       # kubelet API
  sudo ufw allow in on tailscale0 to any port 10259 proto tcp       # kube-scheduler
  sudo ufw allow in on tailscale0 to any port 10257 proto tcp       # kube-controller-manager
  sudo ufw allow in on tailscale0 to any port 30000:32767 proto tcp # NodePort range

  sudo ufw --force enable
}

restrict_ssh_to_tailscale() {
  # Rodar SÓ depois de confirmar que o Tailscale está up e a sessão atual
  # não vai travar, testa numa segunda sessão SSH antes de fechar a atual.
  log "Restringindo SSH à interface tailscale0"
  sudo ufw delete allow OpenSSH || true
  sudo ufw allow in on tailscale0 to any port 22 proto tcp
}

setup_fail2ban() {
  log "fail2ban"
  sudo apt install -y fail2ban
  sudo systemctl enable --now fail2ban
}

setup_unattended_upgrades() {
  log "Unattended upgrades (patches de segurança automáticos)"
  sudo apt install -y unattended-upgrades
  sudo dpkg-reconfigure --priority=low unattended-upgrades
}

disable_swap() {
  log "Desabilitando swap (requisito do kubelet)"
  sudo swapoff -a
  sudo sed -i '/swap/d' /etc/fstab
}

mask_sleep_targets() {
  # Laptop clamshell não pode suspender com a tampa fechada.
  log "Mascarando sleep/suspend/hibernate"
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  sudo sed -i 's/#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
  sudo systemctl restart systemd-logind
}

set_cpu_performance() {
  # Sempre na tomada, sem motivo pra correr em powersave/schedutil.
  log "CPU governor -> performance"
  sudo apt install -y linux-tools-common "linux-tools-$(uname -r)" linux-tools-generic
  sudo cpupower frequency-set -g performance

  sudo tee /etc/systemd/system/cpu-performance.service > /dev/null <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g performance

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl enable cpu-performance.service
}

setup_kernel_modules_sysctl() {
  log "Módulos de kernel e sysctl para CNI/kube-proxy"
  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
  sudo modprobe overlay
  sudo modprobe br_netfilter

  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding        = 1
EOF

  # Tailscale seta net.ipv4.conf.all.src_valid_mark=1, o que derruba as respostas
  # dos pods pro Envoy do Cilium Gateway no mesmo nó (503 "connection timeout",
  # cilium/cilium#48706, #47940). accept_local=1 nas veths lxc* contorna; o
  # default é herdado pelas veths criadas depois.
  cat <<EOF | sudo tee /etc/sysctl.d/99-cilium-gateway.conf
net.ipv4.conf.default.accept_local = 1
EOF
  sudo sysctl --system
}

setup_boot_params() {
  log "Boot: SATA LPM desligado e kdump desativado"
  # SATA LPM com DIPM (lpm-pol 3) gera BadCRC/CommWake no link do SSD.
  echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT ahci.mobile_lpm_policy=1"' | \
    sudo tee /etc/default/grub.d/99-homelab.cfg > /dev/null

  # Com root em LUKS o crash kernel não desbloqueia o disco sem senha interativa:
  # o nó ficava preso no initramfs em vez de reiniciar (kernel.panic=10 do kubelet).
  if systemctl cat kdump-tools.service >/dev/null 2>&1; then
    sudo systemctl disable --now kdump-tools
  fi
  for f in /etc/default/grub.d/*.cfg; do
    [ -f "$f" ] || continue
    sudo sed -i 's/^\([^#].*crashkernel=.*\)$/#\1/' "$f"
  done
  sudo update-grub
}

install_containerd() {
  log "containerd (cgroup driver systemd)"
  sudo apt install -y containerd
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sudo systemctl restart containerd
  sudo systemctl enable containerd
}

install_kubeadm_stack() {
  log "kubeadm / kubelet / kubectl"
  sudo apt install -y apt-transport-https ca-certificates curl gpg
  sudo mkdir -p /etc/apt/keyrings

  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
    sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

  sudo apt update
  sudo apt install -y kubelet kubeadm kubectl
  sudo apt-mark hold kubelet kubeadm kubectl
}

install_tailscale() {
  log "Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Rodar manualmente: sudo tailscale up"
}

install_helm() {
  log "Helm"
  # baltocdn.com era o apt repo oficial do Helm, migrou pro Buildkite.
  local key_id="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
  curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey -o /tmp/helm.gpg
  if [ "$(gpg --show-keys --with-colons /tmp/helm.gpg | awk -F: '$1 == "fpr" {print $10}' | head -n1)" != "$key_id" ]; then
    echo "ERRO: fingerprint da chave do Helm não confere" >&2
    exit 1
  fi
  gpg --dearmor < /tmp/helm.gpg | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | \
    sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt update
  sudo apt install -y helm
}

install_cloudflared() {
  log "cloudflared"
  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    -o /tmp/cloudflared.deb
  sudo dpkg -i /tmp/cloudflared.deb
  echo "Rodar manualmente: cloudflared tunnel login && cloudflared tunnel create k8s-cluster"
}

main() {
  update_system
  configure_hostname_timezone
  harden_ssh
  setup_firewall
  setup_fail2ban
  setup_unattended_upgrades
  disable_swap
  mask_sleep_targets
  set_cpu_performance
  setup_kernel_modules_sysctl
  setup_boot_params
  install_containerd
  install_kubeadm_stack
  install_tailscale
  install_helm
  install_cloudflared

  log "OS-level setup completo."
  echo "Pendências manuais:"
  echo "  1. sudo tailscale up  (autenticar na tailnet)"
  echo "  2. restrict_ssh_to_tailscale  (só depois de confirmar Tailscale ativo)"
  echo "  3. DHCP reservation do MAC no roteador."
  echo "  4. kubeadm init + helm-releases/install.sh"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
