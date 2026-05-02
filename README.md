# NodeGet Docker Compose

NodeGet 单域名 Docker Compose 部署方案。

路由：

- `/` 提供 NodeGet-StatusShow 状态页
- `/board/` 提供 NodeGet-board 控制台
- `/ws` 反代 NodeGet Server WebSocket JSON-RPC

本方案使用 Caddy 自动 HTTPS、Postgres 存储，以及官方 NodeGet Server 镜像。

## 环境要求

- 已安装 Docker 和 Docker Compose
- 一个已经解析到本服务器的域名
- 服务器开放入站 `80` 和 `443` 端口

## 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eeviriyi/NodeGet-Docker-Compose/main/scripts/install.sh)
```

选择 `1. 安装 / 首次部署`，然后按提示输入：

- 域名
- 状态页名称
- ACME 邮箱
- Postgres 密码，也可以直接使用脚本生成的默认值

安装脚本会把本仓库克隆到 `/opt/nodeget-compose`，写入 `.env`，启动 Docker Compose，并在服务日志出现 SuperToken 后直接输出。

启动完成后：

1. 打开 `https://你的域名/board/`。
2. 使用安装脚本输出的 SuperToken 登录。
3. 在控制台里添加后端地址 `wss://你的域名/ws`。
4. 手动创建一个 StatusShow 可用的公开只读 Token。
5. 再次运行安装脚本，选择 `2. 粘贴 StatusShow Token 并更新`。

然后打开 `https://你的域名/` 查看状态页。

## 手动启动

如果不想使用菜单安装器，也可以手动启动：

```bash
git clone https://github.com/eeviriyi/NodeGet-Docker-Compose.git
cd NodeGet-Docker-Compose
cp .env.example .env
nano .env
./scripts/up.sh
```

手动启动前，至少需要配置：

```env
DOMAIN=nodeget.example.com
ACME_EMAIL=admin@example.com
POSTGRES_PASSWORD=change-this-password
STATUS_BACKEND_URL=wss://nodeget.example.com/ws
```

## DNS 解析

在你的 DNS 服务商处添加 `A` 记录：

```text
nodeget.example.com -> your server IPv4
```

如果使用 IPv6，也可以添加 `AAAA` 记录。

## HTTPS

Caddy 会自动申请和续期 Let's Encrypt 证书。域名必须已经解析到本服务器，并且公网可以访问服务器的 `80` 和 `443` 端口。

## 镜像来源

- NodeGet Server：`genshinmc/nodeget:latest`
- Postgres：`postgres:17-alpine`
- Caddy：`caddy:2-alpine`
- Board 和 StatusShow 会从配置的 Git 仓库构建镜像

生产环境建议在 `.env` 中固定版本，不要长期使用 `latest`。

## 常用命令

```bash
docker compose ps
docker compose logs -f nodeget-server
docker compose logs -f caddy
docker compose pull
docker compose up -d --build
```
