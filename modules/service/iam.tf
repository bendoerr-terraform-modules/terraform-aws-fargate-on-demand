data "aws_iam_policy_document" "svc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_control" {
  statement {
    effect  = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = [
      // arn:${Partition}:ecs:${Region}:${Account}:service/${ClusterName}/${ServiceName}
      aws_ecs_service.svc.id,
    ]
  }

  statement {
    effect  = "Allow"
    actions = [
      "ecs:DescribeTasks",
      "ecs:UpdateService",
    ]
    resources = [
      // arn:${Partition}:ecs:${Region}:${Account}:task/${ClusterName}/${TaskId}
      // Need to build this since there isn't a TF representation
      "arn:aws:ecs:${var.context.region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.svc.name}/*"
    ]
  }

  statement {
    effect  = "Allow"
    actions = [
      "ec2:DescribeNetworkInterfaces"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:Region"
      values   = [var.context.region]
    }
  }
}

resource "aws_iam_policy" "ecs_control" {
  name   = module.label_ctl.id
  tags   = module.label_ctl.tags
  path   = "/"
  policy = data.aws_iam_policy_document.ecs_control.json
}


resource "aws_iam_role" "svc" {
  name               = module.label.id
  tags               = module.label.tags
  assume_role_policy = data.aws_iam_policy_document.svc_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_efs" {
  role       = aws_iam_role.svc.name
  policy_arn = var.persistence_access_policy_arn
}

resource "aws_iam_role_policy_attachment" "task_ctrl" {
  role       = aws_iam_role.svc.name
  policy_arn = aws_iam_policy.ecs_control.arn
}


resource "aws_iam_role_policy_attachment" "mc_task_route53" {
  role       = aws_iam_role.svc.name
  policy_arn = var.record_control_policy_arn
}

resource "aws_iam_role_policy_attachment" "mc_task_sns" {
  role       = aws_iam_role.svc.name
  policy_arn = aws_iam_policy.notification_publish.arn
}

data "aws_iam_policy_document" "mc_task_cw" {
  statement {
    effect  = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.svc.arn}:*"]
  }
}

module "label_logs" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "logs"
}

resource "aws_iam_policy" "mc_task_logs" {
  name   = module.label_logs.id
  tags   = module.label_logs.tags
  path   = "/"
  policy = data.aws_iam_policy_document.mc_task_cw.json
}

resource "aws_iam_role_policy_attachment" "mc_task_logs" {
  role       = aws_iam_role.svc.name
  policy_arn = aws_iam_policy.mc_task_logs.arn
}

