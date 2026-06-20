module "label" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.0"
  context = var.context
  name    = "efs-acc"
}

locals {
  enabled = var.enabled ? 1 : 0
  ami_id  = var.ami_id != null ? var.ami_id : nonsensitive(data.aws_ssm_parameter.al2023[0].value)

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    mount_path          = var.mount_path
    file_system_id      = var.file_system_id
    access_point_id     = var.access_point_id
    ssh_authorized_keys = var.ssh_authorized_keys
  })
}

# Latest Amazon Linux 2023 arm64 AMI, published by AWS as a public SSM parameter.
# Skipped entirely when the caller supplies an explicit ami_id.
data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------------------------------------------------------------------------
# Instance role + profile. Always created (IAM is free); only the instance and
# its EBS volume are gated by var.enabled so idle cost stays at $0.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = module.label.id
  tags               = module.label.tags
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Interactive shell + the SSH-over-SSM tunnel used by every transfer lane.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EFS ClientMount/ClientWrite, already scoped to the access point by persistence.
resource "aws_iam_role_policy_attachment" "efs_rw" {
  role       = aws_iam_role.this.name
  policy_arn = var.access_policy_arn
}

resource "aws_iam_instance_profile" "this" {
  name = module.label.id
  tags = module.label.tags
  role = aws_iam_role.this.name
}

# ---------------------------------------------------------------------------
# Optional scratch bucket for the `aws s3 sync` transfer lane.
# ---------------------------------------------------------------------------
module "label_transfer" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.0"
  context = var.context
  name    = "efs-acc-xfer"
}

# A staging-only scratch bucket: encrypted, fully public-access-blocked, owner
# enforced. Versioning and access logging are intentionally omitted because the
# bucket is transient (force_destroy) and holds nothing of record, so access
# logging and versioning add no value on this scratch storage.
# trivy:ignore:AVD-AWS-0089
# trivy:ignore:AVD-AWS-0090
resource "aws_s3_bucket" "transfer" {
  count         = var.create_transfer_bucket ? 1 : 0
  bucket        = module.label_transfer.id
  tags          = module.label_transfer.tags
  force_destroy = var.transfer_bucket_force_destroy
}

resource "aws_s3_bucket_public_access_block" "transfer" {
  count                   = var.create_transfer_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.transfer[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 (AES256), not a customer-managed KMS key: a CMK costs ~$1/mo just to
# exist, which would break this module's $0-idle goal for a transient scratch
# bucket. SSE-S3 is the appropriate, free choice here.
# trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "transfer" {
  count  = var.create_transfer_bucket ? 1 : 0
  bucket = aws_s3_bucket.transfer[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "transfer" {
  count  = var.create_transfer_bucket ? 1 : 0
  bucket = aws_s3_bucket.transfer[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "transfer_rw" {
  count = var.create_transfer_bucket ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.transfer[0].arn,
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.transfer[0].arn}/*",
    ]
  }
}

resource "aws_iam_policy" "transfer_rw" {
  count  = var.create_transfer_bucket ? 1 : 0
  name   = module.label_transfer.id
  tags   = module.label_transfer.tags
  policy = data.aws_iam_policy_document.transfer_rw[0].json
}

resource "aws_iam_role_policy_attachment" "transfer_rw" {
  count      = var.create_transfer_bucket ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.transfer_rw[0].arn
}

# ---------------------------------------------------------------------------
# Egress security group. The persistence data_nfs SG only permits egress to its
# own members (the mount targets), so the helper needs its own outbound rule to
# reach the SSM endpoints and the package mirrors. No ingress -- SSM is
# outbound-only. Always created (an empty SG is free) so idle cost stays at $0.
# ---------------------------------------------------------------------------
data "aws_subnet" "this" {
  id = var.subnet_id
}

module "label_egress" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.0"
  context = var.context
  name    = "efs-acc-egr"
}

resource "aws_security_group" "egress" {
  name        = module.label_egress.id
  tags        = module.label_egress.tags
  vpc_id      = data.aws_subnet.this.vpc_id
  description = "efs-access helper outbound for SSM + package install; no inbound"
}

# Unrestricted egress: an SSM-managed helper must reach the SSM endpoints and the
# AL2023 package mirrors, whose IPs span large, shifting AWS ranges -- the same
# outbound posture the service module uses. There are zero inbound rules, so the
# box cannot be reached from outside.
# trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "egress" {
  security_group_id = aws_security_group.egress.id
  tags              = module.label_egress.tags
  description       = "All outbound for SSM registration and package install"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

# ---------------------------------------------------------------------------
# The helper itself. Gated by var.enabled -> destroy, don't stop, for true $0
# idle (a stopped instance still bills its EBS volume).
# ---------------------------------------------------------------------------
# A public IP is required so the SSM agent can reach Systems Manager over the
# existing internet gateway (this VPC runs NAT-free, matching the service module).
# With zero inbound rules and IMDSv2 enforced, SSM stays outbound-only, so the
# public IP (required for SSM egress in this NAT-free VPC) is not an exposure.
# trivy:ignore:AVD-AWS-0009
resource "aws_instance" "this" {
  count = local.enabled

  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.assign_public_ip
  vpc_security_group_ids      = [var.access_security_group, aws_security_group.egress.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  user_data                   = local.user_data

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size
    kms_key_id  = var.kms_ebs_arn
  }

  tags = module.label.tags
}
