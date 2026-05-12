# MyScript — Ubuntu 24.04 服务部署工具集

## 功能

| 脚本 | 用途 |
|------|------|
| `install-nodebb.sh` | 一键安装 NodeBB v4 + MongoDB 8.0，支持 Docker |
| `install_docker.sh` | 安装 Docker Engine + Compose |
| `nginx_proxy.sh` | 配置 Nginx 反向代理 |
| `secure-setup.sh` | 创建用户、禁用 root SSH 登录 |
| `set-ssh-timeout.sh` | 配置 SSH 保活心跳，防止 NAT 断连 |

## 用法

```bash
# 所有脚本直接运行，自动检测 sudo
./install-nodebb.sh
./install_docker.sh
./nginx_proxy.sh
./secure-setup.sh
./set-ssh-timeout.sh
# 查看 SSH 当前保活配置
./set-ssh-timeout.sh --show
```

## Docker Compose

```bash
cd docker-compose/nodebb
docker compose up -d
```
