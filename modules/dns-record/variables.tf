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
  nullable    = false

  validation {
    condition     = var.context.region == "us-east-1"
    error_message = "Route53 Query Logging is only supported in us-east-1. See: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_query_log and https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/query-logs.html?console_help=true#query-logs-configuring"
  }
}

variable "create_zone" {
  type        = bool
  default     = false
  description = "Should the module create the Route53 Hosted Zone? If true, the variable `zone_name` is required and `zone_id` is ignored. If false, the variable `zone_id` is required and `zone_name` and `zone_comment` will be ignored."
  nullable    = false
}

variable "zone_name" {
  type        = string
  default     = null
  description = "If creating the Route53 Hosted Zone, the domain name for the zone, e.g. `example.com`."
  nullable    = true
}

variable "zone_comment" {
  type        = string
  default     = null
  description = "If creating the Route53 Hosted Zone, an optional comment for the zone info."
  nullable    = true
}

variable "zone_id" {
  type        = string
  default     = null
  description = "The Route53 Hosted Zone ID of an existing zone to use."
  nullable    = true
}

variable "record_name" {
  type        = string
  description = "Full name of the DNS record that will be used to access the on-demand service."
  nullable    = false
}

variable "record_ttl" {
  type        = number
  default     = 30
  description = "For a quick startup, this DNS record TTL should be kept relatively small."
  nullable    = false
}

variable "record_default" {
  type        = string
  default     = "1.1.1.1"
  description = "Default value of the DNS record. This can be anything and would be updated when the on-demand service launches for the first time."
  nullable    = false
}

variable "configure_query_log" {
  type        = bool
  default     = true
  description = "Should the module configure Query Logging on the DNS Hosted Zone? This is required for the on-demand launcher to function, however this should be set to false if query logging is already configured on the DNS Hosted Zone. Further variables related to query logging will be ignored."
  nullable    = false
}

variable "create_log_resource_policy" {
  type        = bool
  default     = true
  description = "There is a limit to the number of CloudWatch Log Resource Policies that can be created (10). Set to false to prevent the creation of the CloudWatch Log Resource Policy, you must ensure that Route53 has appropriate permissions to create log streams and put log events in the associated log group."
  nullable    = false
}

variable "create_query_log_group" {
  type        = bool
  default     = true
  description = "Set this to false to prevent the creation of a CloudWatch Log Group for DNS query logging. If set to false and `configure_query_log` is true the variable `query_log_group_arn` must be provided."
  nullable    = false
}

variable "query_log_group_arn" {
  type        = string
  default     = null
  description = "If `create_query_log_group` is false and `configure_query_log` is true this value is required. Use if the Log Group has already been created for another zone."
  nullable    = true
}

variable "query_log_retention_days" {
  type        = number
  default     = 3
  description = "The number of days to retain DNS query logs."
  nullable    = false
}
