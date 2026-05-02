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
  printf '\n按 Enter 继续...'
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
    echo "未检测到 Docker Compose。" >&2
    exit 1
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "未检测到 Docker。"
    echo "请先安装 Docker：https://docs.docker.com/engine/install/"
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker 已安装，但当前用户无法使用。"
    echo "请尝试用 sudo 运行本脚本，或把当前用户加入 docker 用户组。"
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "未检测到 Docker Compose。"
    echo "请先安装 Docker Compose 插件。"
    exit 1
  fi
}

check_ports() {
  for port in 80 443; do
    if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" | grep -q ":$port"; then
      echo "警告：端口 $port 似乎已被占用。Caddy 默认需要 80 和 443。"
    fi
  done
}

ensure_repo() {
  parent="$(dirname "$INSTALL_DIR")"
  run_as_root mkdir -p "$parent"

  if [ -d "$INSTALL_DIR/.git" ]; then
    run_as_root git -C "$INSTALL_DIR" pull --ff-only
  elif [ -e "$INSTALL_DIR" ]; then
    echo "$INSTALL_DIR 已存在，但不是 Git 仓库。"
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
  echo "NodeGet Docker Compose 已开始启动。"
  echo
  echo "访问地址："
  echo "  状态页：    https://${domain}/"
  echo "  控制台：    https://${domain}/board/"
  echo "  WebSocket： wss://${domain}/ws"
  echo
  echo "DNS 要求："
  echo "  请确认 ${domain} 已解析到本服务器，并且 80/443 端口已开放。"
  echo
  echo "SuperToken:"
  token="$(cd "$INSTALL_DIR" && compose_cmd logs nodeget-server 2>/dev/null | grep 'Super Token:' | tail -1 | sed 's/.*Super Token: //')"
  if [ -n "$token" ]; then
    echo "  ${token}"
  else
    echo "  暂时还没出现在日志里。等 nodeget-server 启动完成后，可运行菜单 5 查看。"
  fi
  echo
  echo "登录 /board/ 后，请手动创建一个 StatusShow 可用的公开只读 Token。"
  echo "然后再次运行本脚本，选择菜单 2，粘贴这个 Token 并更新状态页。"
}

install_stack() {
  check_docker
  check_ports

  default_domain="${DOMAIN:-nodeget.example.com}"
  domain="$(prompt '请输入域名' "$default_domain")"
  site_name="$(prompt '请输入状态页名称' 'NodeGet Status')"
  email="$(prompt '请输入 ACME 邮箱' "admin@${domain}")"
  default_password="$(generate_password)"
  postgres_password="$(prompt '请输入 Postgres 密码' "$default_password")"

  ensure_repo
  write_env "$domain" "$site_name" "$email" "$postgres_password"

  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_cmd up -d --build

  echo "正在等待 nodeget-server 输出日志..."
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
    echo "未在 $INSTALL_DIR 找到已安装的部署。请先运行安装。"
    return
  fi

  printf '请粘贴 StatusShow 可用的公开只读 Token: '
  read -r token
  if [ -z "$token" ]; then
    echo "Token 为空，未做任何修改。"
    return
  fi

  set_env_value STATUS_TOKEN "$token"
  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_cmd restart nodeget-statusshow
  echo "StatusShow Token 已更新。"
}

update_stack() {
  if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。请先运行安装。"
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
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  compose_cmd ps
}

show_super_token() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  compose_cmd logs nodeget-server | grep 'Super Token:' | tail -1 || true
}

show_logs() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  echo "1. nodeget-server"
  echo "2. caddy"
  echo "3. postgres"
  echo "4. nodeget-statusshow"
  echo "5. nodeget-board"
  printf '请选择服务: '
  read -r choice
  case "$choice" in
    1) service=nodeget-server ;;
    2) service=caddy ;;
    3) service=postgres ;;
    4) service=nodeget-statusshow ;;
    5) service=nodeget-board ;;
    *) echo "无效选择"; return ;;
  esac
  cd "$INSTALL_DIR"
  compose_cmd logs -f "$service"
}

uninstall_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  echo "此操作会停止并删除 NodeGet 容器。"
  printf '是否同时删除数据卷？输入 DELETE 删除数据，直接按 Enter 则保留数据: '
  read -r confirm
  cd "$INSTALL_DIR"
  if [ "$confirm" = "DELETE" ]; then
    compose_cmd down -v
    echo "容器和数据卷已删除。"
  else
    compose_cmd down
    echo "容器已删除，数据卷已保留。"
  fi
}

menu() {
  while true; do
    echo
    echo "NodeGet Docker Compose 管理菜单"
    echo
    echo "1. 安装 / 首次部署"
    echo "2. 粘贴 StatusShow Token 并更新"
    echo "3. 更新部署"
    echo "4. 查看状态"
    echo "5. 查看 SuperToken"
    echo "6. 查看日志"
    echo "7. 卸载"
    echo "0. 退出"
    echo
    printf '请选择: '
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
      *) echo "无效选择" ;;
    esac
  done
}

menu
