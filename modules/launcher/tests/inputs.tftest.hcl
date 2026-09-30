# Offline tests (mocked AWS): the launcher builds its ECS service and log group ARNs
# from names (no plan-time lookups) and optionally announces launches.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  context = {
    attributes     = []
    dns_namespace  = "test"
    environment    = "test"
    instance       = "test"
    instance_short = "t"
    namespace      = "brd"
    region         = "us-east-1"
    region_short   = "ue1"
    role           = "test"
    role_short     = "t"
    project        = "launcher"
    tags           = {}
  }
  ecs_cluster              = "test-cluster"
  ecs_service              = "test-service"
  trigger_cloudwatch_group = "/aws/route53/example.com"
  trigger_filter_pattern   = "\"play.example.com\""
}

run "arns_are_built_from_names_without_lookups" {
  command = plan

  assert {
    condition     = toset(data.aws_iam_policy_document.ecs_svc_update.statement[0].resources) == toset(["arn:aws:ecs:us-east-1:111111111111:service/test-cluster/test-service"])
    error_message = "The ECS grant must target the service ARN built from the cluster and service names."
  }
  assert {
    condition     = aws_lambda_permission.launcher_cw_invoke.source_arn == "arn:aws:logs:us-east-1:111111111111:log-group:/aws/route53/example.com:*"
    error_message = "The invoke permission must target the log group ARN built from its name."
  }
  assert {
    condition     = aws_cloudwatch_log_subscription_filter.launcher_cw_domain_filter.log_group_name == "/aws/route53/example.com"
    error_message = "The subscription filter must name the trigger log group."
  }
}

run "no_launch_events_by_default" {
  command = plan

  assert {
    condition     = !contains(keys(aws_lambda_function.launcher.environment[0].variables), "EVENTS_TOPIC_ARN")
    error_message = "Without launch_events the Lambda gets no EVENTS_TOPIC_ARN."
  }
  assert {
    condition     = length(aws_iam_policy.events_publish) == 0 && length(aws_iam_role_policy_attachment.events_publish) == 0
    error_message = "Without launch_events the Lambda gets no sns:Publish grant."
  }
}

run "launch_events_enable_the_notice" {
  command = plan

  variables {
    launch_events = { topic_arn = "arn:aws:sns:us-east-1:111111111111:events" }
  }

  assert {
    condition     = aws_lambda_function.launcher.environment[0].variables["EVENTS_TOPIC_ARN"] == "arn:aws:sns:us-east-1:111111111111:events"
    error_message = "The Lambda must receive EVENTS_TOPIC_ARN."
  }
  assert {
    condition = alltrue([
      length(aws_iam_policy.events_publish) == 1,
      toset(data.aws_iam_policy_document.events_publish[0].statement[0].actions) == toset(["sns:Publish"]),
      toset(data.aws_iam_policy_document.events_publish[0].statement[0].resources) == toset(["arn:aws:sns:us-east-1:111111111111:events"]),
    ])
    error_message = "The Lambda may publish only to the events topic."
  }
}
