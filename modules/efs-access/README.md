# efs-access

An on-demand helper for reading and writing the persistence EFS volume from your laptop — for
setup and testing — without weakening the file system's security model.

The data EFS lives in private space behind an access point with IAM auth and transit encryption, so
there is no direct path to it from a laptop. This module stands up a tiny, **stateless, default-off**
helper instance that mounts the access point and exposes every practical transfer lane over AWS
Systems Manager (SSM) — no bastion, no SSH key on a public port, no VPN.

## On-demand by design ($0 idle)

The helper is gated by `enabled` (default `false`). Because it is stateless — every byte of real data
lives on EFS — it is **destroyed, not stopped**, when idle. A stopped instance still bills its EBS
root volume; a destroyed one costs nothing. The IAM role, instance profile, and optional scratch
bucket are always present (they are free); only the billable instance + volume toggle.

```hcl
# bring it up to seed/test
enabled = true   # then: terraform apply   (~1-2 min to ready)

# tear it down when done
enabled = false  # then: terraform apply   ($0 idle)
```

This follows the NAT-free egress model of the `service` module: the helper gets a **public IP with no
inbound rules** and reaches SSM over the existing internet gateway, so there is no always-on NAT
gateway or interface-endpoint cost. With zero inbound rules and IMDSv2 enforced, the public IP is not
a meaningful exposure — SSM remains outbound-only.

## Transferring files

Files land owned by the access point's `owner_uid`/`owner_gid` (default `1000:1000`) — the same
identity the Fargate service runs as — so there is no ownership cleanup afterward.

### Bulk seeds (multi-GB worlds, datasets) → `aws s3 sync` or `rsync`

For anything large, use S3 as a transfer bus (set `create_transfer_bucket = true`). No SSH setup, and
it is resumable and parallel:

```bash
# from your laptop
aws s3 sync ./world s3://<transfer_bucket>/world/
# then, in an SSM shell on the helper (see connect_command)
aws s3 sync s3://<transfer_bucket>/world/ /mnt/data/world/
```

Or `rsync` straight to the helper over an SSM SSH tunnel (needs an entry in `ssh_authorized_keys` and
the `session-manager-plugin` locally; see the tunnel setup below):

```bash
rsync -avP ./world efs-helper:/mnt/data/world/
```

### Poking at a few files → sshfs (FUSE-T) as a Finder drive, or an SFTP GUI

For browsing or editing a handful of files, mount EFS as a local drive on macOS with
[FUSE-T](https://www.fuse-t.org/) + sshfs (no kernel extension, no SIP changes) — or point a GUI
client like Cyberduck/Transmit at the same SSM SSH tunnel. Lovely for convenience; not the path for a
4 GB blob (sshfs-over-SSM will crawl on bulk transfers — use `aws s3 sync`/`rsync` for those).

### SSH-over-SSM tunnel setup (for rsync / sshfs / SFTP lanes)

Add to `~/.ssh/config`, then the lanes above can address the host as `efs-helper`:

```
Host efs-helper
  HostName <instance_id>
  User ec2-user
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
```

The simplest lane — an interactive shell, no keys required — is just the `connect_command` output:
`aws ssm start-session --target <instance_id>`.

## Example

See [`examples/complete`](./examples/complete) for a full wiring of VPC + `persistence` + `efs-access`.

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version |
| ------------------------------------------------------------------------ | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 0.13 |
| <a name="requirement_aws"></a> [aws](#requirement_aws)                   | ~> 6.32 |

## Providers

| Name                                             | Version |
| ------------------------------------------------ | ------- |
| <a name="provider_aws"></a> [aws](#provider_aws) | ~> 6.32 |

## Modules

| Name                                                                          | Source                                                         | Version |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------- | ------- |
| <a name="module_label"></a> [label](#module_label)                            | git@github.com:bendoerr-terraform-modules/terraform-null-label | v1.0.0  |
| <a name="module_label_transfer"></a> [label_transfer](#module_label_transfer) | git@github.com:bendoerr-terraform-modules/terraform-null-label | v1.0.0  |

## Resources

| Name                                                                                                                                                                                      | Type        |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile)                                                         | resource    |
| [aws_iam_policy.transfer_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy)                                                                      | resource    |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)                                                                                 | resource    |
| [aws_iam_role_policy_attachment.efs_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment)                                           | resource    |
| [aws_iam_role_policy_attachment.ssm_core](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment)                                         | resource    |
| [aws_iam_role_policy_attachment.transfer_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment)                                      | resource    |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance)                                                                                 | resource    |
| [aws_s3_bucket.transfer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)                                                                           | resource    |
| [aws_s3_bucket_ownership_controls.transfer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls)                                     | resource    |
| [aws_s3_bucket_public_access_block.transfer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block)                                   | resource    |
| [aws_s3_bucket_server_side_encryption_configuration.transfer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource    |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document)                                                 | data source |
| [aws_iam_policy_document.transfer_rw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document)                                                 | data source |
| [aws_ssm_parameter.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter)                                                                  | data source |

## Inputs

| Name                                                                                                                     | Description                                                                                                                                                                                                                                                                                                                                                      | Type                                                                                                                                                                                                                                                                                                                      | Default       | Required |
| ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | :------: |
| <a name="input_context"></a> [context](#input_context)                                                                   | Shared Context from Ben's terraform-null-context                                                                                                                                                                                                                                                                                                                 | <pre>object({<br> attributes = list(string)<br> dns_namespace = string<br> environment = string<br> instance = string<br> instance_short = string<br> namespace = string<br> region = string<br> region_short = string<br> role = string<br> role_short = string<br> project = string<br> tags = map(string)<br> })</pre> | n/a           |   yes    |
| <a name="input_access_point_id"></a> [access_point_id](#input_access_point_id)                                           | EFS access point ID to mount through, from the persistence module's access_point_id output. The access point enforces the POSIX owner_uid/owner_gid on every write.                                                                                                                                                                                              | `string`                                                                                                                                                                                                                                                                                                                  | n/a           |   yes    |
| <a name="input_access_policy_arn"></a> [access_policy_arn](#input_access_policy_arn)                                     | IAM policy ARN granting EFS ClientMount/ClientWrite scoped to the access point, from the persistence module's access_policy_arn output. Attached to the helper's instance role for the iam mount option.                                                                                                                                                         | `string`                                                                                                                                                                                                                                                                                                                  | n/a           |   yes    |
| <a name="input_access_security_group"></a> [access_security_group](#input_access_security_group)                         | Security group that permits NFS to the EFS mount targets, from the persistence module's access_security_group output. Attached to the helper so it can reach the file system; its all-egress rule also carries the SSM traffic.                                                                                                                                  | `string`                                                                                                                                                                                                                                                                                                                  | n/a           |   yes    |
| <a name="input_file_system_id"></a> [file_system_id](#input_file_system_id)                                              | EFS file system ID to mount, from the persistence module's file_system_id output.                                                                                                                                                                                                                                                                                | `string`                                                                                                                                                                                                                                                                                                                  | n/a           |   yes    |
| <a name="input_subnet_id"></a> [subnet_id](#input_subnet_id)                                                             | A PUBLIC subnet to place the helper in. This module follows the NAT-free egress model of the service module: the instance gets a public IP (no inbound rules) and reaches AWS Systems Manager over the existing internet gateway, avoiding an always-on NAT gateway or interface endpoints.                                                                      | `string`                                                                                                                                                                                                                                                                                                                  | n/a           |   yes    |
| <a name="input_ami_id"></a> [ami_id](#input_ami_id)                                                                      | AMI ID for the helper. Defaults to the latest Amazon Linux 2023 arm64 AMI resolved from the public SSM parameter when null.                                                                                                                                                                                                                                      | `string`                                                                                                                                                                                                                                                                                                                  | `null`        |    no    |
| <a name="input_assign_public_ip"></a> [assign_public_ip](#input_assign_public_ip)                                        | Assign a public IP so the SSM agent can reach Systems Manager over the internet gateway without a NAT gateway. Combined with zero inbound security-group rules and IMDSv2, the public IP is not a meaningful exposure because SSM remains outbound-only. Only set to false if the subnet already has SSM-reachable egress (NAT or interface endpoints).          | `bool`                                                                                                                                                                                                                                                                                                                    | `true`        |    no    |
| <a name="input_create_transfer_bucket"></a> [create_transfer_bucket](#input_create_transfer_bucket)                      | Create a scratch S3 bucket for the aws s3 sync transfer lane and grant the helper read/write to it. When false, use your own bucket and attach S3 permissions yourself.                                                                                                                                                                                          | `bool`                                                                                                                                                                                                                                                                                                                    | `false`       |    no    |
| <a name="input_enabled"></a> [enabled](#input_enabled)                                                                   | Whether the helper instance and its EBS volume exist. Defaults to false so the module costs $0 when idle. The IAM role, instance profile, and (optional) transfer bucket are always created since they are free; only the billable instance + volume are gated. Set to true and apply when you need to seed or inspect the volume, then back to false when done. | `bool`                                                                                                                                                                                                                                                                                                                    | `false`       |    no    |
| <a name="input_instance_type"></a> [instance_type](#input_instance_type)                                                 | Instance type for the helper. Defaults to the cheapest current-gen Graviton (arm64) size; keep it arm64 to match the default AL2023 arm64 AMI.                                                                                                                                                                                                                   | `string`                                                                                                                                                                                                                                                                                                                  | `"t4g.nano"`  |    no    |
| <a name="input_kms_ebs_arn"></a> [kms_ebs_arn](#input_kms_ebs_arn)                                                       | ARN of the KMS key for encrypting the root EBS volume. Defaults to the account's aws/ebs managed key when null.                                                                                                                                                                                                                                                  | `string`                                                                                                                                                                                                                                                                                                                  | `null`        |    no    |
| <a name="input_mount_path"></a> [mount_path](#input_mount_path)                                                          | Path on the helper instance where the EFS access point is mounted.                                                                                                                                                                                                                                                                                               | `string`                                                                                                                                                                                                                                                                                                                  | `"/mnt/data"` |    no    |
| <a name="input_owner_gid"></a> [owner_gid](#input_owner_gid)                                                             | POSIX GID the access point enforces on writes, from the persistence module's owner_gid output. Surfaced so operators know which GID will own seeded files.                                                                                                                                                                                                       | `number`                                                                                                                                                                                                                                                                                                                  | `1000`        |    no    |
| <a name="input_owner_uid"></a> [owner_uid](#input_owner_uid)                                                             | POSIX UID the access point enforces on writes, from the persistence module's owner_uid output. Surfaced so operators know which UID will own seeded files.                                                                                                                                                                                                       | `number`                                                                                                                                                                                                                                                                                                                  | `1000`        |    no    |
| <a name="input_root_volume_size"></a> [root_volume_size](#input_root_volume_size)                                        | Size in GiB of the encrypted gp3 root volume. The helper is stateless (all data lives on EFS), so this only needs to hold the OS.                                                                                                                                                                                                                                | `number`                                                                                                                                                                                                                                                                                                                  | `8`           |    no    |
| <a name="input_ssh_authorized_keys"></a> [ssh_authorized_keys](#input_ssh_authorized_keys)                               | Public SSH keys to authorize for the ec2-user. Required only for the rsync / scp / sshfs (FUSE-T) / SFTP-over-SSM transfer lanes; the aws s3 sync lane and an interactive SSM shell need no keys.                                                                                                                                                                | `list(string)`                                                                                                                                                                                                                                                                                                            | `[]`          |    no    |
| <a name="input_transfer_bucket_force_destroy"></a> [transfer_bucket_force_destroy](#input_transfer_bucket_force_destroy) | Allow terraform destroy to delete the scratch transfer bucket even if it still holds objects. Defaults to true because the bucket is staging-only scratch; set to false if you want destroy to refuse on a non-empty bucket.                                                                                                                                     | `bool`                                                                                                                                                                                                                                                                                                                    | `true`        |    no    |

## Outputs

| Name                                                                                   | Description                                                                            |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| <a name="output_connect_command"></a> [connect_command](#output_connect_command)       | Ready-to-run command to open an SSM shell on the helper, or null when disabled.        |
| <a name="output_instance_id"></a> [instance_id](#output_instance_id)                   | ID of the helper instance, or null when enabled = false.                               |
| <a name="output_instance_role_arn"></a> [instance_role_arn](#output_instance_role_arn) | ARN of the helper's instance role (carries SSM + EFS access).                          |
| <a name="output_mount_path"></a> [mount_path](#output_mount_path)                      | Path on the helper where the EFS access point is mounted.                              |
| <a name="output_owner_gid"></a> [owner_gid](#output_owner_gid)                         | POSIX GID the access point enforces on writes; seeded files will be owned by this GID. |
| <a name="output_owner_uid"></a> [owner_uid](#output_owner_uid)                         | POSIX UID the access point enforces on writes; seeded files will be owned by this UID. |
| <a name="output_transfer_bucket"></a> [transfer_bucket](#output_transfer_bucket)       | Name of the scratch transfer bucket, or null when create_transfer_bucket = false.      |

<!-- END_TF_DOCS -->
