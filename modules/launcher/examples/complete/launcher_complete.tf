module "launcher" {
  source                   = "../.."
  context                  = module.context.shared
  ecs_cluster              = module.ecs.cluster_name
  ecs_service              = module.ecs.services[module.label_svc.id].name
  trigger_cloudwatch_group = module.log_group.cloudwatch_log_group_name

  depends_on = [
    module.log_group,
    module.vpc,
    module.ecs
  ]
}