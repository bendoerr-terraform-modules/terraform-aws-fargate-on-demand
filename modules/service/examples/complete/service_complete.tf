module "fod_dns_record" {
  source  = "../../../dns-record"
  context = module.context.shared

  create_zone = true
  zone_name   = "${lower(var.namespace)}.fod-svc.test"
  record_name = "play.${lower(var.namespace)}.fod-svc.test"
}

module "fod_persistence" {
  source     = "../../../persistence"
  context    = module.context.shared
  subnet_ids = module.vpc.public_subnets
}

# Second service's own record on the same hosted zone as module.fod_dns_record
# (create_zone = false, zone_id reused). configure_query_log is disabled here:
# a hosted zone accepts only one aws_route53_query_log association, and
# module.fod_dns_record already created it.
module "fod_dns_record_mc" {
  source  = "../../../dns-record"
  context = module.context_mc.shared

  create_zone = false
  zone_id     = module.fod_dns_record.zone_id
  record_name = "mc.${lower(var.namespace)}.fod-svc.test"

  configure_query_log = false
}

module "fod_service" {
  source  = "../.."
  context = module.context.shared

  vpc_id             = module.vpc.vpc_id
  service_subnet_ids = module.vpc.public_subnets

  task_cpu    = "256"
  task_memory = "512"

  service_image = "public.ecr.aws/docker/library/alpine:3"

  port_mappings = [
    {
      containerPort = 25565
      hostPort      = 25565
      protocol      = "tcp"
    },
  ]

  environment_variables = []
  secret_variables      = []

  dns_zone_id               = module.fod_dns_record.zone_id
  dns_record                = module.fod_dns_record.record_name
  record_control_policy_arn = module.fod_dns_record.record_control_policy_arn

  data_file_system_id               = module.fod_persistence.file_system_id
  data_access_point_id              = module.fod_persistence.access_point_id
  persistence_access_policy_arn     = module.fod_persistence.access_policy_arn
  persistence_access_security_group = module.fod_persistence.access_security_group

  enable_container_insights = false
  logs_kms_key_id           = null
  sns_kms_key_id            = null
}

# Second service: kind = "minecraft" on ARM64/FARGATE (spec §6.1), reusing
# this example's VPC and persistence (module.fod_persistence), with its own
# DNS record (module.fod_dns_record_mc) and its own context (module.context_mc)
# so its labels/resource names don't collide with the tcp service above.
module "fod_service_mc" {
  source  = "../.."
  context = module.context_mc.shared

  vpc_id             = module.vpc.vpc_id
  service_subnet_ids = module.vpc.public_subnets

  task_cpu    = "256"
  task_memory = "512"

  service_image = "public.ecr.aws/docker/library/alpine:3"

  port_mappings = [
    {
      containerPort = 25565
      hostPort      = 25565
      protocol      = "tcp"
    },
  ]

  environment_variables = []
  secret_variables      = []

  custodian         = { kind = "minecraft" }
  cpu_architecture  = "ARM64"
  capacity_provider = "FARGATE"

  dns_zone_id               = module.fod_dns_record.zone_id
  dns_record                = module.fod_dns_record_mc.record_name
  record_control_policy_arn = module.fod_dns_record_mc.record_control_policy_arn

  data_file_system_id               = module.fod_persistence.file_system_id
  data_access_point_id              = module.fod_persistence.access_point_id
  persistence_access_policy_arn     = module.fod_persistence.access_policy_arn
  persistence_access_security_group = module.fod_persistence.access_security_group

  enable_container_insights = false
  logs_kms_key_id           = null
  sns_kms_key_id            = null
}

output "ecs_cluster_name" {
  value       = module.fod_service.esc_cluster_name
  description = "Name of the ECS cluster."
}

output "ecs_service_name" {
  value       = module.fod_service.esc_service_name
  description = "Name of the ECS service (parked at desired count 0)."
}

output "events_topic_arn" {
  value       = module.fod_service.events_topic_arn
  description = "SNS topic the watchdog publishes lifecycle events to."
}

output "service_role_name" {
  value       = module.fod_service.service_role_name
  description = "Name of the combined task + execution role."
}

output "svc_control_policy_arn" {
  value       = module.fod_service.svc_control_policy_arn
  description = "IAM policy that allows the launcher to control this service."
}

output "alarm_topic_arn" {
  value       = module.fod_service.alarm_topic_arn
  description = "SNS topic the tcp service's max-runtime cost alarm publishes to."
}

output "dns_zone_id" {
  value       = module.fod_dns_record.zone_id
  description = "Route53 hosted zone shared by both services' DNS records."
}

output "mc_dns_record" {
  value       = module.fod_dns_record_mc.record_name
  description = "DNS record name for the minecraft-custodian service."
}

output "mc_events_topic_arn" {
  value       = module.fod_service_mc.events_topic_arn
  description = "SNS topic the minecraft-custodian service's watchdog publishes lifecycle events to."
}

output "mc_ecs_cluster_name" {
  value       = module.fod_service_mc.esc_cluster_name
  description = "Name of the ECS cluster for the minecraft-custodian service."
}

output "mc_ecs_service_name" {
  value       = module.fod_service_mc.esc_service_name
  description = "Name of the ECS service (parked at desired count 0) for the minecraft-custodian service."
}

output "mc_svc_control_policy_arn" {
  value       = module.fod_service_mc.svc_control_policy_arn
  description = "IAM policy that allows the launcher to control the minecraft-custodian service."
}

output "mc_service_role_name" {
  value       = module.fod_service_mc.service_role_name
  description = "Name of the combined task + execution role for the minecraft-custodian service."
}

output "mc_alarm_topic_arn" {
  value       = module.fod_service_mc.alarm_topic_arn
  description = "SNS topic the minecraft-custodian service's max-runtime cost alarm publishes to."
}
