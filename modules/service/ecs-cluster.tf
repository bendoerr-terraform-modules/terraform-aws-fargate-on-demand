# tfsec:ignore:aws-ecs-enable-container-insight
resource "aws_ecs_cluster" "svc" {
  name = module.label.id
  tags = module.label.tags

  setting {
    # Metrics collected by Container Insights are charged as Custom Metrics.
    #
    # Pricing[1]:
    #   $0.30 per custom metric per month (first 10,000 metrics).
    #   All custom metric charges are prorated by the hour — you are only
    #   billed for hours in which metrics are actually sent.
    #
    # What this means for on-demand Fargate:
    #   Cluster-level metrics (ServiceCount, TaskCount, etc.) are emitted
    #   continuously while the cluster exists, so those cost the full month.
    #   Task and service-level metrics (CpuUtilized, MemoryUtilized,
    #   NetworkRxBytes, etc.) are only emitted while tasks are running.
    #   Since this module spins tasks up on demand and back down when idle,
    #   those metrics are prorated to actual uptime hours — making the real
    #   cost significantly less than the worst-case estimate below.
    #
    # Metric count[2]:
    #   AWS currently publishes 23+ ECS Container Insights metrics. Not all
    #   apply to Fargate (instance-level metrics are EC2-only). The exact
    #   number of custom metrics billed depends on active dimension
    #   combinations (cluster, service, task family).
    #
    # Infracost does not support custom metric pricing (there is no
    # associated Terraform resource for them).
    #
    # [1]: https://aws.amazon.com/cloudwatch/pricing/
    # [2]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html
    #
    # Worst-case estimate (all metrics emitted 24/7):
    #   ~20 applicable metrics * $0.30/metric = ~$6.00/month
    # Realistic estimate for on-demand usage (e.g. 40h/month):
    #   Cluster metrics (~5): $1.50/month (always on)
    #   Task metrics (~15): 15 * $0.30 * (40/730) ≈ $0.25/month
    #   Total: ~$1.75/month
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
