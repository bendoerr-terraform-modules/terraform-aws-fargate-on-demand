<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | ~> 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider_aws) | ~> 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_label"></a> [label](#module_label) | git@github.com:bendoerr-terraform-modules/terraform-null-label | v0.4.0 |
| <a name="module_label_ctl"></a> [label_ctl](#module_label_ctl) | git@github.com:bendoerr-terraform-modules/terraform-null-label | v0.4.0 |
| <a name="module_label_logs"></a> [label_logs](#module_label_logs) | git@github.com:bendoerr-terraform-modules/terraform-null-label | v0.4.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.query](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.query](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_route53_query_log.query](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_query_log) | resource |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_caller_identity.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.query](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_configure_query_log"></a> [configure_query_log](#input_configure_query_log) | Should the module configure Query Logging on the DNS Hosted Zone? This is required for the on-demand launcher to function, however this should be set to false if query logging is already configured on the DNS Hosted Zone. Further variables related to query logging will be ignored. | `bool` | `true` | no |
| <a name="input_context"></a> [context](#input_context) | Shared Context from Ben's terraform-null-context | <pre>object({<br>    attributes     = list(string)<br>    dns_namespace  = string<br>    environment    = string<br>    instance       = string<br>    instance_short = string<br>    namespace      = string<br>    region         = string<br>    region_short   = string<br>    role           = string<br>    role_short     = string<br>    project        = string<br>    tags           = map(string)<br>  })</pre> | n/a | yes |
| <a name="input_create_log_resource_policy"></a> [create_log_resource_policy](#input_create_log_resource_policy) | There is a limit to the number of CloudWatch Log Resource Policies that can be created (10). Set to false to prevent the creation of the CloudWatch Log Resource Policy, you must ensure that Route53 has appropriate permissions to create log streams and put log events in the associated log group. | `bool` | `true` | no |
| <a name="input_create_query_log_group"></a> [create_query_log_group](#input_create_query_log_group) | Set this to false to prevent the creation of a CloudWatch Log Group for DNS query logging. If set to false and `configure_query_log` is true the variable `query_log_group_arn` must be provided. | `bool` | `true` | no |
| <a name="input_create_zone"></a> [create_zone](#input_create_zone) | Should the module create the Route53 Hosted Zone? If true, the variable `zone_name` is required and `zone_id` is ignored. If false, the variable `zone_id` is required and `zone_name` and `zone_comment` will be ignored. | `bool` | `false` | no |
| <a name="input_query_log_group_arn"></a> [query_log_group_arn](#input_query_log_group_arn) | If `create_query_log_group` is false and `configure_query_log` is true this value is required. Use if the Log Group has already been created for another zone. | `string` | `null` | no |
| <a name="input_query_log_retention_days"></a> [query_log_retention_days](#input_query_log_retention_days) | The number of days to retain DNS query logs. | `number` | `3` | no |
| <a name="input_record_default"></a> [record_default](#input_record_default) | Default value of the DNS record. This can be anything and would be updated when the on-demand service launches for the first time. | `string` | `"1.1.1.1"` | no |
| <a name="input_record_name"></a> [record_name](#input_record_name) | Full name of the DNS record that will be used to access the on-demand service. | `string` | n/a | yes |
| <a name="input_record_ttl"></a> [record_ttl](#input_record_ttl) | For a quick startup, this DNS record TTL should be kept relatively small. | `number` | `30` | no |
| <a name="input_zone_comment"></a> [zone_comment](#input_zone_comment) | If creating the Route53 Hosted Zone, an optional comment for the zone info. | `string` | `null` | no |
| <a name="input_zone_id"></a> [zone_id](#input_zone_id) | The Route53 Hosted Zone ID of an existing zone to use. | `string` | `null` | no |
| <a name="input_zone_name"></a> [zone_name](#input_zone_name) | If creating the Route53 Hosted Zone, the domain name for the zone, e.g. `example.com`. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_query_log_group_arn"></a> [query_log_group_arn](#output_query_log_group_arn) | ARN of the CloudWatch Log Group that will receive the DNS Query logs |
| <a name="output_query_log_group_filter_patten"></a> [query_log_group_filter_patten](#output_query_log_group_filter_patten) | A CloudWatch filter pattern that will match this DNS record only |
| <a name="output_record_control_policy_arn"></a> [record_control_policy_arn](#output_record_control_policy_arn) | IAM Policy that allows modification of the DNS Record (and Hosted Zone information) |
| <a name="output_record_id"></a> [record_id](#output_record_id) | ID of the DNS Record |
| <a name="output_record_name"></a> [record_name](#output_record_name) | DNS Name of the Route53 Record |
| <a name="output_zone_arn"></a> [zone_arn](#output_zone_arn) | ARN for the Route53 Hosted Zone |
| <a name="output_zone_id"></a> [zone_id](#output_zone_id) | Zone ID of the Route53 Hosted Zone |
| <a name="output_zone_name"></a> [zone_name](#output_zone_name) | DNS Name for the Route53 Hosted Zone |
| <a name="output_zone_name_servers"></a> [zone_name_servers](#output_zone_name_servers) | Name Servers for the Route53 Hosted Zone |

<!-- END_TF_DOCS -->
