terraform {
  required_version = ">= 1.9.0" # floor-reason: cross-variable validation (var.task_memory references var.task_cpu) requires Terraform 1.9
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}