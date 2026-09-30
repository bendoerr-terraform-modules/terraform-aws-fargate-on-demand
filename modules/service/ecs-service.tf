resource "aws_ecs_service" "svc" {
  name = module.label.id
  tags = module.label.tags

  cluster         = aws_ecs_cluster.svc.id
  task_definition = aws_ecs_task_definition.svc.arn

  desired_count    = 0
  platform_version = "LATEST"
  propagate_tags   = "SERVICE"

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  capacity_provider_strategy {
    capacity_provider = var.capacity_provider
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets = var.service_subnet_ids
    security_groups = [
      aws_security_group.mc.id,
      var.persistence_access_security_group
    ]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [
      desired_count,
      # task_definition
    ]
  }
}

resource "aws_security_group" "mc" {
  name        = module.label.id
  tags        = module.label.tags
  description = "Main service: Allow inbound to configured ports and outbound anywhere"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "mc_allow_port" {
  for_each = {
    for i, m in var.port_mappings :
    m.hostPort => m
  }
  security_group_id = aws_security_group.mc.id
  tags              = module.label.tags

  description = "Inbound to configured game/service port ${each.value.hostPort}"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = each.value.hostPort
  to_port     = each.value.hostPort
  ip_protocol = each.value.protocol
}

# Unrestricted egress is required: the task pulls its container image, calls AWS
# APIs (ECS/CloudWatch/SSM), and Minecraft server auth talks to Mojang/Microsoft
# endpoints, none of which resolve to a fixed, allowlist-able CIDR range.
# trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "mc_allow_egress" {
  security_group_id = aws_security_group.mc.id
  tags              = module.label.tags

  description = "All outbound for image pulls, AWS API calls, and Minecraft auth"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}
