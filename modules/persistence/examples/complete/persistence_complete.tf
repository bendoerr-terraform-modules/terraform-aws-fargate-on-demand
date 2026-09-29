module "fod_persistence" {
  source         = "../.."
  context        = module.context.shared
  mount_path     = "/mount"
  subnet_ids     = module.vpc.public_subnets
  backup_enabled = var.backup_enabled
}

output "name" {
  value       = module.fod_persistence.name
  description = "Name of the EFS file system."
}

output "file_system_id" {
  value       = module.fod_persistence.file_system_id
  description = "EFS file system ID."
}

output "access_point_id" {
  value       = module.fod_persistence.access_point_id
  description = "EFS access point ID."
}

output "mount_path" {
  value       = module.fod_persistence.mount_path
  description = "EFS mount point."
}

output "access_policy_arn" {
  value       = module.fod_persistence.access_policy_arn
  description = "IAM policy that allows mounting and writing to the file system via the access point."
}

output "access_security_group" {
  value       = module.fod_persistence.access_security_group
  description = "Security Group that allows accessing the file system via NFS mount point."
}

output "owner_gid" {
  value       = module.fod_persistence.owner_gid
  description = "TODO"
}

output "owner_uid" {
  value       = module.fod_persistence.owner_uid
  description = "TODO"
}

output "backup_vault_arn" {
  value       = module.fod_persistence.backup_vault_arn
  description = "ARN of the AWS Backup vault protecting the EFS file system. Null when backup_enabled is false."
}

output "backup_plan_id" {
  value       = module.fod_persistence.backup_plan_id
  description = "ID of the AWS Backup plan protecting the EFS file system. Null when backup_enabled is false."
}