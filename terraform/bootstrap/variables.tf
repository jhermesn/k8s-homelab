variable "aws_region" {
  description = "Região AWS onde o bucket do state é criado"
  type        = string
}

variable "bucket_name" {
  description = "Nome do bucket S3 do state (globalmente único)"
  type        = string
}
