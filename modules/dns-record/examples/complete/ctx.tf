terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "namespace" {
  type = string
}

variable "assume_principal" {
  type = string
  nullable = true
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.4.0"
  namespace   = var.namespace
  environment = "example"
  role        = "dns-record"
  region      = "us-east-1"
  project     = "complete"
}

module "label" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "test"
}


data "aws_caller_identity" "this" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.assume_principal != null ? var.assume_principal : data.aws_caller_identity.this.arn]
    }
  }
}

resource "aws_iam_role" "test" {
  name               = module.label.id
  tags               = module.label.tags
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.test.id
  policy_arn = module.dns_record.record_control_policy_arn
}

output "test_record_control_role_arn" {
  value = aws_iam_role.test.arn
}
