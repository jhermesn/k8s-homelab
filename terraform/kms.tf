data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ssm_kms" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

# checkov:skip=CKV_AWS_111: "*" numa key policy = "esta chave", não "todo
# recurso", é assim que key policy funciona, não tem outro jeito de referenciar.
# checkov:skip=CKV_AWS_356: mesmo motivo, resource "*" é o próprio CMK.
# checkov:skip=CKV_AWS_109: kms:* pro root é o boilerplate "Enable IAM User
# Permissions" que a AWS gera por padrão, restringir não reduz risco real
# (root sempre pode alterar a key policy de qualquer forma) e arrisca lockout.
resource "aws_kms_key" "ssm" {
  description         = "CMK para os parâmetros SSM do worker Spot (Tailscale authkey, kubeadm join)"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.ssm_kms.json
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/k8s-homelab-ssm"
  target_key_id = aws_kms_key.ssm.key_id
}
