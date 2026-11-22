# Генерация звуков уведомлений QWE Trader (WAV 22050 Гц, 16 бит, моно)
# python tools/make_sounds.py <папка вывода>
import math, struct, sys, wave, os

RATE = 22050


def note(freq, dur, start, vol=1.0, decay=5.0, attack=0.006, partials=((1, 1.0), (2, 0.25), (3, 0.08))):
    return (freq, dur, start, vol, decay, attack, partials)


def render(notes, total, gain=0.42, sweep=None):
    n = int(RATE * total)
    buf = [0.0] * n
    for freq, dur, start, vol, decay, attack, partials in notes:
        s0 = int(RATE * start)
        for i in range(int(RATE * dur)):
            j = s0 + i
            if j >= n:
                break
            t = i / RATE
            env = min(1.0, t / attack) * math.exp(-decay * t)
            f = freq
            if sweep:
                f = freq * (1 + sweep * math.exp(-t * 30))
            v = 0.0
            for k, a in partials:
                v += a * math.sin(2 * math.pi * f * k * t)
            buf[j] += vol * env * v
    peak = max(1e-9, max(abs(x) for x in buf))
    # плавное затухание в конце, чтобы не было щелчка
    fade = int(RATE * 0.03)
    for i in range(fade):
        buf[n - 1 - i] *= i / fade
    return [x / peak * gain for x in buf]


def save(path, samples):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x)) * 32767)) for x in samples))


SOUNDS = {
    # два чистых звона, как стеклянный колокольчик
    'chime': render([note(1318.5, 0.9, 0.0, 1.0, 5.5), note(1975.5, 1.0, 0.11, 0.8, 5.0)], 1.1),
    # мягкий аккорд (ми мажор), без резкой атаки
    'soft': render([note(659.3, 0.8, 0.0, 1.0, 4.5, 0.02, ((1, 1.0), (2, 0.12))),
                    note(830.6, 0.8, 0.03, 0.7, 4.5, 0.02, ((1, 1.0), (2, 0.12))),
                    note(987.8, 0.8, 0.06, 0.6, 4.5, 0.02, ((1, 1.0), (2, 0.1)))], 0.85, 0.38),
    # короткая «капля»
    'drop': render([note(880.0, 0.35, 0.0, 1.0, 11.0, 0.002, ((1, 1.0), (2, 0.05)))], 0.38, 0.45, sweep=0.6),
    # таймер: восходящее арпеджио, заметнее остальных
    'timer': render([note(1046.5, 0.6, 0.0, 1.0, 5.0), note(1318.5, 0.6, 0.15, 0.9, 5.0),
                     note(1568.0, 0.6, 0.30, 0.9, 5.0), note(2093.0, 0.9, 0.45, 0.8, 4.0)], 1.35, 0.5),
}

if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, s in SOUNDS.items():
        save(os.path.join(out, name + '.wav'), s)
        print(name, os.path.getsize(os.path.join(out, name + '.wav')))
