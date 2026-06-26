<br/>
<p align="center">
  <a href="https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
      <img src="docs/logo-light.png" alt="Logo">
    </picture>
  </a>

<h3 align="center">Ben's Terraform AWS Fargate on Demand Module</h3>

<p align="center">
    This is how I do it.
    <br/>
    <br/>
    <a href="https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand"><strong>Explore the docs »</strong></a>
    <br/>
    <br/>
    <a href="https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/issues">Report Bug</a>
    .
    <a href="https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/issues">Request Feature</a>
  </p>
</p>

![Contributors](https://img.shields.io/github/contributors/bendoerr-terraform-modules/terraform-aws-fargate-on-demand?color=dark-green) ![Issues](https://img.shields.io/github/issues/bendoerr-terraform-modules/terraform-aws-fargate-on-demand) ![GitHub Workflow Status (with event)](https://img.shields.io/github/actions/workflow/status/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/test.yml)
![GitHub tag (with filter)](https://img.shields.io/github/v/tag/bendoerr-terraform-modules/terraform-aws-fargate-on-demand?filter=v*)
![License](https://img.shields.io/github/license/bendoerr-terraform-modules/terraform-aws-fargate-on-demand)

## About The Project

Ever wanted to run Minecraft or Foundry VTT on AWS -- but! DAMN $20/month is so
expensive?! Well I did. If you don't mind a minute or two while things start up
and want crazy cheap hosting for these services -- a few dollars a month -- then
this module is for you! No seriously around $1.50 for 20 hours of uptime.

## Usage

```
TODO
}
```

## Version Constraints

This repository is a **monorepo** of related Terraform modules under
[`modules/`](modules/); each submodule declares its own provider requirements in
its own `versions.tf`. Those submodules use **pessimistic version constraints**
(`~>`) for the AWS provider:

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 6.0" # Allows 6.x, prevents 7.0
  }
}
```

**Why pessimistic constraints?**

- Prevents unexpected breaking changes from major provider updates
- Ensures consistent behavior across environments
- Makes upgrade impact predictable and controllable

When AWS provider v7.0 releases, the affected submodules will require an update to
support it. That is intentional — we prefer explicit, tested upgrades over
automatic major version bumps. Consume the individual submodules under
[`modules/`](modules/); Terraform's dependency resolver will select an AWS
provider version compatible with both your configuration and the submodule's
constraints.

## Requirements

TODO

## Providers

TODO

## Modules

TODO

## Resources

TODO

## Inputs

TODO

## Outputs

TODO

## Roadmap

See the [open issues](https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/issues) for a list of proposed features (and known issues).

## Contributing

Contributions are what make the open source community such an amazing place to be learn, inspire, and create. Any contributions you make are **greatly appreciated**.

- If you have suggestions for adding or removing projects, feel free to [open an issue](https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/issues/new) to discuss it, or directly create a pull request after you edit the _README.md_ file with necessary changes.
- Please make sure you check your spelling and grammar.
- Create individual PR for each suggestion.

### Creating A Pull Request

1. Fork the Project
1. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
1. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
1. Push to the Branch (`git push origin feature/AmazingFeature`)
1. Open a Pull Request

## License

Distributed under the MIT License. See [LICENSE](https://github.com/bendoerr-terraform-modules/terraform-aws-fargate-on-demand/blob/main/LICENSE.txt) for more information.

## Authors

- **Benjamin R. Doerr** - _Terraformer_ - [Benjamin R. Doerr](https://github.com/bendoerr/) - _Built Ben's Terraform Modules_

## Acknowledgements

- [Ray 'doctorray117' Gibson (minecraft-ondemand)](https://github.com/doctorray117/minecraft-ondemand) provided the
  original inspiration and approach for this module.
- [ShaanCoding (ReadME Generator)](https://github.com/ShaanCoding/ReadME-Generator)
