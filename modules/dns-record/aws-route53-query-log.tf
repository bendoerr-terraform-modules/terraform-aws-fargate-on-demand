resource "aws_cloudwatch_log_group" "query" {
  count = local.create_log_group ? 1 : 0

  name              = "/aws/route53/${local.zone_name}"
  tags              = module.label_logs.tags
  retention_in_days = var.query_log_retention_days

  #tfsec:ignore:aws-cloudwatch-log-group-customer-key
  kms_key_id = ""
}

data "aws_iam_policy_document" "query" {
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

resource "aws_cloudwatch_log_resource_policy" "query" {
  count = local.configure_resource_policy ? 1 : 0

  policy_document = data.aws_iam_policy_document.query.json
  policy_name     = module.label_logs.id
}

resource "aws_route53_query_log" "query" {
  count = var.configure_query_log ? 1 : 0

  zone_id                  = local.zone_id
  cloudwatch_log_group_arn = local.query_log_group_arn
  depends_on               = [aws_cloudwatch_log_group.query]
}
