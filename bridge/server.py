"""
Python-Swift Bridge Server for Code Sergeant.

Provides HTTP/WebSocket API for the SwiftUI frontend to communicate
with the Python backend services.

Run with: python bridge/server.py
"""
import logging
import os
import atexit
import signal
import sys
import threading
import time
from datetime import datetime
from typing import Any, Dict, Optional

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from flask import Flask, jsonify, request  # noqa: E402
from flask_cors import CORS  # noqa: E402

from code_sergeant.ai_client import create_ai_client  # noqa: E402

# Import Code Sergeant modules
from code_sergeant.config import load_config, save_config, set_env_var  # noqa: E402
from code_sergeant.controller import AppController  # noqa: E402
from code_sergeant.native_monitor import NativeMonitor  # noqa: E402
from code_sergeant.personality import get_personality_choices  # noqa: E402
from code_sergeant.tts import TTSService  # noqa: E402
from code_sergeant.voice import list_input_devices, resolve_input_device  # noqa: E402

# Set up logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("code_sergeant.bridge")

app = Flask(__name__)
CORS(app)

# Global state
controller: Optional[AppController] = None
config: Dict[str, Any] = {}
native_monitor: Optional[NativeMonitor] = None
tts_service: Optional[TTSService] = None
_shutdown_lock = threading.Lock()
_shutdown_started = False


def _apply_tts_runtime_config(tts: Optional[TTSService], cfg: Dict[str, Any]) -> None:
    """
    Apply TTS settings from merged config + environment to the live service.

    Sessions use controller.tts_service — this keeps voice/model in sync after PATCH or key save.
    """
    if not tts or not cfg:
        return
    t = cfg.get("tts") or {}
    api_key = (
        os.getenv("ELEVENLABS_API_KEY")
        or t.get("elevenlabs_api_key")
        or t.get("api_key")
    )
    provider = (t.get("provider") or "pyttsx3").lower()
    if provider == "elevenlabs" and api_key:
        tts.set_api_key(api_key)
    if t.get("model_id"):
        tts.model_id = t["model_id"]
    if t.get("optimize_for_speed") is not None:
        tts.optimize_for_speed = bool(t["optimize_for_speed"])
    if t.get("voice_id"):
        tts.set_voice(t["voice_id"])
    if t.get("rate") is not None and getattr(tts, "engine", None):
        try:
            tts.rate = int(t["rate"])
            tts.engine.setProperty("rate", tts.rate)
        except Exception:
            pass
    if t.get("volume") is not None and getattr(tts, "engine", None):
        try:
            tts.volume = float(t["volume"])
            tts.engine.setProperty("volume", tts.volume)
        except Exception:
            pass


def initialize_services():
    """Initialize all backend services."""
    global controller, config, native_monitor, tts_service

    logger.info("Initializing Code Sergeant services...")

    # Load config
    config = load_config()

    # Initialize native monitor
    native_monitor = NativeMonitor()

    # Controller owns the TTS instance used for sessions, reminders, and judgments.
    controller = AppController()
    tts_service = controller.tts_service

    logger.info("Services initialized successfully")


def cleanup_services(reason: str = "shutdown") -> None:
    """Stop background services before the bridge process exits."""
    global _shutdown_started

    with _shutdown_lock:
        if _shutdown_started:
            return
        _shutdown_started = True

    logger.info(f"Cleaning up Code Sergeant services ({reason})...")

    if controller:
        try:
            controller.shutdown()
        except Exception as e:
            logger.warning(f"Controller cleanup failed: {e}")
    elif tts_service:
        try:
            tts_service.cancel_all()
            tts_service.stop()
        except Exception as e:
            logger.warning(f"TTS cleanup failed: {e}")

    logger.info("Code Sergeant service cleanup complete")


def shutdown_process(reason: str, exit_code: int = 0) -> None:
    """Cleanup then terminate the bridge process."""
    cleanup_services(reason)
    os._exit(exit_code)


def _pid_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def start_parent_watchdog() -> None:
    """Exit the bridge if the Swift parent app goes away."""
    raw_parent_pid = os.environ.get("CODESERGEANT_PARENT_PID")
    if not raw_parent_pid:
        return

    try:
        parent_pid = int(raw_parent_pid)
    except ValueError:
        logger.warning(f"Ignoring invalid CODESERGEANT_PARENT_PID={raw_parent_pid!r}")
        return

    if parent_pid <= 1:
        return

    def watch_parent() -> None:
        logger.info(f"Parent watchdog active for PID {parent_pid}")
        while True:
            time.sleep(2.0)
            if os.getppid() == 1 or not _pid_exists(parent_pid):
                logger.warning("Parent app exited; shutting down bridge")
                shutdown_process("parent app exited")

    threading.Thread(target=watch_parent, name="parent-watchdog", daemon=True).start()


def install_shutdown_handlers() -> None:
    """Install process-level cleanup hooks."""
    atexit.register(lambda: cleanup_services("atexit"))

    def handle_signal(signum, _frame) -> None:
        logger.info(f"Received signal {signum}; shutting down bridge")
        shutdown_process(f"signal {signum}")

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)


@app.route("/api/shutdown", methods=["POST"])
def shutdown_server():
    """Shutdown the bridge server."""
    logger.info("Shutdown requested via API")
    
    # Schedule shutdown after response is sent
    def shutdown():
        time.sleep(0.5)  # Give time for response to be sent
        logger.info("Shutting down bridge server...")
        shutdown_process("api shutdown")
    
    threading.Thread(target=shutdown, daemon=True).start()
    
    return jsonify({"success": True, "message": "Server shutting down"})


# ============================================================================
# Status & Health Endpoints
# ============================================================================


@app.route("/api/health", methods=["GET"])
def health_check():
    """Health check endpoint."""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})


@app.route("/api/status", methods=["GET"])
def get_status():
    """Get current application status."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    # Get state snapshot
    state = controller.get_state_snapshot()

    # Calculate focus time from stats
    focus_time_minutes = 0
    if state.stats and state.stats.focus_seconds:
        focus_time_minutes = state.stats.focus_seconds // 60

    return jsonify(
        {
            "session_active": state.session_active,
            "focus_time_minutes": focus_time_minutes,
            "current_goal": state.goal if state.session_active else None,
            "personality": state.personality_name,
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route("/api/ai/status", methods=["GET"])
def get_ai_status():
    """Get AI backend status."""
    if not controller or not hasattr(controller, "ai_client"):
        return jsonify({"error": "AI client not initialized"}), 500

    ai_status = controller.ai_client.get_status()
    ollama_available, ollama_msg = controller.ai_client.check_ollama_available()

    return jsonify({**ai_status, "ollama_server_message": ollama_msg})


# ============================================================================
# Session Management
# ============================================================================


@app.route("/api/session/start", methods=["POST"])
def start_session():
    """Start a new focus session."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    data = request.json or {}
    goal = data.get("goal", "")
    work_minutes = data.get("work_minutes", 25)
    break_minutes = data.get("break_minutes", 5)

    try:
        # Update pomodoro settings if provided
        if work_minutes and controller.pomodoro:
            controller.pomodoro.state.work_duration_minutes = work_minutes
        if break_minutes and controller.pomodoro:
            controller.pomodoro.state.short_break_minutes = break_minutes

        # Start session (only takes goal parameter)
        controller.start_session(goal=goal)

        logger.info(
            f"Session started: goal='{goal}', work={work_minutes}min, break={break_minutes}min"
        )

        return jsonify(
            {
                "success": True,
                "message": "Session started",
                "goal": goal,
                "work_minutes": work_minutes,
                "break_minutes": break_minutes,
            }
        )
    except Exception as e:
        logger.error(f"Failed to start session: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/session/end", methods=["POST"])
def end_session():
    """End current focus session."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    try:
        # Check if ending early (with penalty)
        data = request.json or {}
        early = data.get("early", False)

        # End the session (returns summary with XP info)
        summary = controller.end_session(early=early)
        logger.info(f"Session ended (early={early}, penalty={summary.get('xp_penalty', 0)} XP)")

        return jsonify(
            {"success": True, "message": "Session ended", "summary": summary}
        )
    except Exception as e:
        logger.error(f"Failed to end session: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/session/pause", methods=["POST"])
def pause_session():
    """Pause current session timer."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    try:
        controller.pause_session()
        return jsonify({"success": True, "message": "Session paused"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/session/resume", methods=["POST"])
def resume_session():
    """Resume paused session timer."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    try:
        controller.resume_session()
        return jsonify({"success": True, "message": "Session resumed"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/session/skip-break", methods=["POST"])
def skip_break():
    """Skip current break."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    try:
        if controller.pomodoro and hasattr(controller.pomodoro, "skip_break"):
            controller.pomodoro.skip_break()
        return jsonify({"success": True, "message": "Break skipped"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================================
# Timer & Pomodoro
# ============================================================================


@app.route("/api/timer", methods=["GET"])
def get_timer():
    """Get current timer state."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    pomodoro = getattr(controller, "pomodoro", None)
    if not pomodoro or not pomodoro.state:
        return jsonify(
            {
                "state": "stopped",
                "remaining_seconds": 0,
                "total_seconds": 0,
                "is_break": False,
                "is_paused": False,
                "work_minutes": 25,
                "break_minutes": 5,
            }
        )

    pomodoro_state = pomodoro.state
    is_break = pomodoro_state.current_state in ("short_break", "long_break")

    # Calculate total seconds based on current state
    if pomodoro_state.current_state == "work":
        total_seconds = pomodoro_state.work_duration_minutes * 60
    elif pomodoro_state.current_state == "short_break":
        total_seconds = pomodoro_state.short_break_minutes * 60
    elif pomodoro_state.current_state == "long_break":
        total_seconds = pomodoro_state.long_break_minutes * 60
    else:
        total_seconds = 0

    return jsonify(
        {
            "state": pomodoro_state.current_state,
            "remaining_seconds": pomodoro_state.time_remaining_seconds,
            "total_seconds": total_seconds,
            "is_break": is_break,
            "is_paused": pomodoro_state.is_paused,  # Add pause state
            "work_minutes": pomodoro_state.work_duration_minutes,
            "break_minutes": pomodoro_state.short_break_minutes,
        }
    )


# ============================================================================
# XP & Rank System
# ============================================================================


@app.route("/api/xp/status", methods=["GET"])
def get_xp_status():
    """Get current XP and rank status."""
    if not controller or not hasattr(controller, "xp_manager"):
        return jsonify({"error": "XP manager not initialized"}), 500

    try:
        xp_state = controller.get_xp_state()
        return jsonify(xp_state)
    except Exception as e:
        logger.error(f"Failed to get XP status: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/xp/reset", methods=["POST"])
def reset_xp():
    """Reset all XP and rank (for testing/admin)."""
    if not controller or not hasattr(controller, "xp_manager"):
        return jsonify({"error": "XP manager not initialized"}), 500

    try:
        controller.xp_manager.reset_all_xp()
        return jsonify({"success": True, "message": "XP reset to 0"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/xp/ranks", methods=["GET"])
def get_ranks():
    """Get list of all ranks."""
    if not controller or not hasattr(controller, "xp_manager"):
        return jsonify({"error": "XP manager not initialized"}), 500

    try:
        ranks = controller.xp_manager.get_rank_list()
        return jsonify({"ranks": ranks})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ============================================================================
# Judgment & Warning System
# ============================================================================


@app.route("/api/judgment/current", methods=["GET"])
def get_current_judgment():
    """Get current activity judgment for warning system."""
    if not controller:
        return jsonify({"error": "Controller not initialized"}), 500

    try:
        judgment = controller.get_current_judgment()
        if judgment:
            return jsonify(judgment)
        else:
            # Return default idle state if no judgment
            return jsonify({
                "classification": "idle",
                "confidence": 1.0,
                "reason": "No active session",
                "action": "none",
                "say": ""
            })
    except Exception as e:
        logger.error(f"Failed to get judgment: {e}")
        return jsonify({"error": str(e)}), 500


# ============================================================================
# Activity & Monitoring
# ============================================================================


@app.route("/api/activity/current", methods=["GET"])
def get_current_activity():
    """Get current activity."""
    if not native_monitor:
        return jsonify({"error": "Native monitor not initialized"}), 500

    return jsonify(
        {
            "app": native_monitor.get_frontmost_app(),
            "window_title": native_monitor.get_active_window_title(),
            "idle_seconds": native_monitor.get_idle_seconds(),
            "is_idle": native_monitor.is_user_idle(),
        }
    )


@app.route("/api/screen-monitoring/status", methods=["GET"])
def get_screen_monitoring_status():
    """Get screen monitoring status."""
    if not controller or not hasattr(controller, "screen_monitor"):
        return jsonify({"enabled": False, "status": "not_initialized"})

    sm = controller.screen_monitor
    return jsonify(
        {
            "enabled": sm.is_enabled(),
            "use_local_vision": sm.use_local_vision,
            "backend_status": sm.get_vision_backend_status()
            if hasattr(sm, "get_vision_backend_status")
            else "unknown",
            "check_interval_seconds": sm.check_interval,
            "last_analysis": sm.last_analysis.to_dict()
            if sm.last_analysis and hasattr(sm.last_analysis, "to_dict")
            else None,
        }
    )


@app.route("/api/screen-monitoring/toggle", methods=["POST"])
def toggle_screen_monitoring():
    """Toggle screen monitoring."""
    data = request.json or {}
    enabled = data.get("enabled", True)

    if not controller or not hasattr(controller, "screen_monitor"):
        return jsonify({"error": "Screen monitor not available"}), 500

    controller.screen_monitor.enable(enabled)

    return jsonify({"success": True, "enabled": controller.screen_monitor.is_enabled()})


# ============================================================================
# Settings & Config
# ============================================================================


@app.route("/api/config", methods=["GET"])
def get_config():
    """Get current config (sanitized - no API keys)."""
    sanitized = {**config}

    # Remove sensitive data
    if "openai" in sanitized:
        sanitized["openai"] = {
            **sanitized["openai"],
            "api_key": "***" if config.get("openai", {}).get("api_key") else None,
        }
    if "tts" in sanitized:
        sanitized["tts"] = {
            **sanitized["tts"],
            "elevenlabs_api_key": "***"
            if config.get("tts", {}).get("elevenlabs_api_key")
            else None,
        }

    return jsonify(sanitized)


@app.route("/api/config", methods=["PATCH"])
def update_config():
    """Update config values."""
    global config

    data = request.json or {}

    # Deep merge config
    for key, value in data.items():
        if isinstance(value, dict) and key in config:
            config[key].update(value)
        else:
            config[key] = value

    # Save to disk
    save_config(config)

    # Keep AppController in sync (it holds its own config + live TTS used for sessions)
    if controller:
        controller.config = load_config()
        _apply_tts_runtime_config(controller.tts_service, controller.config)
        controller.apply_voice_runtime_config()

    return jsonify({"success": True, "message": "Config updated"})


@app.route("/api/openai-key", methods=["POST"])
def set_openai_key():
    """Set OpenAI API key securely."""
    data = request.json or {}
    api_key = data.get("api_key", "")

    if not api_key:
        return jsonify({"error": "API key required"}), 400

    try:
        # Save to .env file (secure)
        set_env_var("OPENAI_API_KEY", api_key)

        # Update AI client if available
        if controller and hasattr(controller, "ai_client"):
            success = controller.ai_client.set_openai_key(api_key)
            if success:
                return jsonify(
                    {"success": True, "message": "OpenAI API key saved securely"}
                )

        return jsonify(
            {
                "success": True,
                "message": "OpenAI API key saved to .env (restart required)",
            }
        )
    except Exception as e:
        logger.error(f"Failed to set OpenAI key: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/api/elevenlabs-key", methods=["POST"])
def set_elevenlabs_key():
    """Set ElevenLabs API key securely (stored in .env as ELEVENLABS_API_KEY)."""
    data = request.json or {}
    api_key = data.get("api_key", "")

    if not api_key:
        return jsonify({"error": "API key required"}), 400

    try:
        set_env_var("ELEVENLABS_API_KEY", api_key)

        if tts_service:
            tts_service.set_api_key(api_key)
        if controller:
            controller.config = load_config()
            _apply_tts_runtime_config(controller.tts_service, controller.config)

        return jsonify(
            {"success": True, "message": "ElevenLabs API key saved securely"}
        )
    except Exception as e:
        logger.error(f"Failed to set ElevenLabs key: {e}")
        return jsonify({"error": str(e)}), 500


# ============================================================================
# TTS & Voice
# ============================================================================


@app.route("/api/tts/status", methods=["GET"])
def get_tts_status():
    """Return TTS provider status (no secrets)."""
    if not tts_service:
        return jsonify({"error": "TTS service not initialized"}), 500

    return jsonify(tts_service.get_status())


@app.route("/api/audio/input-devices", methods=["GET"])
def list_audio_input_devices():
    """List available input devices and the current microphone selection."""
    selected_device_name = config.get("voice_activation", {}).get("input_device_name")
    devices = list_input_devices()
    _, resolved_device = resolve_input_device(selected_device_name)
    default_device = next((device for device in devices if device.get("is_default")), None)

    return jsonify(
        {
            "devices": devices,
            "selected_device_name": selected_device_name,
            "resolved_device_name": resolved_device.get("name")
            if resolved_device
            else None,
            "default_device_name": default_device.get("name")
            if default_device
            else None,
            "using_default": not selected_device_name
            or (resolved_device is not None and resolved_device.get("name") != selected_device_name),
        }
    )


@app.route("/api/tts/voices", methods=["GET"])
def list_tts_voices():
    """List voices for the current TTS provider (ElevenLabs + system voices when available)."""
    if not tts_service:
        return jsonify({"error": "TTS service not initialized"}), 500

    force = (request.args.get("refresh") or "").lower() in ("1", "true", "yes")
    try:
        voices = tts_service.get_available_voices(force_refresh=force)
        return jsonify({"voices": voices})
    except Exception as e:
        logger.warning(f"Failed to list TTS voices: {e}")
        return jsonify({"error": str(e), "voices": []}), 500


@app.route("/api/tts/speak", methods=["POST"])
def speak():
    """Speak text using TTS."""
    data = request.json or {}
    text = data.get("text", "")

    if not text:
        return jsonify({"error": "Text required"}), 400

    if not tts_service:
        return jsonify({"error": "TTS service not initialized"}), 500

    tts_service.speak(text)
    return jsonify({"success": True, "message": "Speaking..."})


@app.route("/api/tts/stop", methods=["POST"])
def stop_speaking():
    """Stop current TTS audio."""
    if tts_service:
        tts_service.cancel_all()
    return jsonify({"success": True, "message": "Audio stopped"})


# ============================================================================
# Personality
# ============================================================================


@app.route("/api/personality", methods=["GET"])
def get_personality():
    """Get current personality profile."""
    if not controller or not hasattr(controller, "personality_manager"):
        return jsonify({"error": "Personality manager not available"}), 500

    pm = controller.personality_manager
    prof = pm.profile
    return jsonify(
        {
            "name": prof.name,
            "wake_word_name": prof.wake_word_name,
            "description": prof.description,
            "tone": prof.tone,
            "available_profiles": get_personality_choices(),
        }
    )


@app.route("/api/personality", methods=["POST"])
def set_personality():
    """Change personality profile (persists to config.json via AppController)."""
    data = request.json or {}
    profile_name = data.get("profile", "sergeant")
    custom_description = data.get("custom_description")
    custom_wake_word = data.get("custom_wake_word")

    if not controller:
        return jsonify({"error": "Controller not available"}), 500

    try:
        silent = bool(data.get("silent", True))
        controller.set_personality(
            profile_name,
            custom_description,
            custom_wake_word,
            speak_confirmation=not silent,
        )
        global config
        config = load_config()
        return jsonify({"success": True, "profile": profile_name})
    except Exception as e:
        logger.error(f"Failed to set personality: {e}")
        return jsonify({"error": str(e)}), 500


# ============================================================================
# WebSocket (for real-time updates)
# ============================================================================

# Note: For production, consider using flask-socketio for true WebSocket support
# This basic implementation uses polling, which works for the MVP


@app.route("/api/events/poll", methods=["GET"])
def poll_events():
    """Poll for events (simple alternative to WebSocket)."""
    if not controller:
        return jsonify({"events": []})

    events = []

    # Check session state
    if controller.is_session_active():
        events.append(
            {
                "type": "session_active",
                "data": {
                    "goal": getattr(controller, "session_goal", ""),
                    "elapsed_minutes": controller.get_focus_time_minutes()
                    if hasattr(controller, "get_focus_time_minutes")
                    else 0,
                },
            }
        )

    return jsonify({"events": events, "timestamp": datetime.now().isoformat()})


# ============================================================================
# Main
# ============================================================================


def check_and_free_port(port: int) -> bool:
    """
    Check if port is in use and attempt to free it if it's a Python process.

    Returns:
        True if port is free or was freed, False otherwise
    """
    try:
        import subprocess

        # Find processes using the port
        result = subprocess.run(
            ["lsof", "-ti", f":{port}"], capture_output=True, text=True, timeout=2
        )

        if result.returncode != 0 or not result.stdout.strip():
            return True  # Port is free

        pids = result.stdout.strip().split("\n")

        # Check if any are Python processes (likely stale bridge servers)
        python_pids = []
        for pid in pids:
            try:
                # Check the command name
                cmd_result = subprocess.run(
                    ["ps", "-p", pid, "-o", "comm="],
                    capture_output=True,
                    text=True,
                    timeout=1,
                )
                if cmd_result.returncode == 0:
                    cmd = cmd_result.stdout.strip().lower()
                    if "python" in cmd or "python3" in cmd:
                        python_pids.append(pid)
            except Exception:
                pass

        if python_pids:
            logger.warning(
                f"Found Python process(es) using port {port}: {', '.join(python_pids)}"
            )
            logger.info("Attempting to free the port...")

            # Try to kill Python processes
            for pid in python_pids:
                try:
                    subprocess.run(["kill", "-9", pid], timeout=2, check=False)
                    logger.info(f"Killed process {pid}")
                except Exception as e:
                    logger.warning(f"Failed to kill process {pid}: {e}")

            # Wait a moment for port to be released
            time.sleep(0.5)

            # Verify port is now free
            result = subprocess.run(
                ["lsof", "-ti", f":{port}"], capture_output=True, text=True, timeout=2
            )
            if result.returncode != 0 or not result.stdout.strip():
                logger.info("Port is now free!")
                return True
            else:
                logger.warning("Port still in use after kill attempt")
                return False
        else:
            # Non-Python process using the port
            logger.error(
                f"Port {port} is in use by non-Python process(es): {', '.join(pids)}"
            )
            return False

    except Exception as e:
        logger.debug(f"Error checking port: {e}")
        return False


def main():
    """Start the bridge server."""
    install_shutdown_handlers()
    start_parent_watchdog()

    # Run server
    port = int(os.environ.get("BRIDGE_PORT", 5050))

    # Check the port before starting microphones, TTS, or wake-word workers.
    if not check_and_free_port(port):
        logger.error(f"Port {port} is already in use!")
        logger.error(
            "Another instance may be running, or another app is using this port."
        )
        logger.error(f"To use a different port, set BRIDGE_PORT environment variable:")
        logger.error(f"  export BRIDGE_PORT=5051")
        logger.error(f"  python bridge/server.py")
        sys.exit(1)

    # Initialize services
    try:
        initialize_services()
    except Exception as e:
        logger.error(f"Failed to initialize services: {e}")
        logger.error(
            "Make sure you're running from the project root and dependencies are installed"
        )
        sys.exit(1)

    logger.info("=" * 60)
    logger.info(f"🚀 Code Sergeant Bridge Server")
    logger.info(f"   Listening on: http://127.0.0.1:{port}")
    logger.info(f"   Status: http://127.0.0.1:{port}/api/health")
    logger.info("=" * 60)

    try:
        app.run(
            host="127.0.0.1",  # Only local connections
            port=port,
            debug=os.environ.get("DEBUG", "false").lower() == "true",
            threaded=True,
            use_reloader=False,  # Disable reloader for production
        )
    except OSError as e:
        if "Address already in use" in str(e):
            logger.error(f"Port {port} is still in use after cleanup attempt!")
            logger.error("Please manually kill the process or use a different port.")
        else:
            logger.error(f"Failed to start server: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
