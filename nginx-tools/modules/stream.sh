#!/usr/bin/env bash
# =====================================================
# modules/stream.sh - TCP/UDP 流量转发模块
# =====================================================
# 子命令: add, remove, list, help
# 用法:   nginx-tools stream <subcommand> [args...]
# =====================================================

# -----------------------------
# 预设快捷方式定义
# -----------------------------
_stream_preset_port() {
    local _stream_pname="$1"
    case "$_stream_pname" in
        ssh)        echo "22" ;;
        mysql)      echo "3306" ;;
        minecraft)  echo "25565" ;;
        *)          echo "" ;;
    esac
}

_stream_preset_proto() {
    local _stream_pname="$1"
    case "$_stream_pname" in
        ssh|mysql|minecraft) echo "tcp" ;;
        *)                   echo "" ;;
    esac
}

# -----------------------------
# 确保 stream.d 目录和 include 存在
# -----------------------------
_ensure_stream_dir() {
    local _stream_sd
    _stream_sd="$(get_nginx_stream_d)"
    ensure_dir "$_stream_sd"

    local _stream_cdir _stream_nc
    _stream_cdir="$(get_nginx_conf_dir)"
    _stream_nc="${_stream_cdir}/nginx.conf"

    if ! grep -q '^\s*stream\s*{' "$_stream_nc" 2>/dev/null; then
        log_step "nginx.conf 中未找到 stream 块，正在追加..."
        if is_dry_run; then
            log_info "[DRY-RUN] 将在 nginx.conf 末尾追加 stream { include ...; } 块"
            return 0
        fi
        cat >> "$_stream_nc" <<'STREAM_EOF'

# nginx-tools: stream 转发配置
stream {
    include /etc/nginx/stream.d/*.conf;
}
STREAM_EOF
        log_ok "已追加 stream 块到 nginx.conf"
    else
        if ! grep -q 'include.*stream\.d' "$_stream_nc" 2>/dev/null; then
            log_step "stream 块中未包含 stream.d，正在添加 include..."
            if is_dry_run; then
                log_info "[DRY-RUN] 将在 stream 块中添加 include /etc/nginx/stream.d/*.conf;"
                return 0
            fi
            sed -i '/^\s*stream\s*{/a\    include /etc/nginx/stream.d/*.conf;' "$_stream_nc"
            log_ok "已在 stream 块中添加 include 指令"
        fi
    fi
}

# -----------------------------
# 检查端口冲突 (http + stream)
# -----------------------------
_check_port_available() {
    local _stream_port="$1"
    local _stream_skip_name="${2:-}"

    # 检查 http 块
    if check_http_port "$_stream_port"; then
        die "端口 ${_stream_port} 已在 http 块中使用，无法用于 stream 转发"
    fi

    # 检查 stream 块
    if check_stream_port "$_stream_port"; then
        # 如果是同一配置名（重建场景），允许
        if [[ -n "$_stream_skip_name" ]]; then
            local _stream_sdir
            _stream_sdir="$(get_nginx_stream_d)"
            local _stream_existing_listen
            _stream_existing_listen="$(sed -n 's/.*listen\s\+\([0-9]*\).*/\1/p' "${_stream_sdir}/${_stream_skip_name}.conf" 2>/dev/null || true)"
            if [[ "$_stream_existing_listen" == "$_stream_port" ]]; then
                return 0
            fi
        fi
        die "端口 ${_stream_port} 已在 stream 块中使用"
    fi
}

# -----------------------------
# 帮助信息
# -----------------------------
_ensure_stream_dir_check() {
    local _stream_sd
    _stream_sd="$(get_nginx_stream_d)"
    if [[ ! -d "$_stream_sd" ]]; then
        log_info "stream.d 目录不存在，正在创建..."
        ensure_dir "$_stream_sd"
    fi
}

_stream_help() {
    cat <<EOF
nginx-tools stream - TCP/UDP 流量转发管理

用法:
  nginx-tools stream <subcommand> [args...]

可用子命令:
  add <name> --listen <port> --to <IP:PORT> [--proto tcp|udp]
                                       添加 stream 转发配置
  remove <name>                        删除 stream 转发配置 (需确认)
  list                                 列出所有 stream 转发配置
  help                                 显示此帮助信息

预设快捷方式:
  ssh          → listen 22, proto tcp
  mysql        → listen 3306, proto tcp
  minecraft    → listen 25565, proto tcp
  custom       → 需显式指定 --listen 和 --to

示例:
  nginx-tools stream add ssh --to 192.168.1.100:22
  nginx-tools stream add mysql --to 10.0.0.5:3306
  nginx-tools stream add minecraft --to 192.168.1.50:25565
  nginx-tools stream add myapp --listen 8080 --to 10.0.0.2:8080 --proto tcp
  nginx-tools stream add mygame --listen 19132 --to 10.0.0.3:19132 --proto udp
  nginx-tools stream remove ssh
  nginx-tools stream list
EOF
}

# -----------------------------
# _stream_list - 列出所有 stream 转发配置
# -----------------------------
_stream_list() {
    _ensure_stream_dir_check

    local _stream_sd
    _stream_sd="$(get_nginx_stream_d)"

    print_banner "Stream 转发列表"

    # 全局检测一次 nginx 配置状态
    local _stream_nginx_ok=0
    if nginx_test &>/dev/null; then
        _stream_nginx_ok=1
    fi

    local _stream_found=0
    local _stream_cfile

    for _stream_cfile in "${_stream_sd}"/*.conf; do
        [[ -f "$_stream_cfile" ]] || continue
        _stream_found=1

        local _stream_cname _stream_cport _stream_cbackend _stream_cproto _stream_ccreated
        _stream_cname="$(basename "$_stream_cfile" .conf)"
        _stream_cport="$(sed -n 's/.*listen\s\+\([0-9]*\).*/\1/p' "$_stream_cfile" | head -1 || echo "?")"
        _stream_cproto="$(sed -n 's/.*listen\s\+[0-9]\+\s\+\([a-z]*\).*/\1/p' "$_stream_cfile" | head -1 || echo "tcp")"
        _stream_cbackend="$(sed -n 's/.*proxy_pass\s\+\([^;]*\).*/\1/p' "$_stream_cfile" | head -1 || echo "?")"
        _stream_ccreated="$(read_meta "$_stream_cfile" "created")"

        local _stream_status_marker
        if [[ "$_stream_nginx_ok" -eq 1 ]]; then
            _stream_status_marker="${COLOR_GREEN}[正常]${COLOR_RESET}"
        else
            _stream_status_marker="${COLOR_RED}[异常]${COLOR_RESET}"
        fi

        echo -e "  ${_stream_status_marker} ${COLOR_BOLD}${_stream_cname}${COLOR_RESET}"
        echo "    端口: ${_stream_cport}/${_stream_cproto}"
        echo "    后端: ${_stream_cbackend}"
        [[ -n "$_stream_ccreated" ]] && echo "    创建: ${_stream_ccreated}"
        echo
    done

    if [[ "$_stream_found" -eq 0 ]]; then
        log_info "暂无 stream 转发配置"
    fi
}

# -----------------------------
# _stream_add - 添加 stream 转发配置
# -----------------------------
_stream_add() {
    local _stream_name=""
    local _stream_listen=""
    local _stream_to=""
    local _stream_proto=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --listen)
                require_arg "--listen 的值" "${2:-}"
                _stream_listen="$2"
                shift 2
                ;;
            --to)
                require_arg "--to 的值" "${2:-}"
                _stream_to="$2"
                shift 2
                ;;
            --proto)
                require_arg "--proto 的值" "${2:-}"
                _stream_proto="$2"
                shift 2
                ;;
            -*)
                die "未知选项: $1"
                ;;
            *)
                if [[ -z "$_stream_name" ]]; then
                    _stream_name="$1"
                else
                    die "多余的参数: $1"
                fi
                shift
                ;;
        esac
    done

    require_arg "转发名称" "$_stream_name"

    # 验证名称
    if ! is_valid_site_name "$_stream_name"; then
        die "无效的转发名称: ${_stream_name} (只允许字母数字、连字符、下划线、点)"
    fi

    # 应用预设快捷方式
    local _stream_preset_listen _stream_preset_proto
    _stream_preset_listen="$(_stream_preset_port "$_stream_name")"
    _stream_preset_proto="$(_stream_preset_proto "$_stream_name")"

    if [[ -n "$_stream_preset_listen" ]]; then
        # 预设模式: listen 和 proto 有默认值
        [[ -z "$_stream_listen" ]] && _stream_listen="$_stream_preset_listen"
        [[ -z "$_stream_proto" ]] && _stream_proto="$_stream_preset_proto"
    fi

    # 非预设名称 (custom) 必须显式指定
    if [[ -z "$_stream_preset_listen" ]]; then
        if [[ -z "$_stream_listen" ]]; then
            die "非预设转发必须指定 --listen 端口"
        fi
    fi

    # 设置默认协议
    [[ -z "$_stream_proto" ]] && _stream_proto="tcp"

    # 验证参数
    require_arg "--to 后端地址" "$_stream_to"
    validate_port "$_stream_listen" "监听端口"
    validate_protocol "$_stream_proto"
    validate_backend "$_stream_to"

    local _stream_stream_d
    _stream_stream_d="$(get_nginx_stream_d)"
    local _stream_config_file="${_stream_stream_d}/${_stream_name}.conf"

    # 检查配置是否已存在
    if [[ -f "$_stream_config_file" ]]; then
        die "stream 转发配置已存在: ${_stream_config_file}。如需修改请先删除"
    fi

    # 确保 stream.d 目录和 nginx.conf stream 块就绪
    _ensure_stream_dir

    acquire_lock

    # 备份
    backup_nginx_config "pre-stream-add-${_stream_name}" > /dev/null

    # 预检: nginx -t
    log_step "预检: 验证当前 nginx 配置..."
    if ! nginx_test; then
        die "当前 nginx 配置存在问题，无法添加 stream 转发。请先修复配置"
    fi

    # 端口冲突检测
    _check_port_available "$_stream_listen"

    # 生成配置内容
    local _stream_ts
    _stream_ts="$(date '+%Y-%m-%d %H:%M:%S')"

    local _stream_config_content="# nginx-tools:type=stream
# nginx-tools:name=${_stream_name}
# nginx-tools:created=${_stream_ts}

server {
    listen ${_stream_listen} ${_stream_proto};
    proxy_pass ${_stream_to};
    proxy_connect_timeout 10s;
    proxy_timeout 300s;
}
"

    log_step "创建 stream 转发: ${_stream_name} (${_stream_listen}/${_stream_proto} -> ${_stream_to})..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将创建配置: ${_stream_config_file}"
        echo "$_stream_config_content"
        return 0
    fi

    # 写入配置文件
    echo "$_stream_config_content" > "$_stream_config_file" || die "创建配置文件失败: ${_stream_config_file}"

    # 后检: nginx -t
    log_step "后检: 验证 nginx 配置..."
    if ! nginx_test; then
        log_error "添加 stream 转发后 nginx 配置测试失败，正在回滚..."
        rm -f "$_stream_config_file" 2>/dev/null
        log_warn "已移除配置文件: ${_stream_config_file}"
        die "nginx 配置验证失败，已回滚。请检查配置"
    fi

    log_ok "stream 转发已创建: ${_stream_config_file}"
    echo
    log_info "监听: ${_stream_listen}/${_stream_proto}"
    log_info "后端: ${_stream_to}"
}

# -----------------------------
# _stream_remove - 删除 stream 转发配置
# -----------------------------
_stream_remove() {
    local _stream_name="$1"
    require_arg "转发名称" "$_stream_name"

    local _stream_stream_d
    _stream_stream_d="$(get_nginx_stream_d)"
    local _stream_config_file="${_stream_stream_d}/${_stream_name}.conf"

    if [[ ! -f "$_stream_config_file" ]]; then
        die "stream 转发配置不存在: ${_stream_config_file}"
    fi

    # 确认删除
    if ! confirm "确认删除 stream 转发 ${_stream_name}？此操作不可逆" "n"; then
        log_info "已取消删除"
        return 0
    fi

    acquire_lock

    # 备份
    log_step "备份 stream 转发配置..."
    backup_nginx_config "pre-stream-remove-${_stream_name}" > /dev/null

    log_step "删除 stream 转发: ${_stream_name}..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将删除配置文件: ${_stream_config_file}"
        return 0
    fi

    rm -f "$_stream_config_file" || die "删除配置文件失败: ${_stream_config_file}"
    log_ok "stream 转发配置已删除: ${_stream_config_file}"

    # 验证删除后 nginx 配置仍有效
    log_step "验证 nginx 配置..."
    if nginx_test; then
        log_ok "nginx 配置验证通过"
    else
        log_warn "nginx 配置验证失败，请手动检查"
    fi
}

# -----------------------------
# 主入口 (由 nginx-tools 调用)
# -----------------------------
_stream_main() {
    local _stream_subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_stream_subcmd" in
        add)
            _stream_add "$@"
            ;;
        remove|rm|del)
            _stream_remove "$@"
            ;;
        list|ls)
            _stream_list "$@"
            ;;
        help|--help|-h)
            _stream_help
            ;;
        *)
            log_error "未知子命令: ${_stream_subcmd}"
            _stream_help
            return 1
            ;;
    esac
}
