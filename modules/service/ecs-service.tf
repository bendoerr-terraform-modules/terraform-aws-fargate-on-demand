resource "aws_ecs_service" "svc" {
  name = module.label.id
  tags = module.label.tags

  cluster         = aws_ecs_cluster.svc.id
  task_definition = aws_ecs_task_definition.svc.family

  desired_count    = 0
  platform_version = "LATEST"
  propagate_tags   = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets         = var.service_subnet_ids
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
  name   = module.label.id
  tags   = module.label.tags
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "mc_allow_port" {
  for_each = {
    for i, m in var.port_mappings:
        m.hostPort => m
  }
  security_group_id = aws_security_group.mc.id
  tags              = module.label.tags

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = each.value.hostPort
  to_port     = each.value.hostPort
  ip_protocol = each.value.protocol
}

resource "aws_vpc_security_group_egress_rule" "mc_allow_egress" {
  security_group_id = aws_security_group.mc.id
  tags              = module.label.tags

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}
