resource "aws_route53_zone" "this" {
  count   = var.create_zone ? 1 : 0
  name    = var.zone_name
  comment = var.zone_comment != null ? var.zone_comment : module.label.id
  tags    = module.label.tags
}

data "aws_route53_zone" "this" {
  count   = var.create_zone ? 0 : 1
  zone_id = var.zone_id
}

resource "aws_route53_record" "this" {
  name    = var.record_name
  zone_id = local.zone_id
  type    = "A"
  ttl     = var.record_ttl
  records = [var.record_default]
  lifecycle {
    ignore_changes = [records]
  }
}

# Route53 Actions Reference:
# https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonroute53.html
data "aws_iam_policy_document" "this" {
  statement {
    effect = "Allow"
    actions = [
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
    ]
    resources = [local.zone_arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [local.zone_arn]
    condition {
      test     = "StringEquals"
      values   = [aws_route53_record.this.name]
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
