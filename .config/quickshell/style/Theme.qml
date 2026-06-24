// style/Theme.qml — Sistema de diseño global
// Centraliza colores, fuentes y tamaños para mantener consistencia visual
pragma Singleton
import QtQuick

QtObject {
    // ── Colores ──────────────────────────────────────────────────────────────
    readonly property color bgBar:       "#CC0d0d0d"   // negro semi-transparente
    readonly property color bgPill:      "#1A1A1A"     // fondo de pastillas/secciones
    readonly property color accent:      "#89b4fa"     // azul Catppuccin fMocha
    readonly property color accentDim:   "#585b70"     // gris apagado
    readonly property color textPrimary: "#cdd6f4"     // blanco-azulado
    readonly property color textMuted:   "#6c7086"     // gris tenue
    readonly property color success:     "#a6e3a1"     // verde (batería ok / wifi ok)
    readonly property color warning:     "#f9e2af"     // amarillo (batería baja)
    readonly property color danger:      "#f38ba8"     // rojo (batería crítica / sin wifi)

    // ── Tipografía ───────────────────────────────────────────────────────────
    readonly property string fontMono:   "JetBrainsMono Nerd Font"
    readonly property string fontSans:   "Inter"
    readonly property int    fontSizeXs: 12
    readonly property int    fontSizeSm: 14
    readonly property int    fontSizeMd: 16

    // ── Geometría ────────────────────────────────────────────────────────────
    readonly property int barHeight:       42
    readonly property int pillPadding:      8
    readonly property int pillRadius:       6
    readonly property int spacing:          6
    readonly property int iconSize:        16
}
