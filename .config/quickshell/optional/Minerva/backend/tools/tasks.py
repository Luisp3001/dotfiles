from backend.core.tasks_db import add_task, complete_task, get_pending_tasks

_RECURRENCE_LABELS = {
    "daily":   "Diaria",
    "weekly":  "Semanal",
    "monthly": "Mensual",
    "yearly":  "Anual",
}

def tool_manage_tasks(
    action: str,
    description: str = "",
    task_id: int = None,
    due_date: str = None,
    recurrence: str = None,
    recurrence_day: int = None,
    recurrence_month: int = None,
) -> str:
    """Herramienta para que la IA gestione tareas en la base de datos PostgreSQL."""

    if action == "add":
        if not description:
            return "Error: Se requiere una descripción para añadir una tarea."
        success = add_task(description, due_date, recurrence, recurrence_day, recurrence_month)
        if success:
            rec_info = ""
            if recurrence:
                label = _RECURRENCE_LABELS.get(recurrence, recurrence)
                day_info = f" (día {recurrence_day})" if recurrence_day is not None else ""
                month_info = f" del mes {recurrence_month}" if recurrence_month is not None else ""
                rec_info = f" | Recurrencia: {label}{day_info}{month_info}"
            return f"Tarea '{description}' añadida exitosamente.{rec_info}"
        else:
            return "Error al añadir la tarea a la base de datos."

    elif action == "complete":
        if not task_id:
            return "Error: Se requiere el task_id para completar una tarea."
        success = complete_task(task_id)
        if success:
            return f"Tarea #{task_id} marcada como completada."
        else:
            return f"Error al completar la tarea #{task_id}."

    elif action == "list":
        tasks = get_pending_tasks()
        if not tasks:
            return "No hay tareas pendientes en este momento."

        result = "Tareas pendientes:\n"
        for t in tasks:
            date_str = f" (Para: {t['due_date']})" if t.get('due_date') else ""
            rec = t.get('recurrence')
            if rec:
                label = _RECURRENCE_LABELS.get(rec, rec)
                day_info = f" día {t['recurrence_day']}" if t.get('recurrence_day') is not None else ""
                month_info = f" mes {t['recurrence_month']}" if t.get('recurrence_month') is not None else ""
                rec_str = f" [Recurrencia: {label}{day_info}{month_info}]"
            else:
                rec_str = ""
            result += f"- [ID: {t['id']}] {t['description']}{date_str}{rec_str}\n"
        return result

    else:
        return f"Acción desconocida: {action}. Usa 'add', 'complete' o 'list'."
