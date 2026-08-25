#!/bin/bash
# setup-apns.sh — deja lista la configuracion de APNs en este Mac.
#
# Antes de correrlo hace falta la clave, que SOLO se puede descargar una vez:
#   developer.apple.com → Certificates, Identifiers & Profiles → Keys → +
#   Nombre: "RemoteSSH APNs"   Marcar: Apple Push Notifications service (APNs)
#   Continue → Register → Download   (guarda el .p8: no hay segunda descarga)
#
# Uso:  ./scripts/setup-apns.sh ~/Downloads/AuthKey_ABCD123456.p8
set -euo pipefail

P8="${1:-}"
[ -f "$P8" ] || { echo "uso: $0 /ruta/AuthKey_XXXXXXXXXX.p8"; exit 1; }

# El Key ID va en el propio nombre del fichero que da Apple.
KEY_ID=$(basename "$P8" | sed -E 's/^AuthKey_([A-Z0-9]{10})\.p8$/\1/')
if [ "$KEY_ID" = "$(basename "$P8")" ]; then
    read -r -p "Key ID (10 caracteres): " KEY_ID
fi

TEAM_ID="ES2766ARHJ"
BUNDLE_ID="com.maromeapps.RemoteSSH"
DIR="$HOME/.remotessh"

mkdir -p "$DIR"
cp "$P8" "$DIR/AuthKey_${KEY_ID}.p8"
chmod 600 "$DIR/AuthKey_${KEY_ID}.p8"

cat > "$DIR/apns.json" <<JSON
{
  "key_id": "${KEY_ID}",
  "team_id": "${TEAM_ID}",
  "key_path": "${DIR}/AuthKey_${KEY_ID}.p8",
  "bundle_id": "${BUNDLE_ID}"
}
JSON
chmod 600 "$DIR/apns.json"

echo "Configurado en $DIR"
echo
if [ -f "$DIR/apns-token.json" ]; then
    echo "Token del iPhone: ya presente. Prueba:"
    echo "  ~/.claude/hooks/apns-push --session Test --body 'hola desde el Mac'"
else
    echo "Falta el token del iPhone. Abre RemoteSSH en el telefono una vez"
    echo "(con un build que lleve el entitlement aps-environment) y acepta las"
    echo "notificaciones; la app lo escribe sola en $DIR/apns-token.json."
fi
