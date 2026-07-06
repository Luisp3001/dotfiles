import QtQuick
import Quickshell
import "../../style"

Item {
    id: root

    property bool isRecording: false
    property bool isTranscribing: false
    property bool isThinking: false
    property bool isSpeaking: false
    
    property real stateScale: 1.0
    property real stateSpeed: 1.0
    property real statePulse: 0.0

    states: [
        State {
            name: "recording"
            when: root.isRecording
            PropertyChanges { target: root; stateScale: 1.1; stateSpeed: 1.5; statePulse: 0.0 }
        },
        State {
            name: "transcribing"
            when: root.isTranscribing && !root.isRecording
            PropertyChanges { target: root; stateScale: 1.05; stateSpeed: 1.2; statePulse: 0.0 }
        },
        State {
            name: "thinking"
            when: root.isThinking && !root.isRecording && !root.isTranscribing
            PropertyChanges { target: root; stateScale: 1.05; stateSpeed: 2.5; statePulse: 0.0 }
        },
        State {
            name: "speaking"
            when: root.isSpeaking
            PropertyChanges { target: root; stateScale: 1.05; stateSpeed: 1.8; statePulse: 1.0 }
        },
        State {
            name: "idle"
            when: !root.isRecording && !root.isThinking && !root.isSpeaking && !root.isTranscribing
            PropertyChanges { target: root; stateScale: 1.0; stateSpeed: 1.0; statePulse: 0.0 }
        }
    ]

    Behavior on stateScale { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on stateSpeed { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    Behavior on statePulse { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
    
    // Variables para volumen/animación
    property real audioLevel: 0.5 // Podría conectarse al backend después
    
    Canvas {
        id: canvas
        anchors.fill: parent
        
        property real time: 0
        
        NumberAnimation on time {
            loops: Animation.Infinite
            from: 0
            to: Math.PI * 2
            duration: 4000
            running: true
        }
        
        onTimeChanged: canvas.requestPaint()
        
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            
            var cx = width / 2;
            var cy = height / 2;
            
            // Radio base del orbe suavizado
            var baseRadius = Math.min(width, height) * 0.35 * root.stateScale;
            
            if (root.isRecording) {
                baseRadius += (Math.min(width, height) * 0.35) * (root.audioLevel * 0.2); 
            }
            if (root.statePulse > 0) {
                baseRadius += (Math.min(width, height) * 0.35) * (Math.sin(time * 8.0) * 0.05 * root.statePulse);
            }
            
            // 1. Resplandor exterior suave (outer glow)
            var outerGlow = ctx.createRadialGradient(cx, cy, baseRadius * 0.8, cx, cy, baseRadius * 1.3);
            outerGlow.addColorStop(0, "rgba(255, 255, 255, 0.15)");
            outerGlow.addColorStop(1, "rgba(255, 255, 255, 0)");
            ctx.fillStyle = outerGlow;
            ctx.beginPath();
            ctx.arc(cx, cy, baseRadius * 1.3, 0, 2 * Math.PI);
            ctx.fill();
            
            // 2. Clipping path para definir los bordes cortantes del orbe
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, cy, baseRadius, 0, 2 * Math.PI);
            ctx.clip();
            
            // Fondo oscuro del orbe para dar contraste a los colores
            ctx.fillStyle = "rgba(10, 10, 15, 0.9)";
            ctx.fill();
            
            // 3. Nubes de colores dentro del orbe
            var colors = [
                "rgba(65, 214, 195, 0.95)", // Cyan
                "rgba(255, 32, 110, 0.95)", // Magenta
                "rgba(94, 53, 177, 0.95)",  // Morado
                "rgba(41, 121, 255, 0.95)"  // Azul
            ];
            
            ctx.globalCompositeOperation = "screen";
            
            for (var i = 0; i < colors.length; i++) {
                // Usamos stateSpeed suave en lugar de multiplicador brusco
                var currentSpeed = root.stateSpeed;
                var t = (time * currentSpeed) + (i * Math.PI * 2 / colors.length);
                
                // Animación orbital caótica
                var offsetX = Math.cos(t) * (baseRadius * 0.6);
                var offsetY = Math.sin(t * 1.3) * (baseRadius * 0.6);
                
                var r = baseRadius * 1.3;
                
                var grad = ctx.createRadialGradient(cx + offsetX, cy + offsetY, 0, cx + offsetX, cy + offsetY, r);
                grad.addColorStop(0, colors[i]);
                grad.addColorStop(0.4, colors[i].replace("0.95)", "0.5)"));
                grad.addColorStop(1, "rgba(0,0,0,0)");
                
                ctx.fillStyle = grad;
                ctx.beginPath();
                ctx.arc(cx + offsetX, cy + offsetY, r, 0, 2 * Math.PI);
                ctx.fill();
            }
            
            // 4. Brillo interior (inner highlight) para darle aspecto 3D de esfera
            ctx.globalCompositeOperation = "source-over";
            var innerGlow = ctx.createRadialGradient(cx, cy - baseRadius * 0.3, 0, cx, cy, baseRadius);
            innerGlow.addColorStop(0, "rgba(255, 255, 255, 0.3)");
            innerGlow.addColorStop(1, "rgba(255, 255, 255, 0)");
            ctx.fillStyle = innerGlow;
            ctx.beginPath();
            ctx.arc(cx, cy, baseRadius, 0, 2 * Math.PI);
            ctx.fill();
            
            // Restaurar el contexto para no afectar futuros dibujos
            ctx.restore();
        }
    }
}
