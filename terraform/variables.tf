variable "aws_region" {
  description = "Região AWS onde o worker Spot é criado"
  type        = string
}

variable "instance_type" {
  description = "Tipo de instância Spot (t3.micro, ~53% de desconto sobre on-demand)"
  type        = string
  default     = "t3.micro"
}

variable "tailscale_authkey_ssm_param" {
  description = "Nome do parâmetro SSM SecureString com a authkey do Tailscale"
  type        = string
}

variable "kubeadm_join_ssm_param" {
  description = "Nome do parâmetro SSM SecureString com o kubeadm join command atual"
  type        = string
}

variable "tailscale_authkey" {
  description = "Valor da authkey do Tailscale, Terraform cria o parâmetro SSM com esse valor"
  type        = string
  sensitive   = true
}

variable "kubeadm_join_command" {
  description = "Valor do kubeadm join command atual, Terraform cria o parâmetro SSM com esse valor"
  type        = string
  sensitive   = true
}
