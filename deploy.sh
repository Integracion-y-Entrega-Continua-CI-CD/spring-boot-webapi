#!/usr/bin/env bash
set -euo pipefail

# --- Configuracion ---
# Todos los valores se pueden sobreescribir por variable de entorno:
#   APP_DIR=/opt/webapi PORT=8081 ./deploy.sh webapi-1.0.1.jar

APP_NAME="${APP_NAME:-spring-boot-app}"
APP_DIR="${APP_DIR:-/home/ubuntu/opt/spring-boot-app}"
JAR_NAME="${JAR_NAME:-app.jar}"
# t3.micro tiene 1 GB de RAM: un heap de 1 GB deja sin memoria al sistema.
JAVA_OPTS="${JAVA_OPTS:--Xms256m -Xmx512m}"
SPRING_PROFILE="${SPRING_PROFILE:-prod}"
PORT="${PORT:-8080}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-3}"
STOP_TIMEOUT="${STOP_TIMEOUT:-15}"
KEEP_VERSIONS="${KEEP_VERSIONS:-5}"

JAR_PATH="$APP_DIR/$JAR_NAME"
PID_FILE="$APP_DIR/$APP_NAME.pid"
LOG_FILE="$APP_DIR/logs/app.log"
PREVIOUS_JAR=""

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

# --- Validar el artefacto recibido ---

NEW_JAR_PATH="${1:-}"

if [[ -z "$NEW_JAR_PATH" ]]; then
  echo "Uso: $0 <ruta-al-nuevo-jar>"
  exit 1
fi

command -v java >/dev/null 2>&1 || fail "java no esta instalado en este servidor."
command -v curl >/dev/null 2>&1 || fail "curl no esta instalado y hace falta para el health check."

[[ -f "$NEW_JAR_PATH" ]] || fail "No existe el archivo: $NEW_JAR_PATH"
[[ -s "$NEW_JAR_PATH" ]] || fail "El archivo esta vacio: $NEW_JAR_PATH"

# Todo JAR es un ZIP y empieza con la firma "PK": descarta descargas truncadas.
[[ "$(head -c 2 "$NEW_JAR_PATH")" == "PK" ]] || fail "El archivo no parece un JAR valido: $NEW_JAR_PATH"

NEW_JAR_PATH="$(readlink -f "$NEW_JAR_PATH")"

mkdir -p "$APP_DIR/versions" "$APP_DIR/logs"
cd "$APP_DIR"

# --- Funciones de arranque y parada ---

current_pid() {
  local pid=""

  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return 0
    fi
  fi

  pgrep -f -- "-jar $JAR_PATH" 2>/dev/null | head -n 1 || true
}

stop_app() {
  local pid
  pid="$(current_pid)"

  if [[ -z "$pid" ]]; then
    log "No hay ninguna instancia en ejecucion."
    rm -f "$PID_FILE"
    return 0
  fi

  log "Deteniendo la instancia actual (PID=$pid)."
  kill "$pid" 2>/dev/null || true

  local i
  for ((i = 0; i < STOP_TIMEOUT; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      log "Instancia detenida."
      rm -f "$PID_FILE"
      return 0
    fi
    sleep 1
  done

  log "La aplicacion no cerro en ${STOP_TIMEOUT}s, forzando kill -9."
  kill -9 "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
}

start_app() {
  log "Iniciando $APP_NAME en el puerto $PORT (perfil $SPRING_PROFILE)."

  # APP_INSTANCE etiqueta la instancia y la devuelve el endpoint /instance.
  # shellcheck disable=SC2086
  APP_INSTANCE="$APP_NAME" nohup java $JAVA_OPTS \
    -jar "$JAR_PATH" \
    --spring.profiles.active="$SPRING_PROFILE" \
    --server.port="$PORT" \
    >> "$LOG_FILE" 2>&1 &

  echo $! > "$PID_FILE"
  log "Proceso lanzado con PID=$(cat "$PID_FILE"). Log: $LOG_FILE"
}

# --- Health check ---

wait_healthy() {
  local url="http://localhost:${PORT}${HEALTH_PATH}"
  local pid i

  log "Verificando $url"

  for ((i = 1; i <= HEALTH_RETRIES; i++)); do
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"

    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      log "El proceso java (PID=$pid) termino de forma inesperada."
      return 1
    fi

    if curl -sf --max-time 2 "$url" >/dev/null 2>&1; then
      log "La aplicacion responde correctamente (intento $i de $HEALTH_RETRIES)."
      return 0
    fi

    sleep "$HEALTH_INTERVAL"
  done

  log "Se agotaron los $HEALTH_RETRIES intentos sin respuesta de $url"
  return 1
}

# --- Rollback: restaura y levanta la version anterior ---

rollback() {
  log "--------------------------------------"
  log "ROLLBACK: volviendo a la version anterior"
  log "--------------------------------------"

  stop_app

  if [[ -z "$PREVIOUS_JAR" || ! -f "$PREVIOUS_JAR" ]]; then
    log "No hay una version anterior que restaurar. El servicio queda detenido."
    return 1
  fi

  log "Restaurando $PREVIOUS_JAR"
  cp "$PREVIOUS_JAR" "$JAR_PATH"
  chmod 755 "$JAR_PATH"

  start_app

  if wait_healthy; then
    log "Rollback completado: el servicio volvio a la version anterior."
    return 0
  fi

  log "El rollback tampoco logro levantar el servicio. Revisar $LOG_FILE"
  return 1
}

# --- Conservar solo los ultimos KEEP_VERSIONS respaldos ---

prune_versions() {
  [[ "$KEEP_VERSIONS" -gt 0 ]] || return 0

  local antiguos
  antiguos="$(ls -1 "$APP_DIR/versions/${APP_NAME}-"*.jar 2>/dev/null | head -n "-${KEEP_VERSIONS}" || true)"

  [[ -n "$antiguos" ]] || return 0

  while IFS= read -r archivo; do
    [[ -n "$archivo" ]] || continue
    log "Descartando respaldo antiguo: $(basename "$archivo")"
    rm -f "$archivo"
  done <<< "$antiguos"
}

# --- Despliegue ---

log "======================================"
log "Despliegue de $APP_NAME"
log "======================================"
log "Artefacto nuevo : $NEW_JAR_PATH"
log "Destino         : $JAR_PATH"
log "Puerto          : $PORT"

# --- Respaldar la version en uso ---

if [[ -f "$JAR_PATH" ]]; then
  PREVIOUS_JAR="$APP_DIR/versions/${APP_NAME}-$(date +%Y%m%d%H%M%S).jar"
  cp "$JAR_PATH" "$PREVIOUS_JAR"
  log "Version en uso respaldada en $PREVIOUS_JAR"
else
  log "No hay una version previa instalada: este es el primer despliegue."
fi

# --- Detener e instalar la nueva version ---

stop_app

log "Instalando el nuevo artefacto."
cp "$NEW_JAR_PATH" "$JAR_PATH"
chmod 755 "$JAR_PATH"

printf '\n===== Despliegue %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"

start_app

# --- Verificar, y si falla volver atras ---

if wait_healthy; then
  prune_versions
  log "======================================"
  log "Despliegue completado correctamente."
  log "======================================"
  exit 0
fi

log "La version nueva no paso el health check."

if rollback; then
  exit 1
fi

exit 2
