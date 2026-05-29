# nginx-tools — Nginx 运维命令行工具

> 极轻量、零数据库、零 Web UI 的纯 Shell nginx 管理工具

## 定位

类似 `git` / `docker` / `systemctl` 的命令行工具，通过子命令完成 nginx 日常运维，无需手动编辑配置文件。

## 特性

- **极低服务器占用** — 纯 Bash，无运行时依赖
- **零数据库** — 所有状态来自 nginx 配置文件
- **零 Web UI** — 纯 CLI，适合 VPS / Docker / Linux Server
- **模块化** — 功能独立，按需加载
- **幂等操作** — 所有命令可重复执行
- **自动备份** — 配置修改前自动备份
- **配置验证** — 所有变更前后执行 `nginx -t`
- **Dry-Run 模式** — 预览变更而不实际执行

## 项目结构

```
nginx-tools          # 主入口
lib/                 # 公共函数库
  common.sh          # 日志、颜色、锁、提权检测、dry-run
  nginx.sh           # nginx 操作 (test/reload/restart/status/路径检测)
  validation.sh      # 输入验证 (域名/IP/端口/upstream)
  backup-lib.sh      # 备份/还原
modules/             # 功能模块
  nginx.sh           # nginx 服务管理
  site.sh            # 站点管理
  proxy.sh           # 反向代理
  ssl.sh             # SSL 证书 (acme.sh)
  template.sh        # 配置模板生成
  log.sh             # 日志查看
  upstream.sh        # 负载均衡
  stream.sh          # TCP/UDP 转发
  backup.sh          # 备份管理
templates/           # nginx 配置模板文件
sites/               # 站点生成记录
```

## 安装

```bash
# 开发模式（创建符号链接，推荐）
sudo ln -sf $(pwd)/nginx-tools /usr/local/bin/nginx-tools
```

## 快速上手

```bash
# 查看帮助
nginx-tools --help

# 创建站点
nginx-tools site add example.com

# 创建反向代理（支持 WebSocket）
nginx-tools proxy add app.example.com --upstream 127.0.0.1:3000 --websocket

# 申请 SSL 证书
nginx-tools ssl issue example.com

# 创建 HTTPS 反向代理
nginx-tools proxy add app.example.com --upstream 127.0.0.1:3000 --ssl

# 生成模板
nginx-tools template generate blog.example.com wordpress

# 管理 upstream
nginx-tools upstream create backend
nginx-tools upstream add backend 10.0.0.1:8080
nginx-tools upstream add backend 10.0.0.2:8080

# 查看日志
nginx-tools log tail access

# 备份/还原
nginx-tools backup create
nginx-tools backup list

# Dry-Run 预览
nginx-tools --dry-run proxy add test.com --upstream 127.0.0.1:3000
```

## 命令参考

### site — 站点管理

```
nginx-tools site add <domain> [--template static]
nginx-tools site delete <domain>
nginx-tools site enable <domain>
nginx-tools site disable <domain>
nginx-tools site list
nginx-tools site show <domain>
```

### proxy — 反向代理

```
nginx-tools proxy add <domain> --upstream <IP:PORT> [--ssl] [--websocket] [--custom-upstream <name>]
nginx-tools proxy remove <domain>
nginx-tools proxy list
```

### ssl — SSL 证书 (acme.sh)

```
nginx-tools ssl issue <domain> [--ecc] [--keylength 256|384]
nginx-tools ssl install <domain>
nginx-tools ssl renew [domain] [--force]
nginx-tools ssl list
```

### nginx — 服务管理

```
nginx-tools nginx reload     # 平滑重载
nginx-tools nginx restart    # 重启（需确认）
nginx-tools nginx test       # 配置测试
nginx-tools nginx status     # 运行状态
```

### template — 模板生成

```
nginx-tools template list
nginx-tools template generate <domain> <template> [port]

可用模板: static, wordpress, nodebb, reverse-proxy, docker-app
```

### log — 日志查看

```
nginx-tools log access [行数]
nginx-tools log error [行数]
nginx-tools log tail <access|error>
```

### upstream — 负载均衡

```
nginx-tools upstream create <name>
nginx-tools upstream add <name> <IP:PORT>
nginx-tools upstream remove <name> <IP:PORT>
nginx-tools upstream list
```

### stream — TCP/UDP 转发

```
nginx-tools stream add <name> --listen <port> --to <IP:PORT> [--proto tcp|udp]
nginx-tools stream add mysql --to 10.0.0.3:3306
nginx-tools stream remove <name>
nginx-tools stream list
```

### backup — 备份管理

```
nginx-tools backup create [label]
nginx-tools backup list
nginx-tools backup restore <file>
nginx-tools backup cleanup [days]
```

## 全局选项

| 选项 | 说明 |
|------|------|
| `--dry-run` | 预览模式，不执行实际操作 |
| `--verbose` | 调试模式，输出详细日志 |
| `--yes`, `-y` | 跳过所有确认提示 |
| `--help`, `-h` | 显示帮助信息 |
| `--version`, `-v` | 显示版本信息 |

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `NGINX_TOOLS_ROOT` | 自动检测 | 工具安装根目录 |
| `NGINX_TOOLS_DRY_RUN` | `0` | 启用 dry-run 模式 |
| `NGINX_TOOLS_VERBOSE` | `0` | 启用调试输出 |
| `NGINX_TOOLS_YES` | `0` | 跳过确认提示 |
| `NGINX_TOOLS_BACKUP_RETENTION` | `30` | 备份保留天数 |

## 技术细节

- **语言**: Bash 4+
- **系统**: Ubuntu / Debian
- **依赖**: nginx, systemd (可选), acme.sh (SSL 功能)
- **目录标准**: FHS 兼容 (`/usr/local/`, `/etc/nginx/`)
- **备份目录**: `/var/backups/nginx-tools/`
- **配置文件**: 嵌入 nginx config 注释 (`# nginx-tools:KEY=VALUE`)

## 幂等性保证

所有命令可安全重复执行：
- `site enable` — 已启用则跳过
- `proxy add` — 已存在则跳过
- `ssl issue` — 证书有效则跳过
- 配置变更前自动备份
- 变更前后执行 `nginx -t` 验证
- 验证失败自动回滚

## 相关项目

本仓库的其他运维脚本：

| 脚本 | 用途 |
|------|------|
| `install_docker.sh` | 安装 Docker Engine + Compose |
| `nginx_tools.sh` | 原 Nginx 反向代理安装脚本（已升级为 nginx-tools） |
| `secure-setup.sh` | 创建用户、禁用 root SSH 登录 |
| `set-ssh-timeout.sh` | 配置 SSH 保活心跳 |
| `docker_cleanup.sh` | Docker 环境清理 |
