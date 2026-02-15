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
    # Observability modes (as of Dec 2024)[2]:
    #   This module uses standard observability (setting value "enabled").
    #   Enhanced observability ("enhanced") was released Dec 2024 and adds
    #   per-task-definition and per-container metrics at higher cardinality.
    #
    # Metric counts for Fargate standard observability[2]:
    #   Cluster-level:  13 metrics
    #   Service-level:  15 metrics
    #   Task-level:     10 metrics
    #   Total billed = 13×(clusters) + 15×(services) + 10×(tasks)
    #   Increasing running task instances does NOT increase metric count —
    #   metrics are aggregated by task and service name.
    #
    # For reference, Fargate enhanced observability adds:
    #   Cluster: 29, Service: 31, Task-def: 26, Task: 26, Container: 26
    #
    # Infracost does not support custom metric pricing (there is no
    # associated Terraform resource for them).
    #
    # [1]: https://aws.amazon.com/cloudwatch/pricing/
    # [2]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-metrics-ECS.html
    # Pricing validated: Feb 2026
    #
    # Worst-case estimate (all metrics emitted 24/7, 1 cluster + 1 service):
    #   (13 + 15 + 10) = 38 metrics * $0.30/metric = ~$11.40/month
    # Realistic estimate for on-demand usage (e.g. 40h/month):
    #   Cluster metrics (13): $3.90/month (always on)
    #   Service metrics (15): $4.50/month (always on while service exists)
    #   Task metrics (10): 10 * $0.30 * (40/730) ≈ $0.16/month
    #   Total: ~$8.56/month
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
