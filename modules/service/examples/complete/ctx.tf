variable "namespace" {
  type = string
}

module "context" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.5.2"
  namespace   = var.namespace
  environment = "testing"
  role        = "development"
  region      = "us-east-1"
  project     = "service"
}

# Second service's own context: same namespace/environment/role/region/project
# as module.context, but with an attribute appended so every label module
# call downstream (service, dns-record) produces a disambiguated id/name that
# does not collide with the first (tcp) service's resources.
module "context_mc" {
  source      = "git@github.com:bendoerr-terraform-modules/terraform-null-context?ref=v0.5.2"
  namespace   = var.namespace
  environment = "testing"
  role        = "development"
  region      = "us-east-1"
  project     = "service"
  attributes  = ["mc"]
}
