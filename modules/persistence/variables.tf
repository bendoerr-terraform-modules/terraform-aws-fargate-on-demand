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

variable "encrypted" {
  type = bool
  default = true
  description = "If true (default), the file system will be encrypted using the default KMS key."
}

variable "mount_path" {
  type = string
  default = "/data"
  description = "Path that NFS clients access the file system."
}

variable "subnet_ids" {
  type = list(string)
  default = []
  description = "The subnet IDs to expose NFS mount targets."
}