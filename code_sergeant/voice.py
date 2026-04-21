"""Voice recording, transcription, wake word detection, and LLM interaction."""

import json
import logging
import re
import threading
import time
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional

import numpy as np
import ollama
import sounddevice as sd

try:
    import whisper
except ImportError:
    whisper = None
try:
    from faster_whisper import WhisperModel
except ImportError:
    WhisperModel = None
logger = logging.getLogger("code_sergeant.voice")


def list_input_devices() -> List[Dict[str, Any]]:
    """Return available PortAudio input devices."""
    try:
        devices = sd.query_devices()
    except Exception as e:
        logger.warning(f"Failed to enumerate audio devices: {e}")
        return []

    default_input_index = None
    try:
        default_device = sd.default.device
        if isinstance(default_device, (list, tuple)) and len(default_device) >= 1:
            candidate = default_device[0]
            if isinstance(candidate, int) and candidate >= 0:
                default_input_index = candidate
    except Exception:
        pass

    input_devices: List[Dict[str, Any]] = []
    for index, device in enumerate(devices):
        max_input_channels = int(device.get("max_input_channels", 0) or 0)
        if max_input_channels <= 0:
            continue
        input_devices.append(
            {
                "index": index,
                "name": device.get("name", f"Input {index}"),
                "max_input_channels": max_input_channels,
                "default_samplerate": device.get("default_samplerate"),
                "is_default": index == default_input_index,
            }
        )

    return input_devices


def resolve_input_device(
    selected_device_name: Optional[str],
) -> tuple[Optional[int], Optional[Dict[str, Any]]]:
    """Resolve a configured input-device name to a live PortAudio device."""
    devices = list_input_devices()

    if selected_device_name:
        for device in devices:
            if device["name"] == selected_device_name:
                return int(device["index"]), device
        logger.warning(
            f"Configured input device not found: {selected_device_name}. Falling back to default input."
        )

    for device in devices:
        if device.get("is_default"):
            return int(device["index"]), device

    return None, None


def get_input_device_recording_kwargs(
    selected_device_name: Optional[str],
) -> tuple[Dict[str, Any], Optional[Dict[str, Any]]]:
    """Build `sounddevice.rec()` kwargs for the selected input device."""
    device_index, device_info = resolve_input_device(selected_device_name)
    if device_index is None:
        return {}, None
    return {"device": device_index}, device_info


class WhisperBackend:
    """Small adapter over whisper/openai-whisper and faster-whisper."""

    def __init__(self, backend: str, model: Any):
        self.backend = backend
        self.model = model

    def transcribe(
        self,
        audio_data: np.ndarray,
        language: str = "en",
        beam_size: int = 5,
        vad_filter: bool = True,
        vad_parameters: Optional[Dict[str, Any]] = None,
        no_speech_threshold: float = 0.6,
    ):
        if self.backend == "whisper":
            result = self.model.transcribe(
                audio_data,
                language=language,
                fp16=False,
            )
            text = (result.get("text") or "").strip()
            segments = []
            if text:
                segments = [type("Seg", (), {"text": text, "start": 0.0, "end": 0.0})()]
            return segments, {}

        return self.model.transcribe(
            audio_data,
            language=language,
            beam_size=beam_size,
            vad_filter=vad_filter,
            vad_parameters=vad_parameters or {},
            no_speech_threshold=no_speech_threshold,
        )


def load_whisper_backend(model_size: str, purpose: str) -> Optional[WhisperBackend]:
    """Load any supported local speech model backend."""
    if WhisperModel is not None:
        try:
            model = WhisperModel(model_size, device="cpu", compute_type="int8")
            logger.info(f"{purpose}: faster-whisper {model_size} model loaded")
            return WhisperBackend("faster_whisper", model)
        except Exception as e:
            logger.error(f"Failed to load faster-whisper {model_size} model: {e}")

    if whisper is not None:
        try:
            model = whisper.load_model(model_size, device="cpu")
            logger.info(f"{purpose}: whisper {model_size} model loaded")
            return WhisperBackend("whisper", model)
        except Exception as e:
            logger.error(f"Failed to load whisper {model_size} model: {e}")

    logger.warning(
        f"{purpose}: no speech model backend available; install faster-whisper or whisper"
    )
    return None


# Voice command patterns
COMMAND_PATTERNS = {
    "start_session": [
        r"start\s+(?:a\s+)?session\s+(?:for\s+|to\s+|on\s+)?(.+)",
        r"begin\s+(?:a\s+)?session\s+(?:for\s+|to\s+|on\s+)?(.+)",
        r"let'?s\s+(?:start|begin)\s+(?:working\s+on\s+)?(.+)",
    ],
    "end_session": [
        r"(?:end|stop|finish|close)\s+(?:the\s+)?session",
        r"i'?m\s+done",
        r"session\s+(?:over|complete|finished)",
    ],
    "pause_session": [
        r"pause\s+(?:the\s+)?session",
        r"take\s+a\s+break",
        r"pause",
    ],
    "resume_session": [
        r"resume\s+(?:the\s+)?session",
        r"continue\s+(?:the\s+)?session",
        r"i'?m\s+back",
    ],
    "change_goal": [
        r"change\s+(?:my\s+)?goal\s+to\s+(.+)",
        r"(?:new|update)\s+goal[:\s]+(.+)",
        r"i'?m\s+(?:now\s+)?working\s+on\s+(.+)",
    ],
    "save_note": [
        r"(?:save|remember|note)[:\s]+(.+)",
        r"save\s+(?:this\s+)?(?:for\s+)?later[:\s]+(.+)",
        r"remind\s+me[:\s]+(.+)",
        r"i\s+just\s+thought\s+of[:\s]+(.+)",
        # Natural "take a note" patterns
        r"i\s+(?:want\s+to\s+)?take\s+a\s+note[:\s,]*(.+)",
        r"take\s+a\s+note[:\s,]*(.+)",
        r"(?:make|write)\s+a\s+note[:\s,]*(.+)",
        r"i\s+want\s+to\s+note[:\s,]*(.+)",
        r"note\s+(?:that\s+)?(.+)",
        r"jot\s+(?:down\s+)?(.+)",
        r"write\s+(?:down\s+)?(.+)",
    ],
    "report_distraction": [
        r"i'?m\s+(?:getting\s+)?distracted\s+(?:by|because)[:\s]+(.+)",
        r"distracted[:\s]+(.+)",
    ],
    "report_phone": [
        r"i'?m\s+on\s+(?:my\s+)?phone",
        r"phone\s+distraction",
        r"was\s+on\s+(?:my\s+)?phone",
    ],
    "start_pomodoro": [
        r"start\s+(?:a\s+)?pomodoro",
        r"start\s+(?:the\s+)?timer",
        r"pomodoro\s+start",
    ],
    "pause_pomodoro": [
        r"pause\s+(?:the\s+)?(?:pomodoro|timer)",
    ],
    "stop_pomodoro": [
        r"stop\s+(?:the\s+)?(?:pomodoro|timer)",
        r"cancel\s+(?:the\s+)?(?:pomodoro|timer)",
    ],
    "skip_pomodoro": [
        r"skip\s+(?:the\s+)?(?:pomodoro|timer|break)",
        r"next\s+(?:pomodoro|phase)",
    ],
    "status": [
        r"(?:what'?s?\s+)?(?:my\s+)?status",
        r"how\s+(?:am\s+)?i\s+doing",
        r"progress\s+(?:report|update)",
    ],
}


class VoiceCommand:
    """Represents a parsed voice command."""

    def __init__(
        self, command_type: str, args: Optional[str] = None, raw_text: str = ""
    ):
        self.command_type = command_type
        self.args = args
        self.raw_text = raw_text
        self.timestamp = datetime.now()

    def __repr__(self):
        return f"VoiceCommand({self.command_type}, args={self.args})"


class WakeWordDetector:
    """Detects wake words using continuous audio streaming and Whisper."""

    def __init__(
        self,
        wake_words: List[str],
        note_wake_words: Optional[List[str]] = None,
        sample_rate: int = 16000,
        chunk_duration: float = 2.0,
        sensitivity: float = 0.5,
        input_device_name: Optional[str] = None,
        on_wake_word: Optional[Callable[[str], None]] = None,
        on_note_taking: Optional[Callable[[str], None]] = None,
    ):
        """
        Initialize wake word detector.

        Args:
            wake_words: Wake words for general voice interaction (e.g., ["hey sergeant"]).
            note_wake_words: Dedicated wake words that go straight to note-taking
                (e.g., ["take note sergeant"]). Checked before wake_words so a user
                can have overlapping phrases without ambiguity.
            sample_rate: Audio sample rate.
            chunk_duration: Duration of each audio chunk in seconds.
            sensitivity: Detection sensitivity (0.0-1.0).
            on_wake_word: Callback when a general wake word is detected.
            on_note_taking: Callback when a note wake word is detected.
        """
        self.wake_words = [w.lower() for w in wake_words]
        self.note_wake_words = [w.lower() for w in (note_wake_words or [])]
        self.sample_rate = sample_rate
        self.chunk_duration = chunk_duration
        self.sensitivity = sensitivity
        self.input_device_name = input_device_name
        self.on_wake_word = on_wake_word
        self.on_note_taking = on_note_taking

        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()
        self._recording_kwargs: Dict[str, Any] = {}

        # Initialize speech model (tiny for speed in wake word detection)
        self.whisper_model = load_whisper_backend("tiny", "Wake word detector")

    @property
    def is_available(self) -> bool:
        return self.whisper_model is not None

    @property
    def is_running(self) -> bool:
        return self._running

    def set_wake_words(self, wake_words: List[str]):
        """Update general wake words."""
        self.wake_words = [w.lower() for w in wake_words]
        logger.info(f"Wake words updated: {self.wake_words}")

    def set_note_wake_words(self, note_wake_words: List[str]):
        """Update the dedicated note-taking wake words."""
        self.note_wake_words = [w.lower() for w in note_wake_words]
        logger.info(f"Note wake words updated: {self.note_wake_words}")

    def set_input_device(self, input_device_name: Optional[str]):
        """Update the configured input device."""
        self.input_device_name = input_device_name

    def start(self) -> bool:
        """Start wake word detection in background thread."""
        if self._running:
            logger.warning("Wake word detector already running")
            return True

        if not self.whisper_model:
            logger.error(
                "Cannot start wake word detection: Whisper model not available"
            )
            return False

        self._recording_kwargs, device_info = get_input_device_recording_kwargs(
            self.input_device_name
        )
        if device_info:
            logger.info(f"Wake word detector using input device: {device_info['name']}")
        elif self.input_device_name:
            logger.warning(
                "Wake word detector could not resolve the configured microphone; "
                "PortAudio default input will be used if available"
            )
        else:
            logger.info("Wake word detector using the system default input device")

        self._stop_event.clear()
        self._running = True
        self._thread = threading.Thread(target=self._detection_loop, daemon=True)
        self._thread.start()
        logger.info(
            f"Wake word detection started. "
            f"Commands: {self.wake_words}  Notes: {self.note_wake_words}"
        )
        return True

    def stop(self):
        """Stop wake word detection."""
        if not self._running:
            return

        self._stop_event.set()
        self._running = False

        # Don't try to join if we're stopping from within the detection thread itself
        # (this happens when stop is called from a wake word callback)
        if self._thread and self._thread is not threading.current_thread():
            self._thread.join(timeout=3.0)

        logger.info("Wake word detection stopped")

    # ---------------------------------------------------------------------------
    # Music vs. speech discrimination
    # ---------------------------------------------------------------------------

    # Minimum energy coefficient of variation to be considered speech-like.
    # Speech is bursty (words + pauses); music is more sustained.
    _SPEECH_ENERGY_CV_MIN = 0.25

    # Maximum spectral flatness in the voice band (300-3 400 Hz).
    # Values near 0 = very tonal (music instrument / clean note).
    # Values near 1 = noise-like.  Speech sits roughly in 0.05-0.50.
    _MUSIC_FLATNESS_MAX = 0.05

    # Maximum no_speech_prob accepted per Whisper segment.
    # faster-whisper exposes this; we discard segments the model itself
    # is unsure about.
    _MAX_NO_SPEECH_PROB = 0.60

    def _is_speech_like(self, audio: np.ndarray) -> bool:
        """
        Quick pre-Whisper heuristic: return True if the chunk looks like
        speech rather than music or ambient sound.

        Two checks are combined — both must signal "music" to reject the
        chunk, so the filter errs on the side of not missing real commands.
        """
        if len(audio) < self.sample_rate * 0.1:  # too short to analyse
            return True

        # ── 1. Energy burstiness ────────────────────────────────────────────
        # Split into 50 ms frames and compare RMS variance to mean.
        frame_len = max(1, int(self.sample_rate * 0.05))
        frames = [
            audio[i : i + frame_len]
            for i in range(0, len(audio) - frame_len, frame_len)
        ]
        rms = np.array([np.sqrt(np.mean(f**2)) for f in frames])
        mean_rms = rms.mean()
        if mean_rms < 1e-8:
            return False  # effectively silent
        energy_cv = rms.std() / mean_rms  # coefficient of variation

        # ── 2. Spectral flatness in voice band ─────────────────────────────
        fft_mag = np.abs(np.fft.rfft(audio))
        freqs = np.fft.rfftfreq(len(audio), 1.0 / self.sample_rate)
        mask = (freqs >= 300) & (freqs <= 3400)
        band = fft_mag[mask]
        if len(band) == 0:
            flatness = 0.5
        else:
            eps = 1e-10
            geo = np.exp(np.mean(np.log(band + eps)))
            arith = band.mean()
            flatness = geo / (arith + eps)

        # Reject only when BOTH checks agree it's music-like.
        is_tonal = flatness < self._MUSIC_FLATNESS_MAX
        is_sustained = energy_cv < self._SPEECH_ENERGY_CV_MIN
        if is_tonal and is_sustained:
            logger.debug(
                f"Audio rejected as music-like: flatness={flatness:.3f}, energy_cv={energy_cv:.3f}"
            )
            return False

        return True

    def _transcribe_with_confidence_filter(self, audio: np.ndarray) -> str:
        """
        Transcribe a chunk and discard segments that Whisper itself rates as
        low-confidence speech (no_speech_prob too high).

        Returns the filtered transcript (may be empty string).
        """
        # Use a strict no_speech_threshold so the model itself rejects music/
        # silence segments before we even see them.  The post-hoc per-segment
        # check below catches anything the model-level threshold misses.
        segments, _ = self.whisper_model.transcribe(
            audio,
            language="en",
            beam_size=1,
            vad_filter=True,
            no_speech_threshold=0.5,  # stricter than the default 0.6
        )

        parts = []
        for seg in segments:
            # faster-whisper exposes no_speech_prob; vanilla whisper does not.
            no_speech_prob = getattr(seg, "no_speech_prob", 0.0)
            if no_speech_prob > self._MAX_NO_SPEECH_PROB:
                logger.debug(
                    f"Segment discarded (no_speech_prob={no_speech_prob:.2f}): '{seg.text.strip()}'"
                )
                continue
            parts.append(seg.text)

        return " ".join(parts).lower().strip()

    # ---------------------------------------------------------------------------

    def _detection_loop(self):
        """Main detection loop."""
        chunk_samples = int(self.chunk_duration * self.sample_rate)

        while not self._stop_event.is_set():
            try:
                audio_data = sd.rec(
                    chunk_samples,
                    samplerate=self.sample_rate,
                    channels=1,
                    dtype=np.float32,
                    **self._recording_kwargs,
                )
                sd.wait()

                if self._stop_event.is_set():
                    break

                audio_data = audio_data.flatten()

                # Skip chunks that are too quiet to contain speech
                if np.abs(audio_data).max() < 0.01:
                    continue

                # Skip chunks that look like music rather than speech
                if not self._is_speech_like(audio_data):
                    continue

                transcript = self._transcribe_with_confidence_filter(audio_data)
                if not transcript:
                    continue

                logger.debug(f"Wake word check: '{transcript}'")

                # Note wake words are checked first — they take priority over
                # general wake words so there's no ambiguity between the two.
                matched = False
                for note_ww in self.note_wake_words:
                    if self._matches_wake_word(transcript, note_ww):
                        logger.info(f"Note wake word '{note_ww}' in '{transcript}'")
                        if self.on_note_taking:
                            self.on_note_taking(note_ww)
                        time.sleep(1.0)
                        matched = True
                        break

                if not matched:
                    for wake_word in self.wake_words:
                        if self._matches_wake_word(transcript, wake_word):
                            logger.info(f"Wake word '{wake_word}' in '{transcript}'")
                            if self.on_wake_word:
                                self.on_wake_word(wake_word)
                            time.sleep(1.0)
                            break

            except sd.PortAudioError as e:
                logger.error(f"Audio error in wake word detection: {e}")
                time.sleep(1.0)
            except Exception as e:
                logger.error(f"Error in wake word detection: {e}")
                time.sleep(0.5)

    def _matches_wake_word(self, transcript: str, wake_word: str) -> bool:
        """
        Check if transcript contains the full wake phrase.

        The detector may use fuzzy matching for individual words, but every
        word in the configured wake phrase must be present in order. This
        prevents "sergeant" by itself from activating "hey sergeant".

        Args:
            transcript: Transcribed text
            wake_word: Wake word to match

        Returns:
            True if match found
        """
        normalized_transcript = self._normalize_phrase(transcript)
        normalized_wake_word = self._normalize_phrase(wake_word)
        if not normalized_transcript or not normalized_wake_word:
            return False

        transcript_words = normalized_transcript.split()
        wake_words_parts = normalized_wake_word.split()

        # Exact full-phrase match, ignoring punctuation/case.
        if self._contains_word_sequence(transcript_words, wake_words_parts):
            return True

        # Handle common full-phrase transcription variations.
        variations = self._get_wake_word_variations(wake_word)
        for variation in variations:
            variation_words = self._normalize_phrase(variation).split()
            if variation_words and self._contains_word_sequence(
                transcript_words, variation_words
            ):
                return True

        # Fuzzy matching using word-level similarity. Every word must match.
        if len(wake_words_parts) >= 2:
            for i in range(len(transcript_words) - len(wake_words_parts) + 1):
                matches = 0
                for j, wake_part in enumerate(wake_words_parts):
                    transcript_part = (
                        transcript_words[i + j] if i + j < len(transcript_words) else ""
                    )
                    # Check similarity
                    if self._word_similarity(transcript_part, wake_part) >= (
                        0.6 + self.sensitivity * 0.3
                    ):
                        matches += 1

                if matches == len(wake_words_parts):
                    logger.debug(
                        f"Fuzzy match: '{transcript}' matched '{wake_word}' "
                        f"with {matches}/{len(wake_words_parts)} parts"
                    )
                    return True

        return False

    def _normalize_phrase(self, phrase: str) -> str:
        """Normalize a transcribed phrase for wake-word matching."""
        return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", phrase.lower())).strip()

    def _contains_word_sequence(
        self, transcript_words: List[str], phrase_words: List[str]
    ) -> bool:
        """Return True when phrase_words appears contiguously in transcript_words."""
        if not phrase_words or len(phrase_words) > len(transcript_words):
            return False

        phrase_len = len(phrase_words)
        for i in range(len(transcript_words) - phrase_len + 1):
            if transcript_words[i : i + phrase_len] == phrase_words:
                return True
        return False

    def _word_similarity(self, word1: str, word2: str) -> float:
        """
        Calculate similarity between two words (0.0 to 1.0).

        Uses a simple character-based similarity metric.
        """
        if word1 == word2:
            return 1.0
        if not word1 or not word2:
            return 0.0

        # Normalize
        word1 = word1.lower().strip()
        word2 = word2.lower().strip()

        if word1 == word2:
            return 1.0

        # Check if one contains the other
        if word1 in word2 or word2 in word1:
            return 0.8

        # Simple Levenshtein-like ratio
        len1, len2 = len(word1), len(word2)
        max_len = max(len1, len2)

        # Count matching characters at same positions
        matches = sum(1 for c1, c2 in zip(word1, word2) if c1 == c2)

        # Also count matching characters overall
        common_chars = sum(1 for c in set(word1) if c in word2)

        # Weighted average
        position_score = matches / max_len if max_len > 0 else 0
        char_score = (
            common_chars / max(len(set(word1)), len(set(word2))) if max_len > 0 else 0
        )

        return position_score * 0.6 + char_score * 0.4

    def _get_wake_word_variations(self, wake_word: str) -> List[str]:
        """Get common variations of a wake word."""
        variations = [wake_word]

        # Common variations for "hey X"
        if wake_word.startswith("hey "):
            name = wake_word[4:]
            variations.extend(
                [
                    f"hey {name}",
                    f"hay {name}",
                ]
            )

            # Handle common mishearings of "sergeant"
            if "sergeant" in name:
                base = name.replace("sergeant", "")
                variations.extend(
                    [
                        f"hey{base}sargent",
                        f"hey {base}sargent",
                        f"hey {base}sargeant",
                        f"hey {base}sergent",
                        f"hey {base}serjeant",
                        f"hay {base}sargent",
                        f"hay {base}sargeant",
                        f"hay {base}sergent",
                        f"hay {base}serjeant",
                    ]
                )

        return variations


class VoiceCommandParser:
    """Parses voice input into commands."""

    def __init__(
        self,
        ollama_model: str = "llama3.2",
        ollama_base_url: str = "http://localhost:11434",
    ):
        """
        Initialize command parser.

        Args:
            ollama_model: Ollama model for complex command parsing
            ollama_base_url: Ollama API base URL
        """
        self.ollama_client = ollama.Client(host=ollama_base_url)
        self.ollama_model = ollama_model

    def parse(self, transcript: str) -> Optional[VoiceCommand]:
        """
        Parse transcript into a command.

        Args:
            transcript: Voice transcript

        Returns:
            VoiceCommand if recognized, None otherwise
        """
        transcript_lower = transcript.lower().strip()

        # Try pattern matching first
        for command_type, patterns in COMMAND_PATTERNS.items():
            for pattern in patterns:
                match = re.search(pattern, transcript_lower, re.IGNORECASE)
                if match:
                    args = match.group(1) if match.lastindex else None

                    # Special handling for save_note: if args is just punctuation or empty,
                    # treat as a request to start note-taking mode (return start_note_taking command)
                    if command_type == "save_note":
                        cleaned_args = (
                            re.sub(r"^[\s.,!?:;]+|[\s.,!?:;]+$", "", args or "").strip()
                            if args
                            else ""
                        )
                        if not cleaned_args:
                            # User said "take a note" without content - they want to dictate
                            logger.info(
                                f"Parsed command: start_note_taking (user wants to dictate)"
                            )
                            return VoiceCommand("start_note_taking", None, transcript)
                        args = cleaned_args

                    logger.info(f"Parsed command: {command_type} with args: {args}")
                    return VoiceCommand(command_type, args, transcript)

        # If no pattern match, try LLM parsing for complex commands
        return self._parse_with_llm(transcript)

    def _parse_with_llm(self, transcript: str) -> Optional[VoiceCommand]:
        """Parse command using LLM for complex/ambiguous input."""
        try:
            prompt = f"""Parse this voice command and output ONLY valid JSON.

Voice input: "{transcript}"

Possible commands:
- start_session: Start a focus session (args: goal)
- end_session: End the session
- pause_session: Pause the session
- resume_session: Resume the session
- change_goal: Change the goal (args: new goal)
- save_note: Save a note for later (args: note content)
- report_distraction: Report being distracted (args: reason)
- report_phone: Report phone usage
- start_pomodoro: Start pomodoro timer
- pause_pomodoro: Pause pomodoro
- stop_pomodoro: Stop pomodoro
- skip_pomodoro: Skip current phase
- status: Get status
- chat: General conversation (not a command)

Output JSON:
{{"command": "command_type", "args": "arguments or null"}}

If it's just general conversation, output:
{{"command": "chat", "args": null}}

JSON only:"""

            response = self.ollama_client.generate(
                model=self.ollama_model,
                prompt=prompt,
                format="json",
                options={"temperature": 0.1, "num_predict": 50},
            )

            raw = response.get("response", "").strip()
            result = json.loads(raw)

            command_type = result.get("command")
            args = result.get("args")

            if command_type and command_type != "chat":
                return VoiceCommand(command_type, args, transcript)

            return None

        except Exception as e:
            logger.warning(f"LLM command parsing failed: {e}")
            return None


class VoiceWorker:
    """Worker for handling voice input: record → transcribe → LLM → TTS."""

    def __init__(
        self,
        record_seconds: int = 3,
        sample_rate: int = 16000,
        ollama_model: str = "llama3.2",
        ollama_base_url: str = "http://localhost:11434",
        input_device_name: Optional[str] = None,
        tts_service=None,
        personality_manager=None,
    ):
        """
        Initialize voice worker.

        Args:
            record_seconds: Duration to record in seconds
            sample_rate: Audio sample rate
            ollama_model: Ollama model name
            ollama_base_url: Ollama API base URL
            tts_service: TTSService instance for speaking responses
            personality_manager: PersonalityManager for personality-aware responses
        """
        self.record_seconds = record_seconds
        self.sample_rate = sample_rate
        self.ollama_model = ollama_model
        self.input_device_name = input_device_name
        self.ollama_client = ollama.Client(host=ollama_base_url)
        self.tts_service = tts_service
        self.personality_manager = personality_manager

        # Command parser
        self.command_parser = VoiceCommandParser(ollama_model, ollama_base_url)

        # Initialize speech model (base model for accuracy)
        self.whisper_model = load_whisper_backend("base", "Voice worker")

    def set_input_device(self, input_device_name: Optional[str]) -> None:
        """Update the configured input device."""
        self.input_device_name = input_device_name

    def _get_recording_kwargs(
        self, purpose: str
    ) -> tuple[Dict[str, Any], Optional[Dict[str, Any]]]:
        """Resolve the active input device for a recording operation."""
        recording_kwargs, device_info = get_input_device_recording_kwargs(
            self.input_device_name
        )
        if device_info:
            logger.info(f"{purpose}: using input device: {device_info['name']}")
        elif self.input_device_name:
            logger.warning(
                f"{purpose}: configured microphone '{self.input_device_name}' was not found"
            )
        else:
            logger.info(f"{purpose}: using the system default input device")
        return recording_kwargs, device_info

    def record_and_process(
        self,
        goal: Optional[str] = None,
        current_activity: Optional[str] = None,
        parse_commands: bool = True,
    ) -> tuple[Optional[str], Optional[VoiceCommand]]:
        """
        Record audio, transcribe, optionally parse commands, get LLM response.

        Args:
            goal: Current session goal (for context)
            current_activity: Current activity (for context)
            parse_commands: Whether to try parsing as command

        Returns:
            Tuple of (transcript, command) - command may be None
        """
        # Announce recording start
        if self.tts_service:
            self.tts_service.speak("Listening")
            time.sleep(0.5)  # Brief pause after announcement

        # Record audio
        try:
            logger.info("Recording audio...")
            audio_data = self._record_audio()
            if audio_data is None:
                return None, None
        except Exception as e:
            logger.error(f"Recording failed: {e}")
            self._handle_mic_error(e)
            return None, None

        # Transcribe
        try:
            logger.info("Transcribing audio...")
            transcript = self._transcribe(audio_data)
            if not transcript:
                logger.warning("Empty transcription")
                return None, None
            logger.info(f"Transcribed: {transcript}")
        except Exception as e:
            logger.error(f"Transcription failed: {e}")
            return None, None

        # Try to parse as command
        command = None
        if parse_commands:
            command = self.command_parser.parse(transcript)
            if command:
                logger.info(f"Voice command detected: {command}")
                return transcript, command

        # Get LLM response for non-command input
        try:
            logger.info("Getting LLM response...")
            response = self._get_llm_response(transcript, goal, current_activity)
            if response:
                logger.info(f"LLM response: {response}")
                if self.tts_service:
                    self.tts_service.speak(response)
        except Exception as e:
            logger.error(f"LLM response failed: {e}")

        return transcript, command

    def _record_audio(self) -> Optional[np.ndarray]:
        """
        Record audio from microphone.

        Returns:
            Audio data as numpy array, or None on error
        """
        try:
            recording_kwargs, _ = self._get_recording_kwargs("Voice recording")
            # List available devices for debugging
            devices = sd.query_devices()
            logger.debug(f"Available audio devices: {len(devices)}")

            # Record audio
            audio_data = sd.rec(
                int(self.record_seconds * self.sample_rate),
                samplerate=self.sample_rate,
                channels=1,
                dtype=np.float32,
                **recording_kwargs,
            )
            sd.wait()  # Wait until recording is finished

            # Flatten from (samples, 1) to (samples,) for Whisper
            audio_data = audio_data.flatten()

            # Check audio level
            audio_level = np.abs(audio_data).max()
            audio_rms = np.sqrt(np.mean(audio_data**2))
            logger.info(
                f"Recorded {len(audio_data)} samples, peak level: {audio_level:.4f}, RMS: {audio_rms:.4f}"
            )

            if audio_level < 0.01:
                logger.warning(
                    "Audio level very low - microphone may not be capturing sound"
                )

            return audio_data

        except sd.PortAudioError as e:
            logger.error(f"PortAudio error (mic permission?): {e}")
            self._handle_mic_error(e)
            return None
        except Exception as e:
            logger.error(f"Recording error: {e}")
            return None

    def _transcribe(self, audio_data: np.ndarray) -> Optional[str]:
        """
        Transcribe audio using Whisper.

        Args:
            audio_data: Audio data as numpy array (must be 1D, float32)

        Returns:
            Transcribed text, or None on error
        """
        if not self.whisper_model:
            logger.error("Whisper model not available")
            return None

        try:
            # Ensure audio is the right format
            if audio_data.ndim > 1:
                audio_data = audio_data.flatten()

            # Ensure float32
            if audio_data.dtype != np.float32:
                audio_data = audio_data.astype(np.float32)

            logger.debug(
                f"Transcribing audio: shape={audio_data.shape}, dtype={audio_data.dtype}"
            )

            segments, info = self.whisper_model.transcribe(
                audio_data,
                language="en",
                beam_size=5,
                vad_filter=True,  # Enable voice activity detection
                vad_parameters=dict(min_silence_duration_ms=500),
            )

            # Collect all segments
            transcript_parts = []
            for segment in segments:
                logger.debug(
                    f"Segment: [{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}"
                )
                transcript_parts.append(segment.text)

            transcript = " ".join(transcript_parts).strip()

            if not transcript:
                logger.warning("No speech detected in audio")

            return transcript if transcript else None

        except Exception as e:
            logger.error(f"Transcription error: {e}", exc_info=True)
            return None

    def _get_llm_response(
        self,
        transcript: str,
        goal: Optional[str] = None,
        current_activity: Optional[str] = None,
    ) -> Optional[str]:
        """
        Get LLM response to user's voice input.

        Args:
            transcript: Transcribed user input
            goal: Current session goal
            current_activity: Current activity

        Returns:
            LLM response text, or None on error
        """
        # Build context
        context = ""
        if goal:
            context += f"User's current goal: {goal}\n"
        if current_activity:
            context += f"Current activity: {current_activity}\n"

        # Get personality context
        personality_desc = (
            "You are Code Sergeant, a focus assistant helping the user stay on task."
        )
        if self.personality_manager:
            profile = self.personality_manager.profile
            personality_desc = f"You are {profile.wake_word_name.title()}, a focus assistant. {profile.description}"

        prompt = f"""{personality_desc}

{context}

User said: "{transcript}"

Respond briefly and in character. Keep it short (1-2 sentences max). Be encouraging but firm if they're off track.

Response:"""

        try:
            response = self.ollama_client.generate(
                model=self.ollama_model,
                prompt=prompt,
                options={
                    "temperature": 0.7,
                    "num_predict": 100,  # Limit response length
                },
            )

            return response.get("response", "").strip()

        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            return None

    def _handle_mic_error(self, error: Exception):
        """Handle microphone permission errors gracefully."""
        error_str = str(error).lower()
        if "permission" in error_str or "denied" in error_str:
            logger.error("Microphone permission denied")
            # Alert will be shown by UI
            raise PermissionError(
                "Microphone access denied. Go to System Settings → "
                "Privacy & Security → Microphone and enable Code Sergeant."
            )
        else:
            logger.error(f"Microphone error: {error}")
            raise


def run_voice_worker(
    voice_worker: VoiceWorker,
    goal: Optional[str],
    current_activity: Optional[str],
    event_queue,
):
    """
    Run voice worker in a thread.

    Args:
        voice_worker: VoiceWorker instance
        goal: Current goal
        current_activity: Current activity string
        event_queue: Event queue to emit events to
    """
    try:
        transcript, command = voice_worker.record_and_process(goal, current_activity)

        if command:
            # Emit command event
            event_queue.put(
                {
                    "type": "voice_command",
                    "command": command.command_type,
                    "args": command.args,
                    "transcript": transcript,
                    "timestamp": time.time(),
                }
            )
        elif transcript:
            # Emit transcript event
            event_queue.put(
                {
                    "type": "voice_transcript",
                    "transcript": transcript,
                    "timestamp": time.time(),
                }
            )
    except PermissionError as e:
        # Re-raise permission errors so UI can handle them
        raise
    except Exception as e:
        logger.error(f"Voice worker error: {e}")
        event_queue.put(
            {"type": "error_event", "message": f"Voice processing error: {e}"}
        )
