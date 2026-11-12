#!/bin/sh
# Arranque de Cortana: prepara todo y luego inicia n8n normalmente.
set -e
TMP=/tmp/cortana

echo "[Cortana] Instalando nodo de Tavily..."
mkdir -p /home/node/.n8n/nodes
cp -r /opt/cortana-nodos/. /home/node/.n8n/nodes/

echo "[Cortana] Preparando flujos y claves..."
node /cortana/preparar.js "$TMP"

n8n import:credentials --input="$TMP/credenciales.json"

# Si los flujos ya existían y estaban activos, se desactivan directo en la base de datos
# (la primera vez no existen y este paso simplemente no hace nada)
for ID in cortanaPrincipal cortanaRecordat1; do
  n8n unpublish:workflow --id=$ID || true
done
n8n import:workflow --separate --input="$TMP/flujos"
for ID in cortanaPrincipal cortanaRecordat1; do
  n8n publish:workflow --id=$ID
done

# Las claves en texto plano no se quedan en el disco
rm -rf "$TMP"

echo "[Cortana] Todo listo. Iniciando n8n..."
if [ -x /docker-entrypoint.sh ]; then
  if command -v tini >/dev/null 2>&1; then exec tini -- /docker-entrypoint.sh; fi
  exec /docker-entrypoint.sh
fi
exec n8n start
