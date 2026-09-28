locals {
  # Default sidecar images, keyed by custodian.kind. Used when custodian.image
  # is null. The "minecraft" entry is data only (spec §4.1); its container
  # wiring is a later step's job (see watchdog_container_definitions below).
  custodian_default_images = {
    tcp       = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-custodian:0.1.3"
    minecraft = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-minecraft-custodian:v0.1.0"
  }

  custodian_image = coalesce(var.custodian.image, local.custodian_default_images[var.custodian.kind])

  # custodian.environment, converted to the container-definition environment
  # shape and appended after each kind's built-in entries below, so a name
  # collision overrides the built-in value (later entry wins).
  custodian_environment_overrides = [
    for name, value in var.custodian.environment : { name = name, value = value }
  ]

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

  # Per-kind sidecar container definitions, chosen by custodian.kind below.
  # Only "tcp" is implemented here; a later step adds "minecraft" (health
  # check, dependsOn on the app container, timeouts per spec §4.2).
  watchdog_container_definitions = {
    tcp = {
      name  = module.label_wd.id
      image = local.custodian_image
      environment = concat(
        [
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
            value = tostring(var.custodian.tcp_port)
          },
          {
            name  = "SNS_TOPIC_ARN"
            value = aws_sns_topic.notifications.arn
          }
        ],
        local.custodian_environment_overrides
      )
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.context.region
          "awslogs-group"         = aws_cloudwatch_log_group.svc.name
          "awslogs-stream-prefix" = module.label_wd.name
        }
      }
    }
  }

  watchdog_container_definition = local.watchdog_container_definitions[var.custodian.kind]

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

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

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
