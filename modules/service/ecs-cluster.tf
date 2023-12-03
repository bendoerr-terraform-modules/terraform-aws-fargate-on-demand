# tfsec:ignore:aws-ecs-enable-container-insight
resource "aws_ecs_cluster" "svc" {
  name = module.label.id
  tags = module.label.tags

  setting {
    # Metrics collected by Container Insights are charged as Custom Metrics
    #
    # ! Pricing is $0.30/Custom Metric/Month[1]
    # ! There are 18 Custom Metrics[2]
    # ! All custom metrics charges are prorated[1] by the hour.
    #   Problematic for our module since the cluster and task will exist for
    #   the whole month. Only the tasks will be spun up and down.
    # ! Infracost does not support Custom Metric Pricing
    #   (There isn't an associated resource for them)
    #
    # [1]: CloudWatch Pricing: https://aws.amazon.com/cloudwatch/pricing/
    # [2]: ECS Container Insight Metrics: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html
    #
    # Expected Cost for Enabling Container Insights
    # 18 metrics * $0.30/metric = $5.40/month
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
