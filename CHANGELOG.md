# Changelog

All notable changes to Code Sergeant will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-04-20

Major release: full SwiftUI redesign, backend refactor, and voice note recording.

### Added
- Voice note recording — say "Take note Sergeant" to capture a hands-free note with automatic transcription
- XP and rank system with animated XP display and level-up tracking
- Warning strobe overlay — visual full-screen flash when focus drift is detected
- Glass card and liquid button design system throughout the SwiftUI UI
- Dashboard view as the primary session panel
- Animated timer display component
- DMG installer — download and double-click to install, no Xcode required

### Changed
- Complete SwiftUI redesign replacing the legacy menu bar UI (menu_bar.py removed)
- AppController refactored for cleaner session lifecycle and thread-safe worker coordination
- Voice worker fully rewritten — more reliable wake word detection, reduced false triggers
- TTS service updated with better ElevenLabs integration and fallback handling
- Bridge server (Flask) expanded with new REST endpoints for the SwiftUI frontend
- Project migrated from Swift Package Manager to Xcode project (project.yml / xcodegen)

### Removed
- `Package.swift` (SPM) — replaced by `CodeSergeantUI.xcodeproj`
- Legacy `code_sergeant/menu_bar.py` — UI is now entirely in SwiftUI

---

## [1.0.0] - 2025-01-07

First public release. An AI body double for developers who need accountability.

### Added
- Native macOS activity monitoring using AppKit/Quartz APIs
- AI-powered activity judgment (Ollama local or OpenAI cloud)
- Text-to-speech feedback (ElevenLabs premium or system voices)
- Pomodoro timer with configurable durations
- Voice interaction with full wake phrase detection ("Hey Sergeant")
- Voice note capture with dedicated wake phrase ("Take note Sergeant") and automatic transcription
- Multiple personality profiles (Sergeant, Buddy, Advisor, Coach)
- SwiftUI menu bar application
- Python-Swift bridge server (Flask)
- Session logging and statistics
- 157 tests passing

### Technical
- Self-contained monitoring (no external dependencies)
- Privacy-first architecture with local AI processing
- Thread-safe worker architecture with event queue
- Graceful fallback when AI services unavailable

### License
- Released under AGPL-3.0 to keep the project open and community-focused

---

## Contributing to the Changelog

When contributing, add entries to an `[Unreleased]` section using these categories:

- **Added** - New features
- **Changed** - Changes to existing functionality
- **Deprecated** - Features to be removed
- **Removed** - Removed features
- **Fixed** - Bug fixes
- **Security** - Vulnerability fixes
