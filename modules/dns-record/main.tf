module "label_ctl" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "rcd-ctl"
}

data "aws_route53_zone" "this" {
  zone_id = var.dns_zone_id
}

data "aws_iam_policy_document" "this" {
  statement {
    effect = "Allow"
    actions = [
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
    ]
    resources = [data.aws_route53_zone.this.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [data.aws_route53_zone.this.arn]
    condition {
      test     = "StringEquals"
      values   = [var.dns_record]
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
    }
  }
}

resource "aws_iam_policy" "this" {
  name   = module.label_ctl.id
  tags   = module.label_ctl.tags
  path   = "/"
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_route53_record" "this" {
  name    = var.dns_record
  zone_id = var.dns_zone_id
  type    = "A"
  ttl     = 30
  records = [var.default_ip_address]
  lifecycle {
    ignore_changes = [records]
  }
}

module "label_logs" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "rcd-logs"
}

# As far as I know, route 53 doesn't support CMK KMS for query logs
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "query" {
  name              = "/aws/route53/${data.aws_route53_zone.this.name}"
  retention_in_days = 3
  tags              = module.label_logs.tags
}

data "aws_caller_identity" "this" {}

data "aws_iam_policy_document" "query_put" {
  statement {
    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogStream",
    ]

    resources = [
      # Must be permissive, and us-east-1 only
      "arn:aws:logs:us-east-1:${data.aws_caller_identity.this.account_id}:log-group:/aws/route53/*"
    ]

    principals {
      identifiers = ["route53.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "query_put" {
  policy_document = data.aws_iam_policy_document.query_put.json
  policy_name     = module.label_logs.id
}

resource "aws_route53_query_log" "query" {
  zone_id                  = var.dns_zone_id
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.query.arn
  depends_on               = [aws_cloudwatch_log_resource_policy.query_put]
}
