module "log_group" {
  source            = "terraform-aws-modules/cloudwatch/aws//modules/log-group"
  version           = "~> 3.0"
  name              = var.namespace
  retention_in_days = 1
}

output "log_group" {
  value = module.log_group.cloudwatch_log_group_name
}