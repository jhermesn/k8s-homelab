resource "aws_ssm_parameter" "tailscale_authkey" {
  name   = var.tailscale_authkey_ssm_param
  type   = "SecureString"
  value  = var.tailscale_authkey
  key_id = aws_kms_key.ssm.arn
}

resource "aws_ssm_parameter" "kubeadm_join_command" {
  name   = var.kubeadm_join_ssm_param
  type   = "SecureString"
  value  = var.kubeadm_join_command
  key_id = aws_kms_key.ssm.arn
}
