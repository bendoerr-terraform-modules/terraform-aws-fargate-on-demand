terraform {
  # floor-reason: modules/service requires >= 1.9.0 (cross-variable validation on task_cpu/task_memory)
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# AWS Provider Configuration
provider "aws" {
  region = "us-east-1"
}
