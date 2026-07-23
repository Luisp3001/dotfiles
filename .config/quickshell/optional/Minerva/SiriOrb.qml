import QtQuick
import Quickshell
import "../../style"

// ── SiriOrb — GPU ShaderEffect con análisis de audio en tiempo real ──────
// Reemplaza el anterior Canvas (CPU/JS) con un fragment shader que ejecuta
// Simplex Noise, 4 ondas de color con screen blend y glow gaussiano,
// todo modulado por RMS + 4 bandas FFT del audio de Minerva.

Item {
    id: root

    property bool isRecording: false
    property bool isTranscribing: false
    property bool isThinking: false
    property bool isSpeaking: false
    
    property bool isPendingTask: false
    property bool isUrgentTask: false

    // ── Datos de audio en tiempo real (alimentados por el backend) ─────
    property real audioRms:   0.0
    property real audioBand0: 0.0   // sub-bass  (20–80 Hz)
    property real audioBand1: 0.0   // bass      (80–300 Hz)
    property real audioBand2: 0.0   // mids      (300–2000 Hz)
    property real audioBand3: 0.0   // highs     (2000–8000 Hz)

    // ── Animated state properties ─────────────────────────────────────
    property real stateAmplitude: 0.10
    property real stateSpeed: 0.65
    property real stateOpacity: 0.55

    states: [
        State {
            name: "recording"
            when: root.isRecording
            PropertyChanges { target: root; stateAmplitude: 0.50; stateSpeed: 1.6; stateOpacity: 1.0 }
        },
        State {
            name: "transcribing"
            when: root.isTranscribing && !root.isRecording
            PropertyChanges { target: root; stateAmplitude: 0.20; stateSpeed: 0.85; stateOpacity: 0.80 }
        },
        State {
            name: "thinking"
            when: root.isThinking && !root.isRecording && !root.isTranscribing
            PropertyChanges { target: root; stateAmplitude: 0.28; stateSpeed: 3.4; stateOpacity: 0.90 }
        },
        State {
            name: "speaking"
            when: root.isSpeaking
            PropertyChanges { target: root; stateAmplitude: 0.45; stateSpeed: 2.1; stateOpacity: 1.0 }
        },
        State {
            name: "pending_task"
            when: root.isPendingTask
            PropertyChanges { target: root; stateAmplitude: 0.15; stateSpeed: 0.8; stateOpacity: 0.7 }
        },
        State {
            name: "urgent_task"
            when: root.isUrgentTask
            PropertyChanges { target: root; stateAmplitude: 0.35; stateSpeed: 2.8; stateOpacity: 1.0 }
        },
        State {
            name: "idle"
            when: !root.isRecording && !root.isThinking && !root.isSpeaking && !root.isTranscribing && !root.isPendingTask && !root.isUrgentTask
            PropertyChanges { target: root; stateAmplitude: 0.10; stateSpeed: 0.65; stateOpacity: 0.55 }
        }
    ]

    Behavior on stateAmplitude { NumberAnimation { duration: 550; easing.type: Easing.InOutQuad } }
    Behavior on stateSpeed     { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    Behavior on stateOpacity   { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } }

    // ── Continuous Phase Accumulator (avoids animation jumps) ──────────
    property real _t: 0

    Timer {
        interval: 16        // ~60 fps
        running: true
        repeat: true
        onTriggered: {
            // Acumular fase: dt (0.016s) × velocidad base (~2.094 rad/s)
            root._t += 0.0335 * root.stateSpeed
        }
    }

    // ── GPU ShaderEffect ──────────────────────────────────────────────
    ShaderEffect {
        id: orbShader
        anchors.fill: parent
        opacity: root.stateOpacity
        Behavior on opacity { NumberAnimation { duration: 450 } }

        // ── Uniforms → fragment shader ────────────────────────────────
        // El orden DEBE coincidir con el layout del uniform block en el .frag
        property real u_time:      root._t
        property real u_rms:       root.audioRms
        property real u_band0:     root.audioBand0
        property real u_band1:     root.audioBand1
        property real u_band2:     root.audioBand2
        property real u_band3:     root.audioBand3
        property real u_amplitude: root.stateAmplitude
        property real u_speed:     root.stateSpeed
        property real u_width:     width
        property real u_height:    height

        fragmentShader: "shaders/siri_orb.frag.qsb"
    }

    // Overlay rojo parpadeante para tareas urgentes
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#ff3333"
        opacity: root.isUrgentTask ? 0.35 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        SequentialAnimation on opacity {
            running: root.isUrgentTask
            loops: Animation.Infinite
            NumberAnimation { to: 0.6; duration: 400; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.1; duration: 400; easing.type: Easing.InOutSine }
        }
    }
}
