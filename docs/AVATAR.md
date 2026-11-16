**English** | [한국어](AVATAR.ko.md)

# Making the avatar, voice and cue sound

The assistant's video avatar and voice are not in this repository. Make them with the prompts in this
document. The steps:

1. Make one reference face image with an image generator.
2. Using that image as the first frame, make the 9 state clips with an image-to-video tool.
3. Fit them to the app's format with `tools/prepare_clip.sh`.
4. Clone an ElevenLabs voice from the speech in the clips.
5. Optional: make the listening cue sound.

Any tools work. For images, any image generator; for video, a tool with "image to video" and, ideally,
"generate speech audio". Clips with spoken lines let you do the voice clone in step 4 from the same voice.

> Do not make the face resemble a real person (a celebrity, someone you know). Use a fictional character you create from scratch.

## Files the app expects

| File | Shown when | Length |
|---|---|---|
| `avatar/idle.mp4` | Idle, right after a conversation starts | 10 s, loops |
| `avatar/greeting.mp4` | Greeting at the start of a conversation (starts with the greeting voice) | 4 s |
| `avatar/listening.mp4` | While listening | 10 s, loops |
| `avatar/thinking.mp4` | While waiting for the reply | 10 s, loops |
| `avatar/speaking.mp4` | Speaking in a normal tone | 10 s, loops |
| `avatar/speaking_happy.mp4` | Speaking happily (`[cheerfully]`, `[excited]`) | 10 s, loops |
| `avatar/speaking_sad.mp4` | Speaking sadly or sorry (`[sadly]`, `[apologetically]`) | 10 s, loops |
| `avatar/speaking_playful.mp4` | Speaking playfully (`[playfully]`, `[teasing]`) | 10 s, loops |
| `avatar/speaking_comfort.mp4` | Speaking gently to comfort (`[gently]`, `[sympathetically]`) | 10 s, loops |
| `avatar.png` | The still shown when a clip is missing | 360x360 |

All clips are 360x360 squares, 24 frames per second, H.264, without sound. The originals can be any
size; `tools/prepare_clip.sh` converts them.

## Rules for every clip

The avatar switches clips whenever the state changes. If the face moves to a different position or size
between clips, it visibly jumps on screen. So:

- Use **the same reference image as the first frame** for all 9 clips.
- Keep the camera locked: no zoom, no movement, no cuts.
- Keep the face centered, head and shoulders only. Keep hands from moving far out of frame.
- Keep the background plain and the same in all 9.
- Clips loop, so let the last frame return to a pose close to the first.
- No text, subtitles or watermarks.

## Step 1: Reference face image

Make it square (1:1). Generate until you like the face.

```
Square 1:1 portrait of an original fictional Korean woman in her mid twenties, friendly and bright,
looking straight into the camera with a soft natural smile, mouth closed. Head and shoulders,
face centered and filling about half of the frame, eyes at one third from the top.
Soft even studio light, plain softly blurred warm beige background. Natural makeup, shoulder length
dark brown hair, simple cream knit top. Photorealistic, sharp focus on the eyes, calm neutral pose,
hands out of frame. No text, no watermark, not resembling any real person.
```

Change the description to the character you want. Save the image as `reference.png` and use it as the
first frame (start image) of every clip below.

## Step 2: State clips

The lines below match the example persona (friendly polite Korean). Change them to your assistant's
speech style (`persona.md`).
Give the video tool `reference.png` as the start image and enter the prompts one at a time. If the
tool can generate speech, have it say the line after `Says in Korean:`; that voice becomes the material
for the clone in step 4. Add the common sentence to the end of every prompt.

Common sentence:

```
Static locked-off camera, same framing, same background and lighting as the start image, face stays
centered, no zoom, no cuts, no text. The last frame returns to the same pose as the first frame so the
clip loops smoothly.
```

### idle (10 s)

```
She rests calmly, breathing gently, blinking naturally, a faint relaxed smile, mouth closed,
tiny natural head movements. Silent.
```

### greeting (4 s)

```
She brightens with a warm happy smile, raises her eyebrows slightly and greets the viewer with
a small nod. Says in Korean, cheerful and warm: "민준님, 부르셨어요?"
```

Make the line match your `USER_CALL_KO` and `GREETING` joined together (for example `민준님, 부르셨어요?`).

### listening (10 s)

```
She listens attentively to someone speaking off camera, eyes on the camera, small slow nods,
slight head tilt, interested expression, mouth closed. Silent.
```

### thinking (10 s)

```
She thinks about an answer, eyes glance up and to the side, then back to the camera, lips pressed
softly together, a small thoughtful hum without opening the mouth. Silent.
```

### speaking (10 s)

```
She talks naturally to the viewer in a calm friendly tone, clear natural mouth movements, small
expressive eyebrow movements, occasional blinks. Says in Korean, calm and warm:
"네, 확인해 봤어요. 지금 돌아가는 스레드는 두 개고, 둘 다 잘 진행되고 있어요."
```

(Yes, I checked. Two threads are running, and both are going well.)

### speaking_happy (10 s)

```
She talks happily and excitedly, big genuine smile while speaking, bright eyes, lively natural mouth
movements. Says in Korean, cheerful and excited:
"우와, 진짜 잘됐어요! 테스트가 전부 통과했대요. 오늘 정말 최고예요!"
```

(Wow, that went really well! All the tests passed. You're the best today!)

### speaking_sad (10 s)

```
She talks with a sad, sorry expression, eyebrows drawn together and down, softer slower mouth
movements, eyes slightly lowered then back to the camera. Says in Korean, sad and apologetic:
"어떡해요, 서버가 멈췄대요. 죄송해요, 제가 더 빨리 알려 드렸어야 했는데."
```

(Oh no, the server stopped. I'm sorry, I should have told you sooner.)

### speaking_playful (10 s)

```
She talks in a playful teasing way, mischievous smirk, one quick wink, lively eyebrows, natural mouth
movements. Says in Korean, playful and teasing:
"에이, 또 밤새시려는 거죠? 제가 다 알아요. 오늘은 일찍 주무시기로 약속해요."
```

(Come on, you're about to stay up all night again, right? I know you. Promise to sleep early tonight.)

### speaking_comfort (10 s)

```
She talks gently and reassuringly, soft warm eyes, a tender small smile, slow calm mouth movements,
a slight comforting head tilt. Says in Korean, gentle and comforting:
"오늘 많이 힘드셨죠. 괜찮아요, 천천히 하셔도 돼요. 제가 옆에 있을게요."
```

(Today was hard, wasn't it. It's okay, take your time. I'm right here.)

If the video tool only makes clips shorter than 10 seconds, make them as long as it allows; short clips loop too.
Comforting clips often start with a few seconds of a worried face, so check that the face is warm from the first frame.

## Step 3: Fit the clips to the app's format

Keep the original clips (with sound) for step 4; put them in a folder such as `raw/`.
Run this in the repository folder for each clip:

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

- By default it cuts the largest centered square and scales it to 360x360.
- For a portrait clip with the face near the top, set the crop with a fourth argument, for example `"crop=iw:iw:0:ih*0.1"`.
- Processing `idle` also makes `avatar.png` from its first frame.
- Changed clips show after the avatar is reopened: right-click the avatar, choose "아바타 닫기" (close avatar), and it comes back with the next conversation.

## Step 4: Clone the voice (ElevenLabs)

> Clone only a voice you have the right to use: the voice of clips you generated in step 2, your own, or one whose owner agreed. ElevenLabs' terms require this; never clone a real person's voice without consent.

1. Collect only the voice from the original clips with spoken lines. About one minute of clean speech is enough.

   ```bash
   tools/voice_sample.sh voice_sample.wav raw/greeting.mp4 raw/speaking.mp4 raw/speaking_happy.mp4 \
     raw/speaking_sad.mp4 raw/speaking_playful.mp4 raw/speaking_comfort.mp4
   ```

2. On the ElevenLabs website, choose Voices > Add a new voice > Instant Voice Clone, upload `voice_sample.wav` and name it (for example your assistant's name + Clone).
3. Copy the new voice's voice id into `ELEVENLABS_VOICE_ID` in `assistant.conf`.
4. Paste the API key (Profile > API Keys) when `./install.sh` asks for it. If you set a monthly cap on the key, put it in `ELEVENLABS_KEY_MONTHLY_LIMIT`.

ElevenLabs menu names may change. If you cannot find these, look for the add-voice menu on the Voices page.
Instead of cloning, you can also pick a Korean voice you like from the ElevenLabs voice library and use its id.
The assistant speaks with the `eleven_v4` model and acts out emotion tags such as `[cheerfully]`.

### Use the greeting clip's own recording (optional)

By default the greeting is made once with ElevenLabs, kept in `voice_cache/` and reused.
To use the greeting clip's original voice instead, check that its line matches the greeting exactly, then run:

```bash
mkdir -p voice_cache
/opt/homebrew/bin/ffmpeg -i raw/greeting.mp4 -vn -c:a libmp3lame -q:a 2 voice_cache/greeting.mp3
printf '%s' '[cheerfully] 민준님, 부르셨어요?' > voice_cache/greeting.txt
```

`greeting.txt` must match, character for character, `[cheerfully] ` followed by `USER_CALL_KO`, a comma and a space, and `GREETING`.
Otherwise the app makes a new greeting with ElevenLabs.

## Step 5: Listening cue (optional)

A short sound when listening starts. Without it, a macOS system sound is used.
You can make one with ElevenLabs Sound Effects:

```
A short soft futuristic AI assistant chime, waking up to listen, gentle rising tone, under one second
```

Convert the downloaded file and put it in place:

```bash
afconvert -f caff -d LEI16 cue.mp3 sounds/cue.caf
```

If the cue sounds too loud, lower it before converting, for example: `/opt/homebrew/bin/ffmpeg -i cue.mp3 -af volume=-6dB cue_quiet.mp3`
