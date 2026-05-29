#!/usr/bin/env bash
# =====================================================
# nginx-tools.sh — 交互式分层菜单入口
# =====================================================
# 面向不熟悉 nginx 的用户，通过数字编号导航。
# 底层调用 nginx-tools CLI 完成实际操作。
# =====================================================
set -euo pipefail

# -----------------------------
# 路径发现
# -----------------------------
_SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
_SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"

# nginx-tools CLI 路径检测
if [[ -x "${_SELF_DIR}/nginx-tools" ]]; then
    _NGINX_TOOLS_BIN="${_SELF_DIR}/nginx-tools"
elif command -v nginx-tools &>/dev/null; then
    _NGINX_TOOLS_BIN="$(command -v nginx-tools)"
else
    echo -e "\033[31m[ERROR]\033[0m 找不到 nginx-tools CLI" >&2
    echo "  请确保 nginx-tools 与本脚本在同一目录，或已加入 PATH" >&2
    exit 1
fi

# -----------------------------
# 颜色定义（与 lib/common.sh 一致）
# -----------------------------
if [[ -t 1 ]]; then
    COLOR_RESET='\033[0m'
    COLOR_RED='\033[31m'
    COLOR_GREEN='\033[32m'
    COLOR_YELLOW='\033[33m'
    COLOR_BLUE='\033[34m'
    COLOR_CYAN='\033[36m'
    COLOR_BOLD='\033[1m'
else
    COLOR_RESET=''
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_CYAN=''
    COLOR_BOLD=''
fi

# -----------------------------
# 信号处理
# -----------------------------
trap '_exit_handler' INT TERM

_exit_handler() {
    set +e
    echo
    echo -e "${COLOR_YELLOW}已中断，退出菜单。${COLOR_RESET}"
    exit 130
}

# -----------------------------
# 工具函数
# -----------------------------

# 打印带颜色的菜单标题
_header() {
    local title="$1"
    echo
    echo -e "${COLOR_GREEN}============================================${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}  ${title}${COLOR_RESET}"
    echo -e "${COLOR_GREEN}============================================${COLOR_RESET}"
}

# 暂停等待用户按回车
_pause() {
    echo
    read -r -p "按回车键继续..." _dummy || true
}

# 读取必填输入（非空）
# 用法: _read_required "提示" var_name
_read_required() {
    local prompt="$1"
    local _result=""
    while true; do
        read -r -p "${prompt}: " _result || true
        # trim whitespace
        _result="${_result#"${_result%%[![:space:]]*}"}"
        _result="${_result%"${_result##*[![:space:]]}"}"
        if [[ -n "$_result" ]]; then
            printf -v "$2" '%s' "$_result"
            return 0
        fi
        echo -e "${COLOR_RED}输入不能为空，请重新输入。${COLOR_RESET}"
    done
}

# 读取可选输入（带默认值）
# 用法: _read_optional "提示" "默认值" var_name
_read_optional() {
    local prompt="$1"
    local default="$2"
    local _result=""
    read -r -p "${prompt} [${default}]: " _result || true
    _result="${_result#"${_result%%[![:space:]]*}"}"
    _result="${_result%"${_result##*[![:space:]]}"}"
    if [[ -z "$_result" ]]; then
        _result="$default"
    fi
    printf -v "$3" '%s' "$_result"
}

# y/n 确认
# 用法: if _confirm "确认删除？"; then ...
_confirm() {
    local prompt="${1:-确认操作？}"
    local yn
    read -r -p "${prompt} [y/N]: " yn || true
    [[ "$yn" == "y" || "$yn" == "Y" ]]
}

# 执行命令并显示结果
# 用法: _run ./nginx-tools site add example.com
_run() {
    echo
    echo -e "${COLOR_CYAN}=> 执行: $*${COLOR_RESET}"
    echo -e "${COLOR_CYAN}────────────────────────────────────────────${COLOR_RESET}"
    # 不用 set -e，手动捕获退出码
    set +e
    "$@"
    local rc=$?
    set -e
    echo -e "${COLOR_CYAN}────────────────────────────────────────────${COLOR_RESET}"
    if [[ $rc -eq 0 ]]; then
        echo -e "${COLOR_GREEN}[完成] 命令执行成功${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}[失败] 命令返回退出码: ${rc}${COLOR_RESET}"
    fi
    return 0  # 不传播失败，避免退出菜单
}

# 读取并验证数字范围
# 用法: _menu_choice min max
# 结果存入全局变量 CHOICE
_menu_choice() {
    local min="$1"
    local max="$2"
    local input=""
    read -r -p "请选择 [${min}-${max}]: " input || true
    # 去除空白
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    # 允许 q 退出
    if [[ "$input" == "q" ]]; then
        echo -e "${COLOR_YELLOW}退出菜单。${COLOR_RESET}"
        exit 0
    fi
    # 验证是数字
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        CHOICE="-1"
        return 0
    fi
    CHOICE="$input"
}

# 分割线
_separator() {
    echo -e "${COLOR_GREEN}--------------------------------------------${COLOR_RESET}"
}

# -----------------------------
# 1. 站点管理
# -----------------------------
site_menu() {
    while true; do
        _header "站点管理"
        echo "    1. 添加站点"
        echo "    2. 删除站点"
        echo "    3. 启用站点"
        echo "    4. 禁用站点"
        echo "    5. 列出站点"
        echo "    6. 查看详情"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 6

        case "$CHOICE" in
            1)
                local domain template
                _read_required "请输入域名 (如 example.com)" domain
                read -r -p "请输入模板名称 (留空使用默认 static): " template || true
                template="${template#"${template%%[![:space:]]*}"}"
                template="${template%"${template##*[![:space:]]}"}"
                if [[ -n "$template" ]]; then
                    _run "$_NGINX_TOOLS_BIN" site add "$domain" --template "$template"
                else
                    _run "$_NGINX_TOOLS_BIN" site add "$domain"
                fi
                _pause
                ;;
            2)
                local domain
                _read_required "请输入要删除的域名" domain
                echo -e "${COLOR_YELLOW}警告: 此操作将删除站点 ${domain} 的配置文件！${COLOR_RESET}"
                if _confirm "确认删除？"; then
                    _run "$_NGINX_TOOLS_BIN" --yes site delete "$domain"
                else
                    echo "已取消。"
                fi
                _pause
                ;;
            3)
                local domain
                _read_required "请输入要启用的域名" domain
                _run "$_NGINX_TOOLS_BIN" site enable "$domain"
                _pause
                ;;
            4)
                local domain
                _read_required "请输入要禁用的域名" domain
                _run "$_NGINX_TOOLS_BIN" site disable "$domain"
                _pause
                ;;
            5)
                _run "$_NGINX_TOOLS_BIN" site list
                _pause
                ;;
            6)
                local domain
                _read_required "请输入要查看的域名" domain
                _run "$_NGINX_TOOLS_BIN" site show "$domain"
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-6 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 2. 反向代理
# -----------------------------
proxy_menu() {
    while true; do
        _header "反向代理"
        echo "    1. 添加反向代理"
        echo "    2. 删除反向代理"
        echo "    3. 列出反向代理"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 3

        case "$CHOICE" in
            1)
                local domain ip port ws_flag="" ssl_flag=""
                _read_required "请输入域名 (如 app.example.com)" domain
                _read_required "请输入上游 IP (如 127.0.0.1)" ip
                _read_required "请输入上游端口 (如 3000)" port
                if _confirm "是否启用 WebSocket 支持？"; then
                    ws_flag="--websocket"
                fi
                if _confirm "是否启用 SSL (HTTPS)？"; then
                    ssl_flag="--ssl"
                fi
                # shellcheck disable=SC2086
                _run "$_NGINX_TOOLS_BIN" proxy add "$domain" --upstream "${ip}:${port}" $ws_flag $ssl_flag
                _pause
                ;;
            2)
                local domain
                _read_required "请输入要删除反向代理的域名" domain
                echo -e "${COLOR_YELLOW}警告: 此操作将删除 ${domain} 的反向代理配置！${COLOR_RESET}"
                if _confirm "确认删除？"; then
                    _run "$_NGINX_TOOLS_BIN" --yes proxy remove "$domain"
                else
                    echo "已取消。"
                fi
                _pause
                ;;
            3)
                _run "$_NGINX_TOOLS_BIN" proxy list
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-3 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 3. SSL 证书
# -----------------------------
ssl_menu() {
    while true; do
        _header "SSL 证书管理"
        echo "    1. 申请证书"
        echo "    2. 安装证书"
        echo "    3. 续期证书"
        echo "    4. 证书列表"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 4

        case "$CHOICE" in
            1)
                local domain ecc_flag=""
                _read_required "请输入域名" domain
                if _confirm "是否使用 ECC 证书 (更小更快)？"; then
                    ecc_flag="--ecc"
                fi
                # shellcheck disable=SC2086
                _run "$_NGINX_TOOLS_BIN" ssl issue "$domain" $ecc_flag
                _pause
                ;;
            2)
                local domain
                _read_required "请输入域名" domain
                _run "$_NGINX_TOOLS_BIN" ssl install "$domain"
                _pause
                ;;
            3)
                local domain
                read -r -p "请输入域名 (留空续期所有证书): " domain || true
                domain="${domain#"${domain%%[![:space:]]*}"}"
                domain="${domain%"${domain##*[![:space:]]}"}"
                if [[ -n "$domain" ]]; then
                    _run "$_NGINX_TOOLS_BIN" ssl renew "$domain"
                else
                    _run "$_NGINX_TOOLS_BIN" ssl renew
                fi
                _pause
                ;;
            4)
                _run "$_NGINX_TOOLS_BIN" ssl list
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-4 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 4. Nginx 服务
# -----------------------------
nginx_svc_menu() {
    while true; do
        _header "Nginx 服务管理"
        echo "    1. 重载配置"
        echo "    2. 重启服务"
        echo "    3. 测试配置"
        echo "    4. 查看状态"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 4

        case "$CHOICE" in
            1)
                _run "$_NGINX_TOOLS_BIN" nginx reload
                _pause
                ;;
            2)
                echo -e "${COLOR_YELLOW}警告: 重启将中断当前所有连接！${COLOR_RESET}"
                if _confirm "确认重启？"; then
                    _run "$_NGINX_TOOLS_BIN" --yes nginx restart
                else
                    echo "已取消。"
                fi
                _pause
                ;;
            3)
                _run "$_NGINX_TOOLS_BIN" nginx test
                _pause
                ;;
            4)
                _run "$_NGINX_TOOLS_BIN" nginx status
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-4 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 5. 模板生成
# -----------------------------
template_menu() {
    while true; do
        _header "模板生成"
        echo "    1. 查看模板列表"
        echo "    2. Static 站点"
        echo "    3. WordPress 站点"
        echo "    4. NodeBB 站点"
        echo "    5. 反向代理配置"
        echo "    6. Docker 应用"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 6

        case "$CHOICE" in
            1)
                _run "$_NGINX_TOOLS_BIN" template list
                _pause
                ;;
            2)
                local domain
                _read_required "请输入域名" domain
                _run "$_NGINX_TOOLS_BIN" template generate "$domain" static
                _pause
                ;;
            3)
                local domain
                _read_required "请输入域名" domain
                _run "$_NGINX_TOOLS_BIN" template generate "$domain" wordpress
                _pause
                ;;
            4)
                local domain
                _read_required "请输入域名" domain
                _run "$_NGINX_TOOLS_BIN" template generate "$domain" nodebb
                _pause
                ;;
            5)
                local domain
                _read_required "请输入域名" domain
                _run "$_NGINX_TOOLS_BIN" template generate "$domain" reverse-proxy
                _pause
                ;;
            6)
                local domain port
                _read_required "请输入域名" domain
                _read_required "请输入容器端口 (如 8080)" port
                _run "$_NGINX_TOOLS_BIN" template generate "$domain" docker-app "$port"
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-6 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 6. 日志查看
# -----------------------------
log_menu() {
    while true; do
        _header "日志查看"
        echo "    1. 查看访问日志"
        echo "    2. 查看错误日志"
        echo "    3. 实时跟踪访问日志"
        echo "    4. 实时跟踪错误日志"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 4

        case "$CHOICE" in
            1)
                local lines
                _read_optional "显示行数" "50" lines
                _run "$_NGINX_TOOLS_BIN" log access "$lines"
                _pause
                ;;
            2)
                local lines
                _read_optional "显示行数" "50" lines
                _run "$_NGINX_TOOLS_BIN" log error "$lines"
                _pause
                ;;
            3)
                echo -e "${COLOR_CYAN}实时跟踪访问日志 (按 Ctrl+C 停止)${COLOR_RESET}"
                _run "$_NGINX_TOOLS_BIN" log tail access
                _pause
                ;;
            4)
                echo -e "${COLOR_CYAN}实时跟踪错误日志 (按 Ctrl+C 停止)${COLOR_RESET}"
                _run "$_NGINX_TOOLS_BIN" log tail error
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-4 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 7. 负载均衡 (upstream)
# -----------------------------
upstream_menu() {
    while true; do
        _header "负载均衡 (Upstream)"
        echo "    1. 创建 upstream"
        echo "    2. 添加后端"
        echo "    3. 删除后端"
        echo "    4. 列出 upstream"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 4

        case "$CHOICE" in
            1)
                local name
                _read_required "请输入 upstream 名称 (如 backend)" name
                _run "$_NGINX_TOOLS_BIN" upstream create "$name"
                _pause
                ;;
            2)
                local name backend
                _read_required "请输入 upstream 名称" name
                _read_required "请输入后端地址 (如 10.0.0.1:8080)" backend
                _run "$_NGINX_TOOLS_BIN" upstream add "$name" "$backend"
                _pause
                ;;
            3)
                local name backend
                _read_required "请输入 upstream 名称" name
                _read_required "请输入要删除的后端地址 (如 10.0.0.1:8080)" backend
                _run "$_NGINX_TOOLS_BIN" upstream remove "$name" "$backend"
                _pause
                ;;
            4)
                _run "$_NGINX_TOOLS_BIN" upstream list
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-4 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 8. TCP/UDP 转发 (stream)
# -----------------------------
stream_menu() {
    while true; do
        _header "TCP/UDP 转发 (Stream)"
        echo "    1. 添加转发"
        echo "    2. 删除转发"
        echo "    3. 列出转发"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 3

        case "$CHOICE" in
            1)
                local name listen_port target proto
                echo
                echo "  预设模板:"
                echo "    1. SSH    (监听 22)"
                echo "    2. MySQL  (监听 3306)"
                echo "    3. 自定义"
                echo
                read -r -p "  选择 [1-3]: " preset || true
                case "$preset" in
                    1)
                        name="ssh"
                        _read_optional "监听端口" "22" listen_port
                        _read_required "目标地址 (如 10.0.0.3:22)" target
                        proto="tcp"
                        ;;
                    2)
                        name="mysql"
                        _read_optional "监听端口" "3306" listen_port
                        _read_required "目标地址 (如 10.0.0.3:3306)" target
                        proto="tcp"
                        ;;
                    3|*)
                        _read_required "转发名称 (如 ssh-tunnel)" name
                        _read_required "监听端口 (如 2222)" listen_port
                        _read_required "目标地址 (如 10.0.0.3:22)" target
                        read -r -p "协议 (tcp/udp) [tcp]: " proto || true
                        proto="${proto:-tcp}"
                        ;;
                esac
                _run "$_NGINX_TOOLS_BIN" stream add "$name" --listen "$listen_port" --to "$target" --proto "$proto"
                _pause
                ;;
            2)
                local name
                _read_required "请输入要删除的转发名称" name
                echo -e "${COLOR_YELLOW}警告: 此操作将删除转发规则 ${name}！${COLOR_RESET}"
                if _confirm "确认删除？"; then
                    _run "$_NGINX_TOOLS_BIN" --yes stream remove "$name"
                else
                    echo "已取消。"
                fi
                _pause
                ;;
            3)
                _run "$_NGINX_TOOLS_BIN" stream list
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-3 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 9. 备份管理
# -----------------------------
backup_menu() {
    while true; do
        _header "备份管理"
        echo "    1. 创建备份"
        echo "    2. 备份列表"
        echo "    3. 还原备份"
        echo "    4. 清理旧备份"
        echo "    0. 返回上级菜单"
        _separator
        _menu_choice 0 4

        case "$CHOICE" in
            1)
                local label
                _read_optional "备份标签" "manual" label
                _run "$_NGINX_TOOLS_BIN" backup create "$label"
                _pause
                ;;
            2)
                _run "$_NGINX_TOOLS_BIN" backup list
                _pause
                ;;
            3)
                echo -e "${COLOR_CYAN}当前可用备份:${COLOR_RESET}"
                "$_NGINX_TOOLS_BIN" backup list 2>/dev/null || true
                echo
                local filename
                _read_required "请输入要还原的备份文件名" filename
                echo -e "${COLOR_YELLOW}警告: 还原将覆盖当前配置！${COLOR_RESET}"
                if _confirm "确认还原？"; then
                    _run "$_NGINX_TOOLS_BIN" --yes backup restore "$filename"
                else
                    echo "已取消。"
                fi
                _pause
                ;;
            4)
                local days
                _read_optional "保留天数" "30" days
                _run "$_NGINX_TOOLS_BIN" backup cleanup "$days"
                _pause
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-4 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 10. 使用帮助
# -----------------------------
show_help() {
    _header "使用帮助"
    "$_NGINX_TOOLS_BIN" --help 2>/dev/null || echo "无法获取帮助信息。"
    echo
    _pause
}

# -----------------------------
# 主菜单
# -----------------------------
main_menu() {
    while true; do
        _header "nginx-tools 运维工具 — 主菜单"
        echo "    1.  站点管理          (添加/删除/启用/禁用站点)"
        echo "    2.  反向代理          (创建反向代理规则)"
        echo "    3.  SSL 证书          (申请/安装/续期证书)"
        echo "    4.  Nginx 服务        (重载/重启/测试/状态)"
        echo "    5.  模板生成          (生成站点配置)"
        echo "    6.  日志查看          (查看访问/错误日志)"
        echo "    7.  负载均衡          (管理 upstream)"
        echo "    8.  TCP/UDP 转发      (管理 stream 代理)"
        echo "    9.  备份管理          (备份/还原/清理)"
        echo "   10.  使用帮助"
        echo "    0.  退出"
        _separator
        _menu_choice 0 10

        case "$CHOICE" in
            1)  site_menu ;;
            2)  proxy_menu ;;
            3)  ssl_menu ;;
            4)  nginx_svc_menu ;;
            5)  template_menu ;;
            6)  log_menu ;;
            7)  upstream_menu ;;
            8)  stream_menu ;;
            9)  backup_menu ;;
            10) show_help ;;
            0)
                echo -e "${COLOR_GREEN}再见！${COLOR_RESET}"
                exit 0
                ;;
            *)
                echo -e "${COLOR_RED}无效选择，请输入 0-10 的数字。${COLOR_RESET}"
                ;;
        esac
    done
}

# -----------------------------
# 入口
# -----------------------------
main_menu
