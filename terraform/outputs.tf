output "autoscaling_group_name" {
  description = "Nome do ASG do worker Spot"
  value       = aws_autoscaling_group.spot_worker.name
}
