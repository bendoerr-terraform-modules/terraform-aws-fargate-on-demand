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
  description = "The number of CPU units used by the Fargate task. Must be a valid Fargate CPU value."

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_cpu)
    error_message = "task_cpu must be a valid Fargate CPU value: 256, 512, 1024, 2048, 4096, 8192, or 16384."
  }
}

variable "task_memory" {
  type        = string
  description = "The amount of memory (in MiB) used by the Fargate task. Must be a valid Fargate memory value. Valid combinations depend on task_cpu; see https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size"

  validation {
    condition     = contains(["512", "1024", "2048", "3072", "4096", "5120", "6144", "7168", "8192", "9216", "10240", "11264", "12288", "13312", "14336", "15360", "16384", "17408", "18432", "19456", "20480", "21504", "22528", "23552", "24576", "25600", "26624", "27648", "28672", "29696", "30720", "32768", "36864", "40960", "45056", "49152", "53248", "57344", "61440", "65536", "69632", "73728", "77824", "81920", "86016", "90112", "94208", "98304", "102400", "106496", "110592", "114688", "118784", "122880"], var.task_memory)
    error_message = "task_memory must be a valid Fargate memory value (in MiB). See AWS documentation for valid CPU/memory combinations."
  }
}

variable "port_mappings" {
  type = list(object({
    containerPort = number
    hostPort      = number
    protocol      = string
  }))
  description = "List of [Port Mappings](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html)"

  validation {
    condition = alltrue([
      for pm in var.port_mappings : pm.containerPort >= 1 && pm.containerPort <= 65535
    ])
    error_message = "All containerPort values must be between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for pm in var.port_mappings : pm.hostPort >= 1 && pm.hostPort <= 65535
    ])
    error_message = "All hostPort values must be between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for pm in var.port_mappings : contains(["tcp", "udp"], pm.protocol)
    ])
    error_message = "All protocol values must be either 'tcp' or 'udp'."
  }
}

variable "environment_variables" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "List of [Port Mappings](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html)"
}

variable "secret_variables" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  description = "List of [Secrets](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Secret.html) to pass to the container. valueFrom must be an ARN for SSM Parameter Store, Secrets Manager, or a Secrets Manager ARN with a JSON key."

  validation {
    condition = alltrue([
      for sv in var.secret_variables : can(regex("^arn:aws[a-zA-Z-]*:(ssm|secretsmanager):[a-z0-9-]+:\\d{12}:", sv.valueFrom))
    ])
    error_message = "All secret_variables valueFrom values must be valid ARNs for SSM Parameter Store or Secrets Manager."
  }
}

variable "data_mount_path" {
  type        = string
  default     = "/data"
  description = ""
}

variable "idle_seconds" {
  type        = string
  default     = "600"
  description = "Number of seconds of inactivity before the service is stopped. Must be between 60 and 86400 (1 minute to 24 hours)."

  validation {
    condition     = can(tonumber(var.idle_seconds)) && tonumber(var.idle_seconds) >= 60 && tonumber(var.idle_seconds) <= 86400
    error_message = "idle_seconds must be a number between 60 and 86400 (1 minute to 24 hours)."
  }
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
  nullable    = false
}

variable "service_subnet_ids" {
  type        = list(string)
  description = ""
}

variable "log_retention_days" {
  type        = number
  default     = 7
  description = "Number of days to retain CloudWatch log events. Must be a valid CloudWatch Logs retention value."

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653."
  }
}

variable "record_control_policy_arn" {
  type        = string
  default     = ""
  description = ""
}

variable "persistence_access_security_group" {
  type        = string
  default     = ""
  description = ""
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights for the ECS cluster. Metrics are charged as custom metrics ($0.30/metric/month, prorated by hour). Actual cost for on-demand usage is typically low since task-level metrics are only emitted while tasks are running."
  nullable    = false
}

variable "logs_kms_key_id" {
  type        = string
  description = "ARN of the KMS key to use for encrypting CloudWatch Logs. Must be a valid KMS key ARN."
  nullable    = true

  validation {
    condition     = var.logs_kms_key_id == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.logs_kms_key_id))
    error_message = "logs_kms_key_id must be a valid KMS key ARN or key ID (UUID)."
  }
}

variable "sns_kms_key_id" {
  type        = string
  description = "ARN of the KMS key to use for encrypting SNS topics. Must be a valid KMS key ARN."
  nullable    = true

  validation {
    condition     = var.sns_kms_key_id == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:\\d{12}:key/[a-f0-9-]+|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.sns_kms_key_id))
    error_message = "sns_kms_key_id must be a valid KMS key ARN or key ID (UUID)."
  }
}
