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

variable "dns_zone_id" {
  type        = string
  description = ""
}

variable "dns_record" {
  type        = string
  description = ""
}

variable "default_ip_address" {
  type        = string
  default     = "1.1.1.1"
  description = ""
}
