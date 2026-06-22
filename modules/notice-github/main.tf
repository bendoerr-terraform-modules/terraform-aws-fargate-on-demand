module "label_notice" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.0"
  context = var.context
  name    = "ntc-gh"
}

data "archive_file" "notice" {
  output_path = "${path.module}/notice-github-lambda-function.zip"
  type        = "zip"
  source_file = "${path.module}/notice-github-lambda-function.py"
}

resource "aws_lambda_function" "notice" {
  function_name    = module.label_notice.id
  tags             = module.label_notice.tags
  role             = aws_iam_role.notice_role.arn
  handler          = "notice-github-lambda-function.lambda_handler"
  timeout          = 15
  filename         = data.archive_file.notice.output_path
  source_code_hash = data.archive_file.notice.output_base64sha256
  runtime          = "python3.11"

  kms_key_arn = var.lambda_env_kms_arn
  environment {
    variables = {
      GITHUB_TOKEN    = var.github_token
      GITHUB_REPO     = var.github_repo
      GITHUB_BRANCH   = var.github_branch
      STATE_FILE_PATH = var.state_file_path
      NOTIFY_APP_NAME = var.notify_app_name
      NOTIFY_APP_URL  = var.notify_app_url
    }
  }

  tracing_config {
    mode = "Active"
  }

  lifecycle {
    precondition {
      condition     = !startswith(var.github_token, "param:") || var.github_token_ssm_param_arn != null
      error_message = "When github_token uses 'param:<name>', github_token_ssm_param_arn must be set so the Lambda role can read and decrypt that parameter."
    }
  }
}

resource "aws_lambda_permission" "notice_sns_invoke" {
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
  # Subscribe only after SNS may invoke the Lambda, else early events drop.
  depends_on = [aws_lambda_permission.notice_sns_invoke]
}

resource "aws_cloudwatch_log_group" "notice" {
  name              = "/aws/lambda/${module.label_notice.id}"
  retention_in_days = 3
  # No customer-managed KMS key: org house style is AWS-managed encryption
  # everywhere (a CMK buys no security over the AWS-managed key while costing
  # ~$1/mo/key). AWS-managed encryption still applies at rest.
  # trivy:ignore:AVD-AWS-0017
  kms_key_id = var.lambda_logs_kms_arn
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
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.0"
  context = var.context
  name    = "ntc-gh-logs"
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

# --- SSM read for the GitHub token --------------------------------------------
# Only provisioned when the token is supplied as `param:<name>` AND the consumer
# passes the parameter's ARN, so the grant is scoped to exactly that one
# parameter. Literal-token usage (e.g. the example/test) provisions nothing.

module "label_notice_ssm" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.0"
  context = var.context
  name    = "ntc-gh-ssm"
}

# Resolve the default `alias/aws/ssm` key ARN so the decrypt grant can be scoped
# to the exact key rather than a wildcard. Only needed when the token parameter
# uses the AWS-managed key (no CMK supplied).
data "aws_kms_alias" "ssm" {
  count = var.github_token_ssm_param_arn != null && var.github_token_kms_key_arn == null ? 1 : 0
  name  = "alias/aws/ssm"
}

data "aws_iam_policy_document" "notice_ssm" {
  count = var.github_token_ssm_param_arn != null ? 1 : 0

  statement {
    sid       = "ReadGithubToken"
    effect    = "Allow"
    resources = [var.github_token_ssm_param_arn]
    actions   = ["ssm:GetParameter"]
  }

  # Decrypt the SecureString, scoped to the specific key: the supplied CMK, or
  # the resolved default `alias/aws/ssm` key. No wildcard.
  statement {
    sid       = "DecryptGithubToken"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.github_token_kms_key_arn != null ? var.github_token_kms_key_arn : one(data.aws_kms_alias.ssm[*].target_key_arn)]
  }
}

resource "aws_iam_policy" "notice_ssm" {
  count  = var.github_token_ssm_param_arn != null ? 1 : 0
  name   = module.label_notice_ssm.id
  tags   = module.label_notice_ssm.tags
  path   = "/"
  policy = data.aws_iam_policy_document.notice_ssm[0].json
}

resource "aws_iam_role_policy_attachment" "notice_ssm" {
  count      = var.github_token_ssm_param_arn != null ? 1 : 0
  policy_arn = aws_iam_policy.notice_ssm[0].arn
  role       = aws_iam_role.notice_role.name
}
