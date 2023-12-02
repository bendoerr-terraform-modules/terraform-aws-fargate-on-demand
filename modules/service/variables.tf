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

variable "vpc_id" {
  type = string
}

variable "task_cpu" {
  type        = string
  description = ""
}

variable "task_memory" {
  type        = string
  description = ""
}

variable "port_mappings" {
  type = list(object({
    containerPort = number
    hostPort      = number
    protocol      = string
  }))
  description = "List of [Port Mappings](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html)"
}

variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "List of [Port Mappings](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html)"
}

variable "data_mount_path" {
  type        = string
  default     = "/data"
  description = ""
}

variable "idle_seconds" {
  type        = string
  default     = "600"
  description = ""
}

variable "service_image" {
  type    = string
  default = ""
}

variable "dns_zone_id" {
  type        = string
  description = ""
}

variable "dns_record" {
  type        = string
  description = ""
}
variable "data_file_system_id" {
  type        = string
  description = ""
}
variable "data_access_point_id" {
  type        = string
  description = ""
}

variable "persistence_access_policy_arn" {
  type        = string
  description = ""
}

variable "additional_container_definitions" {
  type        = list(any)
  default     = []
  description = ""
  nullable = false
}

variable "service_subnet_ids" {
  type        = list(string)
  description = ""
}

variable "log_retention_days" {
  type        = number
  default     = 7
  description = ""
}

variable "record_control_policy_arn" {
  default = ""
}

variable "persistence_access_security_group" {
  default = ""
}
