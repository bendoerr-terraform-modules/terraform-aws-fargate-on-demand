module "label_alarms" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "alarms"
}

# Separate from aws_sns_topic.notifications: the notice Lambdas parse custodian
# lifecycle JSON off that topic and would fail on CloudWatch alarm payloads.
#
# If var.sns_kms_key_id is a customer-managed KMS key, that key's own key
# policy must separately grant the cloudwatch.amazonaws.com service principal
# kms:Decrypt and kms:GenerateDataKey* (this module does not manage the key
# policy). The AWS-managed alias/aws/sns key cannot be used here: CloudWatch
# alarms are not able to publish through it.
#
# Gated on var.alarm_enabled: count (not for_each) so the enabled path keeps a
# single, stable [0] address (see the `moved` blocks below migrating from the
# pre-alarm_enabled unindexed addresses).
resource "aws_sns_topic" "alarms" {
  count = var.alarm_enabled ? 1 : 0

  name              = module.label_alarms.id
  tags              = module.label_alarms.tags
  kms_master_key_id = var.sns_kms_key_id
}

# Grants cloudwatch.amazonaws.com sns:Publish (scoped to alarms in this
# account/region), plus an owner statement so the topic owner (this account,
# via its own identity policies) keeps the ability to read/manage the topic.
# SNS:SetTopicAttributes/AddPermission/RemovePermission/DeleteTopic are
# intentionally left out of this resource policy: Terraform's own management
# of this topic is authorized by the applying principal's IAM identity policy
# in-account, not by this topic's resource policy, so granting those actions
# here again (to "AWS": "*", scoped only by aws:SourceOwner) would be
# redundant privilege. Without the CloudWatch statement, CloudWatch's publish
# attempt is denied and alarm_email_endpoints subscribers are never notified.
data "aws_iam_policy_document" "alarms_topic" {
  count = var.alarm_enabled ? 1 : 0

  statement {
    sid    = "__default_statement_ID"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "SNS:GetTopicAttributes",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]

    resources = [aws_sns_topic.alarms[0].arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowCloudWatchAlarmsPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alarms[0].arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${var.context.region}:${data.aws_caller_identity.current.account_id}:alarm:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  count = var.alarm_enabled ? 1 : 0

  arn    = aws_sns_topic.alarms[0].arn
  policy = data.aws_iam_policy_document.alarms_topic[0].json
}

resource "aws_sns_topic_subscription" "alarms_email" {
  for_each = var.alarm_enabled ? toset(var.alarm_email_endpoints) : toset([])

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "max_runtime" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name        = module.label_alarms.id
  tags              = module.label_alarms.tags
  alarm_description = "Fires when the service has emitted CPUUtilization datapoints for ${var.max_runtime_hours} consecutive hour(s), i.e. it has been running continuously past max_runtime_hours."

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.svc.name
    ServiceName = aws_ecs_service.svc.name
  }

  statistic           = "SampleCount"
  period              = 3600
  evaluation_periods  = var.max_runtime_hours
  datapoints_to_alarm = var.max_runtime_hours
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms[0].arn]
}

# Existing state for the enabled path (var.alarm_enabled defaults to true)
# moves from these resources' pre-alarm_enabled unindexed addresses to their
# new [0] addresses, rather than destroying and recreating them.
moved {
  from = aws_sns_topic.alarms
  to   = aws_sns_topic.alarms[0]
}

moved {
  from = aws_sns_topic_policy.alarms
  to   = aws_sns_topic_policy.alarms[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.max_runtime
  to   = aws_cloudwatch_metric_alarm.max_runtime[0]
}
