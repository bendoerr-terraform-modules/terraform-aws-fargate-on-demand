module "label_cluster" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "ecs"
}

module "label_svc" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "svc"
}

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "5.2.2"
  cluster_name = module.label_cluster.id
  services = {
    (module.label_svc.id) = {
      cpu    = 256
      memory = 512
      subnet_ids = module.vpc.public_subnets
      desired_count = 0
      enable_autoscaling = false
      container_definitions = {
        alpine = {
          cpu                    = 256
          memory                 = 512
          essential              = true
          image                  = "alpine:3"
        }
      }
    }
  }
}

output "ecs_cluster" {
  value = module.ecs.cluster_name
}

output "ecs_service" {
  value = module.ecs.services[module.label_svc.id].name
}