"""Quiet hours follow the setting picked in the avatar's menu. Run: python3 -m unittest discover -s tests"""
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import quiet_hours  # noqa: E402


def at(hour):
    return datetime(2026, 11, 16, hour, 30)


class ParseTests(unittest.TestCase):
    def test_hours_are_read(self):
        self.assertEqual(quiet_hours.parse("22 7\n"), (True, 22, 7))

    def test_off_keeps_the_hours(self):
        self.assertEqual(quiet_hours.parse("off 22 7\n"), (False, 22, 7))

    def test_unreadable_text_means_the_default(self):
        for text in ("", "garbage", "25 7", "22", "22 7 9", "-1 7", "off", "a b"):
            self.assertEqual(quiet_hours.parse(text), quiet_hours.DEFAULT_SETTING, text)

    def test_a_missing_file_means_the_default(self):
        missing = Path(tempfile.mkdtemp()) / "quiet-hours"
        self.assertEqual(quiet_hours.load(missing), (True, 23, 12))


class InQuietHoursTests(unittest.TestCase):
    def test_hours_over_midnight(self):
        setting = (True, 23, 12)
        for hour in (23, 0, 3, 11):
            self.assertTrue(quiet_hours.in_quiet_hours(at(hour), setting), hour)
        for hour in (12, 18, 22):
            self.assertFalse(quiet_hours.in_quiet_hours(at(hour), setting), hour)

    def test_hours_within_one_day(self):
        setting = (True, 1, 8)
        for hour in (1, 7):
            self.assertTrue(quiet_hours.in_quiet_hours(at(hour), setting), hour)
        for hour in (0, 8, 23):
            self.assertFalse(quiet_hours.in_quiet_hours(at(hour), setting), hour)

    def test_turned_off_is_never_quiet(self):
        for hour in range(24):
            self.assertFalse(quiet_hours.in_quiet_hours(at(hour), (False, 23, 12)), hour)

    def test_same_start_and_end_is_never_quiet(self):
        for hour in range(24):
            self.assertFalse(quiet_hours.in_quiet_hours(at(hour), (True, 9, 9)), hour)

    def test_the_setting_file_is_used(self):
        path = Path(tempfile.mkdtemp()) / "quiet-hours"
        path.write_text("off 23 12\n", encoding="utf-8")
        self.assertFalse(quiet_hours.in_quiet_hours(at(2), quiet_hours.load(path)))


if __name__ == "__main__":
    unittest.main()
