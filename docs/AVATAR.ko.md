[English](AVATAR.md) | **한국어**

# 아바타, 목소리, 신호음 만들기

비서의 영상 아바타와 목소리는 저장소에 들어 있지 않습니다. 이 문서의 프롬프트로 직접 만들어 넣으세요.
순서는 이렇습니다.

1. 이미지 생성 도구로 기준 얼굴 이미지 한 장을 만듭니다.
2. 그 이미지를 첫 장면으로 해서, 이미지로 영상을 만드는 도구로 상태별 영상 9개를 만듭니다.
3. `tools/prepare_clip.sh`로 앱이 쓰는 규격에 맞춥니다.
4. 영상 속 목소리로 ElevenLabs 목소리를 복제합니다.
5. 선택: 듣기 신호음을 만듭니다.

어떤 도구를 써도 됩니다. 이미지는 아무 이미지 생성 도구, 영상은 "이미지로 영상 만들기"와 가능하면
"소리(대사)까지 만들기"를 지원하는 도구가 좋습니다. 대사가 있는 영상을 만들면 그 목소리로 4단계 복제를 할 수 있습니다.

> 실존 인물(연예인, 지인 등)을 닮게 만들지 마세요. 처음부터 새로 만든 가상의 인물을 쓰세요.

## 앱이 기대하는 파일

| 파일 | 언제 보이나 | 길이 |
|---|---|---|
| `avatar/idle.mp4` | 평소, 대화 시작 직후 | 10초, 반복 재생 |
| `avatar/greeting.mp4` | 대화를 시작하며 인사할 때 (인사 목소리와 함께 시작) | 4초 |
| `avatar/listening.mp4` | 듣는 동안 | 10초, 반복 |
| `avatar/thinking.mp4` | 대답을 기다리는 동안 | 10초, 반복 |
| `avatar/speaking.mp4` | 평소 말투로 말할 때 | 10초, 반복 |
| `avatar/speaking_happy.mp4` | 기쁘게 말할 때 (`[cheerfully]`, `[excited]`) | 10초, 반복 |
| `avatar/speaking_sad.mp4` | 슬프거나 미안하게 말할 때 (`[sadly]`, `[apologetically]`) | 10초, 반복 |
| `avatar/speaking_playful.mp4` | 장난스럽게 말할 때 (`[playfully]`, `[teasing]`) | 10초, 반복 |
| `avatar/speaking_comfort.mp4` | 다정하게 위로할 때 (`[gently]`, `[sympathetically]`) | 10초, 반복 |
| `avatar.png` | 영상이 없을 때 대신 보이는 사진 | 360x360 |

규격은 모두 360x360 정사각형, 초당 24프레임, H.264, 소리 없음입니다. 원본은 어떤 크기로 만들어도
`tools/prepare_clip.sh`가 맞춰 줍니다.

## 모든 영상에 공통으로 지킬 것

아바타는 상태가 바뀔 때마다 영상을 바꿔 틉니다. 영상끼리 얼굴 위치나 크기가 다르면 화면에서
얼굴이 뚝뚝 튀어 보입니다. 그래서 아래를 지켜 주세요.

- 9개 모두 **같은 기준 이미지를 첫 장면**으로 씁니다.
- 카메라를 고정합니다. 줌, 이동, 장면 전환을 넣지 않습니다.
- 얼굴이 화면 가운데에 오게 하고, 어깨 위까지만 나오게 합니다. 손이 화면 밖으로 크게 나가지 않게 합니다.
- 배경은 단순하게, 9개 모두 같게 합니다.
- 반복 재생되므로, 끝 장면이 첫 장면과 비슷한 자세로 돌아오게 합니다.
- 글자, 자막, 워터마크가 들어가지 않게 합니다.

## 1단계: 기준 얼굴 이미지

정사각형(1:1)으로 만듭니다. 마음에 드는 얼굴이 나올 때까지 여러 번 만들어 보세요.

```
Square 1:1 portrait of an original fictional Korean woman in her mid twenties, friendly and bright,
looking straight into the camera with a soft natural smile, mouth closed. Head and shoulders,
face centered and filling about half of the frame, eyes at one third from the top.
Soft even studio light, plain softly blurred warm beige background. Natural makeup, shoulder length
dark brown hair, simple cream knit top. Photorealistic, sharp focus on the eyes, calm neutral pose,
hands out of frame. No text, no watermark, not resembling any real person.
```

이 이미지를 `reference.png`로 저장해 두고, 아래 모든 영상의 첫 장면(시작 이미지)으로 씁니다.

## 2단계: 상태별 영상

아래 대사는 예시 페르소나(다정한 존댓말)에 맞춘 것입니다. 내 비서의 말투(`persona.md`)에 맞게 바꿔 쓰세요.
영상 도구에 `reference.png`를 시작 이미지로 넣고, 아래 프롬프트를 하나씩 넣어 만듭니다.
도구가 대사(소리) 생성을 지원하면, `Says in Korean:` 뒤의 대사로 말하게 하세요. 그 목소리가 4단계의 복제 재료가 됩니다.
모든 프롬프트 끝에 공통 문장을 붙입니다.

공통 문장:

```
Static locked-off camera, same framing, same background and lighting as the start image, face stays
centered, no zoom, no cuts, no text. The last frame returns to the same pose as the first frame so the
clip loops smoothly.
```

### idle (10초)

```
She rests calmly, breathing gently, blinking naturally, a faint relaxed smile, mouth closed,
tiny natural head movements. Silent.
```

### greeting (4초)

```
She brightens with a warm happy smile, raises her eyebrows slightly and greets the viewer with
a small nod. Says in Korean, cheerful and warm: "민준님, 부르셨어요?"
```

대사는 `assistant.conf`의 호칭과 인사말을 이은 문장과 같게 바꾸세요(예: `민준님, 부르셨어요?`).

### listening (10초)

```
She listens attentively to someone speaking off camera, eyes on the camera, small slow nods,
slight head tilt, interested expression, mouth closed. Silent.
```

### thinking (10초)

```
She thinks about an answer, eyes glance up and to the side, then back to the camera, lips pressed
softly together, a small thoughtful hum without opening the mouth. Silent.
```

### speaking (10초)

```
She talks naturally to the viewer in a calm friendly tone, clear natural mouth movements, small
expressive eyebrow movements, occasional blinks. Says in Korean, calm and warm:
"네, 확인해 봤어요. 지금 돌아가는 스레드는 두 개고, 둘 다 잘 진행되고 있어요."
```

### speaking_happy (10초)

```
She talks happily and excitedly, big genuine smile while speaking, bright eyes, lively natural mouth
movements. Says in Korean, cheerful and excited:
"우와, 진짜 잘됐어요! 테스트가 전부 통과했대요. 오늘 정말 최고예요!"
```

### speaking_sad (10초)

```
She talks with a sad, sorry expression, eyebrows drawn together and down, softer slower mouth
movements, eyes slightly lowered then back to the camera. Says in Korean, sad and apologetic:
"어떡해요, 서버가 멈췄대요. 죄송해요, 제가 더 빨리 알려 드렸어야 했는데."
```

### speaking_playful (10초)

```
She talks in a playful teasing way, mischievous smirk, one quick wink, lively eyebrows, natural mouth
movements. Says in Korean, playful and teasing:
"에이, 또 밤새시려는 거죠? 제가 다 알아요. 오늘은 일찍 주무시기로 약속해요."
```

### speaking_comfort (10초)

```
She talks gently and reassuringly, soft warm eyes, a tender small smile, slow calm mouth movements,
a slight comforting head tilt. Says in Korean, gentle and comforting:
"오늘 많이 힘드셨죠. 괜찮아요, 천천히 하셔도 돼요. 제가 옆에 있을게요."
```

영상 도구가 10초보다 짧게만 만든다면 만들 수 있는 가장 긴 길이로 만드세요. 짧아도 반복 재생됩니다.
위로 영상은 처음 몇 초가 걱정스러운 표정으로 시작하기 쉬우니, 첫 장면부터 다정한 얼굴인지 확인하세요.

## 3단계: 앱 규격으로 맞추기

원본 영상(소리 있는 것)은 4단계에서 쓰니 지우지 말고 `raw/` 같은 폴더에 따로 두세요.
저장소 폴더에서 영상마다 실행합니다.

```bash
tools/prepare_clip.sh raw/idle.mp4 idle
tools/prepare_clip.sh raw/greeting.mp4 greeting 4
tools/prepare_clip.sh raw/listening.mp4 listening
tools/prepare_clip.sh raw/thinking.mp4 thinking
tools/prepare_clip.sh raw/speaking.mp4 speaking
tools/prepare_clip.sh raw/speaking_happy.mp4 speaking_happy
tools/prepare_clip.sh raw/speaking_sad.mp4 speaking_sad
tools/prepare_clip.sh raw/speaking_playful.mp4 speaking_playful
tools/prepare_clip.sh raw/speaking_comfort.mp4 speaking_comfort
```

- 기본값은 가운데에서 가장 큰 정사각형을 잘라 360x360으로 줄입니다.
- 세로 영상이라 얼굴이 위쪽에 있다면 네 번째 인자로 자를 위치를 정합니다. 예: `"crop=iw:iw:0:ih*0.1"`
- `idle`을 처리하면 첫 장면으로 `avatar.png`도 만들어집니다.
- 바꾼 영상은 아바타를 닫았다 다시 열면 보입니다. 아바타를 오른쪽 클릭해서 "아바타 닫기"를 누르고, 다음 대화를 시작하면 다시 뜹니다.

## 4단계: 목소리 복제 (ElevenLabs)

> 쓸 권리가 있는 목소리만 복제하세요. 2단계에서 직접 만든 영상의 목소리, 내 목소리, 또는 주인이 동의한 목소리만 됩니다. ElevenLabs 약관도 이를 요구하며, 실제 사람의 목소리를 동의 없이 복제하면 안 됩니다.

1. 대사가 있는 원본 영상들에서 목소리만 모읍니다. 깨끗한 말소리 1분 정도면 충분합니다.

   ```bash
   tools/voice_sample.sh voice_sample.wav raw/greeting.mp4 raw/speaking.mp4 raw/speaking_happy.mp4 \
     raw/speaking_sad.mp4 raw/speaking_playful.mp4 raw/speaking_comfort.mp4
   ```

2. ElevenLabs 웹에서 Voices > Add a new voice > Instant Voice Clone을 고르고, `voice_sample.wav`를 올린 뒤 이름(예: 비서 이름 + Clone)을 붙입니다.
3. 만든 목소리의 voice id를 복사해서 `assistant.conf`의 `ELEVENLABS_VOICE_ID`에 넣습니다.
4. API 키(Profile > API Keys)는 `./install.sh`를 실행할 때 붙여 넣습니다. 키에 월 한도를 걸었다면 그 값을 `ELEVENLABS_KEY_MONTHLY_LIMIT`에 적습니다.

ElevenLabs 화면의 메뉴 이름은 바뀔 수 있습니다. 위 이름이 보이지 않으면 Voices 화면에서 목소리 추가 메뉴를 찾으세요.
복제 대신 ElevenLabs 목소리 목록에서 마음에 드는 한국어 목소리를 골라 그 id를 써도 됩니다.
비서는 `eleven_v4` 모델로 말하고, `[cheerfully]` 같은 감정 태그를 연기합니다.

### 인사말을 영상 원본 녹음으로 쓰기 (선택)

기본적으로 인사말은 처음 한 번 ElevenLabs로 만들어 `voice_cache/`에 저장해 두고 다시 씁니다.
greeting 영상의 원래 목소리를 그대로 쓰고 싶다면, 대사가 인사말과 똑같은지 확인한 뒤 실행하세요.

```bash
mkdir -p voice_cache
/opt/homebrew/bin/ffmpeg -i raw/greeting.mp4 -vn -c:a libmp3lame -q:a 2 voice_cache/greeting.mp3
printf '%s' '[cheerfully] 민준님, 부르셨어요?' > voice_cache/greeting.txt
```

`greeting.txt`의 내용은 `[cheerfully] ` 뒤에 `USER_CALL_KO`, 쉼표와 공백, `GREETING`을 이은 문장과 글자 하나까지 같아야 합니다.
다르면 앱이 인사말을 ElevenLabs로 새로 만듭니다.

## 5단계: 듣기 신호음 (선택)

듣기가 시작될 때 나는 짧은 소리입니다. 없으면 macOS 기본 소리를 씁니다.
ElevenLabs의 Sound Effects에서 만들 수 있습니다.

```
A short soft futuristic AI assistant chime, waking up to listen, gentle rising tone, under one second
```

받은 파일을 변환해서 넣습니다.

```bash
afconvert -f caff -d LEI16 cue.mp3 sounds/cue.caf
```

신호음이 너무 크게 들리면 소리를 줄인 뒤 다시 변환하세요. 예: `/opt/homebrew/bin/ffmpeg -i cue.mp3 -af volume=-6dB cue_quiet.mp3`
