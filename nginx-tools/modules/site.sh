#!/usr/bin/env bash
# =====================================================
# modules/site.sh - 站点管理模块
# =====================================================
# 子命令: add, delete, enable, disable, list, show, help
# 用法:   nginx-tools site <subcommand> [args...]
# =====================================================

# -----------------------------
# 帮助信息
# -----------------------------
_site_help() {
    cat <<EOF
nginx-tools site - 站点管理 (nginx 虚拟主机)

用法:
  nginx-tools site <subcommand> [args...]

可用子命令:
  add <domain> [--template <name>]   添加站点配置 (默认模板: static)
  delete <domain>                    删除站点配置 (需确认)
  enable <domain>                    启用站点 (创建符号链接)
  disable <domain>                   禁用站点 (移除符号链接)
  list                               列出所有站点及状态
  show <domain>                      显示站点配置内容
  help                               显示此帮助信息

示例:
  nginx-tools site add example.com
  nginx-tools site add blog.example.com --template static
  nginx-tools site enable example.com
  nginx-tools site list
  nginx-tools site show example.com
  nginx-tools site delete example.com
EOF
}

# -----------------------------
# _site_list - 列出所有站点
# -----------------------------
_site_list() {
    local sites_available sites_enabled
    sites_available="$(get_sites_available)"
    sites_enabled="$(get_sites_enabled)"

    ensure_sites_enabled

    print_banner "站点列表"

    local found=0
    local site_file enabled_marker

    for site_file in "${sites_available}"/*; do
        [[ -f "$site_file" ]] || continue
        found=1
        local name
        name="$(basename "$site_file")"

        if [[ -L "${sites_enabled}/${name}" ]]; then
            enabled_marker="${COLOR_GREEN}[已启用]${COLOR_RESET}"
        else
            enabled_marker="${COLOR_YELLOW}[已禁用]${COLOR_RESET}"
        fi

        local template
        template="$(read_meta "$site_file" "template")"
        [[ -n "$template" ]] && template=" (${template})"

        echo -e "  ${enabled_marker} ${name}${template}"
    done

    if [[ "$found" -eq 0 ]]; then
        log_info "暂无站点配置"
    fi
    echo
}

# -----------------------------
# _site_show - 显示站点配置
# -----------------------------
_site_show() {
    local domain="$1"
    require_arg "域名" "$domain"
    validate_site_name "$domain"

    local sites_available
    sites_available="$(get_sites_available)"
    local config_file="${sites_available}/${domain}"

    if [[ ! -f "$config_file" ]]; then
        die "站点配置不存在: ${config_file}"
    fi

    print_banner "站点配置: ${domain}"

    local created template
    created="$(read_meta "$config_file" "created")"
    template="$(read_meta "$config_file" "template")"

    echo "  文件: ${config_file}"
    [[ -n "$created" ]] && echo "  创建时间: ${created}"
    [[ -n "$template" ]] && echo "  模板: ${template}"
    echo

    print_separator "-"
    cat "$config_file"
    print_separator "-"
}

# -----------------------------
# _site_enable - 启用站点
# -----------------------------
_site_enable() {
    local domain="$1"
    require_arg "域名" "$domain"
    validate_site_name "$domain"

    local sites_available sites_enabled
    sites_available="$(get_sites_available)"
    sites_enabled="$(get_sites_enabled)"

    ensure_sites_enabled

    local config_file="${sites_available}/${domain}"
    local link_file="${sites_enabled}/${domain}"

    # 检查配置文件是否存在
    if [[ ! -f "$config_file" ]]; then
        die "站点配置不存在: ${config_file}"
    fi

    # 幂等: 已启用则跳过
    if [[ -L "$link_file" ]]; then
        local current_target
        current_target="$(readlink "$link_file" 2>/dev/null)" || true
        if [[ "$current_target" == "../sites-available/${domain}" ]] || \
           [[ "$current_target" == "${config_file}" ]]; then
            log_info "站点 ${domain} 已处于启用状态，无需操作"
            return 0
        fi
    fi

    acquire_lock

    # 备份
    backup_site_config "$domain" > /dev/null

    # 预检: nginx -t (当前配置必须有效才能继续)
    log_step "预检: 验证当前 nginx 配置..."
    if ! nginx_test; then
        die "当前 nginx 配置存在问题，无法启用站点。请先修复配置"
    fi

    # 原子符号链接: ln -sf + mv 模式
    log_step "启用站点: ${domain}..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将创建符号链接: ${link_file} -> ../sites-available/${domain}"
        return 0
    fi

    ln -sf "../sites-available/${domain}" "${link_file}.tmp" || {
        rm -f "${link_file}.tmp" 2>/dev/null
        die "创建临时符号链接失败"
    }
    mv -f "${link_file}.tmp" "${link_file}" || {
        rm -f "${link_file}.tmp" 2>/dev/null
        die "移动符号链接失败"
    }

    # 后检: nginx -t (新配置必须有效)
    log_step "后检: 验证 nginx 配置..."
    if ! nginx_test; then
        log_error "启用站点后 nginx 配置测试失败，正在回滚..."
        rm -f "${link_file}" 2>/dev/null
        log_warn "已移除符号链接: ${link_file}"
        die "nginx 配置验证失败，已回滚。请检查站点配置: ${config_file}"
    fi

    log_ok "站点 ${domain} 已启用"
}

# -----------------------------
# _site_disable - 禁用站点
# -----------------------------
_site_disable() {
    local domain="$1"
    require_arg "域名" "$domain"
    validate_site_name "$domain"

    local sites_enabled
    sites_enabled="$(get_sites_enabled)"

    ensure_sites_enabled

    local link_file="${sites_enabled}/${domain}"

    # 幂等: 未启用则跳过
    if [[ ! -L "$link_file" ]]; then
        log_info "站点 ${domain} 已处于禁用状态，无需操作"
        return 0
    fi

    acquire_lock

    # 备份
    backup_site_config "$domain" > /dev/null

    log_step "禁用站点: ${domain}..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将移除符号链接: ${link_file}"
        return 0
    fi

    rm -f "${link_file}" || die "移除符号链接失败: ${link_file}"

    log_ok "站点 ${domain} 已禁用"
}

# -----------------------------
# _site_add - 添加站点
# -----------------------------
_site_add() {
    local domain=""
    local template="static"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --template)
                require_arg "--template 的值" "${2:-}"
                template="$2"
                shift 2
                ;;
            -*)
                die "未知选项: $1"
                ;;
            *)
                if [[ -z "$domain" ]]; then
                    domain="$1"
                else
                    die "多余的参数: $1"
                fi
                shift
                ;;
        esac
    done

    require_arg "域名" "$domain"
    validate_domain "$domain"
    validate_site_name "$domain"

    local sites_available sites_enabled
    sites_available="$(get_sites_available)"
    sites_enabled="$(get_sites_enabled)"

    ensure_sites_enabled

    local config_file="${sites_available}/${domain}"

    # 检查是否已存在
    if [[ -f "$config_file" ]]; then
        die "站点配置已存在: ${config_file}。如需修改请先删除"
    fi

    acquire_lock

    # 备份 (即使新建也备份当前环境)
    backup_nginx_config "pre-add-${domain}" > /dev/null

    log_step "创建站点配置: ${domain} (模板: ${template})..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将创建站点配置: ${config_file}"
        return 0
    fi

    # 生成配置内容
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    local config_content
    case "$template" in
        static)
            config_content="# nginx-tools:created=${ts}
# nginx-tools:template=${template}
# nginx-tools:domain=${domain}

server {
    listen 80;
    listen [::]:80;

    server_name ${domain};

    root /var/www/${domain};
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
"
            ;;
        *)
            die "未知模板: ${template}。可用模板: static"
            ;;
    esac

    # 写入配置文件
    echo "$config_content" > "$config_file" || die "创建配置文件失败: ${config_file}"
    log_ok "站点配置已创建: ${config_file}"

    # 提示启用
    echo
    log_info "如需启用站点，请执行:"
    echo "  nginx-tools site enable ${domain}"
}

# -----------------------------
# _site_delete - 删除站点
# -----------------------------
_site_delete() {
    local domain="$1"
    require_arg "域名" "$domain"
    validate_site_name "$domain"

    local sites_available sites_enabled
    sites_available="$(get_sites_available)"
    sites_enabled="$(get_sites_enabled)"

    local config_file="${sites_available}/${domain}"
    local link_file="${sites_enabled}/${domain}"

    if [[ ! -f "$config_file" ]]; then
        die "站点配置不存在: ${config_file}"
    fi

    # 确认删除
    if ! confirm "确认删除站点 ${domain}？此操作不可逆" "n"; then
        log_info "已取消删除"
        return 0
    fi

    acquire_lock

    # 先备份
    log_step "备份站点配置..."
    backup_site_config "$domain" > /dev/null

    # 如果已启用，先禁用
    if [[ -L "$link_file" ]]; then
        log_step "站点已启用，先禁用..."
        if is_dry_run; then
            log_info "[DRY-RUN] 将移除符号链接: ${link_file}"
        else
            rm -f "${link_file}" || die "移除符号链接失败: ${link_file}"
            log_ok "符号链接已移除: ${link_file}"
        fi
    fi

    # 删除配置文件
    log_step "删除站点配置: ${domain}..."
    if is_dry_run; then
        log_info "[DRY-RUN] 将删除配置文件: ${config_file}"
        return 0
    fi

    rm -f "${config_file}" || die "删除配置文件失败: ${config_file}"
    log_ok "站点配置已删除: ${config_file}"

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
_site_main() {
    local subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$subcmd" in
        add)
            _site_add "$@"
            ;;
        delete|del|rm)
            _site_delete "$@"
            ;;
        enable|en|on)
            _site_enable "$@"
            ;;
        disable|dis|off)
            _site_disable "$@"
            ;;
        list|ls)
            _site_list "$@"
            ;;
        show|info)
            _site_show "$@"
            ;;
        help|--help|-h)
            _site_help
            ;;
        *)
            log_error "未知子命令: ${subcmd}"
            _site_help
            return 1
            ;;
    esac
}
