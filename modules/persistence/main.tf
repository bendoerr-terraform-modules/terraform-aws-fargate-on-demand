module "label_data" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "data"
}

resource "aws_efs_file_system" "data" {
  creation_token = module.label_data.id
  tags           = module.label_data.tags
  encrypted      = var.encrypted
}

resource "aws_efs_access_point" "data" {
  file_system_id = aws_efs_file_system.data.id
  tags           = module.label_data.tags

  root_directory {
    path = var.mount_path
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }
  posix_user {
    gid = 1000
    uid = 1000
  }
}

data "aws_subnet" "subnets" {
  count = length(var.subnet_ids)
  id    = var.subnet_ids[count.index]
}

locals {
  vpc_id = data.aws_subnet.subnets[0].vpc_id
}

resource "aws_efs_mount_target" "data" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.data_nfs.id]
}

data "aws_iam_policy_document" "data_rw" {
  statement {
    effect  = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeFileSystems",
    ]
    resources = [aws_efs_file_system.data.arn]
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [aws_efs_access_point.data.arn]
    }
  }
}

module "label_data_rw" {
  source  = "git@github.com:bendoerr/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "data-rw"
}

resource "aws_iam_policy" "data_rw" {
  name   = module.label_data_rw.id
  tags   = module.label_data_rw.tags
  policy = data.aws_iam_policy_document.data_rw.json
}

module "label_data_nfs" {
  source  = "git@github.com:bendoerr/terraform-null-label?ref=v0.4.0"
  context = var.context
  name    = "data-nfs"
}

resource "aws_security_group" "data_nfs" {
  name   = module.label_data_nfs.id
  tags   = module.label_data_nfs.tags
  vpc_id = local.vpc_id
}


resource "aws_vpc_security_group_ingress_rule" "data_nfs_encrypted" {
  security_group_id            = aws_security_group.data_nfs.id
  referenced_security_group_id = aws_security_group.data_nfs.id
  ip_protocol                  = "TCP"
  from_port                    = 2999
  to_port                      = 2999
  tags                         = module.label_data_nfs.tags
}

resource "aws_vpc_security_group_ingress_rule" "data_nfs" {
  security_group_id            = aws_security_group.data_nfs.id
  referenced_security_group_id = aws_security_group.data_nfs.id
  ip_protocol                  = "TCP"
  from_port                    = 2049
  to_port                      = 2049
  tags                         = module.label_data_nfs.tags
}

resource "aws_vpc_security_group_egress_rule" "data_nfs" {
  security_group_id            = aws_security_group.data_nfs.id
  referenced_security_group_id = aws_security_group.data_nfs.id
  ip_protocol                  = -1
  tags                         = module.label_data_nfs.tags
}