module "dns_record" {
  source      = "../.."
  context     = module.context.shared
  dns_record  = "${module.label.dns_name}.example.bendoerr.com"
  dns_zone_id = aws_route53_zone.test.zone_id

  depends_on = [
    aws_route53_zone.test
  ]
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