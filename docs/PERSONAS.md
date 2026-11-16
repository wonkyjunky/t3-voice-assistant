**English** | [한국어](PERSONAS.ko.md)

# More than one assistant

Besides the main assistant (set up by `assistant.conf` and `persona.md`), you can keep more
assistants, each with its own name, character, voice, avatar and thread, and switch between them in
the avatar's menu ("Assistant"). They share the memory notes, so what you tell one, the others know.

## Files

Each extra assistant is a folder in `personas/` (the folder name is its id, for example `second`):

| File | What |
|---|---|
| `personas/second/persona.conf` | `KEY="value"` lines that differ from `assistant.conf`. The rest comes from `assistant.conf` |
| `personas/second/persona.md` | Its character and speech style (like `persona.md`). Copied from `persona.example.md` if missing |
| `personas/second/avatar/*.mp4`, `avatar.png` | Its clips and photo, made as in [AVATAR.md](AVATAR.md). Without them the avatar shows its name on a circle |
| `personas/second/voice_cache/`, `voice-thread-id` | Made for you: its greeting audio and its thread |

`personas/` and the file `persona` (the assistant in use) are personal and never pushed to GitHub.

A `persona.conf` usually sets:

```
ASSISTANT_NAME_KO="은서"
ASSISTANT_NAME_EN="Eunseo"
ELEVENLABS_VOICE_ID="..."            # its own voice ("" uses the macOS Yuna voice)
ASSISTANT_INSTANCE="claudeAgent_voice_assistant_second"   # its own T3 instance
GREETING="부르셨어요?"                # optional: its own greeting and form of address
USER_CALL_KO="민준오빠"
```

## Setting one up

1. Make `personas/second/persona.conf` (and `persona.md` if you want another character).
2. Run `./install.sh`. It writes the assistant's prompt (`assistant-system.md`) and names
   (`assistant-name.txt`) in its folder, and prints the next two steps for it.
3. In T3 Code, add a provider instance with the id you put in `ASSISTANT_INSTANCE` and these
   launch args:

   ```
   --settings <repo>/assistant-settings.json --append-system-prompt-file <repo>/personas/second/assistant-system.md
   ```

4. Make its thread: `tools/create_voice_thread.sh <T3 project folder> second`.
5. Pick it in the avatar's menu: Assistant > its name. The face, name label, voice, greeting, the
   names the listener expects and the thread it talks to all change at once.

After changing `persona.conf`, `persona.md` or the shared rules, run `./install.sh` again; the
assistant reads its prompt when a new session starts.
