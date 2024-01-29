module "label_state" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.1"
  context = var.context
  name    = "state"
}

resource "aws_ssm_parameter" "state" {
  name        = module.label_state.id
  type        = "String"
  value       = "{}"
  description = "${module.label_state.id}: Last State Event"
  tier        = "Standard"
  tags        = module.label_state.tags
  lifecycle {
    ignore_changes = [value]
  }
}

module "label_notice" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.1"
  context = var.context
  name    = "ntc-ssm-ps"
}

data "archive_file" "notice" {
  output_path = "${path.module}/notice-ssm-ps-lambda-function.zip"
  type        = "zip"
  source_file = "${path.module}/notice-ssm-ps-lambda-function.py"
}

resource "aws_lambda_function" "notice" {
  function_name    = module.label_notice.id
  tags             = module.label_notice.tags
  role             = aws_iam_role.notice_role.arn
  handler          = "notice-ssm-ps-lambda-function.lambda_handler"
  timeout          = 10
  filename         = data.archive_file.notice.output_path
  source_code_hash = data.archive_file.notice.output_base64sha256
  runtime          = "python3.11"

  kms_key_arn = var.lambda_env_kms_arn
  environment {
    variables = {
      PARAM_STORE_KEY = aws_ssm_parameter.state.name
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
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.1"
  context = var.context
  name    = "ntc-ssm-ps-logs"
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

data "aws_iam_policy_document" "ssm_ps" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]
    resources = [
      aws_ssm_parameter.state.arn,
    ]
  }
}

resource "aws_iam_policy" "ssm_ps" {
  name        = module.label_state.id
  tags        = module.label_state.tags
  path        = "/"
  description = "${module.label_state.id}: Allows access to SSM Parameters for event state"
  policy      = data.aws_iam_policy_document.ssm_ps.json
}

resource "aws_iam_role_policy_attachment" "ssm_ps" {
  policy_arn = aws_iam_policy.ssm_ps.arn
  role       = aws_iam_role.notice_role.name
}
