#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ollama AI Backend — Quickshell Dynamic Island Plugin
Protocolo: JSON Lines por stdin/stdout

Entrada (stdin, vía HTTP POST port 11435):
  {"type":"chat",         "message":"...", "history":[...]}
  {"type":"run_confirmed","command":"..."}
  {"type":"run_sudo",     "command":"..."}
  {"type":"ping"}

Salida (stdout, una línea JSON por evento):
  {"type":"ready",          "model":"...", "home":"..."}
  {"type":"token",          "content":"..."}
  {"type":"done",           "full_response":"..."}
  {"type":"tool_start",     "tool":"..."}
  {"type":"tool_result",    "tool":"...", "result":"..."}
  {"type":"run_command",    "command":"..."}
  {"type":"confirm_required","command":"...", "reason":"..."}
  {"type":"sudo_required",  "command":"..."}
  {"type":"command_result", "command":"...", "output":"...", "returncode":0, "success":true}
  {"type":"error",          "message":"..."}
"""

import os
import sys

# Compatibilidad para GPUs AMD RX 6000 (RDNA 2) en PyTorch ROCm
if "HSA_OVERRIDE_GFX_VERSION" not in os.environ:
    os.environ["HSA_OVERRIDE_GFX_VERSION"] = "10.3.0"

import json
import os
import re
import subprocess
import pathlib
import queue
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import ollama
import chromadb
try:
    from ddgs import DDGS
    WEB_SEARCH_AVAILABLE = True
except ImportError:
    WEB_SEARCH_AVAILABLE = False

import numpy as np
import urllib.request
import urllib.parse
import tempfile
import time
import webbrowser
import hashlib
import base64
import secrets
try:
    import sounddevice as sd
    import soundfile as sf
    from pywhispercpp.model import Model
    from piper import PiperVoice
    VOICE_AVAILABLE = True
except ImportError:
    VOICE_AVAILABLE = False

# ─────────────────────────────────────────────────────────────────────────────
# Configuración
# ─────────────────────────────────────────────────────────────────────────────
MODEL       = "gemma4:e4b"
HOME        = str(pathlib.Path.home())
MAX_FILE    = 8_192   # 8 KiB máx por lectura de archivo
MAX_DIR     = 4_096   # 4 KiB máx por listado de directorio

# Spotify
SPOTIFY_CONFIG_DIR  = os.path.join(HOME, ".config", "spotify_minerva")
SPOTIFY_CREDS_FILE  = os.path.join(SPOTIFY_CONFIG_DIR, "credentials.json")
SPOTIFY_TOKEN_FILE  = os.path.join(SPOTIFY_CONFIG_DIR, "token_cache.json")
SPOTIFY_API_BASE    = "https://api.spotify.com/v1"
SPOTIFY_AUTH_URL    = "https://accounts.spotify.com/authorize"
SPOTIFY_TOKEN_URL   = "https://accounts.spotify.com/api/token"
SPOTIFY_SCOPES      = "user-read-playback-state user-modify-playback-state user-read-currently-playing streaming app-remote-control user-read-private playlist-modify-public"

# ─────────────────────────────────────────────────────────────────────────────
# VOZ: STT y TTS
# ─────────────────────────────────────────────────────────────────────────────
VOICE_DIR = os.path.join(HOME, ".config", "quickshell", "optional", "ollama_ai", "voice")
REF_WAV = os.path.join(VOICE_DIR, "referencia.wav")
REF_TXT = os.path.join(VOICE_DIR, "referencia.txt")

class VoiceManager:
    def __init__(self):
        self.is_recording = False
        self.audio_data = []
        self.samplerate = 16000
        self.stream = None
        self.whisper_model = None
        
        self.kokoro_pipeline = None

        self.tts_queue = queue.Queue()
        self.play_queue = queue.Queue()
        self.tts_thread = None
        self.play_thread = None
        self.tts_stop_event = threading.Event()
        
        if VOICE_AVAILABLE:
            os.makedirs(VOICE_DIR, exist_ok=True)
            self.tts_thread = threading.Thread(target=self._tts_worker, daemon=True)
            self.play_thread = threading.Thread(target=self._play_worker, daemon=True)
            self.tts_thread.start()
            self.play_thread.start()
            
    def _ensure_kokoro_model(self):
        if self.kokoro_pipeline is not None:
            return
        try:
            print("Cargando modelo Kokoro TTS...", file=sys.stderr)
            import os
            os.environ["HSA_OVERRIDE_GFX_VERSION"] = "10.3.0"
            from kokoro import KPipeline
            self.kokoro_pipeline = KPipeline(lang_code='e')
            print("Modelo Kokoro TTS cargado exitosamente.", file=sys.stderr)
        except Exception as e:
            print(f"Error cargando Kokoro TTS: {e}", file=sys.stderr)
        
    def _tts_worker(self):
        self._ensure_kokoro_model()
        if not self.kokoro_pipeline:
            print("Kokoro TTS no pudo ser inicializado", file=sys.stderr)
            return
            
        while True:
            text = self.tts_queue.get()
            if text is None: break
            if self.tts_stop_event.is_set():
                self.tts_queue.task_done()
                continue
                
            try:
                if not self.tts_stop_event.is_set():
                    generator = self.kokoro_pipeline(text, voice='ef_dora' , speed=1.0)
                    for i, (gs, ps, audio) in enumerate(generator):
                        if self.tts_stop_event.is_set():
                            break
                        self.play_queue.put((audio, 24000))
                        
            except Exception as e:
                import traceback
                print(f"ERROR EN TTS WORKER (Kokoro): {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)
            self.tts_queue.task_done()

    def _play_worker(self):
        while True:
            item = self.play_queue.get()
            if item is None: break
            audio, sample_rate = item
            if not self.tts_stop_event.is_set():
                sd.play(audio, sample_rate)
                sd.wait()
            self.play_queue.task_done()
            
    def stop_tts(self):
        if not VOICE_AVAILABLE: return
        self.tts_stop_event.set()
        sd.stop()
        # Vaciar colas
        while not self.tts_queue.empty():
            try: self.tts_queue.get_nowait()
            except: pass
        while not self.play_queue.empty():
            try: self.play_queue.get_nowait()
            except: pass
            
    def audio_callback(self, indata, frames, time, status):
        self.audio_data.append(indata.copy())

    def toggle_recording(self):
        if not VOICE_AVAILABLE:
            return None
            
        if not self.is_recording:
            self.stop_tts()
            self.tts_stop_event.clear()
            self.is_recording = True
            self.audio_data = []
            self.stream = sd.InputStream(samplerate=self.samplerate, channels=1, callback=self.audio_callback)
            self.stream.start()
            return "started"
        else:
            self.is_recording = False
            if self.stream:
                self.stream.stop()
                self.stream.close()
            
            if not self.audio_data:
                return "empty"
                
            audio_np = np.concatenate(self.audio_data, axis=0)
            
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                sf.write(tmp.name, audio_np, self.samplerate)
                tmp_name = tmp.name
                
            if not self.whisper_model:
                try:
                    self.whisper_model = Model("base", print_realtime=False, print_progress=False)
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

voice_mgr = VoiceManager()

# ─────────────────────────────────────────────────────────────────────────────
# Spotify Manager — OAuth 2.0 PKCE + API
# ─────────────────────────────────────────────────────────────────────────────
class SpotifyManager:
    """Gestiona la autenticación OAuth 2.0 PKCE y las llamadas a la API de Spotify."""

    def __init__(self):
        self.access_token = None
        self.refresh_token = None
        self.token_expiry = 0
        self.client_id = None
        self.client_secret = None
        self.redirect_uri = "http://localhost:8888/callback"
        self._auth_server = None
        self._auth_code = None
        self._load_credentials()
        self._load_cached_token()

    def _load_credentials(self):
        """Carga client_id y client_secret desde el archivo de configuración."""
        if not os.path.exists(SPOTIFY_CREDS_FILE):
            os.makedirs(os.path.dirname(SPOTIFY_CREDS_FILE), exist_ok=True)
            try:
                with open(SPOTIFY_CREDS_FILE, "w") as f:
                    json.dump({
                        "client_id": "TU_CLIENT_ID_AQUI",
                        "client_secret": "TU_CLIENT_SECRET_AQUI",
                        "redirect_uri": "http://localhost:8888/callback"
                    }, f, indent=4)
            except Exception as e:
                print(f"Error creando archivo de credenciales de Spotify: {e}", file=sys.stderr)
            return
        try:
            with open(SPOTIFY_CREDS_FILE, "r") as f:
                creds = json.load(f)
            self.client_id = creds.get("client_id", "").strip()
            self.client_secret = creds.get("client_secret", "").strip()
            self.redirect_uri = creds.get("redirect_uri", self.redirect_uri).strip()
            # Validar que no sean placeholders
            if self.client_id in ("", "TU_CLIENT_ID_AQUI"):
                self.client_id = None
            if self.client_secret in ("", "TU_CLIENT_SECRET_AQUI"):
                self.client_secret = None
        except Exception:
            pass

    def _load_cached_token(self):
        """Carga tokens desde cache en disco."""
        if not os.path.exists(SPOTIFY_TOKEN_FILE):
            return
        try:
            with open(SPOTIFY_TOKEN_FILE, "r") as f:
                data = json.load(f)
            self.access_token = data.get("access_token")
            self.refresh_token = data.get("refresh_token")
            self.token_expiry = data.get("token_expiry", 0)
        except Exception:
            pass

    def _save_token_cache(self):
        """Persiste tokens en disco."""
        os.makedirs(SPOTIFY_CONFIG_DIR, exist_ok=True)
        try:
            with open(SPOTIFY_TOKEN_FILE, "w") as f:
                json.dump({
                    "access_token": self.access_token,
                    "refresh_token": self.refresh_token,
                    "token_expiry": self.token_expiry
                }, f)
        except Exception:
            pass

    def is_configured(self) -> bool:
        """Verifica si las credenciales de Spotify están configuradas."""
        return bool(self.client_id and self.client_secret)

    def is_authenticated(self) -> bool:
        """Verifica si hay un token válido (o refrescable)."""
        return bool(self.access_token or self.refresh_token)

    def _token_expired(self) -> bool:
        return time.time() >= self.token_expiry

    def _refresh_access_token(self) -> bool:
        """Refresca el access token usando el refresh token."""
        if not self.refresh_token or not self.client_id:
            return False
        try:
            data = urllib.parse.urlencode({
                "grant_type": "refresh_token",
                "refresh_token": self.refresh_token,
                "client_id": self.client_id,
                "client_secret": self.client_secret
            }).encode()
            req = urllib.request.Request(SPOTIFY_TOKEN_URL, data=data, method="POST")
            req.add_header("Content-Type", "application/x-www-form-urlencoded")
            with urllib.request.urlopen(req, timeout=10) as resp:
                token_data = json.loads(resp.read().decode())
            self.access_token = token_data["access_token"]
            self.token_expiry = time.time() + token_data.get("expires_in", 3600) - 60
            if "refresh_token" in token_data:
                self.refresh_token = token_data["refresh_token"]
            self._save_token_cache()
            return True
        except Exception:
            return False

    def _get_valid_token(self) -> str:
        """Obtiene un token válido, refrescando si es necesario."""
        if self._token_expired() and self.refresh_token:
            self._refresh_access_token()
        return self.access_token

    def _api_request(self, method: str, endpoint: str, body: dict = None, params: dict = None, timeout: int = 10) -> dict:
        """Hace una petición autenticada a la API de Spotify."""
        token = self._get_valid_token()
        if not token:
            return {"error": "No hay token de Spotify. Necesitas autenticarte primero."}

        url = f"{SPOTIFY_API_BASE}{endpoint}"
        if params:
            url += "?" + urllib.parse.urlencode(params)

        body_bytes = json.dumps(body).encode() if body else None
        req = urllib.request.Request(url, data=body_bytes, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        if body:
            req.add_header("Content-Type", "application/json")

        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                # Cualquier 2xx sin cuerpo (incluyendo 200, 202, 204) es éxito
                raw = resp.read()
                if not raw:
                    return {"success": True}
                try:
                    return json.loads(raw.decode())
                except (json.JSONDecodeError, UnicodeDecodeError):
                    # Respuesta 2xx con cuerpo no-JSON: igualmente un éxito
                    return {"success": True}
        except urllib.error.HTTPError as e:
            error_body = e.read().decode() if e.fp else ""
            # Si es 401, intentar refresh y reintentar una vez
            if e.code == 401 and self._refresh_access_token():
                return self._api_request(method, endpoint, body, params, timeout)
            return {"error": f"Error HTTP {e.code}: {error_body[:500]}"}
        except Exception as e:
            return {"error": f"Error de conexión: {e}"}

    def authenticate(self) -> str:
        """Inicia el flujo OAuth 2.0 Authorization Code. Abre el navegador y espera el callback."""
        if not self.is_configured():
            return ("Spotify no está configurado. Edita el archivo "
                    f"{SPOTIFY_CREDS_FILE} con tu client_id y client_secret "
                    "de https://developer.spotify.com/dashboard")

        # Generar code_verifier y code_challenge para PKCE
        code_verifier = secrets.token_urlsafe(64)[:128]
        code_challenge = base64.urlsafe_b64encode(
            hashlib.sha256(code_verifier.encode()).digest()
        ).rstrip(b"=").decode()

        state = secrets.token_urlsafe(16)

        auth_params = urllib.parse.urlencode({
            "client_id": self.client_id,
            "response_type": "code",
            "redirect_uri": self.redirect_uri,
            "scope": SPOTIFY_SCOPES,
            "state": state,
            "code_challenge_method": "S256",
            "code_challenge": code_challenge
        })
        auth_url = f"{SPOTIFY_AUTH_URL}?{auth_params}"

        # Servidor HTTP temporal para capturar el callback
        auth_result = {"code": None, "error": None}

        class CallbackHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                if "code" in query:
                    auth_result["code"] = query["code"][0]
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.end_headers()
                    self.wfile.write(b"<html><body><h2>Autorizacion exitosa! Puedes cerrar esta ventana.</h2></body></html>")
                else:
                    auth_result["error"] = query.get("error", ["unknown"])[0]
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(b"Error en la autorizacion")
            def log_message(self, fmt, *args):
                pass

        try:
            server = HTTPServer(("127.0.0.1", 8888), CallbackHandler)
            server.timeout = 120  # 2 minutos para que el usuario autorice

            # Abrir navegador
            webbrowser.open(auth_url)

            # Esperar el callback
            while auth_result["code"] is None and auth_result["error"] is None:
                server.handle_request()

            server.server_close()

            if auth_result["error"]:
                return f"Error de autorización: {auth_result['error']}"

            # Intercambiar código por tokens
            token_data = urllib.parse.urlencode({
                "grant_type": "authorization_code",
                "code": auth_result["code"],
                "redirect_uri": self.redirect_uri,
                "client_id": self.client_id,
                "client_secret": self.client_secret,
                "code_verifier": code_verifier
            }).encode()

            req = urllib.request.Request(SPOTIFY_TOKEN_URL, data=token_data, method="POST")
            req.add_header("Content-Type", "application/x-www-form-urlencoded")

            with urllib.request.urlopen(req, timeout=10) as resp:
                tokens = json.loads(resp.read().decode())

            self.access_token = tokens["access_token"]
            self.refresh_token = tokens.get("refresh_token")
            self.token_expiry = time.time() + tokens.get("expires_in", 3600) - 60
            self._save_token_cache()

            return "Autenticación con Spotify exitosa."

        except OSError as e:
            if "Address already in use" in str(e):
                return "El puerto 8888 está en uso. Cierra cualquier proceso que lo esté usando e intenta de nuevo."
            return f"Error al iniciar servidor de callback: {e}"
        except Exception as e:
            return f"Error durante la autenticación: {e}"

    # ── Métodos de la API ──────────────────────────────────────────────────

    def search(self, query: str, search_type: str = "track", limit: int = 5) -> str:
        """Busca en Spotify y devuelve resultados formateados."""
        valid_types = {"track", "artist", "album", "playlist"}
        if search_type not in valid_types:
            search_type = "track"
        limit = max(1, min(10, limit))

        result = self._api_request("GET", "/search", params={
            "q": query,
            "type": search_type,
            "limit": limit,
            "market": "from_token"
        })

        if "error" in result:
            return result["error"]

        lines = [f"Resultados de Spotify para '{query}' (tipo: {search_type}):\n"]
        items_key = f"{search_type}s"
        items = result.get(items_key, {}).get("items", [])

        if not items:
            return f"No se encontraron resultados para '{query}'"

        for i, item in enumerate(items, 1):
            if search_type == "track":
                artists = ", ".join(a["name"] for a in item.get("artists", []))
                album = item.get("album", {}).get("name", "")
                duration_ms = item.get("duration_ms", 0)
                mins, secs = divmod(duration_ms // 1000, 60)
                uri = item.get("uri", "")
                lines.append(f"[{i}] {item['name']} — {artists}")
                lines.append(f"    Album: {album} | Duracion: {mins}:{secs:02d}")
                lines.append(f"    URI: {uri}")
            elif search_type == "artist":
                genres = ", ".join(item.get("genres", [])[:3]) or "Sin genero"
                followers = item.get("followers", {}).get("total", 0)
                uri = item.get("uri", "")
                lines.append(f"[{i}] {item['name']}")
                lines.append(f"    Generos: {genres} | Seguidores: {followers:,}")
                lines.append(f"    URI: {uri}")
            elif search_type == "album":
                artists = ", ".join(a["name"] for a in item.get("artists", []))
                year = item.get("release_date", "")[:4]
                tracks = item.get("total_tracks", 0)
                uri = item.get("uri", "")
                lines.append(f"[{i}] {item['name']} — {artists}")
                lines.append(f"    Año: {year} | Canciones: {tracks}")
                lines.append(f"    URI: {uri}")
            elif search_type == "playlist":
                owner = item.get("owner", {}).get("display_name", "")
                total = item.get("tracks", {}).get("total", 0)
                uri = item.get("uri", "")
                lines.append(f"[{i}] {item['name']}")
                lines.append(f"    Por: {owner} | Canciones: {total}")
                lines.append(f"    URI: {uri}")
            lines.append("")

        return "\n".join(lines).strip()

    def play(self, uri: str = None, query: str = None) -> str:
        """Reproduce una canción, álbum o playlist. Puede recibir un URI directo o buscar por query."""
        body = {}

        if not uri and query:
            # Buscar primero y usar el resultado más popular
            search_result = self._api_request("GET", "/search", params={
                "q": query, "type": "track", "limit": 10, "market": "from_token"
            })
            if "error" in search_result:
                return search_result["error"]
            tracks = search_result.get("tracks", {}).get("items", [])
            if not tracks:
                return f"No se encontro ninguna cancion para '{query}'"
            
            tracks.sort(key=lambda x: x.get("popularity", 0), reverse=True)
            uri = tracks[0]["uri"]
            track_name = tracks[0]["name"]
            artist_name = ", ".join(a["name"] for a in tracks[0].get("artists", []))

        if uri:
            if ":track:" in uri:
                body["uris"] = [uri]
            elif ":album:" in uri or ":playlist:" in uri or ":artist:" in uri:
                body["context_uri"] = uri
            else:
                body["uris"] = [uri]

        result = self._api_request("PUT", "/me/player/play", body=body if body else None, timeout=20)

        if "error" in result:
            return result["error"]

        if not query and not uri:
            return "Reproduccion reanudada. La accion fue exitosa, NO repitas la llamada."
        if query:
            return f"Reproduciendo: {track_name} — {artist_name}. La accion fue exitosa, NO repitas la llamada."
        return "Reproduccion iniciada. La accion fue exitosa, NO repitas la llamada."

    def pause(self) -> str:
        result = self._api_request("PUT", "/me/player/pause", timeout=20)
        return result.get("error", "Reproduccion pausada. La accion fue exitosa, NO repitas la llamada.")

    def resume(self) -> str:
        result = self._api_request("PUT", "/me/player/play", timeout=20)
        return result.get("error", "Reproduccion reanudada. La accion fue exitosa, NO repitas la llamada.")

    def next_track(self) -> str:
        result = self._api_request("POST", "/me/player/next", timeout=20)
        return result.get("error", "Siguiente cancion. La accion fue exitosa, NO repitas la llamada.")

    def previous_track(self) -> str:
        result = self._api_request("POST", "/me/player/previous", timeout=20)
        return result.get("error", "Cancion anterior. La accion fue exitosa, NO repitas la llamada.")

    def set_volume(self, volume: int) -> str:
        volume = max(0, min(100, volume))
        result = self._api_request("PUT", "/me/player/volume", params={"volume_percent": volume}, timeout=20)
        return result.get("error", f"Volumen establecido al {volume}%. La accion fue exitosa, NO repitas la llamada.")

    def current_playing(self) -> str:
        result = self._api_request("GET", "/me/player/currently-playing")
        if "error" in result:
            return result["error"]
        if not result or not result.get("item"):
            return "No se esta reproduciendo nada en este momento."

        item = result["item"]
        name = item.get("name", "Desconocido")
        artists = ", ".join(a["name"] for a in item.get("artists", []))
        album = item.get("album", {}).get("name", "")
        progress = result.get("progress_ms", 0)
        duration = item.get("duration_ms", 0)
        p_min, p_sec = divmod(progress // 1000, 60)
        d_min, d_sec = divmod(duration // 1000, 60)
        is_playing = result.get("is_playing", False)
        state = "Reproduciendo" if is_playing else "Pausado"

        return (f"{state}: {name} — {artists}\n"
                f"Album: {album}\n"
                f"Progreso: {p_min}:{p_sec:02d} / {d_min}:{d_sec:02d}")

    def add_to_queue(self, uri: str = None, query: str = None) -> str:
        if not uri and query:
            search_result = self._api_request("GET", "/search", params={
                "q": query, "type": "track", "limit": 10, "market": "US"
            })
            if "error" in search_result:
                return search_result["error"]
            tracks = search_result.get("tracks", {}).get("items", [])
            if not tracks:
                return f"No se encontro ninguna cancion para '{query}'"
            
            tracks.sort(key=lambda x: x.get("popularity", 0), reverse=True)
            uri = tracks[0]["uri"]
            track_name = tracks[0]["name"]
            artist_name = ", ".join(a["name"] for a in tracks[0].get("artists", []))

        if not uri:
            return "Se necesita un URI o una consulta de busqueda para agregar a la cola."

        result = self._api_request("POST", "/me/player/queue", params={"uri": uri}, timeout=20)
        if "error" in result:
            return result["error"]
        if query:
            return f"Cancion agregada exitosamente a la cola: {track_name} — {artist_name} (uri={uri}). La accion fue exitosa, NO repitas la llamada."
        return f"Cancion con uri={uri} agregada exitosamente a la cola. La accion fue exitosa, NO repitas la llamada."


spotify_mgr = SpotifyManager()

# Patrones de comandos peligrosos
DESTRUCTIVE_RE = re.compile(
    r"\brm\b"            # cualquier rm
    r"|\bdd\b"           # disk destroyer
    r"|\bmkfs\b"         # formatear sistema de archivos
    r"|\bshred\b"        # borrado seguro
    r"|\btruncate\b"     # truncar archivo
    r"|\bwipe\b"         # borrado de disco
    r"|\bmv\s+.*\s+/"    # mover a ruta absoluta
    r"|>\s*/(?!dev/null)" # redirigir a archivo del sistema
    r"|>>\s*/",           # añadir a archivo del sistema
    re.IGNORECASE
)
SUDO_RE = re.compile(r"\bsudo\b")

SYSTEM_PROMPT = f"""Eres Minerva, una asistente inteligente integrada en el escritorio del usuario. Tu nombre viene de la diosa romana de la sabiduría.

## Tu personalidad
- Eres directa, eficiente y con un toque de ingenio sutil. No eres fría ni robótica — eres como una amiga técnica que sabe mucho.
- Respondes de forma natural y concisa. Nada de relleno.
- Tienes sentido del humor ligero cuando la situación lo permite, pero nunca forzado.

## Reglas CRÍTICAS de comunicación
- **NUNCA narres tus acciones.** No digas cosas como "Voy a ejecutar el siguiente comando", "Procederé a realizar esta acción", "Para hacer esto necesito ejecutar...", "Primero voy a verificar...". Simplemente HAZLO. Usa las herramientas directamente sin anunciarlas.
- Si el usuario te pide algo, actúa primero y después explica brevemente el resultado si es necesario.
- No hagas preguntas innecesarias. Si puedes resolver algo con la información disponible, hazlo.
- Sé breve. Las respuestas largas y redundantes aburren. Ve al grano.
- **NUNCA uses formato markdown (como asteriscos, negritas o cursivas).** El usuario te escucha a través de voz y los símbolos se leerían en voz alta (ej: "asterisco hola asterisco"). Genera solo texto plano.

## Herramientas disponibles
- **Filesystem**: Puedes listar directorios (list_dir) y leer archivos (read_file) dentro de {HOME}.
- **Comandos**: Puedes ejecutar comandos bash (run_command). Los destructivos o con sudo pedirán confirmación.
- **Búsqueda web** (web_search): Tienes acceso a internet en tiempo real. Úsala cuando:
  - El usuario pregunte por noticias, eventos recientes o información que puede haber cambiado.
  - Necesites precios, versiones de software, estadísticas actuales, o cualquier dato perecedero.
  - Tu conocimiento interno pueda estar desactualizado.
  - Te pregunten "¿cuál es la última versión de...?", "¿qué pasó con...?", "precio de...", etc.
  - NO la uses para información atemporal o conceptual que ya conoces.
- **Spotify** (spotify_music): Controla Spotify del usuario. Acciones disponibles:
  - "search": Buscar canciones, artistas, albums o playlists. Requiere "query".
  - "play": Reproducir. Puedes pasar un "uri" de Spotify o un "query" para buscar y reproducir directamente.
  - "pause": Pausar la reproduccion actual.
  - "resume": Reanudar la reproduccion.
  - "next": Saltar a la siguiente cancion.
  - "previous": Volver a la cancion anterior.
  - "volume": Cambiar volumen. Requiere "volume" (0-100).
  - "current": Ver que se esta reproduciendo ahora.
  - "queue": Agregar una cancion a la cola. Usa "uri" o "query".
  - Si el usuario pide musica de un artista o cancion especifica, usa "play" con query directamente.
  - Requiere Spotify Premium para controles de reproduccion.

## Reglas de seguridad
- Solo puedes acceder a archivos dentro de {HOME}
- Los comandos destructivos (rm, dd, mkfs, etc.) pedirán confirmación al usuario automáticamente
- Los comandos con sudo usarán pkexec (polkit) para autenticación gráfica
- Nunca inventes el contenido de archivos; usa read_file si necesitas ver uno
- Responde siempre en el idioma que use el usuario

## Contexto del sistema
- Home del usuario: {HOME}
- Sistema operativo: Arch Linux
- Shell: bash
- Fecha/hora actual: {{fecha_actual}}
"""

OLLAMA_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "list_dir",
            "description": "Lista el contenido de un directorio en el sistema de archivos",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del directorio a listar"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Lee el contenido de texto de un archivo en el sistema",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del archivo a leer"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_command",
            "description": "Ejecuta un comando de bash en el sistema",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "El comando de bash a ejecutar"
                    }
                },
                "required": ["command"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "web_search",
            "description": "Busca información actualizada en internet usando DuckDuckGo. Úsala para noticias, versiones de software, precios, eventos recientes, o cualquier información que pueda haber cambiado desde tu entrenamiento.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "La consulta de búsqueda en lenguaje natural o palabras clave"
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Número máximo de resultados a devolver (1-10, por defecto 5)"
                    }
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "spotify_music",
            "description": "Controla Spotify: buscar musica, reproducir, pausar, saltar cancion, volumen, ver que suena. Requiere Spotify Premium para reproduccion.",
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "description": "La accion a realizar: 'search', 'play', 'pause', 'resume', 'next', 'previous', 'volume', 'current', 'queue'",
                        "enum": ["search", "play", "pause", "resume", "next", "previous", "volume", "current", "queue"]
                    },
                    "query": {
                        "type": "string",
                        "description": "Texto de busqueda (para 'search', 'play', 'queue'). Ej: 'Bohemian Rhapsody Queen'"
                    },
                    "uri": {
                        "type": "string",
                        "description": "URI de Spotify (ej: 'spotify:track:xxx'). Opcional si se proporciona query."
                    },
                    "search_type": {
                        "type": "string",
                        "description": "Tipo de busqueda: 'track', 'artist', 'album', 'playlist'. Por defecto 'track'."
                    },
                    "volume": {
                        "type": "integer",
                        "description": "Nivel de volumen 0-100 (solo para accion 'volume')"
                    }
                },
                "required": ["action"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_file",
            "description": "Elimina un archivo o directorio vacío de forma permanente (solo dentro de HOME)",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del archivo o directorio a eliminar"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "create_directory",
            "description": "Crea un nuevo directorio (solo dentro de HOME)",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "La ruta absoluta del directorio a crear"
                    }
                },
                "required": ["path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "move_file",
            "description": "Mueve o renombra un archivo o directorio (solo dentro de HOME)",
            "parameters": {
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "La ruta absoluta de origen"
                    },
                    "destination": {
                        "type": "string",
                        "description": "La ruta absoluta de destino"
                    }
                },
                "required": ["source", "destination"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "find_files",
            "description": "Busca archivos o directorios por patrón de nombre",
            "parameters": {
                "type": "object",
                "properties": {
                    "directory": {
                        "type": "string",
                        "description": "Directorio donde iniciar la busqueda"
                    },
                    "pattern": {
                        "type": "string",
                        "description": "El patron de busqueda, ej: '*.txt' o '*nombre*'"
                    }
                },
                "required": ["directory", "pattern"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_text",
            "description": "Busca texto específico dentro de archivos o directorios usando grep",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Ruta absoluta del archivo o directorio donde buscar"
                    },
                    "query": {
                        "type": "string",
                        "description": "El texto o expresión regular a buscar"
                    }
                },
                "required": ["path", "query"]
            }
        }
    }
]

# ─────────────────────────────────────────────────────────────────────────────
# Base de datos vectorial de Tools (ChromaDB)
# ─────────────────────────────────────────────────────────────────────────────
CHROMA_DB_PATH = os.path.join(HOME, ".local", "share", "quickshell", "minerva_tools")

try:
    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    tool_collection = chroma_client.get_or_create_collection(name="minerva_tools")
    
    # Sincronizar las tools actuales al arrancar
    _tool_docs = [t["function"]["description"] for t in OLLAMA_TOOLS]
    _tool_ids = [t["function"]["name"] for t in OLLAMA_TOOLS]
    
    tool_collection.upsert(
        documents=_tool_docs,
        ids=_tool_ids
    )
    CHROMADB_AVAILABLE = True
except Exception as e:
    print(f"Error inicializando ChromaDB: {e}", file=sys.stderr)
    CHROMADB_AVAILABLE = False

def get_relevant_tools(prompt: str, top_k: int = 3) -> list:
    """Busca las herramientas más relevantes en base al prompt usando ChromaDB."""
    if not CHROMADB_AVAILABLE or not prompt.strip():
        return OLLAMA_TOOLS
        
    try:
        results = tool_collection.query(
            query_texts=[prompt],
            n_results=min(top_k, len(OLLAMA_TOOLS))
        )
        if not results['ids'] or not results['ids'][0]:
            return OLLAMA_TOOLS
            
        relevant_tool_names = results['ids'][0]
        return [t for t in OLLAMA_TOOLS if t["function"]["name"] in relevant_tool_names]
    except Exception as e:
        print(f"Error consultando ChromaDB: {e}", file=sys.stderr)
        return OLLAMA_TOOLS


# ─────────────────────────────────────────────────────────────────────────────
# I/O helpers
# ─────────────────────────────────────────────────────────────────────────────
def emit(obj: dict):
    """Envía un objeto JSON al QML vía stdout (línea terminada en \n)."""
    try:
        sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        import os
        os._exit(0)

def emit_error(msg: str):
    emit({"type": "error", "message": msg})

# ─────────────────────────────────────────────────────────────────────────────
# Seguridad
# ─────────────────────────────────────────────────────────────────────────────
def is_safe_path(p: str) -> bool:
    """Verifica que la ruta esté dentro de $HOME."""
    try:
        resolved = str(pathlib.Path(p).expanduser().resolve())
        return resolved.startswith(HOME)
    except Exception:
        return False

def classify_cmd(cmd: str) -> str:
    """Clasifica un comando como 'sudo', 'destructive' o 'safe'."""
    if SUDO_RE.search(cmd):
        return "sudo"
    if DESTRUCTIVE_RE.search(cmd):
        return "destructive"
    return "safe"

# ─────────────────────────────────────────────────────────────────────────────
# Herramientas del sistema
# ─────────────────────────────────────────────────────────────────────────────
def tool_web_search(query: str, max_results: int = 5) -> str:
    """Busca en internet usando DuckDuckGo (sin API key)."""
    if not WEB_SEARCH_AVAILABLE:
        return "Error: el módulo 'ddgs' no está instalado en el entorno del plugin."
    max_results = max(1, min(10, int(max_results)))
    try:
        results = []
        with DDGS() as ddgs:
            for r in ddgs.text(query, max_results=max_results):
                results.append(r)
        if not results:
            return f"No se encontraron resultados para: {query}"
        lines = [f"Resultados de búsqueda para: '{query}'\n"]
        for i, r in enumerate(results, 1):
            title   = r.get("title",  "Sin título")
            href    = r.get("href",   "")
            snippet = r.get("body",   r.get("description", "Sin descripción"))
            lines.append(f"[{i}] {title}")
            lines.append(f"    URL: {href}")
            lines.append(f"    {snippet}")
            lines.append("")
        return "\n".join(lines).strip()
    except Exception as e:
        return f"Error al realizar la búsqueda web: {e}"

def tool_spotify_music(action: str, query: str = "", uri: str = "",
                       search_type: str = "track", volume: int = 50) -> str:
    """Herramienta unificada de Spotify para la IA."""
    # Verificar configuración
    if not spotify_mgr.is_configured():
        return ("Spotify no esta configurado. El usuario debe editar el archivo "
                f"{SPOTIFY_CREDS_FILE} con su client_id y client_secret "
                "de https://developer.spotify.com/dashboard")

    # Autenticar si no hay token
    if not spotify_mgr.is_authenticated():
        auth_result = spotify_mgr.authenticate()
        if "exitosa" not in auth_result:
            return auth_result

    action = action.strip().lower()

    if action == "search":
        if not query:
            return "Se necesita un texto de busqueda (parametro 'query')."
        return spotify_mgr.search(query, search_type)

    elif action == "play":
        return spotify_mgr.play(uri=uri or None, query=query or None)

    elif action == "pause":
        return spotify_mgr.pause()

    elif action == "resume":
        return spotify_mgr.resume()

    elif action == "next":
        return spotify_mgr.next_track()

    elif action == "previous":
        return spotify_mgr.previous_track()

    elif action == "volume":
        return spotify_mgr.set_volume(volume)

    elif action == "current":
        return spotify_mgr.current_playing()

    elif action == "queue":
        return spotify_mgr.add_to_queue(uri=uri or None, query=query or None)

    else:
        return f"Accion desconocida: '{action}'. Acciones validas: search, play, pause, resume, next, previous, volume, current, queue."

def tool_list_dir(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo se permite dentro de {HOME}"
    try:
        r = subprocess.run(
            ["ls", "-la", "--color=never", exp],
            capture_output=True, text=True, timeout=5
        )
        return (r.stdout if r.returncode == 0 else r.stderr)[:MAX_DIR]
    except Exception as e:
        return f"Error al listar directorio: {e}"

def tool_read_file(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp):
        return f"Acceso denegado: solo se permite dentro de {HOME}"
    try:
        p = pathlib.Path(exp)
        if not p.exists():
            return f"No existe: {exp}"
        if p.is_dir():
            return "Es un directorio; usa list_dir en su lugar"
        if not p.is_file():
            return "No es un archivo regular"
        raw  = p.read_bytes()
        text = raw[:MAX_FILE].decode("utf-8", errors="replace")
        if len(raw) > MAX_FILE:
            text += f"\n\n[... truncado: mostrando {MAX_FILE} de {len(raw)} bytes ...]"
        return text
    except Exception as e:
        return f"Error leyendo archivo: {e}"

import shutil

def tool_delete_file(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp): return f"Acceso denegado: solo {HOME}"
    try:
        p = pathlib.Path(exp)
        if not p.exists(): return f"No existe: {exp}"
        if p.is_dir():
            shutil.rmtree(exp)
        else:
            p.unlink()
        return f"Eliminado exitosamente: {exp}"
    except Exception as e:
        return f"Error eliminando: {e}"

def tool_create_directory(path: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp): return f"Acceso denegado: solo {HOME}"
    try:
        pathlib.Path(exp).mkdir(parents=True, exist_ok=True)
        return f"Directorio creado: {exp}"
    except Exception as e:
        return f"Error creando directorio: {e}"

def tool_move_file(source: str, destination: str) -> str:
    src_exp = str(pathlib.Path(source).expanduser())
    dst_exp = str(pathlib.Path(destination).expanduser())
    if not is_safe_path(src_exp) or not is_safe_path(dst_exp):
        return f"Acceso denegado: origen y destino deben estar en {HOME}"
    try:
        if not pathlib.Path(src_exp).exists(): return f"Origen no existe: {src_exp}"
        shutil.move(src_exp, dst_exp)
        return f"Movido exitosamente a: {dst_exp}"
    except Exception as e:
        return f"Error moviendo: {e}"

def tool_find_files(directory: str, pattern: str) -> str:
    exp = str(pathlib.Path(directory).expanduser())
    if not is_safe_path(exp): return f"Acceso denegado: solo {HOME}"
    try:
        r = subprocess.run(
            ["find", exp, "-name", pattern],
            capture_output=True, text=True, timeout=10
        )
        out = r.stdout if r.returncode == 0 else r.stderr
        return out[:MAX_DIR] if out else "No se encontraron resultados"
    except Exception as e:
        return f"Error buscando archivos: {e}"

def tool_search_text(path: str, query: str) -> str:
    exp = str(pathlib.Path(path).expanduser())
    if not is_safe_path(exp): return f"Acceso denegado: solo {HOME}"
    try:
        r = subprocess.run(
            ["grep", "-rn", query, exp],
            capture_output=True, text=True, timeout=10
        )
        out = r.stdout if r.returncode == 0 else r.stderr
        return out[:MAX_FILE] if out else "No se encontraron coincidencias"
    except Exception as e:
        return f"Error buscando texto: {e}"

# ─────────────────────────────────────────────────────────────────────────────
# Bucle de chat con tool calls nativos
# ─────────────────────────────────────────────────────────────────────────────
def do_chat_gemini(history: list, max_iters: int = 6, model: str = "gemini-2.5-flash", api_key: str = "", temperature: float = 0.7):
    """Ejecuta un turno de chat usando la API compatible con OpenAI de Gemini."""
    if not api_key:
        emit_error("API Key de Gemini no configurada en los ajustes del widget.")
        return
        
    if VOICE_AVAILABLE:
        voice_mgr.tts_stop_event.clear()
        
    user_prompt = ""
    for msg in reversed(history):
        if msg.get("role") == "user":
            user_prompt = msg.get("content", "")
            break
            
    dynamic_tools = get_relevant_tools(user_prompt, top_k=3) if user_prompt else OLLAMA_TOOLS
        
    for iteration in range(max_iters):
        full_response = ""
        current_tool_calls = []
        buffer_frase = ""
        
        clean_history = []
        valid_keys = {"role", "content", "tool_calls", "tool_call_id", "name"}
        for msg in history:
            clean_msg = {k: v for k, v in msg.items() if k in valid_keys}
            clean_history.append(clean_msg)

        req_data = {
            "model": model,
            "messages": clean_history,
            "tools": dynamic_tools,
            "stream": True,
            "temperature": temperature
        }
        
        import urllib.request, urllib.error
        req = urllib.request.Request(
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            data=json.dumps(req_data).encode("utf-8"),
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        )
        
        try:
            with urllib.request.urlopen(req) as resp:
                for line in resp:
                    line = line.decode('utf-8').strip()
                    if not line: continue
                    if line == "data: [DONE]": break
                    if line.startswith("data: "):
                        try:
                            chunk = json.loads(line[6:])
                        except:
                            continue
                        delta = chunk.get("choices", [{}])[0].get("delta", {})
                        
                        if "content" in delta and delta["content"]:
                            token = delta["content"]
                            full_response += token
                            buffer_frase += token
                            emit({"type": "token", "content": token})
                            
                            if VOICE_AVAILABLE and not voice_mgr.tts_stop_event.is_set():
                                if re.search(r'[.!?\n:]', token) and len(buffer_frase.strip()) > 5:
                                    clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                                    if clean_frase:
                                        voice_mgr.tts_queue.put(clean_frase)
                                    buffer_frase = ""
                                    
                        if "tool_calls" in delta:
                            for tc in delta["tool_calls"]:
                                idx = tc.get("index", 0)
                                while len(current_tool_calls) <= idx:
                                    current_tool_calls.append({"id": "", "type": "function", "function": {"name": "", "arguments": ""}})
                                if "id" in tc:
                                    current_tool_calls[idx]["id"] = tc["id"]
                                if "function" in tc:
                                    if "name" in tc["function"]:
                                        current_tool_calls[idx]["function"]["name"] += tc["function"]["name"]
                                    if "arguments" in tc["function"]:
                                        current_tool_calls[idx]["function"]["arguments"] += tc["function"]["arguments"]
        except urllib.error.HTTPError as e:
            err = e.read().decode('utf-8')
            emit_error(f"Error de Gemini API: {e.code} - {err}")
            return
        except Exception as e:
            emit_error(f"Error de conexión con Gemini: {e}")
            return

        if not current_tool_calls:
            if VOICE_AVAILABLE and len(buffer_frase.strip()) > 0 and not voice_mgr.tts_stop_event.is_set():
                clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                if clean_frase:
                    voice_mgr.tts_queue.put(clean_frase)
            emit({"type": "done", "full_response": full_response})
            return

        history.append({"role": "assistant", "content": full_response, "tool_calls": current_tool_calls})
        
        global current_history
        current_history = history
        
        for tc in current_tool_calls:
            tool_name = tc["function"]["name"]
            try:
                args = json.loads(tc["function"]["arguments"])
            except:
                args = {}
                
            emit({"type": "tool_start", "tool": tool_name})
            
            if tool_name == "list_dir":
                result = tool_list_dir(args.get("path", HOME))
            elif tool_name == "read_file":
                result = tool_read_file(args.get("path", ""))
            elif tool_name == "delete_file":
                result = tool_delete_file(args.get("path", ""))
            elif tool_name == "create_directory":
                result = tool_create_directory(args.get("path", ""))
            elif tool_name == "move_file":
                result = tool_move_file(args.get("source", ""), args.get("destination", ""))
            elif tool_name == "find_files":
                result = tool_find_files(args.get("directory", ""), args.get("pattern", ""))
            elif tool_name == "search_text":
                result = tool_search_text(args.get("path", ""), args.get("query", ""))
            elif tool_name == "web_search":
                result = tool_web_search(args.get("query", ""), args.get("max_results", 5))
            elif tool_name == "spotify_music":
                result = tool_spotify_music(
                    action=args.get("action", ""), query=args.get("query", ""),
                    uri=args.get("uri", ""), search_type=args.get("search_type", "track"),
                    volume=args.get("volume", 50)
                )
            elif tool_name == "run_command":
                cmd = args.get("command", "").strip()
                cls = classify_cmd(cmd)
                if cls == "sudo":
                    clean = re.sub(r"^\s*sudo\s+", "", cmd)
                    emit({"type": "sudo_required", "command": clean})
                elif cls == "destructive":
                    emit({"type": "confirm_required", "command": cmd, "reason": "Este comando puede eliminar o modificar datos de forma irreversible"})
                else:
                    emit({"type": "run_command", "command": cmd})
                return
            else:
                result = "Herramienta desconocida"
                
            emit({"type": "tool_result", "tool": tool_name, "result": result})
            history.append({"role": "tool", "tool_call_id": tc.get("id"), "name": tool_name, "content": result})

    emit_error("Demasiadas iteraciones de herramientas (límite: 6)")

def do_chat(history: list, max_iters: int = 6, model: str = MODEL, temperature: float = 0.7, num_ctx: int = 8192, thinking: bool = False):
    """
    Ejecuta un turno de chat, manejando tool calls de manera iterativa.
    Emite los tokens de texto al QML en tiempo real.
    """
    if VOICE_AVAILABLE:
        voice_mgr.tts_stop_event.clear()
        
    user_prompt = ""
    for msg in reversed(history):
        if msg.get("role") == "user":
            user_prompt = msg.get("content", "")
            break
            
    dynamic_tools = get_relevant_tools(user_prompt, top_k=3) if user_prompt else OLLAMA_TOOLS
        
    for iteration in range(max_iters):
        full_response = ""
        current_tool_calls = []
        buffer_frase = ""
        
        try:
            stream = ollama.chat(
                model=model,
                messages=history,
                stream=True,
                tools=dynamic_tools,
                options={"temperature": temperature, "num_ctx": num_ctx},
                think=thinking  # Activa o desactiva "thinking" nativamente en ollama-python >= 0.6
            )
            
            for chunk in stream:
                msg = chunk.message
                if msg.content:
                    token = msg.content
                    full_response += token
                    buffer_frase += token
                    emit({"type": "token", "content": token})
                    
                    if VOICE_AVAILABLE and not voice_mgr.tts_stop_event.is_set():
                        if re.search(r'[.!?\n:]', token) and len(buffer_frase.strip()) > 5:
                            clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                            if clean_frase:
                                voice_mgr.tts_queue.put(clean_frase)
                            buffer_frase = ""
                
                if msg.tool_calls:
                    current_tool_calls = msg.tool_calls

        except Exception as e:
            emit_error(f"Error de Ollama: {e}")
            return

        # Si no hubo llamadas a herramientas, la IA terminó su respuesta final
        if not current_tool_calls:
            if VOICE_AVAILABLE and len(buffer_frase.strip()) > 0 and not voice_mgr.tts_stop_event.is_set():
                clean_frase = buffer_frase.replace("*", "").replace("#", "").strip()
                if clean_frase:
                    voice_mgr.tts_queue.put(clean_frase)
            emit({"type": "done", "full_response": full_response})
            return

        # Hubo llamadas a herramientas
        # ollama-python espera que tool_calls sea un array de diccionarios, pero `current_tool_calls` son objetos pydantic
        # Necesitamos pasarlos a diccionarios puros
        calls_dict = []
        for tc in current_tool_calls:
            calls_dict.append({
                "function": {
                    "name": tc.function.name,
                    "arguments": tc.function.arguments
                }
            })
            
        history.append({"role": "assistant", "content": full_response, "tool_calls": calls_dict})
        
        global current_history
        current_history = history
        
        # Procesamos las herramientas
        for tc in current_tool_calls:
            tool_name = tc.function.name
            args = tc.function.arguments
            
            emit({"type": "tool_start", "tool": tool_name})
            
            if tool_name == "list_dir":
                result = tool_list_dir(args.get("path", HOME))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})
                
            elif tool_name == "read_file":
                result = tool_read_file(args.get("path", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "delete_file":
                result = tool_delete_file(args.get("path", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "create_directory":
                result = tool_create_directory(args.get("path", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "move_file":
                result = tool_move_file(args.get("source", ""), args.get("destination", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "find_files":
                result = tool_find_files(args.get("directory", ""), args.get("pattern", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "search_text":
                result = tool_search_text(args.get("path", ""), args.get("query", ""))
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "web_search":
                query       = args.get("query", "").strip()
                max_results = args.get("max_results", 5)
                result = tool_web_search(query, max_results)
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})

            elif tool_name == "spotify_music":
                result = tool_spotify_music(
                    action=args.get("action", ""),
                    query=args.get("query", ""),
                    uri=args.get("uri", ""),
                    search_type=args.get("search_type", "track"),
                    volume=args.get("volume", 50)
                )
                emit({"type": "tool_result", "tool": tool_name, "result": result})
                history.append({"role": "tool", "name": tool_name, "content": result})
                
            elif tool_name == "run_command":
                cmd = args.get("command", "").strip()
                cls = classify_cmd(cmd)

                if cls == "sudo":
                    clean = re.sub(r"^\s*sudo\s+", "", cmd)
                    emit({"type": "sudo_required", "command": clean})
                elif cls == "destructive":
                    emit({
                        "type":    "confirm_required",
                        "command": cmd,
                        "reason":  "Este comando puede eliminar o modificar datos de forma irreversible"
                    })
                else:
                    emit({"type": "run_command", "command": cmd})

                # Salimos del bucle completamente, esperamos confirmación desde QML
                # El historial ya está guardado globalmente con el assistant tool_call.
                return
            else:
                emit({"type": "tool_result", "tool": tool_name, "result": "Herramienta desconocida"})
                history.append({"role": "tool", "name": tool_name, "content": "Herramienta desconocida"})
                
        # Continúa el bucle while al iterador (Siguiente turno de la IA para que analice el role: tool)
        
    emit_error("Demasiadas iteraciones de herramientas (límite: 6)")

# ─────────────────────────────────────────────────────────────────────────────
# Servidor HTTP y Bucle principal
# ─────────────────────────────────────────────────────────────────────────────
msg_queue = queue.Queue()
current_history = []
current_settings = {}

class BackendHTTPHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        msg_queue.put(post_data)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')
    def log_message(self, format, *args):
        pass # Silenciar logs

def run_server():
    try:
        HTTPServer.allow_reuse_address = True
        server = HTTPServer(('127.0.0.1', 11435), BackendHTTPHandler)
        server.serve_forever()
    except Exception as e:
        print(f"Server error: {e}", file=sys.stderr)
        import os
        os._exit(1)

def main():
    emit({"type": "ready", "model": MODEL, "home": HOME})
    
    t = threading.Thread(target=run_server, daemon=True)
    t.start()

    while True:
        raw_line = msg_queue.get()
        raw_line = raw_line.strip()
        if not raw_line:
            continue

        try:
            msg = json.loads(raw_line)
        except json.JSONDecodeError as e:
            emit_error(f"JSON inválido: {e}")
            continue

        msg_type = msg.get("type")
        global current_history
        global current_settings

        # ── Chat ──────────────────────────────────────────────────────────
        if msg_type == "chat":
            text = msg.get("message", "").strip()
            hist = msg.get("history", [])
            settings = msg.get("settings", {})
            if not text:
                continue

            current_settings = settings

            import datetime
            fecha_actual = datetime.datetime.now().strftime("%A, %d de %B de %Y, %H:%M")
            system_prompt_with_date = SYSTEM_PROMPT.replace("{fecha_actual}", fecha_actual)

            current_history = [{"role": "system", "content": system_prompt_with_date}]
            current_history.extend(hist)
            current_history.append({"role": "user", "content": text})
            
            provider = current_settings.get("provider", "Ollama")
            
            if provider == "Gemini":
                req_model = current_settings.get("gemini_model", "gemini-2.5-flash")
                req_api_key = current_settings.get("gemini_api_key", "")
                try:
                    req_temp = float(current_settings.get("temperature", "0.7"))
                except ValueError:
                    req_temp = 0.7
                do_chat_gemini(current_history, model=req_model, api_key=req_api_key, temperature=req_temp)
            else:
                req_model = current_settings.get("model", MODEL)
                try:
                    req_temp = float(current_settings.get("temperature", "0.7"))
                except ValueError:
                    req_temp = 0.7
                try:
                    req_ctx = int(current_settings.get("num_ctx", "8192"))
                except ValueError:
                    req_ctx = 8192
                req_think = bool(current_settings.get("thinking", False))
                do_chat(current_history, model=req_model, temperature=req_temp, num_ctx=req_ctx, thinking=req_think)

        # ── Confirmación de comando normal ────────────────────────────────
        elif msg_type == "run_confirmed":
            cmd = msg.get("command", "").strip()
            if not cmd:
                continue
            try:
                r = subprocess.run(
                    ["bash", "-c", cmd],
                    capture_output=True, text=True, timeout=30,
                    cwd=HOME, env={**os.environ}
                )
                out = (r.stdout + r.stderr).strip()
                emit({
                    "type":       "command_result",
                    "command":    cmd,
                    "output":     out[:4096] or "(sin salida)",
                    "returncode": r.returncode,
                    "success":    r.returncode == 0
                })
            except subprocess.TimeoutExpired:
                out = "Tiempo de espera agotado (30s)"
                emit({"type": "command_result", "command": cmd, "output": out, "returncode": -1, "success": False})
            except Exception as e:
                out = str(e)
                emit({"type": "command_result", "command": cmd, "output": out, "returncode": -1, "success": False})
            
            # Retomar conversación agregando la respuesta de la tool
            if current_history and current_history[-1].get("tool_calls"):
                # Asumimos que es para la última tool_call
                t_id = current_history[-1]["tool_calls"][-1].get("id", "")
                current_history.append({"role": "tool", "tool_call_id": t_id, "name": "run_command", "content": out[:4096] or "(sin salida)"})
                provider = current_settings.get("provider", "Ollama")
                if provider == "Gemini":
                    req_model = current_settings.get("gemini_model", "gemini-2.5-flash")
                    req_api_key = current_settings.get("gemini_api_key", "")
                    try:
                        req_temp = float(current_settings.get("temperature", "0.7"))
                    except ValueError:
                        req_temp = 0.7
                    do_chat_gemini(current_history, model=req_model, api_key=req_api_key, temperature=req_temp)
                else:
                    req_model = current_settings.get("model", MODEL)
                    try:
                        req_temp = float(current_settings.get("temperature", "0.7"))
                    except ValueError:
                        req_temp = 0.7
                    try:
                        req_ctx = int(current_settings.get("num_ctx", "8192"))
                    except ValueError:
                        req_ctx = 8192
                    req_think = bool(current_settings.get("thinking", False))
                    do_chat(current_history, model=req_model, temperature=req_temp, num_ctx=req_ctx, thinking=req_think)

        # ── Comando sudo via pkexec ───────────────────────────────────────
        elif msg_type == "run_sudo":
            cmd = msg.get("command", "").strip()
            if not cmd:
                continue
            try:
                r = subprocess.run(
                    ["pkexec", "bash", "-c", cmd],
                    capture_output=True, text=True, timeout=30,
                    cwd=HOME, env={**os.environ}
                )
                out = (r.stdout + r.stderr).strip()
                emit({
                    "type":       "command_result",
                    "command":    f"sudo {cmd}",
                    "output":     out[:4096] or "(sin salida)",
                    "returncode": r.returncode,
                    "success":    r.returncode == 0
                })
            except subprocess.TimeoutExpired:
                out = "Tiempo de espera agotado (30s)"
                emit({"type": "command_result", "command": f"sudo {cmd}", "output": out, "returncode": -1, "success": False})
            except Exception as e:
                out = str(e)
                emit({"type": "command_result", "command": f"sudo {cmd}", "output": out, "returncode": -1, "success": False})
            
            if current_history and current_history[-1].get("tool_calls"):
                t_id = current_history[-1]["tool_calls"][-1].get("id", "")
                current_history.append({"role": "tool", "tool_call_id": t_id, "name": "run_command", "content": out[:4096] or "(sin salida)"})
                provider = current_settings.get("provider", "Ollama")
                if provider == "Gemini":
                    req_model = current_settings.get("gemini_model", "gemini-2.5-flash")
                    req_api_key = current_settings.get("gemini_api_key", "")
                    try:
                        req_temp = float(current_settings.get("temperature", "0.7"))
                    except ValueError:
                        req_temp = 0.7
                    do_chat_gemini(current_history, model=req_model, api_key=req_api_key, temperature=req_temp)
                else:
                    req_model = current_settings.get("model", MODEL)
                    try:
                        req_temp = float(current_settings.get("temperature", "0.7"))
                    except ValueError:
                        req_temp = 0.7
                    try:
                        req_ctx = int(current_settings.get("num_ctx", "8192"))
                    except ValueError:
                        req_ctx = 8192
                    req_think = bool(current_settings.get("thinking", False))
                    do_chat(current_history, model=req_model, temperature=req_temp, num_ctx=req_ctx, thinking=req_think)

        # ── Ping / Cancel / Voice ─────────────────────────────────────────
        elif msg_type == "ping":
            emit({"type": "ready", "model": MODEL, "home": HOME})
            
        elif msg_type == "cancel":
            if VOICE_AVAILABLE:
                voice_mgr.stop_tts()
                
        elif msg_type == "stop_tts":
            if VOICE_AVAILABLE:
                voice_mgr.stop_tts()
                
        elif msg_type == "toggle_voice":
            if not VOICE_AVAILABLE:
                emit_error("Dependencias de voz no instaladas")
                continue
                
            if not voice_mgr.is_recording:
                # Iniciar grabación
                res = voice_mgr.toggle_recording()
                if res == "started":
                    emit({"type": "voice_recording_started"})
                else:
                    emit_error("No se pudo iniciar la grabación")
            else:
                # Detener grabación — la transcripción va en un hilo separado
                voice_mgr.is_recording = False
                if voice_mgr.stream:
                    voice_mgr.stream.stop()
                    voice_mgr.stream.close()
                
                emit({"type": "voice_recording_stopped"})
                
                if not voice_mgr.audio_data:
                    continue
                
                audio_np = np.concatenate(voice_mgr.audio_data, axis=0)
                emit({"type": "voice_transcribing"})
                
                def _transcribe_async(audio_data):
                    try:
                        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                            sf.write(tmp.name, audio_data, 16000)
                            tmp_name = tmp.name
                        
                        if not voice_mgr.whisper_model:
                            voice_mgr.whisper_model = Model("base", language="es", print_realtime=False, print_progress=False)
                        
                        segments = voice_mgr.whisper_model.transcribe(tmp_name)
                        text = " ".join([s.text for s in segments]).strip()
                        os.remove(tmp_name)
                        
                        # Filtrar artefactos de whisper
                        if not text or "[BLANK_AUDIO]" in text or len(text) < 2:
                            return
                        
                        emit({"type": "voice_recognized", "text": text})
                    except Exception as e:
                        emit_error(f"Error al transcribir: {e}")
                
                threading.Thread(target=_transcribe_async, args=(audio_np,), daemon=True).start()

if __name__ == "__main__":
    main()
