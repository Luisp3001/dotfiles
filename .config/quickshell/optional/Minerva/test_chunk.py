from piper import PiperVoice
import sounddevice as sd
import numpy as np
voice = PiperVoice.load('/home/luisp/.config/quickshell/optional/Minerva/voice/es_MX-claude-high.onnx')
for chunk in voice.synthesize('Hola, esta es una prueba de voz de minerva.'):
    audio_np = np.frombuffer(chunk.audio_int16_bytes, dtype=np.int16)
    print("Playing chunk of size", len(audio_np))
    sd.play(audio_np, chunk.sample_rate)
    sd.wait()
