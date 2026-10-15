"""notice-discord task-state lambda.

Subscribed to the fargate-on-demand task-state SNS topic. Posts one Discord embed
per event to DISCORD_CHANNEL_ID as a bot.

The bot token is supplied either literally or as ``param:<ssm-name>``; in the SSM
form it is fetched once at cold start with decryption. Only the token's SOURCE is
ever logged, and delivery errors are logged without the request (its headers carry
the token), and no raised exception carries the token or the SSM path. Every
delivery Discord did not accept is re-raised, so Lambda's async retries (2) apply
and the Errors metric sees it; a revoked token (401) is loud, not dropped. Once
Discord answers 2xx nothing is raised, so a retry cannot post a duplicate (a 5xx
after Discord did accept can still duplicate; acceptable for a notifier).

Discord embed limits: https://stackoverflow.com/a/67224684/84423
"""
import os
import boto3
import datetime
import urllib.error
import urllib.request
import json

# Load the environment variables
discord_bot_auth_token = os.environ.get("DISCORD_BOT_AUTH_TOKEN", None)
discord_channel_id = os.environ.get("DISCORD_CHANNEL_ID", None)
notify_app_name = os.environ.get("NOTIFY_APP_NAME", "Generic Application")
notify_app_url = os.environ.get("NOTIFY_APP_URL", "https://example.com")

# Validate required variables
if discord_bot_auth_token is None:
    raise ValueError("missing DISCORD_BOT_AUTH_TOKEN environment variable")

# Whitespace from a heredoc or tfvars value would hide the param: prefix or end up in the
# SSM parameter name.
discord_bot_auth_token = discord_bot_auth_token.strip()

if discord_channel_id is None:
    raise ValueError("missing DISCORD_CHANNEL_ID environment variable")

# Log only the token SOURCE, never token-derived material: a masked token still
# leaks characters and length, and the param: form would reveal the SSM path.
# (Same rule as notice-github.)
token_source = "ssm-parameter" if discord_bot_auth_token.startswith("param:") else "literal-env"

# Print the current configuration
print(f"[notice-discord] DISCORD_BOT_AUTH_TOKEN_SRC = '{token_source}'")
print(f"[notice-discord] DISCORD_CHANNEL_ID     = '{discord_channel_id}'")
print(f"[notice-discord] NOTIFY_APP_NAME        = '{notify_app_name}'")
print(f"[notice-discord] NOTIFY_APP_URL         = '{notify_app_url}'")

# If this is a SSM Parameter fetch the actual auth token
if token_source == "ssm-parameter":
    param_name = discord_bot_auth_token.removeprefix("param:").strip()
    # An SSM error message names the parameter, and Lambda logs an uncaught init error's
    # message. Raise only the type, outside the except so nothing chains the original.
    ssm_failure = None
    try:
        response = boto3.client("ssm").get_parameter(Name=param_name, WithDecryption=True)
    except Exception as err:  # noqa: BLE001
        ssm_failure = type(err).__name__
    if ssm_failure is not None:
        raise RuntimeError(
            f"notice-discord could not read the bot token from SSM ({ssm_failure}); the "
            "function role needs ssm:GetParameter, and kms:Decrypt for a SecureString, on it"
        )
    discord_bot_auth_token = response["Parameter"]["Value"]

# A trailing newline (common in a value pasted into SSM) makes http.client reject the
# header with a ValueError whose message is the whole header, token included.
discord_bot_auth_token = discord_bot_auth_token.strip()

# urlopen applies this per socket operation (connect, then each read), not to the whole
# request, so two stalls must still fit inside the function's 10 s timeout for the ERROR
# line to print. DNS resolution is not covered.
DISCORD_TIMEOUT_SECONDS = 3

discord_colors = {
    "green": 5763719,
    "yellow": 16705372,
    "fuchsia": 15418782,
    "blurple": 5793266,
    "red": 15548997,
    "orange": 15105570,
}

event_colors = {
    "launch": "orange",
    "start": "green",
    "active": "blurple",
    "inactive": "yellow",
    "stop": "red",
    "unknown": "fuchsia",
}

event_titles = {
    "launch": "Starting Up",
    "start": "Started Container",
    "active": "Active Use",
    "inactive": "Inactive",
    "stop": "Stopped Container",
    "unknown": "Unknown",
}

event_descriptions = {
    "launch": "Someone is connecting. The application will be ready in a minute or two.",
    "start": "The application has started up and is ready to use!",
    "active": "The application currently has active use!",
    "inactive": "The application has become inactive and will shutdown soon!",
    "stop": "The application has shutdown!",
    "unknown": "An unknown event was received!",
}


def _diagnostic_headers(headers):
    """Only the response headers that explain a rate limit. Never request headers."""
    if headers is None:
        return ""
    return "\n".join(
        f"{k}: {v}" for (k, v) in headers.items()
        if k.lower() == "retry-after" or k.lower().startswith("x-ratelimit-")
    )


def lambda_handler(event, context):
    for r in event["Records"]:
        handler(json.loads(r["Sns"]["Message"]), context)


def handler(event, context):
    """Post one Discord embed describing a fargate-on-demand task-state event."""
    print(f"[notice-discord] event.event   = '{event['Event']}'")
    print(f"[notice-discord] event.Cluster = '{event['Cluster']}'")
    print(f"[notice-discord] event.Service = '{event['Service']}'")
    print(f"[notice-discord] event.Topic   = '{event['Topic']}'")

    event_type = event["Event"]
    if event_type not in event_titles:
        event_type = "unknown"

    message = {
        "embeds": [{
            "type": "rich",
            "title": f"{event_titles[event_type]}",
            "description": f"{event_descriptions[event_type]}",
            "url": f"{notify_app_url}",
            "color": discord_colors[event_colors[event_type]],
            "timestamp": f"{datetime.datetime.now(datetime.timezone.utc).isoformat()}",
            "author": {"name": f"{notify_app_name}", "url": f"{notify_app_url}"},
            "fields": [
                {"name": "Event", "value": f"{event['Event']}", "inline": False},
                {"name": "ECS Cluster", "value": f"{event['Cluster']}", "inline": True},
                {"name": "ECS Service", "value": f"{event['Service']}", "inline": True},
                {"name": "Topic", "value": f"{event['Topic']}", "inline": False},
                {"name": "URL", "value": f"{notify_app_url}", "inline": False},
            ],
        }]
    }

    req = urllib.request.Request(
        f"https://discord.com/api/channels/{discord_channel_id}/messages",
        data=json.dumps(message).encode(),
        headers={
            "Authorization": f"Bot {discord_bot_auth_token}",
            "User-Agent": "Ben's Infrabot/0.0.1",
            "Content-Type": "application/json"
        },
        method="POST",
    )

    # Never log the request headers: they carry the bot token (#629).
    failure = None
    try:
        res = urllib.request.urlopen(req, timeout=DISCORD_TIMEOUT_SECONDS)
    except urllib.error.HTTPError as err:
        try:
            detail = err.read().decode()
        except Exception:  # noqa: BLE001 - best-effort logging only
            detail = "<no body>"
        print(
            f"[notice-discord] ERROR: POST {req.get_full_url()} -> HTTP {err.code} {err.reason}\n"
            f"{_diagnostic_headers(err.headers)}\n{detail}\n"
            f"payload: {req.data.decode()}"
        )
        raise
    except urllib.error.URLError as err:
        print(f"[notice-discord] ERROR: POST {req.get_full_url()} failed: {err.reason}")
        raise
    except Exception as err:  # noqa: BLE001
        # Anything else (e.g. http.client's ValueError for a bad header value) may carry the
        # request in its message, and Lambda logs an uncaught exception's message. Keep only
        # the type, and raise outside the except so the original is not chained as context.
        failure = type(err).__name__
    if failure is not None:
        print(f"[notice-discord] ERROR: POST {req.get_full_url()} failed: {failure}")
        raise RuntimeError(f"notice-discord delivery failed: {failure}")

    # 2xx: Discord has the message. A failure reading the reply must not raise, or Lambda's
    # async retry would post a duplicate.
    with res as r:
        try:
            body = json.loads(r.read().decode())
            print(f"[notice-discord] message.id = {body['id']}")
        except Exception as err:  # noqa: BLE001
            print(f"[notice-discord] WARNING: message accepted, but the reply was unreadable: {type(err).__name__}")
