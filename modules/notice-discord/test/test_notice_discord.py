#!/usr/bin/env python3
"""Unit tests for notice-discord-lambda-function.py"""
import importlib.util
import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch


class TestNoticeDiscordEvents(unittest.TestCase):
    """handler posts one Discord embed per event, titled by event type."""

    def setUp(self):
        sys.modules["boto3"] = MagicMock()
        self._original_env = os.environ.copy()
        os.environ.update({
            "DISCORD_BOT_AUTH_TOKEN": "test-token-value",
            "DISCORD_CHANNEL_ID": "123456789012345678",
            "NOTIFY_APP_NAME": "Test App",
            "NOTIFY_APP_URL": "https://example.com",
        })
        spec = importlib.util.spec_from_file_location(
            "notice_discord_lambda_function",
            os.path.join(os.path.dirname(__file__), "../notice-discord-lambda-function.py"),
        )
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._original_env)

    def _post(self, event_type):
        """Runs the handler for event_type and returns the posted embed."""
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"id": "1"}'
        with patch.object(self.module.urllib.request, "urlopen", return_value=response) as urlopen:
            self.module.handler({"Event": event_type, "Cluster": "c", "Service": "s", "Topic": "t"}, None)
        request = urlopen.call_args.args[0]
        return json.loads(request.data.decode())["embeds"][0]

    def test_launch_event_is_a_known_starting_up_notice(self):
        embed = self._post("launch")

        self.assertEqual(embed["title"], "Starting Up")
        self.assertIn("minute", embed["description"])
        self.assertNotEqual(embed["color"], self.module.discord_colors[self.module.event_colors["unknown"]])

    def test_existing_events_keep_their_titles(self):
        self.assertEqual(self._post("start")["title"], "Started Container")
        self.assertEqual(self._post("stop")["title"], "Stopped Container")

    def test_unknown_events_still_post_as_unknown(self):
        self.assertEqual(self._post("mystery")["title"], "Unknown")


if __name__ == "__main__":
    unittest.main()
