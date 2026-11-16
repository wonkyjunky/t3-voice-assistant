[English](PERSONAS.md) | **한국어**

# 비서 여러 명 두기

기본 비서(`assistant.conf`와 `persona.md`로 만든 비서) 말고도, 이름, 성격, 목소리, 아바타, 스레드가
각각 다른 비서를 더 둘 수 있고, 아바타 메뉴의 "비서(Assistant)"에서 바꿀 수 있습니다. 기억 메모는
함께 쓰므로, 한 비서에게 말한 것을 다른 비서도 압니다.

## 파일

추가 비서는 `personas/` 안의 폴더 하나입니다(폴더 이름이 그 비서의 id, 예: `second`).

| 파일 | 내용 |
|---|---|
| `personas/second/persona.conf` | `assistant.conf`와 다른 값만 적는 `KEY="value"` 줄. 나머지는 `assistant.conf`를 따름 |
| `personas/second/persona.md` | 성격과 말투(`persona.md`와 같은 형식). 없으면 `persona.example.md`를 복사 |
| `personas/second/avatar/*.mp4`, `avatar.png` | 영상과 사진. [AVATAR.ko.md](AVATAR.ko.md)대로 만듦. 없으면 원 안에 이름이 보임 |
| `personas/second/voice_cache/`, `voice-thread-id` | 자동으로 만들어짐: 인사말 음성과 그 비서의 스레드 |

`personas/`와 `persona` 파일(지금 고른 비서)은 개인 파일이라 GitHub에 올라가지 않습니다.

`persona.conf`에는 보통 이런 값을 적습니다.

```
ASSISTANT_NAME_KO="은서"
ASSISTANT_NAME_EN="Eunseo"
ELEVENLABS_VOICE_ID="..."            # 그 비서의 목소리 (""면 macOS Yuna 목소리)
ASSISTANT_INSTANCE="claudeAgent_voice_assistant_second"   # 그 비서의 T3 인스턴스
GREETING="부르셨어요?"                # 선택: 그 비서만의 인사말과 호칭
USER_CALL_KO="민준오빠"
```

## 만드는 순서

1. `personas/second/persona.conf`를 만듭니다(성격을 다르게 하려면 `persona.md`도).
2. `./install.sh`를 실행합니다. 그 폴더에 비서 프롬프트(`assistant-system.md`)와 이름
   (`assistant-name.txt`)을 만들고, 다음 두 단계를 알려 줍니다.
3. T3 Code에 `ASSISTANT_INSTANCE`에 적은 id로 공급자 인스턴스를 추가하고, 실행 인자는 이렇게 넣습니다.

   ```
   --settings <저장소>/assistant-settings.json --append-system-prompt-file <저장소>/personas/second/assistant-system.md
   ```

4. 스레드를 만듭니다: `tools/create_voice_thread.sh <T3 프로젝트 폴더> second`
5. 아바타 메뉴에서 비서 > 그 이름을 고릅니다. 얼굴, 이름표, 목소리, 인사말, 듣기 앱이 기다리는 이름,
   메시지를 보낼 스레드가 한 번에 바뀝니다.

`persona.conf`, `persona.md`, 공통 규칙을 고친 뒤에는 `./install.sh`를 다시 실행하세요. 비서는 새
세션을 시작할 때 프롬프트를 읽습니다.
