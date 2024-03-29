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

variable "event_topic_arn" {
  type        = string
  description = "TODO"
}

variable "lambda_env_kms_arn" {
  type        = string
  default     = null
  description = "TODO"
}

variable "lambda_logs_kms_arn" {
  type        = string
  default     = null
  description = "TODO"
}
