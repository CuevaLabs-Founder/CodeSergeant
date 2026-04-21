"""Unit tests for voice wake-word matching."""

import os
import sys

import pytest

sys.path.insert(
    0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

from code_sergeant.voice import WakeWordDetector  # noqa: E402


def make_detector(sensitivity: float = 0.5) -> WakeWordDetector:
    """Build a WakeWordDetector shell without loading Whisper."""
    detector = WakeWordDetector.__new__(WakeWordDetector)
    detector.sensitivity = sensitivity
    return detector


@pytest.mark.unit
class TestWakeWordMatching:
    """Regression coverage for full-phrase wake-word matching."""

    def test_requires_full_hey_sergeant_phrase(self):
        detector = make_detector()

        assert detector._matches_wake_word("hey sergeant", "hey sergeant") is True
        assert detector._matches_wake_word("hey, sergeant.", "hey sergeant") is True
        assert detector._matches_wake_word("sergeant", "hey sergeant") is False
        assert (
            detector._matches_wake_word("the sergeant said focus", "hey sergeant")
            is False
        )
        assert detector._matches_wake_word("hey", "hey sergeant") is False

    def test_allows_full_phrase_transcription_variants(self):
        detector = make_detector()

        assert detector._matches_wake_word("hay sergeant", "hey sergeant") is True
        assert detector._matches_wake_word("hey sargent", "hey sergeant") is True
        assert detector._matches_wake_word("sargent", "hey sergeant") is False

    def test_note_wake_word_requires_every_word(self):
        detector = make_detector()

        assert (
            detector._matches_wake_word("take note sergeant", "take note sergeant")
            is True
        )
        assert detector._matches_wake_word("take note", "take note sergeant") is False
        assert (
            detector._matches_wake_word("note sergeant", "take note sergeant") is False
        )
