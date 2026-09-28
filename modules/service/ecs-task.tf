locals {
  # Default sidecar images, keyed by custodian.kind. Used when custodian.image
  # is null.
  custodian_default_images = {
    tcp       = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-custodian:0.1.3"
    minecraft = "ghcr.io/bendoerr-terraform-modules/terraform-aws-fargate-on-demand-minecraft-custodian:v0.1.0"
  }

  custodian_image = coalesce(var.custodian.image, local.custodian_default_images[var.custodian.kind])

  # "tcp" kind sidecar env (today's watchdog), in the exact order it has
  # always rendered in. custodian.environment overrides a built-in entry's
  # value IN PLACE (same name, same position) rather than appending a
  # duplicate, and any other custodian.environment entries are appended
  # after, in map-iteration (sorted key) order. With an empty
  # custodian.environment, custodian_tcp_environment is byte-identical to
  # today's hard-coded list.
  custodian_tcp_builtin_env = [
    { name = "DNS_ZONE_ID", value = var.dns_zone_id },
    { name = "DNS_RECORD", value = var.dns_record },
    { name = "WATCH_IDLE", value = var.idle_seconds },
    { name = "WATCH_TCP", value = tostring(var.custodian.tcp_port) },
    { name = "SNS_TOPIC_ARN", value = aws_sns_topic.notifications.arn },
  ]

  custodian_tcp_builtin_names = toset([for e in local.custodian_tcp_builtin_env : e.name])

  custodian_tcp_environment = concat(
    [
      for e in local.custodian_tcp_builtin_env : {
        name  = e.name
        value = lookup(var.custodian.environment, e.name, e.value)
      }
    ],
    [
      for name, value in var.custodian.environment : { name = name, value = value }
      if !contains(local.custodian_tcp_builtin_names, name)
    ]
  )

  # "minecraft" kind sidecar env (spec §4.2): built-ins merged with
  # custodian.environment (later wins), then converted below to the
  # name/value list. Terraform's for-over-map always iterates in sorted key
  # order, so the resulting list order is stable across plans regardless of
  # map insertion order.
  custodian_minecraft_environment = merge(
    {
      CUSTODIAN_CLUSTER       = aws_ecs_cluster.svc.name
      CUSTODIAN_SERVICE       = module.label.id
      CUSTODIAN_DNS_ZONE_ID   = var.dns_zone_id
      CUSTODIAN_DNS_RECORD    = var.dns_record
      CUSTODIAN_SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
      CUSTODIAN_IDLE_TIMEOUT  = "${var.idle_seconds}s"
      CUSTODIAN_GATE_TIMEOUT  = "110s"
    },
    var.custodian.environment
  )

  service_container_definition = merge(
    {
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
    },
    # Only the "minecraft" kind's app container waits on the sidecar and
    # gets extra shutdown time (spec §4.2); "tcp" stays byte-identical to
    # today. The for/if filter (rather than a ternary) avoids Terraform
    # having to unify an empty object's type with this one's, and yields no
    # keys at all (not null-valued keys) when the condition is false.
    {
      for k, v in {
        dependsOn = [
          {
            containerName = module.label_wd.id
            condition     = "HEALTHY"
          }
        ]
        stopTimeout = 120
      } : k => v if var.custodian.kind == "minecraft"
    }
  )

  # Per-kind sidecar container definitions, chosen by custodian.kind below.
  watchdog_container_definitions = {
    tcp = {
      name        = module.label_wd.id
      image       = local.custodian_image
      environment = local.custodian_tcp_environment
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-region"        = var.context.region
          "awslogs-group"         = aws_cloudwatch_log_group.svc.name
          "awslogs-stream-prefix" = module.label_wd.name
        }
      }
    }

    minecraft = {
      name      = module.label_wd.id
      image     = local.custodian_image
      essential = true
      environment = [
        for name, value in local.custodian_minecraft_environment : { name = name, value = value }
      ]
      healthCheck = {
        command     = ["CMD", "/custodian", "healthcheck"]
        interval    = 5
        timeout     = 2
        startPeriod = 240
        retries     = 3
      }
      startTimeout = 120
      stopTimeout  = 120
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
