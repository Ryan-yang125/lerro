#!/usr/bin/env python3
"""Render Lerro's capture start/stop sounds (a short bubble: a sine whose pitch
slides up to start and down to stop, with a faint click) into
Sources/Lerro/Resources/Sounds as 48 kHz 16-bit mono CAF files."""
import math, pathlib, random, struct, subprocess, tempfile, wave

SR = 48_000
DURATION = 0.45
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources/Lerro/Resources/Sounds"


def envelope(t, amplitude, attack, decay):
    if t < 0:
        return 0.0
    if t < attack:
        return amplitude * t / attack
    x = (t - attack) / max(decay - attack, 1e-6)
    return amplitude * (1e-4 / amplitude) ** x if x < 1 else 0.0


def click(buffer, start, amount, frequency):
    random.seed(3)
    length = int(SR * 0.012)
    w0 = 2 * math.pi * frequency / SR
    alpha = math.sin(w0) / 2.4
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w0), 1 - alpha
    x1 = x2 = y1 = y2 = 0.0
    for k in range(length):
        x = (random.random() * 2 - 1) * math.exp(-k / (length / 5))
        y = (alpha * x - alpha * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        buffer[int(start * SR) + k] += amount * y * 4


def bubble(rising):
    buffer = [0.0] * int(SR * DURATION)
    start = 0.005
    f0, f1 = (520, 980) if rising else (900, 430)
    phase = 0.0
    for i in range(int(start * SR), int((start + 0.2) * SR)):
        t = i / SR - start
        frequency = f0 * (f1 / f0) ** min(1, t / 0.07)
        phase += 2 * math.pi * frequency / SR
        buffer[i] += envelope(t, 0.38, 0.004, 0.16) * math.sin(phase)
    click(buffer, start, 0.05, 2400)
    return buffer


def write_caf(name, buffer):
    peak = max(abs(v) for v in buffer) or 1
    scale = 0.7 / peak
    with tempfile.TemporaryDirectory() as directory:
        wav = pathlib.Path(directory) / f"{name}.wav"
        with wave.open(str(wav), "wb") as file:
            file.setnchannels(1)
            file.setsampwidth(2)
            file.setframerate(SR)
            file.writeframes(b"".join(
                struct.pack("<h", int(max(-1, min(1, v * scale)) * 32767)) for v in buffer
            ))
        subprocess.run(
            ["afconvert", "-f", "caff", "-d", "LEI16@48000", "-c", "1", str(wav), str(OUTPUT / f"{name}.caf")],
            check=True,
        )


OUTPUT.mkdir(parents=True, exist_ok=True)
write_caf("capture-start", bubble(rising=True))
write_caf("capture-stop", bubble(rising=False))
print(f"Wrote capture-start.caf and capture-stop.caf to {OUTPUT}")
