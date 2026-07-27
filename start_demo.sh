#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

DB_NAME="yoma_triage"
DB_USER="postgres"
DB_PASS="postgres"
DB_PORT="${DB_PORT:-5433}"
API_PORT="${API_PORT:-8000}"
DB_CONTAINER="yoma-db"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[yoma]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[skip]${NC} $*"; }
fail() { echo -e "${RED}[fail]${NC} $*"; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Commands:
  up       Start database + backend (default)
  demo     Run the end-to-end demo flow
  stop     Stop all services
  status   Check what's running
  reset    Wipe database and re-seed

Examples:
  $0 up           # start everything
  $0 demo         # run the judge demo
  $0 stop         # tear down
  $0 reset        # fresh database
EOF
    exit 0
}

# ─── Database ─────────────────────────────────────────────────────────────────

db_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"
}

db_running() {
    docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"
}

start_db() {
    if db_running; then
        ok "PostgreSQL already running on port $DB_PORT"
        return
    fi

    if db_exists; then
        log "Starting existing container $DB_CONTAINER..."
        docker start "$DB_CONTAINER" >/dev/null 2>&1
        ok "PostgreSQL started on port $DB_PORT"
        return
    fi

    log "Creating PostgreSQL container..."
    docker run -d \
        --name "$DB_CONTAINER" \
        -e POSTGRES_PASSWORD="$DB_PASS" \
        -e POSTGRES_DB="$DB_NAME" \
        -p "$DB_PORT:5432" \
        postgres:16 >/dev/null 2>&1

    log "Waiting for PostgreSQL to accept connections..."
    for i in $(seq 1 30); do
        if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            ok "PostgreSQL ready on port $DB_PORT"
            return
        fi
        sleep 1
    done
    fail "PostgreSQL failed to start within 30 seconds"
}

# ─── Backend ──────────────────────────────────────────────────────────────────

API_RUNNING=false

check_api() {
    curl -s "http://127.0.0.1:$API_PORT/" >/dev/null 2>&1 && API_RUNNING=true || API_RUNNING=false
}

start_api() {
    check_api
    if $API_RUNNING; then
        ok "Backend API already running on port $API_PORT"
        return
    fi

    if [ ! -d "venv" ]; then
        log "Creating virtual environment..."
        python3 -m venv venv
        ./venv/bin/pip install -r requirements.txt -q
    fi

    log "Seeding demo data..."
    ./venv/bin/python -m src.db.seed 2>/dev/null || true

    log "Starting FastAPI backend on port $API_PORT..."
    ./venv/bin/python -c "import uvicorn; uvicorn.run('main:app', host='0.0.0.0', port=$API_PORT, reload=False)" &
    API_PID=$!
    echo "$API_PID" > /tmp/yoma_api.pid

    for i in $(seq 1 45); do
        if curl -sf "http://127.0.0.1:$API_PORT/" >/dev/null 2>&1; then
            ok "Backend API ready on port $API_PORT"
            return
        fi
        sleep 1
    done
    fail "Backend API failed to start within 45 seconds"
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_up() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Yoma Triage — Starting Demo        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    start_db
    start_api

    echo ""
    echo -e "${GREEN}All services running.${NC}"
    echo ""
    echo "  API:     http://127.0.0.1:$API_PORT"
    echo "  DB:      localhost:$DB_PORT"
    echo "  Swagger: http://127.0.0.1:$API_PORT/docs"
    echo ""
    echo "Run '$0 demo' to execute the end-to-end flow."
    echo ""
}

cmd_demo() {
    check_api
    if ! $API_RUNNING; then
        log "Backend not running — starting services first..."
        cmd_up
    fi

    echo ""
    log "Running demo_flow.py..."
    echo ""
    ./venv/bin/python scripts/demo_flow.py
    echo ""
    ok "Demo complete"
}

cmd_stop() {
    if [ -f /tmp/yoma_api.pid ]; then
        PID=$(cat /tmp/yoma_api.pid)
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null
            ok "Stopped backend API (pid $PID)"
        fi
        rm -f /tmp/yoma_api.pid
    fi

    # Also kill any uvicorn on the API port
    pkill -f "uvicorn.*main:app" 2>/dev/null && ok "Killed orphaned uvicorn" || true

    if db_running; then
        docker stop "$DB_CONTAINER" >/dev/null 2>&1
        ok "Stopped PostgreSQL container"
    fi
}

cmd_status() {
    echo ""
    echo -e "${CYAN}Yoma Triage Service Status${NC}"
    echo ""

    # Database
    if db_running; then
        ok "PostgreSQL: running (port $DB_PORT)"
    elif db_exists; then
        warn "PostgreSQL: stopped (container exists)"
    else
        warn "PostgreSQL: not created"
    fi

    # API
    check_api
    if $API_RUNNING; then
        ok "Backend API: running (port $API_PORT)"
    else
        warn "Backend API: not running"
    fi

    echo ""
}

cmd_reset() {
    log "Stopping services..."
    cmd_stop

    log "Removing database container..."
    docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
    ok "Database container removed"

    cmd_up
}

# ─── Main ─────────────────────────────────────────────────────────────────────

trap 'echo ""' EXIT

case "${1:-up}" in
    up)     cmd_up ;;
    demo)   cmd_demo ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    reset)  cmd_reset ;;
    -h|--help) usage ;;
    *)      fail "Unknown command: $1 (try '$0 --help')" ;;
esac
