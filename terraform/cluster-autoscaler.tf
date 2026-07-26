# checkov:skip=CKV_AWS_273: credencial de máquina pra workload rodando fora
# da AWS (cluster-autoscaler no k8s on-prem, sem IRSA/instance-profile
# disponível), SSO/Identity Center é pra sign-in humano no console, não se
# aplica aqui. Alternativa real seria federar OIDC do cluster on-prem com a
# AWS, complexidade desproporcional pro caso de uso.
resource "aws_iam_user" "cluster_autoscaler" {
  name = "k8s-cluster-autoscaler"
}

resource "aws_iam_access_key" "cluster_autoscaler" {
  user = aws_iam_user.cluster_autoscaler.name
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "Describe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
    ]
    resources = ["*"] # describe/list da AWS não suportam resource-level scoping
  }

  statement {
    sid    = "ScaleOwnASG"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = [aws_autoscaling_group.spot_worker.arn]
  }
}

resource "aws_iam_group" "cluster_autoscaler" {
  name = "k8s-cluster-autoscaler"
}

resource "aws_iam_group_policy" "cluster_autoscaler" {
  name   = "cluster-autoscaler"
  group  = aws_iam_group.cluster_autoscaler.name
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_iam_group_membership" "cluster_autoscaler" {
  name  = "k8s-cluster-autoscaler"
  group = aws_iam_group.cluster_autoscaler.name
  users = [aws_iam_user.cluster_autoscaler.name]
}

output "cluster_autoscaler_access_key_id" {
  description = "AWS_ACCESS_KEY_ID do Secret aws-secret (kube-system) do cluster-autoscaler"
  value       = aws_iam_access_key.cluster_autoscaler.id
}

output "cluster_autoscaler_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY do Secret aws-secret (kube-system) do cluster-autoscaler"
  value       = aws_iam_access_key.cluster_autoscaler.secret
  sensitive   = true
}
