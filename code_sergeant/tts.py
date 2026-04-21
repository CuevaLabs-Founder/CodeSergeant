"""Text-to-speech service with ElevenLabs support."""
import inspect
import logging
import os
import queue
import subprocess
import tempfile
import threading
import time
from typing import Any, Dict, List, Optional

import pyttsx3

logger = logging.getLogger("code_sergeant.tts")

# Try to import ElevenLabs (optional) - v2 API
try:
    from elevenlabs.client import ElevenLabs

    ELEVENLABS_AVAILABLE = True
    logger.info("ElevenLabs SDK loaded successfully")
except ImportError as e:
    ELEVENLABS_AVAILABLE = False
    logger.warning(
        f"ElevenLabs not installed: {e}. Install with: pip install elevenlabs"
    )


# Common ElevenLabs voices for different personalities
# When ElevenLabs is unavailable, pyttsx3 picks the first ID present on this Mac.
# Fred is very robotic; compact Samantha/Daniel are usually more listenable.
_PREFERRED_PYTTSX3_VOICE_IDS = [
    "com.apple.voice.compact.en-US.Samantha",
    "com.apple.voice.compact.en-GB.Daniel",
    "com.apple.voice.compact.en-AU.Karen",
    "com.apple.speech.synthesis.voice.Fred",
]

RECOMMENDED_VOICES = {
    "sergeant": {
        "voice_id": "DGzg6RaUqxGRTHSBjfgF",
        "name": "Adam (Deep Male)",
        "description": "Deep, authoritative male voice",
    },
    "buddy": {
        "voice_id": "EXAVITQu4vr4xnSDxMaL",
        "name": "Sarah (Friendly Female)",
        "description": "Warm, friendly female voice",
    },
    "advisor": {
        "voice_id": "onwK4e9ZLuTAKqWW03F9",
        "name": "Daniel (British Male)",
        "description": "Professional, clear British male voice",
    },
    "coach": {
        "voice_id": "TX3LPaxmHKxFdv7VOQHJ",
        "name": "Liam (Energetic Male)",
        "description": "Energetic, motivational male voice",
    },
}


class MusicDucker:
    """
    Ducks audio from music apps and browsers while the sergeant speaks.

    Strategy — targets sources independently so TTS always plays at full volume:

      • Native apps (Spotify, Music.app): AppleScript `sound volume` property.
      • Chromium browsers (Chrome, Brave, Edge, Arc …): JS injected into every tab
        via `execute tab javascript`.
      • Safari: JS injected via `do JavaScript … in tab`.

    The macOS system output volume is intentionally never touched — doing so
    would lower the TTS equally, defeating the purpose.

    Firefox has no scriptable tab API on macOS; it is skipped.
    """

    _MUSIC_APPS = ["Spotify", "Music"]

    # Chromium-based browsers that support AppleScript tab JS execution.
    _CHROMIUM_BROWSERS = [
        "Google Chrome",
        "Brave Browser",
        "Microsoft Edge",
        "Arc",
        "Vivaldi",
        "Opera",
    ]
    _SAFARI_BROWSERS = ["Safari"]

    # JS snippets — use single quotes only so the string is safe to embed
    # inside an AppleScript double-quoted string with no escaping.
    _DUCK_JS = (
        "var _e=document.querySelectorAll('video,audio');"
        "for(var _i=0;_i<_e.length;_i++){{"
        "var _m=_e[_i];"
        "if(!_m.paused&&_m.volume>{r}){{_m.dataset.sgtV=_m.volume;_m.volume={r};}}"
        "}}"
    )
    _RESTORE_JS = (
        "var _e=document.querySelectorAll('video,audio');"
        "for(var _i=0;_i<_e.length;_i++){"
        "var _m=_e[_i];"
        "if(_m.dataset.sgtV){_m.volume=parseFloat(_m.dataset.sgtV);delete _m.dataset.sgtV;}"
        "}"
    )

    def __init__(self, duck_to: int = 20, fade_steps: int = 0, step_delay: float = 0.03):
        """
        Args:
            duck_to:     Target volume while speaking (0-100 for native apps;
                         maps to 0.0-1.0 for HTML media elements).
            fade_steps:  Fade steps for native apps (0 = instant).
            step_delay:  Seconds between fade steps.
        """
        self.duck_to = max(0, min(100, duck_to))
        self.fade_steps = fade_steps
        self.step_delay = step_delay
        self._saved_native: dict[str, int] = {}         # app → original volume
        self._ducked_browsers: list[tuple[str, str]] = []  # (kind, app)

    # ------------------------------------------------------------------
    # Generic helpers
    # ------------------------------------------------------------------

    def _app_is_running(self, app: str) -> bool:
        """Ask macOS whether the named application is currently running."""
        try:
            result = subprocess.run(
                ["osascript", "-e", f'application "{app}" is running'],
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            return result.stdout.strip().lower() == "true"
        except Exception:
            return False

    def _run_script(self, script: str) -> bool:
        """Run a multi-line AppleScript passed via stdin. Returns True on success."""
        try:
            result = subprocess.run(
                ["osascript", "-"],
                input=script,
                capture_output=True,
                text=True,
                timeout=3.0,
            )
            return result.returncode == 0
        except Exception:
            return False

    # ------------------------------------------------------------------
    # Native music app helpers
    # ------------------------------------------------------------------

    def _get_app_volume(self, app: str) -> Optional[int]:
        try:
            result = subprocess.run(
                ["osascript", "-e", f'tell application "{app}" to get sound volume'],
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            if result.returncode == 0 and result.stdout.strip():
                return int(result.stdout.strip())
        except Exception:
            pass
        return None

    def _set_app_volume(self, app: str, level: int) -> None:
        try:
            subprocess.run(
                ["osascript", "-e", f'tell application "{app}" to set sound volume to {level}'],
                capture_output=True,
                timeout=1.0,
            )
        except Exception:
            pass

    def _fade_app(self, app: str, from_level: int, to_level: int) -> None:
        if self.fade_steps <= 0 or from_level == to_level:
            self._set_app_volume(app, to_level)
            return
        step = (to_level - from_level) / self.fade_steps
        for i in range(1, self.fade_steps + 1):
            self._set_app_volume(app, int(from_level + step * i))
            time.sleep(self.step_delay)

    # ------------------------------------------------------------------
    # Browser JS injection helpers
    # ------------------------------------------------------------------

    def _duck_js(self) -> str:
        r = round(self.duck_to / 100.0, 3)
        return self._DUCK_JS.format(r=r)

    def _duck_chromium(self, app: str) -> bool:
        js = self._duck_js()
        script = f'''tell application "{app}"
    repeat with w in windows
        repeat with t in tabs of w
            try
                execute t javascript "{js}"
            end try
        end repeat
    end repeat
end tell'''
        ok = self._run_script(script)
        if ok:
            logger.debug(f"Ducked browser tabs: {app}")
        return ok

    def _restore_chromium(self, app: str) -> None:
        js = self._RESTORE_JS
        script = f'''tell application "{app}"
    repeat with w in windows
        repeat with t in tabs of w
            try
                execute t javascript "{js}"
            end try
        end repeat
    end repeat
end tell'''
        self._run_script(script)

    def _duck_safari(self, app: str) -> bool:
        js = self._duck_js()
        script = f'''tell application "{app}"
    repeat with w in windows
        repeat with t in tabs of w
            try
                do JavaScript "{js}" in t
            end try
        end repeat
    end repeat
end tell'''
        ok = self._run_script(script)
        if ok:
            logger.debug(f"Ducked Safari tabs")
        return ok

    def _restore_safari(self, app: str) -> None:
        js = self._RESTORE_JS
        script = f'''tell application "{app}"
    repeat with w in windows
        repeat with t in tabs of w
            try
                do JavaScript "{js}" in t
            end try
        end repeat
    end repeat
end tell'''
        self._run_script(script)

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def duck(self) -> None:
        """Lower music app volumes and browser media elements."""
        self._saved_native.clear()
        self._ducked_browsers.clear()

        # Native apps
        for app in self._MUSIC_APPS:
            if not self._app_is_running(app):
                continue
            vol = self._get_app_volume(app)
            if vol is None or vol <= self.duck_to:
                continue
            self._saved_native[app] = vol
            self._fade_app(app, vol, self.duck_to)
            logger.debug(f"Ducked {app}: {vol} → {self.duck_to}")

        # Chromium browsers
        for app in self._CHROMIUM_BROWSERS:
            if self._app_is_running(app):
                if self._duck_chromium(app):
                    self._ducked_browsers.append(("chromium", app))

        # Safari
        for app in self._SAFARI_BROWSERS:
            if self._app_is_running(app):
                if self._duck_safari(app):
                    self._ducked_browsers.append(("safari", app))

    def restore(self) -> None:
        """Restore all ducked sources."""
        # Native apps
        for app, vol in self._saved_native.items():
            current = self._get_app_volume(app) or self.duck_to
            self._fade_app(app, current, vol)
            logger.debug(f"Restored {app}: → {vol}")
        self._saved_native.clear()

        # Browsers
        for kind, app in self._ducked_browsers:
            if kind == "chromium":
                self._restore_chromium(app)
            elif kind == "safari":
                self._restore_safari(app)
        self._ducked_browsers.clear()


class TTSService:
    """Non-blocking text-to-speech service with ElevenLabs support."""

    def __init__(
        self,
        provider: str = "pyttsx3",
        api_key: Optional[str] = None,
        voice_id: Optional[str] = None,
        model_id: str = "eleven_turbo_v2_5",
        rate: int = 200,
        volume: float = 1.0,
        optimize_for_speed: bool = True,
        music_ducking: bool = True,
        duck_volume: int = 20,
    ):
        """
        Initialize TTS service.

        Args:
            provider: "elevenlabs" or "pyttsx3"
            api_key: ElevenLabs API key (required if provider is "elevenlabs")
            voice_id: Voice ID (ElevenLabs voice ID or pyttsx3 voice ID)
            model_id: ElevenLabs model ID (default: eleven_turbo_v2_5)
            rate: Speech rate (words per minute) - only for pyttsx3
            volume: Volume level (0.0-1.0) - only for pyttsx3
            music_ducking: Lower system audio while speaking, restore after.
            duck_volume: System volume level (0-100) to duck to while speaking.
        """
        self.provider = provider.lower()
        self.api_key = api_key
        self.voice_id = voice_id
        self.model_id = model_id
        self.rate = rate
        self.volume = volume
        self.optimize_for_speed = optimize_for_speed  # Store speed optimization flag
        self._ducker = MusicDucker(duck_to=duck_volume) if music_ducking else None
        self.speak_queue = queue.Queue()
        self.stop_event = threading.Event()
        self.worker_thread: Optional[threading.Thread] = None
        self.client = None
        self.engine = None  # pyttsx3 engine
        self._available_voices: Optional[List[Dict[str, Any]]] = None

        # State tracking for pause/wait functionality
        self._paused = threading.Event()
        self._speaking = threading.Event()  # Set when actively speaking
        self._speaking_done = threading.Event()
        self._speaking_done.set()  # Initially not speaking

        # Track current audio process for interruption
        self._current_process: Optional[subprocess.Popen] = None
        self._current_temp_file: Optional[str] = None

        # Initialize based on provider
        if self.provider == "elevenlabs":
            self._init_elevenlabs()
        else:
            self._init_pyttsx3()

    def _init_elevenlabs(self):
        """Initialize ElevenLabs TTS."""
        if not ELEVENLABS_AVAILABLE:
            logger.error("ElevenLabs not available, falling back to pyttsx3")
            self.provider = "pyttsx3"
            self._init_pyttsx3()
            return

        if not self.api_key:
            # Try to get from environment variable
            self.api_key = os.getenv("ELEVENLABS_API_KEY")
            if not self.api_key:
                logger.error("ElevenLabs API key not provided, falling back to pyttsx3")
                self.provider = "pyttsx3"
                self._init_pyttsx3()
                return

        try:
            # Initialize ElevenLabs client (v2 API)
            self.client = ElevenLabs(api_key=self.api_key)

            # Default voice ID if not provided (drill sergeant voice)
            if not self.voice_id:
                self.voice_id = "DGzg6RaUqxGRTHSBjfgF"

            # Also initialize pyttsx3 as fallback
            self._init_pyttsx3_fallback()

            logger.info(
                f"ElevenLabs TTS initialized with voice: {self.voice_id}, model: {self.model_id}"
            )
        except Exception as e:
            logger.error(
                f"Failed to initialize ElevenLabs: {e}, falling back to pyttsx3"
            )
            self.provider = "pyttsx3"
            self._init_pyttsx3()

    def _init_pyttsx3_fallback(self):
        """Initialize pyttsx3 as fallback (don't change provider)."""
        try:
            self.engine = pyttsx3.init()
            self.engine.setProperty("rate", self.rate)
            self.engine.setProperty("volume", self.volume)
            self._set_preferred_pyttsx3_voice()
            logger.debug("pyttsx3 fallback initialized")
        except Exception as e:
            logger.warning(f"Could not initialize pyttsx3 fallback: {e}")
            self.engine = None

    def _init_pyttsx3(self):
        """Initialize pyttsx3 TTS (primary)."""
        try:
            self.engine = pyttsx3.init()
            self.engine.setProperty("rate", self.rate)
            self.engine.setProperty("volume", self.volume)

            # Set voice if specified and it's a pyttsx3 voice ID
            if self.voice_id and self.voice_id.startswith("com.apple"):
                self._set_voice(self.voice_id)
            else:
                self._set_preferred_pyttsx3_voice()

            logger.info("pyttsx3 TTS engine initialized")
        except Exception as e:
            logger.error(f"Failed to initialize pyttsx3 engine: {e}")
            self.engine = None

    def _set_preferred_pyttsx3_voice(self) -> None:
        """Pick the best available built-in macOS voice (avoids robotic Fred when possible)."""
        if not self.engine:
            return
        try:
            installed = {v.id for v in self.engine.getProperty("voices")}
        except Exception as e:
            logger.warning(f"Could not list pyttsx3 voices: {e}")
            return
        for vid in _PREFERRED_PYTTSX3_VOICE_IDS:
            if vid in installed:
                self.engine.setProperty("voice", vid)
                logger.info(f"TTS voice set to: {vid}")
                return
        logger.warning("No preferred pyttsx3 voice ID matched; using engine default")

    def _set_voice(self, voice_id: str) -> bool:
        """
        Set the pyttsx3 voice by ID.

        Args:
            voice_id: Voice identifier

        Returns:
            True if voice was set, False otherwise
        """
        if not self.engine:
            return False

        try:
            voices = self.engine.getProperty("voices")
            for voice in voices:
                if voice.id == voice_id or voice.name.lower() == voice_id.lower():
                    self.engine.setProperty("voice", voice.id)
                    logger.info(f"TTS voice set to: {voice.name}")
                    return True

            logger.warning(f"Voice not found: {voice_id}")
            return False
        except Exception as e:
            logger.error(f"Error setting voice: {e}")
            return False

    def set_voice(self, voice_id: str) -> bool:
        """
        Set the voice for TTS (public method).

        Args:
            voice_id: Voice ID (ElevenLabs or pyttsx3)

        Returns:
            True if voice was set successfully
        """
        self.voice_id = voice_id

        if self.provider == "elevenlabs":
            # For ElevenLabs, just update the voice_id
            logger.info(f"ElevenLabs voice set to: {voice_id}")
            return True
        else:
            return self._set_voice(voice_id)

    def set_api_key(self, api_key: str) -> bool:
        """
        Set ElevenLabs API key and reinitialize if needed.

        Args:
            api_key: ElevenLabs API key

        Returns:
            True if successful
        """
        self.api_key = api_key

        if self.provider == "elevenlabs" or (api_key and ELEVENLABS_AVAILABLE):
            try:
                self.client = ElevenLabs(api_key=api_key)
                self.provider = "elevenlabs"
                self._available_voices = None  # Reset cached voices
                logger.info("ElevenLabs API key updated and client reinitialized")
                return True
            except Exception as e:
                logger.error(f"Failed to reinitialize ElevenLabs with new API key: {e}")
                return False
        return True

    def get_available_voices(self, force_refresh: bool = False) -> List[Dict[str, Any]]:
        """
        Get list of available voices.

        Args:
            force_refresh: Force refresh from API

        Returns:
            List of voice dictionaries with id, name, description
        """
        if self._available_voices and not force_refresh:
            return self._available_voices

        voices = []

        # Get ElevenLabs voices if available
        if self.provider == "elevenlabs" and self.client:
            try:
                response = self.client.voices.get_all()
                for voice in response.voices:
                    voices.append(
                        {
                            "id": voice.voice_id,
                            "name": voice.name,
                            "description": voice.description or "",
                            "provider": "elevenlabs",
                            "labels": getattr(voice, "labels", {}),
                        }
                    )
                logger.info(f"Fetched {len(voices)} ElevenLabs voices")
            except Exception as e:
                logger.warning(f"Failed to fetch ElevenLabs voices: {e}")

        # Get pyttsx3 voices
        if self.engine:
            try:
                pyttsx3_voices = self.engine.getProperty("voices")
                for voice in pyttsx3_voices:
                    voices.append(
                        {
                            "id": voice.id,
                            "name": voice.name,
                            "description": f"System voice ({voice.languages[0] if voice.languages else 'unknown'})",
                            "provider": "pyttsx3",
                        }
                    )
            except Exception as e:
                logger.warning(f"Failed to get pyttsx3 voices: {e}")

        self._available_voices = voices
        return voices

    def get_recommended_voice(self, personality: str) -> Dict[str, Any]:
        """
        Get recommended voice for a personality.

        Args:
            personality: Personality name (sergeant, buddy, advisor, coach)

        Returns:
            Voice info dictionary
        """
        return RECOMMENDED_VOICES.get(personality, RECOMMENDED_VOICES["sergeant"])

    def preview_voice(
        self, voice_id: str, text: str = "Hello! This is a voice preview."
    ) -> bool:
        """
        Preview a voice by speaking sample text.

        Args:
            voice_id: Voice ID to preview
            text: Sample text to speak

        Returns:
            True if preview successful
        """
        original_voice = self.voice_id
        try:
            self.voice_id = voice_id

            if self.provider == "elevenlabs" and self.client:
                self._speak_elevenlabs(text)
            elif self.engine:
                # Temporarily set voice for preview
                self._set_voice(voice_id)
                self.engine.say(text)
                self.engine.runAndWait()

            return True
        except Exception as e:
            logger.error(f"Voice preview failed: {e}")
            return False
        finally:
            self.voice_id = original_voice

    def start(self):
        """Start TTS worker thread."""
        if self.worker_thread and self.worker_thread.is_alive():
            logger.warning("TTS worker already running")
            return

        self.stop_event.clear()
        self.worker_thread = threading.Thread(target=self._worker_loop, daemon=True)
        self.worker_thread.start()
        logger.info("TTS worker started")

    def stop(self):
        """Stop TTS worker thread."""
        if self.worker_thread:
            self.stop_event.set()
            self.worker_thread.join(timeout=2.0)
            logger.info("TTS worker stopped")

    def speak(self, text: str) -> None:
        """
        Enqueue text to be spoken (non-blocking).

        Args:
            text: Text to speak
        """
        if not text or not text.strip():
            return

        try:
            self.speak_queue.put_nowait(text)
            logger.debug(f"Enqueued speech: {text[:50]}")
        except queue.Full:
            logger.warning("TTS queue full, dropping message")

    def pause(self) -> None:
        """
        Pause TTS queue processing.

        New items can still be enqueued but won't be spoken until resumed.
        """
        self._paused.set()
        logger.debug("TTS paused")

    def resume(self) -> None:
        """Resume TTS queue processing after pause."""
        self._paused.clear()
        logger.debug("TTS resumed")

    def clear_queue(self) -> int:
        """
        Clear all pending TTS messages from the queue.

        Returns:
            Number of messages cleared
        """
        count = 0
        try:
            while True:
                self.speak_queue.get_nowait()
                count += 1
        except queue.Empty:
            pass

        if count > 0:
            logger.info(f"Cleared {count} pending TTS messages")
        return count

    def wait_for_completion(self, timeout: float = 10.0) -> bool:
        """
        Wait until the current TTS message finishes speaking.

        Args:
            timeout: Maximum time to wait in seconds

        Returns:
            True if completed, False if timed out
        """
        if not self._speaking.is_set():
            # Not currently speaking
            return True

        logger.debug("Waiting for TTS to complete...")
        result = self._speaking_done.wait(timeout=timeout)
        if result:
            logger.debug("TTS completed")
        else:
            logger.warning(f"TTS wait timed out after {timeout}s")
        return result

    def is_speaking(self) -> bool:
        """Check if TTS is currently speaking."""
        return self._speaking.is_set()

    def stop_current_audio(self) -> None:
        """
        Immediately stop currently playing audio.

        Terminates the afplay process if one is running.
        """
        if self._current_process and self._current_process.poll() is None:
            try:
                self._current_process.terminate()
                self._current_process.wait(
                    timeout=0.5
                )  # Wait briefly for clean termination
                logger.info("Stopped current audio playback")
            except Exception as e:
                logger.warning(f"Error terminating audio process: {e}")
                try:
                    self._current_process.kill()  # Force kill if terminate fails
                except Exception:
                    pass
            finally:
                self._current_process = None
                self._cleanup_temp_file()

    def cancel_all(self) -> int:
        """
        Stop current audio AND clear the queue.

        Use this when context changes (e.g., user returns to on_task)
        to immediately silence all pending and current speech.

        Returns:
            Number of messages cleared from queue
        """
        # First stop any currently playing audio
        self.stop_current_audio()

        # Then clear the queue
        cleared = self.clear_queue()

        # Reset speaking state
        self._speaking.clear()
        self._speaking_done.set()

        logger.info(
            f"Cancelled all TTS: stopped audio and cleared {cleared} queued messages"
        )
        return cleared

    def _cleanup_temp_file(self) -> None:
        """Clean up temporary audio file."""
        if self._current_temp_file:
            try:
                os.unlink(self._current_temp_file)
            except Exception:
                pass
            self._current_temp_file = None

    def _speak_elevenlabs(self, text: str):
        """Speak using ElevenLabs API (v2) optimized for maximum speed."""
        try:
            # Configure for maximum speed if optimization is enabled
            if self.optimize_for_speed:
                # Ultra-fast settings for minimum latency
                model_id = "eleven_turbo_v2_5"  # Fastest model
                output_format = "mp3_22050_32"  # Lowest quality, fastest
                optimize_streaming_latency = 4  # Maximum streaming optimization
            else:
                # Default balanced settings
                model_id = self.model_id
                output_format = "mp3_44100_128"  # Higher quality
                optimize_streaming_latency = 2  # Standard streaming

            # ElevenLabs SDK signatures vary across versions. Only pass kwargs
            # supported by the installed client so we don't fall back to pyttsx3.
            convert_kwargs = {
                "text": text,
                "voice_id": self.voice_id,
                "model_id": model_id,
                "output_format": output_format,
            }
            try:
                accepted_kwargs = set(
                    inspect.signature(self.client.text_to_speech.convert).parameters
                )
            except (TypeError, ValueError):
                accepted_kwargs = set()
            if (
                optimize_streaming_latency is not None
                and (
                    not accepted_kwargs
                    or "optimize_streaming_latency" in accepted_kwargs
                )
            ):
                convert_kwargs["optimize_streaming_latency"] = (
                    optimize_streaming_latency
                )

            # Generate audio using v2 API
            audio_gen = self.client.text_to_speech.convert(**convert_kwargs)

            # Convert generator to bytes
            audio_bytes = b"".join(audio_gen)

            # Save to temp file and play with afplay (macOS)
            with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as f:
                f.write(audio_bytes)
                temp_file = f.name

            # Track temp file for cleanup
            self._current_temp_file = temp_file

            # Play the audio (afplay: -r is *playback rate* 1.0=normal, not sample rate;
            # -q requires an explicit quality value and only matters for rate-scaled playback.)
            afplay_args: list[str] = ["afplay", temp_file]
            if self.optimize_for_speed:
                # Slightly faster playback at low quality for lower latency.
                afplay_args = ["afplay", "-r", "1.12", "-q", "0", temp_file]
            
            self._current_process = subprocess.Popen(afplay_args)
            self._current_process.wait()  # Block until done or terminated

            if self._current_process.returncode not in (0, None):
                raise RuntimeError(
                    f"afplay exited with code {self._current_process.returncode}"
                )

            # Clean up temp file
            self._cleanup_temp_file()

            logger.debug(f"Spoke (ElevenLabs {'ultra-fast' if self.optimize_for_speed else 'optimized'}): {text[:50]}")
        except Exception as e:
            logger.error(f"Error speaking with ElevenLabs: {e}")
            self._current_process = None
            self._cleanup_temp_file()
            # Fallback to pyttsx3 if available
            if self.engine:
                try:
                    logger.info("Falling back to pyttsx3...")
                    self.engine.say(text)
                    self.engine.runAndWait()
                except Exception as e2:
                    logger.error(f"Fallback TTS also failed: {e2}")

    def _speak_pyttsx3(self, text: str):
        """Speak using pyttsx3."""
        if not self.engine:
            logger.warning(f"TTS engine not available, would speak: {text[:50]}")
            return

        try:
            self.engine.say(text)
            self.engine.runAndWait()
            logger.debug(f"Spoke (pyttsx3): {text[:50]}")
        except Exception as e:
            logger.error(f"Error speaking text: {e}")

    def _worker_loop(self):
        """Worker loop that processes speak queue."""
        logger.info("TTS worker loop started")

        while not self.stop_event.is_set():
            try:
                # Check if paused
                if self._paused.is_set():
                    self.stop_event.wait(timeout=0.1)
                    continue

                # Wait for text with timeout to check stop event
                try:
                    text = self.speak_queue.get(timeout=0.5)
                except queue.Empty:
                    continue

                # Check pause again after getting text (might have been paused while waiting)
                if self._paused.is_set():
                    # Put it back and wait
                    self.speak_queue.put(text)
                    continue

                # Mark as speaking
                self._speaking.set()
                self._speaking_done.clear()

                try:
                    # Duck music before speaking, restore after (always, even on error)
                    if self._ducker:
                        self._ducker.duck()
                    try:
                        if self.provider == "elevenlabs" and self.client:
                            self._speak_elevenlabs(text)
                        else:
                            self._speak_pyttsx3(text)
                    finally:
                        if self._ducker:
                            self._ducker.restore()
                finally:
                    # Mark as done speaking
                    self._speaking.clear()
                    self._speaking_done.set()

            except Exception as e:
                logger.error(f"Error in TTS worker loop: {e}")
                self._speaking.clear()
                self._speaking_done.set()

        logger.info("TTS worker loop ended")

    def get_status(self) -> Dict[str, Any]:
        """
        Get current TTS service status.

        Returns:
            Status dictionary
        """
        return {
            "provider": self.provider,
            "voice_id": self.voice_id,
            "model_id": self.model_id if self.provider == "elevenlabs" else None,
            "elevenlabs_available": ELEVENLABS_AVAILABLE,
            "api_key_set": bool(self.api_key),
            "worker_running": self.worker_thread is not None
            and self.worker_thread.is_alive(),
        }


def get_elevenlabs_voices_for_ui() -> List[Dict[str, str]]:
    """
    Get simplified voice list for UI selection.

    Returns:
        List of voice options
    """
    voices = []

    # Add recommended voices first
    for personality, voice_info in RECOMMENDED_VOICES.items():
        voices.append(
            {
                "id": voice_info["voice_id"],
                "name": f"{voice_info['name']} (Recommended for {personality})",
                "personality": personality,
            }
        )

    return voices
