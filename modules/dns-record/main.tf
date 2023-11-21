module "label" {
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
  name   = module.label.id
  tags   = module.label.tags
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