# persistence

EFS file system, access point, and mount targets for state that survives start/stop.

## Throughput and backups

`throughput_mode` defaults to `elastic`, so the file system scales its throughput to whatever the
workload is doing without you having to size or pay for provisioned throughput ahead of time; it
applies in place to the existing file system if you change it later.

AWS Backup is on by default (`backup_enabled = true`): a daily recovery point at 05:00 UTC, kept for
`backup_retention_days` (default 14 days). Turning this off, or destroying the module after backups
have already run, does **not** clean up what AWS Backup has already stored — a vault that still holds
recovery points cannot be deleted. If you disable `backup_enabled` or plan to `terraform destroy`,
remove or let expire the vault's recovery points first (AWS Backup console, or `aws backup delete-recovery-point`), otherwise the vault deletion (and the destroy) will fail.

The backup IAM role only carries `AWSBackupServiceRolePolicyForBackup` — the minimum AWS Backup needs
to take a backup. It does not carry `AWSBackupServiceRolePolicyForRestores`: restores choose an IAM
role at restore time (in the AWS Backup console or `StartRestoreJob`'s `IamRoleArn`), so this module's
backup role does not need restore permissions to do its own job.

## Reference

<!-- BEGIN_TF_DOCS -->

### Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement_aws) | ~> 6.32 |

### Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider_aws) | ~> 6.32 |

### Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_label_backup_plan"></a> [label_backup_plan](#module_label_backup_plan) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_backup_role"></a> [label_backup_role](#module_label_backup_role) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_backup_vault"></a> [label_backup_vault](#module_label_backup_vault) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_data"></a> [label_data](#module_label_data) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_data_nfs"></a> [label_data_nfs](#module_label_data_nfs) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |
| <a name="module_label_data_rw"></a> [label_data_rw](#module_label_data_rw) | `git@github.com:bendoerr-terraform-modules/terraform-null-label` | v1.0.1 |

### Resources

| Name | Type |
| ---- | ---- |
| [aws_backup_plan.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan) | resource |
| [aws_backup_selection.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection) | resource |
| [aws_backup_vault.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_efs_access_point.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_file_system.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_policy.data_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.data_nfs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.data_nfs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.data_nfs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.data_nfs_encrypted](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.backup_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.data_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_kms_alias.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_alias) | data source |
| [aws_subnet.subnets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_backup_enabled"></a> [backup_enabled](#input_backup_enabled) | Whether to create AWS Backup resources (vault, plan, IAM role, selection) protecting the EFS file system. When false, none of those resources are created and backup_vault_arn/backup_plan_id are null. | `bool` | `true` | no |
| <a name="input_backup_kms_key_arn"></a> [backup_kms_key_arn](#input_backup_kms_key_arn) | KMS key ARN for the AWS Backup vault. Default null uses the AWS-managed aws/backup key. Ignored when backup_enabled is false. | `string` | `null` | no |
| <a name="input_backup_retention_days"></a> [backup_retention_days](#input_backup_retention_days) | Number of days to retain recovery points created by the backup plan's daily rule (delete_after). Ignored when backup_enabled is false. | `number` | `14` | no |
| <a name="input_context"></a> [context](#input_context) | Shared Context from Ben's terraform-null-context | <pre>object({<br/>    attributes     = list(string)<br/>    dns_namespace  = string<br/>    environment    = string<br/>    instance       = string<br/>    instance_short = string<br/>    namespace      = string<br/>    region         = string<br/>    region_short   = string<br/>    role           = string<br/>    role_short     = string<br/>    project        = string<br/>    tags           = map(string)<br/>  })</pre> | n/a | yes |
| <a name="input_kms_efs_arn"></a> [kms_efs_arn](#input_kms_efs_arn) | ARN of the KMS key to use for encrypting the EFS volume. Default aws/elasticfilesystem will be used instead. | `string` | `null` | no |
| <a name="input_mount_path"></a> [mount_path](#input_mount_path) | Path that NFS clients access the file system. | `string` | `"/data"` | no |
| <a name="input_owner_gid"></a> [owner_gid](#input_owner_gid) | TODO | `number` | `1000` | no |
| <a name="input_owner_uid"></a> [owner_uid](#input_owner_uid) | TODO | `number` | `1000` | no |
| <a name="input_subnet_ids"></a> [subnet_ids](#input_subnet_ids) | The subnet IDs to expose NFS mount targets. | `list(string)` | `[]` | no |
| <a name="input_throughput_mode"></a> [throughput_mode](#input_throughput_mode) | Throughput mode for the EFS file system. One of bursting, elastic. Changes apply in place to the existing file system. | `string` | `"elastic"` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_point_id"></a> [access_point_id](#output_access_point_id) | EFS access point ID. |
| <a name="output_access_policy_arn"></a> [access_policy_arn](#output_access_policy_arn) | IAM policy that allows mounting and writing to the file system via the access point. |
| <a name="output_access_security_group"></a> [access_security_group](#output_access_security_group) | Security Group that allows accessing the file system via NFS mount point. |
| <a name="output_backup_plan_id"></a> [backup_plan_id](#output_backup_plan_id) | ID of the AWS Backup plan protecting the EFS file system. Null when backup_enabled is false. |
| <a name="output_backup_vault_arn"></a> [backup_vault_arn](#output_backup_vault_arn) | ARN of the AWS Backup vault protecting the EFS file system. Null when backup_enabled is false. |
| <a name="output_file_system_id"></a> [file_system_id](#output_file_system_id) | EFS file system ID. |
| <a name="output_mount_path"></a> [mount_path](#output_mount_path) | EFS mount point. |
| <a name="output_name"></a> [name](#output_name) | Name of the EFS file system. |
| <a name="output_owner_gid"></a> [owner_gid](#output_owner_gid) | TODO |
| <a name="output_owner_uid"></a> [owner_uid](#output_owner_uid) | TODO |

<!-- END_TF_DOCS -->
