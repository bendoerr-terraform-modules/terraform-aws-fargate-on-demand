output "instance_id" {
  value       = try(aws_instance.this[0].id, null)
  description = "ID of the helper instance, or null when enabled = false."
}

output "mount_path" {
  value       = var.mount_path
  description = "Path on the helper where the EFS access point is mounted."
}

output "instance_role_arn" {
  value       = aws_iam_role.this.arn
  description = "ARN of the helper's instance role (carries SSM + EFS access)."
}

output "connect_command" {
  value       = try("aws ssm start-session --target ${aws_instance.this[0].id}", null)
  description = "Ready-to-run command to open an SSM shell on the helper, or null when disabled."
}

output "transfer_bucket" {
  value       = try(aws_s3_bucket.transfer[0].bucket, null)
  description = "Name of the scratch transfer bucket, or null when create_transfer_bucket = false."
}

output "owner_uid" {
  value       = var.owner_uid
  description = "POSIX UID the access point enforces on writes; seeded files will be owned by this UID."
}

output "owner_gid" {
  value       = var.owner_gid
  description = "POSIX GID the access point enforces on writes; seeded files will be owned by this GID."
}
