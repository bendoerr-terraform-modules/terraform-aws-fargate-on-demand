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

variable "github_token" {
  type        = string
  description = "GitHub token used to commit the status file. Either a literal fine-grained PAT or, preferred, a 'param:<ssm-parameter-name>' reference resolved (with decryption) at runtime. The PAT should be least-privilege: contents:write on the single status repo only."
  sensitive   = true
}

variable "github_token_ssm_param_arn" {
  type        = string
  default     = null
  description = "ARN of the SSM SecureString parameter holding the GitHub token. Set this when github_token is a 'param:<name>' reference so the Lambda role's ssm:GetParameter grant is scoped to exactly that parameter. Leave null for literal-token usage."
}

variable "github_token_kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of the customer-managed KMS key encrypting the token SSM parameter, if one is used. Leave null when the parameter uses the default 'alias/aws/ssm' key (decrypt is then scoped by the kms:ViaService condition instead)."
}

variable "github_repo" {
  type        = string
  description = "Target status repository in 'owner/name' form that the status file is committed to."

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in 'owner/name' form."
  }
}

variable "github_branch" {
  type        = string
  default     = "main"
  description = "Branch in the status repository to commit the status file to."
}

variable "state_file_path" {
  type        = string
  default     = "state.json"
  description = "Path within the status repository for the JSON status file the GitHub Pages status page reads."
}

variable "notify_app_name" {
  type        = string
  description = "Human-readable application name recorded on each service entry and shown on the status page."
}

variable "notify_app_url" {
  type        = string
  description = "Public URL of the application, recorded on each service entry and linked from the status page."

  validation {
    condition     = can(regex("^https?://", var.notify_app_url))
    error_message = "notify_app_url must start with http:// or https://."
  }
}

variable "event_topic_arn" {
  type        = string
  description = "ARN of the SNS topic publishing fargate-on-demand task-state events the Lambda subscribes to."
}

variable "lambda_env_kms_arn" {
  type        = string
  default     = null
  description = "Optional KMS key ARN for encrypting the Lambda environment variables. Null uses the AWS-managed key."
}

variable "lambda_logs_kms_arn" {
  type        = string
  default     = null
  description = "Optional KMS key ARN for encrypting the Lambda CloudWatch log group. Null uses the AWS-managed key."
}
