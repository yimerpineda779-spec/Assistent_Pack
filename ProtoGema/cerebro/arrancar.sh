#!/bin/sh
# =====================================================================
#  ProtoGema | arranque del cerebro (n8n)
#  1. Registra la conexión con el almacén (PostgreSQL) a partir del .env
#  2. Vuelve a cargar los 3 flujos de cerebro/flujos y los publica
#  3. Enciende n8n normalmente
# =====================================================================
set -e
TRABAJO=/tmp/protogema
FLUJOS="pgemaConversa001 pgemaPortal00001 pgemaVigia000001"
mkdir -p "$TRABAJO/flujos"
umask 077

echo "[ProtoGema] Registrando la conexión con el almacén..."
node -e '
const fs = require("fs");
const cred = [{
  id: "pgemaAlmacen0001", name: "Almacén ProtoGema", type: "postgres",
  data: { host: "almacen", port: 5432, database: "protogema", user: "protogema",
          password: process.env.CLAVE_ALMACEN, ssl: "disable",
          allowUnauthorizedCerts: false, maxConnections: 10 }
}];
fs.writeFileSync(process.argv[1], JSON.stringify(cred));
' "$TRABAJO/conexion.json"
n8n import:credentials --input="$TRABAJO/conexion.json"

echo "[ProtoGema] Cargando flujos..."
# Copia limpia (por si los archivos vienen con saltos de línea de Windows)
for f in /protogema/flujos/*.json; do tr -d '\r' < "$f" > "$TRABAJO/flujos/$(basename "$f")"; done
for id in $FLUJOS; do n8n unpublish:workflow --id="$id" >/dev/null 2>&1 || true; done
n8n import:workflow --separate --input="$TRABAJO/flujos"
for id in $FLUJOS; do n8n publish:workflow --id="$id"; done

# Las claves en texto plano no se quedan en el disco
rm -rf "$TRABAJO"

echo "[ProtoGema] Cerebro listo. Encendiendo n8n..."
if [ -x /docker-entrypoint.sh ]; then
  if command -v tini >/dev/null 2>&1; then exec tini -- /docker-entrypoint.sh; fi
  exec /docker-entrypoint.sh
fi
exec n8n start
