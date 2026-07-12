"""Procedurally generate all game audio as 16-bit mono WAVs in assets/audio/.
Pure stdlib - no dependencies. Deterministic output."""
import math
import random
import struct
import wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(42)


def write(name, samples):
    data = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"  {name}.wav ({len(samples)/SR:.2f}s)")


def seconds(t):
    return int(SR * t)


def lowpass(samples, alpha):
    out, prev = [], 0.0
    for s in samples:
        prev = prev + alpha * (s - prev)
        out.append(prev)
    return out


def normalize(samples, peak=0.85):
    m = max(abs(s) for s in samples) or 1.0
    return [s / m * peak for s in samples]


def loopable_noise(n, alpha):
    """Filtered noise that loops cleanly (crossfade tail into head)."""
    raw = [random.uniform(-1, 1) for _ in range(n + SR // 4)]
    f = lowpass(raw, alpha)
    fade = SR // 4
    out = f[:n]
    for i in range(fade):
        t = i / fade
        out[i] = out[i] * t + f[n + i] * (1 - t)
    return out


# ---------------- engine loops ----------------
def engine_prop():
    n = seconds(2.0)
    base = 55.0
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for h, a in [(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.22), (6, 0.1)]:
            s += a * math.sin(TAU * base * h * t)
        s *= 0.75 + 0.25 * math.sin(TAU * 13.0 * t)  # blade beat
        out.append(s)
    noise = loopable_noise(n, 0.12)
    return normalize([o * 0.7 + nz * 0.45 for o, nz in zip(out, noise)], 0.65)


def engine_jet():
    n = seconds(2.0)
    noise = loopable_noise(n, 0.35)
    out = []
    for i in range(n):
        t = i / SR
        whine = 0.16 * math.sin(TAU * 950 * t) + 0.08 * math.sin(TAU * 1480 * t)
        out.append(noise[i] * 0.85 + whine)
    return normalize(out, 0.6)


def engine_heli():
    n = seconds(2.0)
    noise = loopable_noise(n, 0.2)
    out = []
    whop_hz = 13.0
    for i in range(n):
        t = i / SR
        whop = max(0.0, math.sin(TAU * whop_hz * t)) ** 3
        low = 0.3 * math.sin(TAU * 38 * t)
        out.append(noise[i] * (0.35 + 0.85 * whop) + low)
    return normalize(out, 0.65)


def wind_loop():
    return normalize(loopable_noise(seconds(3.0), 0.06), 0.5)


def rolling_loop():
    n = seconds(1.5)
    noise = loopable_noise(n, 0.04)
    return normalize([nz * (1 + 0.3 * math.sin(TAU * 7 * i / SR)) for i, nz in enumerate(noise)], 0.55)


def ab_rumble():
    n = seconds(2.0)
    noise = loopable_noise(n, 0.05)
    return normalize([nz * 1.2 + 0.25 * math.sin(TAU * 28 * i / SR) for i, nz in enumerate(noise)], 0.7)


# ---------------- one-shots ----------------
def touchdown():
    n = seconds(0.5)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 14)
        out.append(env * (math.sin(TAU * 55 * t) * 0.9 + random.uniform(-1, 1) * 0.4 * math.exp(-t * 25)))
    return normalize(out, 0.8)


def screech():
    n = seconds(0.8)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 5) * min(1.0, t * 30)
        f = 1500 + 300 * math.sin(TAU * 6 * t)
        out.append(env * (math.sin(TAU * f * t) * 0.6 + random.uniform(-1, 1) * 0.35))
    return normalize(out, 0.6)


def crash():
    n = seconds(1.8)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-t * 3.2)
        out.append(env * (random.uniform(-1, 1) * 0.9 + 0.5 * math.sin(TAU * 42 * t * (1 - t * 0.3))))
    return normalize(lowpass(out, 0.4), 0.9)


def click():
    n = seconds(0.06)
    return normalize([math.exp(-i / SR * 220) * math.sin(TAU * 1800 * i / SR) for i in range(n)], 0.5)


def warn_beep():
    n = seconds(0.9)
    out = []
    for i in range(n):
        t = i / SR
        gate = 1.0 if (t % 0.3) < 0.18 else 0.0
        out.append(gate * math.sin(TAU * 880 * t) * 0.8)
    return out


def stall_horn():
    n = seconds(1.0)
    out = []
    for i in range(n):
        t = i / SR
        # sawtooth-ish
        s = 2.0 * ((t * 400) % 1.0) - 1.0
        out.append(s * 0.45)
    return lowpass(out, 0.25)


def gear_motor():
    n = seconds(1.2)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.5 * math.sin(TAU * 110 * t) + 0.3 * math.sin(TAU * 223 * t) + random.uniform(-1, 1) * 0.15
        out.append(s * min(1.0, t * 10) * min(1.0, (1.2 - t) * 10))
    return normalize(out, 0.45)


def flap_motor():
    n = seconds(1.0)
    out = []
    for i in range(n):
        t = i / SR
        s = 0.5 * math.sin(TAU * 180 * t) + random.uniform(-1, 1) * 0.1
        out.append(s * min(1.0, t * 10) * min(1.0, (1.0 - t) * 10))
    return normalize(out, 0.35)


def cash():
    n = seconds(0.45)
    out = []
    for i in range(n):
        t = i / SR
        f = 1318 if t < 0.18 else 1760
        env = math.exp(-((t % 0.18)) * 9)
        out.append(env * math.sin(TAU * f * t) * 0.6)
    return out


def penalty():
    n = seconds(0.5)
    out = []
    for i in range(n):
        t = i / SR
        f = 520 if t < 0.22 else 340
        env = math.exp(-(t % 0.22) * 7)
        out.append(env * math.sin(TAU * f * t) * 0.65)
    return out


def radio_blip():
    n = seconds(0.22)
    out = []
    for i in range(n):
        t = i / SR
        stat = random.uniform(-1, 1) * 0.3 * math.exp(-t * 12)
        beep = 0.4 * math.sin(TAU * 1100 * t) * (1.0 if t < 0.08 else 0.0)
        out.append(stat + beep)
    return out


TAU = 2 * math.pi

GENS = {
    "engine_prop_loop": engine_prop, "engine_jet_loop": engine_jet,
    "engine_heli_loop": engine_heli, "wind_loop": wind_loop,
    "rolling_loop": rolling_loop, "ab_rumble_loop": ab_rumble,
    "touchdown": touchdown, "screech": screech, "crash": crash,
    "click": click, "warn_beep": warn_beep, "stall_horn": stall_horn,
    "gear_motor": gear_motor, "flap_motor": flap_motor,
    "cash": cash, "penalty": penalty, "radio_blip": radio_blip,
}

if __name__ == "__main__":
    print(f"Generating {len(GENS)} sounds -> {OUT}")
    for name, fn in GENS.items():
        write(name, fn())
    print("done")
