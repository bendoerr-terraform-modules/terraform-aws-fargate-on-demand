#!/usr/bin/env python3
"""Unit tests for aws-launcher-lambda-function.py"""
import importlib.util
import os
import sys
import unittest
from unittest.mock import MagicMock


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
        # Stub boto3 to avoid needing it installed
        sys.modules["boto3"] = MagicMock()

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

        # Stub boto3 to avoid needing it installed
        sys.modules["boto3"] = MagicMock()

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


if __name__ == "__main__":
    unittest.main()
