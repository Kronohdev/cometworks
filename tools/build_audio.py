"""Renders every sound of Cometworks into assets/audio/ (16-bit .wav), offline and from
scratch: no samples, no downloads, only numpy (pure synthesis), so the sounds are as
licence-clean as the code. Every random choice comes from a fixed seed per sound: running
the script again gives the same files, bit for bit.

The palette is soft and cosy: filtered noise, kalimba / marimba / celesta plucks, warm
additive pads, little formant "babble" voices for the Cometlings, synthetic birds and
crickets. Loops (music, ambience beds, the engine rumble) are rendered on a circular
timeline (note tails, reverb and filtered noise wrap around the end), so they loop without
a seam, and carry a RIFF "smpl" loop chunk that Godot's importer picks up (loop mode
"Detect from WAV").

Folders:
  assets/audio/ui/        hover, click, back, open / close whoosh, toggles, denied, cash, news
  assets/audio/music/     menu theme, campus loop, milestone and finale stingers
  assets/audio/ambience/  day (birds) and night (crickets) beds, space hush, workshop clanks
  assets/audio/voice/     Cometling chirps and babble (happy, question, surprised, sad, ...)
  assets/audio/launch/    countdown, ignition, rumble loop, sputter, failure, crowd, result chimes
  assets/audio/fair/      the conference fair: footsteps, talk chime, award fanfare, applause
  assets/audio/comic/     the flight comic: page turn, panel pop, sound-effect words, end stings
  (ui/ also has the album's shutter / develop / flip / pin, the launch watch's warp and
   simulate loop, and the CML / crew-milestone ticks; ambience/ and music/ the fair's beds
   and its distant band)

What plays what (names, volumes, pitch variance, buses) lives in the editable sound library
assets/audio/cw_sound_library.tres (src/audio/cw_sound_library.gd); this script only makes
the waves. It writes the library once if it is missing (--library forces it, overwriting hand
edits).

Usage:
  python tools/build_audio.py                 render everything
  python tools/build_audio.py --only ui_click,music_menu
  python tools/build_audio.py --plots DIR     also write a waveform + spectrogram PNG per sound
  python tools/build_audio.py --list          list the sounds
"""
from __future__ import annotations

import argparse
import math
import os
import struct
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio"
LIBRARY = OUT / "cw_sound_library.tres"

SR = 44100      # one-shots
SR_LO = 22050   # music, beds and loops (soft and dark anyway; half the bytes)

TAU = 2.0 * math.pi


# ======================================================================== helpers
def midi(n: float) -> float:
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def nm(name: str) -> int:
    """'A4' -> 69, 'F#5' -> 78."""
    letters = name[:-1]
    octave = int(name[-1])
    return 12 * (octave + 1) + NOTE[letters]


def secs(n: int, sr: int) -> np.ndarray:
    return np.arange(n) / sr


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def fade(x: np.ndarray, sr: int, fin=0.002, fout=0.01) -> np.ndarray:
    x = x.copy()
    a = max(1, int(fin * sr))
    b = max(1, int(fout * sr))
    if x.ndim == 1:
        x[:a] *= np.linspace(0, 1, a) ** 2
        x[-b:] *= np.linspace(1, 0, b) ** 2
    else:
        x[:, :a] *= np.linspace(0, 1, a) ** 2
        x[:, -b:] *= np.linspace(1, 0, b) ** 2
    return x


def env_ar(n: int, sr: int, attack: float, decay: float, curve=1.0) -> np.ndarray:
    """Attack (raised cosine) then exponential decay with time constant `decay`."""
    t = secs(n, sr)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    a = 0.5 - 0.5 * np.cos(np.pi * a)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4)) ** curve
    return a * d


def env_adsr(n: int, sr: int, a: float, d: float, s: float, r: float, hold: float) -> np.ndarray:
    t = secs(n, sr)
    e = np.zeros(n)
    e = np.where(t < a, 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(a, 1e-4), 0, 1)), e)
    dec = (t >= a) & (t < a + d)
    e = np.where(dec, 1.0 - (1.0 - s) * (t - a) / max(d, 1e-4), e)
    e = np.where((t >= a + d) & (t < hold), s, e)
    rel = t >= hold
    e = np.where(rel, s * np.exp(-(t - hold) / max(r, 1e-4)), e)
    return e


def raised(n: int, sr: int, attack: float, release: float, hold: float) -> np.ndarray:
    """Smooth swell: cosine attack to 1, flat until `hold`, cosine release to 0."""
    t = secs(n, sr)
    e = np.ones(n)
    e *= 0.5 - 0.5 * np.cos(np.pi * np.clip(t / max(attack, 1e-4), 0, 1))
    r = np.clip((t - hold) / max(release, 1e-4), 0, 1)
    e *= 0.5 + 0.5 * np.cos(np.pi * r)
    return e


def fft_filter(x: np.ndarray, sr: int, lo: float | None = None, hi: float | None = None,
               order: float = 2.0, circular=False, tilt: float = 0.0) -> np.ndarray:
    """Zero-phase Butterworth-shaped band filter in the frequency domain. `circular` keeps
    the length (a loop stays seamless); otherwise the signal is padded so tails do not wrap.
    `tilt` dB per octave above 1 kHz (negative = darker)."""
    n = x.shape[-1]
    pad = 0 if circular else min(n, int(0.25 * sr) + 1024)
    m = n + pad
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1.0 / sr)
    H = np.ones_like(f)
    if hi:
        H /= np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo:
        with np.errstate(divide="ignore"):
            H *= np.where(f > 0, 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order)), 0.0)
    if tilt:
        H *= np.where(f > 1000.0, (np.maximum(f, 1000.0) / 1000.0) ** (tilt / 6.02), 1.0)
    y = np.fft.irfft(X * H, m)
    return y[..., :n]


def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def pink(n: int, rng: np.random.Generator, circular=True) -> np.ndarray:
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(X.size, dtype=float)
    f[0] = 1.0
    y = np.fft.irfft(X / np.sqrt(f), n)
    return y / (np.std(y) + 1e-12)


def brown(n: int, rng: np.random.Generator) -> np.ndarray:
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(X.size, dtype=float)
    f[0] = 1.0
    y = np.fft.irfft(X / f, n)
    return y / (np.std(y) + 1e-12)


def biquad_bp(x: np.ndarray, sr: int, fc, q: float) -> np.ndarray:
    """Time-varying constant-peak band-pass (RBJ); fc may be an array (sweeps)."""
    n = x.size
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    w0 = TAU * np.clip(fc, 20.0, sr * 0.45) / sr
    alpha = np.sin(w0) / (2.0 * q)
    b0 = alpha
    a0 = 1.0 + alpha
    a1 = -2.0 * np.cos(w0)
    a2 = 1.0 - alpha
    b0 /= a0
    b2 = -b0
    a1 /= a0
    a2 /= a0
    y = np.zeros(n)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        xi = x[i]
        yi = b0[i] * xi + b2[i] * x2 - a1[i] * y1 - a2[i] * y2
        x2 = x1
        x1 = xi
        y2 = y1
        y1 = yi
        y[i] = yi
    return y


def onepole_lp(x: np.ndarray, sr: int, fc) -> np.ndarray:
    n = x.size
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    a = 1.0 - np.exp(-TAU * np.clip(fc, 5.0, sr * 0.45) / sr)
    y = np.zeros(n)
    s = 0.0
    for i in range(n):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def add(buf: np.ndarray, sig: np.ndarray, start: int, circular=False, gain=1.0) -> None:
    """Mixes `sig` into `buf` at sample `start` (mono or stereo, wraps when circular)."""
    n = buf.shape[-1]
    m = sig.shape[-1]
    if circular:
        start %= n
        pos = 0
        while pos < m:
            s = (start + pos) % n
            take = min(m - pos, n - s)
            buf[..., s:s + take] += gain * sig[..., pos:pos + take]
            pos += take
        return
    if start >= n:
        return
    s0 = max(start, 0)
    off = s0 - start
    take = min(m - off, n - s0)
    if take > 0:
        buf[..., s0:s0 + take] += gain * sig[..., off:off + take]


def pan(sig: np.ndarray, p: float) -> np.ndarray:
    """Equal-power pan, p in -1..1 -> (2, n)."""
    a = (p + 1.0) * 0.25 * math.pi
    return np.stack([sig * math.cos(a), sig * math.sin(a)])


def reverb_ir(sr: int, seconds: float, rng: np.random.Generator, stereo=False, damp_hz=3500.0,
              predelay=0.012) -> np.ndarray:
    n = int(seconds * sr)
    t = secs(n, sr)
    chans = []
    for _ in range(2 if stereo else 1):
        nz = rng.standard_normal(n)
        lo = fft_filter(nz, sr, hi=damp_hz, order=1.0) * np.exp(-6.9 * t / seconds)
        hi = (nz - fft_filter(nz, sr, hi=damp_hz, order=1.0)) * np.exp(-6.9 * t / (seconds * 0.35))
        ir = lo + 0.5 * hi
        ir *= np.clip(t / 0.03, 0, 1)   # soft build-up
        pd = int(predelay * sr)
        ir = np.concatenate([np.zeros(pd), ir])[:n]
        ir /= math.sqrt(np.sum(ir ** 2)) + 1e-12
        chans.append(ir)
    return np.stack(chans) if stereo else chans[0]


def convolve(x: np.ndarray, ir: np.ndarray, circular=False) -> np.ndarray:
    """FFT convolution; mono x with stereo ir gives stereo. Keeps len(x) when circular,
    else x + tail."""
    n = x.shape[-1]
    k = ir.shape[-1]
    if circular:
        m = n
        if k > n:
            ir = ir[..., :n]
    else:
        m = n + k - 1
    size = 1 << (m - 1).bit_length()
    if circular:
        X = np.fft.rfft(x, n)
        I = np.fft.rfft(ir, n)
        return np.fft.irfft(X * I, n)
    X = np.fft.rfft(x, size)
    I = np.fft.rfft(ir, size)
    return np.fft.irfft(X * I, size)[..., :m]


def with_reverb(x: np.ndarray, sr: int, seconds: float, wet: float, seed: int, stereo=False,
                circular=False, damp_hz=3500.0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    ir = reverb_ir(sr, seconds, rng, stereo=stereo, damp_hz=damp_hz)
    w = convolve(x, ir, circular=circular)
    if circular:
        dry = x if (x.ndim == w.ndim) else np.stack([x, x])
        return dry * (1.0 - wet * 0.5) + w * wet
    dry = np.zeros_like(w)
    if x.ndim == w.ndim:
        dry[..., :x.shape[-1]] = x
    else:
        dry[:, :x.shape[-1]] = x
    return dry * (1.0 - wet * 0.5) + w * wet


# ======================================================================== instruments
def partials(f: float, sr: int, dur: float, ratios, amps, decays, attack=0.002,
             phase_rng: np.random.Generator | None = None) -> np.ndarray:
    n = int(dur * sr)
    t = secs(n, sr)
    x = np.zeros(n)
    for r, a, d in zip(ratios, amps, decays):
        fr = f * r
        if fr >= sr * 0.45:
            continue
        ph = phase_rng.random() * TAU if phase_rng is not None else 0.0
        x += a * np.sin(TAU * fr * t + ph) * np.exp(-t / d)
    at = max(1, int(attack * sr))
    x[:at] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(at) / at)
    return x


def kalimba(f: float, sr: int = SR, dur: float = 1.6, bright: float = 1.0, decay: float = 0.7) -> np.ndarray:
    d = decay * min(1.4, (523.0 / f) ** 0.35)
    x = partials(f, sr, dur, [1.0, 2.0, 6.27], [1.0, 0.10 * bright, 0.28 * bright], [d, d * 0.3, 0.05])
    # the tine's soft tick
    n = x.size
    click = np.zeros(n)
    m = int(0.004 * sr)
    rng = np.random.default_rng(int(f * 10))
    click[:m] = rng.standard_normal(m) * np.linspace(1, 0, m) ** 2
    click = fft_filter(click, sr, lo=1500, hi=6000)
    return fade(x + 0.06 * bright * click, sr, 0.0015, 0.05)


def marimba(f: float, sr: int = SR, dur: float = 1.2, bright: float = 1.0) -> np.ndarray:
    d = 0.5 * min(1.6, (440.0 / f) ** 0.5)
    x = partials(f, sr, dur, [1.0, 3.99, 9.9], [1.0, 0.32 * bright, 0.07 * bright], [d, 0.07, 0.025],
                 attack=0.0025)
    n = x.size
    m = int(0.006 * sr)
    rng = np.random.default_rng(int(f * 7))
    th = np.zeros(n)
    th[:m] = rng.standard_normal(m) * np.linspace(1, 0, m) ** 2
    th = fft_filter(th, sr, lo=200, hi=2500)
    return fade(x + 0.05 * th, sr, 0.002, 0.05)


def celesta(f: float, sr: int = SR, dur: float = 2.5, bright: float = 1.0) -> np.ndarray:
    return fade(partials(f, sr, dur, [1.0, 2.0, 3.01, 4.17, 5.43], [1.0, 0.42 * bright, 0.16 * bright,
                                                                    0.12 * bright, 0.05 * bright],
                         [1.4, 0.8, 0.5, 0.3, 0.18], attack=0.0015), sr, 0.0015, 0.08)


def soft_bass(f: float, sr: int, dur: float, decay=0.9) -> np.ndarray:
    x = partials(f, sr, dur, [1.0, 2.0, 3.0], [1.0, 0.25, 0.06], [decay, decay * 0.5, decay * 0.3], attack=0.012)
    return fade(x, sr, 0.01, 0.08)


def pad_note(f: float, sr: int, dur: float, attack: float, release: float, rng: np.random.Generator,
             cutoff: float = 1800.0, detune=(-6.0, 0.0, 7.0), bright: float = 1.0) -> np.ndarray:
    """Warm additive 'saw' pad (harmonics with a soft low-pass), a few detuned voices."""
    n = int((dur + release) * sr)
    t = secs(n, sr)
    x = np.zeros(n)
    kmax = int(min(24, (sr * 0.45) / f))
    for c in detune:
        fv = f * 2 ** (c / 1200.0)
        drift = 1.0 + 0.0015 * np.sin(TAU * (0.11 + rng.random() * 0.1) * t + rng.random() * TAU)
        ph = TAU * fv * np.cumsum(drift) / sr
        for k in range(1, kmax + 1):
            a = (1.0 / k ** 1.15) / math.sqrt(1.0 + (k * fv / cutoff) ** 4) * (bright if k > 1 else 1.0)
            if a < 0.004:
                continue
            x += a * np.sin(k * ph + rng.random() * TAU)
    x /= len(detune)
    e = raised(n, sr, attack, release, dur)
    return x * e


def sine_glide(f0: float, f1: float, sr: int, dur: float, curve="exp") -> np.ndarray:
    n = int(dur * sr)
    u = np.linspace(0, 1, n)
    f = f0 * (f1 / f0) ** u if curve == "exp" else f0 + (f1 - f0) * u
    return np.sin(TAU * np.cumsum(f) / sr)


# ======================================================================== Cometling voice
VOWELS = {  # cute, small-creature formants (Hz): F1, F2, F3
    "a": (950, 1650, 3000), "e": (620, 2350, 3200), "i": (420, 2900, 3600),
    "o": (640, 1150, 2900), "u": (430, 1000, 2700), "y": (450, 2100, 3000),
}


def cometling_voice(syllables, sr: int = SR, base_f0: float = 620.0, seed: int = 0, breath: float = 0.04,
                    vibrato: float = 0.018) -> np.ndarray:
    """Additive formant babble. syllables: [(dur, f0_from, f0_to, vowel_from, vowel_to, gap, amp)];
    f0 values are ratios of base_f0."""
    rng = np.random.default_rng(seed)
    f0s, f1s, f2s, f3s, amps = [], [], [], [], []
    for (dur, a0, a1, v0, v1, gap, amp) in syllables:
        n = int(dur * sr)
        u = np.linspace(0, 1, n)
        su = u * u * (3 - 2 * u)
        f0s.append(base_f0 * a0 * (a1 / a0) ** su)
        va, vb = VOWELS[v0], VOWELS[v1]
        f1s.append(va[0] + (vb[0] - va[0]) * su)
        f2s.append(va[1] + (vb[1] - va[1]) * su)
        f3s.append(va[2] + (vb[2] - va[2]) * su)
        e = raised(n, sr, min(0.025, dur * 0.3), min(0.06, dur * 0.4), dur - min(0.06, dur * 0.4))
        amps.append(e * amp)
        g = int(gap * sr)
        if g > 0:
            f0s.append(np.full(g, f0s[-1][-1]))
            f1s.append(np.full(g, f1s[-1][-1]))
            f2s.append(np.full(g, f2s[-1][-1]))
            f3s.append(np.full(g, f3s[-1][-1]))
            amps.append(np.zeros(g))
    f0 = np.concatenate(f0s)
    F1, F2, F3 = np.concatenate(f1s), np.concatenate(f2s), np.concatenate(f3s)
    amp = np.concatenate(amps)
    n = f0.size
    t = secs(n, sr)
    f0 = f0 * (1.0 + vibrato * np.sin(TAU * 6.3 * t + rng.random() * TAU))
    ph = TAU * np.cumsum(f0) / sr
    x = np.zeros(n)
    kmax = int(5200 / f0.min())
    for k in range(1, kmax + 1):
        fk = k * f0
        g = (1.0 / (1.0 + ((fk - F1) / 160.0) ** 2) + 0.8 / (1.0 + ((fk - F2) / 260.0) ** 2)
             + 0.25 / (1.0 + ((fk - F3) / 380.0) ** 2) + 0.03)
        g *= 1.0 / k ** 0.35
        g = np.where(fk < sr * 0.45, g, 0.0)
        x += g * np.sin(k * ph)
    x *= amp
    # breath on the onsets
    nz = fft_filter(rng.standard_normal(n), sr, lo=2500, hi=7000) * amp ** 2
    x += breath * nz * (np.max(np.abs(x)) / (np.max(np.abs(nz)) + 1e-9))
    x = fft_filter(x, sr, lo=180, hi=7000)
    return fade(x, sr, 0.003, 0.03)


def syl(dur, a0, a1, v0, v1, gap=0.03, amp=1.0):
    return (dur, a0, a1, v0, v1, gap, amp)


# ======================================================================== sound makers
# Each maker returns (signal, sample_rate, loop) where signal is (n,) mono or (2, n) stereo.

def s_ui_hover():
    n = int(0.09 * SR)
    t = secs(n, SR)
    x = np.sin(TAU * 2350 * t) * np.exp(-t / 0.018) + 0.25 * np.sin(TAU * 4700 * t) * np.exp(-t / 0.008)
    x = fade(x, SR, 0.0015, 0.02)
    return x, SR, False


def s_ui_click():
    n = int(0.16 * SR)
    t = secs(n, SR)
    f = 520 + 380 * np.exp(-t / 0.018)
    body = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.045)
    body += 0.18 * np.sin(2 * TAU * np.cumsum(f) / SR) * np.exp(-t / 0.02)
    tick = kalimba(midi(nm("E6")), SR, 0.16, bright=0.5, decay=0.06)
    return fade(body + 0.35 * tick, SR, 0.0015, 0.03), SR, False


def s_ui_back():
    x = np.zeros(int(0.42 * SR))
    add(x, marimba(midi(nm("E6")), SR, 0.3), 0)
    add(x, marimba(midi(nm("B5")), SR, 0.35), int(0.07 * SR), gain=0.85)
    return fade(x, SR, 0.001, 0.05), SR, False


def _whoosh(f_from, f_to, dur, seed, shimmer_from, shimmer_to):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    u = np.linspace(0, 1, n)
    fc = f_from * (f_to / f_from) ** u
    nz = biquad_bp(pink(n, rng), SR, fc, 1.6)
    e = np.sin(np.pi * np.clip(u, 0, 1)) ** 1.6
    air = nz * e
    sh = sine_glide(shimmer_from, shimmer_to, SR, dur) * e ** 2 * 0.12
    x = air / (np.max(np.abs(air)) + 1e-9) + sh
    return fade(x, SR, 0.004, 0.03)


def s_ui_open():
    return _whoosh(450, 2600, 0.34, 11, 700, 1400), SR, False


def s_ui_close():
    return _whoosh(2400, 420, 0.28, 12, 1300, 650), SR, False


def s_ui_toggle_on():
    x = np.zeros(int(0.32 * SR))
    add(x, kalimba(midi(nm("A5")), SR, 0.3, decay=0.2), 0)
    add(x, kalimba(midi(nm("E6")), SR, 0.25, decay=0.18), int(0.045 * SR), gain=0.8)
    return fade(x, SR, 0.001, 0.04), SR, False


def s_ui_toggle_off():
    x = np.zeros(int(0.32 * SR))
    add(x, kalimba(midi(nm("E6")), SR, 0.3, decay=0.18), 0, gain=0.8)
    add(x, kalimba(midi(nm("A5")), SR, 0.25, decay=0.2), int(0.045 * SR))
    return fade(x, SR, 0.001, 0.04), SR, False


def s_ui_denied():
    x = np.zeros(int(0.36 * SR))
    for i, (f, g) in enumerate([(330.0, 1.0), (294.0, 0.85)]):
        n = int(0.13 * SR)
        t = secs(n, SR)
        fr = f * (1.0 - 0.06 * t / 0.13)
        ph = TAU * np.cumsum(fr) / SR
        tone = (np.sin(ph) + 0.3 * np.sin(3 * ph) + 0.12 * np.sin(5 * ph)) * env_ar(n, SR, 0.004, 0.05)
        add(x, fft_filter(tone, SR, hi=1800), int(i * 0.12 * SR), gain=g)
    return fade(x, SR, 0.001, 0.04), SR, False


def s_cash_up():
    x = np.zeros(int(0.7 * SR))
    add(x, celesta(midi(nm("E6")), SR, 0.6, bright=0.7), 0, gain=0.8)
    add(x, celesta(midi(nm("B6")), SR, 0.6, bright=0.7), int(0.06 * SR))
    return fade(with_reverb(x, SR, 0.8, 0.18, 21)[: x.size], SR, 0.001, 0.08), SR, False


def s_cash_down():
    x = np.zeros(int(0.6 * SR))
    add(x, marimba(midi(nm("B5")), SR, 0.4, bright=0.6), 0, gain=0.9)
    add(x, marimba(midi(nm("F#5")), SR, 0.45, bright=0.6), int(0.08 * SR))
    return fade(x, SR, 0.001, 0.06), SR, False


def s_news_chime():
    x = np.zeros(int(1.6 * SR))
    for i, nn in enumerate(["C6", "E6", "G6", "C7"]):
        add(x, kalimba(midi(nm(nn)), SR, 1.2, decay=0.55), int(i * 0.075 * SR), gain=[0.9, 0.85, 0.9, 0.55][i])
    add(x, celesta(midi(nm("G6")), SR, 1.3, bright=0.4), int(0.3 * SR), gain=0.25)
    y = with_reverb(x, SR, 1.4, 0.3, 22)[: x.size]
    return fade(y, SR, 0.001, 0.15), SR, False


MENU_HOVER_NOTES = ["D5", "E5", "F#5", "A5", "B5"]


def s_menu_hover(i):
    def make():
        x = kalimba(midi(nm(MENU_HOVER_NOTES[i])), SR, 0.55, bright=0.6, decay=0.3)
        y = with_reverb(x, SR, 0.9, 0.2, 30 + i)[: x.size]
        return fade(y, SR, 0.001, 0.08), SR, False
    return make


def s_menu_select():
    x = np.zeros(int(1.2 * SR))
    add(x, kalimba(midi(nm("A5")), SR, 1.0, decay=0.45), 0)
    add(x, kalimba(midi(nm("D6")), SR, 1.0, decay=0.45), int(0.05 * SR), gain=0.8)
    add(x, kalimba(midi(nm("F#6")), SR, 0.9, decay=0.4), int(0.1 * SR), gain=0.6)
    rng = np.random.default_rng(31)
    sw = pad_note(midi(nm("D5")), SR, 0.35, 0.12, 0.5, rng, cutoff=1500)
    add(x, sw * 0.25, 0)
    y = with_reverb(x, SR, 1.2, 0.25, 32)[: x.size]
    return fade(y, SR, 0.001, 0.12), SR, False


# ------------------------------------------------------------------------ voices
def _v(syls, f0, seed, **kw):
    def make():
        return cometling_voice(syls, SR, f0, seed, **kw), SR, False
    return make


VOICES = {
    # happy chirps: up-down "bi-du!" shapes
    "voice_happy_1": _v([syl(0.09, 1.0, 1.25, "i", "i", 0.025), syl(0.14, 1.35, 1.1, "u", "a", 0.0)], 640, 101),
    "voice_happy_2": _v([syl(0.07, 1.1, 1.3, "e", "i", 0.02), syl(0.07, 1.2, 1.4, "i", "i", 0.02),
                         syl(0.16, 1.5, 1.2, "a", "o", 0.0)], 600, 102),
    "voice_happy_3": _v([syl(0.2, 1.0, 1.55, "u", "i", 0.0)], 680, 103),
    "voice_happy_4": _v([syl(0.08, 1.2, 1.2, "a", "e", 0.03), syl(0.12, 1.45, 1.25, "i", "a", 0.0)], 560, 104),
    # questions rise at the end: "mm-hm?"
    "voice_question_1": _v([syl(0.1, 1.0, 0.95, "u", "u", 0.03), syl(0.2, 1.0, 1.6, "e", "i", 0.0)], 600, 111),
    "voice_question_2": _v([syl(0.24, 0.95, 1.7, "o", "i", 0.0)], 620, 112),
    # surprised: a quick high "oh!"
    "voice_surprised_1": _v([syl(0.14, 1.6, 1.25, "o", "o", 0.0)], 640, 121, vibrato=0.01),
    "voice_surprised_2": _v([syl(0.05, 1.3, 1.6, "i", "i", 0.015), syl(0.13, 1.7, 1.3, "a", "o", 0.0)], 600, 122),
    # sad / tired: a soft falling "aww"
    "voice_sad_1": _v([syl(0.38, 1.15, 0.78, "a", "u", 0.0)], 560, 131, vibrato=0.03),
    "voice_sad_2": _v([syl(0.12, 1.1, 1.05, "e", "e", 0.03), syl(0.3, 1.05, 0.75, "o", "u", 0.0)], 540, 132),
    # babble for chats: "bi-da-bu-di"
    "voice_babble_1": _v([syl(0.07, 1.0, 1.1, "i", "a", 0.02), syl(0.07, 1.15, 1.0, "a", "u", 0.02),
                          syl(0.08, 1.05, 1.2, "e", "i", 0.02), syl(0.11, 1.15, 0.95, "o", "a", 0.0)], 600, 141),
    "voice_babble_2": _v([syl(0.09, 1.1, 1.0, "a", "a", 0.025), syl(0.06, 1.2, 1.25, "i", "e", 0.02),
                          syl(0.12, 1.1, 1.3, "u", "i", 0.0)], 650, 142),
    "voice_babble_3": _v([syl(0.06, 0.95, 1.05, "o", "e", 0.02), syl(0.06, 1.1, 1.1, "e", "a", 0.02),
                          syl(0.06, 1.15, 1.0, "a", "i", 0.02), syl(0.07, 1.05, 1.15, "i", "u", 0.02),
                          syl(0.1, 1.2, 1.0, "u", "o", 0.0)], 580, 143),
    # cheer: a longer bright "yaaay!"
    "voice_cheer_1": _v([syl(0.42, 1.2, 1.55, "e", "a", 0.0)], 640, 151, vibrato=0.03),
    "voice_cheer_2": _v([syl(0.08, 1.3, 1.4, "i", "i", 0.03), syl(0.36, 1.5, 1.3, "a", "y", 0.0)], 600, 152, vibrato=0.03),
}


def s_voice_snore():
    rng = np.random.default_rng(161)
    n = int(1.3 * SR)
    t = secs(n, SR)
    inhale = raised(n, SR, 0.45, 0.35, 0.55)
    nz = fft_filter(rng.standard_normal(n), SR, lo=250, hi=1600) * inhale
    hum = np.sin(TAU * np.cumsum(140 + 15 * np.sin(TAU * 1.6 * t)) / SR) * inhale * 0.5
    x = nz / (np.max(np.abs(nz)) + 1e-9) * 0.6 + hum
    # a tiny "pff" at the end
    m = int(0.18 * SR)
    pf = fft_filter(rng.standard_normal(m), SR, lo=800, hi=3000) * env_ar(m, SR, 0.01, 0.05)
    add(x, pf / (np.max(np.abs(pf)) + 1e-9) * 0.35, int(1.05 * SR))
    return fade(x, SR, 0.01, 0.05), SR, False


# ------------------------------------------------------------------------ music
def chord_notes(names):
    return [midi(nm(n)) for n in names]


def render_menu_theme():
    """'Stargazing': 48 s at 80 BPM, D major with a lydian lift. Pad + kalimba + bells + bass."""
    sr = SR_LO
    bpm = 80.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 16
    L = int(round(bars * bar * sr))
    rng = np.random.default_rng(2026)
    out = np.zeros((2, L))
    prog = [  # (pad voicing, bass, arp tones) each 2 bars
        (["D4", "A4", "C#5", "E5", "F#5"], "D2", ["D5", "F#5", "A5", "C#6", "E6"]),
        (["B3", "F#4", "A4", "C#5", "D5"], "B1", ["B4", "D5", "F#5", "A5", "C#6"]),
        (["G3", "D4", "F#4", "A4", "C#5"], "G2", ["G5", "A5", "B5", "D6", "F#6"]),
        (["A3", "E4", "B4", "C#5", "E5"], "A2", ["A5", "B5", "C#6", "E6", "F#6"]),
        (["E4", "G4", "B4", "D5", "F#5"], "E2", ["E5", "G5", "B5", "D6", "F#6"]),
        (["G3", "D4", "F#4", "B4", "E5"], "G2", ["D5", "F#5", "G5", "B5", "E6"]),
        (["F#3", "D4", "A4", "C#5", "E5"], "F#2", ["F#5", "A5", "C#6", "D6", "E6"]),
        (["A3", "D4", "E4", "B4", "F#5"], "A2", ["A5", "B5", "D6", "E6", "A6"]),
    ]
    for ci, (pad, bass, arp) in enumerate(prog):
        t0 = ci * 2 * bar
        start = int(round(t0 * sr))
        # pad: L and R voices detuned differently, slow swells overlapping the next chord
        for vi, n in enumerate(pad):
            f = midi(nm(n))
            for ch, det in enumerate([(-7.0, 2.0), (-2.0, 8.0)]):
                p = pad_note(f, sr, 2 * bar + 0.4, 1.6, 2.2, rng, cutoff=1300, detune=det, bright=0.8)
                add(out[ch], p * 0.055, start - int(0.3 * sr), circular=True)
        # bass: one soft long note, a gentle re-strike on bar 2
        b = soft_bass(midi(nm(bass)), sr, 2 * bar + 1.0, decay=2.4)
        add(out, pan(b * 0.22, 0.0), start, circular=True)
        b2 = soft_bass(midi(nm(bass)) * 2, sr, bar, decay=1.0)
        add(out, pan(b2 * 0.07, 0.0), start + int(bar * sr), circular=True)
        # kalimba: sparse eighths, denser in the middle of the loop
        density = [0.28, 0.32, 0.5, 0.55, 0.6, 0.55, 0.4, 0.3][ci]
        last = -1
        for e in range(16):
            if e % 2 == 1 and rng.random() > 0.5:
                continue
            if rng.random() > density:
                continue
            idx = int(rng.integers(0, len(arp)))
            if idx == last:
                idx = (idx + 2) % len(arp)
            last = idx
            f = midi(nm(arp[idx]))
            vel = 0.55 + 0.45 * rng.random()
            swing = 0.03 * beat if e % 2 == 1 else 0.0
            k = kalimba(f, sr, 2.0, bright=0.7, decay=0.9)
            add(out, pan(k * 0.16 * vel, float(rng.uniform(-0.6, 0.6))),
                start + int((e * beat / 2 + swing) * sr), circular=True)
        # a bell every other chord, high and far
        if ci % 2 == 0:
            f = midi(nm(arp[int(rng.integers(2, len(arp)))])) * 2
            add(out, pan(celesta(f, sr, 3.0, bright=0.5) * 0.06, float(rng.uniform(-0.8, 0.8))),
                start + int((bar + 2 * beat) * sr), circular=True)
    # night air under it all (seamless: circular filter)
    air = fft_filter(pink(L, rng), sr, lo=300, hi=2500, circular=True)
    lfo = 0.6 + 0.4 * np.sin(TAU * 3 * np.arange(L) / L)
    out += np.stack([air, np.roll(air, L // 3)]) * lfo * 0.006
    out = with_reverb(out, sr, 3.2, 0.42, 2027, stereo=True, circular=True, damp_hz=3000)
    return out, sr, True


def render_campus_loop():
    """'Campus afternoon': 64 s at 90 BPM in F major. Marimba ostinato, plucked bass, a soft
    pad, a kalimba tune in the middle, a brushed shaker."""
    sr = SR_LO
    bpm = 90.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 24
    L = int(round(bars * bar * sr))
    rng = np.random.default_rng(1957)
    out = np.zeros((2, L))
    prog = [  # (pad, bass, marimba tones low -> high), 2 bars each
        (["F3", "A3", "C4", "E4"], "F2", ["F4", "A4", "C5", "E5"]),
        (["E3", "A3", "C4", "G4"], "A2", ["E4", "A4", "C5", "G5"]),
        (["D3", "F3", "A3", "D4"], "Bb1", ["D4", "F4", "Bb4", "D5"]),
        (["E3", "G3", "C4", "A4"], "C2", ["E4", "G4", "C5", "A5"]),
        (["D3", "F3", "A3", "C4"], "D2", ["D4", "F4", "A4", "C5"]),
        (["E3", "G3", "C4", "E4"], "A2", ["E4", "G4", "C5", "E5"]),
        (["D3", "F3", "A3", "E4"], "Bb1", ["D4", "F4", "A4", "E5"]),
        (["F3", "G3", "C4", "F4"], "C2", ["C4", "F4", "G4", "C5"]),
        (["F3", "A3", "C4", "E4"], "A1", ["F4", "A4", "C5", "E5"]),
        (["F3", "Bb3", "D4", "G4"], "G1", ["D4", "G4", "Bb4", "D5"]),
        (["D3", "F3", "A3", "C4"], "Bb1", ["D4", "F4", "A4", "C5"]),
        (["E3", "Bb3", "C4", "F4"], "C2", ["C4", "E4", "Bb4", "C5"]),
    ]
    patterns = [[0, 1, 2, 3, 2, 1, 2, 3], [0, 2, 1, 3, 0, 2, 3, 2], [0, 1, 2, 1, 3, 2, 1, 2],
                [0, 2, 3, 2, 1, 2, 3, 2], [0, None, 2, 3, None, 2, 1, None]]
    tune_scale = ["F5", "G5", "A5", "C6", "D6", "F6"]
    for ci, (pad, bass, tones) in enumerate(prog):
        start = int(round(ci * 2 * bar * sr))
        for n in pad:
            f = midi(nm(n))
            for ch, det in enumerate([(-6.0, 3.0), (-3.0, 7.0)]):
                p = pad_note(f, sr, 2 * bar + 0.3, 1.2, 1.6, rng, cutoff=1100, detune=det, bright=0.7)
                add(out[ch], p * 0.04, start - int(0.2 * sr), circular=True)
        # plucked bass on 1 and 3, sometimes the "and" of 4
        fb = midi(nm(bass))
        for b in range(2):
            for beat_i, g in [(0, 0.26), (2, 0.16)]:
                pos = start + int((b * bar + beat_i * beat) * sr)
                add(out, pan(soft_bass(fb, sr, 1.4, decay=0.45) * g, 0.0), pos, circular=True)
            if rng.random() < 0.4:
                pos = start + int((b * bar + 3.5 * beat) * sr)
                add(out, pan(soft_bass(fb * 1.5, sr, 0.6, decay=0.2) * 0.1, 0.0), pos, circular=True)
        # marimba ostinato (8ths), a pattern per chord, quieter at the loop's start and end
        pat = patterns[int(rng.integers(0, len(patterns)))]
        level = [0.6, 0.75, 0.9, 1.0, 1.0, 0.95, 1.0, 0.9, 0.85, 0.8, 0.7, 0.62][ci]
        for b in range(2):
            for e in range(8):
                ti = pat[e]
                if ti is None or (b == 1 and e == 7 and rng.random() < 0.5):
                    continue
                f = midi(nm(tones[ti]))
                vel = (1.0 if e % 2 == 0 else 0.7) * (0.85 + 0.15 * rng.random()) * level
                swing = 0.04 * beat if e % 2 == 1 else 0.0
                pos = start + int((b * bar + e * beat / 2 + swing) * sr)
                add(out, pan(marimba(f, sr, 1.0, bright=0.8) * 0.11 * vel, -0.35 + 0.1 * ti),
                    pos, circular=True)
        # kalimba tune through the middle third (chords 4..9)
        if 4 <= ci <= 9:
            t = 0.0
            while t < 2 * bar - 0.01:
                step = [beat, beat, 2 * beat, beat / 2 * 3][int(rng.integers(0, 4))]
                if rng.random() < 0.72:
                    f = midi(nm(tune_scale[int(rng.integers(0, len(tune_scale)))]))
                    add(out, pan(kalimba(f, sr, 1.8, bright=0.6, decay=0.8) * 0.13, 0.35),
                        start + int(t * sr), circular=True)
                t += step
    # brushed shaker on 8ths in the middle of the loop
    for i in range(bars * 8):
        b = i // 8
        if b < 4 or b >= 20:
            continue
        m = int(0.06 * sr)
        nz = fft_filter(rng.standard_normal(m), sr, lo=4000, hi=9500) * env_ar(m, sr, 0.008, 0.018)
        g = (0.012 if i % 2 == 0 else 0.02) * (0.7 + 0.3 * rng.random())
        swing = 0.04 * beat if i % 2 == 1 else 0.0
        add(out, pan(nz * g, 0.4), int((i * beat / 2 + swing) * sr), circular=True)
    out = with_reverb(out, sr, 2.4, 0.3, 1958, stereo=True, circular=True, damp_hz=3200)
    return out, sr, True


def render_stinger_milestone():
    sr = SR_LO
    L = int(5.0 * sr)
    out = np.zeros((2, L))
    rng = np.random.default_rng(77)
    for i, n in enumerate(["F4", "A4", "C5", "F5", "A5", "C6"]):
        add(out, pan(marimba(midi(nm(n)), sr, 1.4) * 0.22, -0.5 + 0.2 * i), int(i * 0.085 * sr))
    t0 = int(0.55 * sr)
    for n in ["F3", "C4", "E4", "G4", "A4", "D5"]:
        for ch, det in enumerate([(-6.0, 3.0), (-3.0, 7.0)]):
            p = pad_note(midi(nm(n)), sr, 1.8, 0.25, 1.8, rng, cutoff=1800, detune=det)
            add(out[ch], p * 0.06, t0)
    add(out, pan(soft_bass(midi(nm("F2")), sr, 3.0, decay=1.6) * 0.3, 0.0), t0)
    for i, n in enumerate(["C7", "A6", "F6", "C7", "G6"]):
        add(out, pan(celesta(midi(nm(n)), sr, 2.0, bright=0.6) * 0.1, float(rng.uniform(-0.8, 0.8))),
            t0 + int((0.12 + i * 0.16) * sr))
    out = with_reverb(out, sr, 2.2, 0.35, 78, stereo=True)[:, :L]
    return fade(out, sr, 0.001, 0.4), sr, False


def render_stinger_finale():
    sr = SR_LO
    L = int(9.0 * sr)
    out = np.zeros((2, L))
    rng = np.random.default_rng(88)
    chords = [(0.0, ["Bb2", "F3", "D4", "F4", "A4", "C5"], "Bb1"),
              (1.6, ["C3", "G3", "E4", "G4", "Bb4", "D5"], "C2"),
              (3.2, ["F3", "C4", "E4", "A4", "C5", "G5"], "F1")]
    for t, pad, bass in chords:
        hold = 1.7 if t < 3.0 else 3.6
        for n in pad:
            for ch, det in enumerate([(-6.0, 3.0), (-3.0, 7.0)]):
                p = pad_note(midi(nm(n)), sr, hold, 0.35, 2.4, rng, cutoff=1900, detune=det)
                add(out[ch], p * 0.05, int(t * sr))
        add(out, pan(soft_bass(midi(nm(bass)), sr, hold + 1.5, decay=2.0) * 0.32, 0.0), int(t * sr))
        # rising marimba run into each chord
        tones = pad[2:]
        for i, n in enumerate(tones + [tones[0][:-1] + str(int(tones[0][-1]) + 1)]):
            add(out, pan(marimba(midi(nm(n)) * 2, sr, 1.0) * 0.12, -0.6 + 0.25 * i), int((t + i * 0.09) * sr))
    # the last chord: soft drum swell and a shower of bells
    m = int(1.8 * sr)
    tt = secs(m, sr)
    drum = np.sin(TAU * np.cumsum(70 + 40 * np.exp(-tt / 0.08)) / sr) * env_ar(m, sr, 0.004, 0.5)
    add(out, pan(drum * 0.35, 0.0), int(3.2 * sr))
    for i in range(14):
        n = ["F6", "A6", "C7", "E7", "G6", "C7", "F7"][i % 7]
        add(out, pan(celesta(midi(nm(n)), sr, 2.4, bright=0.5) * 0.07 * (1 - i / 18),
                     float(rng.uniform(-0.9, 0.9))), int((3.3 + i * 0.13 + rng.uniform(0, 0.05)) * sr))
    out = with_reverb(out, sr, 3.0, 0.38, 89, stereo=True)[:, :L]
    return fade(out, sr, 0.001, 0.8), sr, False


# ------------------------------------------------------------------------ ambience
def bird_tweet(sr, rng, base):
    """2..4 quick rising pips."""
    count = int(rng.integers(2, 5))
    parts = []
    for i in range(count):
        d = rng.uniform(0.05, 0.08)
        n = int(d * sr)
        u = np.linspace(0, 1, n)
        f = base * (1.0 + 0.35 * u ** 0.7) * (1.0 - 0.06 * i)
        x = np.sin(TAU * np.cumsum(f) / sr) * np.sin(np.pi * u) ** 1.5
        parts.append(x)
        parts.append(np.zeros(int(rng.uniform(0.035, 0.06) * sr)))
    return np.concatenate(parts)


def bird_warble(sr, rng, base):
    d = rng.uniform(0.45, 0.8)
    n = int(d * sr)
    t = secs(n, sr)
    rate = rng.uniform(18, 28)
    f = base * (1.0 + 0.16 * np.sin(TAU * rate * t) + 0.08 * np.sin(TAU * 3.0 * t))
    am = (0.6 + 0.4 * np.sin(TAU * rate * t + 1.0) ** 2) * raised(n, sr, 0.04, 0.12, d - 0.12)
    return np.sin(TAU * np.cumsum(f) / sr) * am


def bird_feebee(sr, rng, base):
    out = []
    for f0, f1, d in [(base, base * 0.98, 0.26), (base * 0.84, base * 0.82, 0.3)]:
        n = int(d * sr)
        u = np.linspace(0, 1, n)
        f = f0 + (f1 - f0) * u
        out.append(np.sin(TAU * np.cumsum(f) / sr) * np.sin(np.pi * u) ** 0.8)
        out.append(np.zeros(int(0.05 * sr)))
    return np.concatenate(out)


def bird_coo(sr, rng, base):
    out = []
    for f, d, g in [(base, 0.28, 0.6), (base * 1.12, 0.42, 1.0), (base * 0.96, 0.32, 0.7)]:
        n = int(d * sr)
        u = np.linspace(0, 1, n)
        ff = f * (1.0 + 0.03 * np.sin(np.pi * u))
        ph = TAU * np.cumsum(ff) / sr
        out.append((np.sin(ph) + 0.15 * np.sin(2 * ph)) * np.sin(np.pi * u) ** 1.2 * g)
        out.append(np.zeros(int(0.08 * sr)))
    return np.concatenate(out)


def render_amb_day():
    sr = SR_LO
    dur = 40.0
    L = int(dur * sr)
    rng = np.random.default_rng(4040)
    x = np.zeros(L)
    u = np.arange(L) / L
    # breeze: pink noise with slow, loop-periodic swells
    wind = fft_filter(pink(L, rng), sr, lo=120, hi=900, circular=True)
    wl = 0.55 + 0.25 * np.sin(TAU * 2 * u + 0.4) + 0.2 * np.sin(TAU * 5 * u + 2.0)
    x += wind * wl * 0.032
    # leaves: bright noise in soft gusts
    leaves = fft_filter(white(L, rng), sr, lo=1800, hi=6000, circular=True)
    gust = np.zeros(L)
    for _ in range(9):
        c = rng.uniform(0, dur)
        w = rng.uniform(1.2, 3.0)
        tt = (np.arange(L) / sr - c + dur / 2) % dur - dur / 2
        gust += np.exp(-(tt / w) ** 2) * rng.uniform(0.4, 1.0)
    x += leaves * gust * 0.012
    # birds
    species = [(bird_tweet, (3300, 4300), 10), (bird_warble, (2800, 3600), 5),
               (bird_feebee, (3600, 4100), 5), (bird_coo, (480, 560), 3)]
    for make, (flo, fhi), count in species:
        for _ in range(count):
            b = make(sr, rng, rng.uniform(flo, fhi))
            dist = rng.uniform(0.25, 1.0)
            b = fft_filter(b, sr, hi=2500 + 5000 * dist)
            g = (0.08 if make is bird_coo else 0.14) * dist
            add(x, b * g, int(rng.uniform(0, dur) * sr), circular=True)
    x = with_reverb(x, sr, 1.6, 0.25, 4041, circular=True, damp_hz=4500)
    return x, sr, True


def cricket_chirp(sr, rng, f):
    pulses = int(rng.integers(3, 5))
    rate = rng.uniform(28, 40)
    d = pulses / rate
    n = int(d * sr)
    t = secs(n, sr)
    car = np.sin(TAU * f * t) + 0.2 * np.sin(TAU * 2 * f * t)
    am = np.clip(np.sin(TAU * rate * t), 0, 1) ** 2
    return car * am * raised(n, sr, 0.005, 0.01, d - 0.01)


def render_amb_night():
    sr = SR_LO
    dur = 40.0
    L = int(dur * sr)
    rng = np.random.default_rng(5050)
    x = np.zeros(L)
    u = np.arange(L) / L
    air = fft_filter(pink(L, rng), sr, lo=80, hi=450, circular=True)
    x += air * (0.7 + 0.3 * np.sin(TAU * 3 * u)) * 0.022
    # four crickets, near and far, each with its own rhythm and pauses
    for c in range(4):
        f = rng.uniform(4100, 5200)
        period = rng.uniform(0.55, 0.95)
        gain = [0.1, 0.065, 0.04, 0.03][c]
        t = rng.uniform(0, period)
        rest_at = rng.uniform(0, dur)
        rest_len = rng.uniform(4.0, 9.0)
        while t < dur:
            inrest = ((t - rest_at) % dur) < rest_len
            if not inrest:
                ch = cricket_chirp(sr, rng, f * rng.uniform(0.995, 1.005))
                if c >= 2:
                    ch = fft_filter(ch, sr, hi=3500 + 1500 * (3 - c))
                add(x, ch * gain * rng.uniform(0.8, 1.0), int(t * sr), circular=True)
            t += period * rng.uniform(0.94, 1.06)
    # a far-off owl, twice
    for at in (9.0, 29.5):
        out = []
        for f, d in [(380, 0.32), (0, 0.18), (395, 0.5)]:
            n = int(d * sr)
            if f == 0:
                out.append(np.zeros(n))
                continue
            uu = np.linspace(0, 1, n)
            ph = TAU * np.cumsum(f * (1.0 - 0.06 * uu)) / sr
            out.append((np.sin(ph) + 0.1 * np.sin(2 * ph)) * np.sin(np.pi * uu) ** 1.4)
        owl = fft_filter(np.concatenate(out), sr, hi=1200)
        add(x, owl * 0.05, int(at * sr), circular=True)
    x = with_reverb(x, sr, 2.2, 0.3, 5051, circular=True, damp_hz=4000)
    return x, sr, True


def render_amb_space():
    """A hush for the space shots of the menu: airy shimmer and two slow drones."""
    sr = SR_LO
    dur = 32.0
    L = int(dur * sr)
    rng = np.random.default_rng(6060)
    u = np.arange(L) / L
    t = np.arange(L) / sr
    x = np.zeros(L)
    hiss = fft_filter(pink(L, rng), sr, lo=1500, hi=7000, circular=True)
    x += hiss * (0.6 + 0.4 * np.sin(TAU * 2 * u)) * 0.012
    for f, cyc, g in [(midi(nm("A2")), 3, 0.05), (midi(nm("E3")), 4, 0.035), (midi(nm("B3")), 5, 0.02)]:
        k = round(f * dur) / dur    # an exact number of cycles per loop: seamless
        tone = np.sin(TAU * k * t) + 0.2 * np.sin(TAU * 2 * k * t)
        x += tone * (0.5 + 0.5 * np.sin(TAU * cyc * u + rng.random() * TAU)) * g
    x = with_reverb(x, sr, 3.5, 0.45, 6061, circular=True, damp_hz=3000)
    return x, sr, True


def modal_hit(sr, f0, ratios, decays, amps, noise_ms=4.0, seed=0, bright_hz=6000):
    rng = np.random.default_rng(seed)
    dur = max(decays) * 6
    n = int(dur * sr)
    t = secs(n, sr)
    x = np.zeros(n)
    for r, d, a in zip(ratios, decays, amps):
        x += a * np.sin(TAU * f0 * r * t + rng.random() * TAU) * np.exp(-t / d)
    m = int(noise_ms / 1000 * sr)
    nz = np.zeros(n)
    nz[:m] = rng.standard_normal(m) * np.linspace(1, 0, m) ** 2
    x += 0.4 * fft_filter(nz, sr, lo=500, hi=bright_hz)
    return fade(x, sr, 0.0008, 0.05)


def s_workshop(i):
    def make():
        sr = SR
        if i == 0:   # light hammer tink on metal
            x = modal_hit(sr, 1750, [1, 2.76, 5.4, 8.93], [0.28, 0.16, 0.08, 0.04], [1, 0.5, 0.3, 0.15], seed=70)
            x2 = modal_hit(sr, 1750, [1, 2.76, 5.4], [0.2, 0.1, 0.06], [1, 0.5, 0.3], seed=71)
            y = np.zeros(int(0.9 * sr))
            add(y, x, 0)
            add(y, x2 * 0.6, int(0.32 * sr))
        elif i == 1:  # deeper clank
            y = modal_hit(sr, 410, [1, 1.58, 2.31, 3.7, 5.1], [0.35, 0.25, 0.15, 0.08, 0.05],
                          [1, 0.6, 0.45, 0.25, 0.12], noise_ms=8, seed=72)
        elif i == 2:  # ratchet: a run of little clicks
            y = np.zeros(int(0.7 * sr))
            for k in range(6):
                c = modal_hit(sr, 2600, [1, 2.3, 4.1], [0.012, 0.008, 0.005], [1, 0.6, 0.4], noise_ms=2, seed=73 + k)
                add(y, c * (0.8 + 0.2 * (k % 2)), int(k * 0.07 * sr))
        else:         # wooden crate thunk
            y = modal_hit(sr, 170, [1, 2.1, 3.3], [0.09, 0.05, 0.03], [1, 0.4, 0.2], noise_ms=12, seed=80,
                          bright_hz=2500)
        y = fft_filter(y, sr, hi=4500, lo=120)        # a little distance
        y = with_reverb(y, sr, 1.0, 0.3, 90 + i)
        return fade(y, sr, 0.0008, 0.08), sr, False
    return make


# ------------------------------------------------------------------------ launch
def s_countdown_tick():
    n = int(0.22 * SR)
    t = secs(n, SR)
    f = midi(nm("C6"))
    x = (np.sin(TAU * f * t) + 0.12 * np.sin(TAU * 2 * f * t)) * env_adsr(n, SR, 0.006, 0.05, 0.4, 0.04, 0.09)
    return fade(x, SR, 0.002, 0.03), SR, False


def s_countdown_go():
    y = np.zeros(int(0.6 * SR))
    for i, nn in enumerate(["C6", "G6"]):
        n = int(0.28 * SR)
        t = secs(n, SR)
        f = midi(nm(nn))
        x = (np.sin(TAU * f * t) + 0.12 * np.sin(TAU * 2 * f * t)) * env_adsr(n, SR, 0.006, 0.06, 0.5, 0.06, 0.14)
        add(y, x, int(i * 0.12 * SR))
    add(y, celesta(midi(nm("G6")), SR, 0.5, bright=0.5) * 0.3, int(0.12 * SR))
    return fade(y, SR, 0.002, 0.05), SR, False


def rumble_layers(L, sr, rng, circular):
    body = fft_filter(brown(L, rng), sr, lo=28, hi=260, circular=circular)
    roar = fft_filter(pink(L, rng), sr, lo=180, hi=1400, circular=circular)
    # crackle: sparse soft pops
    cr = np.zeros(L)
    for _ in range(int(L / sr * 18)):
        p = int(rng.integers(0, L))
        m = int(rng.uniform(0.002, 0.006) * sr)
        pop = rng.standard_normal(m) * np.linspace(1, 0, m) ** 2
        add(cr, pop * rng.uniform(0.3, 1.0), p, circular=True)
    cr = fft_filter(cr, sr, lo=600, hi=3500, circular=circular)
    return body, roar, cr


def s_launch_ignition():
    """1.4 s of valves hissing and the engine spooling up, the ignition thump, then a
    second and a half of full roar that the rumble loop takes over from."""
    sr = SR
    dur = 3.2
    L = int(dur * sr)
    rng = np.random.default_rng(300)
    t = secs(L, sr)
    ig = 1.4
    body, roar, cr = rumble_layers(L, sr, rng, False)
    build = np.clip(t / ig, 0, 1) ** 2.2
    full = np.where(t < ig, build * 0.45, 1.0)
    tail = np.where(t > 2.4, np.exp(-(t - 2.4) / 0.6), 1.0)
    hiss = fft_filter(white(L, rng), sr, lo=2500, hi=7000) * raised(L, sr, 0.5, 0.5, ig - 0.1) * 0.35
    x = (body / np.std(body) * 0.9 + roar / np.std(roar) * 0.45 * full + cr / (np.std(cr) + 1e-9) * 0.12 * full)
    x = x * full * tail + hiss
    m = int(0.8 * sr)
    tt = secs(m, sr)
    thump = np.sin(TAU * np.cumsum(55 + 70 * np.exp(-tt / 0.05)) / sr) * env_ar(m, sr, 0.003, 0.22)
    add(x, thump * 2.2, int(ig * sr))
    x = fft_filter(x, sr, lo=25, hi=5000)
    return fade(x, sr, 0.05, 0.3), sr, False


def s_launch_rumble():
    sr = SR_LO
    L = int(6.0 * sr)
    rng = np.random.default_rng(301)
    u = np.arange(L) / L
    body, roar, cr = rumble_layers(L, sr, rng, True)
    wob = 1.0 + 0.12 * np.sin(TAU * 7 * u) + 0.08 * np.sin(TAU * 13 * u + 1.0)
    x = (body / np.std(body) * 0.9 + roar / np.std(roar) * 0.45 + cr / (np.std(cr) + 1e-9) * 0.12) * wob
    return x, sr, True


def s_launch_sputter():
    sr = SR
    rng = np.random.default_rng(310)
    n = int(0.45 * sr)
    y = np.zeros(n)
    for k, (at, g) in enumerate([(0.0, 1.0), (0.11, 0.7), (0.19, 0.45)]):
        m = int(0.09 * sr)
        nz = fft_filter(rng.standard_normal(m), sr, lo=250, hi=1600) * env_ar(m, sr, 0.004, 0.03)
        nz /= np.max(np.abs(nz)) + 1e-9
        tt = secs(m, sr)
        pop = np.sin(TAU * np.cumsum(140 - 60 * tt / 0.09) / sr) * env_ar(m, sr, 0.002, 0.025)
        add(y, (nz * 0.7 + pop * 0.6) * g, int(at * sr))
    return fade(y, sr, 0.001, 0.05), sr, False


def s_launch_engine_cut():
    sr = SR
    rng = np.random.default_rng(320)
    n = int(1.1 * sr)
    u = np.linspace(0, 1, n)
    fc = 1200 * (120 / 1200) ** u
    nz = biquad_bp(pink(n, rng), sr, fc, 0.9)
    nz /= np.max(np.abs(nz)) + 1e-9
    e = (1 - u) ** 1.5
    tone = sine_glide(180, 60, sr, 1.1) * e * 0.5
    return fade((nz * 0.8 * e + tone), sr, 0.005, 0.1), sr, False


def s_launch_fall_whistle():
    sr = SR
    n = int(1.15 * sr)
    t = secs(n, sr)
    u = t / t[-1]
    f = 1350 * (480 / 1350) ** (u ** 1.3) * (1 + 0.012 * np.sin(TAU * 7.5 * t))
    ph = TAU * np.cumsum(f) / sr
    x = (np.sin(ph) + 0.08 * np.sin(2 * ph)) * raised(n, sr, 0.08, 0.2, 0.95)
    rng = np.random.default_rng(330)
    breath = fft_filter(rng.standard_normal(n), sr, lo=1500, hi=5000) * raised(n, sr, 0.08, 0.2, 0.95)
    return fade(x + 0.03 * breath / (np.std(breath) + 1e-9) * 0.1, sr, 0.005, 0.05), sr, False


def s_launch_fwoomp():
    """The failure: a soft, cushioned 'fwoomp' (no explosion), a puff of air and a low thud."""
    sr = SR
    n = int(2.2 * sr)
    t = secs(n, sr)
    rng = np.random.default_rng(340)
    u = np.clip(t / 0.9, 0, 1)
    fc = 1600 * (160 / 1600) ** u
    puff = biquad_bp(pink(n, rng), sr, fc, 0.8) * env_ar(n, sr, 0.03, 0.35)
    puff /= np.max(np.abs(puff)) + 1e-9
    thud = np.sin(TAU * np.cumsum(48 + 70 * np.exp(-t / 0.07)) / sr) * env_ar(n, sr, 0.006, 0.35)
    body = fft_filter(brown(n, rng), sr, lo=30, hi=200) * env_ar(n, sr, 0.02, 0.5)
    body /= np.max(np.abs(body)) + 1e-9
    x = puff * 0.75 + thud * 0.9 + body * 0.4
    x = with_reverb(x, sr, 1.6, 0.25, 341)[:n]
    return fade(x, sr, 0.002, 0.3), sr, False


def s_launch_debris():
    sr = SR
    n = int(2.4 * sr)
    y = np.zeros(n)
    rng = np.random.default_rng(350)
    tt = 0.15
    k = 0
    while tt < 1.9:
        f0 = rng.uniform(900, 2600)
        hit = modal_hit(sr, f0, [1, 2.76, 5.4], [0.07, 0.04, 0.02], [1, 0.4, 0.2], noise_ms=3, seed=351 + k)
        add(y, hit * rng.uniform(0.3, 0.8) * (1.0 - tt / 2.4), int(tt * sr))
        tt += rng.uniform(0.05, 0.22) * (1 + tt)
        k += 1
    for at, f0 in [(0.25, 150), (0.8, 120)]:
        th = modal_hit(sr, f0, [1, 2.1], [0.08, 0.04], [1, 0.3], noise_ms=10, seed=360 + int(f0), bright_hz=1500)
        add(y, th * 0.9, int(at * sr))
    y = fft_filter(y, sr, hi=5000)
    y = with_reverb(y, sr, 1.2, 0.25, 362)[:n]
    return fade(y, sr, 0.001, 0.2), sr, False


def crowd(sr, rng, voices, dur, pitch_fn, syl_fn, clap_density, clap_gain):
    n = int(dur * sr)
    y = np.zeros(n)
    for v in range(voices):
        f0 = rng.uniform(480, 760)
        x = cometling_voice(syl_fn(rng), sr, f0 * pitch_fn(rng), int(rng.integers(0, 1 << 30)), vibrato=0.03)
        add(y, x * rng.uniform(0.4, 1.0), int(rng.uniform(0.0, dur * 0.45) * sr))
    if clap_density:
        for _ in range(int(clap_density * dur)):
            at = rng.uniform(0.05, dur - 0.2)
            dens = math.exp(-at / (dur * 0.6))
            if rng.random() > dens:
                continue
            m = int(0.03 * sr)
            c = fft_filter(rng.standard_normal(m), sr, lo=900, hi=3500) * env_ar(m, sr, 0.001, 0.008)
            add(y, c * clap_gain * rng.uniform(0.3, 1.0), int(at * sr))
    return y


def s_crowd_cheer():
    sr = SR
    rng = np.random.default_rng(370)
    syls = lambda r: [syl(r.uniform(0.3, 0.55), 1.15, r.uniform(1.4, 1.7), "e", "a", 0.0)] if r.random() < 0.6 else \
        [syl(0.08, 1.3, 1.4, "i", "i", 0.03), syl(r.uniform(0.25, 0.4), 1.5, 1.25, "a", "y", 0.0)]
    y = crowd(sr, rng, 16, 3.8, lambda r: r.uniform(0.9, 1.15), syls, 260, 0.5)
    y = with_reverb(y, sr, 1.4, 0.25, 371)[: y.size]
    return fade(y, sr, 0.01, 0.6), sr, False


def s_crowd_aww():
    sr = SR
    rng = np.random.default_rng(380)
    syls = lambda r: [syl(r.uniform(0.45, 0.7), 1.1, r.uniform(0.7, 0.8), "a", "u", 0.0)]
    y = crowd(sr, rng, 10, 2.4, lambda r: r.uniform(0.9, 1.1), syls, 0, 0)
    y = with_reverb(y, sr, 1.4, 0.25, 381)[: y.size]
    return fade(y, sr, 0.01, 0.4), sr, False


def s_confetti_pop():
    sr = SR
    n = int(1.2 * sr)
    y = np.zeros(n)
    rng = np.random.default_rng(390)
    m = int(0.05 * sr)
    tt = secs(m, sr)
    pop = np.sin(TAU * np.cumsum(900 * np.exp(-tt / 0.01) + 250) / sr) * env_ar(m, sr, 0.001, 0.012)
    pop += fft_filter(rng.standard_normal(m), sr, lo=1200, hi=6000) * env_ar(m, sr, 0.001, 0.006) * 0.5
    add(y, pop, 0)
    for i in range(7):
        f = midi(nm(["C7", "E7", "G7", "A6", "D7", "G6", "C7"][i]))
        add(y, celesta(f, sr, 0.8, bright=0.5) * 0.18, int((0.05 + i * 0.06 + rng.uniform(0, 0.03)) * sr))
    y = with_reverb(y, sr, 1.0, 0.25, 391)[:n]
    return fade(y, sr, 0.001, 0.2), sr, False


def _result(notes, gaps, inst, extra=None, seed=0, dur=2.6, tail_gain=0.0):
    def make():
        sr = SR
        y = np.zeros(int(dur * sr))
        t = 0.0
        for nn, g in zip(notes, gaps):
            for one in nn.split("+"):
                add(y, inst(midi(nm(one)), sr) * 0.5, int(t * sr))
            t += g
        if extra:
            extra(y, sr)
        y = with_reverb(y, sr, 1.6, 0.3, seed)[: y.size]
        return fade(y, sr, 0.001, 0.4), sr, False
    return make


def _success_sparkle(y, sr):
    for i, nn in enumerate(["C7", "E7", "G7"]):
        add(y, celesta(midi(nm(nn)), sr, 1.2, bright=0.5) * 0.15, int((0.45 + i * 0.07) * sr))
    rng = np.random.default_rng(401)
    p = pad_note(midi(nm("F4")), sr, 0.9, 0.2, 1.0, rng, cutoff=1600)
    p += pad_note(midi(nm("C5")), sr, 0.9, 0.2, 1.0, rng, cutoff=1600)
    p += pad_note(midi(nm("A4")), sr, 0.9, 0.2, 1.0, rng, cutoff=1600)
    add(y, p * 0.07, int(0.35 * sr))


def _partial_pad(y, sr):
    rng = np.random.default_rng(402)
    for nn in ["C4", "G4", "D5"]:
        add(y, pad_note(midi(nm(nn)), sr, 1.0, 0.25, 1.0, rng, cutoff=1300) * 0.06, int(0.3 * sr))


def _fail_pad(y, sr):
    rng = np.random.default_rng(403)
    for nn in ["D4", "F4", "A4"]:
        add(y, pad_note(midi(nm(nn)), sr, 0.8, 0.3, 1.2, rng, cutoff=1000) * 0.05, int(0.2 * sr))


# ------------------------------------------------------------------------ the conference fair
def soft_brass(f: float, sr: int, dur: float, attack=0.035, release=0.18, bright=1.0, vib=0.006) -> np.ndarray:
    """A round, cushioned 'brass': harmonics that open up with the swell (the higher ones
    later and softer), a touch of late vibrato. No blat, no buzz."""
    n = int((dur + release) * sr)
    t = secs(n, sr)
    env = raised(n, sr, attack, release, dur)
    v = 1.0 + vib * np.clip((t - 0.15) / 0.2, 0, 1) * np.sin(TAU * 5.5 * t)
    ph = TAU * f * np.cumsum(v) / sr
    x = np.zeros(n)
    kmax = int(min(12, (sr * 0.42) / f))
    for k in range(1, kmax + 1):
        a = (1.0 / k ** 1.2) * (bright if k > 1 else 1.0)
        x += a * np.sin(k * ph) * env ** (1.0 + 0.35 * (k - 1))
    return x


def clap(sr, rng, bright=1.0):
    """One hand clap: three quick micro-bursts and a little room."""
    m = int(0.06 * sr)
    y = np.zeros(m)
    for j, at in enumerate([0.0, 0.004, 0.009]):
        k = int(0.012 * sr)
        b = rng.standard_normal(k) * env_ar(k, sr, 0.0005, 0.003 if j < 2 else 0.009)
        add(y, b * (0.6 if j < 2 else 1.0), int(at * sr))
    return fft_filter(y, sr, lo=700, hi=2600 + 1200 * bright)


def babble_phrase(sr, rng, f0):
    """A few syllables of distant Cometling chatter."""
    vs = list(VOWELS)
    syls = []
    for i in range(int(rng.integers(2, 7))):
        a0 = rng.uniform(0.9, 1.25)
        syls.append(syl(rng.uniform(0.07, 0.17), a0, a0 * rng.uniform(0.85, 1.2), vs[int(rng.integers(0, 6))],
                        vs[int(rng.integers(0, 6))], rng.uniform(0.015, 0.05), rng.uniform(0.6, 1.0)))
    return cometling_voice(syls, sr, f0, int(rng.integers(0, 1 << 30)), breath=0.02, vibrato=0.02)


def _fair_crowd(L, sr, rng, dur, phrases_per_s, laugh_odds):
    """The murmur of a happy crowd: many little phrases at many distances, a warm body of
    room noise under them, now and then a laugh or a few claps."""
    x = np.zeros(L)
    u = np.arange(L) / L
    body = fft_filter(pink(L, rng), sr, lo=180, hi=1100, circular=True)
    x += body * (0.75 + 0.25 * np.sin(TAU * 3 * u + 1.3)) * 0.018
    for _ in range(int(dur * phrases_per_s)):
        dist = rng.uniform(0.15, 1.0) ** 1.5
        p = babble_phrase(sr, rng, rng.uniform(470, 760))
        p = fft_filter(p, sr, hi=900 + 2200 * dist)
        add(x, p * 0.05 * (0.3 + 0.7 * dist), int(rng.uniform(0, dur) * sr), circular=True)
        if rng.random() < laugh_odds:   # "hi-hi-hi!"
            f0 = rng.uniform(560, 720)
            lau = cometling_voice([syl(0.07, 1.3, 1.25, "i", "i", 0.04), syl(0.07, 1.25, 1.2, "i", "i", 0.04),
                                   syl(0.1, 1.2, 1.05, "i", "e", 0.0)], sr, f0, int(rng.integers(0, 1 << 30)))
            add(x, fft_filter(lau, sr, hi=2600) * 0.04 * dist, int(rng.uniform(0, dur) * sr), circular=True)
    for _ in range(int(dur / 9)):     # a little round of claps somewhere
        at = rng.uniform(0, dur)
        for _k in range(int(rng.integers(5, 12))):
            add(x, clap(sr, rng, 0.3) * 0.05, int((at + rng.uniform(0, 1.2)) * sr), circular=True)
    return x


def render_amb_fair_day():
    sr = SR_LO
    dur = 40.0
    L = int(dur * sr)
    rng = np.random.default_rng(7070)
    x = _fair_crowd(L, sr, rng, dur, 5.5, 0.12)
    # birds over the plaza, fewer than on campus (the crowd scares them a bit)
    for make, (flo, fhi), count in [(bird_tweet, (3300, 4300), 6), (bird_warble, (2800, 3600), 3),
                                    (bird_feebee, (3600, 4100), 2)]:
        for _ in range(count):
            b = make(sr, rng, rng.uniform(flo, fhi))
            dist = rng.uniform(0.3, 0.9)
            add(x, fft_filter(b, sr, hi=2500 + 4000 * dist) * 0.1 * dist, int(rng.uniform(0, dur) * sr), circular=True)
    # flags and a breeze
    wind = fft_filter(pink(L, rng), sr, lo=150, hi=800, circular=True)
    x += wind * (0.6 + 0.4 * np.sin(TAU * 2 * np.arange(L) / L)) * 0.012
    x = with_reverb(x, sr, 1.4, 0.25, 7071, circular=True, damp_hz=4000)
    return x, sr, True


def render_amb_fair_night():
    sr = SR_LO
    dur = 40.0
    L = int(dur * sr)
    rng = np.random.default_rng(7080)
    x = _fair_crowd(L, sr, rng, dur, 4.0, 0.1)
    # the evening's crickets at the edge of the plaza
    for c in range(3):
        f = rng.uniform(4200, 5100)
        period = rng.uniform(0.6, 0.95)
        gain = [0.05, 0.035, 0.025][c]
        t = rng.uniform(0, period)
        while t < dur:
            ch = fft_filter(cricket_chirp(sr, rng, f), sr, hi=4200)
            add(x, ch * gain * rng.uniform(0.7, 1.0), int(t * sr), circular=True)
            t += period * rng.uniform(0.94, 1.08)
    x = with_reverb(x, sr, 1.8, 0.3, 7081, circular=True, damp_hz=3600)
    return x, sr, True


def render_music_fair():
    """'Feira dos Cometinhos': 16 bars at 104 BPM in G major, heard from across the plaza. A
    squeeze-box oom-pah, a plucked bass, a marimba tune and a tambourine, all softened by
    distance (low-passed, a lot of room)."""
    sr = SR_LO
    bpm = 104.0
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 16
    L = int(round(bars * bar * sr))
    rng = np.random.default_rng(2112)
    out = np.zeros((2, L))
    prog = [("G2", ["G3", "B3", "D4"], ["G5", "B5", "D6", "B5"]), ("D2", ["F#3", "A3", "D4"], ["A5", "F#5", "D5", "F#5"]),
            ("C2", ["E3", "G3", "C4"], ["E5", "G5", "C6", "E6"]), ("D2", ["F#3", "A3", "C4"], ["D6", "C6", "A5", "F#5"]),
            ("G2", ["G3", "B3", "D4"], ["B5", "D6", "G6", "D6"]), ("E2", ["G3", "B3", "E4"], ["E6", "B5", "G5", "B5"]),
            ("A2", ["A3", "C4", "E4"], ["C6", "A5", "E5", "A5"]), ("D2", ["F#3", "A3", "C4"], ["A5", "B5", "C6", "D6"])]
    for b in range(bars):
        bass, chord, tune = prog[b % len(prog)]
        start = int(round(b * bar * sr))
        fb = midi(nm(bass))
        # oom (bass on 1 and 3, the fifth on 3) - pah (squeeze-box chord on 2 and 4)
        add(out, pan(soft_bass(fb, sr, 0.7, decay=0.3) * 0.3, 0.0), start, circular=True)
        add(out, pan(soft_bass(fb * 1.5, sr, 0.7, decay=0.3) * 0.22, 0.0), start + int(2 * beat * sr), circular=True)
        for k in (1, 3):
            for n in chord:
                p = pad_note(midi(nm(n)), sr, beat * 0.45, 0.012, 0.08, rng, cutoff=2400, detune=(-9.0, 9.0), bright=1.1)
                add(out, pan(p * 0.05, -0.3), start + int(k * beat * sr), circular=True)
        # the tune: chord tones on eighths, some held, the last bar of each phrase resting
        if b % 4 != 3 or rng.random() < 0.5:
            for e in range(8):
                if rng.random() < (0.35 if e % 2 else 0.12):
                    continue
                f = midi(nm(tune[(e // 2 + (e % 2) * int(rng.integers(0, 2))) % 4]))
                swing = 0.05 * beat if e % 2 else 0.0
                add(out, pan(marimba(f, sr, 0.9, bright=0.9) * 0.15 * (1.0 if e % 2 == 0 else 0.75), 0.3),
                    start + int((e * beat / 2 + swing) * sr), circular=True)
        # tambourine on the off-beats
        for e in range(8):
            if e % 2 == 0 and rng.random() < 0.7:
                continue
            m = int(0.09 * sr)
            nz = fft_filter(rng.standard_normal(m), sr, lo=5000, hi=10000) * env_ar(m, sr, 0.002, 0.03)
            jingle = sum(np.sin(TAU * f * secs(m, sr)) for f in (6100.0, 7300.0, 8200.0)) * env_ar(m, sr, 0.001, 0.04)
            add(out, pan((nz + 0.15 * jingle) * 0.02, 0.5), start + int((e * beat / 2) * sr), circular=True)
    # far away: the top end goes, the room comes in
    out = fft_filter(out, sr, hi=2300, lo=90, circular=True)
    out = with_reverb(out, sr, 2.6, 0.5, 2113, stereo=True, circular=True, damp_hz=2200)
    return out, sr, True


def s_fair_step(i):
    """A Cometling's soft footstep on the plaza's paving: a padded pat and a whisper of grit."""
    def make():
        sr = SR
        rng = np.random.default_rng(7100 + i)
        n = int(0.16 * sr)
        t = secs(n, sr)
        pat = fft_filter(rng.standard_normal(n), sr, lo=120, hi=900 + 150 * i) * env_ar(n, sr, 0.002, 0.016)
        pat /= np.max(np.abs(pat)) + 1e-9
        thump = np.sin(TAU * np.cumsum(95 + 60 * np.exp(-t / 0.012) + 8 * i) / sr) * env_ar(n, sr, 0.002, 0.028)
        grit = fft_filter(rng.standard_normal(n), sr, lo=2500, hi=6500) * env_ar(n, sr, 0.003, 0.01 + 0.004 * i)
        grit /= np.max(np.abs(grit)) + 1e-9
        x = pat * 0.7 + thump * 0.55 + grit * 0.12
        return fade(x, sr, 0.001, 0.04), sr, False
    return make


def s_fair_talk_chime():
    """Someone to talk to is in reach: two soft bells, up."""
    x = np.zeros(int(0.7 * SR))
    add(x, kalimba(midi(nm("G6")), SR, 0.6, bright=0.5, decay=0.3), 0, gain=0.8)
    add(x, kalimba(midi(nm("D7")), SR, 0.55, bright=0.5, decay=0.28), int(0.07 * SR), gain=0.65)
    y = with_reverb(x, SR, 0.9, 0.22, 7120)[: x.size]
    return fade(y, SR, 0.001, 0.08), SR, False


def s_fair_fanfare():
    """The award: a soft brass 'ta-ta-ta-taaa' over a warm chord, a timpani roll into it and
    bells on top. Stereo, played as a stinger."""
    sr = SR
    L = int(3.4 * sr)
    out = np.zeros((2, L))
    rng = np.random.default_rng(7130)
    # a short soft roll into the first note
    for k in range(12):
        m = int(0.25 * sr)
        tt = secs(m, sr)
        hit = np.sin(TAU * np.cumsum(98 + 25 * np.exp(-tt / 0.03)) / sr) * env_ar(m, sr, 0.002, 0.09)
        add(out, pan(hit * (0.04 + 0.011 * k), 0.0), int(k * 0.028 * sr))
    t0 = 0.36
    motif = [("G4", 0.0, 0.11), ("G4", 0.15, 0.11), ("G4", 0.3, 0.11), ("C5", 0.45, 0.42), ("E5", 0.92, 0.16),
             ("D5", 1.1, 0.16), ("G5", 1.28, 1.1)]
    for n, at, d in motif:
        f = midi(nm(n))
        for ch, (det, g) in enumerate([(0.997, 1.0), (1.003, 0.9)]):
            add(out[ch], soft_brass(f * det, sr, d, attack=0.03, release=0.2, bright=0.9) * 0.18 * g, int((t0 + at) * sr))
        add(out, pan(soft_brass(f / 2, sr, d, attack=0.04, release=0.2, bright=0.6) * 0.08, 0.0), int((t0 + at) * sr))
    # the chord under the last two notes
    for n in ["C3", "G3", "C4", "E4", "G4"]:
        for ch, det in enumerate([(-6.0, 3.0), (-3.0, 7.0)]):
            p = pad_note(midi(nm(n)), sr, 1.3, 0.12, 1.2, rng, cutoff=1900, detune=det)
            add(out[ch], p * 0.04, int((t0 + 1.28) * sr))
    m = int(1.2 * sr)
    tt = secs(m, sr)
    boom = np.sin(TAU * np.cumsum(65 + 40 * np.exp(-tt / 0.06)) / sr) * env_ar(m, sr, 0.004, 0.4)
    add(out, pan(boom * 0.3, 0.0), int((t0 + 1.28) * sr))
    for i, n in enumerate(["C7", "E7", "G7", "C7", "E7"]):
        add(out, pan(celesta(midi(nm(n)), sr, 1.4, bright=0.5) * 0.08, float(rng.uniform(-0.8, 0.8))),
            int((t0 + 1.35 + i * 0.09) * sr))
    out = with_reverb(out, sr, 2.0, 0.32, 7131, stereo=True)[:, :L]
    return fade(out, sr, 0.001, 0.5), sr, False


def s_fair_applause():
    """A plaza of Cometlings clapping (a swell, a long middle, a tail), a few cheers in it."""
    sr = SR
    dur = 4.8
    n = int(dur * sr)
    rng = np.random.default_rng(7140)
    y = np.zeros(n)
    for c in range(36):
        rate = rng.uniform(3.6, 5.4)
        t = rng.uniform(0.0, 0.5)
        stop = rng.uniform(2.6, dur - 0.3)
        g = rng.uniform(0.3, 1.0) * (0.5 if c > 24 else 1.0)
        bright = rng.uniform(0.0, 1.0)
        while t < stop:
            add(y, clap(sr, rng, bright) * g * rng.uniform(0.7, 1.0), int(t * sr))
            t += (1.0 / rate) * rng.uniform(0.9, 1.1)
    e = raised(n, sr, 0.35, 1.6, dur - 1.6)
    y *= e
    syls = lambda r: [syl(r.uniform(0.3, 0.5), 1.15, r.uniform(1.4, 1.7), "e", "a", 0.0)]
    cheer = crowd(sr, rng, 8, dur, lambda r: r.uniform(0.95, 1.15), syls, 0, 0)
    y = y / (np.max(np.abs(y)) + 1e-9) + cheer / (np.max(np.abs(cheer)) + 1e-9) * 0.35
    y = with_reverb(y, sr, 1.5, 0.28, 7141)[:n]
    return fade(y, sr, 0.01, 0.5), sr, False


# ------------------------------------------------------------------------ the flight comic
def s_comic_page():
    """A comic page turning: a papery swish rising and settling, a little crinkle, the flap."""
    sr = SR
    rng = np.random.default_rng(7200)
    n = int(0.46 * sr)
    u = np.linspace(0, 1, n)
    fc = 900 + 2600 * np.sin(np.pi * np.clip(u * 1.2, 0, 1)) ** 1.2
    sw = biquad_bp(pink(n, rng), sr, fc, 0.9)
    sw /= np.max(np.abs(sw)) + 1e-9
    e = np.clip(u / 0.45, 0, 1) ** 1.4 * np.clip((1 - u) / 0.45, 0, 1) ** 0.8
    x = sw * e * 0.7
    cr = np.zeros(n)
    for _ in range(14):
        m = int(rng.uniform(0.002, 0.005) * sr)
        add(cr, rng.standard_normal(m) * np.linspace(1, 0, m) ** 2 * rng.uniform(0.3, 1.0), int(rng.uniform(0.1, 0.32) * sr))
    x += fft_filter(cr, sr, lo=2000, hi=6500) * 0.35
    m = int(0.08 * sr)
    flap = fft_filter(rng.standard_normal(m), sr, lo=80, hi=500) * env_ar(m, sr, 0.003, 0.02)
    add(x, flap / (np.max(np.abs(flap)) + 1e-9) * 0.45, int(0.33 * sr))
    return fade(x, sr, 0.003, 0.04), sr, False


def s_comic_pop():
    """A panel pops in: a soft bubble 'bup' and a tiny glint."""
    sr = SR
    n = int(0.2 * sr)
    t = secs(n, sr)
    f = 380 + 700 * (1 - np.exp(-t / 0.012)) - 250 * np.clip((t - 0.03) / 0.08, 0, 1)
    x = np.sin(TAU * np.cumsum(f) / sr) * env_ar(n, sr, 0.003, 0.04)
    add(x, kalimba(midi(nm("C7")), sr, 0.18, bright=0.4, decay=0.06) * 0.25, int(0.012 * sr))
    return fade(x, sr, 0.001, 0.04), sr, False


def s_comic_vroom():
    """VRUUUM: a cushioned engine swell, more rumble than roar."""
    sr = SR
    rng = np.random.default_rng(7210)
    n = int(0.85 * sr)
    u = np.linspace(0, 1, n)
    t = secs(n, sr)
    fc = 220 + 520 * np.sin(np.pi * u) ** 0.8
    nz = biquad_bp(pink(n, rng), sr, fc, 1.1)
    nz /= np.max(np.abs(nz)) + 1e-9
    e = np.sin(np.pi * np.clip(u, 0, 1)) ** 0.9
    hum = np.sin(TAU * np.cumsum(70 + 45 * u + 6 * np.sin(TAU * 11 * t)) / sr) * e
    x = nz * e * 0.7 + hum * 0.45
    return fade(fft_filter(x, sr, hi=2200), sr, 0.01, 0.08), sr, False


def s_comic_clac():
    """CLAC: two little wooden clacks (a latch letting go)."""
    sr = SR
    y = np.zeros(int(0.32 * sr))
    add(y, modal_hit(sr, 820, [1, 2.4, 4.6], [0.03, 0.015, 0.008], [1, 0.45, 0.2], noise_ms=3, seed=7220,
                     bright_hz=4500), 0)
    add(y, modal_hit(sr, 1180, [1, 2.4, 4.6], [0.025, 0.012, 0.006], [1, 0.4, 0.2], noise_ms=2, seed=7221,
                     bright_hz=5000) * 0.8, int(0.055 * sr))
    return fade(with_reverb(y, sr, 0.5, 0.15, 7222)[: y.size], sr, 0.0008, 0.05), sr, False


def s_comic_boom():
    """KABUM, the cosy way: a puff and a pillowy thud, no bang."""
    sr = SR
    n = int(1.1 * sr)
    t = secs(n, sr)
    rng = np.random.default_rng(7230)
    u = np.clip(t / 0.5, 0, 1)
    puff = biquad_bp(pink(n, rng), sr, 1300 * (180 / 1300) ** u, 0.8) * env_ar(n, sr, 0.015, 0.18)
    puff /= np.max(np.abs(puff)) + 1e-9
    thud = np.sin(TAU * np.cumsum(55 + 80 * np.exp(-t / 0.05)) / sr) * env_ar(n, sr, 0.004, 0.22)
    x = puff * 0.6 + thud * 0.9
    x = with_reverb(x, sr, 1.0, 0.2, 7231)[:n]
    return fade(x, sr, 0.002, 0.2), sr, False


def s_comic_whoosh():
    """ZUUUM: a bright airy glide (a burn, an orbit, a capture)."""
    x = _whoosh(600, 2400, 0.55, 7240, 900, 1800)
    y = np.zeros(int(0.8 * SR))
    add(y, x, 0)
    add(y, celesta(midi(nm("E7")), SR, 0.5, bright=0.4) * 0.12, int(0.38 * SR))
    return fade(y, SR, 0.002, 0.08), SR, False


def s_comic_splash():
    """SPLASH / POUSO: a round 'bloop' and a little spray."""
    sr = SR
    rng = np.random.default_rng(7250)
    n = int(0.7 * sr)
    t = secs(n, sr)
    f = 160 + 520 * np.exp(-t / 0.03)
    bloop = np.sin(TAU * np.cumsum(f) / sr) * env_ar(n, sr, 0.004, 0.07)
    spray = fft_filter(rng.standard_normal(n), sr, lo=1200, hi=5500) * env_ar(n, sr, 0.01, 0.12)
    spray /= np.max(np.abs(spray)) + 1e-9
    x = bloop * 0.8 + spray * 0.3
    x = with_reverb(x, sr, 0.8, 0.2, 7251)[:n]
    return fade(x, sr, 0.002, 0.1), sr, False


def s_comic_end_good():
    """The comic's last page, a good flight: a kalimba run up and a bright 'ta-da'."""
    sr = SR
    y = np.zeros(int(2.2 * sr))
    for i, nn in enumerate(["G5", "B5", "D6"]):
        add(y, kalimba(midi(nm(nn)), sr, 1.0, decay=0.5) * 0.45, int(i * 0.08 * sr))
    for nn in ["D6", "G6"]:
        add(y, marimba(midi(nm(nn)), sr, 1.2, bright=0.8) * 0.4, int(0.34 * sr))
    for i, nn in enumerate(["G7", "D7", "B6", "G7"]):
        add(y, celesta(midi(nm(nn)), sr, 1.0, bright=0.5) * 0.1, int((0.42 + i * 0.07) * sr))
    rng = np.random.default_rng(7260)
    for nn in ["G4", "B4", "D5"]:
        add(y, pad_note(midi(nm(nn)), sr, 0.8, 0.15, 0.9, rng, cutoff=1700) * 0.05, int(0.34 * sr))
    y = with_reverb(y, sr, 1.5, 0.3, 7261)[: y.size]
    return fade(y, sr, 0.001, 0.35), sr, False


def s_comic_end_meh():
    """A partial flight: a gentle 'hm-hm', not sad."""
    sr = SR
    y = np.zeros(int(1.9 * sr))
    for i, nn in enumerate(["G5", "E5", "A5"]):
        add(y, marimba(midi(nm(nn)), sr, 1.2, bright=0.7) * 0.45, int(i * 0.17 * sr))
    rng = np.random.default_rng(7270)
    for nn in ["C4", "G4", "D5"]:
        add(y, pad_note(midi(nm(nn)), sr, 0.8, 0.2, 0.9, rng, cutoff=1300) * 0.05, int(0.34 * sr))
    y = with_reverb(y, sr, 1.4, 0.3, 7271)[: y.size]
    return fade(y, sr, 0.001, 0.35), sr, False


def s_comic_end_bad():
    """A lost flight: a soft falling 'aww' on the marimba and a low warm pad: there, there."""
    sr = SR
    y = np.zeros(int(2.3 * sr))
    for i, nn in enumerate(["E5", "D5", "B4", "C5"]):
        add(y, marimba(midi(nm(nn)), sr, 1.3, bright=0.55) * 0.45, int(i * 0.22 * sr))
    rng = np.random.default_rng(7280)
    for nn in ["A3", "C4", "E4"]:
        add(y, pad_note(midi(nm(nn)), sr, 1.0, 0.3, 1.1, rng, cutoff=950) * 0.05, int(0.3 * sr))
    y = with_reverb(y, sr, 1.6, 0.3, 7281)[: y.size]
    return fade(y, sr, 0.001, 0.4), sr, False


# ------------------------------------------------------------------------ the photo album
def s_photo_shutter():
    """A little camera: the shutter's click-clack, then the film winding on."""
    sr = SR
    rng = np.random.default_rng(7300)
    y = np.zeros(int(0.55 * sr))
    add(y, modal_hit(sr, 3100, [1, 1.9, 3.3], [0.012, 0.007, 0.004], [1, 0.5, 0.3], noise_ms=3, seed=7301), 0)
    add(y, modal_hit(sr, 2100, [1, 2.2, 3.7], [0.016, 0.008, 0.005], [1, 0.5, 0.25], noise_ms=4, seed=7302) * 0.85,
        int(0.065 * sr))
    m = int(0.2 * sr)
    tt = secs(m, sr)
    whirr = np.sign(np.sin(TAU * 34 * tt)) * 0.5 + 0.5
    buzz = fft_filter(rng.standard_normal(m), sr, lo=900, hi=3500) * whirr * raised(m, sr, 0.02, 0.05, 0.15)
    add(y, buzz / (np.max(np.abs(buzz)) + 1e-9) * 0.18, int(0.16 * sr))
    return fade(y, sr, 0.0008, 0.05), sr, False


def s_photo_develop():
    """A picture comes out of the developer: a soft rising shimmer."""
    sr = SR
    rng = np.random.default_rng(7310)
    y = np.zeros(int(1.2 * sr))
    for i, nn in enumerate(["G5", "B5", "D6", "G6", "B6"]):
        add(y, celesta(midi(nm(nn)), sr, 0.9, bright=0.45) * (0.16 - 0.015 * i), int(i * 0.055 * sr))
    n = int(0.6 * sr)
    air = fft_filter(rng.standard_normal(n), sr, lo=2500, hi=7000) * raised(n, sr, 0.25, 0.3, 0.3)
    add(y, air / (np.max(np.abs(air)) + 1e-9) * 0.05, 0)
    y = with_reverb(y, sr, 1.2, 0.28, 7311)[: y.size]
    return fade(y, sr, 0.004, 0.2), sr, False


def s_photo_flip():
    """Browsing the album: a soft paper flick."""
    sr = SR
    rng = np.random.default_rng(7320)
    n = int(0.12 * sr)
    t = secs(n, sr)
    flick = fft_filter(rng.standard_normal(n), sr, lo=1800, hi=5500) * env_ar(n, sr, 0.002, 0.014)
    flick /= np.max(np.abs(flick)) + 1e-9
    tap = np.sin(TAU * np.cumsum(420 + 300 * np.exp(-t / 0.008)) / sr) * env_ar(n, sr, 0.001, 0.015)
    return fade(flick * 0.55 + tap * 0.5, sr, 0.0008, 0.03), sr, False


def s_photo_pin():
    """'Pendurar no mural': the pin goes into the cork (tk-thup) and a tiny happy ding."""
    sr = SR
    y = np.zeros(int(0.5 * sr))
    add(y, modal_hit(sr, 2600, [1, 2.7], [0.012, 0.005], [1, 0.4], noise_ms=2, seed=7330) * 0.7, 0)
    add(y, modal_hit(sr, 210, [1, 2.3, 3.9], [0.04, 0.02, 0.01], [1, 0.4, 0.15], noise_ms=8, seed=7331,
                     bright_hz=1800), int(0.018 * sr))
    add(y, kalimba(midi(nm("A6")), sr, 0.4, bright=0.5, decay=0.18) * 0.35, int(0.06 * sr))
    return fade(with_reverb(y, sr, 0.7, 0.15, 7332)[: y.size], sr, 0.0008, 0.06), sr, False


# ------------------------------------------------------------------------ the launch watch
def s_warp_up():
    """The speed key: a short rising whoosh and a tick (pitched up per speed by the game)."""
    y = np.zeros(int(0.32 * SR))
    add(y, _whoosh(500, 2600, 0.24, 7400, 800, 1600) * 0.6, 0)
    add(y, kalimba(midi(nm("E6")), SR, 0.25, bright=0.5, decay=0.08) * 0.5, int(0.16 * SR))
    return fade(y, SR, 0.002, 0.05), SR, False


def s_warp_down():
    """Back to 1x: a falling whoosh and a lower tick."""
    y = np.zeros(int(0.34 * SR))
    add(y, _whoosh(2200, 480, 0.26, 7410, 1500, 750) * 0.6, 0)
    add(y, kalimba(midi(nm("A5")), SR, 0.25, bright=0.5, decay=0.08) * 0.5, int(0.17 * SR))
    return fade(y, SR, 0.002, 0.05), SR, False


def s_sim_loop():
    """'Simular até o fim': a gentle busy loop, a small clock ticking over a soft whirr and a
    calm two-note hum, 4 s, seamless."""
    sr = SR_LO
    dur = 4.0
    L = int(dur * sr)
    rng = np.random.default_rng(7420)
    u = np.arange(L) / L
    t = np.arange(L) / sr
    x = np.zeros(L)
    whirr = fft_filter(pink(L, rng), sr, lo=300, hi=1400, circular=True)
    x += whirr * (0.7 + 0.3 * np.sin(TAU * 2 * u)) * 0.05
    for f, g in [(midi(nm("G4")), 0.03), (midi(nm("D5")), 0.02)]:
        k = round(f * dur) / dur
        x += np.sin(TAU * k * t) * (0.6 + 0.4 * np.sin(TAU * u + g * 50)) * g
    for i in range(24):   # tick-tock, 6 a second
        f0 = 2300 if i % 2 == 0 else 1850
        hit = modal_hit(sr, f0, [1, 2.3], [0.01, 0.004], [1, 0.3], noise_ms=1.5, seed=7421 + i, bright_hz=5000)
        add(x, hit * (0.16 if i % 2 == 0 else 0.12), int(i * dur / 24 * sr), circular=True)
    x = with_reverb(x, sr, 0.8, 0.2, 7422, circular=True, damp_hz=4000)
    return x, sr, True


# ------------------------------------------------------------------------ checklists and chips
def s_check_tick():
    """A CML item gets its check: a pencil 'tk' and a tiny bell."""
    sr = SR
    rng = np.random.default_rng(7500)
    n = int(0.3 * sr)
    t = secs(n, sr)
    m = int(0.008 * sr)
    tk = np.zeros(n)
    tk[:m] = rng.standard_normal(m) * np.linspace(1, 0, m) ** 2
    tk = fft_filter(tk, sr, lo=1500, hi=5000)
    body = np.sin(TAU * np.cumsum(1300 - 400 * np.clip(t / 0.02, 0, 1)) / sr) * env_ar(n, sr, 0.001, 0.012)
    x = tk / (np.max(np.abs(tk)) + 1e-9) * 0.5 + body * 0.45
    add(x, kalimba(midi(nm("E7")), sr, 0.26, bright=0.4, decay=0.1) * 0.45, int(0.022 * sr))
    return fade(x, sr, 0.0008, 0.04), sr, False


def s_chip_tick():
    """A crew milestone chip: a glassy little pop-tick."""
    sr = SR
    n = int(0.25 * sr)
    t = secs(n, sr)
    pop = np.sin(TAU * np.cumsum(1700 + 900 * (1 - np.exp(-t / 0.01))) / sr) * env_ar(n, sr, 0.001, 0.018)
    x = pop * 0.45
    add(x, kalimba(midi(nm("B6")), sr, 0.25, bright=0.45, decay=0.09) * 0.55, int(0.008 * sr))
    return fade(x, sr, 0.0008, 0.04), sr, False


SOUNDS = {
    # ui
    "ui/ui_hover": s_ui_hover,
    "ui/ui_click": s_ui_click,
    "ui/ui_back": s_ui_back,
    "ui/ui_open": s_ui_open,
    "ui/ui_close": s_ui_close,
    "ui/ui_toggle_on": s_ui_toggle_on,
    "ui/ui_toggle_off": s_ui_toggle_off,
    "ui/ui_denied": s_ui_denied,
    "ui/cash_up": s_cash_up,
    "ui/cash_down": s_cash_down,
    "ui/news_chime": s_news_chime,
    "ui/menu_select": s_menu_select,
    **{f"ui/menu_hover_{i + 1}": s_menu_hover(i) for i in range(len(MENU_HOVER_NOTES))},
    # music
    "music/music_menu": render_menu_theme,
    "music/music_campus": render_campus_loop,
    "music/stinger_milestone": render_stinger_milestone,
    "music/stinger_finale": render_stinger_finale,
    # ambience
    "ambience/amb_day": render_amb_day,
    "ambience/amb_night": render_amb_night,
    "ambience/amb_space": render_amb_space,
    **{f"ambience/workshop_{i + 1}": s_workshop(i) for i in range(4)},
    # voices
    **{f"voice/{k}": v for k, v in VOICES.items()},
    "voice/voice_snore": s_voice_snore,
    # launch
    "launch/countdown_tick": s_countdown_tick,
    "launch/countdown_go": s_countdown_go,
    "launch/ignition": s_launch_ignition,
    "launch/rumble_loop": s_launch_rumble,
    "launch/sputter": s_launch_sputter,
    "launch/engine_cut": s_launch_engine_cut,
    "launch/fall_whistle": s_launch_fall_whistle,
    "launch/fwoomp": s_launch_fwoomp,
    "launch/debris": s_launch_debris,
    "launch/crowd_cheer": s_crowd_cheer,
    "launch/crowd_aww": s_crowd_aww,
    "launch/confetti_pop": s_confetti_pop,
    "launch/result_success": _result(["F5", "A5", "C6", "F6"], [0.09, 0.09, 0.12, 0.0],
                                     lambda f, sr: kalimba(f, sr, 2.0, decay=0.8), _success_sparkle, 410),
    "launch/result_partial": _result(["G5", "D5+G5", "C5+E5"], [0.16, 0.3, 0.0],
                                     lambda f, sr: marimba(f, sr, 1.6, bright=0.7), _partial_pad, 411),
    "launch/result_fail": _result(["A5", "F5", "D5", "A5"], [0.2, 0.2, 0.55, 0.0],
                                  lambda f, sr: marimba(f, sr, 1.5, bright=0.6), _fail_pad, 412),
    # the conference fair
    "ambience/amb_fair_day": render_amb_fair_day,
    "ambience/amb_fair_night": render_amb_fair_night,
    "music/music_fair": render_music_fair,
    **{f"fair/step_{i + 1}": s_fair_step(i) for i in range(4)},
    "fair/talk_chime": s_fair_talk_chime,
    "fair/fanfare": s_fair_fanfare,
    "fair/applause": s_fair_applause,
    # the flight comic
    "comic/page_turn": s_comic_page,
    "comic/panel_pop": s_comic_pop,
    "comic/word_vroom": s_comic_vroom,
    "comic/word_clac": s_comic_clac,
    "comic/word_boom": s_comic_boom,
    "comic/word_whoosh": s_comic_whoosh,
    "comic/word_splash": s_comic_splash,
    "comic/end_good": s_comic_end_good,
    "comic/end_meh": s_comic_end_meh,
    "comic/end_bad": s_comic_end_bad,
    # the photo album
    "ui/photo_shutter": s_photo_shutter,
    "ui/photo_develop": s_photo_develop,
    "ui/photo_flip": s_photo_flip,
    "ui/photo_pin": s_photo_pin,
    # the launch watch
    "ui/warp_up": s_warp_up,
    "ui/warp_down": s_warp_down,
    "ui/sim_loop": s_sim_loop,
    # checklists and chips
    "ui/check_tick": s_check_tick,
    "ui/chip_tick": s_chip_tick,
}

# loudness targets: peak dBFS per family (the library sets the playback volume on top)
PEAK_DB = {"ui": -3.0, "music": -1.5, "ambience": -3.0, "voice": -3.0, "launch": -1.5, "fair": -3.0,
           "comic": -3.0}
# beds are levelled by RMS instead (dB), so day and night sit at the same loudness
RMS_DB = {"ambience/amb_day": -27.0, "ambience/amb_night": -27.0, "ambience/amb_space": -30.0,
          "music/music_menu": -21.0, "music/music_campus": -20.0, "launch/rumble_loop": -16.0,
          "ambience/amb_fair_day": -27.0, "ambience/amb_fair_night": -27.0, "music/music_fair": -21.0,
          "ui/sim_loop": -28.0}


# ======================================================================== output
def finish(name: str, x: np.ndarray, sr: int, loop: bool) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    # DC: loops lose their mean (a circular, seam-free fix); one-shots get a gentle 20 Hz high-pass
    if loop:
        x = x - x.mean(axis=-1, keepdims=True)
    else:
        x = fft_filter(x, sr, lo=20.0, order=1.0)
    peak = np.max(np.abs(x)) + 1e-12
    fam = name.split("/")[0]
    if name in RMS_DB:
        rms = math.sqrt(float(np.mean(x ** 2))) + 1e-12
        g = db(RMS_DB[name]) / rms
        if peak * g > db(-1.0):
            g = db(-1.0) / peak     # never clip: the peak wins
        x = x * g
    else:
        x = x * (db(PEAK_DB[fam]) / peak)
    if not loop:
        x = fade(x, sr, 0.0005, 0.005)
    return x


def write_wav(path: Path, x: np.ndarray, sr: int, loop: bool, seed: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    chans = 1 if x.ndim == 1 else x.shape[0]
    data = x if x.ndim == 1 else x.T
    dither = (rng.random(data.shape) - rng.random(data.shape)) / 32768.0
    pcm = np.clip(np.round((data + dither) * 32767.0), -32768, 32767).astype("<i2")
    frames = pcm.shape[0]
    with wave.open(str(path), "wb") as w:
        w.setnchannels(chans)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    if loop:
        # RIFF 'smpl' chunk with one forward loop over the whole file
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
            size = f.tell()
            f.seek(4)
            f.write(struct.pack("<I", size - 8))


def stats(x: np.ndarray, sr: int, loop: bool) -> dict:
    mono = x if x.ndim == 1 else x.mean(axis=0)
    peak = float(np.max(np.abs(x)))
    rms = math.sqrt(float(np.mean(mono ** 2)))
    d = {"secs": mono.size / sr, "peak_db": 20 * math.log10(peak + 1e-12),
         "rms_db": 20 * math.log10(rms + 1e-12), "dc": float(np.mean(mono))}
    if loop:
        step = np.abs(np.diff(mono))
        d["seam"] = float(abs(mono[0] - mono[-1]) / (np.percentile(step, 99) + 1e-12))
    return d


# ------------------------------------------------------------------------ PNG preview (PIL)
def plot(path: Path, name: str, x: np.ndarray, sr: int, st: dict) -> None:
    from PIL import Image, ImageDraw
    mono = x if x.ndim == 1 else x.mean(axis=0)
    W, H1, H2 = 900, 180, 240
    img = Image.new("RGB", (W, H1 + H2 + 30), (18, 20, 34))
    dr = ImageDraw.Draw(img)
    # waveform: min / max per column, full scale lines at +/-1
    cols = np.array_split(mono, W)
    mid = H1 // 2 + 20
    dr.line([(0, mid - H1 // 2), (W, mid - H1 // 2)], fill=(90, 40, 40))
    dr.line([(0, mid + H1 // 2), (W, mid + H1 // 2)], fill=(90, 40, 40))
    for i, c in enumerate(cols):
        if c.size == 0:
            continue
        lo, hi = float(c.min()), float(c.max())
        dr.line([(i, mid - hi * H1 / 2), (i, mid - lo * H1 / 2)], fill=(120, 220, 200))
        r = math.sqrt(float(np.mean(c ** 2)))
        dr.point((i, mid - r * H1 / 2), fill=(250, 200, 90))
    # spectrogram (log frequency 40 Hz .. nyquist)
    nfft = 1024 if sr > 30000 else 512
    hop = max(1, (mono.size - nfft) // W) if mono.size > nfft else 1
    win = np.hanning(nfft)
    frames = []
    for i in range(W):
        s = i * hop
        seg = mono[s:s + nfft]
        if seg.size < nfft:
            seg = np.pad(seg, (0, nfft - seg.size))
        frames.append(np.abs(np.fft.rfft(seg * win)))
    S = 20 * np.log10(np.array(frames).T + 1e-9)
    S = np.clip((S - (S.max() - 80)) / 80, 0, 1)
    f = np.fft.rfftfreq(nfft, 1 / sr)
    ylog = np.geomspace(40, sr / 2, H2)
    idx = np.clip(np.searchsorted(f, ylog), 0, f.size - 1)
    spec = S[idx][::-1]
    rgb = np.stack([spec ** 1.5 * 255, spec ** 0.8 * 200, (0.3 + 0.7 * spec) * 160 * (1 - spec) + spec * 90], -1)
    img.paste(Image.fromarray(rgb.astype(np.uint8)), (0, H1 + 30))
    txt = "%s  %.2fs  peak %.1f dB  rms %.1f dB  dc %.4f" % (name, st["secs"], st["peak_db"], st["rms_db"], st["dc"])
    if "seam" in st:
        txt += "  seam %.2f" % st["seam"]
    dr.text((6, 3), txt, fill=(230, 230, 240))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# ======================================================================== the sound library
# name -> (files, volume_db, pitch_min, pitch_max, bus, cooldown, max_voices, chance)
LIB = [
    ("ui_hover", ["ui/ui_hover"], -16.0, 0.94, 1.08, "UI", 0.045, 2, 1.0),
    ("ui_click", ["ui/ui_click"], -8.0, 0.96, 1.05, "UI", 0.04, 3, 1.0),
    ("ui_back", ["ui/ui_back"], -9.0, 0.98, 1.02, "UI", 0.06, 2, 1.0),
    ("ui_open", ["ui/ui_open"], -13.0, 0.95, 1.05, "UI", 0.08, 2, 1.0),
    ("ui_close", ["ui/ui_close"], -14.0, 0.95, 1.05, "UI", 0.08, 2, 1.0),
    ("ui_toggle_on", ["ui/ui_toggle_on"], -10.0, 0.98, 1.02, "UI", 0.04, 2, 1.0),
    ("ui_toggle_off", ["ui/ui_toggle_off"], -11.0, 0.98, 1.02, "UI", 0.04, 2, 1.0),
    ("ui_denied", ["ui/ui_denied"], -10.0, 1.0, 1.0, "UI", 0.15, 1, 1.0),
    ("cash_up", ["ui/cash_up"], -12.0, 0.98, 1.04, "UI", 0.25, 1, 1.0),
    ("cash_down", ["ui/cash_down"], -13.0, 0.98, 1.02, "UI", 0.25, 1, 1.0),
    ("news_chime", ["ui/news_chime"], -11.0, 1.0, 1.0, "UI", 0.6, 1, 1.0),
    ("menu_hover", [f"ui/menu_hover_{i + 1}" for i in range(5)], -15.0, 1.0, 1.0, "UI", 0.05, 2, 1.0),
    ("menu_select", ["ui/menu_select"], -9.0, 1.0, 1.0, "UI", 0.1, 1, 1.0),
    ("music_menu", ["music/music_menu"], -6.0, 1.0, 1.0, "Music", 0.0, 1, 1.0),
    ("music_campus", ["music/music_campus"], -8.0, 1.0, 1.0, "Music", 0.0, 1, 1.0),
    ("stinger_milestone", ["music/stinger_milestone"], -6.0, 1.0, 1.0, "Music", 1.0, 1, 1.0),
    ("stinger_finale", ["music/stinger_finale"], -5.0, 1.0, 1.0, "Music", 1.0, 1, 1.0),
    ("amb_day", ["ambience/amb_day"], -4.0, 1.0, 1.0, "Ambience", 0.0, 1, 1.0),
    ("amb_night", ["ambience/amb_night"], -4.0, 1.0, 1.0, "Ambience", 0.0, 1, 1.0),
    ("amb_space", ["ambience/amb_space"], -4.0, 1.0, 1.0, "Ambience", 0.0, 1, 1.0),
    ("workshop_clank", [f"ambience/workshop_{i + 1}" for i in range(4)], -10.0, 0.9, 1.1, "Ambience", 0.8, 2, 1.0),
    ("voice_happy", [f"voice/voice_happy_{i + 1}" for i in range(4)], -9.0, 0.9, 1.15, "SFX", 0.35, 3, 0.55),
    ("voice_question", ["voice/voice_question_1", "voice/voice_question_2"], -9.0, 0.92, 1.12, "SFX", 0.35, 3, 0.6),
    ("voice_surprised", ["voice/voice_surprised_1", "voice/voice_surprised_2"], -9.0, 0.92, 1.12, "SFX", 0.3, 3, 0.7),
    ("voice_sad", ["voice/voice_sad_1", "voice/voice_sad_2"], -10.0, 0.92, 1.08, "SFX", 0.4, 2, 0.6),
    ("voice_babble", [f"voice/voice_babble_{i + 1}" for i in range(3)], -11.0, 0.9, 1.15, "SFX", 0.4, 3, 0.45),
    ("voice_cheer", ["voice/voice_cheer_1", "voice/voice_cheer_2"], -9.0, 0.9, 1.15, "SFX", 0.25, 3, 0.7),
    ("voice_snore", ["voice/voice_snore"], -16.0, 0.9, 1.1, "SFX", 2.0, 1, 0.15),
    ("countdown_tick", ["launch/countdown_tick"], -12.0, 1.0, 1.0, "SFX", 0.0, 2, 1.0),
    ("countdown_go", ["launch/countdown_go"], -9.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("launch_ignition", ["launch/ignition"], -4.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("launch_rumble", ["launch/rumble_loop"], -6.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("launch_sputter", ["launch/sputter"], -6.0, 0.9, 1.1, "SFX", 0.0, 2, 1.0),
    ("launch_engine_cut", ["launch/engine_cut"], -6.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("launch_fall_whistle", ["launch/fall_whistle"], -14.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("launch_fwoomp", ["launch/fwoomp"], -4.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("launch_debris", ["launch/debris"], -9.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("crowd_cheer", ["launch/crowd_cheer"], -8.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("crowd_aww", ["launch/crowd_aww"], -9.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("confetti_pop", ["launch/confetti_pop"], -10.0, 0.96, 1.06, "SFX", 0.0, 3, 1.0),
    ("result_success", ["launch/result_success"], -7.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("result_partial", ["launch/result_partial"], -8.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    ("result_fail", ["launch/result_fail"], -8.0, 1.0, 1.0, "SFX", 0.0, 1, 1.0),
    # the conference fair
    ("amb_fair_day", ["ambience/amb_fair_day"], -5.0, 1.0, 1.0, "Ambience", 0.0, 1, 1.0),
    ("amb_fair_night", ["ambience/amb_fair_night"], -5.0, 1.0, 1.0, "Ambience", 0.0, 1, 1.0),
    ("music_fair", ["music/music_fair"], -9.0, 1.0, 1.0, "Music", 0.0, 1, 1.0),
    ("fair_step", [f"fair/step_{i + 1}" for i in range(4)], -19.0, 0.9, 1.1, "SFX", 0.08, 2, 1.0),
    ("fair_talk_chime", ["fair/talk_chime"], -15.0, 0.98, 1.03, "UI", 0.35, 1, 1.0),
    ("fair_fanfare", ["fair/fanfare"], -7.0, 1.0, 1.0, "Music", 1.0, 1, 1.0),
    ("fair_applause", ["fair/applause"], -10.0, 0.97, 1.03, "SFX", 1.0, 1, 1.0),
    # the flight comic
    ("comic_page", ["comic/page_turn"], -12.0, 0.95, 1.06, "UI", 0.12, 1, 1.0),
    ("comic_pop", ["comic/panel_pop"], -15.0, 0.94, 1.08, "UI", 0.05, 2, 1.0),
    ("comic_vroom", ["comic/word_vroom"], -13.0, 0.95, 1.05, "UI", 0.1, 1, 1.0),
    ("comic_clac", ["comic/word_clac"], -12.0, 0.95, 1.06, "UI", 0.1, 1, 1.0),
    ("comic_boom", ["comic/word_boom"], -12.0, 0.96, 1.04, "UI", 0.1, 1, 1.0),
    ("comic_whoosh", ["comic/word_whoosh"], -14.0, 0.96, 1.05, "UI", 0.1, 1, 1.0),
    ("comic_splash", ["comic/word_splash"], -13.0, 0.95, 1.05, "UI", 0.1, 1, 1.0),
    ("comic_end_good", ["comic/end_good"], -8.0, 1.0, 1.0, "Music", 0.5, 1, 1.0),
    ("comic_end_meh", ["comic/end_meh"], -8.0, 1.0, 1.0, "Music", 0.5, 1, 1.0),
    ("comic_end_bad", ["comic/end_bad"], -8.0, 1.0, 1.0, "Music", 0.5, 1, 1.0),
    # the photo album
    ("photo_shutter", ["ui/photo_shutter"], -9.0, 0.97, 1.04, "UI", 1.2, 1, 1.0),
    ("photo_develop", ["ui/photo_develop"], -15.0, 0.98, 1.03, "UI", 0.6, 1, 1.0),
    ("photo_flip", ["ui/photo_flip"], -13.0, 0.92, 1.1, "UI", 0.04, 2, 1.0),
    ("photo_pin", ["ui/photo_pin"], -10.0, 0.97, 1.03, "UI", 0.15, 1, 1.0),
    # the launch watch
    ("warp_up", ["ui/warp_up"], -14.0, 1.0, 1.0, "UI", 0.05, 2, 1.0),
    ("warp_down", ["ui/warp_down"], -14.0, 1.0, 1.0, "UI", 0.05, 1, 1.0),
    ("sim_loop", ["ui/sim_loop"], -12.0, 1.0, 1.0, "UI", 0.0, 1, 1.0),
    # checklists and chips
    ("check_tick", ["ui/check_tick"], -11.0, 0.98, 1.03, "UI", 0.05, 3, 1.0),
    ("chip_tick", ["ui/chip_tick"], -13.0, 1.0, 1.0, "UI", 0.03, 4, 1.0),
]


def write_library(path: Path) -> None:
    ext = []
    ids = {}
    for entry in LIB:
        for f in entry[1]:
            if f not in ids:
                ids[f] = "%d_%s" % (len(ids) + 2, f.split("/")[-1])
                ext.append(f)
    lines = []
    total = len(ext) + 2
    lines.append('[gd_resource type="Resource" script_class="CwSoundLibrary" load_steps=%d format=3]' % (total + len(LIB)))
    lines.append("")
    lines.append('[ext_resource type="Script" path="res://src/audio/cw_sound_library.gd" id="1_lib"]')
    lines.append('[ext_resource type="Script" path="res://src/audio/cw_sound.gd" id="1_snd"]')
    for f in ext:
        lines.append('[ext_resource type="AudioStream" path="res://assets/audio/%s.wav" id="%s"]' % (f, ids[f]))
    lines.append("")
    subs = []
    for i, (name, files, vol, pmin, pmax, bus, cd, mv, chance) in enumerate(LIB):
        sid = "snd_%s" % name
        subs.append(sid)
        lines.append('[sub_resource type="Resource" id="%s"]' % sid)
        lines.append('script = ExtResource("1_snd")')
        lines.append('name = &"%s"' % name)
        lines.append("streams = Array[AudioStream]([%s])" % ", ".join('ExtResource("%s")' % ids[f] for f in files))
        lines.append("volume_db = %s" % repr(float(vol)))
        lines.append("pitch_min = %s" % repr(float(pmin)))
        lines.append("pitch_max = %s" % repr(float(pmax)))
        lines.append('bus = &"%s"' % bus)
        lines.append("cooldown = %s" % repr(float(cd)))
        lines.append("max_voices = %d" % mv)
        lines.append("chance = %s" % repr(float(chance)))
        lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_lib")')
    lines.append("sounds = Array[ExtResource(\"1_snd\")]([%s])" % ", ".join('SubResource("%s")' % s for s in subs))
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


# ======================================================================== main
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma separated sound names (file stems or folder/stem)")
    ap.add_argument("--plots", default="", help="folder for waveform + spectrogram PNGs")
    ap.add_argument("--library", action="store_true", help="(re)write assets/audio/cw_sound_library.tres")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        for k in SOUNDS:
            print(k)
        return 0
    only = [s.strip() for s in args.only.split(",") if s.strip()]
    total = 0
    for i, (name, maker) in enumerate(SOUNDS.items()):
        if only and name not in only and name.split("/")[-1] not in only:
            continue
        x, sr, loop = maker()
        x = finish(name, x, sr, loop)
        st = stats(x, sr, loop)
        path = OUT / (name + ".wav")
        write_wav(path, x, sr, loop, seed=9000 + i)
        size = path.stat().st_size
        total += size
        extra = ("  seam %.2f" % st["seam"]) if loop else ""
        print("%-28s %6.2f s %s %5d Hz  peak %6.1f dB  rms %6.1f dB  %7.1f KB%s" % (
            name, st["secs"], "st" if x.ndim == 2 else "mo", sr, st["peak_db"], st["rms_db"], size / 1024, extra))
        if args.plots:
            plot(Path(args.plots) / (name.replace("/", "__") + ".png"), name, x, sr, st)
    print("total %.2f MB" % (total / 1048576))
    if args.library or not LIBRARY.exists():
        write_library(LIBRARY)
        print("wrote", LIBRARY.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
