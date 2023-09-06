module "fod_persistence" {
  source     = "../.."
  context    = module.context.shared
  mount_path = "/mount"
  subnet_ids = module.vpc.public_subnets
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