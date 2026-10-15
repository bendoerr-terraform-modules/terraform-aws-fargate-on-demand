#!/usr/bin/env python3
"""Unit tests for notice-discord-lambda-function.py"""
import contextlib
import email.message
import importlib.util
import io
import json
import os
import re
import sys
import unittest
import urllib.error
from unittest.mock import MagicMock, patch

CANARY = "canary-tok-7f3e9a1c2b4d5e6f"
PARAM_PATH = "/secret/path/discord-bot-token"

BASE_ENV = {
    "DISCORD_CHANNEL_ID": "123456789012345678",
    "NOTIFY_APP_NAME": "Test App",
    "NOTIFY_APP_URL": "https://example.com",
}


def _load(env, ssm_value=CANARY, ssm_error=None):
    """Import the lambda under env; return (module, everything it printed at import)."""
    boto3 = MagicMock()
    boto3.client.return_value.get_parameter.return_value = {"Parameter": {"Value": ssm_value}}
    if ssm_error is not None:
        boto3.client.return_value.get_parameter.side_effect = ssm_error
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


def _http_error(code, reason):
    hdrs = email.message.Message()
    hdrs["Retry-After"] = "3"
    hdrs["X-RateLimit-Reset-After"] = "2.5"
    hdrs["Set-Cookie"] = "__dcfduid=should-not-be-logged"
    return urllib.error.HTTPError(
        "https://discord.com/api/channels/123456789012345678/messages",
        code, reason, hdrs, io.BytesIO(b'{"message": "nope", "code": 0}'),
    )


class TestDeliveryFailureNeverLogsTheToken(unittest.TestCase):
    EVENT = {"Event": "start", "Cluster": "c", "Service": "s", "Topic": "t"}

    def setUp(self):
        self._original_env = os.environ.copy()
        self.module, _ = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": CANARY})

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._original_env)

    def _run(self, side_effect):
        """Run handler with urlopen raising side_effect; return (stdout, raised exception or None, request)."""
        out, raised = io.StringIO(), None
        with patch.object(self.module.urllib.request, "urlopen", side_effect=side_effect) as urlopen, \
                contextlib.redirect_stdout(out):
            try:
                self.module.handler(self.EVENT, None)
            except Exception as exc:  # noqa: BLE001
                raised = exc
        return out.getvalue(), raised, urlopen.call_args.args[0]

    def test_request_really_carried_the_token(self):
        # positive control: every "absent" assertion below is about a request that DID hold the canary
        _, _, request = self._run(_http_error(401, "Unauthorized"))
        self.assertEqual(request.get_header("Authorization"), f"Bot {CANARY}")

    def test_401_is_logged_without_the_token_and_raised(self):
        # a revoked token never heals; it must be loud, not logged-and-dropped
        out, raised, _ = self._run(_http_error(401, "Unauthorized"))
        self.assertNotIn(CANARY, out)
        self.assertNotIn("Authorization", out)
        self.assertIn("HTTP 401 Unauthorized", out)
        self.assertIn('"message": "nope"', out)
        self.assertIsInstance(raised, urllib.error.HTTPError)

    def test_429_is_logged_with_rate_limit_headers_only_and_raised(self):
        out, raised, _ = self._run(_http_error(429, "Too Many Requests"))
        self.assertNotIn(CANARY, out)
        self.assertIn("HTTP 429 Too Many Requests", out)
        self.assertIn("Retry-After: 3", out)
        self.assertIn("X-RateLimit-Reset-After: 2.5", out)
        self.assertNotIn("should-not-be-logged", out)
        self.assertIsInstance(raised, urllib.error.HTTPError)

    def test_5xx_is_raised(self):
        out, raised, _ = self._run(_http_error(502, "Bad Gateway"))
        self.assertIsInstance(raised, urllib.error.HTTPError)  # first, so the raise itself is red-witnessed
        self.assertNotIn(CANARY, out)

    def test_network_error_is_logged_without_the_token_and_raised(self):
        out, raised, _ = self._run(urllib.error.URLError("timed out"))
        self.assertNotIn(CANARY, out)
        self.assertIn("timed out", out)
        self.assertIsInstance(raised, urllib.error.URLError)

    def test_unexpected_error_never_carries_the_token(self):
        # http.client rejects a header value containing a newline with a ValueError whose message
        # is the whole header. It is neither HTTPError nor URLError, and Lambda logs an uncaught
        # exception's message, so it must be replaced, not re-raised as is.
        out, raised, _ = self._run(ValueError(f"Invalid header value b'Bot {CANARY}\\n'"))
        self.assertIsNotNone(raised)
        self.assertNotIn(CANARY, str(raised))
        # not merely suppressed: any handler that walks __context__ must find nothing
        self.assertIsNone(raised.__cause__)
        self.assertIsNone(raised.__context__)
        self.assertNotIn(CANARY, out)
        self.assertIn("ValueError", out)

    def test_request_has_a_timeout_below_the_function_timeout(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"id": "1"}'
        with patch.object(self.module.urllib.request, "urlopen", return_value=response) as urlopen, \
                contextlib.redirect_stdout(io.StringIO()):
            self.module.handler(self.EVENT, None)
        with open(os.path.join(os.path.dirname(__file__), "../main.tf")) as f:
            function_timeout = int(re.search(r"^\s*timeout\s*=\s*(\d+)", f.read(), re.M).group(1))
        # urlopen's timeout is per socket operation (connect, then each read), so leave room for two
        self.assertLess(2 * urlopen.call_args.kwargs["timeout"], function_timeout)

    def test_accepted_message_with_unreadable_response_is_not_retried(self):
        # Discord answered 2xx, so the message is posted; a retry would post a duplicate
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b"not json"
        out = io.StringIO()
        with patch.object(self.module.urllib.request, "urlopen", return_value=response), \
                contextlib.redirect_stdout(out):
            self.module.handler(self.EVENT, None)
        self.assertIn("accepted", out.getvalue())

    def test_http_error_logs_the_payload_for_diagnosis(self):
        out, _, _ = self._run(_http_error(400, "Bad Request"))
        self.assertIn('"embeds"', out)


class TestTokenIsNormalised(unittest.TestCase):
    def setUp(self):
        self._original_env = os.environ.copy()

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self._original_env)

    def test_literal_token_whitespace_is_stripped(self):
        module, _ = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": CANARY + "\n"})
        self.assertEqual(module.discord_bot_auth_token, CANARY)

    def test_param_name_whitespace_is_stripped(self):
        module, _ = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": " param:" + PARAM_PATH + "\n"})
        self.assertEqual(module.token_source, "ssm-parameter")
        self.assertEqual(sys.modules["boto3"].client.return_value.get_parameter.call_args.kwargs["Name"], PARAM_PATH)

    def test_ssm_failure_never_logs_the_parameter_path(self):
        out = io.StringIO()
        with self.assertRaises(Exception) as ctx, contextlib.redirect_stdout(out):
            _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": "param:" + PARAM_PATH},
                  ssm_error=RuntimeError(f"AccessDenied on arn:aws:ssm:us-east-1:1:parameter{PARAM_PATH}"))
        self.assertNotIn(PARAM_PATH, str(ctx.exception))
        self.assertIsNone(ctx.exception.__context__)
        self.assertNotIn(PARAM_PATH, out.getvalue())

    def test_ssm_token_whitespace_is_stripped(self):
        # values pasted into SSM commonly carry a trailing newline
        module, _ = _load({**BASE_ENV, "DISCORD_BOT_AUTH_TOKEN": "param:" + PARAM_PATH}, ssm_value=CANARY + "\r\n")
        self.assertEqual(module.discord_bot_auth_token, CANARY)

if __name__ == "__main__":
    unittest.main()
