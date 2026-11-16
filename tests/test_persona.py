"""Tests for persona.py and per-assistant prompts. Run: python3 -m unittest discover -s tests"""
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))
sys.path.insert(0, str(REPO / "tools"))

import persona  # noqa: E402
import render_template  # noqa: E402


class PersonaTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        (self.folder / "personas" / "sora").mkdir(parents=True)
        (self.folder / "personas" / "sora" / "persona.conf").write_text(
            'ASSISTANT_NAME_KO="소라"\nASSISTANT_NAME_EN="Sora"\nELEVENLABS_VOICE_ID="v2"\n')
        (self.folder / "personas" / "notes").mkdir()  # no persona.conf: not an assistant
        self.saved = (persona.PERSONAS_DIR, persona.CURRENT_PATH, persona.HERE, persona.assistant_config.load)
        persona.PERSONAS_DIR = self.folder / "personas"
        persona.CURRENT_PATH = self.folder / "persona"
        persona.HERE = self.folder
        persona.assistant_config.load = lambda: {"ASSISTANT_NAME_KO": "하나", "ELEVENLABS_VOICE_ID": "v1", "T3_BIN": "t3"}

    def tearDown(self):
        persona.PERSONAS_DIR, persona.CURRENT_PATH, persona.HERE, persona.assistant_config.load = self.saved

    def test_the_main_assistant_and_each_folder_with_a_persona_conf(self):
        self.assertEqual(persona.persona_ids(), ["main", "sora"])

    def test_no_choice_means_the_main_assistant(self):
        self.assertEqual(persona.current_id(), "main")
        self.assertEqual(persona.value("main", "ELEVENLABS_VOICE_ID"), "v1")
        self.assertEqual(persona.value("main", "thread_file"), str(self.folder / "voice-thread-id"))

    def test_another_assistant_overrides_only_what_it_sets(self):
        persona.switch("sora")
        chosen = persona.current_id()
        self.assertEqual(persona.value(chosen, "ELEVENLABS_VOICE_ID"), "v2")
        self.assertEqual(persona.value(chosen, "T3_BIN"), "t3", "the rest comes from assistant.conf")
        self.assertEqual(persona.value(chosen, "voice_cache"), str(self.folder / "personas/sora/voice_cache"))

    def test_an_unknown_assistant_cannot_be_chosen(self):
        with self.assertRaises(ValueError):
            persona.switch("notes")
        (self.folder / "persona").write_text("gone\n")
        self.assertEqual(persona.current_id(), "main", "a stale choice falls back to the main assistant")


class PersonaPromptTests(unittest.TestCase):
    def test_another_assistants_prompt_uses_its_names_and_persona_md(self):
        folder = Path(tempfile.mkdtemp())
        (folder / "persona.conf").write_text('ASSISTANT_NAME_KO="소라"\nUSER_CALL_KO="민준오빠"\n')
        (folder / "persona.md").write_text("Speak softly, {{USER_CALL_KO}}.")
        values = render_template.install_values(folder)
        self.assertEqual(values["ASSISTANT_NAME_KO"], "소라")
        text = render_template.render("{{ASSISTANT_NAME_KO}}: {{PERSONA}}", values)
        self.assertEqual(text, "소라: Speak softly, 민준오빠.")

    def test_a_folder_without_persona_md_uses_the_example(self):
        folder = Path(tempfile.mkdtemp())
        (folder / "persona.conf").write_text('ASSISTANT_NAME_KO="소라"\n')
        example = (REPO / "persona.example.md").read_text(encoding="utf-8").strip()
        self.assertEqual(render_template.install_values(folder)["PERSONA"], example)


if __name__ == "__main__":
    unittest.main()
