"""Tests for assistant_config.py and tools/render_template.py. Run: python3 tests/test_setup_tools.py"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(REPO / "tools"))

import assistant_config  # noqa: E402
import render_template  # noqa: E402


class ConfigTests(unittest.TestCase):
    def test_parse_reads_quoted_values_and_skips_the_rest(self):
        text = '# comment\nUSER_NAME_EN="Alex"  # trailing\nBROKEN=no quotes\n\nGREETING="불렀어?"\n'
        self.assertEqual(assistant_config.parse(text), {"USER_NAME_EN": "Alex", "GREETING": "불렀어?"})

    def test_parse_expands_home(self):
        values = assistant_config.parse('T3_BIN="$HOME/.local/bin/t3"')
        self.assertEqual(values["T3_BIN"], os.path.expanduser("~/.local/bin/t3"))

    def test_conf_overrides_example(self):
        folder = Path(tempfile.mkdtemp())
        (folder / "example").write_text('A="1"\nB="2"\n')
        (folder / "conf").write_text('B="3"\n')
        self.assertEqual(assistant_config.load(folder / "conf", folder / "example"), {"A": "1", "B": "3"})

    def test_missing_conf_falls_back_to_example(self):
        folder = Path(tempfile.mkdtemp())
        (folder / "example").write_text('A="1"\n')
        self.assertEqual(assistant_config.load(folder / "none", folder / "example"), {"A": "1"})

    def test_example_file_parses_completely(self):
        values = assistant_config.read(REPO / "assistant.conf.example")
        for key in ("USER_NAME_EN", "USER_CALL_KO", "USER_SHORT_CALL_KO", "ELEVENLABS_VOICE_ID",
                    "ELEVENLABS_KEY_MONTHLY_LIMIT", "T3_BIN", "ASSISTANT_INSTANCE", "ASSISTANT_MODEL",
                    "ASSISTANT_NAME_KO", "ASSISTANT_NAME_EN",
                    "WORK_INSTANCE", "WORK_MODEL", "GREETING"):
            self.assertIn(key, values)


class RenderTests(unittest.TestCase):
    def test_render_fills_placeholders(self):
        self.assertEqual(render_template.render("Hi {{NAME}} at {{DIR}}", {"NAME": "A", "DIR": "/x"}), "Hi A at /x")

    def test_persona_placeholders_are_filled(self):
        values = {"PERSONA": "Call them {{CALL}}.", "CALL": "민준님"}
        self.assertEqual(render_template.render("## Persona\n{{PERSONA}}", values), "## Persona\nCall them 민준님.")

    def test_missing_persona_is_refused(self):
        with self.assertRaises(KeyError):
            render_template.render("{{PERSONA}}", {"PERSONA": ""})

    def test_render_refuses_missing_values(self):
        with self.assertRaises(KeyError):
            render_template.render("Hi {{NAME}} {{OTHER}}", {"NAME": "A", "OTHER": ""})

    def test_every_template_renders_with_example_values(self):
        config = assistant_config.read(REPO / "assistant.conf.example")
        values = {**config, "ASSISTANT_DIR": "/repo", "PYTHON": "/py", "SONG_RULE": render_template.song_rule(config),
                  "PERSONA": (REPO / "persona.example.md").read_text(encoding="utf-8")}
        for template in sorted((REPO / "templates").glob("*.tmpl")):
            with self.subTest(template=template.name):
                rendered = render_template.render(template.read_text(encoding="utf-8"), values)
                self.assertNotIn("{{", rendered)

    def test_song_rule_follows_the_apple_music_setting(self):
        self.assertIn("music song", render_template.song_rule({"APPLE_MUSIC": "yes"}).split("first")[0])
        self.assertTrue(render_template.song_rule({"APPLE_MUSIC": "no"}).startswith("- When the user asks for a song"))
        self.assertEqual(render_template.song_rule({}), render_template.YOUTUBE_SONG_RULE)

    def test_settings_register_the_tool_guard_for_risky_tools(self):
        import json
        values = {**assistant_config.read(REPO / "assistant.conf.example"), "ASSISTANT_DIR": "/repo", "PYTHON": "/py"}
        settings = json.loads(render_template.render((REPO / "templates/assistant-settings.json.tmpl").read_text(encoding="utf-8"), values))
        guards = [entry for entry in settings["hooks"]["PreToolUse"] if "tool_guard.py" in entry["hooks"][0]["command"]]
        self.assertEqual(len(guards), 1)
        self.assertEqual(guards[0]["matcher"], "*")

    def test_templates_carry_no_personal_leftovers(self):
        # Names reach the templates only through placeholders, never written in.
        example = assistant_config.read(REPO / "assistant.conf.example")
        names = [example[key] for key in ("ASSISTANT_NAME_KO", "ASSISTANT_NAME_EN", "USER_NAME_EN", "USER_CALL_KO")]
        for template in sorted((REPO / "templates").glob("*.tmpl")):
            text = template.read_text(encoding="utf-8")
            with self.subTest(template=template.name):
                self.assertNotIn("/Users/", text)
                for name in names:
                    self.assertNotIn(name, text)


if __name__ == "__main__":
    unittest.main()
