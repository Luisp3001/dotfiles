#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Job Manager para comandos asíncronos de Minerva.

Proporciona:
  - CommandJob  → representa un comando en ejecución con su estado y metadatos.
  - JobManager  → registro global thread-safe de jobs. Coordina la re-entrada
                  al LLM cuando todos los comandos de un turno han terminado.
  - job_mgr     → instancia singleton global.

Estados de un job:
  queued → running → completed
                   ╰→ failed
         ╰→ cancelled  (usuario rechazó antes de ejecutar)
"""
import threading
import uuid


class CommandJob:
    """Representa un comando único emitido por el LLM."""

    __slots__ = (
        "job_id",
        "tool_call_id",
        "command",
        "is_sudo",
        "status",
        "output",
        "returncode",
    )

    def __init__(self, job_id: str, tool_call_id: str, command: str, is_sudo: bool):
        self.job_id       = job_id        # ID único del job (UUID corto)
        self.tool_call_id = tool_call_id  # ID del tool_call del LLM (para el historial)
        self.command      = command       # display_cmd ("sudo pacman -Ss ...")
        self.is_sudo      = is_sudo
        self.status       = "queued"      # queued | running | completed | failed | cancelled
        self.output       = ""
        self.returncode   = -1

    @property
    def is_terminal(self) -> bool:
        """True si el job está en un estado final (no puede cambiar más)."""
        return self.status in ("completed", "failed", "cancelled")

    def __repr__(self) -> str:
        return f"<CommandJob {self.job_id} [{self.status}] cmd={self.command!r}>"


class JobManager:
    """
    Registro global thread-safe de CommandJobs.

    También gestiona el concepto de 'turno': el conjunto de jobs que el LLM
    emitió en una sola respuesta. Cuando todos terminan, el engine puede
    retomar el chat con todos los resultados.
    """

    def __init__(self) -> None:
        self._jobs: dict         = {}
        self._turn_job_ids: list = []
        self._lock               = threading.Lock()

    # ── Creación ─────────────────────────────────────────────────────────────

    def create(self, tool_call_id: str, command: str, is_sudo: bool) -> CommandJob:
        """Crea y registra un nuevo job. Retorna el objeto CommandJob."""
        job_id = uuid.uuid4().hex[:8]
        job    = CommandJob(job_id, tool_call_id, command, is_sudo)
        with self._lock:
            self._jobs[job_id] = job
        return job

    # ── Consulta ─────────────────────────────────────────────────────────────

    def get(self, job_id: str):
        with self._lock:
            return self._jobs.get(job_id)

    # ── Mutación de estado ───────────────────────────────────────────────────

    def update_status(self, job_id: str, status: str) -> None:
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].status = status

    def append_output(self, job_id: str, text: str) -> None:
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].output += text

    def set_result(self, job_id: str, output: str, returncode: int, success: bool) -> None:
        """Actualiza output, returncode y status al terminar la ejecución."""
        with self._lock:
            if job_id in self._jobs:
                job            = self._jobs[job_id]
                job.output     = output
                job.returncode = returncode
                job.status     = "completed" if success else "failed"

    def cancel(self, job_id: str) -> None:
        """Marca un job como cancelado por el usuario."""
        with self._lock:
            if job_id in self._jobs and not self._jobs[job_id].is_terminal:
                self._jobs[job_id].status = "cancelled"

    # ── Gestión de turno ─────────────────────────────────────────────────────

    def start_turn(self, job_ids: list) -> None:
        """
        Registra los job_ids del turno actual del LLM.
        Llamar desde el engine después de despachar todos los tool calls.
        """
        with self._lock:
            self._turn_job_ids = list(job_ids)

    def get_turn_job_ids(self) -> list:
        with self._lock:
            return list(self._turn_job_ids)

    def all_turn_finished(self) -> bool:
        """True cuando todos los jobs del turno actual están en estado terminal."""
        with self._lock:
            for jid in self._turn_job_ids:
                job = self._jobs.get(jid)
                if job and not job.is_terminal:
                    return False
        return True

    def clear_turn(self) -> None:
        """Limpia el turno actual y elimina sus jobs del registro."""
        with self._lock:
            for jid in self._turn_job_ids:
                self._jobs.pop(jid, None)
            self._turn_job_ids = []


# ── Singleton global ──────────────────────────────────────────────────────────
job_mgr = JobManager()
