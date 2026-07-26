terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state de propósito, isso cria o bucket que o terraform/ principal
  # usa como backend remoto, não dá pra depender dele mesmo aqui.
}

provider "aws" {
  region = var.aws_region
}
