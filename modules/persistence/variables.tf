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

variable "mount_path" {
  type        = string
  default     = "/data"
  description = "Path that NFS clients access the file system."
}

variable "owner_uid" {
  type        = number
  default     = 1000
  description = "TODO"
}

variable "owner_gid" {
  type        = number
  default     = 1000
  description = "TODO"
}

variable "subnet_ids" {
  type        = list(string)
  default     = []
  description = "The subnet IDs to expose NFS mount targets."
}

variable "kms_efs_arn" {
  type        = string
  default     = null
  description = "ARN of the KMS key to use for encrypting the EFS volume. Default aws/elasticfilesystem will be used instead."
}

variable "throughput_mode" {
  type        = string
  default     = "elastic"
  nullable    = false
  description = "Throughput mode for the EFS file system. One of bursting, elastic. Changes apply in place to the existing file system."

  validation {
    condition     = contains(["bursting", "elastic"], var.throughput_mode)
    error_message = "throughput_mode must be one of: bursting, elastic."
  }
}

variable "backup_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether to create AWS Backup resources (vault, plan, IAM role, selection) protecting the EFS file system. When false, none of those resources are created and backup_vault_arn/backup_plan_id are null."
}

variable "backup_retention_days" {
  type        = number
  default     = 14
  nullable    = false
  description = "Number of days to retain recovery points created by the backup plan's daily rule (delete_after). Ignored when backup_enabled is false."

  validation {
    condition     = floor(var.backup_retention_days) == var.backup_retention_days
    error_message = "backup_retention_days must be a whole number (no fractional days)."
  }

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "backup_retention_days must be at least 1."
  }
}

variable "backup_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for the AWS Backup vault. Default null uses the AWS-managed aws/backup key. Ignored when backup_enabled is false."
}