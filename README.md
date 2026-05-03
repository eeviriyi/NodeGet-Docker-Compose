# NodeGet Docker Compose

NodeGet 单域名 Docker Compose 部署方案，目标是让个人 VPS 可以用一条脚本启动 Server、Board 和探针页。

路由：

- `/` 提供探针页
- `/board/` 提供 NodeGet-board 控制台
- `/ws` 反代 NodeGet Server WebSocket JSON-RPC

本方案使用 Caddy 自动 HTTPS、Postgres 存储、官方 NodeGet Server 镜像，以及预构建的 Board/StatusShow 镜像。

## 已实测环境

- Debian GNU/Linux 13 trixie
- Docker `29.4.2`
- Docker Compose `v5.1.3`
- Docker Buildx `v0.33.0`
- 单域名 HTTPS：已验证 Caddy 自动签发 Let's Encrypt 证书
- 已验证路径：`/`、`/board/`、`/ws`
- 默认安装不在 VPS 上构建前端镜像，避免低配机器长时间卡在 `Building`

## 环境要求

- 已安装 Docker 和 Docker Compose
- 一个已经解析到本服务器的域名
- 服务器开放入站 `80` 和 `443` 端口

## VPS 测试流程

先准备一台干净 VPS：

- 已安装 Docker 和 Docker Compose 插件；如果没有，安装脚本可以自动安装
- 域名已经添加 `A` 记录指向 VPS IPv4
- 防火墙/安全组放行 `80` 和 `443`

在 VPS 上运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eeviriyi/NodeGet-Docker-Compose/main/scripts/install.sh)
```

选择 `1. 安装 / 首次部署`，然后按提示输入：

- 域名
- 探针页名称
- ACME 邮箱
- Postgres 密码，也可以直接使用脚本生成的默认值

如果 VPS 没有 Docker，安装脚本会提示是否使用 Docker 官方脚本一键安装。也可以先在菜单里选择 `2. 安装 / 修复 Docker`。

安装脚本会把本仓库克隆到 `/opt/nodeget-compose`，写入 `.env`，启动 Docker Compose，并在服务日志出现 SuperToken 后直接输出。

启动完成后：

1. 打开 `https://你的域名/board/`。
2. 使用安装脚本输出的 SuperToken 登录。
3. 在控制台里添加后端地址 `wss://你的域名/ws`。
4. 脚本会自动创建探针页专用只读 Token，并写入探针页配置。
5. 如果探针页暂时不能读取数据，再次运行安装脚本，选择 `3. 自动生成/更新探针页访问 Token`。

然后打开 `https://你的域名/` 查看探针页。

测试时常用菜单：

- `2. 安装 / 修复 Docker`
- `3. 自动生成/更新探针页访问 Token`
- `5. 重新生成配置并重启`
- `6. 查看状态`
- `7. 部署自检`
- `8. 查看 SuperToken`
- `9. 查看日志`

也可以在安装目录手动自检：

```bash
cd /opt/nodeget-compose
./scripts/doctor.sh
```

自检通过后应看到 Docker、Compose、Buildx、DNS、`80/443` 和容器状态均为 OK。

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

默认会拉取预构建前端镜像：

```env
BOARD_IMAGE=ghcr.io/eeviriyi/nodeget-board:main
STATUSSHOW_IMAGE=ghcr.io/eeviriyi/nodeget-statusshow:main
```

如果需要在 VPS 上从源码构建 Board/StatusShow，额外设置：

```env
NODEGET_BUILD_FRONTENDS=1
BOARD_REPO=https://github.com/eeviriyi/NodeGet-board.git
BOARD_REF=main
STATUSSHOW_REPO=https://github.com/eeviriyi/NodeGet-StatusShow.git
STATUSSHOW_REF=main
```

如果需要重新渲染探针页配置：

```bash
./scripts/render-status-config.sh
docker compose restart nodeget-statusshow
```

## DNS 解析

在你的 DNS 服务商处添加 `A` 记录：

```text
nodeget.example.com -> your server IPv4
```

如果使用 IPv6，也可以添加 `AAAA` 记录。

## HTTPS

Caddy 会自动申请和续期 Let's Encrypt 证书。域名必须已经解析到本服务器，并且公网可以访问服务器的 `80` 和 `443` 端口。

如果第一次访问 HTTPS 失败，优先检查：

- DNS 是否已经解析到 VPS
- VPS 安全组是否放行 `80/443`
- VPS 内是否已有 nginx/apache/caddy 占用端口
- `docker compose logs -f caddy` 里的 ACME 错误

## 镜像来源

- NodeGet Server：`genshinmc/nodeget:latest`
- Postgres：`postgres:17-alpine`
- Caddy：`caddy:2-alpine`
- Board：`ghcr.io/eeviriyi/nodeget-board:main`
- StatusShow：`ghcr.io/eeviriyi/nodeget-statusshow:main`

生产环境建议在 `.env` 中固定版本，不要长期使用 `latest`。

## 常用命令

```bash
docker compose ps
docker compose logs -f nodeget-server
docker compose logs -f caddy
docker compose pull
docker compose up -d
./scripts/doctor.sh
```

本地构建前端镜像：

```bash
NODEGET_BUILD_FRONTENDS=1 docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build
```
