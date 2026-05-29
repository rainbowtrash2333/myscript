#!/usr/bin/env bash
# =====================================================
# modules/proxy.sh - 反向代理管理模块
# =====================================================
# 子命令: add, remove, list, help
# 用法:   nginx-tools proxy <subcommand> [args...]
# =====================================================

# -----------------------------
# 帮助信息
# -----------------------------
_proxy_help() {
    cat <<EOF
nginx-tools proxy - 反向代理管理

用法:
  nginx-tools proxy <subcommand> [args...]

可用子命令:
  add <domain> --upstream <IP:PORT> [--ssl] [--websocket] [--custom-upstream <name>]
      添加反向代理配置
  remove <domain>
      删除反向代理配置 (需确认)
  list
      列出所有反向代理配置
  help
      显示此帮助信息

选项:
  --upstream <IP:PORT>       后端地址 (必填)
  --ssl                      启用 HTTPS (生成 80→443 重定向 + 443 ssl server block)
  --websocket                启用 WebSocket 代理头
  --custom-upstream <name>   使用命名 upstream 块而非内联 proxy_pass

示例:
  nginx-tools proxy add app.example.com --upstream 127.0.0.1:3000
  nginx-tools proxy add ws.example.com --upstream 127.0.0.1:3001 --websocket
  nginx-tools proxy add secure.example.com --upstream 127.0.0.1:8080 --ssl
  nginx-tools proxy add api.example.com --upstream 127.0.0.1:4000 --custom-upstream api_backend
  nginx-tools proxy remove app.example.com
  nginx-tools proxy list
EOF
}

# -----------------------------
# _proxy_list - 列出所有反向代理
# -----------------------------
_proxy_list() {
    local _proxy_sites_available _proxy_sites_enabled
    _proxy_sites_available="$(get_sites_available)"
    _proxy_sites_enabled="$(get_sites_enabled)"

    ensure_sites_enabled

    print_banner "反向代理列表"

    local _proxy_found=0
    local _proxy_site_file _proxy_enabled_marker _proxy_name
    local _proxy_type _proxy_upstream _proxy_created

    for _proxy_site_file in "${_proxy_sites_available}"/*; do
        [[ -f "$_proxy_site_file" ]] || continue

        _proxy_type="$(read_meta "$_proxy_site_file" "type")"
        [[ "$_proxy_type" == "reverse-proxy" ]] || continue

        _proxy_found=1
        _proxy_name="$(basename "$_proxy_site_file")"

        if [[ -L "${_proxy_sites_enabled}/${_proxy_name}" ]]; then
            _proxy_enabled_marker="${COLOR_GREEN}[已启用]${COLOR_RESET}"
        else
            _proxy_enabled_marker="${COLOR_YELLOW}[已禁用]${COLOR_RESET}"
        fi

        _proxy_upstream="$(read_meta "$_proxy_site_file" "upstream")"
        _proxy_created="$(read_meta "$_proxy_site_file" "created")"

        echo -e "  ${_proxy_enabled_marker} ${_proxy_name}"
        [[ -n "$_proxy_upstream" ]] && echo "      upstream: ${_proxy_upstream}"
        [[ -n "$_proxy_created" ]] && echo "      创建时间: ${_proxy_created}"
    done

    if [[ "$_proxy_found" -eq 0 ]]; then
        log_info "暂无反向代理配置"
    fi
    echo
}

# -----------------------------
# _proxy_add - 添加反向代理
# -----------------------------
_proxy_add() {
    local _proxy_domain=""
    local _proxy_upstream=""
    local _proxy_ssl=0
    local _proxy_websocket=0
    local _proxy_custom_upstream=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upstream)
                require_arg "--upstream 的值" "${2:-}"
                _proxy_upstream="$2"
                shift 2
                ;;
            --ssl)
                _proxy_ssl=1
                shift
                ;;
            --websocket)
                _proxy_websocket=1
                shift
                ;;
            --custom-upstream)
                require_arg "--custom-upstream 的值" "${2:-}"
                _proxy_custom_upstream="$2"
                shift 2
                ;;
            -*)
                die "未知选项: $1"
                ;;
            *)
                if [[ -z "$_proxy_domain" ]]; then
                    _proxy_domain="$1"
                else
                    die "多余的参数: $1"
                fi
                shift
                ;;
        esac
    done

    # 验证必填参数
    require_arg "域名" "$_proxy_domain"
    require_arg "--upstream" "$_proxy_upstream"
    validate_domain "$_proxy_domain"
    validate_site_name "$_proxy_domain"

    # 验证 upstream 格式 (IP:PORT)
    if ! is_valid_backend "$_proxy_upstream"; then
        die "无效的后端地址: ${_proxy_upstream} (格式: IP:PORT)"
    fi

    # 验证 custom-upstream 名称
    if [[ -n "$_proxy_custom_upstream" ]]; then
        validate_upstream_name "$_proxy_custom_upstream"
    fi

    local _proxy_sites_available _proxy_sites_enabled
    _proxy_sites_available="$(get_sites_available)"
    _proxy_sites_enabled="$(get_sites_enabled)"

    ensure_sites_enabled

    local _proxy_config_file="${_proxy_sites_available}/${_proxy_domain}"

    # 检查是否已存在
    if [[ -f "$_proxy_config_file" ]]; then
        die "站点配置已存在: ${_proxy_config_file}。如需修改请先删除"
    fi

    acquire_lock

    # 备份当前环境
    backup_nginx_config "pre-proxy-add-${_proxy_domain}" > /dev/null

    log_step "创建反向代理配置: ${_proxy_domain} -> ${_proxy_upstream}..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将创建反向代理配置: ${_proxy_config_file}"
        return 0
    fi

    # 生成配置内容
    local _proxy_ts
    _proxy_ts="$(date '+%Y-%m-%d %H:%M:%S')"

    local _proxy_proxy_pass=""
    local _proxy_upstream_block=""

    # 构造 proxy_pass 或 upstream 引用
    if [[ -n "$_proxy_custom_upstream" ]]; then
        _proxy_proxy_pass="proxy_pass http://${_proxy_custom_upstream};"
        _proxy_upstream_block="
upstream ${_proxy_custom_upstream} {
    server ${_proxy_upstream};
}
"
    else
        _proxy_proxy_pass="proxy_pass http://${_proxy_upstream};"
    fi

    # WebSocket 头
    local _proxy_ws_headers=""
    if [[ "$_proxy_websocket" -eq 1 ]]; then
        _proxy_ws_headers="
    # WebSocket 支持
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \"upgrade\";"
    else
        _proxy_ws_headers="
    proxy_http_version 1.1;"
    fi

    # 构造 location 块
    local _proxy_location="
    location / {
        ${_proxy_proxy_pass}
        ${_proxy_ws_headers}

        # 真实 IP 传递
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 代理超时
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        # 请求体大小
        client_max_body_size 100M;
    }"

    # 构造 server 块
    local _proxy_server_blocks=""

    if [[ "$_proxy_ssl" -eq 1 ]]; then
        # HTTP -> HTTPS 重定向
        _proxy_server_blocks="server {
    listen 80;
    listen [::]:80;

    server_name ${_proxy_domain};

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name ${_proxy_domain};

    ssl_certificate     /etc/nginx/ssl/${_proxy_domain}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${_proxy_domain}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
${_proxy_location}
}"
    else
        # 仅 HTTP
        _proxy_server_blocks="server {
    listen 80;
    listen [::]:80;

    server_name ${_proxy_domain};
${_proxy_location}
}"
    fi

    # 完整配置
    local _proxy_config_content="# nginx-tools:type=reverse-proxy
# nginx-tools:upstream=${_proxy_upstream}
# nginx-tools:created=${_proxy_ts}
# nginx-tools:domain=${_proxy_domain}
# nginx-tools:ssl=${_proxy_ssl}
# nginx-tools:websocket=${_proxy_websocket}
${_proxy_upstream_block}
${_proxy_server_blocks}
"

    # 写入配置文件
    echo "$_proxy_config_content" > "$_proxy_config_file" || die "创建配置文件失败: ${_proxy_config_file}"
    log_ok "反向代理配置已创建: ${_proxy_config_file}"

    # nginx -t 验证
    log_step "验证 nginx 配置..."
    if ! nginx_test; then
        log_error "nginx 配置验证失败，正在回滚..."
        rm -f "$_proxy_config_file" 2>/dev/null
        log_warn "已删除配置文件: ${_proxy_config_file}"
        die "nginx 配置验证失败，已回滚。请检查配置: ${_proxy_config_file}"
    fi

    # 自动启用
    local _proxy_link_file="${_proxy_sites_enabled}/${_proxy_domain}"
    log_step "启用反向代理: ${_proxy_domain}..."
    ln -sf "../sites-available/${_proxy_domain}" "${_proxy_link_file}.tmp" || {
        rm -f "${_proxy_link_file}.tmp" 2>/dev/null
        die "创建临时符号链接失败"
    }
    mv -f "${_proxy_link_file}.tmp" "${_proxy_link_file}" || {
        rm -f "${_proxy_link_file}.tmp" 2>/dev/null
        die "移动符号链接失败"
    }

    # 启用后再次验证
    log_step "后检: 验证 nginx 配置..."
    if ! nginx_test; then
        log_error "启用反向代理后 nginx 配置测试失败，正在回滚..."
        rm -f "${_proxy_link_file}" 2>/dev/null
        rm -f "$_proxy_config_file" 2>/dev/null
        log_warn "已移除符号链接和配置文件"
        die "nginx 配置验证失败，已回滚。请检查配置: ${_proxy_config_file}"
    fi

    log_ok "反向代理 ${_proxy_domain} 已启用"

    # 显示摘要
    echo
    print_separator "-"
    echo "  域名:     ${_proxy_domain}"
    echo "  upstream: ${_proxy_upstream}"
    [[ -n "$_proxy_custom_upstream" ]] && echo "  upstream 块: ${_proxy_custom_upstream}"
    [[ "$_proxy_ssl" -eq 1 ]] && echo "  SSL:      已启用"
    [[ "$_proxy_websocket" -eq 1 ]] && echo "  WebSocket: 已启用"
    print_separator "-"
}

# -----------------------------
# _proxy_remove - 删除反向代理
# -----------------------------
_proxy_remove() {
    local _proxy_domain="$1"
    require_arg "域名" "$_proxy_domain"
    validate_site_name "$_proxy_domain"

    local _proxy_sites_available _proxy_sites_enabled
    _proxy_sites_available="$(get_sites_available)"
    _proxy_sites_enabled="$(get_sites_enabled)"

    local _proxy_config_file="${_proxy_sites_available}/${_proxy_domain}"
    local _proxy_link_file="${_proxy_sites_enabled}/${_proxy_domain}"

    if [[ ! -f "$_proxy_config_file" ]]; then
        die "站点配置不存在: ${_proxy_config_file}"
    fi

    # 检查是否为反向代理配置
    local _proxy_type
    _proxy_type="$(read_meta "$_proxy_config_file" "type")"
    if [[ "$_proxy_type" != "reverse-proxy" ]]; then
        die "${_proxy_domain} 不是反向代理配置 (类型: ${_proxy_type:-未知})。如需删除请使用 nginx-tools site delete"
    fi

    # 确认删除
    if ! confirm "确认删除反向代理 ${_proxy_domain}？此操作不可逆" "n"; then
        log_info "已取消删除"
        return 0
    fi

    acquire_lock

    # 先备份
    log_step "备份反向代理配置..."
    backup_site_config "$_proxy_domain" > /dev/null

    # 如果已启用，先禁用
    if [[ -L "$_proxy_link_file" ]]; then
        log_step "反向代理已启用，先禁用..."
        if is_dry_run; then
            log_info "[DRY-RUN] 将移除符号链接: ${_proxy_link_file}"
        else
            rm -f "${_proxy_link_file}" || die "移除符号链接失败: ${_proxy_link_file}"
            log_ok "符号链接已移除: ${_proxy_link_file}"
        fi
    fi

    # 删除配置文件
    log_step "删除反向代理配置: ${_proxy_domain}..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将删除配置文件: ${_proxy_config_file}"
        return 0
    fi

    rm -f "${_proxy_config_file}" || die "删除配置文件失败: ${_proxy_config_file}"
    log_ok "反向代理配置已删除: ${_proxy_config_file}"

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
_proxy_main() {
    local _proxy_subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_proxy_subcmd" in
        add)
            _proxy_add "$@"
            ;;
        remove|rm|del|delete)
            _proxy_remove "$@"
            ;;
        list|ls)
            _proxy_list "$@"
            ;;
        help|--help|-h)
            _proxy_help
            ;;
        *)
            log_error "未知子命令: ${_proxy_subcmd}"
            _proxy_help
            return 1
            ;;
    esac
}
