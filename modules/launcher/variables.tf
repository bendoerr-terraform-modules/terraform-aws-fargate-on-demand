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

variable "ecs_cluster" {
  type = string
  description = ""
}

variable "ecs_service" {
  type = string
  description = ""
}

variable "trigger_cloudwatch_group" {
  type = string
  description = ""
}
