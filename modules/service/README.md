# service

The ECS cluster, task definition, service, security groups, and SNS status topic for the
on-demand workload.

## Custodian

`custodian.kind` selects the watchdog sidecar that idles the service down:

- `"tcp"` (default) is today's watchdog — it watches `custodian.tcp_port` (`WATCH_TCP`, default
  `30000`) for connection activity and reports state on the notifications SNS topic.
- `"minecraft"` runs the Minecraft-aware custodian. The app container gets
  `dependsOn = [{ containerName = <sidecar>, condition = "HEALTHY" }]`, so it does not start until
  the sidecar's own health check passes; the sidecar's health check `startPeriod` is 240s (Fargate's
  allowed maximum is 300s), while its container `startTimeout`/`stopTimeout` are 120s (their own
  Fargate-allowed maximum). Because the `HEALTHY` dependency is gated by that 120s `startTimeout`,
  120s is the effective ceiling the custodian's own gate timeout must expire inside of — not the
  wider 240s health-check `startPeriod`. The module sets `CUSTODIAN_GATE_TIMEOUT` to `110s` by
  default (the custodian itself caps it at 4 minutes) to leave margin under that 120s ceiling. The
  sidecar is configured entirely through `CUSTODIAN_*` environment variables (cluster, service, DNS
  zone/record, the notifications topic, `idle_seconds` as `CUSTODIAN_IDLE_TIMEOUT`, and the
  `110s` `CUSTODIAN_GATE_TIMEOUT` default); set `custodian.environment` to override any of these or
  add your own.

`custodian.image` overrides the module's pinned default image for the selected kind — leave it unset
to use the version this module release ships with.

## `cpu_architecture` and `capacity_provider`

`cpu_architecture` (`X86_64`, `ARM64`) sets the task's `runtime_platform`; `capacity_provider`
(`FARGATE_SPOT`, `FARGATE`) sets the ECS service's capacity provider strategy. Both default to
today's behavior (`X86_64` / `FARGATE_SPOT`) and can be changed independently — e.g. run the
Minecraft custodian on `ARM64` + `FARGATE` for steadier (non-preemptible) capacity.

## Cost alarm

The module creates a CloudWatch alarm that fires once the service has run for more than
`max_runtime_hours` consecutive hours (default 12), as a backstop against a stuck watchdog leaving
the task running indefinitely. The alarm is approximate, not a measurement of continuous runtime: it
fires when the service has emitted at least one `CPUUtilization` sample in each of the last
`max_runtime_hours` hourly periods (`statistic = SampleCount`, `period = 3600`). A brief stop and
restart that both land within the same hourly period still counts as a sample for that period, so a
service that idles down and relaunches within an hour, repeated across `max_runtime_hours` hours,
can still trip the alarm even though it never ran continuously — treat this as "roughly running for
that long," not a precise uptime measurement.

The alarm publishes to its own SNS topic (`alarm_topic_arn`), kept separate from the status topic
(`events_topic_arn`) — the notice Lambdas that subscribe to the status topic parse custodian
lifecycle JSON and would fail on a CloudWatch alarm payload. Subscribe your own endpoints to
`alarm_topic_arn`, or list emails in `alarm_email_endpoints` and this module will subscribe them for
you (each address still has to confirm the SNS subscription).

Set `alarm_enabled = false` to skip creating the alarm entirely — no alarms SNS topic, topic policy,
subscriptions, or CloudWatch alarm, and `alarm_topic_arn` is `null`. Defaults to `true`.

Both topics share `sns_kms_key_id`, which is a required input with no default — pass
`sns_kms_key_id = null` explicitly for an unencrypted topic (there is no implicit null; leaving it
out entirely is a Terraform error, not a fallback to unencrypted). Alarms can notify either way: pass
`null` for an unencrypted topic, or a customer-managed KMS key whose key policy separately grants
`cloudwatch.amazonaws.com` `kms:Decrypt`/`kms:GenerateDataKey*` (this module does not manage the key
policy) — without that grant, CloudWatch's publish to the alarm topic is denied. The one key that
never works here is the AWS-managed `alias/aws/sns`: CloudWatch alarms cannot publish through it, so
if you want an encrypted alarm topic, use a customer-managed key, not `alias/aws/sns`.

## Deployment settings

The ECS service is always created with `deployment_maximum_percent = 100` and
`deployment_minimum_healthy_percent = 0`, for every `custodian.kind`. That means a deployment never
runs two tasks at once against the same EFS data — the EFS volume has a single writer at all times.
The trade-off: rolling out a new task definition while the service is actively running (a nonzero
desired count) stops the running task before starting the replacement, a brief outage, rather than
briefly running two tasks (and so two servers) against the same world/data. This is not configurable.

## Security notes

All containers in a task share the task's single IAM role (`aws_iam_role.svc`, exposed as
`service_role_arn`/`service_role_name`) — there is no per-container IAM isolation in ECS. Any IAM
grant reachable by the app container's task role (EFS access, DNS record control, SNS publish, the
custodian's own log group) is equally reachable from the game/app container, and vice versa.

Values set in `custodian.environment` (and `environment_variables`/`secret_variables` on the app
container) are rendered directly into the ECS task definition, which is visible in the AWS console,
the ECS API, and Terraform state. Do not put secrets in `custodian.environment` or
`environment_variables` — use `secret_variables` (which sources from Secrets Manager/SSM Parameter
Store at task launch) for anything sensitive.

## Reference

<!-- BEGIN_TF_DOCS -->

### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement_aws) | ~> 6.0 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider_aws) | ~> 6.0 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_label"></a> [label](#module_label) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_alarms"></a> [label_alarms](#module_label_alarms) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_ctl"></a> [label_ctl](#module_label_ctl) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_data"></a> [label_data](#module_label_data) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_logs"></a> [label_logs](#module_label_logs) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_topic"></a> [label_topic](#module_label_topic) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_wd"></a> [label_wd](#module_label_wd) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |

### Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.max_runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_ecs_cluster.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_policy.ecs_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.mc_task_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.notification_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.svc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.mc_task_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.mc_task_route53](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.mc_task_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_ctrl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.task_efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.mc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic.notifications](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.alarms_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_vpc_security_group_egress_rule.mc_allow_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.mc_allow_port](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.alarms_topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.mc_task_cw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.notification_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.svc_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_container_definitions"></a> [additional_container_definitions](#input_additional_container_definitions) | n/a | `list(any)` | `[]` | no |
| <a name="input_alarm_enabled"></a> [alarm_enabled](#input_alarm_enabled) | Whether to create the cost alarm's SNS topic (and its policy/subscriptions) and the CloudWatch max-runtime alarm itself. When false, none of those resources are created and alarm_topic_arn is null. | `bool` | `true` | no |
| <a name="input_alarm_email_endpoints"></a> [alarm_email_endpoints](#input_alarm_email_endpoints) | Email addresses to subscribe to the cost alarm's SNS topic. Each address must confirm the SNS subscription email before it will receive alarm notifications. | `list(string)` | `[]` | no |
| <a name="input_capacity_provider"></a> [capacity_provider](#input_capacity_provider) | Capacity provider for the ECS service's capacity provider strategy. One of FARGATE_SPOT, FARGATE. Changing it on an existing service may force the ECS service to be replaced; harmless while the service is parked at desired_count = 0, but plan a maintenance window if it's running. | `string` | `"FARGATE_SPOT"` | no |
| <a name="input_context"></a> [context](#input_context) | Shared Context from Ben's terraform-null-context | <pre>object({<br/>    attributes     = list(string)<br/>    dns_namespace  = string<br/>    environment    = string<br/>    instance       = string<br/>    instance_short = string<br/>    namespace      = string<br/>    region         = string<br/>    region_short   = string<br/>    role           = string<br/>    role_short     = string<br/>    project        = string<br/>    tags           = map(string)<br/>  })</pre> | n/a | yes |
| <a name="input_cpu_architecture"></a> [cpu_architecture](#input_cpu_architecture) | CPU architecture for the Fargate task's runtime platform. One of X86_64, ARM64. | `string` | `"X86_64"` | no |
| <a name="input_custodian"></a> [custodian](#input_custodian) | Watchdog sidecar configuration. kind selects the custodian flavor: "tcp" (default, today's watchdog) or "minecraft". image overrides the module's pinned default image for the selected kind. tcp_port sets WATCH_TCP for kind = "tcp" (default 30000, today's hard-coded value). environment entries whose name matches a built-in entry replace its value in place; entries with any other name are appended. With environment = {} the rendered sidecar environment is unchanged from the built-ins (for kind = "tcp", byte-identical to today's). | <pre>object({<br/>    kind        = optional(string, "tcp")<br/>    image       = optional(string)<br/>    tcp_port    = optional(number, 30000)<br/>    environment = optional(map(string), {})<br/>  })</pre> | `{}` | no |
| <a name="input_data_access_point_id"></a> [data_access_point_id](#input_data_access_point_id) | n/a | `string` | n/a | yes |
| <a name="input_data_file_system_id"></a> [data_file_system_id](#input_data_file_system_id) | n/a | `string` | n/a | yes |
| <a name="input_data_mount_path"></a> [data_mount_path](#input_data_mount_path) | n/a | `string` | `"/data"` | no |
| <a name="input_dns_record"></a> [dns_record](#input_dns_record) | n/a | `string` | n/a | yes |
| <a name="input_dns_zone_id"></a> [dns_zone_id](#input_dns_zone_id) | n/a | `string` | n/a | yes |
| <a name="input_enable_container_insights"></a> [enable_container_insights](#input_enable_container_insights) | Enable CloudWatch Container Insights for the ECS cluster. Metrics are charged as custom metrics ($0.30/metric/month, prorated by hour). Actual cost for on-demand usage is typically low since task-level metrics are only emitted while tasks are running. | `bool` | n/a | yes |
| <a name="input_environment_variables"></a> [environment_variables](#input_environment_variables) | List of [Port Mappings](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html) | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | n/a | yes |
| <a name="input_idle_seconds"></a> [idle_seconds](#input_idle_seconds) | Number of seconds of inactivity before the service is stopped. Must be between 60 and 86400 (1 minute to 24 hours). | `string` | `"600"` | no |
| <a name="input_log_retention_days"></a> [log_retention_days](#input_log_retention_days) | Number of days to retain CloudWatch log events. Must be a valid CloudWatch Logs retention value. | `number` | `7` | no |
| <a name="input_logs_kms_key_id"></a> [logs_kms_key_id](#input_logs_kms_key_id) | KMS key ARN or key ID to use for encrypting CloudWatch Logs. Accepts full KMS ARNs (including multi-Region mrk- keys), standalone UUID key IDs, or standalone mrk- key IDs. | `string` | n/a | yes |
| <a name="input_max_runtime_hours"></a> [max_runtime_hours](#input_max_runtime_hours) | Maximum number of consecutive hours the service may run before the cost alarm fires. Drives the CloudWatch alarm's evaluation_periods and datapoints_to_alarm (period is fixed at 3600s/1h), so it is bounded by CloudWatch's 7-day alarm evaluation window. Must be a whole number between 1 and 168 (1 hour to 7 days). | `number` | `12` | no |
| <a name="input_persistence_access_policy_arn"></a> [persistence_access_policy_arn](#input_persistence_access_policy_arn) | n/a | `string` | n/a | yes |
| <a name="input_persistence_access_security_group"></a> [persistence_access_security_group](#input_persistence_access_security_group) | n/a | `string` | `""` | no |
| <a name="input_port_mappings"></a> [port_mappings](#input_port_mappings) | List of [Port Mappings](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_PortMapping.html) | <pre>list(object({<br/>    containerPort = number<br/>    hostPort      = number<br/>    protocol      = string<br/>  }))</pre> | n/a | yes |
| <a name="input_record_control_policy_arn"></a> [record_control_policy_arn](#input_record_control_policy_arn) | n/a | `string` | `""` | no |
| <a name="input_secret_variables"></a> [secret_variables](#input_secret_variables) | List of [Secrets](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Secret.html) to pass to the container. valueFrom must be an ARN for SSM Parameter Store, Secrets Manager, or a Secrets Manager ARN with a JSON key. | <pre>list(object({<br/>    name      = string<br/>    valueFrom = string<br/>  }))</pre> | n/a | yes |
| <a name="input_service_image"></a> [service_image](#input_service_image) | n/a | `string` | `""` | no |
| <a name="input_service_subnet_ids"></a> [service_subnet_ids](#input_service_subnet_ids) | n/a | `list(string)` | n/a | yes |
| <a name="input_sns_kms_key_id"></a> [sns_kms_key_id](#input_sns_kms_key_id) | KMS key ARN or key ID to use for encrypting SNS topics. Accepts full KMS ARNs (including multi-Region mrk- keys), standalone UUID key IDs, or standalone mrk- key IDs. | `string` | n/a | yes |
| <a name="input_task_cpu"></a> [task_cpu](#input_task_cpu) | The number of CPU units used by the Fargate task. Must be a valid Fargate CPU value. Note: task_cpu and task_memory must form a valid combination per AWS Fargate requirements. See <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html> | `string` | n/a | yes |
| <a name="input_task_memory"></a> [task_memory](#input_task_memory) | The amount of memory (in MiB) used by the Fargate task. Must be a valid Fargate memory value. Note: task_cpu and task_memory must form a valid combination per AWS Fargate requirements. See <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html> | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc_id](#input_vpc_id) | n/a | `string` | n/a | yes |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_topic_arn"></a> [alarm_topic_arn](#output_alarm_topic_arn) | n/a |
| <a name="output_esc_cluster_arn"></a> [esc_cluster_arn](#output_esc_cluster_arn) | n/a |
| <a name="output_esc_cluster_name"></a> [esc_cluster_name](#output_esc_cluster_name) | n/a |
| <a name="output_esc_service_name"></a> [esc_service_name](#output_esc_service_name) | n/a |
| <a name="output_events_topic_arn"></a> [events_topic_arn](#output_events_topic_arn) | n/a |
| <a name="output_service_role_arn"></a> [service_role_arn](#output_service_role_arn) | n/a |
| <a name="output_service_role_name"></a> [service_role_name](#output_service_role_name) | n/a |
| <a name="output_svc_control_policy_arn"></a> [svc_control_policy_arn](#output_svc_control_policy_arn) | n/a |

<!-- END_TF_DOCS -->
