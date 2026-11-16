[English](README.md) | **한국어**

# T3 Voice Assistant: T3 Code 음성 비서 (비공식)

T3 Code 팀이 만든 공식 도구가 아닌 비공식 음성 비서입니다. 말로 부르면 대답하고, T3 Code의 작업 스레드를 대신 확인하고 일을 맡겨 주는 음성 비서입니다.
비서의 이름, 성격, 말투, 얼굴, 목소리는 모두 직접 정합니다(예시 이름은 "하나").
화면 구석에 영상 아바타로 떠 있고, 감정에 맞는 표정으로 말하며, Mac의 볼륨, 음악, 앱도 말로 다룹니다.

이 README를 위에서부터 순서대로 따라 하면 똑같이 만들 수 있습니다.

> **베타입니다.** 지금까지 만든 사람의 Mac(Apple Silicon, macOS 27)에서만 시험했습니다. 특히 T3 Code 설정 단계에서
> 막히는 곳이 있을 수 있으니, 안 되는 부분이 있으면 알려 주세요.

![음성 대화 흐름 예시: 단축키로 듣기를 열고, 비서가 T3 Code 스레드를 읽고, 유튜브에서 노래를 틀고, 다른 스레드의 마일스톤 보고를 전합니다.](docs/media/demo-ko.gif)

*흐름을 보여 주는 예시 그림이며 실제 화면 녹화가 아닙니다. 실제 비서는 직접 만든 아바타, 목소리, 페르소나를 씁니다.*

## 목차

1. [할 수 있는 것](#할-수-있는-것)
2. [어떻게 동작하나](#어떻게-동작하나)
3. [준비물](#준비물)
4. [설치](#설치)
5. [처음 켤 때 허용할 권한](#처음-켤-때-허용할-권한)
6. [사용법](#사용법)
7. [설정 바꾸기](#설정-바꾸기)
8. [문제 해결](#문제-해결)
9. [제거](#제거)
10. [파일 안내](#파일-안내)
11. [보안 주의사항](#보안-주의사항)
12. [라이선스와 고지](#라이선스와-고지)

## 할 수 있는 것

- **음성 대화**: 단축키(⌃⌥C, 아바타 앱에 내장), 메뉴 막대 아이콘, 아바타 클릭으로 시작합니다. 비서가 인사하면 말하고, 대답을 들은 뒤 다시 말하는 식으로 번갈아 대화합니다. 듣는 동안 화면에 창이 뜨지 않습니다. 음성 인식은 Mac 안에서 한국어와 영어로 처리합니다. 메뉴에서 정한 기본 언어로 실시간 받아쓰고, 확신이 서지 않을 때만 녹음을 다른 언어로 한 번 더 들어(약 0.2초) 더 확실한 결과를 보냅니다. 그래서 영어로 그냥 말해도 됩니다. 말하다가 잠깐 쉬어도 괜찮습니다. 쉬기 전에 한 말도 모두 함께 보냅니다. 영어로는 "bye", "that's all"로 대화를 끝낼 수 있습니다.
- **T3 Code 비서**:
  - 스레드 목록, 내용, 진행 상태를 읽고 몇 문장으로 요약합니다.
  - 다른 스레드에 메시지를 보내거나 새 스레드를 시작합니다. 무언가를 바꾸는 일은 반드시 먼저 말로 확인받습니다.
- **먼저 말 걸기**:
  - 일하는 스레드가 큰 고비를 넘기면 `[마일스톤]` 한 줄을 보내고, 비서가 그걸 말로 전합니다.
  - 밤 23시부터 낮 12시까지는 소식을 모아 두었다가 12시에 아침 브리핑으로 알려 줍니다.
- **목소리**: ElevenLabs로 직접 고른 목소리(복제 목소리 추천)로 말합니다. 대답을 받는 대로 바로 재생하고, 감정 태그를 연기합니다. ElevenLabs를 쓸 수 없으면 macOS의 Yuna 목소리로 말합니다. 말하는 도중에 다른 대답이 오면(예: 대답 중에 도착한 마일스톤 보고) 끊고 끼어들지 않고 차례를 기다렸다가 말합니다. 대답마다 그 언어로 읽습니다. 영어 대답은 영어로, 한국어 대답은 한국어로 말합니다.
- **아바타**: 항상 떠 있는 영상 아바타입니다.
  - 상태에 따라 영상이 바뀝니다(인사, 듣기, 생각, 말하기).
  - 말할 때는 대답의 첫 감정 태그에 맞춰 기쁨, 슬픔, 장난, 위로 영상을 보여 줍니다.
  - 자막 말풍선: 말하는 동안 내 말이 실시간으로 뜨고, 비서의 대답은 한국어든 영어든 말하는 속도에 맞춰 채워집니다. 말풍선은 대답 전체가 보이게 커지고, 더 길면 부드럽게 스크롤됩니다. 포인터를 올리면 트랙패드나 휠로 앞부분을 다시 볼 수 있고, 읽는 동안에는 사라지지 않습니다. 한글은 어절 단위로 줄을 바꿉니다. 목소리가 끝나고 몇 초 뒤, 또는 대화를 끝내면 곧 사라집니다. 메뉴의 "Show captions"(자막 보이기)로 끌 수 있습니다.
  - 사진 아래쪽 소리 막대가 내 목소리(듣는 중)와 비서 목소리(말하는 중)의 크기에 맞춰 움직입니다.
  - 아바타 옆 "재생 중" 카드가 Chrome의 YouTube·YouTube Music이나 Music 앱에서 나오는 곡을 보여 줍니다. 재생/일시정지, 다음 곡(Music은 이전 곡도) 버튼과 음악 자체 볼륨 슬라이더가 있습니다. 슬라이더는 Mac 전체 볼륨과 비서 목소리 크기는 건드리지 않습니다. 일시정지해도 2분 동안 남아 카드에서 다시 틀 수 있습니다. 카드 빈 곳을 끌면 원하는 자리에 둘 수 있고, 더블클릭하거나 메뉴의 "오른쪽 위로 옮기기"를 누르면 아바타 옆으로 돌아옵니다.
  - 마우스를 올리면 상태 이름표가 보이고, 스크롤로 크기를 바꿀 수 있습니다.
  - 메뉴 막대 아이콘이 상태를 보여 줍니다. 그 메뉴(아바타 오른쪽 클릭으로도 열림)에서 대화 시작과 끝내기, 단축키 바꾸기, 기본 언어와 메뉴 언어(기본 English, 한국어로 바꿀 수 있음) 바꾸기, 아바타·자막·소리 막대·재생 중 카드 보이기, 아바타 크기, 오른쪽 위로 위치 되돌리기(재생 카드 포함), ElevenLabs 남은 글자 수 확인을 할 수 있습니다.
- **기억**: 새 세션에서도 `assistant-memory.md` 메모를 가지고 시작하고, 중요한 일은 비서가 스스로 적어 둡니다.
- **Mac 제어**:
  - 볼륨을 조절합니다.
  - 말한 노래를 바로 틉니다. Apple Music을 구독하면(`APPLE_MUSIC="yes"`) Music 앱에서 Apple Music으로 틀고(앱 창은 뜨지 않음), 아니면 브라우저의 유튜브로 틉니다. "잔잔한 음악" 같은 분위기 음악은 유튜브로 틉니다.
  - 음악은 한 곳에서만 나오게 합니다. 노래를 새로 틀면 다른 곳(Chrome의 유튜브나 Music 앱)에서 나오던 음악은 일시정지해서 나중에 다시 틀 수 있습니다. "멈춰", "다음 곡", "다시 틀어", "이거 무슨 노래야"는 지금 나오는 곳에 작동합니다.
  - Mac 전체 볼륨과 따로 음악 소리만 키우거나 줄입니다("음악 소리만 줄여줘").
  - Music 앱을 다룹니다.
  - 앱을 열고 닫습니다. 앱 닫기만 먼저 물어봅니다.
  - 대화하는 동안에는 음악 소리를 줄였다가, 대화가 끝나면 되돌립니다.
- **크레딧 알림**: ElevenLabs 사용량이 한도의 80%를 넘으면 한 달에 한 번 알려 줍니다.

## 어떻게 동작하나

```
단축키 / 아바타 클릭
  └─ talk.sh ............ 대화 한 번을 진행 (인사, 듣기, 보내기를 반복)
       ├─ AssistantListen.app ..... 마이크로 듣고 기기 안에서 받아씀
       │                            (기본 언어로 실시간, 확신이 없으면 녹음을 다른 언어로 다시 확인)
       └─ say_to_assistant.sh ..... 받아쓴 말을 T3의 비서 스레드로 보내고, 대답이 끝날 때까지 기다림
            └─ T3 Code의 비서 스레드 (Claude Code, 비서 전용 인스턴스)
                 ├─ assistant-system.md ...... 비서의 성격과 규칙 (install.sh가 만듦)
                 ├─ memory_hook.py ......... 새 세션 시작 때 기억 메모 전달
                 ├─ guard_launch.py ........ 새 작업 스레드가 비서 자신이 되지 않게 막음
                 ├─ tool_guard.py .......... 셸, 파일, 웹 도구를 정해진 범위로 묶음 (보안 주의사항)
                 ├─ mac_control.py ......... 정해진 Mac 제어 명령만 실행
                 ├─ file_search.py ......... 읽을 수 있는 폴더에서 파일 찾기 (셸 검색 대신)
                 └─ speak.py (Stop 훅) ..... 대답을 다듬어 voice.py로 넘김
                      └─ voice.py .......... ElevenLabs로 말하고, 아바타에 말투를 알림
AssistantAvatar.app ............... talk.state와 speaking.* 파일을 보고 영상을 바꾸고,
                                    caption-*, level-* 파일로 자막과 소리 막대를 그림
LaunchAgent ..................... 12시 아침 브리핑, 6시간마다 크레딧 확인, 로그인 때 아바타 실행
```

비서는 T3 Code 안에서 돌아가는 Claude Code 세션입니다. 비서 전용 공급자 인스턴스가 `--settings`와
`--append-system-prompt-file`로 이 저장소의 설정과 프롬프트를 읽습니다. 소리 내어 읽는 훅은 이
설정에만 들어 있어서, 다른 작업 스레드는 조용히 일합니다.

## 준비물

| 항목 | 설명 |
|---|---|
| Mac | Apple Silicon. macOS 15 이상 권장 (만든 환경은 macOS 27) |
| Homebrew | `brew install python ffmpeg` (Python은 `/opt/homebrew/bin/python3`, `ffplay`와 `ffmpeg` 필요) |
| Xcode Command Line Tools | `xcode-select --install` (앱을 빌드하는 `swiftc`) |
| T3 Code | 데스크톱 앱과 `t3` 명령(기본 위치 `~/.local/bin/t3`) |
| Claude | T3 Code에서 Claude Code 공급자를 쓸 수 있는 Claude 요금제 |
| ElevenLabs | 계정과 API 키. 목소리 복제(Instant Voice Clone)를 하려면 유료 요금제가 필요합니다. 요금과 포함 글자 수는 가입할 때 확인하세요 |
| Google Chrome | 유튜브 정지와 다음 곡 기능에 필요 (기본 브라우저로 쓸 때) |
| Apple Music | 선택. 구독하고 `APPLE_MUSIC="yes"`로 두면 말한 노래를 Apple Music으로 틂 |
| 아바타 영상 9개 | [docs/AVATAR.ko.md](docs/AVATAR.ko.md)의 프롬프트로 직접 만듭니다. 저장소에는 들어 있지 않습니다 |

## 설치

### 1. 저장소 받기

```bash
git clone <이 저장소 주소> ~/t3-voice-assistant
cd ~/t3-voice-assistant
```

어느 폴더에 두어도 됩니다. 설치 후에는 폴더를 옮기지 마세요. 옮겼다면 `./install.sh`를 다시 실행하면 됩니다.

### 2. 아바타와 목소리 만들기

[docs/AVATAR.ko.md](docs/AVATAR.ko.md)를 따라 하면 아래 파일이 준비됩니다.

- `avatar/*.mp4` 9개와 `avatar.png`
- ElevenLabs 복제 목소리(목소리 id를 메모해 두세요)
- 선택: 듣기 신호음 `sounds/cue.caf`

영상이 없어도 설치와 대화는 됩니다. 영상이 준비되기 전에는 아바타 자리에 `avatar.png`나 빈 화면이 보입니다.

### 3. 설정 파일 채우기

```bash
./install.sh            # 처음 실행하면 assistant.conf를 만들고 멈춥니다
open -e assistant.conf    # 아래 값을 채웁니다
```

| 키 | 예시 | 설명 |
|---|---|---|
| `ASSISTANT_NAME_KO`, `ASSISTANT_NAME_EN` | `하나`, `Hana` | 비서 이름. 아바타 이름표(메뉴가 영어일 때는 영어 이름), 스레드 제목, 인식 단어에 쓰임 |
| `USER_NAME_EN` | `Alex` | 영어로 대답할 때 부르는 이름 |
| `USER_CALL_KO` | `민준님` | 한국어로 부르는 호칭 |
| `USER_SHORT_CALL_KO` | `민준님` | 가끔 쓰는 짧은 호칭 (같아도 됨) |
| `ELEVENLABS_VOICE_ID` | `AbCd...` | ElevenLabs > Voices에서 복사한 목소리 id |
| `ELEVENLABS_KEY_MONTHLY_LIMIT` | `100000` | API 키에 걸어 둔 월 한도. 없으면 `0` |
| `T3_BIN` | `$HOME/.local/bin/t3` | `t3` 명령 위치 |
| `ASSISTANT_INSTANCE` | `claudeAgent_voice_assistant` | 5단계에서 만들 인스턴스 id |
| `ASSISTANT_MODEL` | `claude-sonnet-5-5` | 비서가 쓰는 모델 |
| `WORK_INSTANCE`, `WORK_MODEL` | `claudeAgent`, `claude-sonnet-5-5` | 비서가 새 작업 스레드를 만들 때 쓸 인스턴스와 모델 |
| `GREETING` | `부르셨어요?` | 대화를 시작할 때 하는 인사 (호칭 뒤에 붙음) |
| `PHRASE_*` | `알겠어요, 또 불러 주세요!` | 모델 없이 바로 말하는 고정 문구 6개 (한국어·영어 작별, 오류). 페르소나 말투에 맞추세요 |
| `ASSISTANT_READ_FOLDERS` | `$HOME/Documents/Notes` | 선택. 비서가 더 읽을 수 있는 폴더, `:`로 구분 (보안 주의사항 참고). 비우면 이 폴더만 |
| `APPLE_MUSIC` | `no` | Apple Music을 구독하면 `yes`: 말한 노래를 먼저 Apple Music으로 틂. `no`면 유튜브로 틂 |

비서의 성격과 말투는 `persona.md`에 씁니다. 처음 설치하면 `persona.example.md`(다정한 존댓말 비서)가
`persona.md`로 복사되니, [docs/PERSONA.ko.md](docs/PERSONA.ko.md)의 예시를 참고해서 원하는 대로 고치세요.
`persona.md`는 개인 파일이라 GitHub에 올라가지 않습니다. 고친 뒤 `./install.sh`를 다시 실행하면 반영됩니다.
음성 대답, 감정 태그, 도구 사용 같은 공통 규칙은 `templates/assistant-system.md.tmpl`에 있습니다.

### 4. 설치 실행

```bash
./install.sh
```

설치 스크립트는 아래 순서로 진행합니다. 다시 실행해도 안전합니다. 메모장, 인식 단어 목록, 음성 스레드 id는 덮어쓰지 않습니다.

1. 준비물을 확인합니다.
2. 아래 파일을 만듭니다.
   - `assistant-system.md`(프롬프트), `assistant-settings.json`(훅과 권한)
   - `assistant-memory.md`, `vocabulary.txt`, `claude-md-milestone.md`
3. ElevenLabs API 키를 물어서 로그인 키체인에 저장합니다(서비스 이름 `voice-assistant-elevenlabs`). 파일에는 저장하지 않습니다.
4. 자체 서명 인증서 `Voice Assistant Local Signing`을 전용 키체인에 만듭니다. 그 인증서로 `AssistantListen.app`과 `AssistantAvatar.app`을 빌드합니다. 같은 인증서로 서명하기 때문에, 다시 빌드해도 macOS가 같은 앱으로 알아보고 권한을 다시 묻지 않습니다.
5. LaunchAgent 3개를 설치합니다(`local.voice-assistant.morning`, `local.voice-assistant.credit`, `local.voice-assistant.avatar`). 이때 아바타가 화면에 뜹니다.

준비물과 설정 파일만 확인하려면 `./install.sh --check`를 실행하세요.

### 5. T3 Code에 비서 인스턴스 추가

T3 Code 설정에서 Claude 공급자 인스턴스를 하나 더 추가합니다.

- 인스턴스 id: `assistant.conf`의 `ASSISTANT_INSTANCE`와 같게 (예: `claudeAgent_voice_assistant`)
- 표시 이름: `Voice Assistant`
- 실행 인자(launch args): 설치 스크립트가 마지막에 실제 경로로 출력해 줍니다.

```
--settings <저장소>/assistant-settings.json --append-system-prompt-file <저장소>/assistant-system.md
```

설정 화면에서 추가할 수 없다면 T3 Code를 완전히 종료한 뒤 `~/.t3/userdata/settings.json`의
`providerInstances`에 아래 항목을 넣고 다시 켜세요. 파일을 고치기 전에 복사본을 만들어 두세요.

```json
"claudeAgent_voice_assistant": {
  "driver": "claudeAgent",
  "displayName": "Voice Assistant",
  "enabled": true,
  "config": {
    "launchArgs": "--settings /Users/<나>/t3-voice-assistant/assistant-settings.json --append-system-prompt-file /Users/<나>/t3-voice-assistant/assistant-system.md"
  }
}
```

비서는 스레드를 읽고, 메시지를 보내고, Mac 제어 스크립트를 실행해야 합니다. 그래서 비서
스레드는 도구를 확인 없이 쓸 수 있는 권한 모드(T3의 full access)로 실행하는 것을 전제로 합니다.
무언가를 바꾸는 일은 비서가 프롬프트 규칙에 따라 먼저 말로 확인받습니다.

### 6. 비서 스레드 만들기

T3 Code를 켠 상태에서, 비서 스레드를 둘 T3 프로젝트 폴더를 정하고 실행합니다.
이 저장소 폴더를 T3에서 프로젝트로 열어 두고 그 폴더를 지정해도 됩니다.

```bash
tools/create_voice_thread.sh ~/t3-voice-assistant
```

비서 이름으로 새 스레드가 생기고 그 id가 `voice-thread-id`에 저장됩니다. 비서가 첫 인사를 하면 성공입니다.
T3 화면에서 직접 만들어도 됩니다. 비서 인스턴스로 새 스레드를 만든 뒤, 그 스레드 id를 `voice-thread-id`에 한 줄로 적으세요.

프롬프트나 설정을 바꾸면 **새 세션부터** 적용됩니다. 기존 스레드에는 T3에서 맥락 초기화(/clear)를 하거나 새 스레드를 만드세요.

### 7. 단축키

아바타 앱에 단축키 **⌃⌥C**(Control + Option + C)가 들어 있습니다. 아바타가 켜져 있으면 어느 앱에서든 동작하고, 아바타는 로그인할 때 자동으로 켜집니다. 따로 설정할 것은 없습니다. 바꾸거나 끄려면 메뉴 막대 아이콘의 메뉴에서 "단축키"를 고르세요.

⌃⌥Space와 ⌃Space는 피하세요. macOS가 기본으로 입력 소스(한/영) 전환에 쓰고, 시스템 단축키가 앱보다 먼저 받습니다. ⌥Space는 Claude 앱의 빠른 입력처럼 다른 앱이 쓰기도 합니다.

단축키는 아바타 클릭과 같게 동작합니다. 대화를 시작하고, 비서가 말하는 중이면 말만 끊습니다. 비서가 말한 뒤 저절로 열린 마이크에 아직 아무 말도 안 했으면 듣기를 새로 시작하고, 그 밖에는 대화를 끝냅니다.

원하면 macOS 단축어 앱으로도 시작할 수 있습니다(예: Siri로 실행). "셸 스크립트 실행" 동작(셸 `bash`, 입력 없음)에 `/bin/bash /Users/<나>/t3-voice-assistant/talk.sh`를 넣고, 단축어 설정 > 고급에서 "스크립트 실행 허용"을 켜세요. 내장 단축키와 같은 키는 지정하지 마세요.

### 8. 다른 스레드의 마일스톤 보고 켜기 (선택)

설치가 만든 `claude-md-milestone.md` 내용을 `~/.claude/CLAUDE.md`에 붙여 넣으세요. 그러면 다른
Claude 스레드가 기능 완성, 테스트 통과, PR, 배포, 막힘 같은 큰 고비에서 비서에게 한 줄을 보내고,
비서가 그걸 말로 전합니다.

## 처음 켤 때 허용할 권한

처음 몇 번은 macOS가 권한을 묻습니다. 모두 **허용**을 누르세요.

| 언제 | 무엇을 | 누가 묻나 |
|---|---|---|
| 첫 대화 | 마이크, 음성 인식 | AssistantListen |
| 단축어 앱으로 처음 실행할 때 (선택) | 스크립트 실행 | 단축어 |
| 음악을 틀었을 때, 대화를 시작할 때, 재생 중 카드 | Music, Google Chrome, System Events 제어 | T3 Code, 단축어, AssistantAvatar |
| 유튜브 정지와 다음 곡, 재생 중 카드의 유튜브 | Chrome 메뉴 보기 > 개발자 > Apple Events의 JavaScript 허용 | (직접 켜기) |

실수로 "허용 안 함"을 눌렀다면 시스템 설정 > 개인정보 보호 및 보안 > 자동화(또는 마이크, 음성 인식)에서 다시 켤 수 있습니다.

## 사용법

단축키를 누르거나 아바타를 클릭한 뒤 말합니다.

- "지금 돌아가는 스레드 몇 개야?"
- "블로그 스레드 뭐 하고 있어?"
- "블로그 스레드에 '오늘 한 일 정리해 줘'라고 보내 줘": 비서가 "보낼까?"라고 확인합니다. "응"이라고 해야 보냅니다.
- "아이유 노래 틀어줘", "잠깐 멈춰", "다음 곡", "다시 틀어", "이거 무슨 노래야?"
- "볼륨 조금 줄여줘", "볼륨 30으로", "음소거"
- "음악 소리만 줄여줘": Mac 전체가 아니라 음악 자체 볼륨
- "메모 앱 열어줘", "사파리 종료해 줘": 종료는 먼저 물어봅니다.
- 끝낼 때: "오늘은 여기까지", "그만 얘기하자", "잘 자"

말이 없거나 대화가 30번 오가면 저절로 끝납니다. 다른 스레드의 대답을 비서가 읽어 준 뒤에는 잠깐 다시 듣습니다.

**감정과 아바타**: 대답의 첫 감정 태그가 말하는 영상을 정합니다.

| 상황 | 첫 태그 | 영상 |
|---|---|---|
| 좋은 소식, 칭찬 | `[cheerfully]`, `[excited]` | speaking_happy |
| 나쁜 일이 생김(실패, 서버 다운) | `[sadly]` | speaking_sad |
| 비서 자신의 실수 사과 | `[apologetically]` | speaking_sad |
| 기분만 처짐(피곤, 힘든 하루) | `[gently]`, `[sympathetically]` | speaking_comfort |
| 장난, 농담 | `[playfully]`, `[teasing]` | speaking_playful |
| 그 밖의 대답 | `[calmly]`, `[warmly]`, 없음 | speaking |

## 설정 바꾸기

| 바꾸고 싶은 것 | 고칠 곳 | 반영 방법 |
|---|---|---|
| 호칭, 인사, 고정 문구, 목소리 id, 키 한도 | `assistant.conf` | `./install.sh` 다시 실행, 비서는 새 세션부터 |
| 이름 | `assistant.conf`의 `ASSISTANT_NAME_*` | `./install.sh` 다시 실행, 아바타는 닫았다 다시 열기 |
| 성격, 말투 | `persona.md` | `./install.sh` 다시 실행, 새 세션부터 |
| 공통 규칙 | `templates/assistant-system.md.tmpl` | `./install.sh` 다시 실행, 새 세션부터 |
| 잘 알아들었으면 하는 단어 | `vocabulary.txt` | 다음 대화부터 |
| 아바타 영상 | `avatar/*.mp4` (`tools/prepare_clip.sh`) | 아바타 오른쪽 클릭 > 닫기 후 다시 열기 |
| 듣기 신호음 | `sounds/cue.caf` | 다음 대화부터 |
| 밤 조용한 시간 | `speak.py`의 `QUIET_START_HOUR`, `QUIET_END_HOUR` | 바로 |

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| 비서가 말을 안 함 | `speak.log` 확인. 비서 인스턴스의 실행 인자에 `--settings .../assistant-settings.json`이 있는지 |
| 기계음(Yuna)으로 말함 | `./install.sh`로 API 키 저장 여부, `ELEVENLABS_VOICE_ID`, 아바타 메뉴의 남은 글자 |
| 단축키를 눌러도 반응이 없음 | 메뉴 막대 메뉴의 "단축키" 항목(켜져 있는지, "등록 안 됨"은 아닌지). 같은 키를 쓰는 다른 앱이나 시스템 단축키(⌃⌥Space는 한/영 전환). `voice.log`의 마지막 줄, 마이크와 음성 인식 권한 |
| 비서가 엉뚱한 스레드로 보냄 | `voice-thread-id`가 비서 스레드 id인지 |
| 바꾼 규칙이 안 먹음 | 새 세션에서 시험했는지 (기존 세션은 예전 프롬프트를 기억함) |
| 유튜브 정지가 안 됨 | Chrome의 "Apple Events의 JavaScript 허용", 자동화 권한 |
| 노래 대신 검색 결과만 열림 | 유튜브가 다른 형식의 페이지를 준 경우. `youtube-miss.html`에 받은 페이지가 남음 |
| 재생 중 카드가 안 보임 | 메뉴의 "재생 중 보이기", AssistantAvatar의 Chrome·Music 자동화 권한, Chrome의 "Apple Events의 JavaScript 허용"(유튜브) |
| 재생 중 카드가 엉뚱한 곳에 있음 | 카드를 더블클릭하거나 메뉴에서 "오른쪽 위로 옮기기" |
| 말한 노래가 Apple Music이 아니라 유튜브로 나옴 | `assistant.conf`의 `APPLE_MUSIC="yes"`, 그다음 `./install.sh`와 새 세션. Apple Music에 없는 곡은 그래도 유튜브로 감 |
| 앱을 다시 빌드했더니 권한을 또 물음 | `./make_signing_identity.sh` 실행 여부 (서명 인증서가 없으면 임시 서명으로 빌드됨) |

로그(`voice.log`, `speak.log`)에는 상태와 길이만 남고, 주고받은 말의 내용은 남지 않습니다.

## 제거

```bash
./uninstall.sh          # LaunchAgent와 아바타
./uninstall.sh --all    # 위와 함께 ElevenLabs 키와 서명 키체인까지
```

T3 Code의 비서 인스턴스(단축어 앱으로 단축어를 만들었다면 그것도)는 직접 지우고, 마지막으로 저장소 폴더를 지우세요.

## 파일 안내

| 파일 | 역할 |
|---|---|
| `talk.sh` | 대화 한 번 진행. 인사, 듣기, 보내기 반복, 음악 소리 줄이기 |
| `say_to_assistant.sh` | 받아쓴 말을 비서 스레드로 보내고 대답이 끝날 때까지 대기 |
| `assistant_listen.swift` | 창 없는 듣기 앱 (기기 안 한국어·영어 인식, 침묵 감지) |
| `assistant_avatar.swift` | 떠 있는 영상 아바타 |
| `avatar_captions.swift`, `avatar_meter.swift` | 아바타의 자막 말풍선과 소리 막대 |
| `avatar_menu.swift`, `avatar_hotkey.swift` | 메뉴 막대 아이콘과 메뉴, 내장 단축키 |
| `avatar_nowplaying.swift`, `avatar_nowplaying_card.swift` | Chrome과 Music 앱에서 무엇이 나오는지 확인, 버튼과 볼륨 슬라이더가 있는 재생 중 카드 |
| `listen_transcript.swift` | 쉬는 사이에도 한 말을 이어서 모아 두고(인식기는 쉴 때마다 처음부터 다시 받아씀), 한국어와 영어 중 하나를 고름 |
| `listen_channel.swift` | 한 언어의 인식기 하나, 그리고 다른 언어가 다시 들을 녹음 |
| `file_search.py` | 비서가 셸 검색 대신 쓰는 정해진 파일 검색 명령 (읽을 수 있는 폴더만, 비밀 파일 제외) |
| `speak.py` | 비서 대답을 소리용으로 다듬는 Stop 훅. 밤에는 아침 브리핑으로 모음 |
| `voice.py` | ElevenLabs 스트리밍 재생, Yuna 대체 목소리, 고정 문구 캐시, 사용량 |
| `memory_hook.py` | 새 세션에 기억 메모 전달 |
| `guard_launch.py` | 비서가 만드는 새 스레드가 비서 자신이 되지 않게 막는 훅 |
| `tool_guard.py` | 비서가 허용 목록의 도구만, 정해진 범위 안에서 쓰게 하는 훅 (보안 주의사항 참고) |
| `mac_control.py` | 볼륨, 유튜브, Music, 앱 제어 (정해진 명령만) |
| `apple_music.py` | Apple Music 카탈로그에서 곡을 찾아(Apple 공개 검색) Music 앱에서 틂 |
| `music_sources.py` | Chrome과 Music 앱 사이에서 음악을 한 곳에서만 나오게 하기, `playing` 명령 |
| `credit_alert.py` | ElevenLabs 사용량 80% 알림 |
| `morning_digest.sh` | 12시 아침 브리핑 |
| `install.sh`, `uninstall.sh` | 설치와 제거 |
| `make_signing_identity.sh`, `sign_app.sh`, `signing_env.sh` | 고정 서명 |
| `assistant_config.py`, `assistant.conf.example` | 개인 설정 읽기와 예시 |
| `persona.example.md` | 기본 페르소나 (설치 때 `persona.md`로 복사) |
| `templates/` | 프롬프트, 설정, LaunchAgent, CLAUDE.md 조각의 원본 |
| `tools/` | 영상 변환, 목소리 샘플, 비서 스레드 만들기, 템플릿 채우기 |
| `tests/`, `run_tests.sh` | 테스트 (`./run_tests.sh`) |

## 보안 주의사항

### 이렇게 지킵니다

- **비밀값은 키체인에만 둡니다.** ElevenLabs API 키와 서명 키체인 비밀번호는 macOS 키체인에만 저장됩니다. 설치하거나 빌드할 때도 비밀값을 명령 인자로 넘기지 않고 표준 입력으로만 넘겨서, 다른 프로그램이 프로세스 목록에서 볼 수 없습니다. 개인 파일(`assistant.conf`, `persona.md`, 메모장, 로그)은 `.gitignore`로 저장소에 올라가지 않습니다.
- **비서의 도구를 코드로 묶습니다** (`tool_guard.py`). 비서는 다른 스레드의 내용을 읽기 때문에, 그 안에 비서를 속이려는 숨은 지시(프롬프트 인젝션)가 섞여 들어올 수 있습니다. 그래서 프롬프트 규칙과 별도로 훅이 모든 도구 호출을 허용 목록과 대조합니다. 목록에 없는 도구는 나중에 Claude Code나 T3 Code에 새로 생긴 도구까지 모두 막힙니다.
  - T3 Code 도구는 스레드 목록, 읽기, 검색, 메시지 보내기, 새 스레드 시작, 기다리기, 멈추기만 됩니다. 프로젝트 삭제, 워크트리 조작, 다른 기기 연결, 예약 작업, 작업 위임은 막힙니다.
  - 셸 명령은 `mac_control.py`와 `file_search.py`(읽을 수 있는 폴더에서 파일 찾기, 비밀 파일은 제외) 호출만 됩니다. 명령 잇기(`;`, `&&`, `|`), 리다이렉트, 치환(`$`, 백틱)은 막힙니다.
  - 파일 쓰기는 메모장(`assistant-memory.md`)만 됩니다. 파일 읽기와 검색은 저장소 폴더, Claude Code가 이 세션의 도구 결과를 저장한 곳(긴 스레드 내용), `ASSISTANT_READ_FOLDERS`에 적은 폴더 안에서만 됩니다. 심볼릭 링크나 `..`로 빠져나가는 경로도 막힙니다.
  - 비밀값처럼 보이는 파일(`.env`, `*.pem`, `*.key`, `id_rsa`, 이름에 `credential`이나 `secret`이 든 파일)은 어디에 있든 읽지 않습니다. 추가한 폴더에서는 검색으로 해당 파일 목록만 볼 수 있고, 폴더 전체에서 일치하는 줄을 뽑아 오지는 못하게 해서 키가 딸려 나오지 않게 합니다.
  - 웹 접근(WebFetch, WebSearch), 하위 에이전트, 스킬은 쓸 수 없습니다.
- **Mac 제어 입력은 코드에 섞이지 않습니다.** 곡 이름과 앱 이름은 AppleScript에 값으로만 전달되고, 앱 이름에 경로나 옵션이 들어오면 거부합니다. T3 Code와 비서 자신의 앱은 종료할 수 없습니다.
- **로그에는 대화 내용이 남지 않습니다.** 상태와 길이만 기록합니다. 자막을 위해 말은 말하는 동안에만 `caption-*.txt`(나만 읽을 수 있는 파일)에 적었다가 지우고, 소리 막대는 소리 크기 숫자만 읽습니다.

### 남아 있는 위험과 주의할 점

1. **메시지 보내기와 새 스레드 시작은 여전히 됩니다.** 비서는 다른 스레드에 메시지를 보내고 새 스레드를 시작할 수 있습니다. 실행 전에 말로 확인받는 것은 프롬프트 규칙이라 코드로 강제되지 않습니다. 비서가 "보낼까?"라고 물으면 보낼 내용을 끝까지 듣고 답하세요. 메시지를 받은 작업 스레드는 그 스레드의 권한으로 일하므로, 작업 스레드의 권한 모드는 필요한 만큼만 주세요.
2. **음성 확인은 누구 목소리인지 구별하지 못합니다.** 대화가 열려 있는 동안 옆 사람이나 TV 소리도 "응"으로 들릴 수 있습니다. 여러 사람이 있는 곳에서는 대화를 열어 두지 마세요.
3. **대화 내용은 외부 서비스로 갑니다.** 음성 인식만 Mac 안에서 처리합니다.
   - 말한 내용, 읽은 스레드 내용, 메모장 → Anthropic(Claude)
   - 비서의 대답 문장 → ElevenLabs(목소리 만들기)
   - 노래 검색어 → YouTube, `APPLE_MUSIC="yes"`면 Apple의 iTunes 검색에도
   각 회사의 개인정보 처리 방침이 적용됩니다. 비밀번호, 계좌, 건강처럼 민감한 내용은 비서에게 말하지 마세요.
4. **메모장은 암호화되지 않습니다.** `assistant-memory.md`는 Mac에 일반 파일로 저장됩니다. 민감한 내용은 적지 않도록 규칙이 있지만, 모델이 따르는 규칙입니다. 가끔 내용을 확인하세요.
5. **서명 키는 같은 macOS 계정의 프로그램이 쓸 수 있습니다.** 내 계정에서 악성 프로그램이 돌고 있다면 듣기 앱인 척 서명할 수 있습니다. 여러 사람이 함께 쓰는 macOS 계정에는 설치하지 마세요.
6. **비서 스레드는 모든 권한(full access)으로 돌아갑니다.** 비서를 묶는 것은 위 훅입니다. 훅을 끄거나 `assistant-settings.json`의 훅 목록을 고치면 보호도 사라집니다. 템플릿을 고칠 때는 `tests/`의 테스트를 함께 돌리세요(`./run_tests.sh`).
7. **`ASSISTANT_READ_FOLDERS`로 연 폴더는 읽힐 수 있습니다.** 비서가 그 폴더의 파일을 읽으면, 읽은 다른 내용과 마찬가지로 Anthropic으로 전송됩니다. 비밀값처럼 보이는 이름은 막지만 다른 민감한 문서까지 막지는 못하니, 공유해도 괜찮은 폴더만 적으세요.
8. **노래를 틀 때 YouTube 검색 페이지를 읽습니다.** 바로 재생하기 위해 `mac_control.py`가 말한 검색어로 YouTube 검색 결과 페이지를 받아 첫 영상을 고릅니다. YouTube 이용약관은 서비스에 자동화된 방식으로 접근하는 것을 허용하지 않으므로, 이 기능은 각자 판단해서 쓰세요. 내 Mac에서 요청할 때마다 검색어만 한 번 보냅니다. 원하지 않으면 YouTube로 노래를 틀어 달라고 하지 않거나, YouTube Data API를 쓰도록 바꾸세요.
9. **쓸 권리가 있는 목소리만 복제하세요.** ElevenLabs는 본인 목소리나 주인이 동의한 목소리만 복제하도록 합니다. 이 안내는 직접 만든 아바타 영상의 목소리를 복제합니다. 실제 사람의 목소리를 동의 없이 복제하지 마세요.
10. **업데이트는 직접 확인하고 받으세요.** 이 저장소를 고친 버전을 받을 때는 훅과 설정 템플릿이 어떻게 바뀌었는지 먼저 보세요.

## 라이선스와 고지

이 프로젝트는 [MIT 라이선스](LICENSE)를 따릅니다. 개인이든 회사든 자유롭게 쓰고, 고치고, 다시 배포하고, 팔 수 있습니다.
단 하나의 조건은 복사본이나 고친 버전에 `LICENSE` 파일의 저작권 표시(`Copyright (c) 2026 wonkyjunky`)와 라이선스 문구를 그대로 남기는 것입니다.

고쳐서 배포한다면 README에 원본 저장소 링크도 남겨 주세요. 라이선스가 요구하는 것은 아니고 부탁입니다.

- 이 프로젝트는 개인 프로젝트입니다. T3 Code, Anthropic(Claude), ElevenLabs, Google(YouTube, Chrome), Apple과 관계가 없고, 이 회사들이 만들거나 보증한 것이 아닙니다. 각 이름과 상표는 해당 회사의 것입니다.
- ElevenLabs, Claude, T3 Code는 각 서비스의 이용약관과 요금제에 따라 직접 가입해서 씁니다. 비용은 쓰는 사람이 냅니다.
- 목소리 복제와 아바타는 본인이 권리를 가진 목소리와 얼굴, 또는 직접 만든 가상의 인물로만 만드세요. 다른 사람의 목소리나 얼굴을 허락 없이 쓰지 마세요.
- `youtube play`는 유튜브 검색 결과 페이지를 읽어 첫 영상을 찾습니다. 유튜브 이용약관과 사는 곳의 규정을 확인하고 각자 판단해서 쓰세요. 쓰지 않으려면 페르소나나 프롬프트에서 `youtube search`만 쓰게 하면 됩니다.
- 이 소프트웨어는 있는 그대로 제공되며, 사용으로 생긴 문제에 대해 저작권자는 책임지지 않습니다(라이선스 본문 참고).
