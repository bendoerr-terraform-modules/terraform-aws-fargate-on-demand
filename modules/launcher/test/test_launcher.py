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

    def test_missing_ecs_service_raises_valueerror(self):
        """Test that importing without ECS_SERVICE raises ValueError."""
        # Set up environment with all required vars except ECS_SERVICE
        test_env = {
            "ECS_REGION": "us-east-1",
            "ECS_CLUSTER": "test-cluster",
            # ECS_SERVICE is intentionally missing
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

            self.assertIn("missing ECS_SERVICE", str(context.exception))

        finally:
            # Restore original environment
            os.environ.clear()
            os.environ.update(original_env)
            # Clean up the module
            if "aws_launcher_lambda_function" in sys.modules:
                del sys.modules["aws_launcher_lambda_function"]

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

            # Verify lambda_handler is defined
            self.assertTrue(hasattr(module, "lambda_handler"))

        finally:
            # Restore original environment
            os.environ.clear()
            os.environ.update(original_env)
            # Clean up the module
            if "aws_launcher_lambda_function" in sys.modules:
                del sys.modules["aws_launcher_lambda_function"]


if __name__ == "__main__":
    unittest.main()
