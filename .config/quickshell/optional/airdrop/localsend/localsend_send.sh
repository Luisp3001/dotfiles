#!/bin/bash
TARGET="$1"
shift

if [ -z "$TARGET" ] || [ $# -eq 0 ]; then
    notify-send "LocalSend" "Usage: localsend_send.sh <ip> <file1>..." -i dialog-error
    exit 1
fi

PORT=53317
FINGERPRINT_FILE="$HOME/.cache/qs_localsend_fp"
[ -f "$FINGERPRINT_FILE" ] || openssl rand -hex 16 > "$FINGERPRINT_FILE"
FINGERPRINT=$(cat "$FINGERPRINT_FILE")

# Escribir el payload a un archivo temporal para evitar límites de ARG_MAX
# con muchos archivos o rutas largas
TMPFILE=$(mktemp /tmp/localsend_payload.XXXXXX.json)
trap 'rm -f "$TMPFILE"' EXIT

python3 - "$FINGERPRINT" "$TMPFILE" "$@" << 'EOF'
import json, sys, os, uuid, mimetypes

fp       = sys.argv[1]
tmp_path = sys.argv[2]
files_args = sys.argv[3:]

files_map = {}
for f in files_args:
    if os.path.isfile(f):
        fid = f"qs_{uuid.uuid4().hex[:8]}"
        files_map[fid] = {
            "path": f,
            "meta": {
                "id": fid,
                "fileName": os.path.basename(f),
                "size": os.path.getsize(f),
                "fileType": mimetypes.guess_type(f)[0] or "application/octet-stream",
                "sha256": None, "preview": None, "metadata": None
            }
        }

payload = {
    "info": {
        "alias": "QuickShell Stash",
        "version": "2.1",
        "deviceModel": None,
        "deviceType": "headless",
        "fingerprint": fp,
        "port": 53317,
        "protocol": "https",
        "download": False
    },
    "files": {k: v["meta"] for k, v in files_map.items()}
}

# Guardar payload + mapa juntos en el archivo temporal
with open(tmp_path, "w") as f:
    json.dump({"payload": payload, "map": files_map}, f)
EOF

if [ ! -s "$TMPFILE" ]; then
    notify-send "LocalSend" "Error generando payload" -i dialog-error
    exit 1
fi

# Extraer solo el payload para prepare-upload (sin el mapa interno)
JSON_PAYLOAD=$(python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    d = json.load(f)
print(json.dumps(d['payload']))
" "$TMPFILE")

RESP=$(curl -sk --max-time 30 -X POST "https://$TARGET:$PORT/api/localsend/v2/prepare-upload" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

SESSION=$(python3 -c "
import sys, json
raw = sys.stdin.read().strip()
d = json.loads(raw) if raw else {}
print(d.get('sessionId', ''))
" <<< "$RESP" 2>/dev/null)

if [ -z "$SESSION" ]; then
    echo "REJECTED"
    notify-send "LocalSend" "Rejected or timed out" -i dialog-error
    exit 1
fi

# Upload de archivos con reporte de progreso
python3 - "$TMPFILE" "$RESP" "$TARGET" "$SESSION" << 'EOF'
import sys, json, os, subprocess
import http.client
import ssl

def notify(title, msg, icon):
    subprocess.run(["notify-send", title, msg, "-i", icon])

try:
    tmp_path = sys.argv[1]
    resp_data = json.loads(sys.argv[2])
    target    = sys.argv[3]
    session   = sys.argv[4]

    with open(tmp_path) as f:
        data = json.load(f)

    files_map     = data["map"]
    accepted_files = resp_data.get("files", {})

    accepted_fids = []
    total_size    = 0
    for fid, token in accepted_files.items():
        if token and fid in files_map:
            total_size += files_map[fid]["meta"]["size"]
            accepted_fids.append((fid, token))

    if not accepted_fids:
        print("REJECTED", flush=True)
        sys.exit(1)

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode    = ssl.CERT_NONE

    uploaded_total = 0
    success_count  = 0
    fail_count     = 0

    for fid, token in accepted_fids:
        f_info = files_map[fid]
        path   = f_info["path"]
        mime   = f_info["meta"]["fileType"]
        f_size = f_info["meta"]["size"]

        try:
            # Sin timeout en el nivel de conexión para no cortar uploads grandes;
            # curl ya validó que el host responde en prepare-upload
            conn = http.client.HTTPSConnection(target, 53317, context=ctx)
            conn.putrequest("POST", f"/api/localsend/v2/upload?sessionId={session}&fileId={fid}&token={token}")
            conn.putheader("Content-Type", mime)
            conn.putheader("Content-Length", str(f_size))
            conn.endheaders()

            with open(path, "rb") as f:
                while True:
                    chunk = f.read(262144)  # 256 KB
                    if not chunk:
                        break
                    conn.send(chunk)
                    uploaded_total += len(chunk)
                    if total_size > 0:
                        prog = (uploaded_total / total_size) * 100
                        print(f"PROGRESS:{prog:.2f}", flush=True)

            resp = conn.getresponse()
            if resp.status == 200:
                success_count += 1
            else:
                fail_count += 1

        except Exception as e:
            print("CANCELLED", flush=True)
            fail_count += 1
            break

    total = len(accepted_fids)
    if total == 1:
        fname = os.path.basename(files_map[accepted_fids[0][0]]["path"])
        if success_count == 1:
            notify("LocalSend", f"Sent: {fname}", "emblem-ok-symbolic")
        else:
            notify("LocalSend", f"Failed to send: {fname}", "dialog-error")
            sys.exit(1)
    elif total > 1:
        if fail_count == 0:
            notify("LocalSend", f"Sent {success_count} files", "emblem-ok-symbolic")
        else:
            notify("LocalSend", f"Sent {success_count} files ({fail_count} failed)", "dialog-error")
            sys.exit(1)

except Exception as e:
    print("CANCELLED", flush=True)
    notify("LocalSend", "Upload error", "dialog-error")
    sys.exit(1)
EOF