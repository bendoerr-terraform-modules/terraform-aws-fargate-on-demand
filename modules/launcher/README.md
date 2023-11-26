<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.4.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.25.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_label_ecs_svc_update"></a> [label\_ecs\_svc\_update](#module\_label\_ecs\_svc\_update) | git@github.com:bendoerr/terraform-null-label | v0.4.0 |
| <a name="module_label_launcher"></a> [label\_launcher](#module\_label\_launcher) | git@github.com:bendoerr-terraform-modules/terraform-null-label | v0.4.0 |
| <a name="module_label_launcher_logs"></a> [label\_launcher\_logs](#module\_label\_launcher\_logs) | git@github.com:bendoerr-terraform-modules/terraform-null-label | v0.4.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.launcher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_subscription_filter.launcher_cw_domain_filter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_subscription_filter) | resource |
| [aws_iam_policy.launcher_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.svc_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.launcher_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.launcher_ecs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.launcher_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.launcher](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.launcher_cw_invoke](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [archive_file.launcher](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_cloudwatch_log_group.domain_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudwatch_log_group) | data source |
| [aws_ecs_cluster.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecs_cluster) | data source |
| [aws_ecs_service.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecs_service) | data source |
| [aws_iam_policy_document.ecs_svc_update](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lambda_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.launcher_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_context"></a> [context](#input\_context) | Shared Context from Ben's terraform-null-context | <pre>object({<br>    attributes     = list(string)<br>    dns_namespace  = string<br>    environment    = string<br>    instance       = string<br>    instance_short = string<br>    namespace      = string<br>    region         = string<br>    region_short   = string<br>    role           = string<br>    role_short     = string<br>    project        = string<br>    tags           = map(string)<br>  })</pre> | n/a | yes |
| <a name="input_ecs_cluster"></a> [ecs\_cluster](#input\_ecs\_cluster) | Name of the ECS Cluster that the service is in | `string` | `null` | no |
| <a name="input_ecs_service"></a> [ecs\_service](#input\_ecs\_service) | Name of the ECS service to update the desired count for | `string` | `null` | no |
| <a name="input_lambda_env_kms_arn"></a> [lambda\_env\_kms\_arn](#input\_lambda\_env\_kms\_arn) | n/a | `string` | `null` | no |
| <a name="input_lambda_logs_kms_arn"></a> [lambda\_logs\_kms\_arn](#input\_lambda\_logs\_kms\_arn) | n/a | `string` | `null` | no |
| <a name="input_lambda_logs_retention"></a> [lambda\_logs\_retention](#input\_lambda\_logs\_retention) | Number of days to keep logs from the AWS Lambda launcher | `number` | `3` | no |
| <a name="input_lambda_python_runtime"></a> [lambda\_python\_runtime](#input\_lambda\_python\_runtime) | Overwrite the AWS Lambda python runtime | `string` | `"python3.11"` | no |
| <a name="input_lambda_timeout"></a> [lambda\_timeout](#input\_lambda\_timeout) | Timeout in seconds of the Launcher Lambda, there shouldn't be a huge reason to change thi.s | `number` | `3` | no |
| <a name="input_lambda_tracing_config"></a> [lambda\_tracing\_config](#input\_lambda\_tracing\_config) | X-Ray Lambda Tracing Mode | `string` | `"PassThrough"` | no |
| <a name="input_trigger_cloudwatch_group"></a> [trigger\_cloudwatch\_group](#input\_trigger\_cloudwatch\_group) | n/a | `string` | n/a | yes |
| <a name="input_trigger_filter_pattern"></a> [trigger\_filter\_pattern](#input\_trigger\_filter\_pattern) | A CloudWatch log subscription filter pattern. This filter pattern will be used to limit the logs which invoke the launcher lambda. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_lambda_arn"></a> [lambda\_arn](#output\_lambda\_arn) | AWS Lambda ARN of the launcher function |
| <a name="output_lambda_id"></a> [lambda\_id](#output\_lambda\_id) | AWS Lambda ID of the launcher function |
| <a name="output_lambda_log_group_id"></a> [lambda\_log\_group\_id](#output\_lambda\_log\_group\_id) | The CloudWatch Log Group ID for the logs from the AWS Lambda function |
| <a name="output_lambda_role_arn"></a> [lambda\_role\_arn](#output\_lambda\_role\_arn) | The IAM Role of the AWS Lambda launcher function |
| <a name="output_lambda_role_id"></a> [lambda\_role\_id](#output\_lambda\_role\_id) | The IAM Role of the AWS Lambda launcher function |
<!-- END_TF_DOCS -->