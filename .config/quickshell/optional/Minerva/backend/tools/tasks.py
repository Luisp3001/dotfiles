from backend.core.tasks_db import add_task, complete_task, get_pending_tasks

def tool_manage_tasks(action: str, description: str = "", task_id: int = None, due_date: str = None) -> str:
    """Herramienta para que la IA gestione tareas en la base de datos PostgreSQL."""
    if action == "add":
        if not description:
            return "Error: Se requiere una descripción para añadir una tarea."
        success = add_task(description, due_date)
        if success:
            return f"Tarea '{description}' añadida exitosamente."
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
            result += f"- [ID: {t['id']}] {t['description']}{date_str}\n"
        return result
        
    else:
        return f"Acción desconocida: {action}. Usa 'add', 'complete' o 'list'."
