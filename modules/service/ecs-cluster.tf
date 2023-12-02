resource "aws_ecs_cluster" "svc" {
  name = module.label.id
  tags = module.label.tags

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "svc" {
  cluster_name       = aws_ecs_cluster.svc.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
  }
}
