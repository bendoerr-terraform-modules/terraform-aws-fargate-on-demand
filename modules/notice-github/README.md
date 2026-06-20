# notice-github

Task-state notifier that records on-demand fargate service status in a file on
GitHub, so a zero-cost [GitHub Pages status page](./status-page/) can render it.

It is the GitHub sibling of `notice-discord`: same task-state lifecycle
(SNS → Lambda), but instead of posting a Discord message it commits/updates a
`state.json` in a GitHub repository. Hosting status on GitHub Pages keeps the
status page itself free — nothing runs on AWS to serve it.

- **Issue #141** — this module (the producer).
- **Issue #140** — the [status page](./status-page/) (the consumer).

## How it works

The Lambda subscribes to the same SNS task-state topic the other `notice-*`
modules use. Each event carries `{ Event, Cluster, Service, Topic }`. On every
event the Lambda:

1. Reads the current `state.json` from the target repo (GitHub contents API).
2. Upserts the **one** emitting service's entry, keyed by ECS service name.
3. Commits the whole document back in a single commit (atomic file replace).

Two near-simultaneous events read the same blob SHA; the first commit wins and
the loser gets HTTP 409/422, so the Lambda re-reads and re-applies (up to five
attempts). A Pages build therefore never fetches a half-written file.

## The `state.json` contract

This is the interface between the producer (this module) and the consumer (the
status page). Treat it as stable; bump `schema_version` before changing shape.

```json
{
  "schema_version": 1,
  "generated_at": "2026-06-20T21:40:00Z",
  "services": {
    "brd-prod-ue1-gimlet": {
      "cluster": "brd-prod-ue1-cluster",
      "app_name": "Gimlet",
      "url": "https://gimlet.example.com",
      "status": "active",
      "updated_at": "2026-06-20T21:39:12Z"
    }
  }
}
```

- `services` is a **map keyed by ECS service name** — an event is a single-key
  upsert, no scan and no chance of duplicate entries.
- `status` is the raw event enum: `start`, `active`, `inactive`, `stop`, or
  `unknown`. The page maps these to display labels.
- `updated_at` (per service) and `generated_at` (top level) are second-precision
  ISO-8601 UTC, used for sorting and staleness detection.

## Token

The Lambda needs a GitHub token with `contents:write` on the single status repo
only — a fine-grained PAT, least-privilege. Source ships a `placeholder`; the
real token belongs in SSM, referenced as `github_token = "param:<name>"`. Pass
`github_token_ssm_param_arn` so the role's `ssm:GetParameter` grant is scoped to
exactly that parameter. A literal token also works (used by the example/test).

## Usage

```hcl
module "notice_github" {
  source = "git@github.com:bendoerr-terraform-modules/terraform-aws-fargate-on-demand//modules/notice-github"

  context         = module.context.shared
  event_topic_arn = aws_sns_topic.task_state.arn

  github_token               = "param:/brd/prod/notice-github/token"
  github_token_ssm_param_arn = aws_ssm_parameter.notice_github_token.arn
  github_repo                = "bendoerr/status"

  notify_app_name = "Gimlet"
  notify_app_url  = "https://gimlet.example.com"
}
```

## Inputs

<!-- markdownlint-disable MD013 -->

| Name                         | Type     | Default        | Required | Description                                                 |
| ---------------------------- | -------- | -------------- | :------: | ----------------------------------------------------------- |
| `context`                    | `object` | n/a            |   yes    | Shared context from `terraform-null-context`.               |
| `event_topic_arn`            | `string` | n/a            |   yes    | SNS topic publishing task-state events.                     |
| `github_repo`                | `string` | n/a            |   yes    | Target status repo, `owner/name`.                           |
| `github_token`               | `string` | n/a            |   yes    | Literal PAT or `param:<ssm-name>` reference (sensitive).    |
| `notify_app_name`            | `string` | n/a            |   yes    | Application name recorded on each service entry.            |
| `notify_app_url`             | `string` | n/a            |   yes    | Public application URL (`http(s)://…`).                     |
| `github_branch`              | `string` | `"main"`       |    no    | Branch to commit the status file to.                        |
| `state_file_path`            | `string` | `"state.json"` |    no    | Path of the status file in the repo.                        |
| `github_token_ssm_param_arn` | `string` | `null`         |    no    | SSM parameter ARN to scope `ssm:GetParameter` to.           |
| `github_token_kms_key_arn`   | `string` | `null`         |    no    | CMK ARN encrypting the token parameter, if not the AWS key. |
| `lambda_env_kms_arn`         | `string` | `null`         |    no    | KMS key for Lambda env vars (null = AWS-managed).           |
| `lambda_logs_kms_arn`        | `string` | `null`         |    no    | KMS key for the Lambda log group (null = AWS-managed).      |

## Outputs

| Name                   | Description                       |
| ---------------------- | --------------------------------- |
| `notice_role_name`     | Name of the Lambda IAM role.      |
| `notice_role_arn`      | ARN of the Lambda IAM role.       |
| `notice_function_name` | Name of the notice-github Lambda. |
| `notice_function_arn`  | ARN of the notice-github Lambda.  |

<!-- markdownlint-enable MD013 -->
