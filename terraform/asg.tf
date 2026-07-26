data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_launch_template" "spot_worker" {
  # checkov:skip=CKV_AWS_88: IP público requerido: sem NAT Gateway/instance
  # (custaria mais que o próprio worker), única forma de egress pra Tailscale/apt/SSM.
  # Sem risco de exposição pois o security group nega toda entrada, então nada escuta.
  name_prefix   = "k8s-spot-worker-"
  image_id      = data.aws_ssm_parameter.ubuntu.value
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.spot_worker.id]
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.spot_worker.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  # Spot é configurado via instances_distribution no ASG (mixed_instances_policy),
  # não aqui, instance_market_options conflita com mixed_instances_policy.
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    tailscale_authkey_ssm_param = var.tailscale_authkey_ssm_param
    kubeadm_join_ssm_param      = var.kubeadm_join_ssm_param
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "k8s-spot-worker" }
  }
}

resource "aws_autoscaling_group" "spot_worker" {
  name                = "k8s-spot-worker"
  min_size            = 0
  max_size            = 2
  desired_capacity    = 0
  vpc_zone_identifier = aws_subnet.public[*].id
  capacity_rebalance  = true

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0
      spot_allocation_strategy                 = "price-capacity-optimized"
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.spot_worker.id
        version            = "$Latest"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "k8s-spot-worker"
    propagate_at_launch = true
  }

  # Tags de auto-discovery do cluster-autoscaler (manifests/cluster-autoscaler/)
  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/k8s-homelab"
    value               = "owned"
    propagate_at_launch = false
  }

  # desired_capacity é escalado pelo cluster-autoscaler
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
