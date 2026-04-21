# Quick Start Guide

Get Code Sergeant running in under 5 minutes.

---

## Option 1: DMG Installer (Recommended)

No Xcode or Python required.

1. Download `CodeSergeant-2.0.0.dmg` from the [Releases page](https://github.com/CuevaLabs/CodeSergeant/releases)
2. Open the DMG and drag **Code Sergeant** to your **Applications** folder
3. Launch Code Sergeant from Applications or Spotlight
4. Grant permissions when prompted (see [Permissions](#permissions) below)
5. Click the shield icon in your menu bar and start a session

---

## Option 2: Build from Source

### Step 1: Install Dependencies

```bash
# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### Step 2: Set Up AI (Choose Your Backend)

Code Sergeant can use local AI (Ollama) or cloud AI (OpenAI). Pick one or both.

#### Option A: Ollama (Local, Free, Private)

Best for privacy. Everything runs on your machine.

1. Download from [ollama.ai](https://ollama.ai/)
2. Pull a model:

```bash
ollama pull llama3.2
```

#### Option B: OpenAI (Cloud, Faster, Paid)

Better responses, requires API key.

1. Get an API key from [platform.openai.com](https://platform.openai.com/)
2. Create a `.env` file in the project root:

```bash
OPENAI_API_KEY=sk-your-key-here
```

Or add it to `config.json`:

```json
{
  "openai": {
    "api_key": "sk-your-key-here",
    "model": "gpt-4o-mini"
  }
}
```

### Step 3: Set Up Voice (Optional)

Code Sergeant talks to you. Choose your voice backend.

#### Default: System Voice (Free)

Works out of the box using macOS system voices. No setup needed.

#### ElevenLabs (Premium AI Voices)

For high-quality, personality-matched voices:

1. Get an API key from [elevenlabs.io](https://elevenlabs.io/)
2. Add to `.env`:

```bash
ELEVENLABS_API_KEY=your-key-here
```

3. Configure voices in `config.json`:

```json
{
  "tts": {
    "provider": "elevenlabs",
    "voice_id": "YOUR_VOICE_ID",
    "model_id": "eleven_turbo_v2_5"
  }
}
```

### Step 4: Open the Xcode Project

```bash
open CodeSergeantUI/CodeSergeantUI.xcodeproj
```

Build and run the `CodeSergeantUI` target in Xcode. The app will:
- Appear in your menu bar with a shield icon
- Start the Python bridge server automatically
- Start monitoring using native macOS APIs once you begin a session

---

## Start Your First Session

1. Click the Code Sergeant icon in your menu bar
2. Click **Start Focus Session**
3. Enter your focus goal (e.g., "Build the login feature")
4. Work — Code Sergeant monitors your active app and window titles
5. When you drift, it speaks up

---

## Permissions

Code Sergeant needs two permissions to function. Grant them through **System Settings → Privacy & Security**.

| Permission | Purpose | How to Grant |
|------------|---------|--------------|
| Accessibility | Read window titles for activity monitoring | System Settings → Privacy & Security → Accessibility |
| Microphone | Wake word detection, voice commands, and voice notes | System Settings → Privacy & Security → Microphone |

---

## Voice Features

- **Wake word**: Say the full phrase **"Hey Sergeant"** to interact hands-free. "Sergeant" alone is ignored to prevent false triggers.
- **Voice notes**: Say **"Take note Sergeant"** to start dictating a note — it's transcribed and saved automatically.
- **Spoken feedback**: Hear warnings, encouragement, and session summaries via your chosen voice backend.

---

## Troubleshooting

**No AI responses?**
- Make sure Ollama is running (`ollama serve`) OR OpenAI key is set
- Check your `.env` file is in the project root
- The app works without AI using rule-based classification

**No voice output?**
- System voice works without setup — check your Mac volume
- For ElevenLabs, verify your API key is correct

**No window titles being monitored?**
- Grant Accessibility permission to Code Sergeant (or Terminal if building from source)

**Microphone not working?**
- Grant Microphone permission when prompted
- Check System Settings → Privacy & Security → Microphone
