variable "context" {
  type = object({
    attributes     = list(string)
    dns_namespace  = string
    environment    = string
    instance       = string
    instance_short = string
    namespace      = string
    region         = string
    region_short   = string
    role           = string
    role_short     = string
    project        = string
    tags           = map(string)
  })
  description = "Shared Context from Ben's terraform-null-context"
}

variable "enabled" {
  type        = bool
  default     = false
  description = "Whether the helper instance and its EBS volume exist. Defaults to false so the module costs $0 when idle. The IAM role, instance profile, and (optional) transfer bucket are always created since they are free; only the billable instance + volume are gated. Set to true and apply when you need to seed or inspect the volume, then back to false when done."
}

variable "subnet_id" {
  type        = string
  description = "A PUBLIC subnet to place the helper in. This module follows the NAT-free egress model of the service module: the instance gets a public IP (no inbound rules) and reaches AWS Systems Manager over the existing internet gateway, avoiding an always-on NAT gateway or interface endpoints."
}

variable "assign_public_ip" {
  type        = bool
  default     = true
  description = "Assign a public IP so the SSM agent can reach Systems Manager over the internet gateway without a NAT gateway. Combined with zero inbound security-group rules and IMDSv2, the public IP is not a meaningful exposure because SSM remains outbound-only. Only set to false if the subnet already has SSM-reachable egress (NAT or interface endpoints)."
}

variable "file_system_id" {
  type        = string
  description = "EFS file system ID to mount, from the persistence module's file_system_id output."
}

variable "access_point_id" {
  type        = string
  description = "EFS access point ID to mount through, from the persistence module's access_point_id output. The access point enforces the POSIX owner_uid/owner_gid on every write."
}

variable "access_security_group" {
  type        = string
  description = "Security group that permits NFS to the EFS mount targets, from the persistence module's access_security_group output. Attached to the helper so it can reach the file system. (SSM and package-mirror egress is carried by this module's own egress SG, since data_nfs only permits egress to its own members.)"
}

variable "access_policy_arn" {
  type        = string
  description = "IAM policy ARN granting EFS ClientMount/ClientWrite scoped to the access point, from the persistence module's access_policy_arn output. Attached to the helper's instance role for the iam mount option."
}

variable "mount_path" {
  type        = string
  default     = "/mnt/data"
  description = "Path on the helper instance where the EFS access point is mounted."
}

variable "instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "Instance type for the helper. Defaults to the cheapest current-gen Graviton (arm64) size; keep it arm64 to match the default AL2023 arm64 AMI."
}

variable "root_volume_size" {
  type        = number
  default     = 8
  description = "Size in GiB of the encrypted gp3 root volume. The helper is stateless (all data lives on EFS), so this only needs to hold the OS."
}

variable "ssh_authorized_keys" {
  type        = list(string)
  default     = []
  description = "Public SSH keys to authorize for the ec2-user. Required only for the rsync / scp / sshfs (FUSE-T) / SFTP-over-SSM transfer lanes; the aws s3 sync lane and an interactive SSM shell need no keys."
}

variable "kms_ebs_arn" {
  type        = string
  default     = null
  description = "ARN of the KMS key for encrypting the root EBS volume. Defaults to the account's aws/ebs managed key when null."
}

variable "owner_uid" {
  type        = number
  default     = 1000
  description = "POSIX UID the access point enforces on writes, from the persistence module's owner_uid output. Surfaced so operators know which UID will own seeded files."
}

variable "owner_gid" {
  type        = number
  default     = 1000
  description = "POSIX GID the access point enforces on writes, from the persistence module's owner_gid output. Surfaced so operators know which GID will own seeded files."
}

variable "ami_id" {
  type        = string
  default     = null
  description = "AMI ID for the helper. Defaults to the latest Amazon Linux 2023 arm64 AMI resolved from the public SSM parameter when null."
}

variable "create_transfer_bucket" {
  type        = bool
  default     = false
  description = "Create a scratch S3 bucket for the aws s3 sync transfer lane and grant the helper read/write to it. When false, use your own bucket and attach S3 permissions yourself."
}

variable "transfer_bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Allow terraform destroy to delete the scratch transfer bucket even if it still holds objects. Defaults to true because the bucket is staging-only scratch; set to false if you want destroy to refuse on a non-empty bucket."
}
