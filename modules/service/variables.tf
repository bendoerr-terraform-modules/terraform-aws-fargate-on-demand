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
  description = "The number of CPU units used by the Fargate task. Must be a valid Fargate CPU value. Note: task_cpu and task_memory must form a valid combination per AWS Fargate requirements. See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html"

  validation {
    condition     = contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_cpu)
    error_message = "task_cpu must be a valid Fargate CPU value: 256, 512, 1024, 2048, 4096, 8192, or 16384."
  }
}

variable "task_memory" {
  type        = string
  description = "The amount of memory (in MiB) used by the Fargate task. Must be a valid Fargate memory value. Note: task_cpu and task_memory must form a valid combination per AWS Fargate requirements. See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html"

  validation {
    condition     = contains(["512", "1024", "2048", "3072", "4096", "5120", "6144", "7168", "8192", "9216", "10240", "11264", "12288", "13312", "14336", "15360", "16384", "17408", "18432", "19456", "20480", "21504", "22528", "23552", "24576", "25600", "26624", "27648", "28672", "29696", "30720", "32768", "36864", "40960", "45056", "49152", "53248", "57344", "61440", "65536", "69632", "73728", "77824", "81920", "86016", "90112", "94208", "98304", "102400", "106496", "110592", "114688", "118784", "122880"], var.task_memory)
    error_message = "task_memory must be a valid Fargate memory value (in MiB). See AWS documentation for valid CPU/memory combinations."
  }

  validation {
    condition = contains(
      lookup(
        {
          "256"   = ["512", "1024", "2048"],
          "512"   = ["1024", "2048", "3072", "4096"],
          "1024"  = ["2048", "3072", "4096", "5120", "6144", "7168", "8192"],
          "2048"  = ["4096", "5120", "6144", "7168", "8192", "9216", "10240", "11264", "12288", "13312", "14336", "15360", "16384"],
          "4096"  = ["8192", "9216", "10240", "11264", "12288", "13312", "14336", "15360", "16384", "17408", "18432", "19456", "20480", "21504", "22528", "23552", "24576", "25600", "26624", "27648", "28672", "29696", "30720"],
          "8192"  = ["16384", "20480", "24576", "28672", "32768", "36864", "40960", "45056", "49152", "53248", "57344", "61440"],
          "16384" = ["32768", "40960", "49152", "57344", "65536", "73728", "81920", "90112", "98304", "106496", "114688", "122880"],
        },
        var.task_cpu,
        []
      ),
      var.task_memory
    )
    error_message = "task_cpu and task_memory must form a valid AWS Fargate CPU/memory combination. See https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html"
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
      for sv in var.secret_variables : (
        can(regex("^arn:aws[a-zA-Z-]*:ssm:[a-z0-9-]+:\\d{12}:parameter\\/.+$", sv.valueFrom)) ||
        can(regex("^arn:aws[a-zA-Z-]*:secretsmanager:[a-z0-9-]+:\\d{12}:secret:[^:]+(:[^:]*){0,3}$", sv.valueFrom))
      )
    ])
    error_message = "All secret_variables valueFrom values must be valid ARNs for SSM Parameter Store (arn:aws:ssm:REGION:ACCOUNT:parameter/NAME) or Secrets Manager (arn:aws:secretsmanager:REGION:ACCOUNT:secret:NAME with optional JSON key, version stage, and version ID suffixes)."
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

variable "custodian" {
  type = object({
    kind        = optional(string, "tcp")
    image       = optional(string)
    tcp_port    = optional(number, 30000)
    environment = optional(map(string), {})
  })
  default     = {}
  nullable    = false
  description = "Watchdog sidecar configuration. kind selects the custodian flavor: \"tcp\" (default, today's watchdog) or \"minecraft\". image overrides the module's pinned default image for the selected kind. tcp_port sets WATCH_TCP for kind = \"tcp\" (default 30000, today's hard-coded value). environment entries whose name matches a built-in entry replace its value in place; entries with any other name are appended. With environment = {} the rendered sidecar environment is unchanged from the built-ins (for kind = \"tcp\", byte-identical to today's)."

  validation {
    condition     = contains(["tcp", "minecraft"], var.custodian.kind)
    error_message = "custodian.kind must be one of: tcp, minecraft."
  }

  validation {
    condition     = var.custodian.tcp_port >= 1 && var.custodian.tcp_port <= 65535
    error_message = "custodian.tcp_port must be between 1 and 65535."
  }
}

variable "cpu_architecture" {
  type        = string
  default     = "X86_64"
  nullable    = false
  description = "CPU architecture for the Fargate task's runtime platform. One of X86_64, ARM64."

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be one of: X86_64, ARM64."
  }
}

variable "capacity_provider" {
  type        = string
  default     = "FARGATE_SPOT"
  nullable    = false
  description = "Capacity provider for the ECS service's capacity provider strategy. One of FARGATE_SPOT, FARGATE. Changing it on an existing service may force the ECS service to be replaced; harmless while the service is parked at desired_count = 0, but plan a maintenance window if it's running."

  validation {
    condition     = contains(["FARGATE_SPOT", "FARGATE"], var.capacity_provider)
    error_message = "capacity_provider must be one of: FARGATE_SPOT, FARGATE."
  }
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
  description = "KMS key ARN or key ID to use for encrypting CloudWatch Logs. Accepts full KMS ARNs (including multi-Region mrk- keys), standalone UUID key IDs, or standalone mrk- key IDs."
  nullable    = true

  validation {
    condition     = var.logs_kms_key_id == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:\\d{12}:key/(mrk-[A-Fa-f0-9]{32}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12})|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}|mrk-[A-Fa-f0-9]{32})$", var.logs_kms_key_id))
    error_message = "logs_kms_key_id must be a valid KMS key ARN or key ID (UUID or multi-Region mrk- format)."
  }
}

variable "alarm_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether to create the cost alarm's SNS topic (and its policy/subscriptions) and the CloudWatch max-runtime alarm itself. When false, none of those resources are created and alarm_topic_arn is null."
}

variable "max_runtime_hours" {
  type        = number
  default     = 12
  nullable    = false
  description = "Maximum number of consecutive hours the service may run before the cost alarm fires. Drives the CloudWatch alarm's evaluation_periods and datapoints_to_alarm (period is fixed at 3600s/1h), so it is bounded by CloudWatch's 7-day alarm evaluation window. Must be a whole number between 1 and 168 (1 hour to 7 days)."

  validation {
    condition     = floor(var.max_runtime_hours) == var.max_runtime_hours
    error_message = "max_runtime_hours must be a whole number (no fractional hours)."
  }

  validation {
    condition     = var.max_runtime_hours >= 1 && var.max_runtime_hours <= 168
    error_message = "max_runtime_hours must be between 1 and 168 (1 hour to 7 days)."
  }
}

variable "alarm_email_endpoints" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "Email addresses to subscribe to the cost alarm's SNS topic. Each address must confirm the SNS subscription email before it will receive alarm notifications."
}

variable "sns_kms_key_id" {
  type        = string
  description = "KMS key ARN or key ID to use for encrypting SNS topics. Accepts full KMS ARNs (including multi-Region mrk- keys), standalone UUID key IDs, or standalone mrk- key IDs."
  nullable    = true

  validation {
    condition     = var.sns_kms_key_id == null || can(regex("^(arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:\\d{12}:key/(mrk-[A-Fa-f0-9]{32}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12})|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}|mrk-[A-Fa-f0-9]{32})$", var.sns_kms_key_id))
    error_message = "sns_kms_key_id must be a valid KMS key ARN or key ID (UUID or multi-Region mrk- format)."
  }
}
