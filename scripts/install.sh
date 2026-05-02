#!/usr/bin/env sh
set -eu

REPO_URL="${REPO_URL:-https://github.com/eeviriyi/NodeGet-Docker-Compose.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/nodeget-compose}"

need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  else
    echo "sudo"
  fi
}

run_as_root() {
  sudo_cmd="$(need_sudo)"
  if [ -n "$sudo_cmd" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

pause() {
  printf '\nPress Enter to continue...'
  # shellcheck disable=SC2034
  read -r _
}

prompt() {
  label="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default"
  else
    printf '%s: ' "$label"
  fi
  read -r value
  if [ -z "$value" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    date +%s | sha256sum | awk '{print $1}'
  fi
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "Docker Compose is not installed." >&2
    exit 1
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed."
    echo "Install Docker first: https://docs.docker.com/engine/install/"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed but not usable by this user."
    echo "Try running this script with sudo, or add your user to the docker group."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose is not installed."
    echo "Install the Docker Compose plugin first."
    exit 1
  fi
}

check_ports() {
  for port in 80 443; do
    if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" | grep -q ":$port"; then
      echo "Warning: port $port appears to be in use. Caddy needs ports 80 and 443."
    fi
  done
}

ensure_repo() {
  parent="$(dirname "$INSTALL_DIR")"
  run_as_root mkdir -p "$parent"

  if [ -d "$INSTALL_DIR/.git" ]; then
    run_as_root git -C "$INSTALL_DIR" pull --ff-only
  elif [ -e "$INSTALL_DIR" ]; then
    echo "$INSTALL_DIR exists but is not a git repository."
    exit 1
  else
    run_as_root git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  run_as_root chown -R "$(id -u):$(id -g)" "$INSTALL_DIR" 2>/dev/null || true
}

write_env() {
  domain="$1"
  site_name="$2"
  email="$3"
  postgres_password="$4"

  cat >"$INSTALL_DIR/.env" <<EOF
DOMAIN=${domain}
ACME_EMAIL=${email}

NODEGET_IMAGE=genshinmc/nodeget:latest
NODEGET_PORT=2211
NODEGET_LOG_FILTER=info
NODEGET_SERVER_UUID=

POSTGRES_DB=nodeget
POSTGRES_USER=nodeget
POSTGRES_PASSWORD=${postgres_password}

BOARD_REPO=https://github.com/eeviriyi/NodeGet-board.git
BOARD_REF=main
STATUSSHOW_REPO=https://github.com/eeviriyi/NodeGet-StatusShow.git
STATUSSHOW_REF=main

STATUS_SITE_NAME="${site_name}"
STATUS_SITE_LOGO=
STATUS_SITE_FOOTER="Powered by NodeGet"
STATUS_BACKEND_NAME=main
STATUS_BACKEND_URL=wss://${domain}/ws
STATUS_TOKEN=
EOF
}

show_next_steps() {
  domain="$1"
  echo
  echo "NodeGet Docker Compose is starting."
  echo
  echo "URLs:"
  echo "  StatusShow: https://${domain}/"
  echo "  Board:      https://${domain}/board/"
  echo "  WebSocket:  wss://${domain}/ws"
  echo
  echo "DNS requirement:"
  echo "  Make sure ${domain} points to this server and ports 80/443 are open."
  echo
  echo "SuperToken:"
  token="$(cd "$INSTALL_DIR" && compose_cmd logs nodeget-server 2>/dev/null | grep 'Super Token:' | tail -1 | sed 's/.*Super Token: //')"
  if [ -n "$token" ]; then
    echo "  ${token}"
  else
    echo "  Not visible yet. Run menu item 5 after nodeget-server finishes starting."
  fi
  echo
  echo "After logging in to /board/, create a StatusShow public/read-only token."
  echo "Then run this installer again and choose menu item 2 to paste it."
}

install_stack() {
  check_docker
  check_ports

  default_domain="${DOMAIN:-nodeget.example.com}"
  domain="$(prompt 'Domain' "$default_domain")"
  site_name="$(prompt 'Status site name' 'NodeGet Status')"
  email="$(prompt 'ACME email' "admin@${domain}")"
  default_password="$(generate_password)"
  postgres_password="$(prompt 'Postgres password' "$default_password")"

  ensure_repo
  write_env "$domain" "$site_name" "$email" "$postgres_password"

  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_cmd up -d --build

  echo "Waiting for nodeget-server logs..."
  i=0
  while [ "$i" -lt 30 ]; do
    if compose_cmd logs nodeget-server 2>/dev/null | grep -q 'Super Token:'; then
      break
    fi
    i=$((i + 1))
    sleep 2
  done

  show_next_steps "$domain"
}

set_env_value() {
  key="$1"
  value="$2"
  file="$INSTALL_DIR/.env"
  tmp="${file}.tmp"
  if grep -q "^${key}=" "$file"; then
    awk -v key="$key" -v value="$value" 'BEGIN{done=0} $0 ~ "^" key "=" {print key "=" value; done=1; next} {print} END{if(!done) print key "=" value}' "$file" >"$tmp"
  else
    cp "$file" "$tmp"
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

configure_status_token() {
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "No installation found at $INSTALL_DIR. Run install first."
    return
  fi

  printf 'Paste StatusShow public/read-only token: '
  read -r token
  if [ -z "$token" ]; then
    echo "Token is empty. Nothing changed."
    return
  fi

  set_env_value STATUS_TOKEN "$token"
  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_cmd restart nodeget-statusshow
  echo "StatusShow token updated."
}

update_stack() {
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "No installation found at $INSTALL_DIR. Run install first."
    return
  fi
  cd "$INSTALL_DIR"
  git pull --ff-only
  ./scripts/render-status-config.sh
  compose_cmd pull
  compose_cmd up -d --build
}

show_status() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "No installation found at $INSTALL_DIR."
    return
  fi
  cd "$INSTALL_DIR"
  compose_cmd ps
}

show_super_token() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "No installation found at $INSTALL_DIR."
    return
  fi
  cd "$INSTALL_DIR"
  compose_cmd logs nodeget-server | grep 'Super Token:' | tail -1 || true
}

show_logs() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "No installation found at $INSTALL_DIR."
    return
  fi
  echo "1. nodeget-server"
  echo "2. caddy"
  echo "3. postgres"
  echo "4. nodeget-statusshow"
  echo "5. nodeget-board"
  printf 'Choose service: '
  read -r choice
  case "$choice" in
    1) service=nodeget-server ;;
    2) service=caddy ;;
    3) service=postgres ;;
    4) service=nodeget-statusshow ;;
    5) service=nodeget-board ;;
    *) echo "Invalid choice"; return ;;
  esac
  cd "$INSTALL_DIR"
  compose_cmd logs -f "$service"
}

uninstall_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "No installation found at $INSTALL_DIR."
    return
  fi
  echo "This will stop and remove NodeGet containers."
  printf 'Also delete data volumes? Type DELETE to delete data, or press Enter to keep data: '
  read -r confirm
  cd "$INSTALL_DIR"
  if [ "$confirm" = "DELETE" ]; then
    compose_cmd down -v
    echo "Containers and data volumes removed."
  else
    compose_cmd down
    echo "Containers removed. Data volumes kept."
  fi
}

menu() {
  while true; do
    echo
    echo "NodeGet Docker Compose"
    echo
    echo "1. Install / first deploy"
    echo "2. Paste StatusShow token and update"
    echo "3. Update stack"
    echo "4. Show status"
    echo "5. Show SuperToken"
    echo "6. Show logs"
    echo "7. Uninstall"
    echo "0. Exit"
    echo
    printf 'Choose: '
    read -r choice
    case "$choice" in
      1) install_stack; pause ;;
      2) configure_status_token; pause ;;
      3) update_stack; pause ;;
      4) show_status; pause ;;
      5) show_super_token; pause ;;
      6) show_logs ;;
      7) uninstall_stack; pause ;;
      0) exit 0 ;;
      *) echo "Invalid choice" ;;
    esac
  done
}

menu

