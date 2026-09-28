data "aws_caller_identity" "current" {}

module "label_backup_vault" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "data-backup-vault"
}

resource "aws_backup_vault" "data" {
  count       = var.backup_enabled ? 1 : 0
  name        = module.label_backup_vault.id
  tags        = module.label_backup_vault.tags
  kms_key_arn = var.backup_kms_key_arn
}

module "label_backup_plan" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "data-backup-plan"
}

resource "aws_backup_plan" "data" {
  count = var.backup_enabled ? 1 : 0
  name  = module.label_backup_plan.id
  tags  = module.label_backup_plan.tags

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.data[0].name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }
}

module "label_backup_role" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v1.0.1"
  context = var.context
  name    = "data-backup"
}

data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "backup" {
  count              = var.backup_enabled ? 1 : 0
  name               = module.label_backup_role.id
  tags               = module.label_backup_role.tags
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  count      = var.backup_enabled ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "data" {
  count        = var.backup_enabled ? 1 : 0
  name         = module.label_backup_plan.id
  plan_id      = aws_backup_plan.data[0].id
  iam_role_arn = aws_iam_role.backup[0].arn
  resources    = [aws_efs_file_system.data.arn]
}
