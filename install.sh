#!/bin/bash
# Voice assistant installer. Run it from the repository folder: ./install.sh
# Safe to run again: each step skips what is already done, and your memory notes, word list and
# voice thread id are never overwritten.
#
#   ./install.sh           everything: checks, settings files, Keychain key, signing, apps, LaunchAgents
#   ./install.sh --check   only checks the requirements and writes the settings files
#
# The ElevenLabs API key goes into the login Keychain (service voice-assistant-elevenlabs), never a file.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

PYTHON=/opt/homebrew/bin/python3
FFPLAY=/opt/homebrew/bin/ffplay
FFMPEG=/opt/homebrew/bin/ffmpeg
KEYCHAIN_SERVICE=voice-assistant-elevenlabs
AGENTS_DIR="$HOME/Library/LaunchAgents"
AGENTS=(local.voice-assistant.morning local.voice-assistant.credit local.voice-assistant.avatar)
CLIPS=(idle greeting listening thinking speaking speaking_happy speaking_sad speaking_playful speaking_comfort)
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

step() { printf '\n== %s\n' "$1"; }
fail() { printf '\ninstall: %s\n' "$1" >&2; exit 1; }
warn() { printf '  주의: %s\n' "$1"; }

check_requirements() {
  step "준비물 확인"
  [ "$(uname -s)" = Darwin ] || fail "macOS에서만 동작해요."
  [ "$(uname -m)" = arm64 ] || fail "Apple Silicon Mac(Homebrew가 /opt/homebrew)이 필요해요."
  [ -x "$PYTHON" ] || fail "Python이 없어요: brew install python"
  [ -x "$FFPLAY" ] && [ -x "$FFMPEG" ] || fail "ffmpeg가 없어요: brew install ffmpeg"
  command -v swiftc >/dev/null || fail "Swift 컴파일러가 없어요: xcode-select --install"
  command -v openssl >/dev/null || fail "openssl이 없어요."
  echo "  ok"
}

ensure_conf() {
  step "설정 파일 assistant.conf"
  if [ ! -f assistant.conf ]; then
    cp assistant.conf.example assistant.conf
    echo "  assistant.conf를 만들었어요. 이름, ElevenLabs 목소리 id를 채운 뒤 ./install.sh를 다시 실행하세요."
    exit 0
  fi
  # shellcheck source=/dev/null
  source assistant.conf
  [ -n "${ASSISTANT_NAME_KO:-}" ] && [ -n "${USER_CALL_KO:-}" ] && [ -n "${USER_NAME_EN:-}" ] ||
    fail "assistant.conf에 ASSISTANT_NAME_KO, USER_CALL_KO, USER_NAME_EN을 채우세요."
  [ -x "${T3_BIN:-}" ] || fail "t3 명령이 없어요: $T3_BIN (README의 'T3 Code 준비'를 보세요)"
  [ -n "${ELEVENLABS_VOICE_ID:-}" ] || warn "ELEVENLABS_VOICE_ID가 비어 있어서 비서는 macOS Yuna 목소리로 말해요."
  echo "  ok"
}

# How the assistant is called by name: 하나 -> 하나야, 지민 -> 지민아 (아 after a final consonant).
vocative() {
  "$PYTHON" -I -c 'import sys
name = sys.argv[1]
last = ord(name[-1]) - 0xAC00 if name else -1
print(name + ("아" if 0 <= last < 11172 and last % 28 else "야") if 0 <= last < 11172 else name)' "$1"
}

render() {
  "$PYTHON" -I tools/render_template.py "templates/$1.tmpl" "$2"
}

write_settings_files() {
  step "비서 프롬프트와 설정 파일 만들기"
  [ -f persona.md ] || cp persona.example.md persona.md
  printf '%s\n%s\n' "$ASSISTANT_NAME_KO" "$ASSISTANT_NAME_EN" > assistant-name.txt
  render assistant-system.md assistant-system.md
  render assistant-settings.json assistant-settings.json
  render claude-md-milestone.md claude-md-milestone.md
  [ -f assistant-memory.md ] || render assistant-memory.md assistant-memory.md
  if [ ! -f vocabulary.txt ]; then
    { cat vocabulary.example.txt; printf '%s\n' "$ASSISTANT_NAME_KO" "$(vocative "$ASSISTANT_NAME_KO")" \
      "$ASSISTANT_NAME_EN" "$USER_CALL_KO" "$USER_SHORT_CALL_KO" "$USER_NAME_EN" | awk '!seen[$0]++'; } > vocabulary.txt
  fi
  echo "  persona.md, assistant-system.md, assistant-settings.json, assistant-memory.md, vocabulary.txt, claude-md-milestone.md"
}

check_media() {
  step "아바타 영상 확인"
  local missing=()
  for clip in "${CLIPS[@]}"; do
    [ -f "avatar/$clip.mp4" ] || missing+=("$clip")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    warn "없는 영상: ${missing[*]} (docs/AVATAR.ko.md를 보고 만들어 넣으세요. 없는 동안은 avatar.png나 빈 화면이 보여요.)"
  else
    echo "  영상 ${#CLIPS[@]}개 모두 있음"
  fi
  [ -f sounds/cue.caf ] || warn "sounds/cue.caf가 없어서 듣기 신호음은 macOS 기본 소리를 써요."
}

ensure_api_key() {
  step "ElevenLabs API 키 (키체인)"
  if security find-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
    echo "  이미 키체인에 있음"
    return
  fi
  printf '  ElevenLabs API 키를 붙여 넣고 Enter (화면에 안 보여요, 건너뛰려면 그냥 Enter): '
  local key
  read -rs key
  echo
  if [ -z "$key" ]; then
    warn "건너뜀. 키가 없으면 Yuna 목소리로 말해요. 나중에 ./install.sh를 다시 실행하면 돼요."
    return
  fi
  case "$key" in
    *[!A-Za-z0-9_-]*)
      warn "키에 예상하지 못한 문자가 있어서 저장하지 않았어요. 키를 다시 복사해서 ./install.sh를 실행하세요."
      return ;;
  esac
  # The key reaches security on standard input (its interactive mode), written by the shell's
  # built-in printf, so it never appears on a command line other processes could read.
  printf 'add-generic-password -U -a "%s" -s "%s" -w %s\n' "$USER" "$KEYCHAIN_SERVICE" "$key" | security -i >/dev/null
  key=""
  if security find-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
    echo "  저장했어요"
  else
    warn "키체인에 저장하지 못했어요."
  fi
}

build_apps() {
  step "서명 인증서와 앱 빌드 (처음엔 1~2분)"
  ./make_signing_identity.sh
  ./build_listen.sh
  pkill -x assistant_avatar 2>/dev/null || true
  ./build_avatar.sh
}

install_agents() {
  step "LaunchAgent 설치 (아침 브리핑, 크레딧 알림, 아바타 자동 실행)"
  mkdir -p "$AGENTS_DIR"
  for label in "${AGENTS[@]}"; do
    render "$label.plist" "$AGENTS_DIR/$label.plist"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENTS_DIR/$label.plist"
    echo "  $label"
  done
}

print_next_steps() {
  step "다음 할 일 (README의 순서대로)"
  cat <<NEXT
  1. T3 Code에 비서 공급자 인스턴스를 추가하세요. 실행 인자(launch args):
       --settings $HERE/assistant-settings.json --append-system-prompt-file $HERE/assistant-system.md
     인스턴스 id는 assistant.conf의 ASSISTANT_INSTANCE($ASSISTANT_INSTANCE)와 같아야 해요.
  2. 비서 스레드 만들기:  tools/create_voice_thread.sh <T3 프로젝트 폴더>
  3. 단축어("${ASSISTANT_NAME_KO}" 부르기)에 셸 스크립트 실행:  /bin/bash $HERE/talk.sh
  4. 다른 스레드의 마일스톤 보고를 원하면 claude-md-milestone.md 내용을 ~/.claude/CLAUDE.md에 붙이세요.
NEXT
}

check_requirements
ensure_conf
write_settings_files
check_media
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo
  echo "확인만 했어요 (--check). 전체 설치는 ./install.sh"
  exit 0
fi
ensure_api_key
build_apps
install_agents
print_next_steps
