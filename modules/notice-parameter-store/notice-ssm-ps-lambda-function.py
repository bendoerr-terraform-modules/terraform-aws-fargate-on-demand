"""
TODO
"""
import os
import boto3
import json

# Load the environment variables
param_store_key = os.environ.get("PARAM_STORE_KEY", None)

# Validate required variables
if param_store_key is None:
    raise ValueError("missing PARAM_STORE_KEY environment variable")

# Print the current configuration
print(f"[notice-ssm-ps] PARAM_STORE_KEY = '{param_store_key}'")


def lambda_handler(event, context):
    for r in event["Records"]:
        handler(json.loads(r["Sns"]["Message"]), context)


def handler(event, context):
    print(f"[notice-ssm-ps] event.Event   = '{event['Event']}'")
    print(f"[notice-ssm-ps] event.Cluster = '{event['Cluster']}'")
    print(f"[notice-ssm-ps] event.Service = '{event['Service']}'")
    print(f"[notice-ssm-ps] event.Topic   = '{event['Topic']}'")

    boto3.client("ssm").put_parameter(Name=param_store_key,
                                      Value=json.dumps(event),
                                      Overwrite=True)
