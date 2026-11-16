"""Tests for credit_alert.py. Run: /opt/homebrew/bin/python3 tests/test_credit_alert.py"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import credit_alert as ca  # noqa: E402

RESET = 1797239466


def subscription(used, limit=156736, reset=RESET):
    return {"character_count": used, "character_limit": limit, "next_character_count_reset_unix": reset}


class AlertMessageTests(unittest.TestCase):
    def test_no_alert_below_threshold_of_key_limit(self):
        self.assertIsNone(ca.alert_message(subscription(23999), key_limit=30000, alerted_reset=None))

    def test_alert_uses_the_smaller_key_limit(self):
        message = ca.alert_message(subscription(24000), key_limit=30000, alerted_reset=None)
        self.assertTrue(message.startswith(ca.ALERT_PREFIX))
        self.assertIn("30,000", message)
        self.assertIn("6,000", message)
        self.assertIn("API 키", message)

    def test_alert_uses_account_limit_when_smaller(self):
        message = ca.alert_message(subscription(8500, limit=10000), key_limit=30000, alerted_reset=None)
        self.assertIn("10,000", message)
        self.assertNotIn("API 키", message)

    def test_key_without_cap_uses_account_limit(self):
        self.assertIsNone(ca.alert_message(subscription(30000), key_limit=0, alerted_reset=None))
        message = ca.alert_message(subscription(130000), key_limit=0, alerted_reset=None)
        self.assertIn("156,736", message)
        self.assertNotIn("API 키", message)

    def test_no_second_alert_in_same_period(self):
        self.assertIsNone(ca.alert_message(subscription(29000), key_limit=30000, alerted_reset=RESET))

    def test_alert_again_in_a_new_period(self):
        message = ca.alert_message(subscription(29000), key_limit=30000, alerted_reset=RESET - 1)
        self.assertIsNotNone(message)

    def test_missing_fields_give_no_alert(self):
        self.assertIsNone(ca.alert_message({}, key_limit=30000, alerted_reset=None))


class MainTests(unittest.TestCase):
    def setUp(self):
        self.state = Path(tempfile.mkdtemp()) / "credit-alert.state"
        self.sent = []

    def send(self, text):
        self.sent.append(text)
        return True

    def run_main(self, data):
        return ca.main(fetch=lambda: data, send=self.send, state_path=self.state, key_limit=30000)

    def test_sends_once_and_remembers_period(self):
        self.assertEqual(self.run_main(subscription(25000)), 0)
        self.assertEqual(self.run_main(subscription(26000)), 0)
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(self.state.read_text().strip(), str(RESET))

    def test_failed_send_is_retried_next_time(self):
        ca.main(fetch=lambda: subscription(25000), send=lambda text: False,
                state_path=self.state, key_limit=30000)
        self.assertFalse(self.state.exists())
        self.run_main(subscription(25000))
        self.assertEqual(len(self.sent), 1)

    def test_unreachable_api_sends_nothing(self):
        self.assertEqual(self.run_main(None), 1)
        self.assertEqual(self.sent, [])

    def test_corrupt_state_is_treated_as_not_alerted(self):
        self.state.write_text("garbage\n")
        self.run_main(subscription(25000))
        self.assertEqual(len(self.sent), 1)


if __name__ == "__main__":
    unittest.main()
