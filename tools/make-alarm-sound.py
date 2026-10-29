#!/usr/bin/python3
"""Writes data/alarm.wav, the sound the timer and alarm clock ring with: a calm
C-major bell phrase (C, E, G, C, G, E), three times, 8 seconds, mono 16-bit at
22.05 kHz (about 350 KB). Made only from sine waves with a soft attack and a
bell-like fade, so it can be remade and nothing in it comes from anywhere else.
The alarm clock repeats it for a few minutes (bin/timer).
    python3 tools/make-alarm-sound.py"""
import math
import os
import struct
import wave

SAMPLE_RATE = 22050
DURATION = 8.0
VOLUME = 0.32
NOTES = [523.25, 659.25, 783.99, 1046.50, 783.99, 659.25]
BEAT = 0.55
NOTE_LENGTH = 0.9


def main():
    events = []
    for repeat_start in (0.0, 3.3, 6.6):
        for i, frequency in enumerate(NOTES):
            start = repeat_start + i * BEAT
            if start < DURATION:
                events.append((start, frequency))

    frames = bytearray()
    for i in range(int(DURATION * SAMPLE_RATE)):
        t = i / SAMPLE_RATE
        sample = 0.0
        for start, frequency in events:
            elapsed = t - start
            if 0 <= elapsed < NOTE_LENGTH:
                attack = min(1.0, elapsed / 0.035)      # gentle attack
                decay = math.exp(-3.2 * elapsed)        # bell-like fade
                tone = (
                    math.sin(2 * math.pi * frequency * elapsed)
                    + 0.22 * math.sin(2 * math.pi * frequency * 2 * elapsed)
                    + 0.08 * math.sin(2 * math.pi * frequency * 3 * elapsed)
                )
                sample += tone * attack * decay
        sample = max(-1.0, min(1.0, sample * VOLUME))
        frames.extend(struct.pack("<h", int(sample * 32767)))

    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "alarm.wav")
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(bytes(frames))
    print("wrote", os.path.normpath(path))


main()
