locals {
  service_container_definition = {
    name         = module.label.id
    tags         = module.label.tags
    image        = var.service_image
    portMappings = var.port_mappings != null ? var.port_mappings : []
    environment  = var.environment_variables != null ? var.environment_variables : []
    secrets      = var.secret_variables != null ? var.secret_variables : []

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-region"        = var.context.region
        "awslogs-group"         = aws_cloudwatch_log_group.svc.name
        "awslogs-stream-prefix" = module.label.name
      }
    }

    mountPoints = [
      {
        containerPath = var.data_mount_path
        sourceVolume  = module.label_data.id,
        readOnly      = false,
      }
    ]
  }

  watchdog_container_definition = {
    name  = module.label_wd.id
    image = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-custodian:main"
    environment = [
      {
        name  = "DNS_ZONE_ID"
        value = var.dns_zone_id
      },
      {
        name  = "DNS_RECORD"
        value = var.dns_record
      },
      {
        name  = "WATCH_IDLE"
        value = var.idle_seconds
      },
      {
        name  = "WATCH_TCP"
        value = "30000"
      },
      {
        name  = "SNS_TOPIC_ARN"
        value = aws_sns_topic.notifications.arn
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-region"        = var.context.region
        "awslogs-group"         = aws_cloudwatch_log_group.svc.name
        "awslogs-stream-prefix" = module.label_wd.name
      }
    }
  }

  container_definitions = flatten([
    [local.service_container_definition], [local.watchdog_container_definition], var.additional_container_definitions
  ])
}

resource "aws_ecs_task_definition" "svc" {
  family = module.label.id
  tags   = module.label.tags

  cpu                      = var.task_cpu
  memory                   = var.task_memory
  task_role_arn            = aws_iam_role.svc.arn
  execution_role_arn       = aws_iam_role.svc.arn
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  container_definitions    = jsonencode(local.container_definitions)

  volume {
    name = module.label_data.id
    efs_volume_configuration {
      file_system_id     = var.data_file_system_id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = var.data_access_point_id
        iam             = "ENABLED"
      }
    }
  }
}
