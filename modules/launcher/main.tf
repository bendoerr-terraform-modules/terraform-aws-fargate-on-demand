module "label_launcher" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "lnchr"
}

data "archive_file" "launcher" {
  output_path = "${path.module}/aws-launcher-lambda-function.zip"
  type        = "zip"
  source_file = "${path.module}/aws-launcher-lambda-function.py"
}

resource "aws_lambda_function" "launcher" {
  function_name    = module.label_launcher.id
  tags             = module.label_launcher.tags
  role             = aws_iam_role.launcher_role.arn
  handler          = "aws-launcher-lambda-function.lambda_handler"
  timeout          = var.lambda_timeout
  filename         = data.archive_file.launcher.output_path
  source_code_hash = data.archive_file.launcher.output_base64sha256
  runtime          = var.lambda_python_runtime
  kms_key_arn      = var.lambda_env_kms_arn

  environment {
    variables = {
      ECS_REGION  = var.context.region
      ECS_CLUSTER = var.ecs_cluster
      ECS_SERVICE = var.ecs_service
    }
  }

  tracing_config {
    mode = var.lambda_tracing_config
  }
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "launcher_cw_invoke" {
  statement_id   = module.label_launcher.id
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.launcher.function_name
  principal      = "logs.${var.context.region}.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = "${data.aws_cloudwatch_log_group.domain_logs.arn}:*"
}

data "aws_cloudwatch_log_group" "domain_logs" {
  name = var.trigger_cloudwatch_group
}

resource "aws_cloudwatch_log_subscription_filter" "launcher_cw_domain_filter" {
  depends_on      = [aws_lambda_permission.launcher_cw_invoke]
  destination_arn = aws_lambda_function.launcher.arn
  filter_pattern  = var.trigger_filter_pattern
  log_group_name  = data.aws_cloudwatch_log_group.domain_logs.name
  name            = module.label_launcher_logs.id
}

resource "aws_cloudwatch_log_group" "launcher" {
  name              = "/aws/lambda/${module.label_launcher.id}"
  retention_in_days = var.lambda_logs_retention
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

resource "aws_iam_role" "launcher_role" {
  name               = module.label_launcher.id
  tags               = module.label_launcher.tags
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

module "label_launcher_logs" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "lnchr-logs"
}

data "aws_iam_policy_document" "launcher_logs" {
  statement {
    effect    = "Allow"
    resources = [aws_cloudwatch_log_group.launcher.arn]
    actions = [
      "logs:CreateLogGroup",
    ]
  }
  statement {
    effect = "Allow"
    # We cannot know what the name of the stream will be so this wildcard is the minimal permission
    # tfsec:ignore:aws-iam-no-policy-wildcards
    resources = ["${aws_cloudwatch_log_group.launcher.arn}:*"]
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_policy" "launcher_logs" {
  name   = module.label_launcher_logs.id
  tags   = module.label_launcher_logs.tags
  path   = "/"
  policy = data.aws_iam_policy_document.launcher_logs.json
}

resource "aws_iam_role_policy_attachment" "launcher_logs" {
  policy_arn = aws_iam_policy.launcher_logs.arn
  role       = aws_iam_role.launcher_role.name
}

data "aws_ecs_cluster" "cluster" {
  cluster_name = var.ecs_cluster
}

data "aws_ecs_service" "svc" {
  cluster_arn  = data.aws_ecs_cluster.cluster.arn
  service_name = var.ecs_service
}

data "aws_iam_policy_document" "ecs_svc_update" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = [
      // arn:${Partition}:ecs:${Region}:${Account}:service/${ClusterName}/${ServiceName}
      data.aws_ecs_service.svc.id
    ]
  }
}

module "label_ecs_svc_update" {
  source  = "git@github.com:bendoerr/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "lnchr-ecs-ctl"
}

resource "aws_iam_policy" "svc_control" {
  name   = module.label_ecs_svc_update.id
  tags   = module.label_ecs_svc_update.tags
  path   = "/"
  policy = data.aws_iam_policy_document.ecs_svc_update.json
}

resource "aws_iam_role_policy_attachment" "launcher_ecs" {
  policy_arn = aws_iam_policy.svc_control.arn
  role       = aws_iam_role.launcher_role.name
}
