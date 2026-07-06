#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SpotifyManager — OAuth 2.0 PKCE + API REST de Spotify para Minerva.

Expone:
  - SpotifyManager (clase)
  - spotify_mgr   (singleton)
  - tool_spotify_music() (función unificada para la IA)
"""
import base64
import hashlib
import json
import os
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

from ..core.config import (
    SPOTIFY_API_BASE, SPOTIFY_AUTH_URL, SPOTIFY_TOKEN_URL,
    SPOTIFY_SCOPES, SPOTIFY_CREDS_FILE, SPOTIFY_TOKEN_FILE, SPOTIFY_CONFIG_DIR
)


class SpotifyManager:
    """Gestiona la autenticación OAuth 2.0 PKCE y las llamadas a la API de Spotify."""

    def __init__(self):
        self.access_token  = None
        self.refresh_token = None
        self.token_expiry  = 0
        self.client_id     = None
        self.client_secret = None
        self.redirect_uri  = "http://localhost:8888/callback"
        self._auth_server  = None
        self._auth_code    = None
        self._load_credentials()
        self._load_cached_token()

    # ── Autenticación ──────────────────────────────────────────────────────────

    def _load_credentials(self):
        """Carga client_id y client_secret desde el archivo de configuración."""
        if not os.path.exists(SPOTIFY_CREDS_FILE):
            os.makedirs(os.path.dirname(SPOTIFY_CREDS_FILE), exist_ok=True)
            try:
                with open(SPOTIFY_CREDS_FILE, "w") as f:
                    json.dump({
                        "client_id":     "TU_CLIENT_ID_AQUI",
                        "client_secret": "TU_CLIENT_SECRET_AQUI",
                        "redirect_uri":  "http://localhost:8888/callback"
                    }, f, indent=4)
            except Exception as e:
                import sys
                print(f"Error creando archivo de credenciales de Spotify: {e}", file=sys.stderr)
            return
        try:
            with open(SPOTIFY_CREDS_FILE, "r") as f:
                creds = json.load(f)
            self.client_id     = creds.get("client_id",     "").strip()
            self.client_secret = creds.get("client_secret", "").strip()
            self.redirect_uri  = creds.get("redirect_uri",  self.redirect_uri).strip()
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
            self.access_token  = data.get("access_token")
            self.refresh_token = data.get("refresh_token")
            self.token_expiry  = data.get("token_expiry", 0)
        except Exception:
            pass

    def _save_token_cache(self):
        """Persiste tokens en disco."""
        os.makedirs(SPOTIFY_CONFIG_DIR, exist_ok=True)
        try:
            with open(SPOTIFY_TOKEN_FILE, "w") as f:
                json.dump({
                    "access_token":  self.access_token,
                    "refresh_token": self.refresh_token,
                    "token_expiry":  self.token_expiry
                }, f)
        except Exception:
            pass

    def is_configured(self) -> bool:
        return bool(self.client_id and self.client_secret)

    def is_authenticated(self) -> bool:
        return bool(self.access_token or self.refresh_token)

    def _token_expired(self) -> bool:
        return time.time() >= self.token_expiry

    def _refresh_access_token(self) -> bool:
        """Refresca el access token usando el refresh token."""
        if not self.refresh_token or not self.client_id:
            return False
        try:
            data = urllib.parse.urlencode({
                "grant_type":    "refresh_token",
                "refresh_token": self.refresh_token,
                "client_id":     self.client_id,
                "client_secret": self.client_secret
            }).encode()
            req = urllib.request.Request(SPOTIFY_TOKEN_URL, data=data, method="POST")
            req.add_header("Content-Type", "application/x-www-form-urlencoded")
            with urllib.request.urlopen(req, timeout=10) as resp:
                token_data = json.loads(resp.read().decode())
            self.access_token  = token_data["access_token"]
            self.token_expiry  = time.time() + token_data.get("expires_in", 3600) - 60
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

    def _api_request(self, method: str, endpoint: str, body: dict = None,
                     params: dict = None, timeout: int = 10) -> dict:
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
                raw = resp.read()
                if not raw:
                    return {"success": True}
                try:
                    return json.loads(raw.decode())
                except (json.JSONDecodeError, UnicodeDecodeError):
                    return {"success": True}
        except urllib.error.HTTPError as e:
            error_body = e.read().decode() if e.fp else ""
            if e.code == 401 and self._refresh_access_token():
                return self._api_request(method, endpoint, body, params, timeout)
            return {"error": f"Error HTTP {e.code}: {error_body[:500]}"}
        except Exception as e:
            return {"error": f"Error de conexión: {e}"}

    def authenticate(self) -> str:
        """Inicia el flujo OAuth 2.0 Authorization Code con PKCE."""
        if not self.is_configured():
            return (
                "Spotify no está configurado. Edita el archivo "
                f"{SPOTIFY_CREDS_FILE} con tu client_id y client_secret "
                "de https://developer.spotify.com/dashboard"
            )

        code_verifier  = secrets.token_urlsafe(64)[:128]
        code_challenge = base64.urlsafe_b64encode(
            hashlib.sha256(code_verifier.encode()).digest()
        ).rstrip(b"=").decode()
        state = secrets.token_urlsafe(16)

        auth_params = urllib.parse.urlencode({
            "client_id":              self.client_id,
            "response_type":          "code",
            "redirect_uri":           self.redirect_uri,
            "scope":                  SPOTIFY_SCOPES,
            "state":                  state,
            "code_challenge_method":  "S256",
            "code_challenge":         code_challenge
        })
        auth_url = f"{SPOTIFY_AUTH_URL}?{auth_params}"

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
            server.timeout = 120
            webbrowser.open(auth_url)
            while auth_result["code"] is None and auth_result["error"] is None:
                server.handle_request()
            server.server_close()

            if auth_result["error"]:
                return f"Error de autorización: {auth_result['error']}"

            token_data = urllib.parse.urlencode({
                "grant_type":    "authorization_code",
                "code":          auth_result["code"],
                "redirect_uri":  self.redirect_uri,
                "client_id":     self.client_id,
                "client_secret": self.client_secret,
                "code_verifier": code_verifier
            }).encode()

            req = urllib.request.Request(SPOTIFY_TOKEN_URL, data=token_data, method="POST")
            req.add_header("Content-Type", "application/x-www-form-urlencoded")
            with urllib.request.urlopen(req, timeout=10) as resp:
                tokens = json.loads(resp.read().decode())

            self.access_token  = tokens["access_token"]
            self.refresh_token = tokens.get("refresh_token")
            self.token_expiry  = time.time() + tokens.get("expires_in", 3600) - 60
            self._save_token_cache()
            return "Autenticación con Spotify exitosa."

        except OSError as e:
            if "Address already in use" in str(e):
                return "El puerto 8888 está en uso. Cierra cualquier proceso que lo esté usando e intenta de nuevo."
            return f"Error al iniciar servidor de callback: {e}"
        except Exception as e:
            return f"Error durante la autenticación: {e}"

    # ── Métodos de la API ──────────────────────────────────────────────────────

    def search(self, query: str, search_type: str = "track", limit: int = 5) -> str:
        valid_types = {"track", "artist", "album", "playlist"}
        if search_type not in valid_types:
            search_type = "track"
        limit  = max(1, min(10, limit))
        result = self._api_request("GET", "/search", params={
            "q": query, "type": search_type, "limit": limit, "market": "from_token"
        })
        if "error" in result:
            return result["error"]

        lines     = [f"Resultados de Spotify para '{query}' (tipo: {search_type}):\n"]
        items_key = f"{search_type}s"
        items     = result.get(items_key, {}).get("items", [])

        if not items:
            return f"No se encontraron resultados para '{query}'"

        for i, item in enumerate(items, 1):
            if search_type == "track":
                artists      = ", ".join(a["name"] for a in item.get("artists", []))
                album        = item.get("album", {}).get("name", "")
                duration_ms  = item.get("duration_ms", 0)
                mins, secs   = divmod(duration_ms // 1000, 60)
                uri          = item.get("uri", "")
                lines.append(f"[{i}] {item['name']} — {artists}")
                lines.append(f"    Album: {album} | Duracion: {mins}:{secs:02d}")
                lines.append(f"    URI: {uri}")
            elif search_type == "artist":
                genres    = ", ".join(item.get("genres", [])[:3]) or "Sin genero"
                followers = item.get("followers", {}).get("total", 0)
                uri       = item.get("uri", "")
                lines.append(f"[{i}] {item['name']}")
                lines.append(f"    Generos: {genres} | Seguidores: {followers:,}")
                lines.append(f"    URI: {uri}")
            elif search_type == "album":
                artists = ", ".join(a["name"] for a in item.get("artists", []))
                year    = item.get("release_date", "")[:4]
                tracks  = item.get("total_tracks", 0)
                uri     = item.get("uri", "")
                lines.append(f"[{i}] {item['name']} — {artists}")
                lines.append(f"    Año: {year} | Canciones: {tracks}")
                lines.append(f"    URI: {uri}")
            elif search_type == "playlist":
                owner = item.get("owner", {}).get("display_name", "")
                total = item.get("tracks", {}).get("total", 0)
                uri   = item.get("uri", "")
                lines.append(f"[{i}] {item['name']}")
                lines.append(f"    Por: {owner} | Canciones: {total}")
                lines.append(f"    URI: {uri}")
            lines.append("")

        return "\n".join(lines).strip()

    def play(self, uri: str = None, query: str = None) -> str:
        body = {}
        if not uri and query:
            search_result = self._api_request("GET", "/search", params={
                "q": query, "type": "track", "limit": 10, "market": "from_token"
            })
            if "error" in search_result:
                return search_result["error"]
            tracks = search_result.get("tracks", {}).get("items", [])
            if not tracks:
                return f"No se encontro ninguna cancion para '{query}'"
            tracks.sort(key=lambda x: x.get("popularity", 0), reverse=True)
            uri         = tracks[0]["uri"]
            track_name  = tracks[0]["name"]
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
        item      = result["item"]
        name      = item.get("name", "Desconocido")
        artists   = ", ".join(a["name"] for a in item.get("artists", []))
        album     = item.get("album", {}).get("name", "")
        progress  = result.get("progress_ms", 0)
        duration  = item.get("duration_ms", 0)
        p_min, p_sec = divmod(progress // 1000, 60)
        d_min, d_sec = divmod(duration // 1000, 60)
        state     = "Reproduciendo" if result.get("is_playing", False) else "Pausado"
        return (
            f"{state}: {name} — {artists}\n"
            f"Album: {album}\n"
            f"Progreso: {p_min}:{p_sec:02d} / {d_min}:{d_sec:02d}"
        )

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
            uri         = tracks[0]["uri"]
            track_name  = tracks[0]["name"]
            artist_name = ", ".join(a["name"] for a in tracks[0].get("artists", []))

        if not uri:
            return "Se necesita un URI o una consulta de busqueda para agregar a la cola."

        result = self._api_request("POST", "/me/player/queue", params={"uri": uri}, timeout=20)
        if "error" in result:
            return result["error"]
        if query:
            return f"Cancion agregada exitosamente a la cola: {track_name} — {artist_name} (uri={uri}). La accion fue exitosa, NO repitas la llamada."
        return f"Cancion con uri={uri} agregada exitosamente a la cola. La accion fue exitosa, NO repitas la llamada."


# ─────────────────────────────────────────────────────────────────────────────
# Singleton + función unificada para la IA
# ─────────────────────────────────────────────────────────────────────────────
spotify_mgr = SpotifyManager()


def tool_spotify_music(action: str, query: str = "", uri: str = "",
                       search_type: str = "track", volume: int = 50) -> str:
    """Herramienta unificada de Spotify para la IA."""
    if not spotify_mgr.is_configured():
        return (
            "Spotify no esta configurado. El usuario debe editar el archivo "
            f"{SPOTIFY_CREDS_FILE} con su client_id y client_secret "
            "de https://developer.spotify.com/dashboard"
        )

    if not spotify_mgr.is_authenticated():
        def _run_auth():
            spotify_mgr.authenticate()
        threading.Thread(target=_run_auth, daemon=True).start()
        return (
            "Spotify necesita autorizacion. Se ha abierto el navegador para que inicies sesion. "
            "Una vez que autorices en el navegador, intenta tu peticion de nuevo."
        )

    action = action.strip().lower()
    if action == "search":
        res = spotify_mgr.search(query, search_type) if query else "Se necesita un texto de busqueda (parametro 'query')."
    elif action == "play":
        res = spotify_mgr.play(uri=uri or None, query=query or None)
    elif action == "pause":
        res = spotify_mgr.pause()
    elif action == "resume":
        res = spotify_mgr.resume()
    elif action == "next":
        res = spotify_mgr.next_track()
    elif action == "previous":
        res = spotify_mgr.previous_track()
    elif action == "volume":
        res = spotify_mgr.set_volume(volume)
    elif action == "current":
        res = spotify_mgr.current_playing()
    elif action == "queue":
        res = spotify_mgr.add_to_queue(uri=uri or None, query=query or None)
    else:
        res = f"Accion desconocida: '{action}'. Acciones validas: search, play, pause, resume, next, previous, volume, current, queue."

    return res + "\n\nIMPORTANTE: Responde brevemente al usuario confirmando verbalmente lo que acabas de hacer o informando del error si lo hubo."
