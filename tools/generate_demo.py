"""Generate two original synthetic demo tracks, without external media assets."""
from pathlib import Path
import math
import struct
import wave

destination = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
destination.mkdir(parents=True, exist_ok=True)
rate = 22050
seconds = 32
for name, notes in [('dawn', [261.63, 329.63, 392.00, 523.25, 440.00, 392.00, 329.63, 293.66]),
                    ('tide', [220.00, 261.63, 329.63, 392.00, 349.23, 329.63, 261.63, 246.94])]:
    samples = bytearray()
    for index in range(rate * seconds):
        t = index / rate
        beat = t % .5
        note = notes[int(t / .5) % len(notes)]
        envelope = min(1, beat / .02) * math.exp(-beat * 6)
        melody = (math.sin(math.tau * note * t) + .22 * math.sin(math.tau * note * 2 * t)) * envelope
        bass = math.sin(math.tau * notes[int(t / 4) % 4] / 2 * t) * .18
        fade = min(1, t / 2, (seconds - t) / 2)
        value = int((melody * .21 + bass) * fade * 32767)
        samples.extend(struct.pack('<h', value))
    with wave.open(str(destination / f'{name}.wav'), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(samples)
print('Generated two 32-second original demo tracks.')
