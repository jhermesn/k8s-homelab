resource "aws_iam_role" "spot_worker" {
  name = "k8s-spot-worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

data "aws_iam_policy_document" "spot_worker_ssm_read" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.tailscale_authkey.arn,
      aws_ssm_parameter.kubeadm_join_command.arn,
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.ssm.arn]
  }
}

resource "aws_iam_role_policy" "spot_worker_ssm_read" {
  name   = "read-bootstrap-params"
  role   = aws_iam_role.spot_worker.id
  policy = data.aws_iam_policy_document.spot_worker_ssm_read.json
}

resource "aws_iam_instance_profile" "spot_worker" {
  name = "k8s-spot-worker"
  role = aws_iam_role.spot_worker.name
}
