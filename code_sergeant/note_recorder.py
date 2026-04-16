"""VAD-based voice note recorder."""
import logging
import subprocess
import threading
import time
from typing import Optional

import numpy as np
import sounddevice as sd

from .voice import WhisperBackend, get_input_device_recording_kwargs

logger = logging.getLogger("code_sergeant.note_recorder")

# Short system beep played between recording chunks — non-verbal so Whisper ignores it
_WARNING_SOUND = "/System/Library/Sounds/Funk.aiff"


class NoteRecorder:
    """
    Records a voice note using silence-based voice activity detection.

    Captures audio in 300 ms chunks. Recording stops when a configurable
    silence window follows detected speech, or when max_duration_seconds is
    reached. A double-beep warns the user when warn_seconds_remaining remain.

    The full audio is transcribed after recording ends. Returns None if fewer
    than min_words were captured (Whisper hallucination guard).
    """

    CHUNK_DURATION = 0.3  # seconds — tight enough for responsive silence detection

    def __init__(
        self,
        sample_rate: int = 16000,
        silence_threshold_seconds: float = 2.0,
        silence_rms_threshold: float = 0.015,
        max_duration_seconds: float = 60.0,
        warn_seconds_remaining: float = 15.0,
        min_words: int = 4,
        input_device_name: Optional[str] = None,
        whisper_model: Optional[WhisperBackend] = None,
    ):
        """
        Args:
            sample_rate: Audio sample rate (must match the Whisper model's expectation, 16 kHz).
            silence_threshold_seconds: Seconds of consecutive silence (after speech) that
                triggers auto-stop. Configurable via Settings slider.
            silence_rms_threshold: RMS amplitude below which a chunk is considered silent.
            max_duration_seconds: Hard timeout. Warning beep fires at
                max_duration_seconds - warn_seconds_remaining.
            warn_seconds_remaining: Seconds before timeout to play warning beep.
            min_words: Transcripts shorter than this are discarded (Whisper hallucination guard).
            input_device_name: PortAudio device name, or None for system default.
            whisper_model: Pre-loaded WhisperBackend instance (shared with the voice worker).
        """
        self.sample_rate = sample_rate
        self.silence_threshold_seconds = silence_threshold_seconds
        self.silence_rms_threshold = silence_rms_threshold
        self.max_duration_seconds = max_duration_seconds
        self.warn_seconds_remaining = warn_seconds_remaining
        self.min_words = min_words
        self.input_device_name = input_device_name
        self.whisper_model = whisper_model

    def record(self) -> Optional[str]:
        """
        Record a note until natural silence or timeout.

        Returns:
            Cleaned transcript string, or None if nothing substantial was captured.
        """
        if not self.whisper_model:
            logger.error("NoteRecorder: no Whisper model available")
            return None

        recording_kwargs, device_info = get_input_device_recording_kwargs(
            self.input_device_name
        )
        if device_info:
            logger.info(f"NoteRecorder: using device '{device_info['name']}'")
        else:
            logger.info("NoteRecorder: using system default input device")

        chunk_samples = int(self.CHUNK_DURATION * self.sample_rate)
        max_chunks = int(self.max_duration_seconds / self.CHUNK_DURATION)
        # Number of consecutive silent chunks required to stop
        silence_chunks_needed = max(1, round(self.silence_threshold_seconds / self.CHUNK_DURATION))
        # Chunk index at which the warning beep fires
        warn_at_chunk = max(
            0,
            int((self.max_duration_seconds - self.warn_seconds_remaining) / self.CHUNK_DURATION),
        )

        chunks: list[np.ndarray] = []
        silent_chunks = 0
        speech_detected = False
        warned = False

        logger.info(
            f"NoteRecorder: recording "
            f"(max {self.max_duration_seconds:.0f}s, "
            f"silence stop at {self.silence_threshold_seconds:.1f}s)"
        )

        try:
            for chunk_idx in range(max_chunks):
                # Warning fires synchronously between chunks so the beep sound
                # cannot bleed into the current recording chunk.
                if not warned and chunk_idx >= warn_at_chunk and speech_detected:
                    warned = True
                    self._play_warning_sync()

                chunk = sd.rec(
                    chunk_samples,
                    samplerate=self.sample_rate,
                    channels=1,
                    dtype=np.float32,
                    **recording_kwargs,
                )
                sd.wait()
                chunk = chunk.flatten()
                chunks.append(chunk)

                rms = float(np.sqrt(np.mean(chunk ** 2)))

                if rms >= self.silence_rms_threshold:
                    speech_detected = True
                    silent_chunks = 0
                elif speech_detected:
                    silent_chunks += 1
                    logger.debug(
                        f"NoteRecorder: silence chunk {silent_chunks}/{silence_chunks_needed}"
                        f" (RMS={rms:.4f})"
                    )
                    if silent_chunks >= silence_chunks_needed:
                        logger.info("NoteRecorder: silence detected — stopping")
                        break

        except sd.PortAudioError as e:
            logger.error(f"NoteRecorder: PortAudio error: {e}")
            if not speech_detected:
                return None
        except Exception as e:
            logger.error(f"NoteRecorder: recording error: {e}")
            if not speech_detected:
                return None

        if not speech_detected:
            logger.warning("NoteRecorder: no speech detected in recording")
            return None

        full_audio = np.concatenate(chunks)
        duration = len(full_audio) / self.sample_rate
        logger.info(f"NoteRecorder: transcribing {duration:.1f}s of audio")

        transcript = self._transcribe(full_audio)
        if not transcript:
            logger.warning("NoteRecorder: empty transcript")
            return None

        word_count = len(transcript.split())
        if word_count < self.min_words:
            logger.warning(
                f"NoteRecorder: only {word_count} word(s) captured "
                f"(min {self.min_words}) — discarding"
            )
            return None

        logger.info(f"NoteRecorder: captured {word_count} words")
        return transcript

    def _transcribe(self, audio: np.ndarray) -> Optional[str]:
        """Transcribe a numpy audio array using the faster-whisper backend."""
        try:
            segments, _ = self.whisper_model.transcribe(
                audio,
                language="en",
                beam_size=5,
                vad_filter=True,
                vad_parameters={"min_silence_duration_ms": 300},
            )
            text = " ".join(seg.text for seg in segments).strip()
            return text or None
        except Exception as e:
            logger.error(f"NoteRecorder: transcription error: {e}")
            return None

    def _play_warning_sync(self) -> None:
        """
        Play two short beeps synchronously between recording chunks.

        Called in the recording loop BEFORE sd.rec() so the beep cannot
        overlap with an active recording window.
        """
        try:
            for _ in range(2):
                subprocess.run(
                    ["afplay", _WARNING_SOUND],
                    check=False,
                    timeout=2,
                )
                time.sleep(0.15)
        except Exception as e:
            logger.debug(f"NoteRecorder: warning sound error: {e}")
