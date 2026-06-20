module "fod_persistence" {
  source     = "../../../persistence"
  context    = module.context.shared
  subnet_ids = module.vpc.public_subnets
}

module "fod_efs_access" {
  source  = "../.."
  context = module.context.shared
  enabled = true

  subnet_id             = module.vpc.public_subnets[0]
  file_system_id        = module.fod_persistence.file_system_id
  access_point_id       = module.fod_persistence.access_point_id
  access_security_group = module.fod_persistence.access_security_group
  access_policy_arn     = module.fod_persistence.access_policy_arn
  owner_uid             = module.fod_persistence.owner_uid
  owner_gid             = module.fod_persistence.owner_gid

  create_transfer_bucket = true
}

output "instance_id" {
  value       = module.fod_efs_access.instance_id
  description = "ID of the helper instance."
}

output "connect_command" {
  value       = module.fod_efs_access.connect_command
  description = "Command to open an SSM shell on the helper."
}

output "mount_path" {
  value       = module.fod_efs_access.mount_path
  description = "Path on the helper where EFS is mounted."
}

output "transfer_bucket" {
  value       = module.fod_efs_access.transfer_bucket
  description = "Name of the scratch transfer bucket."
}
