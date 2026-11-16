**English** | [한국어](README.ko.md)

# T3 Voice Assistant (unofficial)

An unofficial voice assistant for T3 Code, not made by the T3 Code team. Call it by voice, and it answers, checks on your T3 Code work threads,
and hands them work for you. You choose its name, character, speech style, face and voice
(the example name is "Hana"). It floats in a screen corner as a video avatar, speaks with a matching
expression, and controls your Mac's volume, music and apps by voice.

Follow this README from top to bottom and you will end up with the same setup.

> **Beta.** So far this has been tested only on the author's Mac (Apple Silicon, macOS 27). Expect rough
> edges, especially in the T3 Code setup steps, and please report what did not work.

> **Built for Korean.** Speech recognition, the voice and the default persona are set up for Korean.
> The assistant can answer in English when you speak English, but listening is tuned for Korean, and
> the installer prints its messages in Korean.

![Illustration of a voice conversation: a shortcut opens listening, the assistant reads a T3 Code thread, plays a song on YouTube, and passes on a milestone report from another thread.](docs/media/demo-en.gif)

*An illustration of the flow, not a screen recording. Your assistant uses your own avatar, voice and persona.*

## Contents

1. [What it does](#what-it-does)
2. [How it works](#how-it-works)
3. [Requirements](#requirements)
4. [Install](#install)
5. [Permissions on first use](#permissions-on-first-use)
6. [Usage](#usage)
7. [Changing settings](#changing-settings)
8. [Troubleshooting](#troubleshooting)
9. [Uninstall](#uninstall)
10. [Files](#files)
11. [Security notes](#security-notes)
12. [License and notices](#license-and-notices)

## What it does

- **Voice conversation**: Start with a keyboard shortcut (⌃⌥C, built into the avatar app), the menu bar icon or a click on the avatar. The assistant greets you, you speak, it answers, and you take turns. No window appears while it listens. Speech recognition runs on the Mac, in Korean and English. The main spoken language (set in the menu) listens live; when it is unsure, the recording is heard again in the other language (about 0.2 s) and the surer result is sent, so you can just speak English. Short pauses while you talk are fine: everything said before a pause is kept. "bye" or "that's all" ends a conversation in English.
- **T3 Code assistant**:
  - Reads thread lists, thread contents and progress, and sums them up in a few sentences.
  - Sends messages to other threads or starts new ones. Anything that changes something is always confirmed by voice first.
- **Speaks up on its own**:
  - When a work thread passes a big milestone, it sends one `[마일스톤]` line and the assistant tells you.
  - From 23:00 to 12:00 news is held and given as a morning briefing at 12:00.
- **Voice**: Speaks with an ElevenLabs voice you choose (a cloned voice is recommended). Replies start playing as soon as audio arrives, and emotion tags are acted out. Without ElevenLabs it uses the macOS Yuna voice. A reply that arrives while another is playing (such as a milestone report in the middle of an answer) waits its turn instead of cutting in. Each reply is spoken in its own language: English replies in English, Korean ones in Korean.
- **Avatar**: An always-on video avatar.
  - Its clip follows the state (greeting, listening, thinking, speaking).
  - While speaking it shows a happy, sad, playful or comforting clip, chosen by the reply's first emotion tag.
  - Caption bubbles: your words appear live while you talk, and the reply fills in at the pace of speech in either language. The bubble grows to show the whole reply; a longer one scrolls smoothly, and with the pointer on it you can scroll back with the trackpad or wheel (it stays while you read). Korean wraps between words. The bubbles fade a few seconds after the voice stops, or soon after you end the conversation. Turn them off with "Show captions" in the menu.
  - Sound bars on the photo follow how loud your voice (while listening) and the assistant's voice (while speaking) are.
  - Hover to see a status label; scroll to resize it.
  - A menu bar icon shows the state. Its menu, also opened by a right-click on the avatar, starts or ends a conversation, changes the keyboard shortcut, the main spoken language and the menu language (English by default, or 한국어), shows or hides the avatar, captions and sound bars, sets the avatar's size, moves it back to the top right corner and shows the ElevenLabs characters left.
- **Memory**: New sessions start with the notes in `assistant-memory.md`, and the assistant writes down what matters.
- **Mac control**:
  - Changes the volume.
  - Plays songs on YouTube right away, and pauses YouTube in Chrome or skips to the next video.
  - Controls the Music app.
  - Opens and quits apps. Only quitting asks first.
  - Turns music down during a conversation and back up afterwards.
- **Credit alert**: Once a month, tells you when ElevenLabs use passes 80% of the limit.

## How it works

```
Keyboard shortcut / avatar click
  └─ talk.sh .................... runs one conversation (greet, listen, send, repeat)
       ├─ AssistantListen.app ... listens on the microphone and transcribes on the device
       │                          (main language live; when unsure, the other language rechecks the recording)
       └─ say_to_assistant.sh ... sends the words to the assistant's T3 thread and waits for the spoken reply
            └─ The assistant's thread in T3 Code (Claude Code, its own provider instance)
                 ├─ assistant-system.md ... its persona and rules (made by install.sh)
                 ├─ memory_hook.py ........ hands over the memory notes when a session starts
                 ├─ guard_launch.py ....... keeps new work threads from becoming the assistant itself
                 ├─ tool_guard.py ......... limits its shell, file and web tools (see Security notes)
                 ├─ mac_control.py ........ runs only the fixed Mac control commands
                 ├─ file_search.py ........ finds files in the readable folders (instead of shell searches)
                 └─ speak.py (Stop hook) .. tidies the reply and passes it to voice.py
                      └─ voice.py ......... speaks through ElevenLabs and tells the avatar the speaking style
AssistantAvatar.app ................. switches clips by watching talk.state and the speaking.* files,
                                      and draws captions and sound bars from the caption-* and level-* files
LaunchAgents ........................ 12:00 morning briefing, credit check every 6 hours, avatar at login
```

The assistant is a Claude Code session running inside T3 Code. Its own provider instance reads this
repository's settings and prompt through `--settings` and `--append-system-prompt-file`. Only those
settings contain the hook that speaks, so your other work threads stay silent.

## Requirements

| Item | Notes |
|---|---|
| Mac | Apple Silicon. macOS 15 or later recommended (built on macOS 27) |
| Homebrew | `brew install python ffmpeg` (Python at `/opt/homebrew/bin/python3`; `ffplay` and `ffmpeg` are needed) |
| Xcode Command Line Tools | `xcode-select --install` (`swiftc` builds the apps) |
| T3 Code | The desktop app and the `t3` command (default `~/.local/bin/t3`) |
| Claude | A Claude plan that can use the Claude Code provider in T3 Code |
| ElevenLabs | An account and API key. Voice cloning (Instant Voice Clone) needs a paid plan; check prices and included characters when you sign up |
| Google Chrome | Needed to pause YouTube and skip videos (when it is your default browser) |
| 9 avatar clips | You make them with the prompts in [docs/AVATAR.md](docs/AVATAR.md). They are not in this repository |

## Install

### 1. Get the repository

```bash
git clone <this repository's URL> ~/t3-voice-assistant
cd ~/t3-voice-assistant
```

Any folder works. Do not move it after installing; if you do, run `./install.sh` again.

### 2. Make the avatar and the voice

Follow [docs/AVATAR.md](docs/AVATAR.md) to prepare:

- the 9 `avatar/*.mp4` clips and `avatar.png`
- an ElevenLabs cloned voice (note its voice id)
- optional: the listening cue `sounds/cue.caf`

Installing and talking work without the clips; until they exist, the avatar shows `avatar.png` or nothing.

### 3. Fill in the settings

```bash
./install.sh              # the first run creates assistant.conf and stops
open -e assistant.conf    # fill in the values below
```

| Key | Example | Meaning |
|---|---|---|
| `ASSISTANT_NAME_KO`, `ASSISTANT_NAME_EN` | `하나`, `Hana` | The assistant's name, used on the avatar label (the English one when the menu is in English), as the thread title and in the recognizer's word list |
| `USER_NAME_EN` | `Alex` | What it calls you in English replies |
| `USER_CALL_KO` | `민준님` | What it calls you in Korean |
| `USER_SHORT_CALL_KO` | `민준님` | A shorter form it uses now and then (may be the same) |
| `ELEVENLABS_VOICE_ID` | `AbCd...` | The voice id copied from ElevenLabs > Voices |
| `ELEVENLABS_KEY_MONTHLY_LIMIT` | `100000` | The monthly cap set on the API key, `0` if none |
| `T3_BIN` | `$HOME/.local/bin/t3` | Where the `t3` command is |
| `ASSISTANT_INSTANCE` | `claudeAgent_voice_assistant` | The instance id you create in step 5 |
| `ASSISTANT_MODEL` | `claude-sonnet-5-5` | The model the assistant runs on |
| `WORK_INSTANCE`, `WORK_MODEL` | `claudeAgent`, `claude-sonnet-5-5` | The instance and model it gives new work threads |
| `GREETING` | `부르셨어요?` | What it says after your name when a conversation starts |
| `PHRASE_*` | `알겠어요, 또 불러 주세요!` | Six fixed phrases spoken without the model (goodbye in Korean and English, errors). Match your persona's style |
| `ASSISTANT_READ_FOLDERS` | `$HOME/Documents/Notes` | Optional. More folders the assistant may read, separated by `:` (see Security notes). Empty means only this folder |

Write the assistant's character and speech style in `persona.md`. The first install copies
`persona.example.md` (a friendly polite secretary) to `persona.md`; change it as you like, using the
examples in [docs/PERSONA.md](docs/PERSONA.md). `persona.md` is your own file and is never pushed to
GitHub. Run `./install.sh` again after editing it. The shared rules (spoken replies, emotion tags,
tool use) live in `templates/assistant-system.md.tmpl`.

### 4. Run the installer

```bash
./install.sh
```

The installer runs these steps. Running it again is safe; it never overwrites your memory notes, word list or voice thread id.

1. Checks the requirements.
2. Writes these files:
   - `assistant-system.md` (prompt), `assistant-settings.json` (hooks and permissions)
   - `assistant-memory.md`, `vocabulary.txt`, `claude-md-milestone.md`
3. Asks for the ElevenLabs API key and stores it in the login Keychain (service `voice-assistant-elevenlabs`), never in a file.
4. Creates the self-signed certificate `Voice Assistant Local Signing` in its own keychain and builds `AssistantListen.app` and `AssistantAvatar.app` with it. Because every build uses the same certificate, macOS recognizes the apps after a rebuild and does not ask for permissions again.
5. Installs three LaunchAgents (`local.voice-assistant.morning`, `local.voice-assistant.credit`, `local.voice-assistant.avatar`). The avatar appears now.

To only check the requirements and write the settings files, run `./install.sh --check`.

### 5. Add the assistant's instance to T3 Code

In T3 Code's settings, add one more Claude provider instance:

- Instance id: the same as `ASSISTANT_INSTANCE` in `assistant.conf` (for example `claudeAgent_voice_assistant`)
- Display name: `Voice Assistant`
- Launch args: the installer prints them with the real paths at the end.

```
--settings <repo>/assistant-settings.json --append-system-prompt-file <repo>/assistant-system.md
```

If the settings screen cannot add it, quit T3 Code completely, add this entry under `providerInstances`
in `~/.t3/userdata/settings.json`, and start T3 Code again. Make a copy of the file before editing it.

```json
"claudeAgent_voice_assistant": {
  "driver": "claudeAgent",
  "displayName": "Voice Assistant",
  "enabled": true,
  "config": {
    "launchArgs": "--settings /Users/<you>/t3-voice-assistant/assistant-settings.json --append-system-prompt-file /Users/<you>/t3-voice-assistant/assistant-system.md"
  }
}
```

The assistant reads threads, sends messages and runs the Mac control script, so its thread is meant to
run in a permission mode that uses tools without asking (T3's full access). Anything that changes
something is still confirmed by voice first, as its prompt rules require.

### 6. Create the assistant's thread

With T3 Code running, pick the T3 project folder for the assistant's thread and run the command below.
You can open this repository folder as a project in T3 and use it.

```bash
tools/create_voice_thread.sh ~/t3-voice-assistant
```

A new thread named after the assistant is created and its id is saved in `voice-thread-id`. If the
assistant greets you, it worked. You can also create it in T3 yourself: start a new thread on the
assistant's instance and write its id on one line in `voice-thread-id`.

Prompt and settings changes apply **from a new session**. For an existing thread, clear its context in T3 (/clear) or create a new thread.

### 7. The keyboard shortcut

The avatar app has a built-in keyboard shortcut, **⌃⌥C** (Control + Option + C). It works from any app while the avatar is running, and the avatar starts at login. Nothing needs to be set up. To change it or turn it off, use "단축키" in the menu bar icon's menu.

Avoid ⌃⌥Space and ⌃Space: macOS uses them to switch input sources (한/영) by default, and a system shortcut wins over the app's. ⌥Space is used by some apps, such as Claude's quick entry.

The shortcut works like a click on the avatar. It starts a conversation. While the assistant speaks, it only cuts the speech off. When the microphone opened on its own after the assistant spoke and you have not said anything yet, listening starts over. Otherwise it ends the conversation.

You can also start a conversation from the macOS Shortcuts app (for example to run it with Siri): add a "Run Shell Script" action (shell `bash`, input none) with `/bin/bash /Users/<you>/t3-voice-assistant/talk.sh`, and turn on "Allow Running Scripts" in Shortcuts settings > Advanced. Do not give it the same key as the built-in shortcut.

### 8. Turn on milestone reports from other threads (optional)

Paste the contents of `claude-md-milestone.md` (made by the installer) into `~/.claude/CLAUDE.md`.
Your other Claude threads then send the assistant one line at big milestones (a finished feature,
all tests passing, a PR, a deploy, or a blocker), and the assistant tells you.

## Permissions on first use

macOS asks for permissions the first few times. Choose **Allow** for all of them.

| When | What | Asked by |
|---|---|---|
| First conversation | Microphone, Speech Recognition | AssistantListen |
| First run of a Shortcuts app shortcut (optional) | Running scripts | Shortcuts |
| Playing music, starting a conversation | Control of Music, Google Chrome, System Events | T3 Code, Shortcuts, AssistantAvatar |
| Pausing YouTube, skipping videos | In Chrome: View > Developer > Allow JavaScript from Apple Events | (turn on yourself) |

If you clicked "Don't Allow" by mistake, turn it back on in System Settings > Privacy & Security > Automation (or Microphone, Speech Recognition).

## Usage

Press the shortcut or click the avatar, then speak (in Korean):

- "지금 돌아가는 스레드 몇 개야?" (How many threads are running?)
- "블로그 스레드 뭐 하고 있어?" (What is the blog thread doing?)
- "블로그 스레드에 '오늘 한 일 정리해 줘'라고 보내 줘" (Send "sum up today's work" to the blog thread): it asks "보낼까?" and sends only after you say yes.
- "아이유 노래 틀어줘", "잠깐 멈춰", "다음 곡", "다시 틀어", "이거 무슨 노래야?" (play, pause, next, resume, what is this song)
- "볼륨 조금 줄여줘", "볼륨 30으로", "음소거" (a bit quieter, volume 30, mute)
- "메모 앱 열어줘", "사파리 종료해 줘" (open Notes, quit Safari): quitting asks first.
- To finish: "오늘은 여기까지", "그만 얘기하자", "잘 자"

The conversation ends on its own after silence or 30 turns. After the assistant reads out another thread's reply, it listens again for a moment.

**Emotion and the avatar**: the reply's first emotion tag picks the speaking clip.

| Situation | First tag | Clip |
|---|---|---|
| Good news, praise | `[cheerfully]`, `[excited]` | speaking_happy |
| Something bad happened (a failure, a server down) | `[sadly]` | speaking_sad |
| Apologizing for its own mistake | `[apologetically]` | speaking_sad |
| Only feeling low (tired, a rough day) | `[gently]`, `[sympathetically]` | speaking_comfort |
| Teasing, jokes | `[playfully]`, `[teasing]` | speaking_playful |
| Anything else | `[calmly]`, `[warmly]`, none | speaking |

## Changing settings

| What | Where | How it takes effect |
|---|---|---|
| How it calls you, greeting, fixed phrases, voice id, key cap | `assistant.conf` | Run `./install.sh` again; the assistant from a new session |
| Name | `ASSISTANT_NAME_*` in `assistant.conf` | Run `./install.sh` again; close and reopen the avatar |
| Character, speech style | `persona.md` | Run `./install.sh` again; from a new session |
| Shared rules | `templates/assistant-system.md.tmpl` | Run `./install.sh` again; from a new session |
| Words it should recognize better | `vocabulary.txt` | From the next conversation |
| Avatar clips | `avatar/*.mp4` (`tools/prepare_clip.sh`) | Right-click the avatar > close, then reopen |
| Listening cue | `sounds/cue.caf` | From the next conversation |
| Quiet hours at night | `QUIET_START_HOUR`, `QUIET_END_HOUR` in `speak.py` | Right away |

## Troubleshooting

| Symptom | Check |
|---|---|
| The assistant does not speak | `speak.log`. Do the instance's launch args contain `--settings .../assistant-settings.json`? |
| It speaks with the robotic Yuna voice | Whether `./install.sh` stored the API key, `ELEVENLABS_VOICE_ID`, the characters left in the avatar's menu |
| The shortcut does nothing | The "단축키" item in the menu bar menu (is it on, and not refused?). Another app or a system shortcut on the same key (⌃⌥Space switches input sources). The last lines of `voice.log`, microphone and speech recognition permissions |
| It sends to the wrong thread | Whether `voice-thread-id` holds the assistant's thread id |
| A changed rule has no effect | Whether you tested in a new session (an existing session remembers the old prompt) |
| YouTube does not pause | Chrome's "Allow JavaScript from Apple Events", Automation permission |
| Search results open instead of a song | YouTube sent a different page layout. The page is kept in `youtube-miss.html` |
| macOS asks for permissions again after a rebuild | Whether `./make_signing_identity.sh` ran (without the certificate, builds are signed ad hoc) |

The logs (`voice.log`, `speak.log`) keep only states and lengths, never the words spoken.

## Uninstall

```bash
./uninstall.sh          # the LaunchAgents and the avatar
./uninstall.sh --all    # also the ElevenLabs key and the signing keychain
```

Remove the assistant's T3 Code instance (and a Shortcuts app shortcut, if you made one) yourself, then delete the repository folder.

## Files

| File | Role |
|---|---|
| `talk.sh` | Runs one conversation: greet, listen, send, repeat; turns music down |
| `say_to_assistant.sh` | Sends the transcribed words to the assistant's thread and waits for the reply |
| `assistant_listen.swift` | The windowless listener (on-device Korean and English recognition, silence detection) |
| `assistant_avatar.swift` | The floating video avatar |
| `avatar_captions.swift`, `avatar_meter.swift` | The avatar's caption bubbles and sound bars |
| `avatar_menu.swift`, `avatar_hotkey.swift` | The menu bar icon and menu, and the built-in keyboard shortcut |
| `listen_transcript.swift` | Keeps what was said across pauses (the recognizer starts over after each one) and picks Korean or English |
| `listen_channel.swift` | One recognizer in one language, and the recording the second language listens to |
| `file_search.py` | The fixed file search command the assistant uses instead of shell searches (readable folders only, no secret files) |
| `speak.py` | Stop hook that tidies replies for speech; holds them for the morning briefing at night |
| `voice.py` | ElevenLabs streaming playback, the Yuna fallback, the fixed phrase cache, usage |
| `memory_hook.py` | Hands the memory notes to a new session |
| `guard_launch.py` | Hook that keeps new threads from becoming the assistant itself |
| `tool_guard.py` | Hook that lets the assistant use only allowlisted tools, within set limits (see Security notes) |
| `mac_control.py` | Volume, YouTube, Music and app control (fixed commands only) |
| `credit_alert.py` | The 80% ElevenLabs usage alert |
| `morning_digest.sh` | The 12:00 morning briefing |
| `install.sh`, `uninstall.sh` | Install and uninstall |
| `make_signing_identity.sh`, `sign_app.sh`, `signing_env.sh` | Stable code signing |
| `assistant_config.py`, `assistant.conf.example` | Reading the personal settings, and their example |
| `persona.example.md` | The default persona (copied to `persona.md` on install) |
| `templates/` | Sources of the prompt, settings, LaunchAgents and the CLAUDE.md snippet |
| `tools/` | Clip conversion, voice sample, creating the assistant's thread, filling templates |
| `tests/`, `run_tests.sh` | Tests (`./run_tests.sh`) |

## Security notes

### What is protected

- **Secrets live only in the Keychain.** The ElevenLabs API key and the signing keychain's password are stored only in the macOS Keychain. Installing and building pass them on standard input, never as command arguments, so other programs cannot read them from the process list. Personal files (`assistant.conf`, `persona.md`, the memory notes, logs) are kept out of the repository by `.gitignore`.
- **The assistant's tools are limited in code** (`tool_guard.py`). The assistant reads other threads, which can carry hidden instructions written to trick it (prompt injection). So, separately from the prompt's rules, a hook checks every tool call against an allowlist; any tool not on it is blocked, including tools Claude Code or T3 Code add later:
  - From T3 Code, only listing, reading and searching threads, sending messages, starting threads, waiting and interrupting are allowed. Deleting projects, worktrees, linking other machines, scheduling and delegating tasks are blocked.
  - Shell commands can only call `mac_control.py` and `file_search.py` (finding files in the readable folders, never secret ones). Chaining (`;`, `&&`, `|`), redirection and substitution (`$`, backticks) are blocked.
  - Files can be written only for the memory notes (`assistant-memory.md`). They can be read or searched only inside the repository folder, in long results Claude Code saved from the session's own tool calls, and in folders you list in `ASSISTANT_READ_FOLDERS`. Paths that escape through symlinks or `..` are blocked.
  - Files that look like secrets (`.env`, `*.pem`, `*.key`, `id_rsa`, names with `credential` or `secret`) are never read, wherever they are. In the listed folders a search can list matching files but not pull matching lines out of the whole folder, so a key cannot be swept up in passing.
  - Web access (WebFetch, WebSearch), sub-agents and skills are off.
- **Mac control input never becomes code.** Song and app names reach AppleScript only as values, and app names with paths or options are refused. T3 Code and the assistant's own apps cannot be quit.
- **Logs never contain what was said.** Only states and lengths are recorded. For the captions, the words are written to `caption-*.txt` (readable only by you) only while they are being said, and removed afterwards; the sound bars read only loudness numbers.

### Remaining risks and cautions

1. **Messaging and starting threads are still possible.** The assistant can send messages to other threads and start new ones. Asking you first is a prompt rule, not something code enforces. When it asks "보낼까?" (send it?), listen to the whole message before you answer. A work thread that receives a message works with that thread's own permissions, so give work threads only the permission mode they need.
2. **Voice confirmation cannot tell who is speaking.** While a conversation is open, a person nearby or a TV can also be heard as "yes". Do not leave a conversation open around other people.
3. **What you say goes to outside services.** Only speech recognition stays on the Mac.
   - What you say, thread contents it reads, and the memory notes → Anthropic (Claude)
   - The assistant's reply text → ElevenLabs (to make the voice)
   - Song search words → YouTube
   Each company's privacy policy applies. Do not tell the assistant sensitive things such as passwords, account numbers or health details.
4. **The memory notes are not encrypted.** `assistant-memory.md` is a plain file on the Mac. There is a rule against writing sensitive details, but it is a rule the model follows. Look at the file now and then.
5. **Programs in the same macOS account can use the signing key.** Malware already running in your account could sign itself as the listener app. Do not install this in a macOS account shared by several people.
6. **The assistant's thread runs with full access.** The hook is what limits it. Turning the hook off or editing the hook list in `assistant-settings.json` removes the protection. When you change the templates, run the tests in `tests/` too (`./run_tests.sh`).
7. **Folders you open with `ASSISTANT_READ_FOLDERS` can be read.** When the assistant reads a file there, its text goes to Anthropic like everything else it reads. Secret-looking file names are blocked, but other sensitive documents are not, so list only folders you are comfortable sharing.
8. **Playing a song reads YouTube's search page.** To play a song right away, `mac_control.py` downloads the YouTube search results page for the words you said and takes the first video. YouTube's Terms of Service do not allow automated access to the service, so this part is used at your own discretion. It sends only the search words, from your own Mac, once per request. If you would rather not, do not ask it to play songs on YouTube, or change it to use the YouTube Data API.
9. **Clone only a voice you have the right to use.** ElevenLabs allows cloning only your own voice or a voice whose owner agreed. The guide clones the voice of avatar clips you generate yourself; never clone a real person's voice without their consent.
10. **Review updates before you take them.** When you pull a changed version of this repository, look at how the hooks and settings templates changed first.

## License and notices

This project is under the [MIT License](LICENSE). Anyone, individuals and companies alike, may use,
change, redistribute and sell it. The one condition is that copies and changed versions keep the
copyright notice in `LICENSE` (`Copyright (c) 2026 wonkyjunky`) and the license text.

If you publish a changed version, please also link to the original repository in your README. The
license does not require this; it is a request.

- This is a personal project. It is not affiliated with, made by or endorsed by T3 Code, Anthropic (Claude), ElevenLabs, Google (YouTube, Chrome) or Apple. Their names and trademarks belong to them.
- You sign up for ElevenLabs, Claude and T3 Code yourself, under their terms and plans, and pay for your own use.
- Make the cloned voice and the avatar only from a voice and face you have the rights to, or from a fictional character you created. Do not use another person's voice or face without their permission.
- `youtube play` reads YouTube's search results page to find the first video. Check YouTube's terms of service and the rules where you live, and decide for yourself. To avoid it, have the assistant use only `youtube search` (through your persona or the prompt).
- The software is provided as is, and the copyright holder is not liable for problems from its use (see the license text).
