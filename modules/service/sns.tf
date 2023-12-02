module "label_topic" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "events"
}

resource "aws_sns_topic" "notifications" {
  name = module.label_topic.id
  tags = module.label_topic.tags
}

data "aws_iam_policy_document" "notification_publish" {
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
}

resource "aws_iam_policy" "notification_publish" {
  name   = module.label_topic.id
  tags   = module.label_topic.tags
  path   = "/"
  policy = data.aws_iam_policy_document.notification_publish.json
}