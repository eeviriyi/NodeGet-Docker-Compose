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

check_command() {
  name="$1"
  hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "未检测到 ${name}。"
    echo "$hint"
    exit 1
  fi
}

check_docker() {
  check_command git "请先安装 git，例如：apt install -y git"

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

check_domain_hint() {
  domain="$1"
  if command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahosts "$domain" | awk '{print $1}' | sort -u | tr '\n' ' ')"
    if [ -n "$resolved" ]; then
      echo "域名解析结果：${resolved}"
    else
      echo "警告：当前服务器暂时解析不到 ${domain}。"
      echo "如果 DNS 还没生效，Caddy 可能暂时无法签发 HTTPS 证书。"
    fi
  fi
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
  echo "  探针页：    https://${domain}/"
  echo "  控制台：    https://${domain}/board/"
  echo "  WebSocket： wss://${domain}/ws"
  echo
  echo "DNS 要求："
  echo "  请确认 ${domain} 已解析到本服务器，并且 80/443 端口已开放。"
  echo
  echo "SuperToken:"
  token="$(get_super_token)"
  if [ -n "$token" ]; then
    echo "  ${token}"
  else
    echo "  暂时还没出现在日志里。等 nodeget-server 启动完成后，可运行菜单 5 查看。"
  fi
  echo
  echo "脚本会自动创建探针页专用只读 Token 并写入探针页配置。"
  echo "如果探针页暂时不能读取数据，可稍后再次运行本脚本，选择菜单 2 重新生成。"
}

install_stack() {
  check_docker
  check_ports

  default_domain="${DOMAIN:-nodeget.example.com}"
  domain="$(prompt '请输入域名' "$default_domain")"
  site_name="$(prompt '请输入探针页名称' 'NodeGet Status')"
  email="$(prompt '请输入 ACME 邮箱' "admin@${domain}")"
  default_password="$(generate_password)"
  postgres_password="$(prompt '请输入 Postgres 密码' "$default_password")"

  check_domain_hint "$domain"

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

  token="$(get_super_token)"
  if [ -n "$token" ]; then
    create_probe_token "$token" || true
  fi

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

get_super_token() {
  if [ ! -d "$INSTALL_DIR" ]; then
    return 0
  fi
  cd "$INSTALL_DIR"
  compose_cmd logs nodeget-server 2>/dev/null | grep 'Super Token:' | tail -1 | sed 's/.*Super Token: //' || true
}

create_probe_token() {
  super_token="$1"
  if [ -z "$super_token" ]; then
    echo "未找到 SuperToken，无法自动创建探针页访问 Token。"
    return 1
  fi

  echo "正在自动创建探针页专用只读 Token..."

  created_token="$(
    docker run --rm -i \
      --network nodeget-stack_default \
      -e FATHER_TOKEN="$super_token" \
      node:22-alpine node <<'NODE'
const fatherToken = process.env.FATHER_TOKEN
const permissions = [
  { static_monitoring: { read: 'cpu' } },
  { static_monitoring: { read: 'system' } },
  { static_monitoring: { read: 'gpu' } },
  { dynamic_monitoring_summary: 'read' },
  { node_get: 'list_all_agent_uuid' },
  { kv: { read: 'metadata_*' } },
  { task: { read: 'ping' } },
  { task: { read: 'tcp_ping' } },
]

const request = {
  jsonrpc: '2.0',
  id: 'create-probe-token',
  method: 'token_create',
  params: {
    father_token: fatherToken,
    token_creation: {
      username: `nodeget-probe-page-${Date.now()}`,
      password: crypto.randomUUID(),
      version: 1,
      token_limit: [
        {
          scopes: [{ global: null }],
          permissions,
        },
      ],
    },
  },
}

const ws = new WebSocket('ws://nodeget-server:2211/')
const timeout = setTimeout(() => {
  console.error('连接 NodeGet Server 超时')
  process.exit(1)
}, 15000)

ws.addEventListener('open', () => ws.send(JSON.stringify(request)))
ws.addEventListener('message', event => {
  clearTimeout(timeout)
  const response = JSON.parse(String(event.data))
  if (response.error) {
    console.error(response.error.message || JSON.stringify(response.error))
    process.exit(1)
  }
  if (!response.result?.key || !response.result?.secret) {
    console.error('token_create 没有返回 key/secret')
    process.exit(1)
  }
  console.log(`${response.result.key}:${response.result.secret}`)
  ws.close()
})
ws.addEventListener('error', () => {
  clearTimeout(timeout)
  console.error('连接 NodeGet Server 失败')
  process.exit(1)
})
NODE
  )"

  if [ -z "$created_token" ]; then
    echo "探针页访问 Token 创建失败。"
    return 1
  fi

  set_env_value STATUS_TOKEN "$created_token"
  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
  compose_cmd restart nodeget-statusshow
  echo "探针页专用只读 Token 已自动创建并写入配置。"
}

configure_status_token() {
  if [ ! -f "$INSTALL_DIR/.env" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。请先运行安装。"
    return
  fi

  token="$(get_super_token)"
  if [ -z "$token" ]; then
    echo "未能从 nodeget-server 日志中读取 SuperToken，无法自动生成。"
    echo "请确认服务已启动，或用菜单 6 查看 nodeget-server 日志。"
    return
  fi

  create_probe_token "$token"
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

restart_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  ./scripts/render-status-config.sh
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

doctor_stack() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  ./scripts/doctor.sh
}

show_super_token() {
  if [ ! -d "$INSTALL_DIR" ]; then
    echo "未在 $INSTALL_DIR 找到已安装的部署。"
    return
  fi
  cd "$INSTALL_DIR"
  token="$(get_super_token)"
  if [ -n "$token" ]; then
    echo "Super Token: ${token}"
  fi
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
    echo "2. 自动生成/更新探针页访问 Token"
    echo "3. 更新部署"
    echo "4. 重新生成配置并重启"
    echo "5. 查看状态"
    echo "6. 部署自检"
    echo "7. 查看 SuperToken"
    echo "8. 查看日志"
    echo "9. 卸载"
    echo "0. 退出"
    echo
    printf '请选择: '
    read -r choice
    case "$choice" in
      1) install_stack; pause ;;
      2) configure_status_token; pause ;;
      3) update_stack; pause ;;
      4) restart_stack; pause ;;
      5) show_status; pause ;;
      6) doctor_stack; pause ;;
      7) show_super_token; pause ;;
      8) show_logs ;;
      9) uninstall_stack; pause ;;
      0) exit 0 ;;
      *) echo "无效选择" ;;
    esac
  done
}

menu
