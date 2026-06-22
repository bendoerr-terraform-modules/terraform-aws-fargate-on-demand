"""notice-github task-state lambda.

Subscribed to the fargate-on-demand task-state SNS topic (same lifecycle the
notice-discord module hangs off of). On each event it upserts the emitting
service's entry in a ``state.json`` committed to a GitHub repo, so a GitHub
Pages status page (issue #140) can render live, near-real-time service status.

Design notes (the contract with the status page):

* The whole state document is rewritten in a SINGLE commit (atomic file
  replace via the GitHub contents API), never appended -- a Pages build can
  never fetch a half-written file.
* ``services`` is a MAP keyed by ECS service name, so an event is a trivial
  upsert of one key -- no scan, no dup risk.
* A ``schema_version`` rides at the top so the page can render old and new
  files when the shape evolves.
* Two near-simultaneous events read the same blob sha; the first PUT wins and
  the slower write gets HTTP 409/422. We re-read and re-apply up to
  MAX_WRITE_ATTEMPTS so a concurrent event can't clobber another service's update.

The GitHub token is supplied either literally or as ``param:<ssm-name>``; in the
SSM form it is fetched at runtime with decryption (mirrors notice-discord).
Source ships a ``placeholder`` -- the real fine-grained PAT lives in SSM,
least-privilege scoped to the one status repo with contents:write.
"""

import base64
import datetime
import json
import os
import random
import time
import urllib.error
import urllib.request

import boto3

GITHUB_API = "https://api.github.com"
SCHEMA_VERSION = 1
KNOWN_EVENTS = ("start", "active", "inactive", "stop")
MAX_WRITE_ATTEMPTS = 5

github_token = os.environ.get("GITHUB_TOKEN", None)
github_repo = os.environ.get("GITHUB_REPO", None)  # "owner/name"
github_branch = os.environ.get("GITHUB_BRANCH", "main")
state_file_path = os.environ.get("STATE_FILE_PATH", "state.json")
notify_app_name = os.environ.get("NOTIFY_APP_NAME", "Generic Application")
notify_app_url = os.environ.get("NOTIFY_APP_URL", "https://example.com")

# Validate required variables
if github_token is None:
    raise ValueError("missing GITHUB_TOKEN environment variable")

if github_repo is None:
    raise ValueError("missing GITHUB_REPO environment variable")

# Log only the token SOURCE, never token-derived material (a masked token still
# leaks entropy, and the param: form would reveal the SSM parameter path).
token_source = "ssm-parameter" if github_token.startswith("param:") else "literal-env"

# Print the current configuration
print(f"[notice-github] GITHUB_REPO     = '{github_repo}'")
print(f"[notice-github] GITHUB_BRANCH   = '{github_branch}'")
print(f"[notice-github] STATE_FILE_PATH = '{state_file_path}'")
print(f"[notice-github] GITHUB_TOKEN_SRC = '{token_source}'")
print(f"[notice-github] NOTIFY_APP_NAME = '{notify_app_name}'")
print(f"[notice-github] NOTIFY_APP_URL  = '{notify_app_url}'")

# If this is a SSM Parameter fetch the actual token
if github_token.startswith("param:"):
    ssm = boto3.client("ssm")
    param_name = github_token.removeprefix("param:")
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    github_token = response["Parameter"]["Value"]


def _now():
    """Current UTC time as a second-precision ISO-8601 'Z' string."""
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _gh_request(method, path, body=None):
    """Call the GitHub REST API and return (status, parsed-json-or-empty-dict)."""
    url = f"{GITHUB_API}/repos/{github_repo}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {github_token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "notice-github-lambda",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as res:
        raw = res.read().decode()
        return res.status, (json.loads(raw) if raw else {})


def _empty_state():
    return {"schema_version": SCHEMA_VERSION, "generated_at": _now(), "services": {}}


def _load_state():
    """Return (state_dict, sha). sha is None when the file does not exist yet."""
    try:
        _, payload = _gh_request(
            "GET", f"contents/{state_file_path}?ref={github_branch}"
        )
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return _empty_state(), None
        raise

    content = base64.b64decode(payload["content"]).decode()
    state = json.loads(content) if content.strip() else {}
    state.setdefault("schema_version", SCHEMA_VERSION)
    state.setdefault("services", {})
    return state, payload["sha"]


def _write_state(state, sha):
    """Commit the full state document back. sha=None creates the file."""
    state["generated_at"] = _now()
    blob = json.dumps(state, indent=2, sort_keys=True) + "\n"
    body = {
        "message": f"chore(status): update {state_file_path}",
        "content": base64.b64encode(blob.encode()).decode(),
        "branch": github_branch,
    }
    if sha is not None:
        body["sha"] = sha
    _gh_request("PUT", f"contents/{state_file_path}", body)


def _normalize(event_type):
    """Map a raw event name to the status enum the page renders against."""
    return event_type if event_type in KNOWN_EVENTS else "unknown"


def _log_http_error(err):
    try:
        detail = err.read().decode()
    except Exception:  # noqa: BLE001 - best-effort logging only
        detail = "<no body>"
    print(f"[notice-github] ERROR: HTTP {err.code} {err.reason}\n{detail}")


def handler(event, context):
    """Upsert one service's status, retrying on a concurrent-write conflict."""
    service = event["Service"]
    status = _normalize(event["Event"])
    print(
        f"[notice-github] event.Event='{event['Event']}' "
        f"event.Cluster='{event['Cluster']}' event.Service='{service}'"
    )

    for attempt in range(1, MAX_WRITE_ATTEMPTS + 1):
        state, sha = _load_state()
        state.setdefault("services", {})[service] = {
            "cluster": event["Cluster"],
            "app_name": notify_app_name,
            "url": notify_app_url,
            "status": status,
            "updated_at": _now(),
        }
        try:
            _write_state(state, sha)
            print(
                f"[notice-github] wrote state for service '{service}' "
                f"(status='{status}', attempt {attempt})"
            )
            return
        except urllib.error.HTTPError as err:
            # 409 (sha conflict) / 422 (stale sha): another event committed
            # between our read and write -- re-read and re-apply.
            if err.code in (409, 422) and attempt < MAX_WRITE_ATTEMPTS:
                # Exponential backoff with jitter so concurrent writers don't
                # keep re-colliding on every immediate retry.
                backoff = min(2.0, random.uniform(0, 0.1 * (2**attempt)))
                print(
                    f"[notice-github] write conflict (HTTP {err.code}), "
                    f"retrying in {backoff:.2f}s (attempt {attempt})"
                )
                time.sleep(backoff)
                continue
            _log_http_error(err)
            raise


def lambda_handler(event, context):
    for r in event["Records"]:
        handler(json.loads(r["Sns"]["Message"]), context)
