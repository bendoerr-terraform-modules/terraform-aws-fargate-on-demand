"""TODO
See limitations about message here
https://stackoverflow.com/a/67224684/84423
"""
import os
import boto3
import datetime
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

if discord_channel_id is None:
    raise ValueError("missing DISCORD_CHANNEL_ID environment variable")

# Create a printable representation of the auth token for logs
printable_auth_token = ""
if discord_bot_auth_token.startswith("param:"):
    printable_auth_token = discord_bot_auth_token
else:
    printable_auth_token = (
            discord_bot_auth_token[:3]
            + ("*" * (len(discord_bot_auth_token) - 5))
            + discord_bot_auth_token[-2:]
    )

# Print the current configuration
print(f"[notice-discord] DISCORD_BOT_AUTH_TOKEN = '{printable_auth_token}'")
print(f"[notice-discord] DISCORD_CHANNEL_ID     = '{discord_channel_id}'")
print(f"[notice-discord] NOTIFY_APP_NAME        = '{notify_app_name}'")
print(f"[notice-discord] NOTIFY_APP_URL         = '{notify_app_url}'")

# If this is a SSM Parameter fetch the actual auth token
if discord_bot_auth_token.startswith("param:"):
    ssm = boto3.client("ssm")
    param_name = discord_bot_auth_token.removeprefix("param:")
    response = ssm.get_parameter(Name=param_name, WithDecryption=True)
    discord_bot_auth_token = response["Parameter"]["Value"]

discord_colors = {
    "green": 5763719,
    "yellow": 16705372,
    "fuchsia": 15418782,
    "blurple": 5793266,
    "red": 15548997,
}

event_colors = {
    "start": "green",
    "active": "blurple",
    "inactive": "yellow",
    "stop": "red",
    "unknown": "fuchsia",
}

event_titles = {
    "start": "Started Container",
    "active": "Active Use",
    "inactive": "Inactive",
    "stop": "Stopped Container",
    "unknown": "Unknown",
}

event_descriptions = {
    "start": "The application has started up and is ready to use!",
    "active": "The application currently has active use!",
    "inactive": "The application has become inactive and will shutdown soon!",
    "stop": "The application has shutdown!",
    "unknown": "An unknown event was received!",
}


def lambda_handler(event, context):
    for r in event["Records"]:
        handler(json.loads(r["Sns"]["Message"]), context)


def handler(event, context):
    print(f"[notice-discord] event.event   = '{event['Event']}'")
    print(f"[notice-discord] event.Cluster = '{event['Cluster']}'")
    print(f"[notice-discord] event.Service = '{event['Service']}'")
    print(f"[notice-discord] event.Topic   = '{event['Topic']}'")

    """Updates the desired task count for an ECS Service."""
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

    # request.add_header("Authorization", f"Bot {discord_bot_auth_token}")

    try:
        with urllib.request.urlopen(req) as res:
            body = json.loads(res.read().decode())
            print(f"[notice-discord] message.id = {body['id']}")
    except urllib.error.HTTPError as err:
        req_hdrs = "\n".join([f"{k}: {v}" for (k, v) in req.header_items()])
        req_str = f"{req.get_method()} {req.get_full_url()} HTTP/1.1\n{req_hdrs}\n\n{req.data.decode()}"
        res_hdrs = "\n".join([f"{k}: {v}" for (k, v) in err.headers.items()])
        res_str = f"HTTP/1.1 {err.code} {err.reason}\n{res_hdrs}\n\n{err.read().decode()}"
        print(f"[notice-discord] ERROR: Failed to send message.\n{req_str}\n\n{res_str}")

# if __name__ == "__main__":
#     # {"Event": "Error", "Cluster": "brd-testing-ue1-cluster", "Service": "brd-testing-ue1-foobar", "Topic": "arn:::foobar://cake"}
#     lambda_handler({
#         "Event": "Error",
#         "Cluster": "brd-testing-ue1-cluster",
#         "Service": "brd-testing-ue1-foobar",
#         "Topic": "arn:::foobar://cake"
#     }, {})
