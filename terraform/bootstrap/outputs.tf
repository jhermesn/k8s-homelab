output "bucket_name" {
  description = "Nome do bucket, usar em terraform/backend.hcl"
  value       = aws_s3_bucket.state.bucket
}
