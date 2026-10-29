#!/usr/bin/python3
"""Writes data/alarm.wav, the sound the timer and alarm clock ring with: three
short beeps, 16-bit mono at 16 kHz (about 20 KB), with soft edges so they do not
click. Made here so the file can be remade, and so it is clear what is in it:
only sine waves, no samples from anywhere.   python3 tools/make-alarm-sound.py"""
import math
import os
import struct
import wave

RATE = 16000
BEEP, GAP, FREQ, LEVEL = 0.16, 0.12, 880.0, 0.45


def beep():
    n = int(RATE * BEEP)
    fade = int(RATE * 0.01)
    out = []
    for i in range(n):
        edge = min(1.0, i / fade, (n - 1 - i) / fade)
        out.append(int(32767 * LEVEL * edge * math.sin(2 * math.pi * FREQ * i / RATE)))
    return out


def main():
    samples = []
    for _ in range(3):
        samples += beep() + [0] * int(RATE * GAP)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "alarm.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", s) for s in samples))
    print("wrote", os.path.normpath(path))


main()
