# MyScript — Ubuntu 24.04 服务部署工具集

## nginx-tools 🚀

> 极轻量、零数据库、零 Web UI 的纯 Shell nginx 管理工具

类似 `git` / `docker` / `systemctl` 的命令行工具，通过子命令完成 nginx 日常运维。

- **CLI 模式**: `./nginx-tools/nginx-tools site add example.com`
- **交互菜单模式**: `./nginx-tools/nginx-tools.sh`（数字导航，新手友好）
- **功能**: 站点管理、反向代理、SSL证书、模板生成、日志查看、负载均衡、TCP/UDP转发、备份管理

详细文档：[nginx-tools/README.md](nginx-tools/README.md)

## 独立脚本

| 脚本 | 用途 |
|------|------|
| `install_docker.sh` | 安装 Docker Engine + Compose |
| `secure-setup.sh` | 创建用户、禁用 root SSH 登录 |
| `set-ssh-timeout.sh` | 配置 SSH 保活心跳，防止 NAT 断连 |
| `docker_cleanup.sh` | 清理 Docker 容器、镜像、卷、网络 |

## 用法

```bash
# 所有脚本直接运行，自动检测 sudo
./install_docker.sh
./secure-setup.sh
./set-ssh-timeout.sh
./set-ssh-timeout.sh --show    # 查看当前保活配置
./docker_cleanup.sh

# nginx-tools CLI
./nginx-tools/nginx-tools --help
./nginx-tools/nginx-tools site add example.com
./nginx-tools/nginx-tools proxy add app.example.com --upstream 127.0.0.1:3000

# nginx-tools 交互菜单
./nginx-tools/nginx-tools.sh
```

## Docker Compose

```bash
cd docker-compose/nodebb
docker compose up -d
```

> 注: `nginx_proxy.sh` 已被功能更完整的 `nginx-tools` 取代。
