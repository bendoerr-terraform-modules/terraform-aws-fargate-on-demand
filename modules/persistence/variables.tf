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