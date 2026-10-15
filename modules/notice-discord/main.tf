module "label_notice" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "ntc-dscrd"
}

data "archive_file" "notice" {
  output_path = "${path.module}/notice-discord-lambda-function.zip"
  type        = "zip"
  source_file = "${path.module}/notice-discord-lambda-function.py"
}

resource "aws_lambda_function" "notice" {
  function_name    = module.label_notice.id
  tags             = module.label_notice.tags
  role             = aws_iam_role.notice_role.arn
  handler          = "notice-discord-lambda-function.lambda_handler"
  timeout          = 10
  filename         = data.archive_file.notice.output_path
  source_code_hash = data.archive_file.notice.output_base64sha256
  runtime          = "python3.11"

  kms_key_arn = var.lambda_env_kms_arn
  environment {
    variables = {
      DISCORD_BOT_AUTH_TOKEN = var.discord_bot_auth_token
      DISCORD_CHANNEL_ID     = var.discord_channel_id
      NOTIFY_APP_NAME        = var.notify_app_name
      NOTIFY_APP_URL         = var.notify_app_url
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_permission" "notice_cw_invoke" {
  statement_id  = module.label_notice.id
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notice.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.event_topic_arn
}

resource "aws_sns_topic_subscription" "events" {
  endpoint  = aws_lambda_function.notice.arn
  protocol  = "lambda"
  topic_arn = var.event_topic_arn
}

resource "aws_cloudwatch_log_group" "notice" {
  name              = "/aws/lambda/${module.label_notice.id}"
  retention_in_days = 3
  kms_key_id        = var.lambda_logs_kms_arn
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "notice_role" {
  name               = module.label_notice.id
  tags               = module.label_notice.tags
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

module "label_notice_logs" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "ntc-dscrd-logs"
}

data "aws_iam_policy_document" "notice_logs" {
  statement {
    effect    = "Allow"
    resources = [aws_cloudwatch_log_group.notice.arn]
    actions = [
      "logs:CreateLogGroup",
    ]
  }
  statement {
    effect = "Allow"
    # We cannot know what the name of the stream will be so this wildcard is the minimal permission
    # tfsec:ignore:aws-iam-no-policy-wildcards
    resources = ["${aws_cloudwatch_log_group.notice.arn}:*"]
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_policy" "notice_logs" {
  name   = module.label_notice_logs.id
  tags   = module.label_notice_logs.tags
  path   = "/"
  policy = data.aws_iam_policy_document.notice_logs.json
}

resource "aws_iam_role_policy_attachment" "notice_logs" {
  policy_arn = aws_iam_policy.notice_logs.arn
  role       = aws_iam_role.notice_role.name
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  count = length(var.alarm_topic_arns) > 0 ? 1 : 0

  alarm_name          = "${module.label_notice.id}-errors"
  alarm_description   = "notice-discord failed at least one delivery attempt in the last 5 minutes (a retry may since have succeeded). The ERROR line in its log group gives the cause: HTTP 401 = bot token revoked; 400/403/404 = configuration."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.notice.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  # An event signal, not a state: every failed attempt pages, and the alarm returns to OK
  # silently. No ok_actions, because an OK would read as "resolved" when it only means "no
  # invocations since" (and a new alarm's first OK would page for nothing). A revoked token
  # fails every later notification, so it pages again on the next failure after a quiet
  # period; a burst inside one 300 s window (or spanning its retries) pages once.
  treat_missing_data = "notBreaching"
  alarm_actions      = var.alarm_topic_arns
  tags               = module.label_notice.tags

  lifecycle {
    # A validation block cannot reference another variable below Terraform 1.9; the floor is 1.3.
    precondition {
      condition     = !contains(var.alarm_topic_arns, var.event_topic_arn)
      error_message = "alarm_topic_arns must not include event_topic_arn: the alarm payload has no Event key (the function would fail on it and re-trigger the alarm), and a revoked token cannot report itself through Discord."
    }
  }
}
