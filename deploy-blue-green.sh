#!/usr/bin/env bash
set -euo pipefail

APP_NAME="spring-boot-app"
APP_DIR="/home/ubuntu/opt/spring-boot-app"

# t3.micro tiene 1 GB de RAM: con dos instancias, 512m de heap cada una.
JAVA_OPTS="-Xms256m -Xmx512m"
SPRING_PROFILE="prod"

BLUE_PORT=8081
GREEN_PORT=8082

BLUE_JAR="app-blue.jar"
GREEN_JAR="app-green.jar"

NEW_JAR_PATH="${1:-}"

if [[ -z "$NEW_JAR_PATH" ]]; then
  echo "Usage: deploy-blue-green.sh <path-to-new-jar>"
  exit 1
fi

if [[ ! -f "$NEW_JAR_PATH" ]]; then
  echo "❌ No existe el archivo: $NEW_JAR_PATH"
  exit 1
fi

# Ruta absoluta: mas abajo se hace cd y una ruta relativa dejaria de servir.
NEW_JAR_PATH="$(readlink -f "$NEW_JAR_PATH")"

mkdir -p "$APP_DIR/versions" "$APP_DIR/logs"

cd "$APP_DIR"

echo "======================================"
echo "🚀 Blue-Green Deployment"
echo "======================================"
echo "➡️  New artifact: $NEW_JAR_PATH"

# --------------------------------------------------
# Detect current active environment
# --------------------------------------------------

if [[ -f "active-environment" ]]; then
    ACTIVE=$(cat active-environment)
else
    ACTIVE="blue"
fi

echo "🔵 Current active environment: $ACTIVE"

# --------------------------------------------------
# Determine target environment
# --------------------------------------------------

if [[ "$ACTIVE" == "blue" ]]; then
    TARGET="green"
    TARGET_PORT="$GREEN_PORT"
    TARGET_JAR="$GREEN_JAR"
else
    TARGET="blue"
    TARGET_PORT="$BLUE_PORT"
    TARGET_JAR="$BLUE_JAR"
fi

echo "🟢 Target environment: $TARGET"
echo "➡️  Target port: $TARGET_PORT"

# --------------------------------------------------
# Stop previous instance on target environment
# --------------------------------------------------

echo "🛑 Stopping previous $TARGET instance"

PID=$(pgrep -f "$TARGET_JAR" 2>/dev/null || true)

if [[ -n "$PID" ]]; then
    echo "PID=$PID"

    kill "$PID" || true

    for i in {1..15}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            echo "✅ Instance stopped"
            break
        fi

        sleep 1
    done

    if kill -0 "$PID" 2>/dev/null; then
        echo "⚠️ Force stopping instance"
        kill -9 "$PID"
    fi
else
    echo "ℹ️ No previous instance found"
fi

# --------------------------------------------------
# Backup previous JAR
# --------------------------------------------------

if [[ -f "$TARGET_JAR" ]]; then

    TIMESTAMP=$(date +%Y%m%d%H%M%S)

    mkdir -p versions

    cp "$TARGET_JAR" \
       "versions/${APP_NAME}-${TARGET}-${TIMESTAMP}.jar"

fi

# --------------------------------------------------
# Deploy new JAR
# --------------------------------------------------

echo "📦 Installing new artifact"

cp "$NEW_JAR_PATH" "$TARGET_JAR"

chmod 755 "$TARGET_JAR"

# --------------------------------------------------
# Start target instance
# --------------------------------------------------

echo "▶️ Starting $TARGET instance"

nohup java $JAVA_OPTS \
    -jar "$TARGET_JAR" \
    --spring.profiles.active="$SPRING_PROFILE" \
    --server.port="$TARGET_PORT" \
    > "logs/app-${TARGET}.log" 2>&1 &

TARGET_PID=$!

echo "PID=$TARGET_PID"

# --------------------------------------------------
# Health check
# --------------------------------------------------

echo "🔍 Waiting for $TARGET instance to become healthy"

HEALTHY=false

for i in {1..20}; do

    if curl -sf \
        "http://localhost:${TARGET_PORT}/health" \
        > /dev/null; then

        echo "✅ $TARGET instance is healthy"

        HEALTHY=true
        break
    fi

    sleep 3
done

# --------------------------------------------------
# Deployment failed
# --------------------------------------------------

if [[ "$HEALTHY" != "true" ]]; then

    echo "❌ $TARGET instance failed health check"

    echo "🛑 Stopping failed instance"

    kill "$TARGET_PID" 2>/dev/null || true

    exit 1
fi

# --------------------------------------------------
# Switch traffic
# --------------------------------------------------

echo "🔄 Switching traffic to $TARGET"

switch_traffic() {

    echo "⚠️ Traffic switch not implemented"
    echo "   Configure this function for your load balancer."

}

switch_traffic "$TARGET" "$TARGET_PORT"

# --------------------------------------------------
# Mark new environment as active
# --------------------------------------------------

echo "$TARGET" > active-environment

echo "======================================"
echo "✅ Blue-Green deployment completed"
echo "======================================"
echo "Active environment: $TARGET"
echo "Port: $TARGET_PORT"
