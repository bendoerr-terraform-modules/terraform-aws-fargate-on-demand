"""AWS ECS Service Launcher

This script will update the desired count of an ECS Service when invoked. This
can be very useful for starting a service on demand given some signal that
triggers an AWS Lambda Function.

Configuration via Environment Variables

 ECS_REGION     (required) The AWS Region which the ECS Cluster is running.
 ECS_CLUSTER    (required) The name of the ECS Cluster
 ECS_SERVICE    (required) The name of the ECS Service
 DESIRED_COUNT  (default: 1) The count of tasks to update to

"""
import os
import boto3

# Load the environment variables
ecs_region = os.environ.get('ECS_REGION', None)
ecs_cluster = os.environ.get('ECS_CLUSTER', None)
ecs_service = os.environ.get('ECS_SERVICE', None)
desired_count = os.environ.get('DESIRED_COUNT', 1)

# Validate required variables
if ecs_region is None:
    raise ValueError("missing ECS_REGION environment variable")

if ecs_cluster is None:
    raise ValueError("missing ECS_CLUSTER environment variable")

if ecs_cluster is None:
    raise ValueError("missing ECS_SERVICE environment variable")

# Print the current configuration
print(f"[launcher] ECS_REGION   = '{ecs_region}'")
print(f"[launcher] ECS_CLUSTER  = '{ecs_cluster}'")
print(f"[launcher] ECS_SERVICE  = '{ecs_service}'")
print(f"[launcher] DESIRED_COUNT= '{desired_count}'")


def lambda_handler(event, context):
    """Updates the desired task count for an ECS Service."""

    ecs = boto3.client('ecs', region_name=ecs_region)
    response = ecs.describe_services(
        cluster=ecs_cluster,
        services=[ecs_service],
    )

    desired = response["services"][0]["desiredCount"]

    if desired == 0:
        ecs.update_service(
            cluster=ecs_cluster,
            service=ecs_service,
            desiredCount=desired_count,
        )
        print(f"[launcher] updated service '{ecs_service}' desired task count: '{desired_count}'")
    else:
        print(f"[launcher] service '{ecs_service}' desired task count already greater than zero")
