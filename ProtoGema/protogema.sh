#!/usr/bin/env bash
# =====================================================================
#  ProtoGema | lanzador para Linux y macOS
#  Uso:  ./protogema.sh            enciende y abre el navegador
#        ./protogema.sh apagar     apaga (la agenda queda guardada)
#        ./protogema.sh estado     muestra los servicios
# =====================================================================
set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RAIZ" || exit 1
mkdir -p registros
ACCION="${1:-encender}"

morado=$'\e[35m'; verde=$'\e[32m'; gris=$'\e[90m'; rojo=$'\e[31m'; fin=$'\e[0m'
faceta=0
paso() {
  faceta=$((faceta + 1))
  local marca="" i
  for i in 1 2 3 4 5; do if [ "$i" -le "$faceta" ]; then marca="$marca◆"; else marca="$marca◇"; fi; done
  printf '   %s%s%s  %s\n' "$morado" "$marca" "$fin" "$1"
}
bien()  { printf '             %sok%s  %s\n' "$verde" "$fin" "$1"; }
nota()  { printf '                 %s%s%s\n' "$gris" "$1" "$fin"; }
fallo() {
  printf '\n   %sNo pude seguir:%s %s\n   %sLos detalles quedaron en la carpeta registros/%s\n\n' "$rojo" "$fin" "$1" "$gris" "$fin"
  command -v notify-send >/dev/null && notify-send -a ProtoGema "ProtoGema" "$1" 2>/dev/null
  exit 1
}

dc() {
  if docker compose version >/dev/null 2>&1; then docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then docker-compose "$@"
  else return 127; fi
}

# Acceso directo en el escritorio (solo la primera vez)
acceso_directo() {
  if [ "$(uname)" = "Darwin" ]; then
    local destino="$HOME/Desktop/ProtoGema.command"
    [ -e "$destino" ] && return 0
    printf '#!/bin/bash\ncd "%s" && ./protogema.sh\n' "$RAIZ" > "$destino" && chmod +x "$destino" \
      && nota "Creé el acceso directo \"ProtoGema\" en tu escritorio"
    return 0
  fi
  local escritorio
  escritorio="$(xdg-user-dir DESKTOP 2>/dev/null)"
  [ -n "$escritorio" ] && [ "$escritorio" != "$HOME" ] || escritorio="$HOME/Desktop"
  [ -d "$escritorio" ] || { [ -d "$HOME/Escritorio" ] && escritorio="$HOME/Escritorio"; }
  [ -d "$escritorio" ] || return 0
  local destino="$escritorio/protogema.desktop"
  [ -e "$destino" ] && return 0
  local entrada="[Desktop Entry]
Type=Application
Name=ProtoGema
Comment=Asistente personal con agenda inteligente
Exec=bash \"$RAIZ/protogema.sh\"
Path=$RAIZ
Icon=$RAIZ/lanzador/protogema.png
Terminal=true
Categories=Office;Utility;"
  printf '%s\n' "$entrada" > "$destino" && chmod +x "$destino"
  # GNOME pide marcar el acceso como "de confianza" para poder abrirlo con doble clic
  command -v gio >/dev/null && gio set "$destino" metadata::trusted true 2>/dev/null
  # También aparece en el menú de aplicaciones
  mkdir -p "$HOME/.local/share/applications" && printf '%s\n' "$entrada" > "$HOME/.local/share/applications/protogema.desktop"
  nota "Creé el acceso directo \"ProtoGema\" en tu escritorio y en el menú de aplicaciones"
}

secreto() { od -An -tx1 -N24 /dev/urandom | tr -d ' \n'; }

printf '\n%s      /\\  /\\  /\\      P R O T O G E M A%s\n' "$morado" "$fin"
printf '%s     /__\\/__\\/__\\     %sasistente personal con agenda inteligente%s\n' "$morado" "$gris" "$fin"
printf '%s     \\    \\/    /%s\n%s        \\ || /%s\n\n' "$morado" "$fin" "$morado" "$fin"

case "$ACCION" in
  apagar)
    paso "Apagando ProtoGema (tu agenda queda guardada)..."
    dc down >registros/apagar.log 2>&1 && bien "ProtoGema se apagó"
    exit 0 ;;
  estado)
    dc ps; exit 0 ;;
esac

paso "Revisando Docker..."
command -v docker >/dev/null 2>&1 || fallo "Docker no está instalado: https://docs.docker.com/get-docker/"
if ! docker info >/dev/null 2>&1; then
  nota "Docker no responde, intento encenderlo..."
  if [ "$(uname)" = "Darwin" ]; then open -a Docker 2>/dev/null
  else pkexec systemctl start docker >/dev/null 2>&1 || sudo -n systemctl start docker >/dev/null 2>&1; fi
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
fi
docker info >/dev/null 2>&1 || fallo "Docker no responde. Si dice 'permission denied': sudo usermod -aG docker \$USER y vuelve a iniciar sesión."
dc version >/dev/null 2>&1 || fallo "Falta Docker Compose."
bien "Docker responde"

paso "Preparando la configuración..."
if [ ! -f .env ]; then
  ZONA="$(cat /etc/timezone 2>/dev/null || readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')"
  [ -n "$ZONA" ] || ZONA="America/Caracas"
  umask 077
  cat > .env <<EOF
# ProtoGema | configuración local (se creó sola, no la compartas)
CLAVE_ALMACEN=$(secreto)
CLAVE_CEREBRO=$(secreto)
ZONA_HORARIA=$ZONA
PUERTO_PROTOGEMA=4646
PUERTO_N8N=5699
EOF
  bien "Configuración creada por primera vez (zona: $ZONA)"
else
  bien "Configuración encontrada"
fi
PUERTO="$(grep -E '^PUERTO_PROTOGEMA=' .env | cut -d= -f2)"; PUERTO="${PUERTO:-4646}"
URL="http://localhost:$PUERTO"

paso "Encendiendo los servicios (la primera vez descarga ~800 MB)..."
dc up -d --build >registros/encender.log 2>&1 || fallo "Docker Compose no pudo levantar los servicios (registros/encender.log)."
bien "Servicios levantados"

paso "Esperando a que el cerebro (n8n) despierte..."
listo=0
for _ in $(seq 1 180); do
  if curl -fsS -m 3 "$URL/api/latido" 2>/dev/null | grep -q '"vivo"'; then listo=1; break; fi
  sleep 2
done
if [ "$listo" -ne 1 ]; then
  dc logs --tail 80 >registros/servicios.log 2>&1
  fallo "El cerebro no respondió a tiempo (registros/servicios.log)."
fi
bien "ProtoGema está despierta"

paso "Abriendo ProtoGema..."
acceso_directo
if command -v xdg-open >/dev/null; then xdg-open "$URL" >/dev/null 2>&1 &
elif command -v open >/dev/null; then open "$URL"; fi
command -v notify-send >/dev/null && notify-send -a ProtoGema -i "$RAIZ/portal/publico/gema.svg" "ProtoGema" "Lista en $URL" 2>/dev/null
bien "Listo: $URL"
echo
