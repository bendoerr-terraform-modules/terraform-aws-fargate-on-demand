module "label_events" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = module.context.shared
  name    = "events"
}

resource "aws_sns_topic" "events" {
  name              = module.label_events.id
  tags              = module.label_events.tags
  kms_master_key_id = "alias/aws/sns"
}

module "launcher" {
  source                   = "../.."
  context                  = module.context.shared
  ecs_cluster              = module.ecs.cluster_name
  ecs_service              = module.ecs.services[module.label_svc.id].name
  trigger_cloudwatch_group = module.log_group.cloudwatch_log_group_name

  # Announce launches (as the service module's events topic would).
  launch_events = { topic_arn = aws_sns_topic.events.arn }

  depends_on = [
    module.log_group,
    module.vpc,
    module.ecs
  ]
}