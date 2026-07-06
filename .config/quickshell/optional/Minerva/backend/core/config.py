#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Configuración global del backend Minerva.
Todas las constantes y flags de disponibilidad de dependencias opcionales.
"""
import os
import pathlib
import sys

# ─────────────────────────────────────────────────────────────────────────────
# Configuración base
# ─────────────────────────────────────────────────────────────────────────────
MODEL    = "gemma4:e4b"
HOME     = str(pathlib.Path.home())
MAX_FILE = 8_192   # 8 KiB máx por lectura de archivo
MAX_DIR  = 4_096   # 4 KiB máx por listado de directorio

# ─────────────────────────────────────────────────────────────────────────────
# Spotify
# ─────────────────────────────────────────────────────────────────────────────
SPOTIFY_CONFIG_DIR = os.path.join(HOME, ".config", "spotify_minerva")
SPOTIFY_CREDS_FILE = os.path.join(SPOTIFY_CONFIG_DIR, "credentials.json")
SPOTIFY_TOKEN_FILE = os.path.join(SPOTIFY_CONFIG_DIR, "token_cache.json")
SPOTIFY_API_BASE   = "https://api.spotify.com/v1"
SPOTIFY_AUTH_URL   = "https://accounts.spotify.com/authorize"
SPOTIFY_TOKEN_URL  = "https://accounts.spotify.com/api/token"
SPOTIFY_SCOPES     = (
    "user-read-playback-state user-modify-playback-state "
    "user-read-currently-playing streaming app-remote-control "
    "user-read-private playlist-modify-public"
)

# ─────────────────────────────────────────────────────────────────────────────
# Voz (STT / TTS)
# ─────────────────────────────────────────────────────────────────────────────
VOICE_DIR = os.path.join(HOME, ".config", "quickshell", "optional", "Minerva", "voice")
REF_WAV   = os.path.join(VOICE_DIR, "referencia.wav")
REF_TXT   = os.path.join(VOICE_DIR, "referencia.txt")

# ─────────────────────────────────────────────────────────────────────────────
# Disponibilidad de dependencias opcionales
# ─────────────────────────────────────────────────────────────────────────────
try:
    from ddgs import DDGS  # noqa: F401
    WEB_SEARCH_AVAILABLE = True
except ImportError:
    WEB_SEARCH_AVAILABLE = False

try:
    import sounddevice as _sd   # noqa: F401
    import soundfile as _sf     # noqa: F401
    from pywhispercpp.model import Model as _WhisperModel  # noqa: F401
    VOICE_AVAILABLE = True
except ImportError:
    VOICE_AVAILABLE = False

try:
    from vosk import Model as _VoskModel, KaldiRecognizer as _KaldiRecognizer  # noqa: F401
    VOSK_AVAILABLE = True
except ImportError:
    VOSK_AVAILABLE = False
