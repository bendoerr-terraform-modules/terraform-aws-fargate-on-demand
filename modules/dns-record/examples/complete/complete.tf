module "dns_record" {
  source      = "../.."
  context     = module.context.shared
  zone_name   = "${var.namespace}.example.bendoerr.com"
  record_name = "${module.label.dns_name}.${var.namespace}.example.bendoerr.com"

  create_zone                = true
  configure_query_log        = true
  create_log_resource_policy = true
  create_query_log_group     = true

  zone_id                  = null
  zone_comment             = null
  record_default           = null
  record_ttl               = null
  query_log_group_arn      = null
  query_log_retention_days = null
}

output "record_id" {
  value = module.dns_record.record_id
}

output "record_name" {
  value = module.dns_record.record_name
}

output "record_control_policy_arn" {
  value = module.dns_record.record_control_policy_arn
}

output "test_route53_zone_name" {
  value = module.dns_record.zone_name
}

output "test_route53_zone_id" {
  value = module.dns_record.zone_id
}
