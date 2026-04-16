# Code Sergeant - SwiftUI Setup

Code Sergeant now uses a **pure SwiftUI frontend** with a Python backend bridge server, completely removing the old rumps dependency.

## Architecture

- **SwiftUI Frontend**: Native macOS app in `CodeSergeantUI/`
- **Python Backend**: Bridge server in `bridge/server.py`
- **Communication**: HTTP API on port 5050

## Running the Application

### Method 1: Using Xcode (Recommended)

1. Open `CodeSergeantUI/CodeSergeantUI.xcodeproj` in Xcode
2. Build and run the app (⌘+R)
3. The SwiftUI app will automatically start the Python bridge server

### Method 2: Manual Bridge Server + SwiftUI

1. Start the Python bridge server:
   ```bash
   cd /Users/cuevalabs/Desktop/Projects/CodeSergeant
   source .venv/bin/activate
   python3 main.py
   ```

2. In another terminal, build and run the SwiftUI app:
   ```bash
   cd CodeSergeantUI
    xcodebuild -project CodeSergeantUI.xcodeproj -scheme CodeSergeantUI -configuration Debug build
   open CodeSergeantUI.xcodeproj  # then run from Xcode
   ```

## What Changed

### Removed
- `rumps` dependency from `requirements.txt`
- `code_sergeant/menu_bar.py` (entire file)
- All rumps-based menu bar code

### Updated
- `main.py` now starts the bridge server instead of rumps app
- `code_sergeant/__init__.py` removed rumps imports
- Added missing API endpoints to bridge server
- Fixed SwiftUI bridge client with proper data models

### Added
- Complete SwiftUI interface with:
  - Menu bar dropdown
  - Expanded session panel inside the menu bar window
  - Settings panel
  - Real-time status updates
  - XP and rank system
  - Screen monitoring controls

## API Endpoints

The bridge server provides these endpoints for the SwiftUI app:

- `GET /api/health` - Health check
- `GET /api/status` - Session status
- `GET /api/timer` - Pomodoro timer state
- `GET /api/xp/status` - XP and rank information
- `GET /api/judgment/current` - Current activity judgment
- `GET /api/ai/status` - AI backend status
- `GET /api/screen-monitoring/status` - Screen monitoring status
- `POST /api/session/start` - Start focus session
- `POST /api/session/end` - End focus session
- `POST /api/session/pause` - Pause session
- `POST /api/session/resume` - Resume session
- `POST /api/session/skip-break` - Skip current break
- `POST /api/openai-key` - Set OpenAI API key
- `POST /api/screen-monitoring/toggle` - Toggle screen monitoring
- `POST /api/tts/speak` - Text-to-speech
- `POST /api/tts/stop` - Stop TTS
- `POST /api/personality` - Set personality
- `POST /api/shutdown` - Shutdown bridge server

## Troubleshooting

### Bridge Server Won't Start
- Ensure you're in the project root directory
- Activate virtual environment: `source .venv/bin/activate`
- Install dependencies: `pip install -r requirements.txt`

### SwiftUI App Can't Connect
- Check that bridge server is running on port 5050
- Test with: `curl http://127.0.0.1:5050/api/health`
- Check Xcode console for bridge server startup logs

### Missing Features
- All original rumps functionality is now available in SwiftUI
- Voice features require Whisper to be installed: `pip install openai-whisper`
- Screen monitoring requires proper permissions in System Settings

## Development

- **SwiftUI Code**: `CodeSergeantUI/`
- **Python Bridge**: `bridge/server.py`
- **Backend Logic**: `code_sergeant/`
- **API Models**: `CodeSergeantUI/Services/PythonBridge.swift`

The SwiftUI app automatically manages the Python backend process, starting and stopping it as needed.
