# Quickshell Dynamic Island - Guía del Proyecto y Desarrollo de Plugins

Este proyecto implementa una "Isla Dinámica" interactiva usando **Quickshell**. La interfaz principal se compone del `Bar.qml` que controla la barra superior y maneja las transiciones fluidas entre su estado "cerrado" (una pequeña píldora) y "expandido" (mostrando widgets detallados).

## Arquitectura General
* `core/bar/Bar.qml`: El contenedor principal de la Isla Dinámica. Maneja las dimensiones, animaciones de apertura/cierre y muestra los componentes expandidos.
* `core/bar/CenterSection.qml`: La "pastilla" central visible cuando la isla está cerrada. Al deslizar sobre ella, se cambia de widget (ej. entre el reloj y Spotify).
* `core/bar/NotificationCenter.qml`: Panel expandido por defecto de la isla (Tab 0).
* `PluginManager`: Motor interno que detecta carpetas con archivos `plugin.json` y los inyecta dinámicamente en tiempo de ejecución.

---

## 🛠️ Cómo crear un nuevo Plugin Dinámico

La arquitectura permite que agregues fácilmente nuevos plugins modulares (como el de Spotify, medidores de sistema, clima, etc.) sin tocar el código base.

### 1. Estructura de archivos
Un plugin debe vivir en su propia carpeta (por ejemplo en `~/.config/quickshell/optional/mi_plugin/`).
Debe contener obligatoriamente al menos dos archivos:
- `plugin.json` (Manifiesto)
- `Main.qml` (Componente visual principal)

### 2. El Manifiesto (`plugin.json`)
Debe ser un JSON válido que declare los metadatos del plugin. Quickshell lo leerá para cargar el módulo en el gestor.

```json
{
  "id": "com.tu_nombre.mi_plugin",
  "name": "Mi Super Plugin",
  "description": "Descripción de lo que hace el plugin.",
  "version": "1.0.0",
  "author": "Tu Nombre",
  "main": "Main.qml"
}
```

### 3. El Componente Principal (`Main.qml`)
El archivo principal debe exponer ciertas **properties** (propiedades) estandarizadas para que `Bar.qml` y `CenterSection.qml` puedan incrustarlo adecuadamente tanto en modo minimizado como maximizado.

Aquí tienes un esqueleto base con las **propiedades que obligatoriamente debes exponer**:

```qml
import QtQuick

Item {
    id: widget

    // 1. Identificador único (debe coincidir con el plugin.json)
    property string pluginId: "com.tu_nombre.mi_plugin"

    // 2. Tipo de plugin (se usa para iconos fallback, ej: "window", "metric", "tool")
    property string type: "tool"

    // 3. Icono de la pestaña global (Opcional: si no se especifica, usa el fallback de type)
    property string tabIcon: "󰏗"

    // ─────────────────────────────────────────────────────────────────
    // COMPONENTE 1: Icono en la barra (Cuando la isla está cerrada, a la derecha)
    property Component barIcon: Component {
        Text {
            text: "󰏗" // Tu icono (Nerd Fonts)
            color: "white"
            font.pixelSize: 14
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // COMPONENTE 2: Pastilla Central (Cuando la isla está cerrada y seleccionada)
    // Este componente se insertará dentro de CenterSection.qml
    property Component centerWidget: Component {
        Item {
            implicitWidth: contentRow.implicitWidth
            implicitHeight: 24

            Row {
                id: contentRow
                anchors.centerIn: parent
                spacing: 8
                
                Text { text: "󰏗"; color: "white" }
                Text { text: "Info rápida"; color: "white" }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // COMPONENTE 3: Panel Expandido (Cuando la isla está ABIERTA)
    // Este componente define el diseño detallado.
    property int expandedWidth: 400 // Opcional: define el ancho que pedirá la isla
    property int expandedHeight: 200 // Opcional: define el alto que pedirá la isla

    property Component expandedPanel: Component {
        Item {
            anchors.fill: parent

            // Opcional: El Loader inyecta rootWidget y shellRoot por si necesitas invocar cosas globales
            property var rootWidget
            property var shellRoot

            Rectangle {
                anchors.fill: parent
                color: "#1e1e1e"
                radius: 16

                Text {
                    anchors.centerIn: parent
                    text: "¡Aquí va la interfaz completa de tu plugin!"
                    color: "white"
                }
            }
        }
    }
}
```

### 4. Menú de Configuración (Opcional)
Si quieres que tu plugin tenga opciones personalizables desde la interfaz de Quickshell (pestaña de Plugins), puedes definir una propiedad `settingsConfig` en tu `Main.qml`. El sistema generará automáticamente un menú con interruptores y guardará las preferencias del usuario en `~/.config/quickshell/plugin_settings.json`.

```qml
    // Define las propiedades locales
    property bool miAjuste: true

    // Expón la configuración al sistema
    property var settingsConfig: [
        { id: "miAjuste", name: "Activar mi super ajuste", type: "bool", defaultValue: true }
    ]

    // Lee los ajustes guardados al inicializar
    Component.onCompleted: {
        if (parent && parent.getSetting) {
            miAjuste = parent.getSetting(pluginId, "miAjuste", true)
        }
    }

    // Reacciona en tiempo real a los cambios desde la interfaz
    Connections {
        target: widget.parent && widget.parent.settingChanged ? widget.parent : null
        function onSettingChanged(id, key, value) {
            if (id === widget.pluginId) {
                if (key === "miAjuste") widget.miAjuste = value
            }
        }
    }
```

### Notas sobre la integración
1. **Dimensiones Dinámicas**: `Bar.qml` leerá las propiedades `expandedWidth` y `expandedHeight` (si existen) de tu `Main.qml` para cambiar el tamaño de la isla dinámicamente al seleccionarse tu pestaña.
2. **Tab Bar Global (Generación Automática)**: Cuando tu plugin expone la propiedad `centerWidget` y está activo, se añade automáticamente a la lista interna `centerWidgets` de `CenterSection.qml`.
    - Luego, la barra superior (`Bar.qml`) usa un `Repeater` que detecta esta lista y crea una pestaña para tu plugin **sin que tengas que tocar el código principal**.
    - **Icono de la pestaña**: El icono que se mostrará en tu pestaña puede ser personalizado declarando la propiedad `property string tabIcon` en tu `Main.qml` (ej. `property string tabIcon: "\u{F1BC}"`). Si esta propiedad no se especifica, el sistema usará el valor de la propiedad `type`: si es `"window"`, usará el icono `󰖲`; de lo contrario (ej. `"tool"`, `"metric"`), usará el icono de paquete `󰏗`.
3. **Señal de Click**: Si en tu `centerWidget` quieres que al darle clic pase algo, ten en cuenta que el clic ya lo maneja `CenterSection.qml` para expandir la isla. Tu `centerWidget` no necesita tener un `MouseArea` global que detenga el evento, solo renderiza información.
