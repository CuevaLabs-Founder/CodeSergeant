# Code Sergeant v2.0.0

**Release Date**: April 2026

---

## Your AI Body Double — Now With a Proper Installer

v2.0.0 ships a fully redesigned SwiftUI interface, a refactored backend, and a clean DMG installer. No Xcode required to get running.

**Built for:**
- Developers who want to ship more and scroll less
- People with ADHD who need external accountability
- Vibe coders who work best with company (even artificial company)
- Anyone tired of losing hours to "just one quick Twitter check"

---

## What's New in v2.0.0

### DMG Installer
Download `CodeSergeant-2.0.0.dmg`, drag the app to Applications, and you're running. No Xcode, no terminal, no Python setup required.

### Full SwiftUI Redesign
The entire interface was rebuilt from scratch:

- **Glass card layout** — clean layered panels for each view
- **Liquid buttons** — animated interactive controls
- **Dashboard view** — all session info in a single focused panel
- **XP and rank system** — earn XP during focus sessions, watch the rank climb
- **Warning strobe overlay** — full-screen visual flash when drift is detected

### Voice Note Recording
Say "Take note Sergeant" at any time to capture a hands-free note. The audio is transcribed automatically and saved with the session.

### Backend Refactor
- AppController rewritten for cleaner session lifecycle management
- Voice worker rebuilt — more reliable wake phrase detection, fewer false triggers
- TTS updated with better ElevenLabs integration and fallback handling
- Bridge server expanded with new REST endpoints for all SwiftUI panels

---

## Install (DMG — Recommended)

1. Download `CodeSergeant-2.0.0.dmg` from the [Releases page](https://github.com/CuevaLabs/CodeSergeant/releases)
2. Open the DMG and drag **Code Sergeant** to your Applications folder
3. Launch from Applications or Spotlight
4. Grant **Accessibility** and **Microphone** permissions when prompted

> Code Sergeant needs these permissions to read active window titles and listen for wake phrases. Both are granted through System Settings → Privacy & Security.

---

## Install (Build from Source)

For developers who want to run the full stack locally:

```bash
git clone https://github.com/CuevaLabs/CodeSergeant.git
cd CodeSergeant
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
open CodeSergeantUI/CodeSergeantUI.xcodeproj
```

Build and run the `CodeSergeantUI` target in Xcode. For smarter AI judgment, install [Ollama](https://ollama.ai/) and run `ollama pull llama3.2`.

---

## Requirements

- macOS 13+ (Ventura or later) for v2.0.0
- Ollama or OpenAI API key (optional but recommended)
- ElevenLabs API key (optional, for premium voices)

---

## Known Limitations

- macOS only for now
- Wake word can false-trigger in noisy environments
- First launch takes a few seconds while models load

---

## What's Coming

- Analytics dashboard to track focus patterns
- Session history visualization
- iOS companion app
- Community-requested personalities

---

## Join the Community

- **Twitter/X**: Share your wins with [#CodeSergeant](https://x.com/search?q=%23CodeSergeant)
- **GitHub Issues**: Bug reports and feature requests welcome
- **Follow**: [@cuevalabsdev](https://x.com/cuevalabsdev) for updates

---

## Acknowledgments

- [Ollama](https://ollama.ai/) for making local AI accessible
- [ElevenLabs](https://elevenlabs.io/) for voices that don't sound like robots
- [faster-whisper](https://github.com/guillaumekln/faster-whisper) for speech recognition
- Everyone in the ADHD productivity community who inspired this

---

**Stay focused. Ship code. You've got this.**
