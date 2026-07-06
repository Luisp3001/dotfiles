#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VoiceManager — STT (Whisper + Vosk) y TTS (Kokoro) para Minerva.

Expone el singleton `voice_mgr` que utilizan los engines de chat.
"""
import json
import os
import queue
import sys
import tempfile
import threading
import time

from .config import VOICE_AVAILABLE, VOSK_AVAILABLE, VOICE_DIR
from .io import emit

if VOICE_AVAILABLE:
    import numpy as np
    import sounddevice as sd
    import soundfile as sf
    from pywhispercpp.model import Model

if VOSK_AVAILABLE:
    from vosk import Model as VoskModel, KaldiRecognizer


class VoiceManager:
    def __init__(self):
        self.is_recording  = False
        self.audio_data    = []
        self.samplerate    = 16000
        self.stream        = None
        self.whisper_model = None

        self.piper_voice = None

        self.tts_queue     = queue.Queue()
        self.play_queue    = queue.Queue()
        self.tts_thread    = None
        self.play_thread   = None
        self.tts_stop_event = threading.Event()

        if VOICE_AVAILABLE:
            os.makedirs(VOICE_DIR, exist_ok=True)
            self.tts_thread  = threading.Thread(target=self._tts_worker,  daemon=True)
            self.play_thread = threading.Thread(target=self._play_worker, daemon=True)
            self.tts_thread.start()
            self.play_thread.start()

            # Vosk para wake word
            self.vosk_model      = None
            self.vosk_recognizer = None
            if VOSK_AVAILABLE:
                try:
                    vosk_path = os.path.join(VOICE_DIR, "vosk-model-es")
                    if os.path.exists(vosk_path):
                        self.vosk_model      = VoskModel(vosk_path)
                        self.vosk_recognizer = KaldiRecognizer(self.vosk_model, 16000)
                        self.wake_word_thread = threading.Thread(
                            target=self._wake_word_worker, daemon=True
                        )
                        self.wake_word_thread.start()
                except Exception as e:
                    print(f"Error cargando vosk: {e}", file=sys.stderr)

    # ── TTS (Piper) ──────────────────────────────────────────────────────────

    def _ensure_piper_model(self):
        if self.piper_voice is not None:
            return
        try:
            print("Cargando modelo Piper TTS...", file=sys.stderr)
            from piper import PiperVoice
            model_path = os.path.join(VOICE_DIR, "es_MX-claude-high.onnx")
            if not os.path.exists(model_path):
                print(f"Modelo no encontrado: {model_path}", file=sys.stderr)
                return
            self.piper_voice = PiperVoice.load(model_path)
            print("Modelo Piper TTS cargado exitosamente.", file=sys.stderr)
        except Exception as e:
            print(f"Error cargando Piper TTS: {e}", file=sys.stderr)

    def _tts_worker(self):
        self._ensure_piper_model()
        if not self.piper_voice:
            print("Piper TTS no pudo ser inicializado", file=sys.stderr)
            return

        while True:
            text = self.tts_queue.get()
            if text is None:
                break
            if self.tts_stop_event.is_set():
                self.tts_queue.task_done()
                continue

            try:
                if not self.tts_stop_event.is_set():
                    for chunk in self.piper_voice.synthesize(text):
                        if self.tts_stop_event.is_set():
                            break
                        audio_np = np.frombuffer(chunk.audio_int16_bytes, dtype=np.int16)
                        self.play_queue.put((audio_np, chunk.sample_rate))
            except Exception as e:
                import traceback
                print(f"ERROR EN TTS WORKER (Piper): {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)
            self.tts_queue.task_done()

    def _play_worker(self):
        is_speaking = False
        while True:
            item = self.play_queue.get()
            if item is None:
                if is_speaking:
                    emit({"type": "voice_speaking_stopped"})
                    is_speaking = False
                break
                
            if not is_speaking:
                emit({"type": "voice_speaking_started"})
                is_speaking = True
                
            audio, sample_rate = item
            if not self.tts_stop_event.is_set():
                sd.play(audio, sample_rate)
                sd.wait()
                
            self.play_queue.task_done()
            
            if self.play_queue.empty() and is_speaking:
                emit({"type": "voice_speaking_stopped"})
                is_speaking = False

    def stop_tts(self):
        if not VOICE_AVAILABLE:
            return
        self.tts_stop_event.set()
        sd.stop()
        while not self.tts_queue.empty():
            try:
                self.tts_queue.get_nowait()
            except Exception:
                pass
        while not self.play_queue.empty():
            try:
                self.play_queue.get_nowait()
            except Exception:
                pass

    # ── Wake word (Vosk) ──────────────────────────────────────────────────────

    def _wake_word_worker(self):
        if not self.vosk_model:
            return
        try:
            with sd.RawInputStream(
                samplerate=16000, blocksize=8000, dtype='int16',
                channels=1, callback=self.audio_callback
            ):
                while True:
                    time.sleep(1)
        except Exception as e:
            print(f"Error en wake word stream: {e}", file=sys.stderr)

    def audio_callback(self, indata, frames, time_info, status):
        if self.is_recording:
            audio_np = np.frombuffer(indata, dtype=np.int16).astype(np.float32) / 32768.0
            self.audio_data.append(audio_np.copy())

            if self.vosk_recognizer:
                is_final = self.vosk_recognizer.AcceptWaveform(bytes(indata))
                if is_final:
                    res  = json.loads(self.vosk_recognizer.Result())
                    text = res.get("text", "")
                    if text.strip():
                        emit({"type": "silence_detected"})
        elif self.vosk_recognizer:
            is_final = self.vosk_recognizer.AcceptWaveform(bytes(indata))
            if is_final:
                res  = json.loads(self.vosk_recognizer.Result())
                text = res.get("text", "")
            else:
                res  = json.loads(self.vosk_recognizer.PartialResult())
                text = res.get("partial", "")

            if "minerva" in text.lower():
                if not self.is_recording:
                    self.vosk_recognizer.Reset()
                    emit({"type": "wake_word_detected"})

    # ── Grabación / Transcripción ─────────────────────────────────────────────

    def toggle_recording(self):
        if not VOICE_AVAILABLE:
            return None

        if not self.is_recording:
            self.stop_tts()
            self.tts_stop_event.clear()
            self.is_recording = True
            self.audio_data   = []
            if not getattr(self, "wake_word_thread", None) or not self.wake_word_thread.is_alive():
                self.stream = sd.RawInputStream(
                    samplerate=16000, blocksize=8000, dtype='int16',
                    channels=1, callback=self.audio_callback
                )
                self.stream.start()
            return "started"
        else:
            self.is_recording = False
            if self.stream:
                self.stream.stop()
                self.stream.close()
                self.stream = None

            if not self.audio_data:
                return "empty"

            audio_np = np.concatenate(self.audio_data, axis=0)

            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                sf.write(tmp.name, audio_np, self.samplerate)
                tmp_name = tmp.name

            if not self.whisper_model:
                try:
                    self.whisper_model = Model(
                        "small", language="es",
                        print_realtime=False, print_progress=False
                    )
                except Exception:
                    os.remove(tmp_name)
                    return "error"

            try:
                segments = self.whisper_model.transcribe(tmp_name)
                text = " ".join([s.text for s in segments]).strip()
            except Exception:
                text = "error"
            finally:
                os.remove(tmp_name)

            return text


# ─────────────────────────────────────────────────────────────────────────────
# Singleton
# ─────────────────────────────────────────────────────────────────────────────
voice_mgr = VoiceManager()
