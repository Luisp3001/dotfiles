import os
import datetime
import psycopg2
from psycopg2.extras import RealDictCursor
from backend.core.io import emit_error

def get_connection():
    """Obtiene una conexión a la base de datos PostgreSQL usando variables de entorno."""
    try:
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST", "localhost"),
            port=os.getenv("DB_PORT", "5432"),
            user=os.getenv("DB_USER", "postgres"),
            password=os.getenv("DB_PASSWORD", ""),
            dbname=os.getenv("DB_NAME", "postgres")
        )
        return conn
    except Exception as e:
        emit_error(f"Error conectando a PostgreSQL: {e}")
        return None

def init_db():
    """Inicializa la base de datos creando la tabla si no existe."""
    conn = get_connection()
    if not conn:
        return

    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS minerva_tasks (
                        id SERIAL PRIMARY KEY,
                        description TEXT NOT NULL,
                        status VARCHAR(20) DEFAULT 'pending',
                        due_date TIMESTAMP NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    );
                """)
    except Exception as e:
        emit_error(f"Error inicializando DB de tareas: {e}")
    finally:
        conn.close()

def get_pending_tasks():
    """Devuelve una lista de tareas pendientes."""
    conn = get_connection()
    if not conn:
        return []

    tasks = []
    try:
        with conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                cursor.execute("""
                    SELECT id, description, status, due_date
                    FROM minerva_tasks
                    WHERE status = 'pending'
                    ORDER BY created_at ASC;
                """)
                tasks = cursor.fetchall()
    except Exception as e:
        emit_error(f"Error obteniendo tareas pendientes: {e}")
    finally:
        conn.close()
    return tasks

def add_task(description, due_date=None):
    """Agrega una nueva tarea a la base de datos."""
    conn = get_connection()
    if not conn:
        return False

    try:
        with conn:
            with conn.cursor() as cursor:
                if due_date:
                    cursor.execute("""
                        INSERT INTO minerva_tasks (description, due_date)
                        VALUES (%s, %s);
                    """, (description, due_date))
                else:
                    cursor.execute("""
                        INSERT INTO minerva_tasks (description)
                        VALUES (%s);
                    """, (description,))
        return True
    except Exception as e:
        emit_error(f"Error agregando tarea: {e}")
        return False
    finally:
        conn.close()

def complete_task(task_id):
    """Marca una tarea como completada."""
    conn = get_connection()
    if not conn:
        return False

    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute("""
                    UPDATE minerva_tasks
                    SET status = 'completed'
                    WHERE id = %s;
                """, (task_id,))
        return True
    except Exception as e:
        emit_error(f"Error completando tarea: {e}")
        return False
    finally:
        conn.close()
