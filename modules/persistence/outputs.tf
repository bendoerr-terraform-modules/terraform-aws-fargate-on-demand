output "name" {
  value       = module.label_data.id
  description = "Name of the EFS file system."
}

output "file_system_id" {
  value       = aws_efs_file_system.data.id
  description = "EFS file system ID."
}

output "access_point_id" {
  value       = aws_efs_access_point.data.id
  description = "EFS access point ID."
}

output "mount_path" {
  value       = var.mount_path
  description = "EFS mount point."
}

output "access_policy_arn" {
  value       = aws_iam_policy.data_rw.arn
  description = "IAM policy that allows mounting and writing to the file system via the access point."
}

output "access_security_group" {
  value       = aws_security_group.data_nfs.id
  description = "Security Group that allows accessing the file system via NFS mount point."
}

output "owner_gid" {
  value       = var.owner_gid
  description = "TODO"
}

output "owner_uid" {
  value       = var.owner_uid
  description = "TODO"
}