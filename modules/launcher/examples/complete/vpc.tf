module "label_network" {
  source  = "git@github.com:bendoerr-terraform-modules/terraform-null-label?ref=v0.4.0"
  context = module.context.shared
  name    = "ntwrk"
}

module "vpc" {
  source     = "terraform-aws-modules/vpc/aws"
  version    = "5.1.1"
  create_vpc = true

  name = module.label_network.id

  cidr           = "10.10.0.0/16"
  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.10.1.0/24", "10.10.2.0/24"]

  enable_nat_gateway = false
}