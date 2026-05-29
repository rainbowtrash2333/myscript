#!/usr/bin/env bash
# =====================================================
# lib/nginx.sh - nginx 相关操作函数
# =====================================================

# -----------------------------
# nginx 二进制路径检测
# -----------------------------
_NGINX_BIN=""

detect_nginx_bin() {
    if [[ -n "$_NGINX_BIN" ]]; then
        echo "$_NGINX_BIN"
        return 0
    fi
    if is_command nginx; then
        _NGINX_BIN="$(command -v nginx)"
        echo "$_NGINX_BIN"
        return 0
    fi
    # 尝试常见路径
    for path in /usr/sbin/nginx /usr/bin/nginx /usr/local/nginx/sbin/nginx; do
        if [[ -x "$path" ]]; then
            _NGINX_BIN="$path"
            echo "$_NGINX_BIN"
            return 0
        fi
    done
    die "未检测到 nginx，请先安装 nginx"
}

# -----------------------------
# nginx 配置文件路径检测
# -----------------------------
_NGINX_CONF_DIR=""
_NGINX_SITES_AVAILABLE=""
_NGINX_SITES_ENABLED=""
_NGINX_CONF_D=""
_NGINX_STREAM_D=""
_NGINX_SSL_DIR=""
_NGINX_LOG_DIR=""

detect_nginx_paths() {
    local nginx_bin
    nginx_bin="$(detect_nginx_bin)"

    # 获取 nginx 配置目录
    if [[ -z "$_NGINX_CONF_DIR" ]]; then
        _NGINX_CONF_DIR="$(nginx -V 2>&1 | sed -n 's/.*--conf-path=\([^ ]*\).*/\1/p' | xargs dirname 2>/dev/null)" || true
        [[ -d "$_NGINX_CONF_DIR" ]] || _NGINX_CONF_DIR="/etc/nginx"
    fi

    _NGINX_SITES_AVAILABLE="${_NGINX_CONF_DIR}/sites-available"
    _NGINX_SITES_ENABLED="${_NGINX_CONF_DIR}/sites-enabled"
    _NGINX_CONF_D="${_NGINX_CONF_DIR}/conf.d"

    # 自动检测 sites-enabled 路径
    if [[ ! -d "$_NGINX_SITES_ENABLED" ]]; then
        # 检查 nginx.conf 中的 include 指令
        local include_dir
        include_dir=$(sed -n 's/.*include\s\+\([^;]*\).*/\1/p' "${_NGINX_CONF_DIR}/nginx.conf" 2>/dev/null | \
                     grep -v 'mime.types\|modules' | head -1 | sed 's/\*\.conf//' | xargs 2>/dev/null) || true
        if [[ -d "$include_dir" ]]; then
            _NGINX_SITES_ENABLED="$include_dir"
        fi
    fi

    # stream.d
    _NGINX_STREAM_D="${_NGINX_CONF_DIR}/stream.d"
    if [[ ! -d "$_NGINX_STREAM_D" ]]; then
        if grep -q "include.*stream.d" "${_NGINX_CONF_DIR}/nginx.conf" 2>/dev/null; then
            : # stream.d 在 nginx.conf 中已包含
        fi
    fi

    _NGINX_SSL_DIR="${_NGINX_CONF_DIR}/ssl"
    _NGINX_LOG_DIR="/var/log/nginx"

    # 如果 log 目录不在默认位置，从 nginx 配置检测
    local detected_log
    detected_log=$(sed -n 's/.*access_log\s\+\([^;]*\).*/\1/p' "${_NGINX_CONF_DIR}/nginx.conf" 2>/dev/null | head -1 | xargs dirname 2>/dev/null) || true
    if [[ -d "$detected_log" ]]; then
        _NGINX_LOG_DIR="$detected_log"
    fi

    export _NGINX_CONF_DIR _NGINX_SITES_AVAILABLE _NGINX_SITES_ENABLED
    export _NGINX_CONF_D _NGINX_STREAM_D _NGINX_SSL_DIR _NGINX_LOG_DIR
}

# 获取配置路径（懒加载）
get_nginx_conf_dir()        { detect_nginx_paths; echo "$_NGINX_CONF_DIR"; }
get_sites_available()       { detect_nginx_paths; echo "$_NGINX_SITES_AVAILABLE"; }
get_sites_enabled()         { detect_nginx_paths; echo "$_NGINX_SITES_ENABLED"; }
get_nginx_conf_d()          { detect_nginx_paths; echo "$_NGINX_CONF_D"; }
get_nginx_stream_d()        { detect_nginx_paths; echo "$_NGINX_STREAM_D"; }
get_nginx_ssl_dir()         { detect_nginx_paths; echo "$_NGINX_SSL_DIR"; }
get_nginx_log_dir()         { detect_nginx_paths; echo "$_NGINX_LOG_DIR"; }

# -----------------------------
# nginx 操作函数
# -----------------------------

# 配置测试
nginx_test() {
    local output status
    output=$(nginx -t 2>&1)
    status=$?

    if [[ $status -ne 0 ]]; then
        log_error "nginx 配置测试失败:"
        echo "$output" >&2
        return 1
    fi

    if ! echo "$output" | grep -q "successful"; then
        log_error "nginx 配置测试异常 (未找到 'successful' 标记):"
        echo "$output" >&2
        return 1
    fi

    log_ok "nginx 配置测试通过"
    return 0
}

# 重载配置
nginx_reload() {
    log_step "重载 nginx 配置..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将执行: nginx -s reload"
        return 0
    fi

    nginx_test || return 1

    if command -v systemctl &>/dev/null && systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl reload nginx || {
            log_error "systemctl reload nginx 失败"
            return 1
        }
    else
        nginx -s reload || {
            log_error "nginx -s reload 失败"
            return 1
        }
    fi
    log_ok "nginx 配置已重载"
    return 0
}

# 重启 nginx
nginx_restart() {
    log_step "重启 nginx..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将执行: nginx 重启"
        return 0
    fi

    nginx_test || return 1

    if command -v systemctl &>/dev/null; then
        systemctl restart nginx || {
            log_error "systemctl restart nginx 失败"
            return 1
        }
    else
        nginx -s stop && nginx || {
            log_error "nginx 重启失败"
            return 1
        }
    fi
    log_ok "nginx 已重启"
    return 0
}

# nginx 状态
nginx_status() {
    if command -v systemctl &>/dev/null; then
        systemctl status nginx 2>/dev/null || true
    else
        if pgrep -x nginx &>/dev/null; then
            log_ok "nginx 正在运行"
        else
            log_warn "nginx 未运行"
        fi
    fi

    # 显示版本信息
    if is_command nginx; then
        echo
        nginx -v 2>&1 || true
    fi
}

# 检查 nginx 是否运行
nginx_is_running() {
    if command -v systemctl &>/dev/null; then
        systemctl is-active --quiet nginx 2>/dev/null
    else
        pgrep -x nginx &>/dev/null
    fi
}

# 检查 systemd
has_systemd() {
    command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]
}

# 确保目录存在
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_step "创建目录: $dir"
        run_cmd mkdir -p "$dir"
    fi
}

# 验证 sites-enabled 目录
ensure_sites_enabled() {
    detect_nginx_paths
    ensure_dir "$_NGINX_SITES_ENABLED"
    ensure_dir "$_NGINX_SITES_AVAILABLE"

    # 确保 nginx.conf 包含 sites-enabled
    if ! grep -q "include.*${_NGINX_SITES_ENABLED}" "${_NGINX_CONF_DIR}/nginx.conf" 2>/dev/null && \
       ! grep -q "include.*sites-enabled/\*" "${_NGINX_CONF_DIR}/nginx.conf" 2>/dev/null; then
        log_warn "nginx.conf 未包含 sites-enabled，请手动添加:"
        echo "  include ${_NGINX_SITES_ENABLED}/*;"
    fi
}

# 配置 dump（用于检测重复端口等）
nginx_config_dump() {
    nginx -T 2>/dev/null || true
}

# 检查端口是否在 http 块中使用
check_http_port() {
    local port="$1"
    if nginx_config_dump | awk '/^http\s*\{/,/^\}/' | grep -q "listen.*${port}"; then
        return 0
    fi
    return 1
}

# 检查端口是否在 stream 块中使用
check_stream_port() {
    local port="$1"
    if nginx_config_dump | awk '/^stream\s*\{/,/^\}/' | grep -q "listen.*${port}"; then
        return 0
    fi
    return 1
}

# 检查上游服务器
check_upstream_exists() {
    local name="$1"
    nginx_config_dump | grep -q "upstream ${name}"
}

# 发送 USR1 信号（日志轮转后重新打开日志文件）
nginx_reopen_logs() {
    if nginx_is_running; then
        run_cmd kill -USR1 "$(cat /var/run/nginx.pid 2>/dev/null)" 2>/dev/null || true
    fi
}
