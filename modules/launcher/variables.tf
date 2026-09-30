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
}

variable "ecs_cluster" {
  type        = string
  description = "Name of the ECS Cluster that the service is in"
  nullable    = false

}

variable "ecs_service" {
  type        = string
  description = "Name of the ECS service to update the desired count for"
  nullable    = false
}

variable "trigger_cloudwatch_group" {
  type        = string
  description = ""
}

variable "launch_events" {
  type = object({
    topic_arn = string
  })
  default     = null
  description = "Publish a \"launch\" event to topic_arn (e.g. the service module's events_topic_arn) when the launcher scales the service up from zero. An object so it can be set from a topic created in the same apply. Null disables the event."
}

variable "trigger_filter_pattern" {
  type        = string
  default     = ""
  description = "A CloudWatch log subscription filter pattern. This filter pattern will be used to limit the logs which invoke the launcher lambda."
  nullable    = false
}

variable "lambda_env_kms_arn" {
  type        = string
  default     = null
  description = ""
}

variable "lambda_logs_kms_arn" {
  type        = string
  default     = null
  description = ""
}

variable "lambda_timeout" {
  type        = number
  default     = 3
  description = "Timeout in seconds of the Launcher Lambda, there shouldn't be a huge reason to change thi.s"
  nullable    = false
}

variable "lambda_python_runtime" {
  type        = string
  default     = "python3.13"
  description = "Overwrite the AWS Lambda python runtime"
  nullable    = false

  validation {
    condition     = can(regex("^python", var.lambda_python_runtime))
    error_message = "Must be a python runtime"
  }
}

variable "lambda_logs_retention" {
  type        = number
  default     = 3
  description = "Number of days to keep logs from the AWS Lambda launcher"
  nullable    = false
}

variable "lambda_tracing_config" {
  type        = string
  default     = "Active"
  description = "X-Ray Lambda Tracing Mode"
  nullable    = false

  validation {
    condition     = contains(["PassThrough", "Active"], var.lambda_tracing_config)
    error_message = "Must be one of 'PassThrough' or 'Active'"
  }
}
