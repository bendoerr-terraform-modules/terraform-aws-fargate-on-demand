#!/usr/bin/env python3
"""Unit tests for aws-launcher-lambda-function.py"""
import importlib.util
import json
import os
import sys
import unittest
from unittest.mock import MagicMock


def stub_aws_sdk():
    """Stubs boto3 and botocore.config (not installed in CI) before importing the launcher."""
    sys.modules["boto3"] = MagicMock()
    botocore_config = MagicMock()
    sys.modules["botocore"] = MagicMock(config=botocore_config)
    sys.modules["botocore.config"] = botocore_config


class TestLauncherImport(unittest.TestCase):
    """Test that the launcher module validates environment variables at import time."""

    def setUp(self):
        """Clear the launcher module from sys.modules before each test."""
        # Remove the module if it was previously imported
        if "aws_launcher_lambda_function" in sys.modules:
            del sys.modules["aws_launcher_lambda_function"]

    def _assert_missing_var_raises(self, test_env, missing_var_message):
        """Import the launcher module with test_env and assert it raises
        ValueError whose message contains missing_var_message."""
        # Stub the AWS SDK (not installed in CI)
        stub_aws_sdk()

        # Clear the launcher module from sys.modules
        if "aws_launcher_lambda_function" in sys.modules:
            del sys.modules["aws_launcher_lambda_function"]

        # Save original environment
        original_env = os.environ.copy()
        try:
            # Set test environment
            os.environ.clear()
            os.environ.update(test_env)

            # Load the launcher module - should raise ValueError
            spec = importlib.util.spec_from_file_location(
                "aws_launcher_lambda_function",
                os.path.join(
                    os.path.dirname(__file__),
                    "../aws-launcher-lambda-function.py",
                ),
            )
            module = importlib.util.module_from_spec(spec)

            with self.assertRaises(ValueError) as context:
                spec.loader.exec_module(module)

            self.assertIn(missing_var_message, str(context.exception))

        finally:
            # Restore original environment
            os.environ.clear()
            os.environ.update(original_env)
            # Clean up the module
            if "aws_launcher_lambda_function" in sys.modules:
                del sys.modules["aws_launcher_lambda_function"]

    def test_missing_ecs_service_raises_valueerror(self):
        """Test that importing without ECS_SERVICE raises ValueError."""
        self._assert_missing_var_raises(
            {
                "ECS_REGION": "us-east-1",
                "ECS_CLUSTER": "test-cluster",
                # ECS_SERVICE is intentionally missing
            },
            "missing ECS_SERVICE",
        )

    def test_missing_ecs_region_raises_valueerror(self):
        """Test that importing without ECS_REGION raises ValueError."""
        self._assert_missing_var_raises(
            {
                # ECS_REGION is intentionally missing
                "ECS_CLUSTER": "test-cluster",
                "ECS_SERVICE": "test-service",
            },
            "missing ECS_REGION",
        )

    def test_missing_ecs_cluster_raises_valueerror(self):
        """Test that importing without ECS_CLUSTER raises ValueError."""
        self._assert_missing_var_raises(
            {
                "ECS_REGION": "us-east-1",
                # ECS_CLUSTER is intentionally missing
                "ECS_SERVICE": "test-service",
            },
            "missing ECS_CLUSTER",
        )

    def test_all_required_vars_imports_cleanly(self):
        """Test that importing with all required vars succeeds."""
        # Set up environment with all required vars
        test_env = {
            "ECS_REGION": "us-east-1",
            "ECS_CLUSTER": "test-cluster",
            "ECS_SERVICE": "test-service",
        }

        # Stub the AWS SDK (not installed in CI)
        stub_aws_sdk()

        # Clear the launcher module from sys.modules
        if "aws_launcher_lambda_function" in sys.modules:
            del sys.modules["aws_launcher_lambda_function"]

        # Save original environment
        original_env = os.environ.copy()
        try:
            # Set test environment
            os.environ.clear()
            os.environ.update(test_env)

            # Load the launcher module - should succeed
            spec = importlib.util.spec_from_file_location(
                "aws_launcher_lambda_function",
                os.path.join(
                    os.path.dirname(__file__),
                    "../aws-launcher-lambda-function.py",
                ),
            )
            module = importlib.util.module_from_spec(spec)

            # This should not raise an exception
            spec.loader.exec_module(module)

            # lambda_handler is a real callable, not just a name that
            # happens to exist on the module.
            self.assertTrue(callable(module.lambda_handler))

            # The module-level config it reads at import time (and that
            # lambda_handler closes over) came from the env vars we set,
            # not some hard-coded or stale value.
            self.assertEqual(module.ecs_region, "us-east-1")
            self.assertEqual(module.ecs_cluster, "test-cluster")
            self.assertEqual(module.ecs_service, "test-service")
            self.assertEqual(module.desired_count, 1)  # default, DESIRED_COUNT unset

        finally:
            # Restore original environment
            os.environ.clear()
            os.environ.update(original_env)
            # Clean up the module
            if "aws_launcher_lambda_function" in sys.modules:
                del sys.modules["aws_launcher_lambda_function"]



class TestLauncherHandler(unittest.TestCase):
    """lambda_handler scales the service from zero and announces the launch."""

    def _load(self, extra_env, desired_count):
        """Import the launcher with a fake boto3 whose ECS service reports
        desired_count; returns (module, ecs_client, sns_client)."""
        ecs = MagicMock()
        ecs.describe_services.return_value = {"services": [{"desiredCount": desired_count}]}
        sns = MagicMock()
        boto3 = MagicMock()
        self.client_kwargs = {}

        def client(name, **kwargs):
            self.client_kwargs[name] = kwargs
            return {"ecs": ecs, "sns": sns}[name]

        boto3.client.side_effect = client
        sys.modules["boto3"] = boto3
        # botocore.config.Config records its kwargs so tests can check the SNS bounds.
        botocore_config = MagicMock()
        botocore_config.Config.side_effect = lambda **kwargs: ("Config", kwargs)
        sys.modules["botocore"] = MagicMock(config=botocore_config)
        sys.modules["botocore.config"] = botocore_config
        if "aws_launcher_lambda_function" in sys.modules:
            del sys.modules["aws_launcher_lambda_function"]

        env = {"ECS_REGION": "us-east-1", "ECS_CLUSTER": "test-cluster", "ECS_SERVICE": "test-service", **extra_env}
        self._original_env = os.environ.copy()
        self.addCleanup(self._restore_env)
        os.environ.clear()
        os.environ.update(env)

        spec = importlib.util.spec_from_file_location(
            "aws_launcher_lambda_function",
            os.path.join(os.path.dirname(__file__), "../aws-launcher-lambda-function.py"),
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module, ecs, sns

    def _restore_env(self):
        os.environ.clear()
        os.environ.update(self._original_env)

    def test_launch_from_zero_publishes_launch_event(self):
        topic = "arn:aws:sns:us-east-1:111111111111:events"
        module, ecs, sns = self._load({"EVENTS_TOPIC_ARN": topic}, desired_count=0)

        module.lambda_handler({}, None)

        ecs.update_service.assert_called_once_with(cluster="test-cluster", service="test-service", desiredCount=1)
        sns.publish.assert_called_once()
        kwargs = sns.publish.call_args.kwargs
        self.assertEqual(kwargs["TopicArn"], topic)
        self.assertEqual(
            json.loads(kwargs["Message"]),
            {"Event": "launch", "Cluster": "test-cluster", "Service": "test-service", "Topic": topic},
        )

    def test_sns_call_is_bounded_well_inside_the_lambda_timeout(self):
        module, _, _ = self._load({"EVENTS_TOPIC_ARN": "arn:aws:sns:us-east-1:111111111111:events"}, desired_count=0)

        module.lambda_handler({}, None)

        kind, config = self.client_kwargs["sns"]["config"]
        self.assertEqual(kind, "Config")
        self.assertLessEqual(config["connect_timeout"], 1)
        self.assertLessEqual(config["read_timeout"], 1)
        self.assertEqual(config["retries"], {"max_attempts": 1})

    def test_already_running_neither_scales_nor_publishes(self):
        module, ecs, sns = self._load({"EVENTS_TOPIC_ARN": "arn:aws:sns:us-east-1:111111111111:events"}, desired_count=1)

        module.lambda_handler({}, None)

        ecs.update_service.assert_not_called()
        sns.publish.assert_not_called()

    def test_no_topic_scales_without_publishing(self):
        module, ecs, sns = self._load({}, desired_count=0)

        module.lambda_handler({}, None)

        ecs.update_service.assert_called_once()
        sns.publish.assert_not_called()

    def test_publish_failure_does_not_undo_the_launch(self):
        module, ecs, sns = self._load({"EVENTS_TOPIC_ARN": "arn:aws:sns:us-east-1:111111111111:events"}, desired_count=0)
        sns.publish.side_effect = RuntimeError("sns down")

        module.lambda_handler({}, None)  # must not raise

        ecs.update_service.assert_called_once()


if __name__ == "__main__":
    unittest.main()
