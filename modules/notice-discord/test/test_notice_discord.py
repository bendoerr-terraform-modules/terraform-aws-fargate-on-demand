#!/usr/bin/env python3
"""Unit tests for notice-discord-lambda-function.py"""
import contextlib
import importlib.util
import io
import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

CANARY = "canary-tok-7f3e9a1c2b4d5e6f"
PARAM_PATH = "/secret/path/discord-bot-token"

BASE_ENV = {
    "DISCORD_CHANNEL_ID": "123456789012345678",
    "NOTIFY_APP_NAME": "Test App",
    "NOTIFY_APP_URL": "https://example.com",
}


def _load(env):
    """Import the lambda under env; return (module, everything it printed at import)."""
    boto3 = MagicMock()
    boto3.client.return_value.get_parameter.return_value = {"Parameter": {"Value": CANARY}}
    sys.modules["boto3"] = boto3
    os.environ.update(env)
    spec = importlib.util.spec_from_file_location(
        "notice_discord_lambda_function",
        os.path.join(os.path.dirname(__file__), "../notice-discord-lambda-function.py"),
    )
    module = importlib.util.module_from_spec(spec)
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        spec.loader.exec_module(module)
    return module, out.getvalue()


class TestNoticeDiscordEvents(unittest.TestCase):
    """handler posts one Discord embed per event, titled by event type."""

    def setUp(self):
        self._original_env = os.environ.copy()
        self.module, _ = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": CANARY})

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


class TestStartupLogNeverCarriesTheToken(unittest.TestCase):
    def setUp(self):
        self._original_env = os.environ.copy()

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._original_env)

    def _assert_no_token_material(self, out):
        self.assertNotIn(CANARY, out)
        self.assertNotIn(CANARY[:3] + "*", out)   # the old prefix mask
        self.assertNotIn(CANARY[-6:], out)
        self.assertNotIn(PARAM_PATH, out)

    def test_literal_token_logs_only_its_source(self):
        _, out = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": CANARY})
        self._assert_no_token_material(out)
        self.assertIn("DISCORD_BOT_AUTH_TOKEN_SRC = 'literal-env'", out)

    def test_ssm_token_logs_only_its_source(self):
        module, out = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": "param:" + PARAM_PATH})
        self._assert_no_token_material(out)
        self.assertIn("DISCORD_BOT_AUTH_TOKEN_SRC = 'ssm-parameter'", out)
        # positive control: the SSM value really was resolved, so "absent" above is not vacuous
        self.assertEqual(module.discord_bot_auth_token, CANARY)


if __name__ == "__main__":
    unittest.main()
