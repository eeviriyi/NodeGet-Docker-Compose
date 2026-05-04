# NodeGet-Docker-Compose 工作记录

## 定位

这是个人维护的一体化部署方案，不计划合并进上游。目标是让用户用单域名部署：

- `/`：NodeGet-StatusShow 探针页
- `/board/`：NodeGet-board 控制台
- `/ws`：NodeGet Server WebSocket JSON-RPC

## VPS 测试经验

- 2026-05-03 已在 Debian GNU/Linux 13 trixie VPS 上跑通，测试域名 `tz.aqa.cc`。
- 最终自检结果：Docker、Docker Compose、Docker Buildx、DNS、`80/443`、Postgres healthcheck、Caddy、Server、Board、StatusShow 均正常。
- 已验证接入一个 Agent 后，探针页可以显示数据。
- 用户反馈本地构建前端镜像耗时过长，默认部署改为拉 GHCR 预构建镜像；`docker-compose.build.yml` 保留源码构建路径。
- 用户反馈 ARM VPS 拉取 `nodeget-board` 报 `no matching manifest for linux/arm64/v8`，GHCR workflow 已改为发布 `linux/amd64,linux/arm64`。
- Debian 13/trixie 可能预装 `docker-buildx 0.13.1`，会和 Docker 官方 `docker-buildx-plugin` 冲突。安装脚本会移除旧包并安装官方插件。
- Docker Compose v5 构建本地镜像要求 Buildx `0.17+`。
- Cloudflare 橙云会让 Caddy ACME 校验打到 Cloudflare IP，首次部署建议先用“仅 DNS / 灰云”。
- NodeGet Server 当前 Postgres 初始化 SuperToken 时固定插入 `id=1`，可能导致 token 表自增序列未对齐。脚本创建探针页 Token 前会执行 `setval` 修正。
- 重复执行首次安装时不能覆盖 `.env`，尤其是 `POSTGRES_PASSWORD` 和 `STATUS_TOKEN`。脚本默认复用，只有输入 `REWRITE` 才重写。

## 推荐用户流程

1. DNS `A` 记录指向 VPS 公网 IP，先关闭 Cloudflare 代理。
2. 运行：

   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/eeviriyi/NodeGet-Docker-Compose/main/scripts/install.sh)
   ```

3. 选 `1. 安装 / 首次部署`。
4. 安装完成后打开脚本输出的“快速添加控制台后端”链接，或手动填写：

   ```text
   wss://你的域名/ws
   ```

5. 选菜单 `3` 生成/更新探针页 Token。
6. 打开 `https://你的域名/` 查看探针页。

## 后续待改进

- 首次发布前需要确认 GitHub Actions 已成功推送 `ghcr.io/eeviriyi/nodeget-board:main` 和 `ghcr.io/eeviriyi/nodeget-statusshow:main`，并把包可见性设为 public。
- 探针页 Token 创建应优先复用已有 `nodeget-probe-page-*` Token；当前无法从 API 取回 secret，只能重新创建。
- 增加非交互安装参数，方便一条命令自动部署。
- 支持用户选择是否启用 Cloudflare 代理场景下的 DNS-01 证书。
